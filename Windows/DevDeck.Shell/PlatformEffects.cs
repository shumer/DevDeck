using System.Diagnostics;
using System.Text.Json;

namespace DevDeck.Shell;

public sealed record PlatformLaunchPlan(
    string Executable,
    IReadOnlyList<string> Arguments,
    bool UseShellExecute = false);

public static class PlatformEffects
{
    public static void Apply(JsonElement effect)
    {
        var kind = JsonModel.String(effect, "kind");
        try
        {
            var plan = kind switch
            {
                "openURL" when JsonModel.String(effect, "url") is { } url => BrowserPlan(effect, url),
                "openTerminal" when JsonModel.String(effect, "folder") is { } folder =>
                    TerminalPlan(folder, ExecutableExists("wt.exe"), WindowsTerminalChoice.Parse(effect)),
                "revealFolder" when JsonModel.String(effect, "folder") is { } folder =>
                    new PlatformLaunchPlan("explorer.exe", [folder], true),
                "launchDocker" => DockerPlan(),
                _ => null,
            };
            if (plan is null)
            {
                Console.Error.WriteLine($"Ignored engine effect: {kind ?? "unknown"}.");
                return;
            }
            Start(plan);
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            Console.Error.WriteLine($"Engine effect failed: {kind ?? "unknown"}.");
        }
    }

    public static PlatformLaunchPlan DockerPlan(string? programFiles = null)
    {
        var directory = programFiles
            ?? Environment.GetEnvironmentVariable("ProgramFiles")
            ?? @"C:\Program Files";
        return new PlatformLaunchPlan(
            Path.Combine(directory, "Docker", "Docker", "Docker Desktop.exe"),
            [],
            true);
    }

    public static PlatformLaunchPlan BrowserPlan(
        string url,
        string? identifier,
        string? profileDirectory,
        IReadOnlyList<WindowsBrowserOption>? installed = null)
    {
        var browser = WindowsBrowserCatalog.Resolve(identifier, installed);
        if (browser?.Executable is not { Length: > 0 } executable)
        {
            return new PlatformLaunchPlan(url, [], true);
        }
        var arguments = new List<string>();
        if (!string.IsNullOrWhiteSpace(profileDirectory) && browser.SupportsProfiles)
        {
            arguments.Add($"--profile-directory={profileDirectory}");
        }
        arguments.Add(url);
        return new PlatformLaunchPlan(executable, arguments);
    }

    public static PlatformLaunchPlan TerminalPlan(
        string folder, bool windowsTerminalAvailable, WindowsTerminalChoice? choice = null)
    {
        var application = choice?.Application;
        if (application is "windowsPowerShell" or "powerShell")
        {
            var script = TryWslFolder(folder, out var distro, out var path)
                ? $"& wsl.exe -d '{PowerShellLiteral(distro)}' --cd '{PowerShellLiteral(path)}'"
                : $"Set-Location -LiteralPath '{PowerShellLiteral(folder)}'";
            var encoded = Convert.ToBase64String(System.Text.Encoding.Unicode.GetBytes(script));
            return new PlatformLaunchPlan(application == "powerShell" ? "pwsh.exe" : "powershell.exe",
                ["-NoExit", "-EncodedCommand", encoded], true);
        }
        if (application is not null && application is not ("windowsTerminal" or "commandPrompt"))
        {
            throw new InvalidOperationException("Unknown terminal application.");
        }
        if (application == "windowsTerminal" && !windowsTerminalAvailable)
        {
            throw new InvalidOperationException("The selected terminal is unavailable.");
        }
        var useWindowsTerminal = application != "commandPrompt" && windowsTerminalAvailable;
        var profileArguments = choice?.Profile is { Length: > 0 } profile
            ? new[] { "-p", profile }
            : Array.Empty<string>();
        if (TryWslFolder(folder, out var distribution, out var linuxPath))
        {
            var arguments = new[] { "wsl.exe", "-d", distribution, "--cd", linuxPath };
            if (useWindowsTerminal) return new PlatformLaunchPlan("wt.exe", [.. profileArguments, .. arguments]);
            return application == "commandPrompt"
                ? new PlatformLaunchPlan("cmd.exe", ["/K", .. arguments], true)
                : new PlatformLaunchPlan("wsl.exe", arguments[1..], true);
        }
        return useWindowsTerminal
            ? new PlatformLaunchPlan("wt.exe", [.. profileArguments, "-d", folder])
            : new PlatformLaunchPlan("cmd.exe", ["/K", "cd", "/d", folder], true);
    }

    private static string PowerShellLiteral(string value)
    {
        return value.Replace("'", "''", StringComparison.Ordinal);
    }

    public static bool TryWslFolder(string folder, out string distribution, out string linuxPath)
    {
        var normalized = folder.Replace('\\', '/');
        var prefixes = new[] { "//wsl.localhost/", "//wsl$/" };
        var prefix = prefixes.FirstOrDefault(value =>
            normalized.StartsWith(value, StringComparison.OrdinalIgnoreCase));
        if (prefix is null)
        {
            distribution = "";
            linuxPath = "";
            return false;
        }
        var parts = normalized[prefix.Length..]
            .Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0)
        {
            distribution = "";
            linuxPath = "";
            return false;
        }
        distribution = parts[0];
        linuxPath = "/" + string.Join('/', parts.Skip(1));
        return true;
    }

    private static PlatformLaunchPlan BrowserPlan(JsonElement effect, string url)
    {
        var identifier = "";
        var profile = "";
        if (JsonModel.Object(effect, "browser", out var browser))
        {
            identifier = JsonModel.String(browser, "bundleIdentifier") ?? "";
            profile = JsonModel.String(browser, "profileDirectory") ?? "";
        }
        return BrowserPlan(url, identifier, profile);
    }

    private static bool ExecutableExists(string name)
    {
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        if (path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries)
            .Any(folder => File.Exists(Path.Combine(folder, name))))
        {
            return true;
        }
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return File.Exists(Path.Combine(local, "Microsoft", "WindowsApps", name));
    }

    private static void Start(PlatformLaunchPlan plan)
    {
        var startInfo = new ProcessStartInfo(TerminalExecutable(plan.Executable))
        {
            UseShellExecute = plan.UseShellExecute,
        };
        foreach (var argument in plan.Arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        _ = Process.Start(startInfo);
    }

    public static string TerminalExecutable(
        string executable, string? searchPath = null, string? programFiles = null, Func<string, bool>? exists = null)
    {
        if (!executable.Equals("pwsh.exe", StringComparison.OrdinalIgnoreCase)) return executable;
        exists ??= File.Exists;
        searchPath ??= Environment.GetEnvironmentVariable("Path") + Path.PathSeparator +
            Environment.ExpandEnvironmentVariables(
                Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.Machine) + Path.PathSeparator +
                Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User));
        var folders = searchPath.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
        var candidates = folders.Select(folder => Path.Combine(folder, executable)).Append(
            Path.Combine(programFiles ?? Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", executable));
        return candidates.FirstOrDefault(candidate => exists(candidate)) ?? executable;
    }
}
