using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace DevDeck.Shell;

public enum DeckTextTrimming
{
    None,
    End,
    Middle,
}

public sealed class TrackedTextBlock : FrameworkElement
{
    public required string Text { get; init; }
    public required Brush Foreground { get; init; }
    public required FontFamily FontFamily { get; init; }
    public double FontSize { get; init; } = 12;
    public FontWeight FontWeight { get; init; } = FontWeights.Normal;
    public double TrackingEm { get; init; }
    public DeckTextTrimming Trimming { get; init; }
    public string RenderedText { get; private set; } = "";

    protected override Size MeasureOverride(Size availableSize)
    {
        var fullSize = MeasureText(Text);
        return new Size(
            double.IsInfinity(availableSize.Width) ? fullSize.Width : Math.Min(fullSize.Width, availableSize.Width),
            fullSize.Height);
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        RenderedText = FitText(ActualWidth);
        var x = 0.0;
        foreach (var character in RenderedText.Select(value => value.ToString()))
        {
            var formatted = Format(character);
            drawingContext.DrawText(formatted, new Point(x, 0));
            x += formatted.WidthIncludingTrailingWhitespace + TrackingEm * FontSize;
        }
    }

    private string FitText(double availableWidth)
    {
        if (Trimming == DeckTextTrimming.None || MeasureText(Text).Width <= availableWidth)
        {
            return Text;
        }

        const string ellipsis = "…";
        var low = 0;
        var high = Text.Length;
        while (low < high)
        {
            var count = (low + high + 1) / 2;
            var candidate = Trimming == DeckTextTrimming.Middle
                ? Middle(Text, count, ellipsis)
                : Text[..count] + ellipsis;
            if (MeasureText(candidate).Width <= availableWidth)
            {
                low = count;
            }
            else
            {
                high = count - 1;
            }
        }

        return Trimming == DeckTextTrimming.Middle
            ? Middle(Text, low, ellipsis)
            : Text[..low] + ellipsis;
    }

    private Size MeasureText(string value)
    {
        var width = 0.0;
        var height = 0.0;
        foreach (var character in value.Select(item => item.ToString()))
        {
            var formatted = Format(character);
            width += formatted.WidthIncludingTrailingWhitespace;
            height = Math.Max(height, formatted.Height);
        }
        if (value.Length > 1)
        {
            width += (value.Length - 1) * TrackingEm * FontSize;
        }
        return new Size(width, height);
    }

    private FormattedText Format(string value)
    {
        return new FormattedText(
            value,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface(FontFamily, FontStyles.Normal, FontWeight, FontStretches.Normal),
            FontSize,
            Foreground,
            VisualTreeHelper.GetDpi(this).PixelsPerDip);
    }

    private static string Middle(string value, int count, string ellipsis)
    {
        var left = (count + 1) / 2;
        var right = count / 2;
        return value[..left] + ellipsis + value[(value.Length - right)..];
    }
}
