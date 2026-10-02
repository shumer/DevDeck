param(
    [ValidateSet('win-arm64', 'win-x64')][string]$Runtime = 'win-arm64',
    [string]$Dotnet = 'dotnet',
    [string]$Output = (Join-Path $env:LOCALAPPDATA 'DevDeck/Development/app'),
    [switch]$Launch,
    [string]$Settings,
    [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Version = '0.0.0-windows-dev'
)
$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'DevDeck.Windows.App/DevDeck.Windows.App.csproj'
# WPF native libraries must be staged on a Windows filesystem, not the case-sensitive WSL UNC checkout.
$resolvedOutput = [System.IO.Path]::GetFullPath($Output)
if ($resolvedOutput.StartsWith('\\')) { throw 'Choose a local Windows output directory for the executable.' }
& $Dotnet publish $project -c Release -r $Runtime --self-contained true -p:Version=$Version -o $resolvedOutput
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
foreach ($script in @('install.ps1', 'uninstall.ps1', 'rollback.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script) -Destination $resolvedOutput -Force }
$files = @(Get-ChildItem -LiteralPath $resolvedOutput -File -Recurse | Where-Object { $_.Name -ne 'windows-package.json' } | ForEach-Object {
    @{ path = [System.IO.Path]::GetRelativePath($resolvedOutput, $_.FullName); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
})
@{ schemaVersion = 1; platform = 'windows'; runtime = $Runtime; version = $Version; releaseQualified = $false; files = $files } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $resolvedOutput 'windows-package.json') -Encoding utf8
if ($Launch) {
    $start = [System.Diagnostics.ProcessStartInfo]::new((Join-Path $resolvedOutput 'DevDeck.Windows.exe'))
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    if ($Settings) { $start.ArgumentList.Add('--settings'); $start.ArgumentList.Add([System.IO.Path]::GetFullPath($Settings)) }
    [System.Diagnostics.Process]::Start($start) | Out-Null
}
