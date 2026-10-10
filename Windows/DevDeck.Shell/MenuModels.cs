using System.Text.Json;
using System.Text.Json.Nodes;

namespace DevDeck.Shell;

public enum DeckMenuEntryKind
{
    Item,
    Header,
    Separator,
    Submenu,
}

public sealed record DeckMenuEntryModel(
    DeckMenuEntryKind Kind,
    DeckMenuItemModel? Item,
    string? Header,
    IReadOnlyList<DeckMenuEntryModel> Children)
{
    public static IReadOnlyList<DeckMenuEntryModel> ParseList(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Array)
        {
            throw new JsonException();
        }

        return value.EnumerateArray().Select(Parse).ToArray();
    }

    private static DeckMenuEntryModel Parse(JsonElement value)
    {
        if (JsonModel.Object(value, "item", out var item))
        {
            return new(DeckMenuEntryKind.Item, DeckMenuItemModel.Parse(Wrapper(item, "_0")), null, []);
        }
        if (JsonModel.Object(value, "header", out var header))
        {
            return new(DeckMenuEntryKind.Header, null, DeckEvent.RequiredString(header, "_0"), []);
        }
        if (JsonModel.Object(value, "separator", out _))
        {
            return new(DeckMenuEntryKind.Separator, null, null, []);
        }
        if (JsonModel.Object(value, "submenu", out var submenu))
        {
            return new(
                DeckMenuEntryKind.Submenu,
                DeckMenuItemModel.Parse(Wrapper(submenu, "_0")),
                null,
                ParseList(Wrapper(submenu, "_1")));
        }
        throw new JsonException();
    }

    private static JsonElement Wrapper(JsonElement value, string name)
    {
        if (!DeckEvent.TryProperty(value, name, out var result))
        {
            throw new JsonException();
        }
        return result;
    }
}

public sealed record DeckMenuItemModel(
    string Title,
    string? Subtitle,
    string? Badge,
    string? Help,
    bool IsEnabled,
    bool IsOn,
    bool IsIndented,
    string KeyEquivalent,
    DeckCommand? Command,
    DeckMenuImageModel? Image,
    DeckMenuAlternateModel? Alternate,
    DeckMenuDialogModel? Confirmation,
    DeckMenuPromptModel? Prompt)
{
    public static DeckMenuItemModel Parse(JsonElement value)
    {
        return new(
            DeckEvent.RequiredString(value, "title"),
            JsonModel.String(value, "subtitle"),
            JsonModel.String(value, "badge"),
            JsonModel.String(value, "help"),
            JsonModel.Bool(value, "isEnabled"),
            JsonModel.Bool(value, "isOn"),
            JsonModel.Bool(value, "isIndented"),
            JsonModel.String(value, "keyEquivalent") ?? "",
            JsonModel.Command(value),
            JsonModel.Object(value, "image", out var image) ? DeckMenuImageModel.Parse(image) : null,
            JsonModel.Object(value, "alternate", out var alternate) ? DeckMenuAlternateModel.Parse(alternate) : null,
            JsonModel.Object(value, "confirmation", out var confirmation) ? DeckMenuDialogModel.Parse(confirmation) : null,
            JsonModel.Object(value, "prompt", out var prompt) ? DeckMenuPromptModel.Parse(prompt) : null);
    }
}

public sealed record DeckMenuImageModel(string Kind, string? Mark)
{
    public static DeckMenuImageModel Parse(JsonElement value)
    {
        var property = value.EnumerateObject().Single();
        if (property.Name != "attention")
        {
            return new(property.Name, null);
        }
        if (!DeckEvent.TryProperty(property.Value, "_0", out var wrapper))
        {
            throw new JsonException();
        }
        return new(property.Name, wrapper.EnumerateObject().Single().Name);
    }
}

public sealed record DeckMenuAlternateModel(string Title, bool IsEnabled, DeckCommand Command)
{
    public static DeckMenuAlternateModel Parse(JsonElement value)
    {
        return new(
            DeckEvent.RequiredString(value, "title"),
            JsonModel.Bool(value, "isEnabled"),
            JsonModel.Command(value) ?? throw new JsonException());
    }
}

public record DeckMenuDialogModel(string Title, string Detail, string Confirm, string Cancel)
{
    public static DeckMenuDialogModel Parse(JsonElement value)
    {
        return new(
            DeckEvent.RequiredString(value, "title"),
            DeckEvent.RequiredString(value, "detail"),
            DeckEvent.RequiredString(value, "confirm"),
            DeckEvent.RequiredString(value, "cancel"));
    }
}

public sealed record DeckMenuPromptModel(
    string Title,
    string Detail,
    string Confirm,
    string Cancel,
    string Placeholder) : DeckMenuDialogModel(Title, Detail, Confirm, Cancel)
{
    public static new DeckMenuPromptModel Parse(JsonElement value)
    {
        return new(
            DeckEvent.RequiredString(value, "title"),
            DeckEvent.RequiredString(value, "detail"),
            DeckEvent.RequiredString(value, "confirm"),
            DeckEvent.RequiredString(value, "cancel"),
            DeckEvent.RequiredString(value, "placeholder"));
    }
}

public static class DeckCommandPrompt
{
    public static DeckCommand WithName(DeckCommand command, string name)
    {
        var root = JsonNode.Parse(command.Json)?.AsObject() ?? throw new JsonException();
        var operation = root.Single().Value?.AsObject() ?? throw new JsonException();
        operation["name"] = name;
        return new DeckCommand(root.ToJsonString());
    }
}
