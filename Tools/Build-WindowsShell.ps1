param(
    [ValidateSet("x64", "arm64")]
    [string]$Architecture = $(if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }),
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
$repository = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $OutputDirectory) {
    $OutputDirectory = "dist\windows-$Architecture"
}
$output = [System.IO.Path]::GetFullPath((Join-Path $repository $OutputDirectory))
if (-not $output.StartsWith($repository + [System.IO.Path]::DirectorySeparatorChar)) {
    throw "Output directory must stay inside the repository."
}

$env:Path = $env:Path + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" `
    + [Environment]::GetEnvironmentVariable("Path", "User")
foreach ($name in @("SDKROOT", "SWIFT_DEVELOPER_DIR")) {
    # Hosted setup actions provide the toolchain through the process environment.
    if ([Environment]::GetEnvironmentVariable($name, "Process")) { continue }
    $value = [Environment]::GetEnvironmentVariable($name, "Machine")
    if (-not $value) {
        $value = [Environment]::GetEnvironmentVariable($name, "User")
    }
    if ($value) {
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}
$visualStudio = $null
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$visualStudioComponent = if ($Architecture -eq "arm64") {
    "Microsoft.VisualStudio.Component.VC.Tools.ARM64"
} else {
    "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
}
if (Test-Path -LiteralPath $vswhere) {
    $visualStudio = & $vswhere -latest -products '*' `
        -requires $visualStudioComponent -property installationPath
    if ($LASTEXITCODE -ne 0) { $visualStudio = $null }
}
if (-not $visualStudio) {
    $visualStudio = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $visualStudio) {
    throw "Visual Studio with C++ build tools is not installed."
}
$toolPath = $env:Path
Import-Module (Join-Path $visualStudio "Common7\Tools\Microsoft.VisualStudio.DevShell.dll")
Enter-VsDevShell `
    -VsInstallPath $visualStudio -SkipAutomaticLocation `
    -DevCmdArguments "-arch=$Architecture -host_arch=$Architecture" | Out-Null
$env:Path = $toolPath + ";" + $env:Path
if (-not (($env:LIB -split ';') | Where-Object { Test-Path -LiteralPath (Join-Path $_ "kernel32.lib") })) {
    $windowsKits = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10"
    $sdkVersion = Get-ChildItem (Join-Path $windowsKits "Lib") -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName "um\$Architecture\kernel32.lib")
        } |
        Sort-Object { [Version]$_.Name } -Descending |
        Select-Object -First 1 -ExpandProperty Name
    if (-not $sdkVersion) {
        throw "Windows SDK libraries for $Architecture are not installed."
    }
    $sdkInclude = Join-Path $windowsKits "Include\$sdkVersion"
    $env:INCLUDE += ";$(Join-Path $sdkInclude 'ucrt');$(Join-Path $sdkInclude 'shared');$(Join-Path $sdkInclude 'um');$(Join-Path $sdkInclude 'winrt');$(Join-Path $sdkInclude 'cppwinrt')"
    $env:LIB += ";$(Join-Path $windowsKits "Lib\$sdkVersion\ucrt\$Architecture");$(Join-Path $windowsKits "Lib\$sdkVersion\um\$Architecture")"
    $env:LIBPATH = $env:LIB
    $env:Path = (Join-Path $windowsKits "bin\$sdkVersion\$Architecture") + ";" + $env:Path
}

$swiftArchitecture = if ($Architecture -eq "arm64") { "aarch64" } else { "x86_64" }
$swiftCandidates = @()
$swiftCommand = Get-Command swift.exe -ErrorAction SilentlyContinue
if ($swiftCommand) { $swiftCandidates += $swiftCommand.Source }
$swiftCandidates += Get-ChildItem `
    (Join-Path $env:LOCALAPPDATA "Programs\Swift\Toolchains") `
    -Filter swift.exe -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -ExpandProperty FullName
$swift = $null
$targetInfo = $null
foreach ($candidate in $swiftCandidates | Select-Object -Unique) {
    try {
        $candidateInfo = & $candidate -print-target-info 2>$null | ConvertFrom-Json
    } catch {
        continue
    }
    if ($LASTEXITCODE -ne 0 -or -not $candidateInfo.target.triple) { continue }
    if ($candidateInfo.target.triple.StartsWith("$swiftArchitecture-")) {
        $swift = $candidate
        $targetInfo = $candidateInfo
        break
    }
}
if (-not $swift) {
    throw "Swift for Windows $Architecture is not installed or cannot start."
}
$swiftBin = Split-Path $swift
$env:Path = $swiftBin + ";" + $env:Path
$runtimePaths = @($targetInfo.paths.runtimeLibraryPaths)
$targetTriple = $targetInfo.target.triple
$userDotnet = Join-Path $env:LOCALAPPDATA "Microsoft\dotnet\dotnet.exe"
$dotnet = if (Test-Path -LiteralPath $userDotnet) {
    $userDotnet
} else {
    (Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
}
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
    Invoke-SwiftProduct "DevDeckMCP"

    if (Test-Path -LiteralPath $output) {
        Remove-Item -LiteralPath $output -Recurse -Force
    }
    New-Item -ItemType Directory -Path $output | Out-Null
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
    & $dotnet publish Windows\DevDeck.Shell\DevDeck.Shell.csproj `
        -c Release -r "win-$Architecture" --self-contained false --output $output `
        -p:DebugType=None -p:DebugSymbols=false -warnaserror
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $products = @()
    $legacyProducts = Join-Path $repository ".build\out\Products"
    if (Test-Path -LiteralPath $legacyProducts) {
        $products += Get-ChildItem $legacyProducts -Directory -Filter "Release-windows-*"
    }
    $tripleProduct = Join-Path $repository ".build\$targetTriple\release"
    if (Test-Path -LiteralPath $tripleProduct) {
        $products += Get-Item -LiteralPath $tripleProduct
    }
    $product = $products | Where-Object {
        $_.FullName.ToLowerInvariant().Contains($swiftArchitecture) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName "DevDeckEngineHost.exe"))
    } | Select-Object -First 1
    if (-not $product) {
        throw "Swift release products for '$targetTriple' were not found."
    }
    $engineHost = Join-Path $product.FullName "DevDeckEngineHost.exe"
    $processHost = Join-Path $product.FullName "DevDeckProcessHost.exe"
    $mcpServer = Join-Path $product.FullName "DevDeckMCP.exe"
    Copy-Item -LiteralPath $engineHost, $processHost, $mcpServer -Destination $output
    # The engine host reads the delivery's version from this file to know what an update replaces.
    Copy-Item -LiteralPath (Join-Path $repository "VERSION") -Destination $output

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
