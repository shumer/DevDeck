using System.Text;
using System.Text.Json;

namespace DevDeck.Shell;

public sealed class DeckEvent
{
    private DeckEvent()
    {
    }

    public int ProtocolVersion { get; private init; }
    public int Revision { get; private init; }
    public string Event { get; private init; } = "";
    public string? Id { get; private init; }
    public DeckPresentation? Deck { get; private init; }
    public IReadOnlyList<PanelChange>? Panels { get; private init; }
    public string? Card { get; private init; }
    public JsonElement? Model { get; private init; }
    public JsonElement? Menu { get; private init; }
    public JsonElement? Stopped { get; private init; }
    public JsonElement? Status { get; private init; }
    public JsonElement? Effect { get; private init; }
    public JsonElement? Answer { get; private init; }
    public IReadOnlyList<DeckNotification>? Notifications { get; private init; }
    public string RawLine { get; private init; } = "";

    public static DeckEvent Parse(string line)
    {
        using var document = JsonDocument.Parse(line);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
        {
            throw new JsonException();
        }

        return new DeckEvent
        {
            ProtocolVersion = RequiredInt(root, "protocolVersion"),
            Revision = RequiredInt(root, "revision"),
            Event = RequiredString(root, "event"),
            Id = OptionalString(root, "id"),
            Deck = TryProperty(root, "deck", out var deck) ? DeckPresentation.Parse(deck) : null,
            Panels = TryProperty(root, "panels", out var panels) ? ParsePanels(panels) : null,
            Card = OptionalString(root, "card"),
            Model = Clone(root, "model"),
            Menu = Clone(root, "menu"),
            Stopped = Clone(root, "stopped"),
            Status = Clone(root, "status"),
            Effect = Clone(root, "effect"),
            Answer = Clone(root, "answer"),
            Notifications = TryProperty(root, "notifications", out var notifications)
                ? ParseNotifications(notifications)
                : null,
            RawLine = line,
        };
    }

    private static IReadOnlyList<PanelChange> ParsePanels(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Array)
        {
            throw new JsonException();
        }

        return value.EnumerateArray().Select(PanelChange.Parse).ToArray();
    }

    private static IReadOnlyList<DeckNotification> ParseNotifications(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Array)
        {
            throw new JsonException();
        }

        return value.EnumerateArray().Select(DeckNotification.Parse).ToArray();
    }

    private static JsonElement? Clone(JsonElement root, string name)
    {
        return TryProperty(root, name, out var value) ? value.Clone() : null;
    }

    internal static bool TryProperty(JsonElement root, string name, out JsonElement value)
    {
        value = default;
        return root.ValueKind == JsonValueKind.Object && root.TryGetProperty(name, out value);
    }

    internal static string RequiredString(JsonElement root, string name)
    {
        if (!TryProperty(root, name, out var value) || value.ValueKind != JsonValueKind.String)
        {
            throw new JsonException();
        }

        return value.GetString() ?? "";
    }

    internal static string? OptionalString(JsonElement root, string name)
    {
        if (!TryProperty(root, name, out var value) || value.ValueKind == JsonValueKind.Null)
        {
            return null;
        }

        return value.ValueKind == JsonValueKind.String ? value.GetString() : throw new JsonException();
    }

    internal static int RequiredInt(JsonElement root, string name)
    {
        if (!TryProperty(root, name, out var value) || !value.TryGetInt32(out var number))
        {
            throw new JsonException();
        }

        return number;
    }

    internal static bool RequiredBool(JsonElement root, string name)
    {
        if (!TryProperty(root, name, out var value) ||
            value.ValueKind is not JsonValueKind.True and not JsonValueKind.False)
        {
            throw new JsonException();
        }

        return value.GetBoolean();
    }
}

public sealed record DeckNotification(
    string Id,
    string Source,
    string Title,
    string Subtitle,
    string Body,
    bool IsQuiet,
    DeckCommand Command)
{
    public static DeckNotification Parse(JsonElement value)
    {
        if (!DeckEvent.TryProperty(value, "command", out var command))
        {
            throw new JsonException();
        }

        return new DeckNotification(
            DeckEvent.RequiredString(value, "id"),
            DeckEvent.RequiredString(value, "source"),
            DeckEvent.RequiredString(value, "title"),
            DeckEvent.RequiredString(value, "subtitle"),
            DeckEvent.RequiredString(value, "body"),
            DeckEvent.RequiredBool(value, "isQuiet"),
            DeckCommand.From(command));
    }
}

