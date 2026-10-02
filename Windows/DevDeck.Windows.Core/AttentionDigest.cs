using System.Globalization;

namespace DevDeck.Windows.Core;

public sealed record AttentionDigestSection(string Tier, AttentionItem[] Visible, AttentionItem[] Overflow)
{
    public string? OverflowTitle(Localization localization) => Overflow.Length == 0 ? null : localization.Plural("attention.more." + (Tier switch {
        "waiting" => "waiting", "needsFixing" => "toFix", "stuck" => "stuck", _ => "other"
    }),Overflow.Length);
}

/// Presentation of the already validated, merged worker signals; their priority stays authoritative.
public static class AttentionDigest
{
    public const int RowsPerSection = 3;
    public const int RowsForGoodToKnow = 2;
    private static readonly string[] Tiers = ["waiting","needsFixing","stuck","goodToKnow"];

    public static AttentionDigestSection[] Sections(IEnumerable<AttentionItem> orderedItems)
    {
        var items = orderedItems.ToArray();
        return Tiers.Select(tier => {
            var rows = items.Where(item => item.Tier == tier).ToArray();
            var cap = tier == "goodToKnow" ? RowsForGoodToKnow : RowsPerSection;
            // Hiding one leftover behind a submenu takes the same line as showing the item.
            return rows.Length <= cap + 1 ? new AttentionDigestSection(tier,rows,[]) : new(tier,rows[..cap],rows[cap..]);
        }).Where(section => section.Visible.Length > 0).ToArray();
    }

    public static string? Age(double? since, DateTimeOffset now, Localization localization)
    {
        if (since is not { } date || !double.IsFinite(date) || date < 0 || date > 253402300799) return null;
        var seconds = Math.Max(0,now.ToUnixTimeMilliseconds() / 1000d - date);
        return seconds < 60 ? localization.Get("attention.age.now")
            : seconds < 3600 ? localization.Get("attention.age.minutes",(long)(seconds / 60))
            : seconds < 86400 ? localization.Get("attention.age.hours",(long)(seconds / 3600))
            : localization.Get("attention.age.days",(long)(seconds / 86400));
    }

    /// Matches Swift Character counting, so a combining mark or joined emoji is never split.
    public static string TrimSubtitle(string text, int limit = 72)
    {
        if (limit < 1) throw new ArgumentOutOfRangeException(nameof(limit));
        var elements = StringInfo.ParseCombiningCharacters(text);
        if (elements.Length <= limit) return text;
        var count = limit - 1;
        var space = -1;
        for (var index = 0;index < count;index++) {
            var end = index + 1 < elements.Length ? elements[index+1] : text.Length;
            if (end - elements[index] == 1 && text[elements[index]] == ' ') space = index;
        }
        if (space > limit / 2) count = space;
        return text[..elements[count]] + "…";
    }

    public static string Clock(DateTimeOffset date) => date.ToLocalTime().ToString("HH:mm",CultureInfo.InvariantCulture);
}
