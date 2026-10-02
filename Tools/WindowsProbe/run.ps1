param(
    [string]$Distribution = 'Ubuntu-24.04',
    [string]$LinuxRoot = '/home/ashumenko/Projects/DevDeck',
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
dotnet build "$PSScriptRoot/WindowsProbe.csproj" --nologo
if ($LASTEXITCODE -ne 0) { throw 'Probe build failed.' }
$probeArgs = @('--distribution', $Distribution, '--worker', "$LinuxRoot/Tools/WindowsProbe/worker.py")
if ($SelfTest) {
    $probeArgs += @('--self-test', '--report', "$PSScriptRoot/../../.local_docs/windows-probe-results.json")
    & "$PSScriptRoot/bin/Debug/net8.0-windows/WindowsProbe.exe" @probeArgs
    if ($LASTEXITCODE -ne 0) { throw 'Probe self-test failed. See the JSON report.' }
} else {
    # This is the interactive tool the user is trying, so its card must be visible.
    Start-Process -FilePath "$PSScriptRoot/bin/Debug/net8.0-windows/WindowsProbe.exe" -ArgumentList $probeArgs
}
