namespace DevDeck.Windows.Core;

/// A slow local cycle must not queue more cycles or delay another distribution's initial read.
public sealed class LocalRefreshBatch
{
    public static readonly TimeSpan Interval = TimeSpan.FromSeconds(10);
    private Task? current;

    public Task RunAsync(IEnumerable<Func<string,Task>> reads)
    {
        if (current is { IsCompleted: false }) return current;
        var cycle = Guid.NewGuid().ToString("N");
        return current = Task.WhenAll(reads.Select(read => read(cycle)));
    }
}
