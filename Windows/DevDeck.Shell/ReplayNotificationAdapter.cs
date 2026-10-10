using System.Text;
using System.Text.Json;

namespace DevDeck.Shell;

public static class ReplayNotificationAdapter
{
    public static IReadOnlyList<DeckNotification> Parse(JsonElement value)
    {
        var notifications = new List<DeckNotification>();
        Add(value, notifications);
        return notifications;
    }

    private static void Add(JsonElement value, List<DeckNotification> notifications)
    {
        if (value.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in value.EnumerateArray())
            {
                Add(item, notifications);
            }
            return;
        }

        if (value.ValueKind != JsonValueKind.Object ||
            !DeckEvent.TryProperty(value, "target", out var target))
        {
            throw new JsonException();
        }

        notifications.Add(new DeckNotification(
            DeckEvent.RequiredString(value, "id"),
            DeckEvent.RequiredString(value, "source"),
            DeckEvent.RequiredString(value, "title"),
            DeckEvent.RequiredString(value, "subtitle"),
            DeckEvent.RequiredString(value, "body"),
            DeckEvent.RequiredBool(value, "isQuiet"),
            FollowAlertCommand(target)));
    }

    private static DeckCommand FollowAlertCommand(JsonElement target)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            writer.WritePropertyName("followAlert");
            writer.WriteStartObject();
            writer.WritePropertyName("_0");
            writer.WriteRawValue(target.GetRawText());
            writer.WriteEndObject();
            writer.WriteEndObject();
        }
        return new DeckCommand(Encoding.UTF8.GetString(stream.ToArray()));
    }
}
