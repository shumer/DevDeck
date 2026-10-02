using System;
using System.IO;
using System.Reflection;
using System.Security;

namespace DevDeck.Windows.App;

// Facts about this process's loaded App, captured before Application startup.
// No sidecar, file existence, package trust or release qualification is inferred.
internal sealed record RunningBuildInfo
{
    internal const int MaximumVersionLength = 2048;
    internal const int MaximumPathLength = 32768;

    internal string? InformationalVersion { get; }
    internal string? AssemblyVersion { get; }
    internal Guid? ModuleVersionID { get; }
    internal string? ExecutablePath { get; }
    internal string? ModulePath { get; }
    // An assembly-version or localized display fallback is never updater input.
    internal string? VersionForUpdates => InformationalVersion;

    internal RunningBuildInfo(string? informationalVersion, string? assemblyVersion,
        Guid? moduleVersionID, string? executablePath, string? modulePath)
    {
        InformationalVersion = AcceptedText(informationalVersion, MaximumVersionLength);
        AssemblyVersion = AcceptedText(assemblyVersion, MaximumVersionLength);
        ModuleVersionID = moduleVersionID is { } identifier && identifier != Guid.Empty ? identifier : null;
        ExecutablePath = AcceptedText(executablePath, MaximumPathLength);
        ModulePath = AcceptedText(modulePath, MaximumPathLength);
    }

    internal static RunningBuildInfo Unknown { get; } = new(null, null, null, null, null);
    private static readonly object startupGate = new();
    private static RunningBuildInfo startup = Unknown;
    private static bool initialized;
    internal static RunningBuildInfo Startup { get { lock (startupGate) return startup; } }

    // Main owns the single call; repeated calls cannot replace the original loaded-copy facts.
    internal static bool InitializeStartup()
    {
        lock (startupGate) {
            if (initialized) return false;
            startup = CaptureCurrent(); initialized = true; return true;
        }
    }

    internal static RunningBuildInfo CaptureCurrent()
    {
        var app = typeof(SettingsWindow).Assembly;
        return Capture(
            () => app.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion,
            () => app.GetName().Version?.ToString(),
            () => app.ManifestModule.ModuleVersionId,
            () => Environment.ProcessPath,
            () => app.Location);
    }

    // Also admits bounded owned reader fixtures; production readers are the loaded metadata above.
    internal static RunningBuildInfo Capture(Func<string?> informationalVersion, Func<string?> assemblyVersion,
        Func<Guid> moduleVersionID, Func<string?> executablePath, Func<string?> modulePath) => new(
            Read(informationalVersion), Read(assemblyVersion), ReadID(moduleVersionID), Read(executablePath), Read(modulePath));

    private static string? Read(Func<string?> read)
    {
        try { return read(); }
        catch (Exception error) when (MetadataUnavailable(error)) { return null; }
    }
    private static Guid? ReadID(Func<Guid> read)
    {
        try { return read(); }
        catch (Exception error) when (MetadataUnavailable(error)) { return null; }
    }
    private static bool MetadataUnavailable(Exception error) => error is
        NotSupportedException or InvalidOperationException or ArgumentException or SecurityException
        or IOException or UnauthorizedAccessException or CustomAttributeFormatException or TypeLoadException;

    private static string? AcceptedText(string? value, int maximum)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > maximum) return null;
        for (var index = 0; index < value.Length; index++) {
            var character = value[index];
            if (char.IsControl(character)) return null;
            if (char.IsHighSurrogate(character)) {
                if (index + 1 == value.Length || !char.IsLowSurrogate(value[index + 1])) return null;
                index++;
            } else if (char.IsLowSurrogate(character)) return null;
        }
        return value;
    }
}
