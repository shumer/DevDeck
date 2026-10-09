param(
    [string]$OutputDirectory = "dist\windows-x64"
)

$ErrorActionPreference = "Stop"
$repository = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$output = [System.IO.Path]::GetFullPath((Join-Path $repository $OutputDirectory))
if (-not $output.StartsWith($repository + [System.IO.Path]::DirectorySeparatorChar)) {
    throw "Output directory must stay inside the repository."
}

$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" `
    + [Environment]::GetEnvironmentVariable("Path", "User")
foreach ($name in @("SDKROOT", "SWIFT_DEVELOPER_DIR")) {
    $value = [Environment]::GetEnvironmentVariable($name, "Machine")
    if (-not $value) {
        $value = [Environment]::GetEnvironmentVariable($name, "User")
    }
    if ($value) {
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}
$visualStudio = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
if (-not (Test-Path -LiteralPath $visualStudio)) {
    $visualStudio = "C:\Program Files\Microsoft Visual Studio\2022\BuildTools"
}
Import-Module (Join-Path $visualStudio "Common7\Tools\Microsoft.VisualStudio.DevShell.dll")
Enter-VsDevShell `
    -VsInstallPath $visualStudio -SkipAutomaticLocation `
    -DevCmdArguments "-arch=x64 -host_arch=x64" | Out-Null

$swiftCommand = Get-Command swift.exe -ErrorAction SilentlyContinue
$swift = $swiftCommand.Source
if (-not $swift) {
    $swift = Get-ChildItem `
        (Join-Path $env:LOCALAPPDATA "Programs\Swift\Toolchains") `
        -Filter swift.exe -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $swift) {
    throw "Swift is not installed."
}
$swiftBin = Split-Path $swift
$env:Path = $swiftBin + ";" + $env:Path
$targetInfo = (& $swift -print-target-info | ConvertFrom-Json)
$runtimePaths = @($targetInfo.paths.runtimeLibraryPaths)
$dotnet = (Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
if (-not $dotnet) {
    $dotnet = "C:\Program Files\dotnet\dotnet.exe"
}
if (-not (Test-Path -LiteralPath $dotnet)) {
    throw ".NET 10 SDK is not installed."
}

function Invoke-SwiftProduct([string]$product) {
    $log = Join-Path $env:TEMP "devdeck-swift-$product.log"
    & $swift build -c release --product $product --jobs 1 2>&1 | Tee-Object -FilePath $log
    $buildExit = $LASTEXITCODE
    if ($buildExit -ne 0) { exit $buildExit }

    # Swift 6.4 emits swiftlang/swift#91000 from WinSDK. Remove this exception with the toolchain fix.
    $allowedWarning = "warning: reference to type 'wchar_t' broken by a context change; 'wchar_t' was expected to be in '_Builtin_stddef', but now a candidate is found only in 'SwiftShims'"
    $unexpectedWarnings = Select-String -Path $log -SimpleMatch "warning:" |
        Where-Object { -not $_.Line.Contains($allowedWarning) }
    Remove-Item -LiteralPath $log -Force
    if ($unexpectedWarnings) {
        $unexpectedWarnings | ForEach-Object { Write-Error $_.Line }
        exit 1
    }
}

Push-Location $repository
try {
    Invoke-SwiftProduct "DevDeckEngineHost"
    Invoke-SwiftProduct "DevDeckProcessHost"

    if (Test-Path -LiteralPath $output) {
        Remove-Item -LiteralPath $output -Recurse -Force
    }
    New-Item -ItemType Directory -Path $output | Out-Null
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
    & $dotnet publish Windows\DevDeck.Shell\DevDeck.Shell.csproj `
        -c Release -r win-x64 --self-contained true --output $output `
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:DebugType=None -p:DebugSymbols=false -warnaserror
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $products = Get-ChildItem .build\out\Products -Directory -Filter "Release-windows-*"
    $product = $products | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName "DevDeckEngineHost.exe")
    } | Select-Object -First 1
    if (-not $product) {
        throw "Swift release products were not found."
    }
    $engineHost = Join-Path $product.FullName "DevDeckEngineHost.exe"
    $processHost = Join-Path $product.FullName "DevDeckProcessHost.exe"
    Copy-Item -LiteralPath $engineHost, $processHost -Destination $output

    Get-ChildItem -LiteralPath $product.FullName -Directory -Filter "*.bundle" | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $output -Recurse
    }

    $readObject = Join-Path $swiftBin "llvm-readobj.exe"
    $pending = [System.Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($engineHost)
    $pending.Enqueue($processHost)
    $copied = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    while ($pending.Count -gt 0) {
        $binary = $pending.Dequeue()
        $imports = & $readObject --coff-imports $binary
        foreach ($line in $imports) {
            if ($line -notmatch '^\s+Name:\s+(.+\.dll)$') { continue }
            $name = $Matches[1]
            $candidate = $runtimePaths |
                ForEach-Object { Join-Path $_ $name } |
                Where-Object { Test-Path -LiteralPath $_ } |
                Select-Object -First 1
            if (-not $candidate) { continue }
            if (-not $copied.Add($name)) { continue }
            Copy-Item -LiteralPath $candidate -Destination $output
            $pending.Enqueue($candidate)
        }
    }

    $testFiles = Get-ChildItem -LiteralPath $output -Recurse | Where-Object Name -Like "*Tests*"
    if ($testFiles) {
        throw "Test files entered the delivery directory."
    }
    Get-ChildItem -LiteralPath $output | Sort-Object Name | Select-Object Name, Length
}
finally {
    Pop-Location
}
