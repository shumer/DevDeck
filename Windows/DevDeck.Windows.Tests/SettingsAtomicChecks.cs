using System.Text;
using DevDeck.Windows.Core;

// Real SettingsStore serialization/cleanup and owned files; no user settings or SDK.
internal static class SettingsAtomicChecks
{
    private const int RemoveReplaced = unchecked((int)0x80070497);

    internal static async Task RunAsync(Func<string, Func<Task>, Task> check, bool transientOnly = false)
    {
        await check("settings transient native1175 retries the same flushed payload and preserves preceding backup", () => {
            using var fixture = new Fixture();
            var attempts = 0; var waits = new List<TimeSpan>(); var clock = TimeSpan.Zero;
            string? source = null; byte[]? payload = null;
            var original = fixture.TargetBytes; var priorBackup = fixture.BackupBytes;
            var store = new SettingsStore(fixture.Path, new AtomicSettingsCommit((temporary, target, backup) => {
                attempts++;
                if (source is null) { source = temporary; payload = File.ReadAllBytes(temporary); }
                Require(source == temporary && Same(File.ReadAllBytes(temporary), payload!) && target == fixture.Path && backup == fixture.BackupPath,
                    "Retry regenerated, rewrote or rerouted the prepared payload.");
                Require(Same(File.ReadAllBytes(target), original) && Same(File.ReadAllBytes(backup), priorBackup), "A failed attempt changed old settings or backup.");
                if (attempts <= 2) throw Fault();
                File.Replace(temporary, target, backup);
            }, pause => { waits.Add(pause); clock += pause; }, () => clock));
            store.Save(fixture.Next);
            Require(attempts == 3 && waits.SequenceEqual(new[] { TimeSpan.FromMilliseconds(10), TimeSpan.FromMilliseconds(20) }), "Transient1175 did not use the bounded retry path.");
            Require(Same(File.ReadAllBytes(fixture.Path), payload!) && Same(File.ReadAllBytes(fixture.BackupPath), original), "Successful replacement lost payload or previous-valid backup.");
            Require(store.Load().Floating && store.Load().Cards.Single().Project.Id == "project.owned" && store.Load().WorkInFlight is null, "Save changed permanent identity or optional preference.");
            fixture.RequireNoTemporary(); return Task.CompletedTask;
        });
        if (transientOnly) return;

        await check("settings permanent1175 has five attempts150ms waits original files and owned temporary cleanup", () => {
            using var fixture = new Fixture(); var attempts = 0; var clock = TimeSpan.Zero; var waits = new List<TimeSpan>(); var failure = Fault();
            var store = new SettingsStore(fixture.Path, new AtomicSettingsCommit((_, _, _) => { attempts++; throw failure; }, pause => { waits.Add(pause); clock += pause; }, () => clock));
            Require(ReferenceEquals(Capture(() => store.Save(fixture.Next)), failure), "Permanent failure was replaced or hidden.");
            Require(attempts == 5 && waits.SequenceEqual(new[] { 10, 20, 40, 80 }.Select(value => TimeSpan.FromMilliseconds(value))) && clock == TimeSpan.FromMilliseconds(150), "Permanent failure exceeded or skipped the attempt budget.");
            fixture.RequireOriginal(); fixture.RequireNoTemporary(); return Task.CompletedTask;
        });

        await check("settings hard1176 1177 access-denied unrelated IO and non-IO failures never retry", () => {
            foreach (var failure in new Exception[] { Fault(unchecked((int)0x80070498)), Fault(unchecked((int)0x80070499)), Fault(unchecked((int)0x80070005)), new IOException("ordinary IO"), new UnauthorizedAccessException("owned denial"), new ArgumentException("owned argument") }) {
                using var fixture = new Fixture(); var attempts = 0; var waits = 0;
                var store = new SettingsStore(fixture.Path, new AtomicSettingsCommit((_, _, _) => { attempts++; throw failure; }, _ => waits++, () => TimeSpan.Zero));
                Require(ReferenceEquals(Capture(() => store.Save(fixture.Next)), failure) && attempts == 1 && waits == 0, "An unrelated error used1175 recovery.");
                fixture.RequireOriginal(); fixture.RequireNoTemporary();
            }
            return Task.CompletedTask;
        });

        await check("settings1175 changed or missing target refuses retry without restoring another writer", async () => {
            await Mutation("target"); await Mutation("missing-target");
        });
        await check("settings1175 changed prepared source refuses retry and cleans only its owned temporary", () => Mutation("source"));
        await check("settings1175 missing prepared source refuses retry without recreating it", () => Mutation("missing-source"));
        await check("settings1175 changed backup refuses retry without overwriting foreign backup", () => Mutation("backup"));
        await check("settings1175 newly created formerly absent backup refuses retry", () => Mutation("new-backup"));

        await check("settings1175 expired monotonic admission budget never performs a late replacement", () => {
            foreach (var expiresDuringDelay in new[] { false, true }) {
                using var fixture = new Fixture(); var attempts = 0; var waits = 0; var clock = TimeSpan.Zero; var failure = Fault();
                var store = new SettingsStore(fixture.Path, new AtomicSettingsCommit((_, _, _) => { attempts++; if (!expiresDuringDelay) clock = TimeSpan.FromMilliseconds(200); throw failure; }, _ => { waits++; clock = TimeSpan.FromMilliseconds(210); }, () => clock));
                Require(ReferenceEquals(Capture(() => store.Save(fixture.Next)), failure) && attempts == 1 && waits == (expiresDuringDelay ? 1 : 0), "Expired retry admission still called File.Replace.");
                fixture.RequireOriginal(); fixture.RequireNoTemporary();
            }
            // Time can also expire during an unchanged-byte read, before the next action.
            foreach (var expiresAfterGuard in new[] { 3, 5 }) {
                using var fixture = new Fixture(); var attempts = 0; var waits = 0; var timeReads = 0; var clock = TimeSpan.Zero; var failure = Fault();
                var store = new SettingsStore(fixture.Path, new AtomicSettingsCommit((_, _, _) => { attempts++; throw failure; }, pause => { waits++; clock += pause; },
                    () => ++timeReads >= expiresAfterGuard ? TimeSpan.FromMilliseconds(200) : clock));
                Require(ReferenceEquals(Capture(() => store.Save(fixture.Next)), failure) && attempts == 1 && waits == (expiresAfterGuard == 3 ? 0 : 1),
                    "Budget exhausted while checking unchanged files still admitted a wait or another replacement.");
                fixture.RequireOriginal(); fixture.RequireNoTemporary();
            }
            return Task.CompletedTask;
        });

        await check("settings invalid data fails before replacement and leaves no serialized temporary", () => {
            using var fixture = new Fixture(); var attempts = 0;
            var store = new SettingsStore(fixture.Path, new AtomicSettingsCommit((_, _, _) => attempts++, _ => throw new Exception("Unexpected wait."), () => TimeSpan.Zero));
            var invalid = fixture.Next with { Cards = [fixture.Next.Cards[0], fixture.Next.Cards[0]] };
            Require(Capture(() => store.Save(invalid)) is InvalidDataException && attempts == 0, "Invalid config reached atomic replacement.");
            fixture.RequireOriginal(); fixture.RequireNoTemporary(); return Task.CompletedTask;
        });

        await check("settings first save remains a non-replacing move and next save retains exact previous bytes", () => {
            using var fixture = new Fixture(empty: true); var attempts = 0;
            var store = new SettingsStore(fixture.Path, new AtomicSettingsCommit((source, target, backup) => { attempts++; File.Replace(source, target, backup); }, _ => throw new Exception("Unexpected wait."), () => TimeSpan.Zero));
            store.Save(fixture.Original); var original = File.ReadAllBytes(fixture.Path);
            Require(attempts == 0 && !File.Exists(fixture.BackupPath), "First save began a replacement transaction.");
            store.Save(fixture.Next);
            Require(attempts == 1 && Same(File.ReadAllBytes(fixture.BackupPath), original) && store.Load().Floating, "Second save lost ordinary backup semantics.");
            fixture.RequireNoTemporary(); return Task.CompletedTask;
        });

        await check("settings actual owned NTFS backup lock1175 recovers after only the owned lock is released", () => {
            if (!OwnedNTFS()) return Task.CompletedTask;
            using var fixture = new Fixture(); var attempts = 0; var observed = false; var clock = TimeSpan.Zero;
            FileStream? blocker = new(fixture.BackupPath, FileMode.Open, FileAccess.Read, FileShare.Read);
            try {
                var store = new SettingsStore(fixture.Path, new AtomicSettingsCommit((source, target, backup) => {
                    attempts++;
                    try { File.Replace(source, target, backup); }
                    catch (IOException error) when (error.HResult == RemoveReplaced) { observed = true; throw; }
                }, pause => { blocker?.Dispose(); blocker = null; clock += pause; }, () => clock));
                store.Save(fixture.Next);
                Require(observed && attempts == 2 && Same(File.ReadAllBytes(fixture.BackupPath), fixture.TargetBytes) && store.Load().Floating, "Actual native lock did not recover with the exact previous backup.");
                fixture.RequireNoTemporary();
            } finally { blocker?.Dispose(); }
            return Task.CompletedTask;
        });

        await check("settings default production store rapidly replaces100 owned NTFS settings with exact prior backup", () => {
            if (!OwnedNTFS()) return Task.CompletedTask;
            using var fixture = new Fixture(); var store = new SettingsStore(fixture.Path);
            for (var index = 0; index < 100; index++) {
                var prior = File.ReadAllBytes(fixture.Path);
                var value = fixture.Original with { Floating = index % 2 == 0, Locked = index % 3 == 0, Cards = [fixture.Original.Cards[0] with { X = 48 + index, Collapsed = index % 2 == 1 }] };
                store.Save(value); var loaded = store.Load();
                Require(Same(File.ReadAllBytes(fixture.BackupPath), prior) && loaded.Floating == value.Floating && loaded.Locked == value.Locked && loaded.Cards.Single().X == 48 + index && loaded.Cards.Single().Project.Id == "project.owned" && loaded.WorkInFlight is null,
                    "Rapid production save lost prior valid bytes, identity, preference or current mode.");
                fixture.RequireNoTemporary();
            }
            return Task.CompletedTask;
        });
    }

