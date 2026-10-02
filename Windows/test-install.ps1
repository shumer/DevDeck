param([Parameter(Mandatory)][string]$Package, [string]$Report)
$ErrorActionPreference = 'Stop'
$sourceRoot = [System.IO.Path]::GetFullPath($Package)
$manifestPath = Join-Path $sourceRoot 'windows-package.json'
$originalBytes = [System.IO.File]::ReadAllBytes($manifestPath)
$testRoot = Join-Path $env:LOCALAPPDATA ('DevDeck\InstallerTests\' + [guid]::NewGuid().ToString('N'))
$installer = Join-Path $sourceRoot 'install.ps1'
$startupDirectory = Join-Path $testRoot 'startup-fixture'
$checks = @()
try {
    $first = & $installer -Package $sourceRoot -InstallRoot $testRoot -NoShortcuts -StartupDirectory $startupDirectory
    $firstState = Get-Content -LiteralPath (Join-Path $testRoot 'current-install.json') -Raw | ConvertFrom-Json
    if (!(Test-Path -LiteralPath $first) -or $firstState.platform -ne 'windows') { throw 'First installation failed.' }
    $checks += 'install verified package'
    $again = & $installer -Package $sourceRoot -InstallRoot $testRoot -NoShortcuts -StartupDirectory $startupDirectory
    if ($again -ne $first) { throw 'Repeated installation changed its target.' }
    $checks += 'idempotent install'
    $preserved = Join-Path $testRoot 'windows-settings.json'
    Set-Content -LiteralPath $preserved -Value 'owned-settings-fixture'
    New-Item -ItemType Directory -Path $startupDirectory | Out-Null
    $startupPath = Join-Path $startupDirectory 'DevDeck-owned-fixture.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $startup = $shell.CreateShortcut($startupPath)
    $startup.TargetPath = $first; $startup.Arguments = '--settings "' + $preserved + '"';
    $startup.Description = 'DevDeck Windows startup schema 1'; $startup.Save()
    $nextManifest = [System.Text.Encoding]::UTF8.GetString($originalBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $nextManifest.version = '0.0.1-installer-test'
    $nextManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    $second = & $installer -Package $sourceRoot -InstallRoot $testRoot -NoShortcuts -StartupDirectory $startupDirectory
    $secondState = Get-Content -LiteralPath (Join-Path $testRoot 'current-install.json') -Raw | ConvertFrom-Json
    if ($second -eq $first -or $secondState.previous -ne $firstState.path -or !(Test-Path -LiteralPath $first)) { throw 'Upgrade did not preserve the previous version.' }
    $checks += 'upgrade preserves previous package'
    $startup = $shell.CreateShortcut($startupPath)
    if ($startup.TargetPath -ne $second -or $startup.Arguments -ne ('--settings "' + $preserved + '"')) { throw 'Upgrade did not preserve enabled startup configuration.' }
    $checks += 'upgrade retargets owned opt-in startup'
    & (Join-Path $sourceRoot 'rollback.ps1') -InstallRoot $testRoot -NoShortcuts -StartupDirectory $startupDirectory | Out-Null
    $rolled = Get-Content -LiteralPath (Join-Path $testRoot 'current-install.json') -Raw | ConvertFrom-Json
    if ($rolled.path -ne $firstState.path) { throw 'Rollback did not reactivate the previous version.' }
    $checks += 'rollback reactivates verified previous package'
    if ($shell.CreateShortcut($startupPath).TargetPath -ne $first) { throw 'Rollback did not retarget startup.' }
    $statePath = Join-Path $testRoot 'current-install.json'
    $stateBytes = [System.IO.File]::ReadAllBytes($statePath)
    $outsideVersion = Join-Path $testRoot 'outside-version'
    New-Item -ItemType Directory -Path $outsideVersion | Out-Null
    Set-Content -LiteralPath (Join-Path $outsideVersion '.devdeck-installed') -Value 'owned outside-version fixture'
    $invoked = Join-Path $outsideVersion 'unexpected-invocation'
    Set-Content -LiteralPath (Join-Path $outsideVersion 'install.ps1') -Value 'Set-Content -LiteralPath (Join-Path $PSScriptRoot "unexpected-invocation") -Value "wrong target"'
    try {
        $unsafeState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $unsafeState.previous = (Join-Path $testRoot 'Versions') + '\..\outside-version'
        $unsafeState | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8
        $rollbackRejected = $false
        try { & (Join-Path $sourceRoot 'rollback.ps1') -InstallRoot $testRoot -NoShortcuts -StartupDirectory $startupDirectory | Out-Null } catch { $rollbackRejected = $true }
        if (!$rollbackRejected -or (Test-Path -LiteralPath $invoked)) { throw 'Rollback executed a path outside Versions.' }
        $checks += 'rollback canonicalizes previous path and rejects traversal before execution'
    }
    finally { [System.IO.File]::WriteAllBytes($statePath, $stateBytes) }
    $unsafe = [System.Text.Encoding]::UTF8.GetString($originalBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $unsafe.files += @{ path = '..\outside.exe'; sha256 = '00' }
    $unsafe | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    $rejected = $false
    try { & $installer -Package $sourceRoot -InstallRoot $testRoot -NoShortcuts -StartupDirectory $startupDirectory | Out-Null } catch { $rejected = $true }
    if (!$rejected) { throw 'Installer accepted a path outside the package.' }
    $checks += 'traversal rejected before copying'
    & (Join-Path $sourceRoot 'uninstall.ps1') -InstallRoot $testRoot -StartupDirectory $startupDirectory | Out-Null
    if (Test-Path -LiteralPath $startupPath) { throw 'Uninstall kept the owned startup entry.' }
    if ((Get-Content -LiteralPath $preserved -Raw).Trim() -ne 'owned-settings-fixture' -or (Test-Path -LiteralPath $first) -or (Test-Path -LiteralPath $second)) { throw 'Uninstall damaged settings or kept installed packages.' }
    $checks += 'uninstall preserves settings and removes only owned versions'
    $result = @{ passed = $checks.Count; failed = 0; checks = $checks; releaseQualified = $false }
    if ($Report) { $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Report -Encoding utf8 }
    Write-Output ('Installer checks: ' + $checks.Count + ' passed, 0 failed.')
}
finally {
    [System.IO.File]::WriteAllBytes($manifestPath, $originalBytes)
    # Any failed installation remains under this unique owned test root for inspection.
}
