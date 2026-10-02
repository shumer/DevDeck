param(
    [string]$Package = $PSScriptRoot,
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'DevDeck'),
    [switch]$NoShortcuts,
    [switch]$Launch,
    [string]$StartupDirectory = ([Environment]::GetFolderPath('Startup'))
)
$ErrorActionPreference = 'Stop'
$sourceRoot = [System.IO.Path]::GetFullPath($Package).TrimEnd('\')
$targetRoot = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
if ($targetRoot.StartsWith('\\') -or $targetRoot -eq [System.IO.Path]::GetPathRoot($targetRoot).TrimEnd('\')) { throw 'Choose a local per-user installation directory.' }
$manifestFile = Join-Path $sourceRoot 'windows-package.json'
$manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.platform -ne 'windows' -or $manifest.version -notmatch '^[A-Za-z0-9._-]+$' -or $manifest.runtime -notin @('win-arm64', 'win-x64')) { throw 'Invalid Windows package manifest.' }
$native = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
if ($manifest.runtime -ne ('win-' + $native)) { throw 'Install the package matching this Windows architecture.' }
if (!($manifest.files | Where-Object { $_.path -eq 'DevDeck.Windows.exe' })) { throw 'The package has no Windows executable.' }
function Resolve-PackageFile([string]$base, [string]$relative) {
    if ([System.IO.Path]::IsPathRooted($relative)) { throw 'Manifest contains an absolute path.' }
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $base $relative))
    if (!$resolved.StartsWith($base + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest path leaves the package directory.' }
    return $resolved
}
function Assert-Package([string]$base) {
    foreach ($entry in $manifest.files) {
        $file = Resolve-PackageFile $base $entry.path
        if (!(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) { throw 'Package file is missing or is a reparse point.' }
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.sha256) { throw 'Package checksum does not match.' }
    }
}
Assert-Package $sourceRoot
$fingerprint = (Get-FileHash -LiteralPath $manifestFile -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
$versions = Join-Path $targetRoot 'Versions'
New-Item -ItemType Directory -Path $versions -Force | Out-Null
foreach ($directory in @($targetRoot, $versions)) {
    if ((Get-Item -LiteralPath $directory).Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) { throw 'Installation directories must not be reparse points.' }
}
$destination = [System.IO.Path]::GetFullPath((Join-Path $versions ($manifest.version + '-' + $manifest.runtime + '-' + $fingerprint)))
if (!$destination.StartsWith($versions + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Installation target leaves Versions.' }
$completion = Join-Path $destination '.devdeck-installed'
if (Test-Path -LiteralPath $completion) { Assert-Package $destination }
else {
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    if ((Get-Item -LiteralPath $destination).Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) { throw 'Installation target must not be a reparse point.' }
    foreach ($entry in $manifest.files) {
        $outputFile = Resolve-PackageFile $destination $entry.path
        New-Item -ItemType Directory -Path (Split-Path $outputFile) -Force | Out-Null
        Copy-Item -LiteralPath (Resolve-PackageFile $sourceRoot $entry.path) -Destination $outputFile -Force
    }
    Copy-Item -LiteralPath $manifestFile -Destination (Join-Path $destination 'windows-package.json') -Force
    Assert-Package $destination
    Set-Content -LiteralPath $completion -Value 'DevDeck Windows package schema 1'
}
$currentPath = Join-Path $targetRoot 'current-install.json'
$oldState = if (Test-Path -LiteralPath $currentPath) { Get-Content -LiteralPath $currentPath -Raw | ConvertFrom-Json } else { $null }
$previous = if ($oldState -and $oldState.path -eq $destination) { $oldState.previous } elseif ($oldState) { $oldState.path } else { $null }
if ($previous) {
    if (![System.IO.Path]::IsPathRooted($previous)) { throw 'Previous install path must be absolute.' }
    $previous = [System.IO.Path]::GetFullPath($previous)
}
if ($previous -and !$previous.StartsWith($versions + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Previous install path is outside Versions.' }
$state = @{ schemaVersion = 1; platform = 'windows'; path = $destination; previous = $previous; version = $manifest.version }
$temporary = $currentPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
$state | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding utf8
if (Test-Path -LiteralPath $currentPath) { [System.IO.File]::Replace($temporary, $currentPath, $currentPath + '.bak') }
else { [System.IO.File]::Move($temporary, $currentPath) }
Set-Content -LiteralPath (Join-Path $targetRoot '.devdeck-install-root') -Value 'DevDeck Windows package schema 1'
$executable = Join-Path $destination 'DevDeck.Windows.exe'
# Retarget only pre-existing, explicitly enabled DevDeck startup entries from this installation.
# Installation never enables startup by itself. Configuration arguments are preserved verbatim.
if (Test-Path -LiteralPath $StartupDirectory -PathType Container) {
    $startupShell = New-Object -ComObject WScript.Shell
    foreach ($file in Get-ChildItem -LiteralPath $StartupDirectory -Filter 'DevDeck-*.lnk' -File) {
        if ($file.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) { continue }
        $entry = $startupShell.CreateShortcut($file.FullName)
        if ($entry.Description -eq 'DevDeck Windows startup schema 1' -and $entry.TargetPath.StartsWith($versions + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $entry.TargetPath = $executable; $entry.WorkingDirectory = $destination; $entry.Save()
        }
    }
}
if (!$NoShortcuts) {
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\DevDeck.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $executable; $shortcut.WorkingDirectory = $destination; $shortcut.Description = 'DevDeck desktop widgets'; $shortcut.Save()
}
if ($Launch) { Start-Process -FilePath $executable -WorkingDirectory $destination -WindowStyle Hidden | Out-Null }
Write-Output $executable
