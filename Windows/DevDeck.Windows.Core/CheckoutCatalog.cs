using System.Text.Json.Serialization;

namespace DevDeck.Windows.Core;

public sealed record WorkInFlightSettings(bool Enabled = false, double X = 48, double Y = 80, bool Collapsed = false);
public sealed record CheckoutReference(string ProjectID, string Distribution, string Path, string Title);
public sealed record CheckoutRequest(string CardID, string PassToken, CheckoutReference Reference);
public sealed record CheckoutTarget(string Distribution, string ProjectID, string Path);
public sealed record CheckoutSummaryFact(string Kind, int? Count = null);
public sealed record CheckoutState(string Branch,
    [property: JsonRequired] int DirtyFiles, [property: JsonRequired] int Ahead, [property: JsonRequired] int Behind,
    [property: JsonRequired] bool HasUpstream, [property: JsonRequired] int LocalCommits, double? OldestLocalCommitAt,
    [property: JsonRequired] bool InFlight, [property: JsonRequired] bool Urgent,
    [property: JsonRequired] CheckoutSummaryFact[] SummaryFacts);
public sealed record CheckoutFailure(string Stage, string Code);
public sealed record CheckoutResult(string CardID, string PassToken, string ProjectID, string Path,
    [property: JsonRequired] double CheckedAt, CheckoutState? State, CheckoutFailure? Failure,
    [property: JsonRequired] AttentionItem[] Signals);

/// Configured checkout ownership is saved-order based, independent of card visibility or title sort.
public static class CheckoutCatalog
{
    public const string CardID = "local.workInFlight";
    public const int MaximumCheckouts = 1024;
    public static string Standardize(string path)
    {
        if (path is null || !LinuxPath.IsAbsolute(path)) throw new InvalidDataException("Checkout requires an absolute Linux path.");
        return "/" + string.Join('/', path.Split('/', StringSplitOptions.RemoveEmptyEntries).Where(part => part != "."));
    }
    public static CheckoutReference[] Select(DeckSettings settings)
    {
        var selected = new List<CheckoutReference>();
        var seen = new HashSet<(string Distribution, string Path)>();
        foreach (var kind in new[] { "arc", "ddev", "local" })
            foreach (var card in settings.Cards.Where(card => card.Project.Kind == kind && card.Project.Path.Length > 0)) {
                var project = card.Project;
                var path = Standardize(project.Path);
                if (!settings.Workers.Any(worker => worker.Distribution == project.Distribution))
                    throw new InvalidDataException("Checkout distribution has no configured worker.");
                var reference = new CheckoutReference(project.Id, project.Distribution, path, card.Title);
                CheckoutValidation.ValidateReference(reference, project.Distribution);
                if (!seen.Add((project.Distribution, path))) continue;
                if (selected.Count >= MaximumCheckouts) throw new InvalidDataException("Checkout selection exceeds the configuration limit.");
                selected.Add(reference);
            }
        return selected.ToArray();
    }
    public static bool HasIdentityConflict(DeckSettings settings) => settings.Cards.Any(card => card.Project.Id == CardID)
        || settings.RemoteCardList.Any(card => card.Id == CardID);
    public static DeckSettings SetEnabled(DeckSettings settings, bool enabled, Func<DeckSettings, (double X, double Y)>? placement = null)
    {
        if (enabled && HasIdentityConflict(settings)) throw new InvalidOperationException("The Work in flight card ID is already configured.");
        if (settings.WorkInFlight is { } existing) return settings with { WorkInFlight = existing with { Enabled = enabled } };
        if (!enabled) return settings;
        var point = placement?.Invoke(settings) ?? (48d, 80d);
        if (!double.IsFinite(point.Item1) || !double.IsFinite(point.Item2)) throw new InvalidDataException("Work in flight placement is invalid.");
        return settings with { WorkInFlight = new(true, point.Item1, point.Item2) };
    }
    public static bool CurrentTarget(DeckSettings settings, CheckoutTarget? target)
    {
        if (settings.WorkInFlight?.Enabled != true || target is null || !CheckoutValidation.ValidTarget(target)) return false;
        try { return Select(settings).Any(reference => reference.ProjectID == target.ProjectID && reference.Distribution == target.Distribution && reference.Path == target.Path); }
        catch (IOException) { return false; }
    }
}
