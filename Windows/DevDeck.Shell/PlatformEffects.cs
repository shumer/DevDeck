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
                    TerminalPlan(folder, ExecutableExists("wt.exe")),
                "revealFolder" when JsonModel.String(effect, "folder") is { } folder =>
                    new PlatformLaunchPlan("explorer.exe", [folder], true),
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

    public static PlatformLaunchPlan TerminalPlan(string folder, bool windowsTerminalAvailable)
    {
        if (TryWslFolder(folder, out var distribution, out var linuxPath))
        {
            var arguments = new[] { "wsl.exe", "-d", distribution, "--cd", linuxPath };
            return windowsTerminalAvailable
                ? new PlatformLaunchPlan("wt.exe", arguments)
                : new PlatformLaunchPlan("wsl.exe", arguments[1..], true);
        }
        return windowsTerminalAvailable
            ? new PlatformLaunchPlan("wt.exe", ["-d", folder])
            : new PlatformLaunchPlan("cmd.exe", ["/K", "cd", "/d", folder], true);
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
        var startInfo = new ProcessStartInfo(plan.Executable)
        {
            UseShellExecute = plan.UseShellExecute,
        };
        foreach (var argument in plan.Arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        _ = Process.Start(startInfo);
    }
}
