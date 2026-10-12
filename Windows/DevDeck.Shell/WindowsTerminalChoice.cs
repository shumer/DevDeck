using System.Text.Json;

namespace DevDeck.Shell;

public sealed record WindowsTerminalChoice(string? Application, string? Profile)
{
    public static WindowsTerminalChoice? Parse(JsonElement effect)
    {
        if (!DeckEvent.TryProperty(effect, "terminal", out var terminal) || terminal.ValueKind != JsonValueKind.Object)
        {
            return null;
        }
        return new WindowsTerminalChoice(JsonModel.String(terminal, "application"), JsonModel.String(terminal, "profile"));
    }
}
