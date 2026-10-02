using System.Globalization;
using System.Text.Json.Serialization;

namespace DevDeck.Windows.Core;

public sealed record CheckoutEntry(CheckoutReference Reference, CheckoutResult Result)
{
    [JsonIgnore] public CheckoutState? State => Result.State;
    [JsonIgnore] public CheckoutTarget Target => new(Reference.Distribution, Reference.ProjectID, Reference.Path);
}
public sealed record CheckoutProjection(CheckoutEntry[] Rows, int Watched, int InFlight, int Unpushed, int Failures, bool Urgent);
public sealed record WorkInFlightSnapshot(CheckoutEntry[] Entries, int SelectedCount, double? CheckedAt, bool Checking = false, bool Stale = false)
{
    [JsonIgnore] public CheckoutEntry[] Rows => CheckoutPresentation.Project(Entries).Rows;
    [JsonIgnore] public int SuccessfulCount => Entries.Count(entry => entry.State is not null);
    [JsonIgnore] public int FailureCount => Entries.Count(entry => entry.Result.Failure is not null);
    [JsonIgnore] public bool Partial => Stale || FailureCount > 0 || Entries.Length < SelectedCount;
    [JsonIgnore] public int InFlightCount => Entries.Count(entry => entry.State?.InFlight == true);
    [JsonIgnore] public int UnpushedCount => Entries.Count(entry => entry.State?.InFlight == true && entry.State!.Ahead > 0);
    [JsonIgnore] public bool Urgent => Entries.Any(entry => entry.State?.Urgent == true);
}

/// Merge route entries in frozen selection order before applying the original stable global sort.
public static class CheckoutPresentation
{
    public static CheckoutProjection Project(IEnumerable<CheckoutEntry> entries, CultureInfo? culture = null)
    {
        var all = entries.ToArray();
        var comparison = (culture ?? CultureInfo.CurrentCulture).CompareInfo;
        var titles = Comparer<string>.Create((left, right) => comparison.Compare(left, right, CompareOptions.IgnoreCase | CompareOptions.NumericOrdering));
        var rows = all.Where(entry => entry.State?.InFlight == true).OrderByDescending(entry => entry.State!.Urgent)
            .ThenByDescending(entry => entry.State!.DirtyFiles).ThenBy(entry => entry.Reference.Title, titles).ToArray();
        return new(rows, all.Count(entry => entry.State is not null), rows.Length, rows.Count(entry => entry.State!.Ahead > 0),
            all.Count(entry => entry.Result.Failure is not null), rows.Any(entry => entry.State!.Urgent));
    }
    public static CheckoutEntry[] CardRows(CheckoutProjection projection, bool expanded) => projection.Rows.Take(expanded ? 12 : 3).ToArray();
}
