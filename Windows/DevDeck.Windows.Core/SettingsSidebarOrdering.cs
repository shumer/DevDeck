using System.Globalization;

namespace DevDeck.Windows.Core;

/// Settings groups are flat projections; deck ordering and persisted arrays are independent.
public static class SettingsSidebarOrdering
{
    public static CardSettings[] Projects(IEnumerable<CardSettings> cards, CultureInfo? culture = null) => cards
        .OrderBy(card => card.Title, Titles(culture)).ToArray();

    public static RemoteAccountSettings[] Accounts(IEnumerable<RemoteAccountSettings> accounts, CultureInfo? culture = null) => accounts
        .OrderBy(account => account.Label, Titles(culture)).ToArray();

    private static IComparer<string> Titles(CultureInfo? culture)
    {
        var comparison = (culture ?? CultureInfo.CurrentCulture).CompareInfo;
        // OrderBy is stable: equivalent titles retain their saved input order.
        return Comparer<string>.Create((left, right) => comparison.Compare(left, right,
            CompareOptions.IgnoreCase | CompareOptions.NumericOrdering));
    }
}
