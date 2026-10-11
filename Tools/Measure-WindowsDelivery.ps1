#requires -Version 7.0
param(
    [string]$OutputDirectory = "dist"
)

$ErrorActionPreference = "Stop"
$repository = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$output = [System.IO.Path]::GetFullPath((Join-Path $repository $OutputDirectory))
if (-not $output.StartsWith($repository + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Output directory must stay inside the repository."
}
$session = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
if (Get-CimInstance Win32_Process -Filter "Name='DevDeck.Shell.exe' AND SessionId=$session") {
    throw "Close DevDeck before measuring the live shell."
}
New-Item -ItemType Directory -Path $output -Force | Out-Null
$work = Join-Path $output "size-measurement"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
New-Item -ItemType Directory -Path (Join-Path $work "temp") -Force | Out-Null
# The existing builder has fixed log names, so concurrent checkouts need separate TEMP.
$env:TEMP = Join-Path $work "temp"
$env:TMP = $env:TEMP

function Reset-Directory([string]$path) {
    $resolved = [System.IO.Path]::GetFullPath($path)
    if (-not $resolved.StartsWith($output + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Measurement directory must stay inside its output directory."
    }
    if (Test-Path -LiteralPath $resolved) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    New-Item -ItemType Directory -Path $resolved | Out-Null
}

function Invoke-Publish([string]$destination, [string[]]$flags, [string]$log) {
    Reset-Directory $destination
    & dotnet publish Windows/DevDeck.Shell/DevDeck.Shell.csproj -c Release -r win-x64 `
        --output $destination -p:DebugType=None -p:DebugSymbols=false @flags *> $log
    return $LASTEXITCODE
}

function Copy-Swift([string]$destination) {
    foreach ($file in Get-ChildItem -LiteralPath $baseline -File) {
        if ($file.Name -in $runtimeNames -or $file.Name -in @("DevDeckEngineHost.exe", "DevDeckProcessHost.exe")) {
            Copy-Item -LiteralPath $file.FullName -Destination $destination
        }
    }
    Get-ChildItem -LiteralPath $baseline -Directory -Filter "*.bundle" | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse
    }
}

function Start-Shell([string]$directory, [string]$trace, [string]$engine, [string]$extract) {
    $name = 'Local\DevDeck.Shell.' + [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    while ($true) {
        $existing = $null
        $other = Get-CimInstance Win32_Process -Filter "Name='DevDeck.Shell.exe' AND SessionId=$session"
        $locked = [System.Threading.Mutex]::TryOpenExisting($name, [ref]$existing)
        if ($locked) { $existing.Dispose() }
        if (-not $locked -and -not $other) { break }
        if ([DateTime]::UtcNow -ge $deadline) { throw "Close the other live DevDeck instance before measuring." }
        Start-Sleep -Milliseconds 100
    }
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = Join-Path $directory "DevDeck.Shell.exe"
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.Environment["LOCALAPPDATA"] = $profile
    $info.Environment["APPDATA"] = Join-Path $work "roaming"
    $info.Environment["PROGRAMDATA"] = Join-Path $work "programdata"
    $info.Environment["DOTNET_BUNDLE_EXTRACT_BASE_DIR"] = $extract
    # A removed Swift DLL must not be rescued by a development toolchain on PATH.
    $info.Environment["PATH"] = "$env:SystemRoot\System32;$env:SystemRoot"
    $info.Environment["DEVDECK_MEASURE_HOST"] = Join-Path $directory "DevDeckEngineHost.exe"
    $info.Environment["DEVDECK_MEASURE_RESULT"] = Join-Path $work "survey.json"
    $info.Environment["DEVDECK_MEASURE_PORT"] = "$port"
    $info.ArgumentList.Add("--trace")
    $info.ArgumentList.Add($trace)
    if ($engine) {
        $info.ArgumentList.Add("--engine")
        $info.ArgumentList.Add($engine)
    }
    return [System.Diagnostics.Process]::Start($info)
}

function Stop-MeasurementShell($process) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($process.Id)")
    if (-not $process.HasExited) { $process.Kill() }
    foreach ($child in $children) {
        if ($child.Name -eq "DevDeckEngineHost.exe") {
            Stop-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
        }
    }
    $process.WaitForExit()
    $process.Dispose()
}

function Measure-Startup([string]$directory, [string]$label) {
    $times = @()
    for ($run = 1; $run -le 3; $run++) {
        $trace = Join-Path $work "$label-start-$run.trace"
        if (Test-Path -LiteralPath $trace) { Remove-Item -LiteralPath $trace }
        $extract = Join-Path $work "$label-extract-$run"
        Reset-Directory $extract
        $process = Start-Shell $directory $trace "" $extract
        try {
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            $first = $null
            while ([DateTime]::UtcNow -lt $deadline -and -not $first) {
                if (Test-Path -LiteralPath $trace) {
                    $first = Get-Content -LiteralPath $trace |
                        Where-Object { $_ -match ' < .*"event":"card.changed"' } |
                        Select-Object -First 1
                }
                if ($process.HasExited) { throw "$label exited before its first card." }
                if (-not $first) { Start-Sleep -Milliseconds 20 }
            }
            if (-not $first) { throw "$label did not send card.changed within 30 seconds." }
            $when = [DateTimeOffset]::Parse(($first -split ' ', 2)[0])
            $times += ($when.UtcDateTime - $process.StartTime.ToUniversalTime()).TotalSeconds
        }
        finally { Stop-MeasurementShell $process }
    }
    return $times
}

function Invoke-Survey([string]$directory, [string]$label) {
    $result = Join-Path $work "survey.json"
    if (Test-Path -LiteralPath $result) { Remove-Item -LiteralPath $result }
    $process = Start-Shell $directory (Join-Path $work "$label-survey.trace") $proxy (Join-Path $work "$label-survey-extract")
    try {
        if (-not $process.WaitForExit(90000)) { throw "$label survey did not finish." }
        if (-not (Test-Path -LiteralPath $result)) { throw "$label produced no module survey." }
        $survey = Get-Content -LiteralPath $result -Raw | ConvertFrom-Json
        Copy-Item -LiteralPath $result -Destination (Join-Path $work "$label-survey.json")
        if (-not ($survey.started -and $survey.stopped -and $survey.settings -and $survey.logs)) {
            throw "$label scenario failed: $($survey | ConvertTo-Json -Compress -Depth 4)"
        }
        if ($survey.errors -match 'load|dll|module|failed') {
            throw "$label host diagnostics need inspection: $($survey.errors)"
        }
        return $survey
    }
    finally { Stop-MeasurementShell $process }
}

function Measure-Folder([string]$directory, [string]$label) {
    $files = @(Get-ChildItem -LiteralPath $directory -Recurse -File)
    $archive = "$directory.zip"
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive }
    Compress-Archive -Path (Join-Path $directory "*") -DestinationPath $archive
    $times = @(Measure-Startup $directory $label)
    return [pscustomobject]@{
        Variant = $label
        Bytes = ($files | Measure-Object Length -Sum).Sum
        ZipBytes = (Get-Item -LiteralPath $archive).Length
        Files = $files.Count
        RunsSeconds = $times
        MeanSeconds = ($times | Measure-Object -Average).Average
    }
}

Push-Location $repository
try {
    $baseline = Join-Path $output "size-baseline"
    & (Join-Path $PSScriptRoot "Build-WindowsShell.ps1") -OutputDirectory ([System.IO.Path]::GetRelativePath($repository, $baseline)) *> (Join-Path $work "baseline-build.log")
    if (-not $?) { throw "Baseline build failed. See size-measurement/baseline-build.log." }
    $swift = (Get-Command swift.exe).Source
    $runtimePaths = @((& $swift -print-target-info | ConvertFrom-Json).paths.runtimeLibraryPaths)
    $runtimeNames = @(Get-ChildItem -LiteralPath $baseline -File | Where-Object {
        $name = $_.Name
        @($runtimePaths | Where-Object { Test-Path -LiteralPath (Join-Path $_ $name) }).Count -gt 0
    } | Select-Object -ExpandProperty Name)
    $inventory = @(Get-ChildItem -LiteralPath $baseline -Recurse -File | ForEach-Object {
        $relative = [System.IO.Path]::GetRelativePath($baseline, $_.FullName)
        $group = if ($_.Name -in $runtimeNames) { "Swift runtime" }
            elseif ($_.Name -in @("DevDeckEngineHost.exe", "DevDeckProcessHost.exe")) { "Swift products" }
            elseif ($relative -match '\.bundle[\\/]') { "Resources" }
            else { ".NET shell and runtime" }
        [pscustomobject]@{ File = $relative; Group = $group; Bytes = $_.Length }
    })

    $profile = Join-Path $work "profile"
    Reset-Directory $profile
    $projectFolder = Join-Path $profile "sample-project"
    New-Item -ItemType Directory -Path (Join-Path $profile "DevDeck"), $projectFolder -Force | Out-Null
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    $server = @'
param([int]$Port)
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Output "Sample server ready."
while ($true) {
    $client = $listener.AcceptTcpClient()
    $stream = $client.GetStream()
    $stream.ReadTimeout = 3000
    $request = [byte[]]::new(4096)
    $count = $stream.Read($request, 0, $request.Length)
    $bytes = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: 2`r`nConnection: close`r`n`r`nOK")
    if ($count -gt 0) { $stream.Write($bytes, 0, $bytes.Length) }
    $client.Dispose()
}
'@
    $serverFile = Join-Path $projectFolder "server.ps1"
    Set-Content -LiteralPath $serverFile -Value $server -Encoding utf8
    $project = @{
        id = "delivery-sample"; title = "Sample project"; subtitle = ""; folder = $projectFolder
        startCommand = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$serverFile`" -Port $port"
        stopCommand = ""; holdsProcess = $true; requiresDocker = $false; isEnabled = $true
        healthURL = "http://127.0.0.1:$port"; localSiteURL = "http://127.0.0.1:$port"; links = @(); browser = @{}
    }
    $layout = @{ settings = @("github.pullRequests", "github.inbox", "github.actions", "gitlab.mergeRequests", "local.workInFlight", "arc.organizations", "local.stack") | ForEach-Object { @{id = $_; isEnabled = $false} } }
    $preferences = @{}
    foreach ($entry in @(@{key = "local.projects"; value = @($project)}, @{key = "cards.layout"; value = $layout})) {
        $json = ConvertTo-Json -InputObject $entry.value -Depth 12 -Compress
        $preferences[$entry.key] = @{data = @{_0 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))}}
    }
    $preferences["language"] = @{string = @{_0 = "en"}}
    $preferences | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $profile "DevDeck/preferences.json") -Encoding utf8

    # The proxy only forwards bytes and drives measurement requests through protocol v2.
    $helper = Join-Path $work "proxy"
    New-Item -ItemType Directory -Path $helper -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $helper "Proxy.csproj") -Encoding utf8 -Value '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup></Project>'
    $source = @'
