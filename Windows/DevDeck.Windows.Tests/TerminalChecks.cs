using System.Diagnostics;
using System.Text.Json;
using DevDeck.Windows.Core;

// Explicit live qualification: disposable WT windows/WSL fixtures, no actual deck capture or lifecycle actions.
internal static class TerminalChecks
{
    internal static async Task<int> RunAsync(string settingsPath, string reportPath)
    {
        var results = new List<object>();
        var failed = 0;
        var previousDirectory = Environment.CurrentDirectory;
        var callerDirectory = Path.Combine(Path.GetTempPath(), "devdeck-terminal-caller-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(callerDirectory);
        Environment.CurrentDirectory = callerDirectory;
        try
        {
            var settings = new SettingsStore(settingsPath).Load();
            foreach (var distribution in settings.Cards.Where(card => card.Enabled).Select(card => card.Project.Distribution).Distinct())
            {
                var id = "devdeck-terminal-" + Guid.NewGuid().ToString("N");
                var linuxRoot = "/tmp/" + id;
                var uncParent = Path.GetFullPath(@"\\wsl.localhost\" + distribution + @"\tmp");
                var root = Path.GetFullPath(Path.Combine(uncParent, id));
                if (Path.GetDirectoryName(root) != uncParent || Directory.Exists(root)) throw new IOException("Fixture is not a new owned directory.");
                Directory.CreateDirectory(root);
                try
                {
                    async Task Check(string name, Func<Task> action)
                    {
                        try { await action(); results.Add(new { name, distribution, passed = true }); Console.WriteLine("ok  " + distribution + ": " + name); }
                        catch (Exception error) { failed++; results.Add(new { name, distribution, passed = false, error = error.Message }); Console.WriteLine("FAIL " + distribution + ": " + name + ": " + error.Message); }
                    }
                    var actual = settings.Cards.First(card => card.Enabled && card.Project.Distribution == distribution).Project;
                    // The reported checkout is preferred when present; reading pwd does not alter the project.
                    actual = settings.Cards.FirstOrDefault(card => card.Enabled && card.Project.Distribution == distribution && card.Project.Path.EndsWith("/nasdaqir", StringComparison.Ordinal))?.Project ?? actual;
                    await Check("WT opens actual project directory", () => VerifyFolder(actual.Path, true, "actual"));
                    Directory.CreateDirectory(Path.Combine(root, "проект с пробелами"));
                    await Check("WT preserves Unicode and spaces", () => VerifyFolder(linuxRoot + "/проект с пробелами", true, "unicode"));
                    Directory.CreateDirectory(Path.Combine(root, "literal;new-tab"));
                    await Check("direct WSL preserves literal delimiter path", () => VerifyFolder(linuxRoot + "/literal;new-tab", true, "literal"));
                    await Check("log terminal enters project and opens its log", async () =>
                    {
                        var logPath = linuxRoot + "/проект с пробелами/synthetic.log";
                        await File.WriteAllTextAsync(Path.Combine(root, "проект с пробелами", "synthetic.log"), id + "\n");
                        var launch = TerminalLaunch.CreateLogs(new("fixture", distribution, "local", linuxRoot + "/проект с пробелами"), logPath);
                        Require(Directory.Exists(launch.WorkingDirectory), "Missing log terminal Windows directory");
                        IsolateTerminal(launch);
                        using var process = Process.Start(launch) ?? throw new IOException("Terminal did not start");
                        JsonElement? observed = null;
                        try
                        {
                            var deadline = Stopwatch.StartNew();
                            while (deadline.Elapsed < TimeSpan.FromSeconds(20))
                            {
                                var response = await Wsl(distribution, "python3", "-c", ObserveTail, logPath);
                                using var document = JsonDocument.Parse(response);
                                if (document.RootElement.GetArrayLength() == 1) { observed = document.RootElement[0].Clone(); break; }
                                await Task.Delay(250);
                            }
                            Require(observed is { }, "Terminal never executed the log command");
                            Require(observed!.Value.GetProperty("cwd").GetString() == linuxRoot + "/проект с пробелами", "Log terminal entered another directory");
                            Require(observed.Value.GetProperty("open").GetBoolean(), "Tail did not open the fixture log");
                        }
                        finally
                        {
                            // Only tail processes with this unique owned log target and unchanged start identity.
                            var records = observed is { } item ? "[" + item.GetRawText() + "]" : await Wsl(distribution, "python3", "-c", ObserveTail, logPath);
                            await Wsl(distribution, "python3", "-c", StopTail, logPath, records);
                        }
                    });

                    async Task VerifyFolder(string path, bool preferTerminal, string name)
                    {
                        var output = Path.Combine(root, name + ".pwd");
                        var script = Path.Combine(root, name + ".sh");
                        await File.WriteAllTextAsync(script, "pwd -P > " + Quote(linuxRoot + "/" + name + ".pwd") + "\n");
                        var launch = TerminalLaunch.Create(distribution, path, preferTerminal);
                        IsolateTerminal(launch);
                        foreach (var argument in new[] { "--exec", "/bin/sh", linuxRoot + "/" + name + ".sh" }) launch.ArgumentList.Add(argument);
                        using var process = Process.Start(launch) ?? throw new IOException("Terminal did not start");
                        var deadline = Stopwatch.StartNew();
                        while (!File.Exists(output) && deadline.Elapsed < TimeSpan.FromSeconds(20)) await Task.Delay(100);
                        Require(File.Exists(output), "Terminal never executed WSL");
                        Require((await File.ReadAllTextAsync(output)).TrimEnd('\r', '\n') == path, "WSL entered another directory");
                    }
                }
                finally
                {
                    // The exact absolute root was allocated above; all children are disposable synthetic files.
                    if (Path.GetFullPath(root) != Path.Combine(uncParent, id)) throw new IOException("Fixture cleanup boundary changed");
                    Directory.Delete(root, recursive: true);
                }
            }
        }
        catch (Exception error) { failed++; results.Add(new { name = "fixture setup/cleanup", passed = false, error = error.Message }); }
        finally { Environment.CurrentDirectory = previousDirectory; Directory.Delete(callerDirectory); }
        await File.WriteAllTextAsync(reportPath, JsonSerializer.Serialize(new { passed = results.Count - failed, failed, checks = results,
            actualWSLExecution = failed == 0, globalTerminalSettingsChanged = false, releaseQualified = false }, new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"Live terminal checks: {results.Count - failed} passed, {failed} failed.");
        return failed == 0 ? 0 : 1;
    }

    private static void IsolateTerminal(ProcessStartInfo launch)
    {
        if (launch.FileName == "wt.exe") { launch.ArgumentList.Insert(0, "new"); launch.ArgumentList.Insert(0, "--window"); }
    }
    private static string Quote(string value) => "'" + value.Replace("'", "'\"'\"'") + "'";
    private static void Require(bool condition, string message) { if (!condition) throw new IOException(message); }
    private static async Task<string> Wsl(string distribution, params string[] arguments)
    {
        var start = new ProcessStartInfo("wsl.exe") { UseShellExecute = false, CreateNoWindow = true,
            WorkingDirectory = Environment.SystemDirectory, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "--distribution", distribution, "--cd", "/tmp", "--exec" }.Concat(arguments)) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new IOException("WSL did not start");
        var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(15));
        Require(process.ExitCode == 0, "Owned WSL probe failed: " + await error);
        return await output;
    }
    private const string ObserveTail = """
        import os, sys, json
        result = []
        for pid in os.listdir('/proc'):
            if not pid.isdigit(): continue
            try:
                base = '/proc/' + pid
                cmd = open(base + '/cmdline', 'rb').read().rstrip(b'\0').split(b'\0')
                if os.path.basename(cmd[0]) != b'tail' or cmd[-1].decode() != sys.argv[1]: continue
                stat = open(base + '/stat').read().rsplit(')', 1)[1].split()
                result.append(dict(pid=int(pid), start=stat[19], cwd=os.readlink(base + '/cwd'),
                    open=any(os.readlink(base + '/fd/' + fd) == sys.argv[1] for fd in os.listdir(base + '/fd'))))
            except (OSError, IndexError): pass
        print(json.dumps(result))
        """;
    private const string StopTail = """
        import os, sys, json, signal
        for item in json.loads(sys.argv[2]):
            try:
                base = '/proc/' + str(item['pid'])
                cmd = open(base + '/cmdline', 'rb').read().rstrip(b'\0').split(b'\0')
                stat = open(base + '/stat').read().rsplit(')', 1)[1].split()
                if os.path.basename(cmd[0]) == b'tail' and cmd[-1].decode() == sys.argv[1] and stat[19] == item['start']:
                    os.kill(item['pid'], signal.SIGTERM)
            except (OSError, IndexError): pass
        """;
}
