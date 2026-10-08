using Forms = System.Windows.Forms;

namespace DevDeck.Shell;

public interface IShellSurface : IDisposable
{
    event Action<CardMeasurement>? CardMeasured;
    event Action<CardInteraction>? CardInteracted;
    event Action? QuitRequested;
    void Configure(ShellPresentation presentation);
    void UpdateCard(CardModel card);
    void ApplyLayout(IReadOnlyList<CardPlacement> placements);
    void ShowTransportFailure(IReadOnlyList<CardModel> cards);
}

public sealed class ShellSurface : IShellSurface
{
    private readonly Dictionary<string, CardWindow> windows = [];
    private Forms.NotifyIcon? trayIcon;

    public event Action<CardMeasurement>? CardMeasured;
    public event Action<CardInteraction>? CardInteracted;
    public event Action? QuitRequested;

    public void Configure(ShellPresentation presentation)
    {
        trayIcon?.Dispose();
        var menu = new Forms.ContextMenuStrip();
        var quit = menu.Items.Add(presentation.QuitLabel);
        quit.Click += (_, _) => QuitRequested?.Invoke();
        trayIcon = new Forms.NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Text = presentation.ToolTip,
            ContextMenuStrip = menu,
            Visible = true,
        };
    }

    public void UpdateCard(CardModel card)
    {
        if (!windows.TryGetValue(card.Id, out var window))
        {
            window = new CardWindow(
                card,
                measurement => CardMeasured?.Invoke(measurement),
                interaction => CardInteracted?.Invoke(interaction));
            windows.Add(card.Id, window);
            window.Show();
        }
        else
        {
            window.Update(card);
        }
    }

    public void ApplyLayout(IReadOnlyList<CardPlacement> placements)
    {
        foreach (var placement in placements)
        {
            if (placement.TopLeft.Count == 2 && windows.TryGetValue(placement.Card, out var window))
            {
                window.ApplyPosition(placement.TopLeft[0], placement.TopLeft[1]);
            }
        }
    }

    public void ShowTransportFailure(IReadOnlyList<CardModel> cards)
    {
        foreach (var card in cards)
        {
            UpdateCard(card);
        }
    }

    public void Dispose()
    {
        trayIcon?.Dispose();
        foreach (var window in windows.Values)
        {
            window.Close();
        }
        windows.Clear();
    }
}
