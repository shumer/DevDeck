param(
    [string]$OutputDirectory = "dist"
)

$ErrorActionPreference = "Stop"
$repository = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$output = [System.IO.Path]::GetFullPath((Join-Path $repository $OutputDirectory))
if (-not $output.StartsWith($repository + [System.IO.Path]::DirectorySeparatorChar)) {
    throw "Output directory must stay inside the repository."
}
$candidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe")
)
$compiler = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { $compiler = $command.Source }
}
if (-not $compiler) {
    throw "Inno Setup 6 was not found. Install it with winget install JRSoftware.InnoSetup."
}
$version = (Get-Content -LiteralPath (Join-Path $repository "VERSION") -Raw).Trim()
if ($version -notmatch '^\d+\.\d+(\.\d+)?$') {
    throw "VERSION must contain a numeric release version."
}
$delivery = Join-Path $output "windows-x64"
& (Join-Path $PSScriptRoot "Build-WindowsShell.ps1") -OutputDirectory ([System.IO.Path]::GetRelativePath($repository, $delivery))
if (-not $?) { throw "Windows delivery build failed." }
$icon = Join-Path $repository "Windows\DevDeck.Shell\Resources\DevDeck.ico"
$fileEntries = Join-Path $output "installer-runtime-files.iss"
$entries = @(Get-ChildItem -LiteralPath $delivery -File | Where-Object {
    $_.Extension -eq ".dll" -or $_.Name -eq "DevDeckProcessHost.exe"
} | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    'Source: "{#DeliveryDirectory}\' + $_.Name + '"; DestDir: "{app}"; Flags: ignoreversion; Check: NeedsDeliveryFile(''' + $_.Name + ''', ''' + $hash + ''')'
})
# Loaded project hosts keep their runtime, so identical files must not be replaced.
Set-Content -LiteralPath $fileEntries -Value $entries -Encoding utf8
& $compiler "/DAppVersion=$version" "/DDeliveryDirectory=$delivery" "/DInstallerOutput=$output" "/DAppIcon=$icon" "/DRuntimeFileEntries=$fileEntries" (Join-Path $repository "Windows\Installer\DevDeck.iss")
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed with exit code $LASTEXITCODE." }
Get-Item -LiteralPath (Join-Path $output "DevDeck-Setup-$version.exe") | Select-Object Name, Length
