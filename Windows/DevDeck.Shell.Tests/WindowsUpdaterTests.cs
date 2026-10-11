using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using DevDeck.Shell;

namespace DevDeck.Shell.Tests;

public static class WindowsUpdaterTests
{
    private static readonly byte[] Fixture = Encoding.UTF8.GetBytes("DevDeck installer fixture\n");
    private static readonly string Hash = Convert.ToHexString(SHA256.HashData(Fixture));

    public static void Run(Action<string, Action> run)
    {
        run("update effects accept an optional checksum", EffectsParse);
        run("installer checksums match including uppercase", ChecksumsMatch);
        run("invalid or different installer checksums fail", ChecksumsFail);
        run("installer arguments allow a quiet restart", InstallerArguments);
        run("an unverified installer is never downloaded or launched", MissingChecksum);
        run("a mismatched download is removed without launching", MismatchRemovesInstaller);
        run("download progress is bounded and throttled", ProgressIsThrottled);
        run("an installer launch failure is reported", LaunchFailure);
        run("quit cancels the installer wait without blocking", QuitCancelsWait);
        run("an unfinished installer reports its release page", InstallerTimeout);
        run("update intents carry the contract fields", UpdateIntents);
    }

    private static void EffectsParse()
    {
        using var document = JsonDocument.Parse("""
            {"kind":"installUpdate","update":{"version":"9.0","asset":"https://example.invalid/setup.exe","size":1024,"page":"https://example.invalid/release","checksum":"https://example.invalid/setup.exe.sha256"}}
            """);
        var update = WindowsUpdate.Parse(document.RootElement);
        Require(update.Version == "9.0" && update.Size == 1024 && update.Checksum?.EndsWith(".sha256") == true);
        using var missing = JsonDocument.Parse("""
            {"kind":"installUpdate","update":{"version":"9.0","asset":"https://example.invalid/setup.exe","size":1024,"page":"https://example.invalid/release"}}
            """);
        Require(WindowsUpdate.Parse(missing.RootElement).Checksum is null);
    }

    private static void ChecksumsMatch()
    {
        WithFolder(folder =>
        {
            var installer = Path.Combine(folder, "setup.exe");
            var checksum = installer + ".sha256";
            File.WriteAllBytes(installer, Fixture);
            foreach (var text in new[] { Hash.ToLowerInvariant() + "  setup.exe\n", Hash + "  setup.exe\r\n" })
            {
                File.WriteAllText(checksum, text);
                Require(WindowsUpdater.ChecksumMatchesAsync(installer, checksum).GetAwaiter().GetResult());
            }
        });
    }

    private static void ChecksumsFail()
    {
        WithFolder(folder =>
        {
            var installer = Path.Combine(folder, "setup.exe");
            var checksum = installer + ".sha256";
            File.WriteAllBytes(installer, Fixture);
            foreach (var text in new[] { new string('0', 64), "", "invalid", new string('g', 64) })
            {
                File.WriteAllText(checksum, text);
                Require(!WindowsUpdater.ChecksumMatchesAsync(installer, checksum).GetAwaiter().GetResult());
            }
            Require(WindowsUpdater.StatedChecksum(Hash + "  setup.exe\n" + new string('0', 64)) == Hash.ToLowerInvariant());
        });
    }

    private static void InstallerArguments()
    {
        var plan = WindowsUpdater.InstallerPlan(@"C:\sample folder\setup.exe");
        Require(plan.Executable == @"C:\sample folder\setup.exe" && plan.UseShellExecute);
        Require(plan.Arguments.SequenceEqual(new[]
        {
            "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/CLOSEAPPLICATIONS",
        }));
    }

    private static void MissingChecksum()
    {
        WithFolder(folder =>
        {
            var download = new FixtureDownloader(Hash);
            var reports = new List<Report>();
            var updater = MakeUpdater(folder, download, reports, _ => throw new Exception("must not launch"));
            updater.InstallAsync(Update() with { Checksum = null }, default).GetAwaiter().GetResult();
            Require(download.Calls == 0 && reports.Single() == new Report("update.failed", null, "installer is not verified"));
            Require(!Directory.Exists(Path.Combine(folder, "9.0")));
        });
    }

    private static void MismatchRemovesInstaller()
    {
        WithFolder(folder =>
        {
            var reports = new List<Report>();
            var updater = MakeUpdater(folder, new FixtureDownloader(new string('0', 64)), reports,
                _ => throw new Exception("must not launch"));
            updater.InstallAsync(Update(), default).GetAwaiter().GetResult();
            Require(reports.Last() == new Report("update.failed", null, "checksum mismatch"));
            Require(!File.Exists(Path.Combine(folder, "9.0", "setup.exe")));
        });
    }

    private static void ProgressIsThrottled()
    {
        foreach (var reportingDelay in new[] { 0, 200 })
        {
            WithFolder(folder =>
            {
                using var cancellation = new CancellationTokenSource();
                var clock = new TestClock();
                var reports = new List<Report>();
                var download = new FixtureDownloader(Hash) { Clock = clock };
                var updater = new WindowsUpdater(download, (intent, fraction, reason) =>
                {
                    reports.Add(new Report(intent, fraction, reason));
                    if (intent == "update.progress")
                    {
                        clock.Advance(reportingDelay);
                    }
                    return Task.CompletedTask;
                }, _ => cancellation.Cancel(), folder, clock);
                updater.InstallAsync(Update(), cancellation.Token).GetAwaiter().GetResult();
                var progress = reports.Where(item => item.Intent == "update.progress").ToArray();
                Require(progress.Length == 3);
                Require(progress.Select(item => item.Fraction).SequenceEqual(new double?[] { 0, 0.5, 1 }));
                Require(reports.Last().Intent == "update.installing");
            });
        }
    }

