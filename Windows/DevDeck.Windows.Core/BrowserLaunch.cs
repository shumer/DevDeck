using System.Diagnostics;
using System.ComponentModel;
using System.Security;

namespace DevDeck.Windows.Core;

public static class BrowserLaunch
{
    public static string[] Choices => BrowserCatalog.Choices;
    public static ProcessStartInfo Create(string browser, string? profile, string address, Func<string,string?>? resolveExecutable = null)
    {
        var arguments = Arguments(browser, profile, address);
        if (browser == "system") return new ProcessStartInfo(arguments[0]) { UseShellExecute = true };
        var executable = (resolveExecutable ?? BrowserCatalog.ResolveExecutable)(browser);
        if (executable is null) return new ProcessStartInfo(arguments[^1]) { UseShellExecute = true };
        var start = new ProcessStartInfo(executable) { UseShellExecute = false };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        return start;
    }
    public static void Open(string browser, string? profile, string address, Func<string,string?>? resolveExecutable = null, Action<ProcessStartInfo>? start = null)
    {
        start ??= info => Process.Start(info)?.Dispose();
        var selected = Create(browser, profile, address, resolveExecutable);
        if (selected.UseShellExecute) { start(selected); return; }
        try { start(selected); }
        catch (Exception error) when (error is Win32Exception or InvalidOperationException or IOException or UnauthorizedAccessException or SecurityException) {
            start(Create("system", null, address));
        }
    }
    public static string[] Arguments(string browser, string? profile, string address)
    {
        if (!Choices.Contains(browser) || profile?.Any(char.IsControl) == true || profile?.Length > 256
            || address.Any(char.IsControl) || !Uri.TryCreate(address, UriKind.Absolute, out var url) || url.Scheme is not ("http" or "https") || url.UserInfo.Length > 0)
            throw new ArgumentException("Choose a valid browser profile and HTTP(S) link.");
        if (!BrowserCatalog.SupportsProfiles(browser) || string.IsNullOrWhiteSpace(profile)) return [url.AbsoluteUri];
        return ["--profile-directory=" + profile, url.AbsoluteUri];
    }
}
