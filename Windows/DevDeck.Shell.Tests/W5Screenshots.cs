using System.Text.Json;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DevDeck.Shell;

namespace DevDeck.Shell.Tests;

public static class W5Screenshots
{
    public static void Generate(string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        CaptureMenu("runtime-menu-en.expected.jsonl", "menu", "w5-tray-menu-en.png", outputDirectory);
        CaptureMenu("runtime-menu-ru.expected.jsonl", "menu", "w5-tray-menu-ru.png", outputDirectory);
        CaptureMenu("runtime-menu-en.expected.jsonl", "projectMenu", "w5-card-context-menu.png", outputDirectory);
        CaptureDialog(outputDirectory, prompt: false);
        CaptureDialog(outputDirectory, prompt: true);
        CaptureIcons(outputDirectory, light: true);
        CaptureIcons(outputDirectory, light: false);
    }

    private static void CaptureMenu(string transcript, string step, string fileName, string outputDirectory)
    {
        var presenter = new MenuPresenter(_ => { });
        presenter.Update(ReadStep(transcript, step));
        var view = presenter.View;
        view.Width = 390;
        Capture(view, Path.Combine(outputDirectory, fileName), 390, 1500, cropHeight: true);
    }

    private static void CaptureDialog(string outputDirectory, bool prompt)
    {
        var items = Flatten(DeckMenuEntryModel.ParseList(ReadStep("runtime-menu-en.expected.jsonl", "menu")))
            .Select(entry => entry.Item)
            .Where(item => item is not null)
            .ToArray();
        DeckMenuDialogModel model = prompt
            ? items.Single(item => item?.Prompt is not null)?.Prompt ?? throw new InvalidOperationException()
            : items.Single(item => item?.Confirmation is not null)?.Confirmation ?? throw new InvalidOperationException();
        var window = MenuDialogs.Build(
            model,
            prompt ? ((DeckMenuPromptModel)model).Placeholder : null,
            out _,
            out _);
        var content = (FrameworkElement)window.Content;
        content.Width = 420;
        Capture(
            content,
            Path.Combine(outputDirectory, prompt ? "w5-prompt.png" : "w5-confirmation.png"),
            468,
            500,
            cropHeight: true);
        window.Close();
    }

    private static void CaptureIcons(string outputDirectory, bool light)
    {
        var background = light ? Color.FromRgb(242, 242, 242) : Color.FromRgb(32, 32, 32);
        var foreground = light ? Brushes.Black : Brushes.White;
        var grid = new Grid
        {
            Width = 520,
            Height = 108,
            Background = new SolidColorBrush(background),
        };
        var states = new (int? Tier, string Label)[]
        {
            (null, "Calm"),
            (0, "Waiting"),
            (1, "Needs fixing"),
            (2, "Stuck"),
            (3, "Good to know"),
        };
        for (var index = 0; index < states.Length; index++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            var panel = new StackPanel
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            };
            panel.Children.Add(new Image
            {
                Source = TrayIconFactory.Preview(32, states[index].Tier, light),
                Width = 32,
                Height = 32,
                HorizontalAlignment = HorizontalAlignment.Center,
            });
            panel.Children.Add(new TextBlock
            {
                Text = states[index].Label,
                FontFamily = WindowsTheme.Sans,
                FontSize = 12,
                Foreground = foreground,
                Margin = new Thickness(0, 10, 0, 0),
                HorizontalAlignment = HorizontalAlignment.Center,
            });
            Grid.SetColumn(panel, index);
            grid.Children.Add(panel);
        }
        Capture(
            grid,
            Path.Combine(outputDirectory, light ? "w5-tray-icons-light.png" : "w5-tray-icons-dark.png"),
            520,
            108,
            cropHeight: false);
    }

    private static JsonElement ReadStep(string transcript, string step)
    {
        var path = Path.Combine(RepositoryRoot(), "Tests", "EngineTests", "Golden", transcript);
        JsonElement? found = null;
        foreach (var line in File.ReadLines(path))
        {
            using var document = JsonDocument.Parse(line);
            if (document.RootElement.GetProperty("step").GetString() == step)
            {
                found = document.RootElement.GetProperty("value").Clone();
            }
        }
        return found ?? throw new InvalidOperationException();
    }

    private static IEnumerable<DeckMenuEntryModel> Flatten(IReadOnlyList<DeckMenuEntryModel> entries)
    {
        foreach (var entry in entries)
        {
            yield return entry;
            foreach (var child in Flatten(entry.Children))
            {
                yield return child;
            }
        }
    }

    private static void Capture(
        FrameworkElement element,
        string path,
        int width,
        int maximumHeight,
        bool cropHeight)
    {
        element.Measure(new Size(width, maximumHeight));
        var height = cropHeight ? Math.Min(maximumHeight, (int)Math.Ceiling(element.DesiredSize.Height)) : maximumHeight;
        element.Arrange(new Rect(0, 0, width, height));
        element.UpdateLayout();
        var bitmap = new RenderTargetBitmap(width, Math.Max(1, height), 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(element);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var output = File.Create(path);
        encoder.Save(output);
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
