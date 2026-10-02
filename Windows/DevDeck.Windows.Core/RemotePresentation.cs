namespace DevDeck.Windows.Core;

// Data priority comes from the shared Swift snapshots. The host only selects the card's visible slice.
public static class RemotePresentation
{
    public const int CollapsedRows = 3;
    public const int ExpandedRows = 12;
    public static RemoteRow[] CardRows(RemoteSnapshot snapshot, bool expanded)
    {
        if (snapshot.Kind != "actions") return snapshot.Rows.Take(expanded ? ExpandedRows : CollapsedRows).ToArray();
        var failures = snapshot.Rows.Where(row => row.Health == "blocked").OrderByDescending(row => row.UpdatedAt ?? 0).ToArray();
        return (failures.Length > 0 ? failures : snapshot.Rows.Where(row => row.Health == "attention")).Take(2).ToArray();
    }
    public static string Dashboard(RemoteAccountSettings account, string kind)
    {
        account.Validate();
        var endpoint = new Uri(account.Endpoint);
        if (account.Provider == "gitlab") return account.Endpoint.TrimEnd('/') + "/dashboard/merge_requests";
        var origin = endpoint.Host == "api.github.com" ? "https://github.com" : endpoint.GetLeftPart(UriPartial.Authority);
        return origin + (kind == "pullRequests" ? "/pulls" : kind == "inbox" ? "/notifications" : "");
    }
    public static Dictionary<string, double> ReadCutoffs(RemoteSnapshot snapshot) => snapshot.Kind != "inbox" ? [] : snapshot.Rows
        .Where(row => row.UpdatedAt is > 0).GroupBy(row => row.AccountID)
        .ToDictionary(group => group.Key, group => group.Max(row => row.UpdatedAt!.Value), StringComparer.Ordinal);
    public static string ReasonKey(string reason) => "card.inbox.chip." + (reason switch {
        "reviewRequested" => "review", "teamMention" => "team", "ciActivity" => "ci", "stateChange" => "state", "author" => "yours",
        "subscribed" => "watching", "securityAlert" => "security", "mention" => "mention", "assigned" => "assigned", "comment" => "comment", _ => "other" });
}
