using System.Text.Json;
using System.Text.Json.Nodes;

namespace DevDeck.Shell;

public sealed record SettingsWireRequest(string Id, string Json);

public sealed class SettingsWords
{
    private readonly Dictionary<string, string> values = [];

    public int Count => values.Count;

    public void Replace(JsonElement answer)
    {
        values.Clear();
        if (!SettingsJson.Case(answer, "words", out var payload) ||
            !DeckEvent.TryProperty(payload, "_0", out var words) ||
            words.ValueKind != JsonValueKind.Object)
        {
            return;
        }

        foreach (var property in words.EnumerateObject())
        {
            values[property.Name] = property.Value.GetString() ?? "";
        }
    }

    public string Get(string key, string? value = null)
    {
        if (!values.TryGetValue(key, out var text))
        {
            return "";
        }

        return value is null ? text : text.Replace("%@", value, StringComparison.Ordinal);
    }
}

public static class SettingsJson
{
    public static string Empty(string name)
    {
        return new JsonObject { [name] = new JsonObject() }.ToJsonString();
    }

    public static string Named(string name, string field, string? value)
    {
        return new JsonObject
        {
            [name] = new JsonObject { [field] = value is null ? null : JsonValue.Create(value) },
        }.ToJsonString();
    }

    public static string Value(string name, JsonNode value)
    {
        return new JsonObject
        {
            [name] = new JsonObject { ["_0"] = value.DeepClone() },
        }.ToJsonString();
    }

    public static string Token(string name, JsonNode account, string typed)
    {
        return new JsonObject
        {
            [name] = new JsonObject
            {
                ["_0"] = account.DeepClone(),
                ["typed"] = typed,
            },
        }.ToJsonString();
    }

    public static string SetCard(string id, bool isEnabled)
    {
        return new JsonObject
        {
            ["setCard"] = new JsonObject
            {
                ["id"] = id,
                ["isEnabled"] = isEnabled,
            },
        }.ToJsonString();
    }

    public static bool Case(JsonElement answer, string name, out JsonElement payload)
    {
        return DeckEvent.TryProperty(answer, name, out payload) && payload.ValueKind == JsonValueKind.Object;
    }

    public static JsonNode? CaseValue(JsonElement answer, string name)
    {
        if (!Case(answer, name, out var payload) ||
            !DeckEvent.TryProperty(payload, "_0", out var value) ||
            value.ValueKind == JsonValueKind.Null)
        {
            return null;
        }

        return JsonNode.Parse(value.GetRawText());
    }

    public static JsonObject Object(JsonNode? node)
    {
        return node as JsonObject ?? new JsonObject();
    }

    public static string String(JsonObject value, string name)
    {
        return value[name]?.GetValue<string>() ?? "";
    }

    public static bool Bool(JsonObject value, string name)
    {
        return value[name]?.GetValue<bool>() ?? false;
    }

    public static void Set(JsonObject value, string name, string text)
    {
        value[name] = text;
    }

    public static void Set(JsonObject value, string name, bool selected)
    {
        value[name] = selected;
    }
}

public sealed class SettingsClient
{
    private readonly Dictionary<string, Action<JsonElement>> callbacks = [];
    private long nextId;

    public SettingsWords Words { get; } = new();
    public JsonNode? List { get; private set; }
    public JsonArray? Cards { get; private set; }
    public JsonObject? Preferences { get; private set; }
    public event Action<SettingsWireRequest>? RequestSent;
    public event Action<string>? IntentSent;
    public event Action<JsonElement>? AnswerReceived;
    public event Action<DeckCommand>? CommandSent;
    public event Action? Changed;

    public void BeginSession()
    {
        callbacks.Clear();
        Request(SettingsJson.Empty("words"));
        Request(SettingsJson.Empty("list"));
        Request(SettingsJson.Empty("cards"));
        Request(SettingsJson.Empty("preferences"));
    }

    public string Request(string request, Action<JsonElement>? callback = null)
    {
        var id = $"settings.{Interlocked.Increment(ref nextId)}";
        if (callback is not null)
        {
            callbacks[id] = callback;
        }
        RequestSent?.Invoke(new SettingsWireRequest(id, request));
        return id;
    }

    public void Receive(string? id, JsonElement answer)
    {
        var preferencesChanged = false;
        if (SettingsJson.Case(answer, "words", out _))
        {
            Words.Replace(answer);
        }
        else if (SettingsJson.CaseValue(answer, "list") is { } list)
        {
            List = list;
        }
        else if (SettingsJson.CaseValue(answer, "cards") is JsonArray cards)
        {
            Cards = cards;
        }
        else if (SettingsJson.CaseValue(answer, "preferences") is JsonObject preferences)
        {
            Preferences = preferences;
            preferencesChanged = true;
        }

        if (id is not null && callbacks.Remove(id, out var callback))
        {
            callback(answer);
        }
        AnswerReceived?.Invoke(answer);
        Changed?.Invoke();

        if (preferencesChanged)
        {
            Request(SettingsJson.Empty("words"));
        }
    }

    public void RefreshList()
    {
        Request(SettingsJson.Empty("list"));
    }

    public void SavePreferences(JsonObject preferences)
    {
        Preferences = (JsonObject)preferences.DeepClone();
        Request(SettingsJson.Value("setPreferences", preferences));
    }

    public void SendIntent(string intent)
    {
        IntentSent?.Invoke(intent);
    }

    public void SendCommand(DeckCommand command)
    {
        CommandSent?.Invoke(command);
    }
}

public sealed class TokenSubmission
{
    private string typed = "";

    public string Typed
    {
        get => typed;
        set => typed = value;
    }

    public string Take()
    {
        var value = typed;
        typed = "";
        return value;
    }
}
