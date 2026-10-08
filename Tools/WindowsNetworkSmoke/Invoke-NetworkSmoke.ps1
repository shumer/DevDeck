$ErrorActionPreference = 'Stop'
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$smokePath = Join-Path $repoRoot '.build/out/Products/Debug-windows-x86_64/DevDeckNetworkSmoke.exe'
if (!(Test-Path -LiteralPath $smokePath)) { throw 'Build DevDeckNetworkSmoke first.' }
$credential = Read-Host 'GitHub token, hidden input' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential)
$process = [Diagnostics.Process]::new()
try {
    $process.StartInfo.FileName = $smokePath
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardInput = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.CreateNoWindow = $true
    [void]$process.Start()
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    $process.StandardInput.WriteLine((ConvertTo-Json -InputObject $plain -Compress))
    $process.StandardInput.Close()
    $plain = $null
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (!$process.WaitForExit(120000)) { $process.Kill(); throw 'Network smoke check timed out.' }
    Write-Output $stdout.GetAwaiter().GetResult()
    Write-Output $stderr.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) { throw 'Network smoke check failed.' }
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    $credential.Dispose()
    $plain = $null
    $process.Dispose()
}
