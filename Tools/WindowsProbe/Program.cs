using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace WindowsProbe;

internal sealed class WslWorker : IAsyncDisposable
{
    private readonly Process process;
    private readonly Task<string> errors;
    private readonly SemaphoreSlim gate = new(1);
    private int sequence;

    public WslWorker(string distribution, string worker)
    {
        var start = new ProcessStartInfo("wsl.exe")
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true
        };
        foreach (var arg in new[] { "--distribution", distribution, "--exec", "python3", "-u", worker })
            start.ArgumentList.Add(arg);
        process = Process.Start(start) ?? throw new IOException("Cannot launch WSL worker.");
        errors = process.StandardError.ReadToEndAsync();
    }

    public async Task<JsonElement> Call(string action)
    {
        await gate.WaitAsync();
        try
        {
            int id = ++sequence;
            await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(new { id, action }));
            await process.StandardInput.FlushAsync();
            string? line;
            try { line = await process.StandardOutput.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(25)); }
            catch (TimeoutException)
            {
                // Closing input lets the worker clean up after its bounded operation finishes.
                process.StandardInput.Close();
                throw new TimeoutException("WSL worker timed out; restart the probe to reconnect.");
            }
            if (line is null) throw new IOException("WSL worker ended: " + await errors);
            using var document = JsonDocument.Parse(line);
            var response = document.RootElement;
            if (response.GetProperty("protocol").GetInt32() != 1 || response.GetProperty("id").GetInt32() != id)
                throw new IOException("WSL protocol mismatch.");
            if (!response.GetProperty("ok").GetBoolean()) throw new IOException(response.GetProperty("error").GetString());
            return response.GetProperty("result").Clone();
        }
        finally { gate.Release(); }
    }

    public async ValueTask DisposeAsync()
    {
        process.StandardInput.Close();
        try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(20)); }
        catch (TimeoutException) { process.Kill(entireProcessTree: true); }
        process.Dispose();
    }
}

internal static class Native
{
    [DllImport("user32.dll", SetLastError = true)]
    internal static extern bool SetWindowPos(nint window, nint after, int x, int y, int cx, int cy, uint flags);
}

internal sealed class Card : Window
{
    private readonly TextBlock status = new() { Text = "Ready to test", FontSize = 22, Margin = new(0, 16, 0, 8) };
    private readonly TextBlock detail = new() { Text = "A disposable server in WSL. Your projects are untouched.", TextWrapping = TextWrapping.Wrap, Foreground = Brushes.LightGray };
    private readonly TextBox logs = new() { IsReadOnly = true, Height = 116, Text = "No demo started yet.", TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Background = new SolidColorBrush(Color.FromRgb(18, 24, 33)), Foreground = Brushes.LightGray, BorderThickness = new(0), Margin = new(0, 14, 0, 12), FontFamily = new("Consolas"), FontSize = 12 };
    private readonly List<Button> actions = [];
    private readonly WslWorker worker;
    private readonly System.Windows.Threading.DispatcherTimer poll;
    private bool busy;
    private bool closing;
    private bool floating;
    private nint handle;
    internal bool ModeApplied { get; private set; }

