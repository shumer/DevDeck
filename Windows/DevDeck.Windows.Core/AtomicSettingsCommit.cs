using System.Diagnostics;

namespace DevDeck.Windows.Core;

// Retry only the recoverable Windows replacement error while every input is unchanged.
// The per-store seam keeps owned fault/time tests on the real Save path.
internal sealed class AtomicSettingsCommit(
    Action<string, string, string>? replace = null,
    Action<TimeSpan>? delay = null,
    Func<TimeSpan>? now = null)
{
    private const int UnableToRemoveReplaced = unchecked((int)0x80070497);
    private static readonly TimeSpan Budget = TimeSpan.FromMilliseconds(200);
    private static readonly TimeSpan[] Waits = [TimeSpan.FromMilliseconds(10), TimeSpan.FromMilliseconds(20), TimeSpan.FromMilliseconds(40), TimeSpan.FromMilliseconds(80)];
    private Action<string, string, string> ReplaceFile { get; } = replace ?? ((source, target, backup) => File.Replace(source, target, backup));
    private Action<TimeSpan> Delay { get; } = delay ?? Thread.Sleep;
    private Func<TimeSpan> Now { get; } = now ?? (() => Stopwatch.GetElapsedTime(0));

    internal void Replace(string temporary, string target, string backup)
    {
        var prepared = FileSnapshot.Read(temporary);
        var original = FileSnapshot.Read(target);
        var previousBackup = FileSnapshot.Read(backup);
        if (!prepared.Exists || !original.Exists)
            throw new FileNotFoundException("Prepared or original settings disappeared before replacement.", !prepared.Exists ? temporary : target);
        var started = Now();
        for (var attempt = 0; ; attempt++) {
            try { ReplaceFile(temporary, target, backup); return; }
            catch (IOException error) when (error.HResult == UnableToRemoveReplaced) {
                if (attempt >= Waits.Length || !Admit(Waits[attempt]) || !Unchanged() || !Admit(Waits[attempt])) throw;
                Delay(Waits[attempt]);
                // A writer can change any input while we wait; never restore or overwrite it.
                if (!Admit(TimeSpan.Zero) || !Unchanged() || !Admit(TimeSpan.Zero)) throw;
            }
        }

        bool Admit(TimeSpan pause)
        {
            var elapsed = Now() - started;
            return elapsed >= TimeSpan.Zero && elapsed + pause < Budget;
        }
        bool Unchanged()
        {
            try { return prepared.Matches(temporary) && original.Matches(target) && previousBackup.Matches(backup); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
        }
    }

    private sealed record FileSnapshot(byte[]? Bytes)
    {
        internal bool Exists => Bytes is not null;
        internal static FileSnapshot Read(string path)
        {
            try { return new(File.ReadAllBytes(path)); }
            catch (Exception error) when (error is FileNotFoundException or DirectoryNotFoundException) { return new((byte[]?)null); }
        }
        internal bool Matches(string path)
        {
            var current = Read(path).Bytes;
            return Bytes is null ? current is null : current is not null && Bytes.AsSpan().SequenceEqual(current);
        }
    }
}
