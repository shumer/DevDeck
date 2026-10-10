using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DevDeck.Shell;

namespace DevDeck.Shell.Tests;

public static class W6Screenshots
{
    public static void Generate(string outputDirectory)
    {
        WindowsTheme.EnsureLoaded();
        Directory.CreateDirectory(outputDirectory);
        var github = RuntimeNotifications("runtime-banners-en.expected.jsonl");
        Capture(github[0], "w6-toast-github.png", outputDirectory);
        Capture(github[1], "w6-toast-summary.png", outputDirectory);
        Capture(GitLabNotification(), "w6-toast-gitlab.png", outputDirectory);
        Capture(ProjectNotification(), "w6-toast-project.png", outputDirectory);
        Capture(SessionNotification("session-settings-ru.expected.jsonl"), "w6-toast-devdeck.png", outputDirectory);
    }

    private static DeckNotification GitLabNotification()
    {
        var menu = RuntimeStep("runtime-menu-en.expected.jsonl", "menu", last: true);
        var item = Descendants(menu)
            .Where(value => value.ValueKind == JsonValueKind.Object)
            .First(value =>
                JsonModel.Object(value, "image", out var image) &&
                JsonModel.Object(image, "attention", out var attention) &&
                attention.TryGetProperty("_0", out var source) &&
                source.TryGetProperty("gitlab", out _));
        return new DeckNotification(
            "gitlab.golden",
            "gitlab",
            item.GetProperty("title").GetString() ?? throw new JsonException(),
            item.GetProperty("subtitle").GetString() ?? throw new JsonException(),
            "",
            false,
            JsonModel.Command(item) ?? throw new JsonException());
    }

    private static DeckNotification ProjectNotification()
    {
        var path = Path.Combine(RepositoryRoot(), "docs", "poc", "windows-ui", "w6-project-notification.jsonl");
        return DeckEvent.Parse(File.ReadAllText(path).Trim()).Notifications?.Single() ?? throw new JsonException();
    }

    private static DeckNotification SessionNotification(string fileName)
    {
        var path = Path.Combine(RepositoryRoot(), "Tests", "EngineTests", "Golden", fileName);
        foreach (var line in File.ReadLines(path))
        {
            var notification = DeckEvent.Parse(line).Notifications?.SingleOrDefault();
            if (notification is not null)
            {
                return notification;
            }
        }
        throw new JsonException();
    }

    private static IReadOnlyList<DeckNotification> RuntimeNotifications(string fileName)
    {
        var notifications = new List<DeckNotification>();
        var path = Path.Combine(RepositoryRoot(), "Tests", "EngineTests", "Golden", fileName);
        foreach (var line in File.ReadLines(path))
        {
            using var document = JsonDocument.Parse(line);
            notifications.AddRange(ReplayNotificationAdapter.Parse(document.RootElement.GetProperty("value")));
        }
        return notifications;
    }

    private static JsonElement RuntimeStep(string fileName, string stepName, bool last)
    {
        var values = new List<JsonElement>();
        var path = Path.Combine(RepositoryRoot(), "Tests", "EngineTests", "Golden", fileName);
        foreach (var line in File.ReadLines(path))
        {
            using var document = JsonDocument.Parse(line);
            if (document.RootElement.GetProperty("step").GetString() == stepName)
            {
                values.Add(document.RootElement.GetProperty("value").Clone());
            }
        }
        return last ? values.Last() : values.First();
    }

    private static IEnumerable<JsonElement> Descendants(JsonElement value)
    {
        yield return value;
        if (value.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in value.EnumerateObject())
            {
                foreach (var child in Descendants(property.Value))
                {
                    yield return child;
                }
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in value.EnumerateArray())
            {
                foreach (var child in Descendants(item))
                {
                    yield return child;
                }
            }
        }
    }

    private static void Capture(DeckNotification notification, string fileName, string outputDirectory)
    {
        var toast = Toast(notification);
        const int width = 480;
        const int height = 230;
        toast.Measure(new Size(width, height));
        toast.Arrange(new Rect(0, 0, width, height));
        toast.UpdateLayout();
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(toast);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var output = File.Create(Path.Combine(outputDirectory, fileName));
        encoder.Save(output);
    }

    private static FrameworkElement Toast(DeckNotification notification)
    {
        var content = new Grid { Margin = new Thickness(20) };
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(52) });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var markTile = new Border
        {
            Width = 42,
            Height = 42,
            CornerRadius = new CornerRadius(10),
            Background = new SolidColorBrush(Color.FromRgb(26, 30, 36)),
            Child = BrandMarks.Create(notification.Source, 26),
            VerticalAlignment = VerticalAlignment.Top,
        };
        content.Children.Add(markTile);

        var words = new StackPanel();
        Grid.SetColumn(words, 1);
        words.Children.Add(Text("DevDeck", 12, FontWeights.SemiBold, Color.FromRgb(190, 190, 194), 0));
        words.Children.Add(Text(notification.Title, 16, FontWeights.SemiBold, Colors.White, 11));
        if (notification.Subtitle.Length > 0)
        {
            words.Children.Add(Text(notification.Subtitle, 13, FontWeights.Normal, Color.FromRgb(205, 205, 209), 5));
        }
        if (notification.Body.Length > 0)
        {
            words.Children.Add(Text(notification.Body, 13, FontWeights.Normal, Color.FromRgb(225, 225, 229), 6));
        }
        content.Children.Add(words);

        return new Grid
        {
            Width = 480,
            Height = 230,
            Background = new SolidColorBrush(Color.FromRgb(23, 23, 26)),
            Children =
            {
                new Border
                {
                    Margin = new Thickness(18),
                    CornerRadius = new CornerRadius(10),
                    Background = new SolidColorBrush(Color.FromRgb(47, 47, 51)),
                    BorderBrush = new SolidColorBrush(Color.FromArgb(38, 255, 255, 255)),
                    BorderThickness = new Thickness(1),
                    Child = content,
                },
            },
        };
    }

    private static TextBlock Text(string value, double size, FontWeight weight, Color color, double top)
    {
        return new TextBlock
        {
            Text = value,
            FontFamily = WindowsTheme.Sans,
            FontSize = size,
            FontWeight = weight,
            Foreground = new SolidColorBrush(color),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, top, 0, 0),
        };
    }

    private static string RepositoryRoot()
    {
        var directory = new DirectoryInfo(Directory.GetCurrentDirectory());
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "Package.swift")))
            {
                return directory.FullName;
            }
            directory = directory.Parent;
        }
        throw new DirectoryNotFoundException();
    }
}
