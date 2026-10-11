using System.Globalization;
using System.Text.Json;
using System.Windows.Threading;

namespace DevDeck.Shell;

public sealed class ProtocolState
{
    public int Revision { get; private set; }

    public void Reset()
    {
        Revision = 0;
    }

    public bool Accept(DeckEvent message)
    {
        if (message.ProtocolVersion != 2 || message.Revision <= Revision)
        {
            return false;
        }

        Revision = message.Revision;
        return true;
    }
}

public sealed class ShellCoordinator : IAsyncDisposable
{
    private readonly Dispatcher dispatcher;
    private readonly string enginePath;
    private readonly IShellSurface surface;
    private readonly DisplayWatcher displayWatcher;
    private readonly ProtocolState protocol = new();
    private readonly CancellationTokenSource cancellation = new();
    private readonly object engineLock = new();
    private EngineClient? engine;
    private readonly ProtocolTrace? trace;
    private Task? hostLoop;
    private long nextId;
    private bool beganSession;
    private bool isReplay;
    private readonly Dictionary<string, double[]> replayFrames = [];
    private readonly Dictionary<string, double> replayHeights = [];
    private readonly AsyncShutdown shutdown;

    public ShellCoordinator(Dispatcher dispatcher, string enginePath, IShellSurface surface, ProtocolTrace? trace = null)
    {
        this.trace = trace;
        this.dispatcher = dispatcher;
        this.enginePath = enginePath;
        this.surface = surface;
        shutdown = new AsyncShutdown(() => DisposeAsync().AsTask(), surface.Quit);
        displayWatcher = new DisplayWatcher(dispatcher, () => DisplayProvider.Current());
        displayWatcher.Changed += OnDisplaysChanged;
        surface.CardMeasured += OnCardMeasured;
        surface.CardMoved += OnCardMoved;
        surface.CommandInvoked += OnCommandInvoked;
        surface.LogWindowChanged += OnLogWindowChanged;
        surface.SettingsRequested += OnSettingsRequested;
        surface.IntentRequested += OnIntentRequested;
        surface.DisplayConfigurationChanged += displayWatcher.Refresh;
    }

    public Task StartLiveAsync()
    {
        hostLoop = RunHostLoopAsync();
        return Task.CompletedTask;
    }

    public Task RequestShutdownAsync()
    {
        return shutdown.Request();
    }

    public async Task StartReplayAsync(string path)
    {
        isReplay = true;
        protocol.Reset();
        beganSession = false;
        foreach (var line in File.ReadLines(path))
        {
            if (line.Length == 0)
            {
                continue;
            }
            using var document = JsonDocument.Parse(line);
            if (document.RootElement.TryGetProperty("protocolVersion", out _))
            {
                Apply(DeckEvent.Parse(line));
            }
            else
            {
                ApplyReplayStep(document.RootElement);
            }
        }
        await Task.CompletedTask;
    }

    public async ValueTask DisposeAsync()
    {
        var current = CurrentEngine();
        if (current is not null)
        {
            try
            {
                await current.SendAsync(ProtocolWriter.SessionStop(NextId()))
                    .WaitAsync(TimeSpan.FromSeconds(3));
            }
            catch (TimeoutException)
            {
                Console.Error.WriteLine("Engine shutdown request timed out.");
            }
        }
        cancellation.Cancel();
        if (hostLoop is not null)
        {
            try
            {
                await hostLoop;
            }
            catch (OperationCanceledException)
            {
            }
        }
        displayWatcher.Dispose();
        surface.Dispose();
        cancellation.Dispose();
    }

    private async Task RunHostLoopAsync()
    {
        var hadSession = false;
        while (!cancellation.IsCancellationRequested)
        {
            await using var client = new EngineClient(enginePath, trace);
            client.EventReceived += message => dispatcher.BeginInvoke(() => Apply(message));
            lock (engineLock)
            {
                engine = client;
            }

            protocol.Reset();
            beganSession = false;
            try
            {
                client.Start();
                await client.SendAsync(
                    ProtocolWriter.SessionStart(
                        NextId(),
                        CultureInfo.CurrentUICulture.Name,
                        DisplayProvider.Current()));
                hadSession = true;
                await client.Completion.WaitAsync(cancellation.Token);
            }
            catch (Exception exception) when (
                exception is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                Console.Error.WriteLine("Engine host could not start.");
                return;
            }
            finally
            {
                lock (engineLock)
                {
                    if (ReferenceEquals(engine, client))
                    {
                        engine = null;
                    }
                }
            }

            if (!cancellation.IsCancellationRequested && hadSession)
            {
                await dispatcher.InvokeAsync(surface.ShowStopped);
            }
        }
    }

