using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;

namespace DevDeck.Windows.Core;

/// Opt-in per-user startup; each configuration owns a separately identified shortcut.
[SupportedOSPlatform("windows")]
public static class StartupShortcut
{
    public const string Description = "DevDeck Windows startup schema 1";
    public static string Name(string settings) => "DevDeck-" + Convert.ToHexString(SHA256.HashData(
        Encoding.UTF8.GetBytes(Path.GetFullPath(settings).ToUpperInvariant())))[..20] + ".lnk";
    public static bool IsEnabled(string directory, string settings)
    {
        var path = Path.Combine(directory, Name(settings));
        if (!File.Exists(path) || File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) return false;
        try { return WithShortcut(path, shortcut => (string)shortcut.Description == Description && (string)shortcut.Arguments == Arguments(settings)); }
        catch (COMException) { return false; }
    }
    public static void Set(string directory, string executable, string settings, bool enabled)
    {
        executable = Path.GetFullPath(executable); settings = Path.GetFullPath(settings);
        if (executable.StartsWith("\\\\", StringComparison.Ordinal) || settings.StartsWith("\\\\", StringComparison.Ordinal))
            throw new InvalidDataException("Startup requires a local Windows installation and settings.");
        var path = Path.Combine(directory, Name(settings));
        if (File.Exists(path) && !IsEnabled(directory, settings)) throw new IOException("The startup shortcut belongs to another application. Inspect it before replacing it.");
        if (!enabled) { if (File.Exists(path)) File.Delete(path); return; }
        if (!File.Exists(executable)) throw new FileNotFoundException("The Windows executable is missing.");
        Directory.CreateDirectory(directory);
        var temporary = Path.Combine(directory, "DevDeck-" + Guid.NewGuid().ToString("N") + ".lnk");
        try
        {
            WithShortcut(temporary, shortcut => {
                shortcut.TargetPath = executable; shortcut.Arguments = Arguments(settings);
                shortcut.WorkingDirectory = Path.GetDirectoryName(executable);
                shortcut.Description = Description; shortcut.Save(); return true;
            });
            File.Move(temporary, path, overwrite: true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    private static string Arguments(string settings) => "--settings \"" + Path.GetFullPath(settings) + "\"";
    private static T WithShortcut<T>(string path, Func<dynamic, T> action)
    {
        var type = Type.GetTypeFromProgID("WScript.Shell") ?? throw new IOException("Windows shortcut support is unavailable.");
        var shell = Activator.CreateInstance(type)!;
        object? shortcut = null;
        try { shortcut = ((dynamic)shell).CreateShortcut(path); return action(shortcut); }
        finally
        {
            if (shortcut is not null) Marshal.FinalReleaseComObject(shortcut);
            Marshal.FinalReleaseComObject(shell);
        }
    }
}
