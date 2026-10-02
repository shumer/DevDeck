param([string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'DevDeck'), [switch]$NoShortcuts, [string]$StartupDirectory = ([Environment]::GetFolderPath('Startup')))
$ErrorActionPreference = 'Stop'
$targetRoot = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$statePath = Join-Path $targetRoot 'current-install.json'
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$versions = [System.IO.Path]::GetFullPath((Join-Path $targetRoot 'Versions'))
if (!$state.previous -or ![System.IO.Path]::IsPathRooted($state.previous)) { throw 'No previous owned package is available.' }
$previous = [System.IO.Path]::GetFullPath($state.previous)
if (!$previous.StartsWith($versions + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Previous package leaves the owned Versions directory.' }
foreach ($directory in @($targetRoot, $versions, $previous)) {
    if (!(Test-Path -LiteralPath $directory -PathType Container) -or (Get-Item -LiteralPath $directory).Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) { throw 'Rollback refuses missing directories or reparse points.' }
}
$installer = Join-Path $previous 'install.ps1'
if (!(Test-Path -LiteralPath (Join-Path $previous '.devdeck-installed')) -or !(Test-Path -LiteralPath $installer)) { throw 'Previous package is incomplete.' }
& $installer -Package $previous -InstallRoot $targetRoot -NoShortcuts:$NoShortcuts -StartupDirectory $StartupDirectory
