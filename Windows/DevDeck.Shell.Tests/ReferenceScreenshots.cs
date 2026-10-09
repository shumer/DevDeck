using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DevDeck.Shell;

namespace DevDeck.Shell.Tests;

public static class ReferenceScreenshots
{
    public static void Generate(string fixturePath, string outputPath, double scale)
    {
        var cards = new Dictionary<string, FrameworkElement>(StringComparer.Ordinal);
        foreach (var line in File.ReadLines(fixturePath))
        {
            var message = DeckEvent.Parse(line);
            if (message.Event == "card.changed" && message.Model is { } model && message.Card is { } cardId)
            {
                var card = CardRenderer.Create(model, _ => { });
                card.Width = 352;
                cards[cardId] = card;
            }
        }

        var surface = new Canvas
        {
            Width = 772,
            Height = 500,
            Background = new LinearGradientBrush(
                Color.FromRgb(11, 20, 36),
                Color.FromRgb(16, 37, 68),
                new Point(0, 0),
                new Point(1, 1)),
        };

        Place(surface, cards["github.pullRequests"], 28, 28);
        var wsl = cards["project.wsl"];
        Place(surface, wsl, 392, 28);
        wsl.Measure(new Size(352, double.PositiveInfinity));
        Place(surface, cards["project.windows"], 392, 28 + wsl.DesiredSize.Height + 12);

        surface.Measure(new Size(surface.Width, surface.Height));
        surface.Arrange(new Rect(0, 0, surface.Width, surface.Height));
        surface.UpdateLayout();
        var width = (int)Math.Ceiling(surface.Width * scale);
        var height = (int)Math.Ceiling(surface.Height * scale);
        var dpi = 96 * scale;
        var bitmap = new RenderTargetBitmap(width, height, dpi, dpi, PixelFormats.Pbgra32);
        bitmap.Render(surface);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var output = File.Create(outputPath);
        encoder.Save(output);
        Console.WriteLine($"Rendered {cards.Count} cards at {scale.ToString("P0", CultureInfo.InvariantCulture)}.");
    }

    private static void Place(Canvas surface, FrameworkElement card, double left, double top)
    {
        Canvas.SetLeft(card, left);
        Canvas.SetTop(card, top);
        surface.Children.Add(card);
    }
}
