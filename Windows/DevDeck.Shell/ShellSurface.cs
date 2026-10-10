using System.Text.Json;
using System.Windows;

namespace DevDeck.Shell;

public interface IShellSurface : IDisposable
{
    event Action<CardMeasurement>? CardMeasured;
    event Action<CardMove>? CardMoved;
    event Action<DeckCommand>? CommandInvoked;
    event Action<LogWindowChange>? LogWindowChanged;
    event Action? DisplayConfigurationChanged;
    void BeginSession();
    void ApplyDeck(DeckPresentation presentation);
    void ApplyPanels(IReadOnlyList<PanelChange> panels);
    void UpdateCard(string card, JsonElement model, JsonElement menu, JsonElement stopped);
    void UpdateStatus(JsonElement status);
    void UpdateMenu(JsonElement menu);
    void ShowNotifications(IReadOnlyList<DeckNotification> notifications);
    void UpdateLog(string card, DeckLog log);
    void OpenLogs(string card);
    void CloseLogs(string card);
    void ApplySummonPreferences(SummonPreferences preferences);
    void PresentDeck();
    void OpenMenu();
    void Quit();
    void ShowStopped();
}

public sealed class ShellSurface : IShellSurface
{
    private readonly Dictionary<string, CardWindow> windows = [];
    private readonly Dictionary<string, CardState> cards = [];
    private readonly TrayController tray;
    private readonly NotificationController notifications;
    private readonly LogWindowRegistry logs;
    private readonly SummonController summon;
    private readonly List<SummonVeilWindow> veils = [];
    private bool isLocked;
    private bool isSummoned;
    private string displayMode = "desktop";
    private JsonElement? stoppedStatus;

    public event Action<CardMeasurement>? CardMeasured;
    public event Action<CardMove>? CardMoved;
    public event Action<DeckCommand>? CommandInvoked;
    public event Action<LogWindowChange>? LogWindowChanged;
    public event Action? DisplayConfigurationChanged;

    public ShellSurface()
    {
        tray = new TrayController(command => CommandInvoked?.Invoke(command));
        notifications = new NotificationController(
            new WindowsToastPlatform(),
            NotificationArtwork.FileUri,
            command => CommandInvoked?.Invoke(command));
        logs = new LogWindowRegistry(card => new LogWindow(card));
        logs.WindowChanged += change => LogWindowChanged?.Invoke(change);
        summon = new SummonController(
            Application.Current.Dispatcher,
            ApplySummonPresentation);
    }

    public void BeginSession()
    {
        foreach (var window in windows.Values)
        {
            window.Close();
        }
        windows.Clear();
        cards.Clear();
        logs.CloseAll(false);
        stoppedStatus = null;
    }

    public void ApplyDeck(DeckPresentation presentation)
    {
        isLocked = presentation.IsLocked;
        displayMode = presentation.DisplayMode;
        stoppedStatus = presentation.StoppedStatus;
        foreach (var window in windows.Values)
        {
            window.SetLocked(isLocked);
            window.SetDisplayMode(isSummoned ? "floating" : displayMode);
        }
    }

    public void ApplyPanels(IReadOnlyList<PanelChange> panels)
    {
        foreach (var panel in panels)
        {
            switch (panel.Change)
            {
                case "open":
                    Open(panel.Card).ApplyFrame(panel.Frame);
                    break;
                case "place" when windows.TryGetValue(panel.Card, out var window):
                    window.ApplyFrame(panel.Frame);
                    break;
                case "close":
                    Close(panel.Card);
                    break;
            }
        }
    }

    public void UpdateCard(string card, JsonElement model, JsonElement menu, JsonElement stopped)
    {
        cards[card] = new CardState(model, menu, stopped);
        logs.UpdateTitle(card, CardTitle(model));
        if (windows.TryGetValue(card, out var window))
        {
            window.Update(model);
            window.UpdateMenu(menu);
        }
    }

    public void UpdateStatus(JsonElement status)
    {
        tray.UpdateStatus(status);
    }

    public void UpdateMenu(JsonElement menu)
    {
        tray.UpdateMenu(menu);
    }

    public void ShowNotifications(IReadOnlyList<DeckNotification> value)
    {
        notifications.Show(value);
    }

    public void UpdateLog(string card, DeckLog log)
    {
        logs.UpdateLog(card, log);
    }

    public void OpenLogs(string card)
    {
        logs.Open(card);
    }

    public void CloseLogs(string card)
    {
        logs.Close(card);
    }

    public void ApplySummonPreferences(SummonPreferences preferences)
    {
        summon.ApplyPreferences(preferences);
    }

    public void PresentDeck()
    {
        summon.Present();
    }

    public void OpenMenu()
    {
        tray.OpenMenu();
    }

    public void Quit()
    {
        Application.Current.Shutdown();
    }

    public void ShowStopped()
    {
        foreach (var item in windows)
        {
            if (cards.TryGetValue(item.Key, out var state))
            {
                item.Value.ShowStopped(state.Stopped, stoppedStatus);
            }
        }
    }

    public void Dispose()
    {
        summon.Dispose();
        CloseVeils();
        BeginSession();
        notifications.Dispose();
        tray.Dispose();
    }

    private CardWindow Open(string card)
    {
        if (windows.TryGetValue(card, out var existing))
        {
            return existing;
        }

        var window = new CardWindow(
            card,
            measurement => CardMeasured?.Invoke(measurement),
            move => CardMoved?.Invoke(move),
            command => CommandInvoked?.Invoke(command),
            () => DisplayConfigurationChanged?.Invoke());
        windows.Add(card, window);
        window.Show();
        window.SetLocked(isLocked);
        window.SetDisplayMode(isSummoned ? "floating" : displayMode);
        if (cards.TryGetValue(card, out var state))
        {
            window.Update(state.Model);
            window.UpdateMenu(state.Menu);
        }
        return window;
    }

    private void Close(string card)
    {
        if (windows.Remove(card, out var window))
        {
            window.Close();
        }
    }

    private void ApplySummonPresentation(SummonPresentation presentation)
    {
        isSummoned = presentation.IsRaised;
        CloseVeils();
        if (presentation.IsRaised && presentation.Dims)
        {
            foreach (var display in DisplayProvider.Current())
            {
                var veil = new SummonVeilWindow(display, summon.Dismiss);
                veils.Add(veil);
                veil.ShowVeil();
            }
        }

        foreach (var window in windows.Values)
        {
            window.SetDisplayMode(presentation.IsRaised ? "floating" : displayMode);
        }
    }

    private void CloseVeils()
    {
        foreach (var veil in veils)
        {
            veil.Close();
        }
        veils.Clear();
    }

    private sealed record CardState(JsonElement Model, JsonElement Menu, JsonElement Stopped);

    private static string CardTitle(JsonElement model)
    {
        var card = model.EnumerateObject().Single().Value;
        return JsonModel.String(card, "title") ?? "";
    }
}
