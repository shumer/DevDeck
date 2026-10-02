using System.Globalization;

namespace DevDeck.Windows.Core;

/// Platform delivery only. The Swift kits decide which items require attention.
public sealed class AttentionTracker
{
    private readonly Dictionary<string, RemoteAttention[]> cards = new(StringComparer.Ordinal);
    private readonly HashSet<string> announced = new(StringComparer.Ordinal);
    private readonly Dictionary<string, AttentionItem[]> signals = new(StringComparer.Ordinal);
    private static int Tier(string tier) => tier switch { "waiting" => 0, "needsFixing" => 1, "stuck" => 2, _ => 3 };
    public AttentionItem[] SignalItems => signals.Values.SelectMany(value => value)
        .OrderBy(item => Tier(item.Tier)).DistinctBy(item => item.Key, StringComparer.Ordinal)
        .OrderBy(item => Tier(item.Tier)).ThenBy(item => item.Tier == "waiting" ? item.Since ?? double.MinValue : -(item.Since ?? double.MinValue))
        .ThenBy(item => item.Title, Comparer<string>.Create((left,right) => CultureInfo.CurrentCulture.CompareInfo.Compare(left,right,CompareOptions.IgnoreCase | CompareOptions.NumericOrdering))).ToArray();
    public int BadgeCount => SignalItems.Count(item => item.Tier != "goodToKnow");
    public void Observe(AttentionSnapshot snapshot) => signals[snapshot.Scope] = snapshot.Items;
    public void Reset() { cards.Clear(); signals.Clear(); }
    public void RemoveScope(string scope) { cards.Remove(scope); signals.Remove(scope); }
    public void PruneScope(string scope, Func<AttentionItem, bool> keep)
    {
        if (signals.TryGetValue(scope, out var items)) signals[scope] = items.Where(keep).ToArray();
    }
    public RemoteAttention[] Items => cards.Values.SelectMany(value => value).DistinctBy(value => value.Key, StringComparer.Ordinal).ToArray();
    public RemoteAttention[] Observe(RemoteSnapshot snapshot)
    {
        var first = !cards.ContainsKey(snapshot.CardID);
        var previous = Items.Select(item => item.Key).ToHashSet(StringComparer.Ordinal);
        cards[snapshot.CardID] = snapshot.Attention ?? [];
        var candidates = (snapshot.Attention ?? []).Where(item => !first && !previous.Contains(item.Key) && !announced.Contains(item.Key)).ToArray();
        foreach (var item in snapshot.Attention ?? []) announced.Add(item.Key);
        return candidates;
    }
    public void Retain(string[] cardIDs)
    {
        foreach (var id in cards.Keys.Where(id => !cardIDs.Contains(id)).ToArray()) cards.Remove(id);
        foreach (var id in signals.Keys.Where(id => !cardIDs.Contains(id)).ToArray()) signals.Remove(id);
    }
}
