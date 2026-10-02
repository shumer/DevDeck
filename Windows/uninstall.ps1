param([string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'DevDeck'), [string]$StartupDirectory = ([Environment]::GetFolderPath('Startup')))
$ErrorActionPreference = 'Stop'
$targetRoot = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$marker = Join-Path $targetRoot '.devdeck-install-root'
if ($targetRoot.StartsWith('\\') -or !(Test-Path -LiteralPath $marker) -or (Get-Content -LiteralPath $marker -Raw).Trim() -ne 'DevDeck Windows package schema 1') { throw 'Not an owned DevDeck Windows installation.' }
$versions = [System.IO.Path]::GetFullPath((Join-Path $targetRoot 'Versions'))
foreach ($process in Get-Process -Name 'DevDeck.Windows' -ErrorAction SilentlyContinue) {
    if ($process.Path -and $process.Path.StartsWith($versions + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Quit the installed DevDeck application before uninstalling its packages.' }
}
foreach ($directory in @($targetRoot, $versions)) {
    if ((Get-Item -LiteralPath $directory).Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) { throw 'Uninstall refuses reparse points.' }
}
$ownedTargets = @()
foreach ($directory in Get-ChildItem -LiteralPath $versions -Directory) {
    $resolved = [System.IO.Path]::GetFullPath($directory.FullName)
    if (!$resolved.StartsWith($versions + '\', [System.StringComparison]::OrdinalIgnoreCase) -or $directory.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) { throw 'Uninstall target leaves the owned Versions directory.' }
    $manifest = Join-Path $resolved 'windows-package.json'
    $completion = Join-Path $resolved '.devdeck-installed'
    if (!(Test-Path -LiteralPath $manifest) -or !(Test-Path -LiteralPath $completion)) { throw 'Uninstall found an incomplete or unowned directory; inspect it before removing it.' }
    $metadata = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($metadata.platform -ne 'windows' -or $metadata.schemaVersion -ne 1) { throw 'Uninstall found an unowned package.' }
    if (Get-ChildItem -LiteralPath $resolved -Recurse -Attributes ReparsePoint) { throw 'Uninstall refuses a package containing reparse points.' }
    $ownedTargets += $resolved
}
foreach ($resolved in $ownedTargets) { Remove-Item -LiteralPath $resolved -Recurse -Force }
if (Test-Path -LiteralPath $StartupDirectory -PathType Container) {
    $startupShell = New-Object -ComObject WScript.Shell
    foreach ($file in Get-ChildItem -LiteralPath $StartupDirectory -Filter 'DevDeck-*.lnk' -File) {
        if ($file.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) { continue }
        $entry = $startupShell.CreateShortcut($file.FullName)
        if ($entry.Description -eq 'DevDeck Windows startup schema 1' -and $entry.TargetPath.StartsWith($versions + '\', [System.StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $file.FullName }
    }
}
$shortcutPath = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\DevDeck.lnk'
if (Test-Path -LiteralPath $shortcutPath) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if ($shortcut.TargetPath.StartsWith($versions + '\', [System.StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $shortcutPath }
}
foreach ($name in @('current-install.json', 'current-install.json.bak', '.devdeck-install-root')) {
    $file = Join-Path $targetRoot $name; if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
}
Write-Output 'Windows application packages removed. Settings, credentials, WSL runtimes and projects are preserved.'