    private static Task Mutation(string changed)
    {
        foreach (var duringDelay in new[] { false, true }) {
            using var fixture = new Fixture();
            if (changed == "new-backup") File.Delete(fixture.BackupPath);
            var foreign = Encoding.UTF8.GetBytes("owned foreign writer bytes"); var attempts = 0; var waits = 0; var failure = Fault(); var clock = TimeSpan.Zero;
            string? preparedSource = null;
            void ChangeInput()
            {
                switch (changed) {
                    case "target": File.WriteAllBytes(fixture.Path, foreign); break;
                    case "missing-target": File.Delete(fixture.Path); break;
                    case "source": File.WriteAllBytes(preparedSource!, foreign); break;
                    case "missing-source": File.Delete(preparedSource!); break;
                    case "backup": case "new-backup": File.WriteAllBytes(fixture.BackupPath, foreign); break;
                }
            }
            var store = new SettingsStore(fixture.Path, new AtomicSettingsCommit((source, _, _) => {
                attempts++; preparedSource = source;
                if (!duringDelay) ChangeInput();
                throw failure;
            }, pause => { waits++; clock += pause; if (duringDelay) ChangeInput(); }, () => clock));
            Require(ReferenceEquals(Capture(() => store.Save(fixture.Next)), failure) && attempts == 1 && waits == (duringDelay ? 1 : 0), "Changed transaction input was retried or its error was hidden.");
            Require(changed == "missing-target" ? !File.Exists(fixture.Path) : Same(File.ReadAllBytes(fixture.Path), changed == "target" ? foreign : fixture.TargetBytes), "Changed target was silently restored or unrelated target modified.");
            Require(Same(File.ReadAllBytes(fixture.BackupPath), changed is "backup" or "new-backup" ? foreign : fixture.BackupBytes), "Foreign backup was overwritten or old backup changed.");
            fixture.RequireNoTemporary();
        }
        return Task.CompletedTask;
    }

