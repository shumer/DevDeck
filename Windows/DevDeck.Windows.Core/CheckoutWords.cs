namespace DevDeck.Windows.Core;

/// Windows display wording; worker-derived facts and the original attention policy stay intact.
public static class CheckoutWords
{
    public static string Summary(CheckoutState state, Localization words) => string.Join(" · ", state.SummaryFacts.Select(fact => fact.Kind switch {
        "changed" => words.Get("windows.wif.changed", fact.Count!.Value),
        "unpushed" => words.Get("windows.wif.unpushed", fact.Count!.Value),
        "noRemote" => words.Get("windows.wif.noRemote"),
        "behind" => words.Get("windows.wif.behind", fact.Count!.Value), _ => ""
    }));
    public static string Collapsed(CheckoutProjection projection, Localization words)
    {
        if (projection.Failures > 0) return projection.Watched == 0
            ? words.Get("windows.wif.readFailed", projection.Failures)
            : words.Get("windows.wif.partial", projection.Watched, projection.Failures);
        return projection.InFlight == 0 ? words.Get("card.wif.allClean") : projection.Unpushed > 0
            ? words.Get("card.wif.unpushedInFlight", projection.Unpushed, projection.InFlight)
            : words.Get("card.wif.inFlight", projection.InFlight);
    }
    public static string Footer(CheckoutProjection projection, Localization words) => words.Plural("card.wif.watched", projection.Watched);
    public static AttentionItem Signal(AttentionItem item, CheckoutReference reference, CheckoutState state, Localization words, double checkedAt)
    {
        var commits = words.Plural("attention.local.commits", state.LocalCommits);
        var days = words.Plural("attention.local.days", (int)Math.Floor(Math.Max(0, checkedAt - item.Since!.Value) / 86400));
        return item with {
            Title = state.HasUpstream ? words.Get("windows.wif.localCommitsTitle", commits, reference.Title)
                : words.Get("attention.local.noRemote.title", reference.Title),
            Subtitle = state.HasUpstream ? words.Get("attention.local.unpushed.subtitle", state.Branch, days)
                : words.Get("attention.local.noRemote.subtitle", state.Branch, commits, days)
        };
    }
}
