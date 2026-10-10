using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DevDeck.Shell;

namespace DevDeck.Shell.Tests;

public static class W8Screenshots
{
    public static void Generate(string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        Capture(
            "Project · Feed",
            new DeckLog([], "tail feed.log", "nothing has been started from here yet"),
            null,
            Path.Combine(outputDirectory, "w8-log-detail.png"));
        var live = new DeckLog(
            [
                "ready on http://localhost:4173",
                "GET / 200 12 ms",
                "GET /assets/app.css 200 4 ms",
                "GET /api/status 200 7 ms",
                "GET /api/status 200 6 ms",
            ],
            "tail sample-web.log",
            null);
        Capture("Project · Sample Web", live, null, Path.Combine(outputDirectory, "w8-log-live.png"));
        Capture("Project · Sample Web", live, "api", Path.Combine(outputDirectory, "w8-log-search.png"));
    }

    private static void Capture(string title, DeckLog log, string? query, string path)
    {
        var window = new LogWindow("project.capture")
        {
            Width = 720,
            Height = 440,
            Left = -10000,
            Top = -10000,
            ShowInTaskbar = false,
        };
        window.SetTitle(title);
        window.Update(log);
        window.Show();
        if (query is not null)
        {
            window.SetSearchQuery(query);
        }
        window.UpdateLayout();
        window.Dispatcher.Invoke(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
        if (window.Content is not FrameworkElement content)
        {
            throw new InvalidOperationException();
        }
        var width = Math.Max(1, (int)Math.Ceiling(content.ActualWidth));
        var height = Math.Max(1, (int)Math.Ceiling(content.ActualHeight));
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(content);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var output = File.Create(path);
        encoder.Save(output);
        window.Close();
    }
}