    internal Card(WslWorker worker)
    {
        this.worker = worker;
        Title = "DevDeck · Windows feasibility probe";
        Width = 430; Height = 390; Left = 48; Top = 80;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = Brushes.Transparent;
        ShowInTaskbar = false; ShowActivated = false;
        Foreground = Brushes.White;
        var panel = new StackPanel { Margin = new(22) };
        var header = new DockPanel();
        var close = Button("×", async () => { await Task.CompletedTask; Close(); });
        DockPanel.SetDock(close, Dock.Right); header.Children.Add(close);
        var title = new TextBlock { Text = "DEVDECK / WINDOWS PROBE", FontSize = 12, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
        title.MouseLeftButtonDown += (_, e) => { if (e.LeftButton == MouseButtonState.Pressed) DragMove(); };
        header.Children.Add(title); panel.Children.Add(header);
        panel.Children.Add(status); panel.Children.Add(detail); panel.Children.Add(logs);
        var commands = new WrapPanel();
        foreach (string action in new[] { "start", "stop", "restart", "status" })
        {
            var button = Button(char.ToUpperInvariant(action[0]) + action[1..], () => Run(action));
            actions.Add(button); commands.Children.Add(button);
        }
        panel.Children.Add(commands);
        var modes = new StackPanel { Orientation = Orientation.Horizontal, Margin = new(0, 12, 0, 0) };
        var mode = new CheckBox { Content = "Float above windows", Foreground = Brushes.LightGray, VerticalAlignment = VerticalAlignment.Center };
        mode.Checked += (_, _) => SetMode(true); mode.Unchecked += (_, _) => SetMode(false);
        modes.Children.Add(mode);
        panel.Children.Add(modes);
        Content = new Border { Background = new SolidColorBrush(Color.FromArgb(242, 29, 37, 50)), BorderBrush = new SolidColorBrush(Color.FromRgb(76, 91, 111)), BorderThickness = new(1), CornerRadius = new(20), Child = panel };
        SourceInitialized += (_, _) =>
        {
            handle = new WindowInteropHelper(this).Handle;
            HwndSource.FromHwnd(handle)?.AddHook((nint hwnd, int message, nint wparam, nint lparam, ref bool handled) =>
            {
                // First click is delivered without bringing a desktop card into the foreground.
                if (message == 0x21 && !floating) { handled = true; return (nint)3; }
                return 0;
            });
            SetMode(false);
        };
        Deactivated += (_, _) => { if (!floating) SetMode(false); };
        poll = new(TimeSpan.FromSeconds(3), System.Windows.Threading.DispatcherPriority.Background,
            async (_, _) => { if (!busy && !closing) await Run("status"); }, Dispatcher);
        Closing += async (_, e) =>
        {
            if (closing) return;
            e.Cancel = true; closing = true; poll.Stop();
            try { await worker.DisposeAsync(); } catch { /* Window must still be closable after a worker failure. */ }
            Close();
        };
    }

    private static Button Button(string title, Func<Task> action)
    {
        var button = new Button { Content = title, Padding = new(10, 5, 10, 5), Margin = new(0, 0, 6, 0), Background = new SolidColorBrush(Color.FromRgb(46, 59, 78)), Foreground = Brushes.White, BorderThickness = new(0) };
        button.Click += async (_, _) => await action();
        return button;
    }

    internal void SetMode(bool value)
    {
        floating = value;
        if (handle != 0)
            ModeApplied = Native.SetWindowPos(handle, value ? (nint)(-1) : (nint)1, 0, 0, 0, 0, 0x13);
    }

    private async Task Run(string action)
    {
        if (busy || closing) return;
        busy = true; actions.ForEach(button => button.IsEnabled = false);
        try
        {
            var result = await worker.Call(action);
            bool running = result.GetProperty("running").GetBoolean();
            status.Text = running ? "● Demo is running" : "○ Demo is stopped";
            status.Foreground = running ? Brushes.LightGreen : Brushes.White;
            detail.Text = result.GetProperty("url").GetString() ?? "Start creates a temporary HTTP server inside WSL.";
            logs.Text = result.GetProperty("logs").GetString();
        }
        catch (Exception error) { status.Text = "Probe needs attention"; detail.Text = error.Message; }
        finally { busy = false; actions.ForEach(button => button.IsEnabled = true); }
    }

    internal void Render(string path)
    {
        UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)Width, (int)Height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(this);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var output = File.Create(path); encoder.Save(output);
    }
}

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        string Option(string key, string fallback) => Array.IndexOf(args, key) is var index && index >= 0 && index + 1 < args.Length ? args[index + 1] : fallback;
        string distribution = Option("--distribution", "Ubuntu-24.04");
        string workerPath = Option("--worker", "/home/ashumenko/Projects/DevDeck/Tools/WindowsProbe/worker.py");
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        if (args.Contains("--self-test"))
        {
            string report = Path.GetFullPath(Option("--report", "windows-probe-results.json"));
            var results = new List<object>();
            int exit = 0;
            app.Startup += async (_, _) =>
            {
                try
                {
                    await using var worker = new WslWorker(distribution, workerPath);
                    void Check(string name, bool passed) { results.Add(new { name, passed }); if (!passed) throw new Exception(name); }
                    var environment = await worker.Call("environment");
                    results.Add(new { name = "environment", data = environment });
                    Check("Docker daemon answers inside selected WSL", environment.GetProperty("dockerReady").GetBoolean());
                    var initial = await worker.Call("status"); Check("Demo starts stopped", !initial.GetProperty("running").GetBoolean());
                    var started = await worker.Call("start"); Check("Start verified by WSL health", started.GetProperty("running").GetBoolean());
                    Check("Demo child is running", started.GetProperty("childAlive").GetBoolean());
                    using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
                    string url = started.GetProperty("url").GetString()!;
                    using var health = JsonDocument.Parse(await http.GetStringAsync(url));
                    Check("Windows localhost reaches the owned WSL server", health.RootElement.GetProperty("probe").GetString() == started.GetProperty("marker").GetString());
                    var repeated = await worker.Call("start"); Check("Start is idempotent", repeated.GetProperty("pid").GetInt32() == started.GetProperty("pid").GetInt32());
                    Check("Server logs available", !string.IsNullOrEmpty(repeated.GetProperty("logs").GetString()));
                    var restarted = await worker.Call("restart"); Check("Restart replaces process and health answers", restarted.GetProperty("running").GetBoolean() && restarted.GetProperty("pid").GetInt32() != started.GetProperty("pid").GetInt32());
                    var stopped = await worker.Call("stop"); Check("Stop removes owned process and health", !stopped.GetProperty("running").GetBoolean() && stopped.GetProperty("pid").ValueKind == JsonValueKind.Null);
                    Check("Stop terminates the demo child too", !stopped.GetProperty("childAlive").GetBoolean());
                    bool rejected = false;
                    try { await worker.Call("unsupported"); } catch (IOException) { rejected = true; }
                    Check("Unsupported action rejected", rejected);
                    Check("Worker remains usable after rejection", !(await worker.Call("status")).GetProperty("running").GetBoolean());
                    string eofUrl;
                    await using (var eofWorker = new WslWorker(distribution, workerPath))
                    {
                        eofUrl = (await eofWorker.Call("start")).GetProperty("url").GetString()!;
                    }
                    bool eofStopped = false;
                    try { await http.GetStringAsync(eofUrl); } catch (HttpRequestException) { eofStopped = true; }
                    Check("Closing worker input cleans up its active server", eofStopped);
                    await using (var missing = new WslWorker(distribution, workerPath + ".missing"))
                    {
                        bool missingRejected = false;
                        try { await missing.Call("status"); } catch (IOException) { missingRejected = true; }
                        Check("Missing worker produces a visible protocol failure", missingRejected);
                    }
                    var card = new Card(worker); card.Show();
                    Check("Bottom mode accepted by Win32", card.ModeApplied);
                    card.SetMode(true); Check("Floating mode accepted by Win32", card.ModeApplied);
                    card.SetMode(false);
                    await Task.Delay(200);
                    card.Render(Path.ChangeExtension(report, ".png"));
                    card.Hide();
                    // End the worker explicitly; do not use the card's interactive Closing path here.
                }
                catch (Exception error) { exit = 1; results.Add(new { name = "failure", error = error.ToString() }); }
                try
                {
                    File.WriteAllText(report, JsonSerializer.Serialize(new { date = "2026-09-30", distribution, architecture = RuntimeInformation.OSArchitecture.ToString(), results, manualDesktopChecks = "Pending: Win+D, inactive clicks, virtual desktops, DPI, fullscreen, hot-plug, Explorer restart" }, new JsonSerializerOptions { WriteIndented = true }));
                }
                catch (Exception error) { Debug.WriteLine(error); exit = 1; }
                app.Shutdown(exit);
            };
            app.Run(); return exit;
        }
        var cardWindow = new Card(new WslWorker(distribution, workerPath));
        cardWindow.Closed += (_, _) => app.Shutdown();
        app.Run(cardWindow); return 0;
    }
}
