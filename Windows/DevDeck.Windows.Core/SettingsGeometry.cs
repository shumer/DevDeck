using System.Text.Json;
using System.Text.Json.Serialization;

namespace DevDeck.Windows.Core;

[JsonConverter(typeof(SettingsWindowGeometryJsonConverter))]
public sealed record SettingsWindowGeometry(double Width, double Height);

public static class SettingsGeometry
{
    public const double DefaultWidth = 1020;
    public const double DefaultHeight = 720;
    public const double MinimumWidth = 880;
    public const double MinimumHeight = 440;
    public const double MaximumDimension = 10000;

    public static bool Valid(SettingsWindowGeometry? value) => value is null
        || double.IsFinite(value.Width) && double.IsFinite(value.Height)
        && value.Width is >= MinimumWidth and <= MaximumDimension
        && value.Height is >= MinimumHeight and <= MaximumDimension;

    public static SettingsWindowGeometry Restore(SettingsWindowGeometry? saved, double? workWidth, double? workHeight)
    {
        SettingsWindowGeometry chosen = Valid(saved) && saved is not null ? saved : new(DefaultWidth, DefaultHeight);
        if (workWidth is not { } width || workHeight is not { } height
            || !double.IsFinite(width) || !double.IsFinite(height) || width < MinimumWidth || height < MinimumHeight)
            return chosen;
        return new(Math.Min(chosen.Width, width), Math.Min(chosen.Height, height));
    }

    // A metadata draft cannot overwrite a separately committed window resize.
    public static DeckSettings PreserveCurrent(DeckSettings current, DeckSettings draft)
        => draft with { SettingsWindow = current.SettingsWindow };
}

// Stored corruption of this optional field must not discard otherwise valid settings.
// Keep parsing bounded without allocating an entire unknown JSON object or string value.
internal sealed class SettingsWindowGeometryJsonConverter : JsonConverter<SettingsWindowGeometry>
{
    private const int PropertyLimit = 8;
    private const int PropertyNameByteLimit = 64;
    public SettingsWindowGeometryJsonConverter() { }
    public override bool HandleNull => true;

    public override SettingsWindowGeometry? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType != JsonTokenType.StartObject) {
            reader.Skip();
            return null;
        }
        var properties = 0;
        var invalid = false;
        var hasWidth = false;
        var hasHeight = false;
        double width = 0, height = 0;
        while (reader.Read()) {
            if (reader.TokenType == JsonTokenType.EndObject) {
                var result = new SettingsWindowGeometry(width, height);
                return !invalid && hasWidth && hasHeight && SettingsGeometry.Valid(result) ? result : null;
            }
            if (reader.TokenType != JsonTokenType.PropertyName) throw new JsonException("Expected settings window property.");
            var nameBytes = reader.HasValueSequence ? reader.ValueSequence.Length : reader.ValueSpan.Length;
            var boundedName = ++properties <= PropertyLimit && nameBytes <= PropertyNameByteLimit;
            var name = boundedName ? reader.GetString() : null;
            if (!boundedName) invalid = true;
            if (!reader.Read()) throw new JsonException("Missing settings window property value.");
            if (string.Equals(name, "width", StringComparison.OrdinalIgnoreCase)) {
                if (hasWidth || reader.TokenType != JsonTokenType.Number || !reader.TryGetDouble(out width)) invalid = true;
                hasWidth = true;
            } else if (string.Equals(name, "height", StringComparison.OrdinalIgnoreCase)) {
                if (hasHeight || reader.TokenType != JsonTokenType.Number || !reader.TryGetDouble(out height)) invalid = true;
                hasHeight = true;
            }
            reader.Skip();
        }
        throw new JsonException("Incomplete settings window size.");
    }

    public override void Write(Utf8JsonWriter writer, SettingsWindowGeometry value, JsonSerializerOptions options)
    {
        if (value is null) { writer.WriteNullValue(); return; }
        if (!SettingsGeometry.Valid(value)) throw new JsonException("Settings window size is invalid.");
        writer.WriteStartObject();
        writer.WriteNumber("width", value.Width);
        writer.WriteNumber("height", value.Height);
        writer.WriteEndObject();
    }
}
