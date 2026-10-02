using System.Globalization;

namespace DevDeck.Windows.Core;

/// <summary>Catalog presentation order, independent of persisted array and placement order.</summary>
public static class CardOrdering
{
    public static CardSettings[] Projects(IEnumerable<CardSettings> cards, CultureInfo? culture = null) => cards
        .OrderBy(card => ProjectKind(card.Project.Kind))
        .ThenBy(card => card.Title, Titles(culture))
        .ThenBy(card => card.Project.Id, StringComparer.Ordinal).ToArray();

    public static RemoteCardSettings[] Remote(IEnumerable<RemoteCardSettings> cards, CultureInfo? culture = null)
    {
        var saved = cards.ToArray();
        // Resolve uses the first saved card of each kind. A legacy ID can therefore own a
        // built-in slot while a later canonical ID is an independent custom card.
        var roles = RemoteCardCatalog.All.Select((descriptor,index) => (card:saved.FirstOrDefault(card => card.Kind == descriptor.Kind),index))
            .Where(role => role.card is not null).ToDictionary(role => role.card!.Id,role => role.index,StringComparer.Ordinal);
        return saved.OrderBy(card => roles.GetValueOrDefault(card.Id,int.MaxValue))
            .ThenBy(card => card.Title,Titles(culture))
            .ThenBy(card => card.Id,StringComparer.Ordinal).ToArray();
    }

    public static string[] IDs(DeckSettings settings, CultureInfo? culture = null)
    {
        var remote = Remote(settings.RemoteCardList, culture);
        var roles = RemoteCardCatalog.All.Select(descriptor => RemoteCardCatalog.Resolve(settings, descriptor.Kind)?.Id)
            .Where(id => id is not null).ToHashSet(StringComparer.Ordinal);
        return remote.Where(card => roles.Contains(card.Id)).Select(card => card.Id)
            .Concat(settings.WorkInFlight is not null ? new[] { CheckoutCatalog.CardID } : [])
            .Concat(remote.Where(card => !roles.Contains(card.Id)).Select(card => card.Id))
            .Concat(Projects(settings.Cards, culture).Select(card => card.Project.Id)).ToArray();
    }

    private static int ProjectKind(string kind) => kind switch { "arc" => 0, "ddev" => 1, "local" => 2, _ => 3 };
    private static IComparer<string> Titles(CultureInfo? culture)
    {
        var comparison = (culture ?? CultureInfo.CurrentCulture).CompareInfo;
        return Comparer<string>.Create((left,right) => comparison.Compare(left,right,CompareOptions.IgnoreCase | CompareOptions.NumericOrdering));
    }
}
