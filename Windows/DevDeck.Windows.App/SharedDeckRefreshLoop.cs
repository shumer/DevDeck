using System;
using System.Linq;
using System.Threading.Tasks;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed record SharedRefreshRead(RemoteAccountFailure[] Failures, double? ServerHint = null);
internal sealed record SharedRefreshSource(string ID, Func<bool> Eligible, Func<Task<SharedRefreshRead>> Read);
internal sealed record SharedRefreshOutcome(TimeSpan Delay, int ConsecutiveFailures, int ReadSources);

/// One coalesced provider → open logs → checkout pass. The controller owns its only timer.
internal sealed class SharedDeckRefreshLoop
{
    private Task<SharedRefreshOutcome>? running;
    private int failures;
    internal bool IsRunning => running is { IsCompleted: false };
    internal Task<SharedRefreshOutcome> RunAsync(SharedRefreshSource[] sources, int interval,
        Func<Task> logs, Func<Task> checkouts, Func<bool> alive, Func<DateTimeOffset>? clock = null)
        => running is { IsCompleted: false } ? running : running = ReadAsync(sources.ToArray(), interval, logs, checkouts, alive, clock ?? (() => DateTimeOffset.UtcNow));

    private async Task<SharedRefreshOutcome> ReadAsync(SharedRefreshSource[] sources, int interval,
        Func<Task> logs, Func<Task> checkouts, Func<bool> alive, Func<DateTimeOffset> clock)
    {
        RemoteAccountFailure? first = null; double? hint = null; var read = 0;
        foreach (var source in sources) {
            if (!alive()) break;
            if (!source.Eligible()) continue;
            SharedRefreshRead result;
            try{result=await source.Read();}
            catch(Exception error) when(error is System.IO.IOException or System.ComponentModel.Win32Exception or OperationCanceledException){result=new([new(null,"other")]);}
            read++;
            if (result.Failures.Length > 0) first ??= result.Failures[0];
            else if (result.ServerHint is { } value && double.IsFinite(value)) hint = Math.Max(hint ?? 0, value);
        }
        failures = first is null ? 0 : Math.Min(failures + 1, 8);
        if (alive()) {
            try{await logs();}
            catch(Exception error) when(error is System.IO.IOException or System.ComponentModel.Win32Exception or OperationCanceledException){ }
        }
        if (alive()) await checkouts();
        var seconds = first is null ? SharedRefreshPolicy.NextDelay(interval, failures, hint)
            : SharedRefreshPolicy.AfterError(interval, failures, first.Kind, first.ResetAt, clock().ToUnixTimeSeconds());
        return new(TimeSpan.FromSeconds(seconds), failures, read);
    }
}