    private void Apply(DeckEvent message)
    {
        if (cancellation.IsCancellationRequested)
        {
            return;
        }
        if (!protocol.Accept(message))
        {
            return;
        }

        switch (message.Event)
        {
            case "deck.changed" when message.Deck is { } deck:
                if (!beganSession)
                {
                    surface.BeginSession();
                    beganSession = true;
                }
                surface.ApplyDeck(deck);
                break;
            case "panels.changed" when message.Panels is { } panels:
                if (isReplay)
                {
                    RememberReplayFrames(panels);
                }
                surface.ApplyPanels(panels);
                if (isReplay)
                {
                    // A later frame in the transcript must not undo a height already measured.
                    foreach (var (card, height) in replayHeights.ToList())
                    {
                        ApplyReplayMeasurement(new CardMeasurement(card, [352, height]));
                    }
                }
                break;
            case "card.changed" when
                message.Card is { } card &&
                message.Model is { } model &&
                message.Menu is { } cardMenu &&
                message.Stopped is { } stopped &&
                CardRenderer.CanRender(model):
                surface.UpdateCard(card, model, cardMenu, stopped);
                break;
            case "status.changed" when message.Status is { } status:
                surface.UpdateStatus(status);
                break;
            case "menu.changed" when message.Menu is { } menu:
                surface.UpdateMenu(menu);
                break;
            case "notify" when message.Notifications is { } notifications:
                surface.ShowNotifications(notifications);
                break;
            case "log.changed" when message.Card is { } logCard && message.Log is { } log:
                surface.UpdateLog(logCard, log);
                break;
            case "effect" when message.Effect is { } effect:
                ApplyEffect(effect);
                break;
            case "settings.answered" when message.Answer is { } answer:
                surface.UpdateSettings(message.Id, answer);
                if (SummonPreferences.TryParse(answer, out var preferences))
                {
                    surface.ApplySummonPreferences(preferences);
                }
                break;
            case "update.changed" when message.Update is { } update:
                surface.UpdateSettingsUpdate(update);
                break;
        }
    }

    private void ApplyReplayStep(JsonElement step)
    {
        var name = DeckEvent.RequiredString(step, "step");
        if (!DeckEvent.TryProperty(step, "value", out var value))
        {
            throw new JsonException();
        }
        switch (name)
        {
            case "status":
                surface.UpdateStatus(value);
                break;
            case "menu":
                surface.UpdateMenu(value);
                break;
            case "firstPass":
            case "secondPass":
            case "summary":
                surface.ShowNotifications(ReplayNotificationAdapter.Parse(value));
                break;
        }
    }

    private void ApplyEffect(JsonElement effect)
    {
        switch (JsonModel.String(effect, "kind"))
        {
            case "openMenu":
                surface.OpenMenu();
                break;
            case "quit" when isReplay:
                // A replay exists to be looked at, so it stays up until it is closed by hand.
                Console.Error.WriteLine("Replay ignored the quit effect.");
                break;
            case "quit":
                _ = shutdown.Request();
                break;
            case "openSettings":
                surface.OpenSettings(effect);
                break;
            case "openLogs" when JsonModel.String(effect, "card") is { } openCard:
                surface.OpenLogs(openCard);
                break;
            case "closeLogs" when JsonModel.String(effect, "card") is { } closeCard:
                surface.CloseLogs(closeCard);
                break;
            case "present":
                surface.PresentDeck();
                break;
            default:
                PlatformEffects.Apply(effect);
                break;
        }
    }

    private void OnDisplaysChanged(IReadOnlyList<DisplayModel> displays)
    {
        _ = SendAsync(ProtocolWriter.DisplaysChanged(NextId(), displays));
    }

    private void OnCardMeasured(CardMeasurement measurement)
    {
        if (isReplay)
        {
            ApplyReplayMeasurement(measurement);
            return;
        }
        _ = SendAsync(ProtocolWriter.CardMeasured(NextId(), measurement));
    }

    private void RememberReplayFrames(IReadOnlyList<PanelChange> panels)
    {
        foreach (var panel in panels)
        {
            if (panel.Change == "close")
            {
                replayFrames.Remove(panel.Card);
            }
            else if (panel.Frame.Length == 4)
            {
                replayFrames[panel.Card] = panel.Frame;
            }
        }
    }

    // A replay has no engine to answer a measurement, so it sizes its own panels: a card takes its
    // measured height and the cards below it in the same column move by the difference.
    private void ApplyReplayMeasurement(CardMeasurement measurement)
    {
        if (measurement.Size.Length == 2)
        {
            replayHeights[measurement.Card] = measurement.Size[1];
        }
        if (measurement.Size.Length != 2 ||
            !replayFrames.TryGetValue(measurement.Card, out var frame) ||
            Math.Abs(frame[3] - measurement.Size[1]) < 0.5)
        {
            return;
        }
        var delta = measurement.Size[1] - frame[3];
        var changes = new List<PanelChange>();
        foreach (var (card, other) in replayFrames.ToList())
        {
            double[]? moved = null;
            if (card == measurement.Card)
            {
                moved = [other[0], other[1], other[2], measurement.Size[1]];
            }
            else if (Math.Abs(other[0] - frame[0]) < 0.5 && other[1] > frame[1])
            {
                moved = [other[0], other[1] + delta, other[2], other[3]];
            }
            if (moved is not null)
            {
                replayFrames[card] = moved;
                changes.Add(new PanelChange(card, "place", moved));
            }
        }
        surface.ApplyPanels(changes);
    }

    private void OnCardMoved(CardMove move)
    {
        _ = SendAsync(ProtocolWriter.CardMoved(NextId(), move));
    }

    private void OnCommandInvoked(DeckCommand command)
    {
        _ = SendAsync(ProtocolWriter.Command(NextId(), command));
    }

    private void OnLogWindowChanged(LogWindowChange change)
    {
        _ = SendAsync(ProtocolWriter.LogWindowChanged(NextId(), change));
    }

    private void OnSettingsRequested(SettingsWireRequest request)
    {
        _ = SendAsync(ProtocolWriter.Settings(request.Id, request.Json));
    }

    private void OnIntentRequested(string intent)
    {
        _ = SendAsync(ProtocolWriter.Intent(NextId(), intent));
    }

    private Task SendAsync(string line)
    {
        return CurrentEngine()?.SendAsync(line) ?? Task.CompletedTask;
    }

    private EngineClient? CurrentEngine()
    {
        lock (engineLock)
        {
            return engine;
        }
    }

    private string NextId()
    {
        return Interlocked.Increment(ref nextId).ToString(CultureInfo.InvariantCulture);
    }
}
