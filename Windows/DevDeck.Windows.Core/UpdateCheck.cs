using System.Net.Http.Headers;
using System.Text.Json;

namespace DevDeck.Windows.Core;

public sealed record WindowsUpdate(string Version, string PageURL, string DownloadURL, string? Digest);
public static class WindowsUpdateCheck
{
    public const string Repository = "shumer/DevDeck";
    public static WindowsUpdate? Select(JsonElement release, string current, string runtime)
    {
        if (runtime is not ("win-arm64" or "win-x64") || release.GetProperty("draft").GetBoolean() || release.GetProperty("prerelease").GetBoolean()) return null;
        var tag = release.GetProperty("tag_name").GetString()!;
        var latestText = tag.TrimStart('v', 'V');
        if (!Version.TryParse(latestText, out var latest) || !Version.TryParse(current.Split('-')[0].Split('+')[0], out var running)
            || Normalize(latest) <= Normalize(running)) return null;
        var name = "Windows-DevDeck-" + latestText + "-" + runtime + ".zip";
        foreach (var asset in release.GetProperty("assets").EnumerateArray())
        {
            if (asset.GetProperty("name").GetString() != name) continue;
            var download = asset.GetProperty("browser_download_url").GetString()!;
            var page = release.GetProperty("html_url").GetString()!;
            if (!IsReleaseURL(download, "/releases/download/") || !IsReleaseURL(page, "/releases/tag/")) continue;
            return new WindowsUpdate(latestText, page, download, asset.TryGetProperty("digest", out var digest) ? digest.GetString() : null);
        }
        return null;
    }
    private static Version Normalize(Version value) => new(value.Major, value.Minor, Math.Max(0, value.Build), Math.Max(0, value.Revision));
    private static bool IsReleaseURL(string value, string prefix) => Uri.TryCreate(value, UriKind.Absolute, out var uri)
        && uri.Scheme == "https" && uri.Host == "github.com" && uri.IsDefaultPort && string.IsNullOrEmpty(uri.UserInfo)
        && string.IsNullOrEmpty(uri.Query) && string.IsNullOrEmpty(uri.Fragment)
        && uri.AbsolutePath.StartsWith("/" + Repository + prefix, StringComparison.Ordinal);
    public static async Task<WindowsUpdate?> CheckAsync(string current, string runtime, CancellationToken cancellation = default)
    {
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("DevDeck-Windows", "1.0"));
        http.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        using var response = await http.GetAsync("https://api.github.com/repos/" + Repository + "/releases/latest", cancellation);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound) return null;
        response.EnsureSuccessStatusCode();
        using var document = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(cancellation));
        return Select(document.RootElement, current, runtime);
    }
}
