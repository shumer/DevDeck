namespace DevDeck.Windows.Core;

public sealed record RemoteCardDescriptor(string Id, string Kind, string TitleKey, string Provider, bool EnabledByDefault);

/// Built-in discovery is independent of saved cards. Legacy/custom IDs and explicit hidden states
/// remain authoritative; only new built-ins follow all accounts of their provider automatically.
public static class RemoteCardCatalog
{
    public static readonly RemoteCardDescriptor[] All = [
        new("github.pullRequests", "pullRequests", "card.title.pulls", "github", true),
        new("github.inbox", "inbox", "card.title.inbox", "github", true),
        new("github.actions", "actions", "card.title.actions", "github", false),
        new("gitlab.mergeRequests", "mergeRequests", "card.title.merges.gitlab", "gitlab", true)
    ];

    public static RemoteCardSettings? Resolve(DeckSettings settings, string kind) =>
        settings.RemoteCardList.FirstOrDefault(card => card.Kind == kind);

    public static bool Available(DeckSettings settings, string kind) => settings.Workers.Length > 0 &&
        settings.AccountList.Any(account => account.Enabled && account.Provider == All.Single(item => item.Kind == kind).Provider);
    public static bool Active(DeckSettings settings, RemoteCardSettings card) => card.Enabled &&
        card.AccountIDs.Any(id => settings.AccountList.Any(account => account.Id == id && account.Enabled));

    public static DeckSettings RemoveAccount(DeckSettings settings, string id) => settings with {
        Accounts = settings.AccountList.Where(account => account.Id != id).ToArray(),
        RemoteCards = settings.RemoteCardList.Select(card => {
            var ids = card.AccountIDs.Where(accountID => accountID != id).ToArray();
            return card.AccountIDs.SequenceEqual(ids) ? card : card with { AccountIDs = ids,
                Enabled = card.Enabled && (card.UseAllAccounts || ids.Length > 0) };
        }).ToArray()
    };

    public static DeckSettings Synchronize(DeckSettings settings, Func<string, string> title,
        Func<DeckSettings, (double X, double Y)>? placement = null)
    {
        var cards = settings.RemoteCardList.Select(card => {
            if (!card.UseAllAccounts) return card;
            var provider = All.Single(item => item.Kind == card.Kind).Provider;
            var ids = settings.AccountList.Where(account => account.Provider == provider).Select(account => account.Id).ToArray();
            return card.AccountIDs.SequenceEqual(ids) ? card : card with { AccountIDs = ids };
        }).ToArray();
        var result = cards.SequenceEqual(settings.RemoteCardList) ? settings : settings with { RemoteCards = cards };
        foreach (var descriptor in All) {
            if (Resolve(result, descriptor.Kind) is not null || !Available(result, descriptor.Kind)) continue;
            result = Add(result, descriptor, descriptor.EnabledByDefault, title, placement);
        }
        return result;
    }

    public static DeckSettings SetEnabled(DeckSettings settings, string kind, bool enabled, Func<string, string> title,
        Func<DeckSettings, (double X, double Y)>? placement = null)
    {
        var existing = Resolve(settings, kind);
        if (existing is not null) return settings with { RemoteCards = settings.RemoteCardList.Select(card => {
            if (card.Id != existing.Id) return card;
            if (enabled && card.AccountIDs.Length == 0) return card with { Enabled = true, UseAllAccounts = true,
                AccountIDs = settings.AccountList.Where(account => account.Provider == All.Single(item => item.Kind == kind).Provider).Select(account => account.Id).ToArray() };
            return card with { Enabled = enabled };
        }).ToArray() };
        if (!Available(settings, kind)) throw new InvalidOperationException("No enabled account or worker is configured.");
        return Add(settings, All.Single(item => item.Kind == kind), enabled, title, placement);
    }

    private static DeckSettings Add(DeckSettings settings, RemoteCardDescriptor descriptor, bool enabled,
        Func<string, string> title, Func<DeckSettings, (double X, double Y)>? placement)
    {
        var point = placement?.Invoke(settings) ?? (48d + 430 * (settings.Cards.Length + settings.RemoteCardList.Length), 80d);
        var card = new RemoteCardSettings(descriptor.Id, title(descriptor.TitleKey), descriptor.Kind, settings.Workers[0].Distribution,
            settings.AccountList.Where(account => account.Provider == descriptor.Provider).Select(account => account.Id).ToArray(),
            enabled, point.Item1, point.Item2, UseAllAccounts: true);
        return settings with { RemoteCards = settings.RemoteCardList.Append(card).ToArray() };
    }
}
