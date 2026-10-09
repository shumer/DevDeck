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
        var cards = new List<FrameworkElement>();
        foreach (var line in File.ReadLines(fixturePath))
        {
            var message = DeckEvent.Parse(line);
            if (message.Event == "card.changed" && message.Model is { } model)
            {
                var card = CardRenderer.Create(model, _ => { });
                card.Width = 352;
                cards.Add(card);
            }
        }

        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(20),
        };
        foreach (var card in cards)
        {
            card.Margin = new Thickness(8);
            card.VerticalAlignment = VerticalAlignment.Top;
            row.Children.Add(card);
        }
        var surface = new Border
        {
            Background = new SolidColorBrush(Color.FromRgb(17, 17, 21)),
            Child = row,
        };
        surface.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        surface.Arrange(new Rect(surface.DesiredSize));
        surface.UpdateLayout();
        var width = (int)Math.Ceiling(surface.ActualWidth * scale);
        var height = (int)Math.Ceiling(surface.ActualHeight * scale);
        var dpi = 96 * scale;
        var bitmap = new RenderTargetBitmap(width, height, dpi, dpi, PixelFormats.Pbgra32);
        bitmap.Render(surface);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var output = File.Create(outputPath);
        encoder.Save(output);
        Console.WriteLine($"Rendered {cards.Count} cards at {scale.ToString("P0", CultureInfo.InvariantCulture)}.");
    }
}