public sealed record DeckPresentation(bool IsLocked, string DisplayMode, JsonElement StoppedStatus)
{
    public static DeckPresentation Parse(JsonElement value)
    {
        if (!DeckEvent.TryProperty(value, "isLocked", out var isLocked) ||
            isLocked.ValueKind is not JsonValueKind.True and not JsonValueKind.False)
        {
            throw new JsonException();
        }

        if (!DeckEvent.TryProperty(value, "stoppedStatus", out var stoppedStatus))
        {
            throw new JsonException();
        }

        return new DeckPresentation(
            isLocked.GetBoolean(),
            DeckEvent.RequiredString(value, "displayMode"),
            stoppedStatus.Clone());
    }
}

public sealed record PanelChange(string Card, string Change, double[] Frame)
{
    public static PanelChange Parse(JsonElement value)
    {
        var change = DeckEvent.RequiredString(value, "change");
        if (!DeckEvent.TryProperty(value, "frame", out var frame))
        {
            if (change == "close")
            {
                return new PanelChange(DeckEvent.RequiredString(value, "card"), change, []);
            }
            throw new JsonException();
        }
        if (frame.ValueKind != JsonValueKind.Array)
        {
            throw new JsonException();
        }

        return new PanelChange(
            DeckEvent.RequiredString(value, "card"),
            change,
            frame.EnumerateArray().Select(number => number.GetDouble()).ToArray());
    }
}

public sealed record DisplayModel(string Id, double[] Frame, bool IsPrimary);

public sealed record CardMeasurement(string Card, double[] Size);

public sealed record CardMove(string Card, double[] Frame);

public readonly record struct DeckCommand(string Json)
{
    public static DeckCommand From(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object)
        {
            throw new JsonException();
        }

        return new DeckCommand(value.GetRawText());
    }
}

public static class ProtocolWriter
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public static string SessionStart(string id, string language, IReadOnlyList<DisplayModel> displays)
    {
        return Write(id, "session.start", writer =>
        {
            writer.WriteString("systemLanguage", language);
            writer.WritePropertyName("displays");
            JsonSerializer.Serialize(writer, displays, JsonOptions);
        });
    }

    public static string DisplaysChanged(string id, IReadOnlyList<DisplayModel> displays)
    {
        return Write(id, "displays.changed", writer =>
        {
            writer.WritePropertyName("displays");
            JsonSerializer.Serialize(writer, displays, JsonOptions);
        });
    }

    public static string CardMeasured(string id, CardMeasurement measurement)
    {
        return Write(id, "card.measured", writer =>
        {
            writer.WriteString("card", measurement.Card);
            writer.WritePropertyName("size");
            JsonSerializer.Serialize(writer, measurement.Size, JsonOptions);
        });
    }

    public static string CardMoved(string id, CardMove move)
    {
        return Write(id, "card.moved", writer =>
        {
            writer.WriteString("card", move.Card);
            writer.WritePropertyName("frame");
            JsonSerializer.Serialize(writer, move.Frame, JsonOptions);
        });
    }

    public static string Command(string id, DeckCommand command)
    {
        return Write(id, "command", writer =>
        {
            writer.WritePropertyName("command");
            writer.WriteRawValue(command.Json);
        });
    }

    public static string Settings(string id, string request)
    {
        return Write(id, "settings", writer =>
        {
            writer.WritePropertyName("request");
            writer.WriteRawValue(request);
        });
    }

    public static string SessionStop(string id)
    {
        return Write(id, "session.stop", null);
    }

    private static string Write(string id, string intent, Action<Utf8JsonWriter>? fields)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            writer.WriteNumber("protocolVersion", 2);
            writer.WriteString("id", id);
            writer.WriteString("intent", intent);
            fields?.Invoke(writer);
            writer.WriteEndObject();
        }

        return Encoding.UTF8.GetString(stream.ToArray());
    }
}

public static class JsonModel
{
    public static bool Object(JsonElement parent, string name, out JsonElement value)
    {
        return DeckEvent.TryProperty(parent, name, out value) && value.ValueKind == JsonValueKind.Object;
    }

    public static bool Array(JsonElement parent, string name, out JsonElement value)
    {
        return DeckEvent.TryProperty(parent, name, out value) && value.ValueKind == JsonValueKind.Array;
    }

    public static string? String(JsonElement parent, string name)
    {
        return DeckEvent.TryProperty(parent, name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
    }

    public static bool Bool(JsonElement parent, string name)
    {
        return DeckEvent.TryProperty(parent, name, out var value) && value.ValueKind == JsonValueKind.True;
    }

    public static string NumberText(JsonElement parent, string name)
    {
        if (!DeckEvent.TryProperty(parent, name, out var value) || value.ValueKind != JsonValueKind.Number)
        {
            return "";
        }

        return value.GetRawText();
    }

    public static DeckCommand? Command(JsonElement parent, string name = "command")
    {
        return Object(parent, name, out var value) ? DeckCommand.From(value) : null;
    }
}