using System.Diagnostics;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

var info = new ProcessStartInfo(Environment.GetEnvironmentVariable("DEVDECK_MEASURE_HOST")!) {
    UseShellExecute = false, RedirectStandardInput = true, RedirectStandardOutput = true,
    RedirectStandardError = true, CreateNoWindow = true, StandardInputEncoding = new UTF8Encoding(false)
};
using var host = Process.Start(info)!;
var gate = new SemaphoreSlim(1);
var first = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
var settings = false;
var logs = false;
var diagnostics = host.StandardError.ReadToEndAsync();
async Task Send(string line) {
    await gate.WaitAsync();
    try { await host.StandardInput.WriteLineAsync(line); await host.StandardInput.FlushAsync(); }
    finally { gate.Release(); }
}
Task Command(string json) => Send("{\"protocolVersion\":2,\"id\":\"measure\",\"intent\":\"command\",\"command\":" + json + "}");
var output = Task.Run(async () => {
    while (await host.StandardOutput.ReadLineAsync() is { } line) {
        using var document = JsonDocument.Parse(line);
        var root = document.RootElement;
        var name = root.GetProperty("event").GetString();
        if (name == "card.changed") first.TrySetResult();
        if (name == "log.changed") logs = true;
        if (name == "settings.answered") settings = true;
        Console.WriteLine(line);
    }
});
var input = Task.Run(async () => {
    while (await Console.In.ReadLineAsync() is { } line) await Send(line);
    host.StandardInput.Close();
});
var port = int.Parse(Environment.GetEnvironmentVariable("DEVDECK_MEASURE_PORT")!);
async Task<bool> Alive() {
    try {
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
        using var response = await client.GetAsync("http://127.0.0.1:" + port);
        return response.IsSuccessStatusCode;
    }
    catch (HttpRequestException) { return false; }
    catch (TaskCanceledException) { return false; }
}
async Task<bool> Wait(bool expected) {
    var timer = Stopwatch.StartNew();
    while (timer.Elapsed < TimeSpan.FromSeconds(25)) {
        if (await Alive() == expected) return true;
        await Task.Delay(100);
    }
    return false;
}
await first.Task.WaitAsync(TimeSpan.FromSeconds(30));
await Command("{\"project\":{\"_0\":\"project.delivery-sample\",\"_1\":\"start\"}}");
var started = await Wait(true);
await Command("{\"toggleLogs\":{\"_0\":\"project.delivery-sample\"}}");
await Command("{\"openSettings\":{}}");
await Task.Delay(2500);
await Command("{\"project\":{\"_0\":\"project.delivery-sample\",\"_1\":\"stop\"}}");
var stopped = await Wait(false);
await Task.Delay(1500);
var modules = host.Modules.Cast<ProcessModule>().Select(module => new { name = module.ModuleName, path = module.FileName }).ToArray();
await Command("{\"quit\":{}}");
await host.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(15));
var errors = await diagnostics;
var result = new { started, stopped, settings, logs, modules, errors };
await File.WriteAllTextAsync(Environment.GetEnvironmentVariable("DEVDECK_MEASURE_RESULT")!, JsonSerializer.Serialize(result));
await output;
'@
    Set-Content -LiteralPath (Join-Path $helper "Program.cs") -Value $source -Encoding utf8
    & dotnet publish (Join-Path $helper "Proxy.csproj") -c Release -o (Join-Path $helper "out") *> (Join-Path $work "proxy-build.log")
    if ($LASTEXITCODE -ne 0) { throw "Measurement proxy did not build." }
    $proxy = Join-Path $helper "out/Proxy.exe"
    $baselineSurvey = Invoke-Survey $baseline "Baseline"
    $unloaded = @($inventory | Where-Object { $_.Group -eq "Swift runtime" -and $_.File -notin $baselineSurvey.modules.name })

    $a = Join-Path $output "size-A"
    if ((Invoke-Publish $a @("--self-contained", "false", "-warnaserror") (Join-Path $work "A-publish.log")) -ne 0) { throw "A did not publish." }
    Copy-Swift $a
    $b = Join-Path $output "size-B"
    $flags = @("--self-contained", "true", "-p:PublishReadyToRun=false", "-p:PublishSingleFile=true", "-p:IncludeNativeLibrariesForSelfExtract=true", "-p:EnableCompressionInSingleFile=true")
    $trimExit = Invoke-Publish $b ($flags + "-p:PublishTrimmed=true") (Join-Path $work "B-trim.log")
    $trimError = $null
    if ($trimExit -ne 0) {
        $trimError = @(Get-Content (Join-Path $work "B-trim.log") | Where-Object { $_ -match 'error ' })
        if ((Invoke-Publish $b ($flags + @("-p:PublishTrimmed=false", "-warnaserror")) (Join-Path $work "B-publish.log")) -ne 0) { throw "Untrimmed B did not publish." }
    }
    Copy-Swift $b
    $c = Join-Path $output "size-C"
    Reset-Directory $c
    Copy-Item -Path (Join-Path $a "*") -Destination $c -Recurse
    foreach ($file in $unloaded) { Remove-Item -LiteralPath (Join-Path $c $file.File) }
    $returned = @()
    try { $cSurvey = Invoke-Survey $c "C" }
    catch {
        # Restore conservatively when the scenario cannot establish a safe reduced set.
        foreach ($file in $unloaded) {
            Copy-Item -LiteralPath (Join-Path $a $file.File) -Destination $c
            $returned += $file.File
        }
        $cSurvey = Invoke-Survey $c "C-restored"
    }
    $aSurvey = Invoke-Survey $a "A"
    $bSurvey = Invoke-Survey $b "B"
    $rows = @(
        Measure-Folder $baseline "Baseline"
        Measure-Folder $a "A"
        Measure-Folder $b "B"
        Measure-Folder $c "C"
    )
    $metadata = @{
        Date = [DateTimeOffset]::Now.ToString("yyyy-MM-dd")
        Commit = (& git rev-parse HEAD)
        Swift = (& $swift --version) -join " "
        Dotnet = (& dotnet --version)
        Windows = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
        WindowsRevision = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").UBR
        Inventory = $inventory; Rows = $rows; Unloaded = $unloaded; Returned = $returned
        TrimExit = $trimExit; TrimError = $trimError; BaselineSurvey = $baselineSurvey; CSurvey = $cSurvey
    }
    $metadata | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $work "results.json") -Encoding utf8
    $rows | Select-Object Variant, @{Name = "FolderMiB"; Expression = {[Math]::Round($_.Bytes / 1MB, 3)}},
        @{Name = "ZipMiB"; Expression = {[Math]::Round($_.ZipBytes / 1MB, 3)}}, Files,
        @{Name = "FirstCardSeconds"; Expression = {[Math]::Round($_.MeanSeconds, 3)}} | Format-Table -AutoSize
}
finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    Pop-Location
}
