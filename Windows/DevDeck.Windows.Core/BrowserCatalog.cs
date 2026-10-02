using System.Runtime.Versioning;
using System.Security;
using System.Text.Json;
using Microsoft.Win32;

namespace DevDeck.Windows.Core;

public sealed record InstalledBrowser(string ID, string Name, string Executable, bool SupportsProfiles);
public sealed record BrowserProfile(string Directory, string Name);
public sealed record BrowserRegistration(string BrowserID, string Command);

/// <summary>Read-only installed-browser discovery and Chromium profile-name metadata.</summary>
public static class BrowserCatalog
{
    public const int MaximumLocalStateBytes = 4 * 1024 * 1024;
    private sealed record Definition(string ID, string Name, string[] Executables, string[] RelativePaths, string? UserData);
    private static readonly Definition[] definitions = [
        new("edge", "Microsoft Edge", ["msedge.exe"], ["Microsoft/Edge/Application/msedge.exe"], "Microsoft/Edge/User Data"),
        new("chrome", "Google Chrome", ["chrome.exe"], ["Google/Chrome/Application/chrome.exe"], "Google/Chrome/User Data"),
        new("firefox", "Firefox", ["firefox.exe"], ["Mozilla Firefox/firefox.exe", "Programs/Mozilla Firefox/firefox.exe"], null),
        new("brave", "Brave", ["brave.exe"], ["BraveSoftware/Brave-Browser/Application/brave.exe"], "BraveSoftware/Brave-Browser/User Data"),
        new("vivaldi", "Vivaldi", ["vivaldi.exe"], ["Vivaldi/Application/vivaldi.exe"], "Vivaldi/User Data"),
        new("chromium", "Chromium", ["chrome.exe", "chromium.exe"], ["Chromium/Application/chrome.exe", "Chromium/Application/chromium.exe"], "Chromium/User Data")
    ];

    public static string[] Choices => ["system", .. definitions.Select(browser => browser.ID)];
    public static string Name(string browserID) => definitions.FirstOrDefault(browser => browser.ID == browserID)?.Name ?? browserID;
    public static bool SupportsProfiles(string browserID) => definitions.Any(browser => browser.ID == browserID && browser.UserData is not null);

