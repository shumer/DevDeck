using System.Diagnostics;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;

namespace DevDeck.Shell;

public sealed record WindowsUpdate(string Version, string Asset, long Size, string Page, string? Checksum)
{
    public static WindowsUpdate Parse(JsonElement effect)
    {
        var update = effect.GetProperty("update");
        return new WindowsUpdate(
            DeckEvent.RequiredString(update, "version"),
            DeckEvent.RequiredString(update, "asset"),
            update.GetProperty("size").GetInt64(),
            DeckEvent.RequiredString(update, "page"),
            DeckEvent.OptionalString(update, "checksum"));
    }
}

public interface IUpdateDownloader
{
    Task DownloadAsync(Uri address, string destination, Func<long, Task> received, CancellationToken cancellation);
}

public sealed class HttpUpdateDownloader : IUpdateDownloader, IDisposable
{
    private readonly HttpClient client = new(new HttpClientHandler { AllowAutoRedirect = true })
    {
        Timeout = Timeout.InfiniteTimeSpan,
    };

    public async Task DownloadAsync(
        Uri address,
        string destination,
        Func<long, Task> received,
        CancellationToken cancellation)
    {
        using var response = await client.GetAsync(address, HttpCompletionOption.ResponseHeadersRead, cancellation)
            .ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        await using var input = await response.Content.ReadAsStreamAsync(cancellation).ConfigureAwait(false);
        await using var output = new FileStream(
            destination, FileMode.Create, FileAccess.Write, FileShare.None, 65536, FileOptions.Asynchronous);
        var buffer = new byte[65536];
        long total = 0;
        int count;
        while ((count = await input.ReadAsync(buffer, cancellation).ConfigureAwait(false)) != 0)
        {
            await output.WriteAsync(buffer.AsMemory(0, count), cancellation).ConfigureAwait(false);
            total += count;
            await received(total).ConfigureAwait(false);
        }
    }

    public void Dispose()
    {
        client.Dispose();
    }
}

public sealed class WindowsUpdater
{
    private readonly IUpdateDownloader downloader;
    private readonly Func<string, double?, string?, Task> report;
    private readonly Action<PlatformLaunchPlan> launch;
    private readonly string updatesFolder;
    private readonly TimeProvider clock;
    private int active;

    public WindowsUpdater(
        IUpdateDownloader downloader,
        Func<string, double?, string?, Task> report,
        Action<PlatformLaunchPlan>? launch = null,
        string? updatesFolder = null,
        TimeProvider? clock = null)
    {
        this.downloader = downloader;
        this.report = report;
        this.launch = launch ?? LaunchInstaller;
        this.updatesFolder = updatesFolder ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DevDeck", "Updates");
        this.clock = clock ?? TimeProvider.System;
    }

    public async Task InstallAsync(WindowsUpdate update, CancellationToken cancellation)
    {
        // The engine owns retries, but two effects must not write the same file concurrently.
        if (Interlocked.CompareExchange(ref active, 1, 0) != 0)
        {
            return;
        }
        try
        {
            if (string.IsNullOrWhiteSpace(update.Checksum))
            {
                await report("update.failed", null, "installer is not verified").ConfigureAwait(false);
                return;
            }

            var asset = DownloadAddress(update.Asset);
            var checksum = DownloadAddress(update.Checksum);
            var folder = VersionFolder(update.Version);
            var name = Path.GetFileName(asset.LocalPath);
            if (name.Length == 0 || name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 ||
                !name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("invalid installer filename");
            }
            Directory.CreateDirectory(folder);
            var installer = Path.Combine(folder, name);
            var checksumFile = installer + ".sha256";
            await downloader.DownloadAsync(checksum, checksumFile, _ => Task.CompletedTask, cancellation)
                .ConfigureAwait(false);

            await report("update.progress", 0, null).ConfigureAwait(false);
            var lastProgress = clock.GetTimestamp();
            await downloader.DownloadAsync(asset, installer, async bytes =>
            {
                if (clock.GetElapsedTime(lastProgress) < TimeSpan.FromMilliseconds(100))
                {
                    return;
                }
                var fraction = update.Size > 0 ? Math.Clamp((double)bytes / update.Size, 0, 1) : 0;
                await report("update.progress", fraction, null).ConfigureAwait(false);
                lastProgress = clock.GetTimestamp();
            }, cancellation).ConfigureAwait(false);

            if (!await ChecksumMatchesAsync(installer, checksumFile, cancellation).ConfigureAwait(false))
            {
                File.Delete(installer);
                await report("update.failed", null, "checksum mismatch").ConfigureAwait(false);
                return;
            }

            cancellation.ThrowIfCancellationRequested();
            await report("update.installing", null, null).ConfigureAwait(false);
            launch(InstallerPlan(installer));
            // A successful installer closes this instance through its existing quit pipe.
            await Task.Delay(TimeSpan.FromSeconds(60), clock, cancellation).ConfigureAwait(false);
            await report("update.failed", null, $"installer did not finish; see {update.Page}").ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
        }
        catch (HttpRequestException exception)
        {
            var reason = exception.StatusCode is { } status ? $"download failed ({(int)status})" : "download failed";
            await report("update.failed", null, reason).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            await report("update.failed", null, exception.Message).ConfigureAwait(false);
        }
        finally
        {
            Volatile.Write(ref active, 0);
        }
    }

    public static string? StatedChecksum(string text)
    {
        var line = text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        var word = line?.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        return word is { Length: 64 } && word.All(char.IsAsciiHexDigit) ? word.ToLowerInvariant() : null;
    }

    public static async Task<bool> ChecksumMatchesAsync(
        string installer, string checksumFile, CancellationToken cancellation = default)
    {
        var stated = StatedChecksum(await File.ReadAllTextAsync(checksumFile, cancellation).ConfigureAwait(false));
        if (stated is null)
        {
            return false;
        }
        await using var input = File.OpenRead(installer);
        var actual = Convert.ToHexString(await SHA256.HashDataAsync(input, cancellation).ConfigureAwait(false));
        return actual.Equals(stated, StringComparison.OrdinalIgnoreCase);
    }

    public static PlatformLaunchPlan InstallerPlan(string installer)
    {
        return new PlatformLaunchPlan(installer,
            ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/CLOSEAPPLICATIONS"], true);
    }

    private string VersionFolder(string version)
    {
        if (version.Length == 0 || version is "." or ".." || version.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
        {
            throw new InvalidOperationException("invalid update version");
        }
        return Path.Combine(updatesFolder, version);
    }

    private static Uri DownloadAddress(string text)
    {
        var address = new Uri(text, UriKind.Absolute);
        if (address.Scheme is not ("https" or "http"))
        {
            throw new InvalidOperationException("invalid download address");
        }
        return address;
    }

    private static void LaunchInstaller(PlatformLaunchPlan plan)
    {
        var startInfo = new ProcessStartInfo(plan.Executable) { UseShellExecute = plan.UseShellExecute };
        foreach (var argument in plan.Arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("installer could not start");
    }
}
