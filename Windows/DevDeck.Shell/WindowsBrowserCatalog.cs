using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Text;

namespace DevDeck.Shell;

public sealed record WindowsBrowserOption(string Name, string? Identifier);

public static class WindowsBrowserCatalog
{
    private const string ClientsKey = @"SOFTWARE\Clients\StartMenuInternet";

    public static IReadOnlyList<WindowsBrowserOption> Installed()
    {
        var options = new List<WindowsBrowserOption>();
        var systemName = SystemDefaultName();
        if (systemName.Length > 0)
        {
            options.Add(new WindowsBrowserOption(systemName, null));
        }

        foreach (var hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
        {
            foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
            {
                AddInstalled(options, hive, view);
            }
        }

        return options
            .GroupBy(option => option.Identifier ?? "", StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .ToArray();
    }

    private static void AddInstalled(
        List<WindowsBrowserOption> options,
        RegistryHive hive,
        RegistryView view)
    {
        using var baseKey = RegistryKey.OpenBaseKey(hive, view);
        using var clients = baseKey.OpenSubKey(ClientsKey);
        if (clients is null)
        {
            return;
        }

        foreach (var keyName in clients.GetSubKeyNames())
        {
            using var browser = clients.OpenSubKey(keyName);
            using var command = browser?.OpenSubKey(@"shell\open\command");
            var name = browser?.GetValue(null) as string;
            var executable = Executable(command?.GetValue(null) as string);
            if (!string.IsNullOrWhiteSpace(name) && executable.Length > 0)
            {
                options.Add(new WindowsBrowserOption(name, executable));
            }
        }
    }

    private static string Executable(string? command)
    {
        if (string.IsNullOrWhiteSpace(command))
        {
            return "";
        }
        var value = Environment.ExpandEnvironmentVariables(command.Trim());
        if (value.StartsWith('"'))
        {
            var end = value.IndexOf('"', 1);
            return end > 1 ? value[1..end] : "";
        }
        var space = value.IndexOf(' ');
        return space < 0 ? value : value[..space];
    }

    private static string SystemDefaultName()
    {
        uint length = 0;
        _ = AssocQueryString(0, 4, "https", null, null, ref length);
        if (length == 0)
        {
            return "";
        }
        var value = new StringBuilder((int)length);
        return AssocQueryString(0, 4, "https", null, value, ref length) == 0
            ? value.ToString()
            : "";
    }

    [DllImport("shlwapi.dll", EntryPoint = "AssocQueryStringW", CharSet = CharSet.Unicode)]
    private static extern int AssocQueryString(
        uint flags,
        uint value,
        string association,
        string? extra,
        StringBuilder? output,
        ref uint outputLength);
}
