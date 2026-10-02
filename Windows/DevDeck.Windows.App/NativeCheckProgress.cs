using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;

namespace DevDeck.Windows.App;

// Diagnostic receipts for the owned --window-check fixture. A partial count is
// never a qualification result. The normal application does not create this.
internal sealed class NativeCheckProgress : IDisposable
{
    internal static NativeCheckProgress? Current { get; private set; }
    private readonly string path;
    private readonly Func<int> count;
    private readonly Stopwatch elapsed = Stopwatch.StartNew();
    private readonly List<string> completed = [];
    private bool complete;

    internal NativeCheckProgress(string report, Func<int> count)
    {
        path = report + ".progress.json"; this.count = count;
        Current = this; Mark("starting");
    }

    internal async Task RunAsync(string phase, Func<Task> action)
    {
        Mark(phase); await action(); completed.Add(phase); Mark(phase + ".completed");
    }

    internal void Mark(string phase) => File.WriteAllText(path, JsonSerializer.Serialize(new {
        processID = Environment.ProcessId, phase, elapsedSeconds = elapsed.Elapsed.TotalSeconds,
        checksRecordedSoFar = count(), completedGroups = completed, complete,
        diagnosticOnly = true, releaseQualified = false
    }));

    internal void Complete() { complete = true; Mark("finished"); }
    public void Dispose() { if (ReferenceEquals(Current, this)) Current = null; }
}
