using System.Text.Json.Serialization;

namespace DevDeck.Shell;

public sealed class EngineEvent
{
    [JsonPropertyName("protocolVersion")]
    public int ProtocolVersion { get; init; }

    [JsonPropertyName("revision")]
    public int Revision { get; init; }

    [JsonPropertyName("event")]
    public string Event { get; init; } = "";

    [JsonPropertyName("card")]
    public CardModel? Card { get; init; }

    [JsonPropertyName("cards")]
    public List<CardPlacement>? Cards { get; init; }

    [JsonPropertyName("effect")]
    public OpenUrlEffect? Effect { get; init; }

    [JsonPropertyName("shell")]
    public ShellPresentation? Shell { get; init; }
}

public sealed class CardModel
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("kind")]
    public string Kind { get; init; } = "";

    [JsonPropertyName("mark")]
    public string Mark { get; init; } = "";

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";

    [JsonPropertyName("timeText")]
    public string TimeText { get; init; } = "";

    [JsonPropertyName("hero")]
    public CardHero Hero { get; init; } = new();

    [JsonPropertyName("rows")]
    public List<CardRow> Rows { get; init; } = [];

    [JsonPropertyName("footer")]
    public CardFooter? Footer { get; init; }

    [JsonPropertyName("expander")]
    public CardExpander? Expander { get; init; }

    [JsonPropertyName("meta")]
    public List<CardMeta> Meta { get; init; } = [];

    [JsonPropertyName("chips")]
    public List<CardChip> Chips { get; init; } = [];

    [JsonPropertyName("actions")]
    public List<CardAction> Actions { get; init; } = [];

    [JsonPropertyName("branch")]
    public CardBranch? Branch { get; init; }
}

public sealed class CardHero
{
    [JsonPropertyName("number")]
    public string? Number { get; init; }

    [JsonPropertyName("unit")]
    public string? Unit { get; init; }

    [JsonPropertyName("badge")]
    public CardBadge? Badge { get; init; }

    [JsonPropertyName("tone")]
    public string? Tone { get; init; }

    [JsonPropertyName("state")]
    public string? State { get; init; }

    [JsonPropertyName("note")]
    public string? Note { get; init; }
}

public sealed class CardBadge
{
    [JsonPropertyName("text")]
    public string Text { get; init; } = "";

    [JsonPropertyName("tone")]
    public string Tone { get; init; } = "";
}

public sealed class CardRow
{
    [JsonPropertyName("tone")]
    public string Tone { get; init; } = "";

    [JsonPropertyName("chips")]
    public List<CardBadge> Chips { get; init; } = [];

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";

    [JsonPropertyName("trailing")]
    public string Trailing { get; init; } = "";

    [JsonPropertyName("action")]
    public string Action { get; init; } = "";

    [JsonPropertyName("glyph")]
    public string? Glyph { get; init; }
}

public sealed class CardFooter
{
    [JsonPropertyName("text")]
    public string Text { get; init; } = "";
}

public sealed class CardExpander
{
    [JsonPropertyName("hiddenCount")]
    public int HiddenCount { get; init; }

    [JsonPropertyName("isExpanded")]
    public bool IsExpanded { get; init; }

    [JsonPropertyName("label")]
    public string Label { get; init; } = "";
}

public sealed class CardMeta
{
    [JsonPropertyName("leading")]
    public string Leading { get; init; } = "";
}

public sealed class CardChip
{
    [JsonPropertyName("label")]
    public string Label { get; init; } = "";

    [JsonPropertyName("tone")]
    public string Tone { get; init; } = "";

    [JsonPropertyName("isEnabled")]
    public bool IsEnabled { get; init; }

    [JsonPropertyName("action")]
    public string Action { get; init; } = "";
}

public sealed class CardAction
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("label")]
    public string Label { get; init; } = "";

    [JsonPropertyName("glyph")]
    public string Glyph { get; init; } = "";

    [JsonPropertyName("role")]
    public string Role { get; init; } = "";

    [JsonPropertyName("isEnabled")]
    public bool IsEnabled { get; init; }

    [JsonPropertyName("isBusy")]
    public bool IsBusy { get; init; }
}

public sealed class CardBranch
{
    [JsonPropertyName("name")]
    public string Name { get; init; } = "";
}

public sealed class CardPlacement
{
    [JsonPropertyName("card")]
    public string Card { get; init; } = "";

    [JsonPropertyName("display")]
    public string Display { get; init; } = "";

    [JsonPropertyName("topLeft")]
    public List<double> TopLeft { get; init; } = [];
}

public sealed class OpenUrlEffect
{
    [JsonPropertyName("kind")]
    public string Kind { get; init; } = "";

    [JsonPropertyName("url")]
    public string Url { get; init; } = "";
}

public sealed class ShellPresentation
{
    [JsonPropertyName("toolTip")]
    public string ToolTip { get; init; } = "";

    [JsonPropertyName("quitLabel")]
    public string QuitLabel { get; init; } = "";

    [JsonPropertyName("credentialAccounts")]
    public List<string> CredentialAccounts { get; init; } = [];

    [JsonPropertyName("failureCards")]
    public List<CardModel> FailureCards { get; init; } = [];
}

public sealed record DisplayModel(string Id, double[] VisibleFrame, double Scale);

public sealed record CardMeasurement(string Card, double Width, double Height);

public sealed record CardInteraction(string Card, string Action, bool? IsExpanded = null);
