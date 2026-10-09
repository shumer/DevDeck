using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DevDeck.Shell;

namespace DevDeck.Shell.Tests;

public static class GoldenCardScreenshots
{
    private static readonly IReadOnlyDictionary<string, string> FileNames =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["github.pullRequests"] = "w4-github-pull-requests.png",
            ["github.inbox"] = "w4-github-inbox.png",
            ["github.actions"] = "w4-github-actions.png",
            ["gitlab.mergeRequests"] = "w4-gitlab-merge-requests.png",
            ["local.workInFlight"] = "w4-work-in-flight.png",
            ["arc.project.paper"] = "w4-arc-project.png",
            ["ddev.project.shop"] = "w4-ddev-project.png",
            ["project.feed"] = "w4-plain-project.png",
        };

    public static void Generate(string fixturePath, string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        var models = ReadModels(fixturePath);
        foreach (var pair in FileNames)
        {
            var cards = models[pair.Key].Select(model => CardRenderer.Create(model, _ => { })).ToArray();
            Render(cards, Path.Combine(outputDirectory, pair.Value));
        }

        var collapsed = new List<FrameworkElement>();
        foreach (var cardId in FileNames.Keys)
        {
            var model = models[cardId].Last().EnumerateObject().Single().Value;
            if (JsonModel.Object(model, "collapsed", out var row))
            {
                collapsed.Add(WindowsCardRenderer.Stopped(row, _ => { }));
            }
        }
        Render(collapsed, Path.Combine(outputDirectory, "w4-collapsed-cards.png"));
    }

    private static IReadOnlyDictionary<string, IReadOnlyList<System.Text.Json.JsonElement>> ReadModels(string fixturePath)
    {
        var models = FileNames.Keys.ToDictionary(
            cardId => cardId,
            _ => new List<System.Text.Json.JsonElement>(),
            StringComparer.Ordinal);
        var bytes = File.ReadAllLines(fixturePath);
        foreach (var line in bytes)
        {
            var message = DeckEvent.Parse(line);
            if (message.Event != "card.changed" ||
                message.Card is not { } cardId ||
                message.Model is not { } model ||
                !models.TryGetValue(cardId, out var cardModels))
            {
                continue;
            }
            if (cardModels.All(existing => existing.GetRawText() != model.GetRawText()))
            {
                cardModels.Add(model.Clone());
            }
        }
        return models.ToDictionary(
            pair => pair.Key,
            pair => (IReadOnlyList<System.Text.Json.JsonElement>)pair.Value,
            StringComparer.Ordinal);
    }

    private static void Render(IReadOnlyList<FrameworkElement> cards, string outputPath)
    {
        const double padding = 24;
        const double gap = 12;
        var height = padding;
        foreach (var card in cards)
        {
            card.Width = 352;
            card.Measure(new Size(352, double.PositiveInfinity));
            card.Arrange(new Rect(0, 0, 352, card.DesiredSize.Height));
            height += card.DesiredSize.Height + gap;
        }
        height += padding - gap;

        var surface = new Canvas
        {
            Width = 400,
            Height = Math.Ceiling(height),
            Background = new LinearGradientBrush(
                Color.FromRgb(11, 20, 36),
                Color.FromRgb(16, 37, 68),
                new Point(0, 0),
                new Point(1, 1)),
        };
        var top = padding;
        foreach (var card in cards)
        {
            Canvas.SetLeft(card, padding);
            Canvas.SetTop(card, top);
            surface.Children.Add(card);
            top += card.DesiredSize.Height + gap;
        }
        surface.Measure(new Size(surface.Width, surface.Height));
        surface.Arrange(new Rect(0, 0, surface.Width, surface.Height));
        surface.UpdateLayout();

        var bitmap = new RenderTargetBitmap(
            (int)surface.Width,
            (int)surface.Height,
            96,
            96,
            PixelFormats.Pbgra32);
        bitmap.Render(surface);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var output = File.Create(outputPath);
        encoder.Save(output);
    }
}
