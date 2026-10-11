using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DevDeck.Shell;

namespace DevDeck.Shell.Tests;

// Draws the same cards in the four schemes of the reference mock, off screen and over a plain
// backdrop, to compare the palette before it is checked on a live desktop.
public static class ThemePreview
{
    private static readonly string[] Cards = ["github.pullRequests", "arc.project.paper", "ddev.project.shop"];

    public static void Generate(string fixturePath, string outputPath)
    {
        var system = ThemeMonitor.ReadSystem();
        var variants = new (string Name, ThemeInputs Inputs, Color Backdrop)[]
        {
            ("dark", system with { AppsUseLightTheme = false, TransparencyEnabled = true, AccentOnTaskbar = false }, Color.FromRgb(58, 62, 74)),
            ("dark, accent on the taskbar", system with { AppsUseLightTheme = false, TransparencyEnabled = true, AccentOnTaskbar = true }, Color.FromRgb(58, 62, 74)),
            ("light", system with { AppsUseLightTheme = true, TransparencyEnabled = true, AccentOnTaskbar = false }, Color.FromRgb(196, 204, 214)),
            ("light, no transparency", system with { AppsUseLightTheme = true, TransparencyEnabled = false, AccentOnTaskbar = false }, Color.FromRgb(196, 204, 214)),
        };
        var models = ReadModels(fixturePath);
        // Brushes follow the palette live, so each scheme is drawn before the next one applies.
        var columns = new List<BitmapSource>();
        foreach (var (name, inputs, backdrop) in variants)
        {
            WindowsTheme.Apply(DeckPalette.For(inputs));
            var column = new StackPanel { Background = new SolidColorBrush(backdrop) };
            column.Children.Add(new TextBlock
            {
                Text = name,
                Margin = new Thickness(24, 16, 24, 8),
                FontSize = 13,
                Foreground = new SolidColorBrush(inputs.AppsUseLightTheme ? Color.FromRgb(20, 20, 20) : Color.FromRgb(240, 240, 240)),
            });
            foreach (var card in Cards)
            {
                var view = CardRenderer.Create(models[card], _ => { });
                view.Width = 352;
                view.Margin = new Thickness(24, 0, 24, 12);
                column.Children.Add(view);
            }
            columns.Add(Draw(column));
        }
        WindowsTheme.Apply(DeckPalette.For(ThemeInputs.Default));
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var column in columns)
        {
            row.Children.Add(new Image { Source = column, Width = column.Width, Height = column.Height, VerticalAlignment = VerticalAlignment.Top });
        }
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(Draw(row)));
        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        using var stream = File.Create(outputPath);
        encoder.Save(stream);
    }

    private static BitmapSource Draw(FrameworkElement view)
    {
        view.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        view.Arrange(new Rect(view.DesiredSize));
        view.UpdateLayout();
        var bitmap = new RenderTargetBitmap(
            (int)Math.Ceiling(view.ActualWidth * 2),
            (int)Math.Ceiling(view.ActualHeight * 2),
            192,
            192,
            PixelFormats.Pbgra32);
        bitmap.Render(view);
        bitmap.Freeze();
        return bitmap;
    }

    private static IReadOnlyDictionary<string, System.Text.Json.JsonElement> ReadModels(string fixturePath)
    {
        var models = new Dictionary<string, System.Text.Json.JsonElement>(StringComparer.Ordinal);
        foreach (var line in File.ReadAllLines(fixturePath))
        {
            var message = DeckEvent.Parse(line);
            if (message.Event == "card.changed" && message.Card is { } card && message.Model is { } model && Cards.Contains(card))
            {
                models[card] = model.Clone();
            }
        }
        return models;
    }
}
