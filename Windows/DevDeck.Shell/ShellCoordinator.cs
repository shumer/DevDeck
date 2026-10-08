using System.Diagnostics;
using System.Text.Json;
using System.Windows.Threading;

namespace DevDeck.Shell;

public sealed class ProtocolState
{
    public int Revision { get; private set; }
    public IReadOnlyList<CardModel> FailureCards { get; private set; } = [];

    public bool Accept(EngineEvent message)
    {
        if (message.ProtocolVersion != 2 || message.Revision <= Revision)
        {
            return false;
        }
        Revision = message.Revision;
        if (message.Shell is { } shell)
        {
            FailureCards = shell.FailureCards;
        }
        return true;
    }
}

public sealed class ShellCoordinator : IAsyncDisposable
{
    private readonly Dispatcher dispatcher;
    private readonly EngineClient engine;
    private readonly IShellSurface surface;
    private readonly ProtocolState protocol = new();

    public ShellCoordinator(Dispatcher dispatcher, EngineClient engine, IShellSurface surface)
    {
        this.dispatcher = dispatcher;
        this.engine = engine;
        this.surface = surface;
        engine.EventReceived += OnEngineEvent;
        engine.Exited += OnEngineExited;
        surface.CardMeasured += OnCardMeasured;
        surface.CardInteracted += OnCardInteracted;
    }

    public async Task StartAsync()
    {
        engine.Start();
        await engine.SendAsync("session.start", new { Displays = DisplayProvider.Current() });
        await engine.SendAsync("shell.bootstrap");
    }

    private void OnEngineEvent(EngineEvent message)
    {
        dispatcher.BeginInvoke(async () => await ApplyAsync(message));
    }

    private async Task ApplyAsync(EngineEvent message)
    {
        if (!protocol.Accept(message))
        {
            return;
        }
        switch (message.Event)
        {
            case "shell.ready" when message.Shell is { } presentation:
                surface.Configure(presentation);
                foreach (var account in presentation.CredentialAccounts)
                {
                    if (CredentialManager.Read(account) is { Length: > 0 } secret)
                    {
                        await engine.SendAsync("credentials.set", new { Account = account, Token = secret });
                    }
                }
                break;
            case "card.updated" when message.Card is { } card:
                surface.UpdateCard(card);
                break;
            case "layout.updated" when message.Cards is { } cards:
                surface.ApplyLayout(cards);
                break;
            case "effect" when message.Effect is { Kind: "openURL" } effect:
                Process.Start(new ProcessStartInfo(effect.Url) { UseShellExecute = true });
                break;
        }
    }

    private void OnEngineExited()
    {
        dispatcher.BeginInvoke(() => surface.ShowTransportFailure(protocol.FailureCards));
    }

    private void OnCardMeasured(CardMeasurement measurement)
    {
        _ = engine.SendAsync(
            "card.measured",
            new { measurement.Card, Size = new[] { measurement.Width, measurement.Height } });
    }

    private void OnCardInteracted(CardInteraction interaction)
    {
        if (interaction.IsExpanded is { } expanded)
        {
            _ = engine.SendAsync(
                "card.setExpanded", new { interaction.Card, IsExpanded = expanded });
        }
        else
        {
            _ = engine.SendAsync(
                "card.invoke", new { interaction.Card, interaction.Action });
        }
    }

    public async ValueTask DisposeAsync()
    {
        surface.Dispose();
        await engine.DisposeAsync();
    }
}
