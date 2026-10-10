using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace DevDeck.Shell;

public sealed record WindowsBrowserOption(
    string Name,
    string? Identifier,
    string? Executable,
    string? LocalStatePath)
{
    public bool SupportsProfiles => LocalStatePath is not null;
}

public sealed record WindowsBrowserProfile(string Directory, string Name);

public static class WindowsBrowserCatalog
{
    private const string ClientsKey = @"SOFTWARE\Clients\StartMenuInternet";

    // Chromium vendors keep Local State under fixed directories in Local AppData.
    private static readonly IReadOnlyDictionary<string, string> ChromiumLocalStatePaths =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["msedge.exe"] = @"Microsoft\Edge\User Data\Local State",
            ["chrome.exe"] = @"Google\Chrome\User Data\Local State",
            ["brave.exe"] = @"BraveSoftware\Brave-Browser\User Data\Local State",
            ["vivaldi.exe"] = @"Vivaldi\User Data\Local State",
        };

    public static IReadOnlyList<WindowsBrowserOption> Installed()
    {
        var options = new List<WindowsBrowserOption>();
        var systemName = Association(4);
        if (systemName.Length == 0)
        {
            systemName = Path.GetFileNameWithoutExtension(Association(2));
        }
        if (systemName.Length > 0)
        {
            options.Add(new WindowsBrowserOption(systemName, null, null, null));
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

    public static WindowsBrowserOption? Resolve(
        string? identifier,
        IReadOnlyList<WindowsBrowserOption>? installed = null)
    {
        if (string.IsNullOrWhiteSpace(identifier))
        {
            return null;
        }
        var found = (installed ?? Installed()).FirstOrDefault(option =>
            string.Equals(option.Identifier, identifier, StringComparison.OrdinalIgnoreCase));
        if (found is not null)
        {
            return found;
        }

        // W-10 stored the executable before the registry identifier became the contract.
        return Path.IsPathFullyQualified(identifier)
            ? Option(Path.GetFileNameWithoutExtension(identifier), identifier, identifier)
            : null;
    }

    public static IReadOnlyList<WindowsBrowserProfile> Profiles(WindowsBrowserOption option)
    {
        if (option.LocalStatePath is null || !File.Exists(option.LocalStatePath))
        {
            return [];
        }
        try
        {
            return ParseProfiles(File.ReadAllText(option.LocalStatePath));
        }
        catch (IOException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }
    }

    public static IReadOnlyList<WindowsBrowserProfile> ParseProfiles(string localState)
    {
        try
        {
            using var document = JsonDocument.Parse(localState);
            if (!document.RootElement.TryGetProperty("profile", out var profile) ||
                !profile.TryGetProperty("info_cache", out var cache) ||
                cache.ValueKind != JsonValueKind.Object)
            {
                return [];
            }
            return cache.EnumerateObject()
                .Select(entry => new WindowsBrowserProfile(
                    entry.Name,
                    ProfileName(entry.Value, entry.Name)))
                .OrderBy(profile => ProfileOrder(profile.Directory))
                .ThenBy(profile => profile.Directory, StringComparer.OrdinalIgnoreCase)
                .ToArray();
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private static string ProfileName(JsonElement value, string directory)
    {
        if (value.ValueKind == JsonValueKind.Object &&
            value.TryGetProperty("name", out var name) &&
            name.ValueKind == JsonValueKind.String &&
            !string.IsNullOrWhiteSpace(name.GetString()))
        {
            return name.GetString() ?? directory;
        }
        return directory;
    }

    private static int ProfileOrder(string directory)
    {
        if (directory.Equals("Default", StringComparison.OrdinalIgnoreCase))
        {
            return 0;
        }
        const string prefix = "Profile ";
        return directory.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) &&
            int.TryParse(directory[prefix.Length..], out var number)
            ? number + 1
            : int.MaxValue;
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
                options.Add(Option(name, keyName, executable));
            }
        }
    }

    private static WindowsBrowserOption Option(string name, string identifier, string executable)
    {
        var fileName = Path.GetFileName(executable);
        var localState = ChromiumLocalStatePaths.TryGetValue(fileName, out var relative)
            ? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                relative)
            : null;
        return new WindowsBrowserOption(name, identifier, executable, localState);
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
        var executableEnd = value.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
        if (executableEnd >= 0)
        {
            return value[..(executableEnd + 4)];
        }
        var space = value.IndexOf(' ');
        return space < 0 ? value : value[..space];
    }

    private static string Association(uint value)
    {
        uint length = 0;
        _ = AssocQueryString(0, value, "https", null, null, ref length);
        if (length == 0)
        {
            return "";
        }
        var output = new StringBuilder((int)length);
        return AssocQueryString(0, value, "https", null, output, ref length) == 0
            ? output.ToString()
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
