namespace DevDeck.Windows.Core;

/// Delivery policy only: candidate identities and meanings come from the shared Swift builders.
public sealed class NotificationLedger(IEnumerable<string>? seen = null)
{
    public const int Memory = 200;
    public const int SummaryThreshold = 3;
    private readonly HashSet<string> observed = new(StringComparer.Ordinal);
    public string[] Seen { get; private set; } = (seen ?? []).Distinct(StringComparer.Ordinal).TakeLast(Memory).ToArray();

    public DeckAlert[] Observe(AttentionSnapshot snapshot, DeckSettings settings)
    {
        if (!settings.Notifications) return [];
        var candidates = snapshot.Alerts.Where(alert => Enabled(alert, settings)).DistinctBy(alert => alert.Id, StringComparer.Ordinal).ToArray();
        var first = observed.Add(snapshot.Scope);
        var remembered = Seen.ToHashSet(StringComparer.Ordinal);
        DeckAlert[] fresh = first ? [] : candidates.Where(alert => !remembered.Contains(alert.Id)).ToArray();
        var ids = candidates.Select(alert => alert.Id).ToHashSet(StringComparer.Ordinal);
        Seen = Seen.Where(id => !ids.Contains(id)).Concat(candidates.Select(alert => alert.Id)).TakeLast(Memory).ToArray();
        return fresh;
    }

    public void ResetObservations() => observed.Clear();
    public void ResetScope(string scope) => observed.Remove(scope);
    public void Seed(IEnumerable<DeckAlert> alerts, DeckSettings settings)
    {
        var candidates = alerts.Where(alert => Enabled(alert, settings)).DistinctBy(alert => alert.Id, StringComparer.Ordinal).ToArray();
        var ids = candidates.Select(alert => alert.Id).ToHashSet(StringComparer.Ordinal);
        Seen = Seen.Where(id => !ids.Contains(id)).Concat(candidates.Select(alert => alert.Id)).TakeLast(Memory).ToArray();
    }

    public static bool Enabled(DeckAlert alert, DeckSettings settings)
    {
        if (alert.Kind == "cantCheck") return true;
        if (alert.Target.Kind == "open")
        {
            var account = settings.AccountList.FirstOrDefault(account => account.Id == alert.Target.AccountID && account.Enabled
                && account.Provider == alert.Target.Service);
            return alert.Kind switch { "reviewRequest" => account?.NotifiesReviewRequests == true, "blocked" => account?.NotifiesBlocked == true,
                "failedRun" => account?.NotifiesFailedRuns == true, _ => false };
        }
        if (alert.Target.Kind == "showCard")
        {
            var card = settings.Cards.FirstOrDefault(card => card.Enabled && card.Project.Id == alert.Target.CardID);
            return alert.Kind == "startFailed" ? card?.NotifiesStartFailed == true : card?.NotifiesWhenDown == true;
        }
        return false;
    }
}
