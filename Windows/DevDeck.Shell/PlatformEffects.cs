using System.Diagnostics;
using System.Text.Json;

namespace DevDeck.Shell;

public static class PlatformEffects
{
    public static void Apply(JsonElement effect)
    {
        var kind = JsonModel.String(effect, "kind");
        try
        {
            switch (kind)
            {
                case "openURL" when JsonModel.String(effect, "url") is { } url:
                    _ = Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
                    break;
                case "openTerminal" when JsonModel.String(effect, "folder") is { } terminalFolder:
                    Start("wt.exe", "-d", terminalFolder);
                    break;
                case "revealFolder" when JsonModel.String(effect, "folder") is { } revealFolder:
                    Start("explorer.exe", revealFolder);
                    break;
                default:
                    Console.Error.WriteLine($"Ignored engine effect: {kind ?? "unknown"}.");
                    break;
            }
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            Console.Error.WriteLine($"Engine effect failed: {kind ?? "unknown"}.");
        }
    }

    private static void Start(string executable, params string[] arguments)
    {
        var startInfo = new ProcessStartInfo(executable) { UseShellExecute = true };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        _ = Process.Start(startInfo);
    }
}