    private static bool OwnedNTFS()
    {
        if (!OperatingSystem.IsWindows()) return false;
        var root = Path.GetPathRoot(Path.GetFullPath(Path.GetTempPath()))!;
        return !root.StartsWith("\\\\", StringComparison.Ordinal) && string.Equals(new DriveInfo(root).DriveFormat, "NTFS", StringComparison.OrdinalIgnoreCase);
    }
    private static IOException Fault(int hresult = RemoveReplaced) => new("Owned replacement fault.", hresult);
    private static Exception Capture(Action action) { try { action(); } catch (Exception error) { return error; } throw new Exception("Expected atomic failure."); }
    private static bool Same(byte[] left, byte[] right) => left.AsSpan().SequenceEqual(right);
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }

    private sealed class Fixture : IDisposable
    {
        private readonly string directory = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "devdeck-settings-atomic-" + Guid.NewGuid().ToString("N"));
        internal string Path { get; }
        internal string BackupPath => Path + ".bak";
        internal DeckSettings Original { get; } = new(1, [new("Owned Linux", "/missing/worker")], [new(new("project.owned", "Owned Linux", "local", "/missing/project"), "Owned 🧩")]);
        internal DeckSettings Next => Original with { Floating = true };
        internal byte[] TargetBytes { get; }
        internal byte[] BackupBytes { get; }
        internal Fixture(bool empty = false)
        {
            Directory.CreateDirectory(directory); Path = System.IO.Path.Combine(directory, "settings.json");
            var store = new SettingsStore(Path);
            if (!empty) {
                store.Save(Original with { Locked = true }); store.Save(Original);
                TargetBytes = File.ReadAllBytes(Path); BackupBytes = File.ReadAllBytes(BackupPath);
            } else { TargetBytes = []; BackupBytes = []; }
        }
        internal void RequireOriginal() => Require(Same(File.ReadAllBytes(Path), TargetBytes) && Same(File.ReadAllBytes(BackupPath), BackupBytes), "Rejected save changed previous settings/backup bytes.");
        internal void RequireNoTemporary() => Require(!Directory.EnumerateFiles(directory, "*.tmp").Any(), "Save leaked an owned prepared temporary.");
        public void Dispose()
        {
            // Exact generated directory only; no recursive traversal or user config cleanup.
            foreach (var file in Directory.EnumerateFiles(directory)) File.Delete(file);
            Directory.Delete(directory);
        }
    }
}
