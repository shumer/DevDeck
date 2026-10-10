namespace DevDeck.Shell;

public interface ILogWindow
{
    event EventHandler? Closed;
    void Show();
    void Activate();
    void Close();
    void SetTitle(string title);
    void Update(DeckLog log);
}

public sealed class LogWindowRegistry
{
    private readonly Func<string, ILogWindow> factory;
    private readonly Dictionary<string, ILogWindow> windows = [];
    private readonly Dictionary<string, string> titles = [];
    private readonly Dictionary<string, DeckLog> models = [];
    private readonly HashSet<string> silentCloses = [];

    public LogWindowRegistry(Func<string, ILogWindow> factory)
    {
        this.factory = factory;
    }

    public event Action<LogWindowChange>? WindowChanged;

    public int Count => windows.Count;

    public void UpdateTitle(string card, string title)
    {
        titles[card] = title;
        if (windows.TryGetValue(card, out var window))
        {
            window.SetTitle(title);
        }
    }

    public void UpdateLog(string card, DeckLog log)
    {
        models[card] = log;
        if (windows.TryGetValue(card, out var window))
        {
            window.Update(log);
        }
    }

    public void Open(string card)
    {
        if (windows.TryGetValue(card, out var existing))
        {
            existing.Activate();
            return;
        }

        var window = factory(card);
        windows.Add(card, window);
        window.Closed += (_, _) => OnClosed(card, window);
        if (titles.TryGetValue(card, out var title))
        {
            window.SetTitle(title);
        }
        if (models.TryGetValue(card, out var model))
        {
            window.Update(model);
        }
        window.Show();
        WindowChanged?.Invoke(new LogWindowChange(card, true));
    }

    public void Close(string card)
    {
        if (windows.TryGetValue(card, out var window))
        {
            window.Close();
        }
    }

    public void CloseAll(bool notify)
    {
        foreach (var item in windows.ToArray())
        {
            if (!notify)
            {
                silentCloses.Add(item.Key);
            }
            item.Value.Close();
        }
    }

    private void OnClosed(string card, ILogWindow window)
    {
        if (!windows.TryGetValue(card, out var current) || !ReferenceEquals(current, window))
        {
            return;
        }
        windows.Remove(card);
        if (!silentCloses.Remove(card))
        {
            WindowChanged?.Invoke(new LogWindowChange(card, false));
        }
    }
}
