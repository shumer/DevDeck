namespace DevDeck.Windows.Core;

public static class SharedRefreshPolicy
{
    public static double NextDelay(int preferenceSeconds, int consecutiveFailures, double? serverHintSeconds = null)
    {
        var hint = serverHintSeconds is { } value && double.IsFinite(value) ? value : 0;
        var basis = Math.Max(60, Math.Max(preferenceSeconds, hint));
        return Math.Min(900, consecutiveFailures > 0 ? basis * Math.Pow(2, Math.Min(consecutiveFailures, 8)) : basis);
    }
    public static double AfterError(int preferenceSeconds, int consecutiveFailures, string? failureKind, double? resetAt, double now)
    {
        if (failureKind == "rateLimited" && resetAt is { } reset && double.IsFinite(reset) && double.IsFinite(now)) {
            var wait = reset - now + 5;
            if (wait > 0) return Math.Clamp(wait, 60, 900);
        }
        return NextDelay(preferenceSeconds, consecutiveFailures);
    }
    public static RemoteCardSettings[] SourceOrder(DeckSettings settings)
    {
        var roles = new[] { "pullRequests", "inbox", "mergeRequests", "actions" }
            .Select(kind => RemoteCardCatalog.Resolve(settings, kind)).Where(card => card is not null).Cast<RemoteCardSettings>().ToArray();
        var roleIDs = roles.Select(card => card.Id).ToHashSet(StringComparer.Ordinal);
        return roles.Concat(settings.RemoteCardList.Where(card => !roleIDs.Contains(card.Id))).ToArray();
    }
}