    public static InstalledBrowser[] InstalledBrowsers()
    {
        var registrations = OperatingSystem.IsWindows() ? RegisteredBrowsers() : [];
        var roots = new[] {
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)
        };
        return Discover(registrations, roots, File.Exists);
    }

    // Registry entries are only candidates: the executable must exist and have the expected
    // browser filename. Registered arguments never become launch arguments.
    public static InstalledBrowser[] Discover(IEnumerable<BrowserRegistration> registrations, IEnumerable<string> roots, Func<string,bool> exists)
    {
        var entries = registrations.ToArray();
        var locations = roots.Where(root => !string.IsNullOrWhiteSpace(root)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var result = new List<InstalledBrowser>();
        foreach (var browser in definitions) {
            var candidates = entries.Where(entry => entry.BrowserID == browser.ID).Select(entry => ExecutableFromCommand(entry.Command))
                .Concat(locations.SelectMany(root => browser.RelativePaths.Select(relative => Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)))));
            var executable = candidates.FirstOrDefault(path => path is not null && Path.IsPathRooted(path)
                && browser.Executables.Contains(Path.GetFileName(path), StringComparer.OrdinalIgnoreCase) && exists(path));
            if (executable is not null) result.Add(new(browser.ID, browser.Name, executable, browser.UserData is not null));
        }
        return result.OrderBy(browser => browser.Name, StringComparer.CurrentCultureIgnoreCase).ToArray();
    }

    public static string? ExecutableFromCommand(string? command)
    {
        if (string.IsNullOrWhiteSpace(command) || command.Length > 32768 || command.Any(char.IsControl)) return null;
        var value = Environment.ExpandEnvironmentVariables(command.Trim());
        if (value.StartsWith('"')) {
            var closing = value.IndexOf('"', 1);
            if (closing < 0) return null;
            value = value[1..closing];
        } else {
            var end = value.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
            if (end < 0) return null;
            value = value[..(end + 4)].Trim();
        }
        if (!value.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) || value.Contains('"') || !Path.IsPathRooted(value)) return null;
        return value;
    }

    public static string? ResolveExecutable(string browserID) => InstalledBrowsers().FirstOrDefault(browser => browser.ID == browserID)?.Executable;

    public static BrowserProfile[] Profiles(string browserID)
    {
        var relative = definitions.FirstOrDefault(browser => browser.ID == browserID)?.UserData;
        if (relative is null) return [];
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (root.Length == 0) return [];
        return ReadProfiles(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar), "Local State"));
    }

    public static BrowserProfile[] ReadProfiles(string localState)
    {
        try {
            using var stream = new FileStream(localState, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (stream.Length <= 0 || stream.Length > MaximumLocalStateBytes) return [];
            using var bytes = new MemoryStream((int)stream.Length);
            var buffer = new byte[8192];
            while (true) {
                var count = stream.Read(buffer, 0, buffer.Length);
                if (count == 0) break;
                if (bytes.Length + count > MaximumLocalStateBytes) return [];
                bytes.Write(buffer, 0, count);
            }
            return ParseProfiles(bytes.ToArray());
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException or ArgumentException or NotSupportedException) { return []; }
    }

    public static BrowserProfile[] ParseProfiles(byte[] data)
    {
        if (data.Length > MaximumLocalStateBytes) return [];
        try {
            using var document = JsonDocument.Parse(data);
            if (document.RootElement.ValueKind != JsonValueKind.Object || !document.RootElement.TryGetProperty("profile", out var profile)
                || profile.ValueKind != JsonValueKind.Object || !profile.TryGetProperty("info_cache", out var cache) || cache.ValueKind != JsonValueKind.Object) return [];
            var entries = cache.EnumerateObject().Take(257).ToArray();
            if (entries.Length > 256) return [];
            var results = new Dictionary<string,BrowserProfile>(StringComparer.Ordinal);
            foreach (var entry in entries) {
                var directory = entry.Name;
                if (string.IsNullOrWhiteSpace(directory) || directory.Length > 256 || directory.Any(char.IsControl)
                    || directory.Contains('/') || directory.Contains('\\') || directory is "." or "..") continue;
                var name = entry.Value.ValueKind == JsonValueKind.Object && entry.Value.TryGetProperty("name", out var named) && named.ValueKind == JsonValueKind.String
                    ? named.GetString() : null;
                if (string.IsNullOrEmpty(name) || name.Length > 512 || name.Any(char.IsControl)) name = directory;
                results[directory] = new(directory, name);
            }
            return results.Values.OrderBy(value => value.Directory, Comparer<string>.Create(CompareDirectories)).ToArray();
        }
        catch (JsonException) { return []; }
    }

    private static int CompareDirectories(string left, string right)
    {
        if (left == right) return 0;
        if (left == "Default") return -1;
        if (right == "Default") return 1;
        var a = 0; var b = 0;
        while (a < left.Length && b < right.Length) {
            if (char.IsAsciiDigit(left[a]) && char.IsAsciiDigit(right[b])) {
                var aEnd = a; while (aEnd < left.Length && char.IsAsciiDigit(left[aEnd])) aEnd++;
                var bEnd = b; while (bEnd < right.Length && char.IsAsciiDigit(right[bEnd])) bEnd++;
                var aDigits = left[a..aEnd].TrimStart('0'); var bDigits = right[b..bEnd].TrimStart('0');
                var comparison = aDigits.Length.CompareTo(bDigits.Length);
                if (comparison == 0) comparison = string.Compare(aDigits, bDigits, StringComparison.Ordinal);
                if (comparison != 0) return comparison;
                a = aEnd; b = bEnd;
            } else {
                var comparison = char.ToUpperInvariant(left[a]).CompareTo(char.ToUpperInvariant(right[b]));
                if (comparison != 0) return comparison;
                a++; b++;
            }
        }
        var length = left.Length.CompareTo(right.Length);
        return length == 0 ? string.Compare(left, right, StringComparison.Ordinal) : length;
    }

    [SupportedOSPlatform("windows")]
    private static BrowserRegistration[] RegisteredBrowsers()
    {
        var result = new List<BrowserRegistration>();
        foreach (var hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
            foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 }) {
                try {
                    using var registry = RegistryKey.OpenBaseKey(hive, view);
                    foreach (var browser in definitions) foreach (var executable in browser.Executables) {
                        // Chrome and Chromium share chrome.exe. Only a Chromium-specific entry
                        // can identify Chromium; otherwise Chrome would appear twice.
                        if (browser.ID == "chromium" && executable == "chrome.exe") continue;
                        using var entry = registry.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\App Paths\" + executable, writable: false);
                        if (entry?.GetValue("", null, RegistryValueOptions.DoNotExpandEnvironmentNames) is string path)
                            result.Add(new(browser.ID, path));
                    }
                    using var clients = registry.OpenSubKey(@"Software\Clients\StartMenuInternet", writable: false);
                    foreach (var key in clients?.GetSubKeyNames() ?? []) {
                        var browserID = ClientBrowserID(key);
                        if (browserID is null) continue;
                        using var entry = clients!.OpenSubKey(key + @"\shell\open\command", writable: false);
                        if (entry?.GetValue("", null, RegistryValueOptions.DoNotExpandEnvironmentNames) is string command)
                            result.Add(new(browserID, command));
                    }
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException or ArgumentException) { }
            }
        return result.ToArray();
    }

    private static string? ClientBrowserID(string value)
    {
        foreach (var browser in new[] { "chromium", "brave", "vivaldi", "firefox", "edge", "chrome" })
            if (value.Contains(browser, StringComparison.OrdinalIgnoreCase)) return browser;
        return null;
    }
}