    private static void LaunchFailure()
    {
        WithFolder(folder =>
        {
            var reports = new List<Report>();
            var updater = MakeUpdater(folder, new FixtureDownloader(Hash), reports,
                _ => throw new InvalidOperationException("installer could not start"));
            updater.InstallAsync(Update(), default).GetAwaiter().GetResult();
            Require(reports.TakeLast(2).Select(item => item.Intent)
                .SequenceEqual(new[] { "update.installing", "update.failed" }));
            Require(reports.Last().Reason == "installer could not start");
        });
    }

    private static void QuitCancelsWait()
    {
        WithFolder(folder =>
        {
            using var cancellation = new CancellationTokenSource();
            using var launched = new ManualResetEventSlim();
            var reports = new List<Report>();
            var updater = MakeUpdater(folder, new FixtureDownloader(Hash), reports, _ => launched.Set());
            var pending = updater.InstallAsync(Update(), cancellation.Token);
            Require(launched.Wait(TimeSpan.FromSeconds(3)));
            Require(!pending.IsCompleted);
            cancellation.Cancel();
            pending.WaitAsync(TimeSpan.FromSeconds(1)).GetAwaiter().GetResult();
            Require(!reports.Any(item => item.Intent == "update.failed"));
        });
    }

    private static void InstallerTimeout()
    {
        WithFolder(folder =>
        {
            var clock = new TestClock();
            var reports = new List<Report>();
            var updater = MakeUpdater(folder, new FixtureDownloader(Hash), reports, _ => { }, clock);
            var pending = updater.InstallAsync(Update(), default);
            Require(clock.Ready.Wait(TimeSpan.FromSeconds(3)));
            clock.Advance(60000);
            pending.WaitAsync(TimeSpan.FromSeconds(1)).GetAwaiter().GetResult();
            Require(reports.Last().Reason == "installer did not finish; see https://example.invalid/release");
            Require(File.Exists(Path.Combine(folder, "9.0", "setup.exe")));
        });
    }

    private static void UpdateIntents()
    {
        using var progress = JsonDocument.Parse(ProtocolWriter.Update("1", "update.progress", 0.5));
        Require(progress.RootElement.GetProperty("fraction").GetDouble() == 0.5);
        using var failure = JsonDocument.Parse(ProtocolWriter.Update("2", "update.failed", reason: "checksum mismatch"));
        Require(failure.RootElement.GetProperty("reason").GetString() == "checksum mismatch");
        using var installing = JsonDocument.Parse(ProtocolWriter.Update("3", "update.installing"));
        Require(installing.RootElement.EnumerateObject().Count() == 3);
    }

    private static WindowsUpdate Update()
    {
        return new WindowsUpdate("9.0", "https://example.invalid/setup.exe", Fixture.Length,
            "https://example.invalid/release", "https://example.invalid/setup.exe.sha256");
    }

    private static WindowsUpdater MakeUpdater(
        string folder, IUpdateDownloader download, List<Report> reports, Action<PlatformLaunchPlan> launch,
        TimeProvider? clock = null)
    {
        return new WindowsUpdater(download, (intent, fraction, reason) =>
        {
            lock (reports)
            {
                reports.Add(new Report(intent, fraction, reason));
            }
            return Task.CompletedTask;
        }, launch, folder, clock);
    }

    private static void WithFolder(Action<string> test)
    {
        var folder = Path.Combine(Path.GetTempPath(), "DevDeck-update-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        try
        {
            test(folder);
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }

    private static void Require(bool value)
    {
        if (!value)
        {
            throw new InvalidOperationException("Update assertion failed.");
        }
    }

    private sealed record Report(string Intent, double? Fraction, string? Reason);

    private sealed class FixtureDownloader(string checksum) : IUpdateDownloader
    {
        public int Calls { get; private set; }
        public TestClock? Clock { get; init; }

        public async Task DownloadAsync(
            Uri address, string destination, Func<long, Task> received, CancellationToken cancellation)
        {
            Calls++;
            if (address.LocalPath.EndsWith(".sha256", StringComparison.Ordinal))
            {
                await File.WriteAllTextAsync(destination, checksum + "  setup.exe\n", cancellation);
                return;
            }
            await File.WriteAllBytesAsync(destination, Fixture, cancellation);
            if (Clock is not null)
            {
                Clock.Advance(50);
                await received(1);
                Clock.Advance(50);
                await received(Fixture.Length / 2);
                Clock.Advance(99);
                await received(Fixture.Length - 1);
                Clock.Advance(1);
                await received(Fixture.Length * 2);
            }
        }
    }

    private sealed class TestClock : TimeProvider
    {
        private long milliseconds;
        private TestTimer? timer;
        public ManualResetEventSlim Ready { get; } = new();
        public override long TimestampFrequency => 1000;
        public override long GetTimestamp() => Interlocked.Read(ref milliseconds);

        public void Advance(long delta)
        {
            Interlocked.Add(ref milliseconds, delta);
            if (timer is { } value && milliseconds >= value.Due)
            {
                timer = null;
                value.Fire();
            }
        }

        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            timer = new TestTimer(callback, state, milliseconds + (long)dueTime.TotalMilliseconds);
            Ready.Set();
            return timer;
        }

        private sealed class TestTimer(TimerCallback callback, object? state, long due) : ITimer
        {
            public long Due => due;
            public void Fire() => callback(state);
            public bool Change(TimeSpan dueTime, TimeSpan period) => false;
            public void Dispose() { }
            public ValueTask DisposeAsync() => ValueTask.CompletedTask;
        }
    }
}
