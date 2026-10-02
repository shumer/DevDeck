namespace DevDeck.Windows.Core;

public sealed record MeasuredCard(string Id, double Width, double Height);
public sealed record LayoutPosition(string Id, double X, double Y);
public sealed record LayoutArea(double Left, double Top, double Width, double Height)
{
    public double Right => Left + Width;
    public double Bottom => Top + Height;
}

/// Windows top-left/DIP equivalent of the Mac DeckLayout.tidy arithmetic. Callers supply
/// visible cards in deck order, using the actual presentation height (including compact cards).
public static class ColumnLayout
{
    public const double Gap = 12;
    public static LayoutPosition[] Tidy(IReadOnlyList<MeasuredCard> cards, double anchorX, double anchorY, LayoutArea area)
    {
        if (!double.IsFinite(anchorX) || !double.IsFinite(anchorY) || !double.IsFinite(area.Left) || !double.IsFinite(area.Top)
            || !double.IsFinite(area.Right) || !double.IsFinite(area.Bottom) || area.Width <= 0 || area.Height <= 0
            || cards.Any(card => string.IsNullOrWhiteSpace(card.Id) || !double.IsFinite(card.Width) || !double.IsFinite(card.Height)
                || card.Width <= 0 || card.Height <= 0) || cards.Select(card => card.Id).Distinct(StringComparer.Ordinal).Count() != cards.Count)
            throw new ArgumentException("Invalid measured deck geometry.");
        if (cards.Count == 0) return [];
        var widest = cards.Max(card => card.Width);
        anchorX = Math.Clamp(anchorX, area.Left, Math.Max(area.Left, area.Right - widest));
        anchorY = Math.Clamp(anchorY, area.Top, Math.Max(area.Top, area.Bottom - cards[0].Height));
        var growsRight = area.Right - (anchorX + widest) >= anchorX - area.Left;
        var x = anchorX; var y = anchorY; var columnWidth = 0d; var empty = true;
        var result = new List<LayoutPosition>();
        foreach (var card in cards) {
            if (!empty && y + card.Height > area.Bottom) {
                var next = growsRight ? x + columnWidth + Gap : x - columnWidth - Gap;
                x = Math.Clamp(next, area.Left, Math.Max(area.Left, area.Right - card.Width));
                y = anchorY; columnWidth = 0; empty = true;
            }
            result.Add(new(card.Id, x, y));
            y += card.Height + Gap; columnWidth = Math.Max(columnWidth, card.Width); empty = false;
        }
        return result.ToArray();
    }
}
