using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;

namespace DevDeck.Windows.Core;

/// Reads the original six-language resources without rewriting or translating the Mac files.
public sealed class Localization
{
    public static readonly string[] Languages = ["en", "ru", "de", "es", "fr", "it"];
    private readonly Dictionary<string, string> values;
    private readonly Dictionary<string, Dictionary<string, string>> plurals;
    public string Language { get; }
    public int Count => values.Count;
    public Localization(string language)
    {
        Language = Languages.Contains(language) ? language : "en";
        using var stream = typeof(Localization).Assembly.GetManifestResourceStream("DevDeck.Strings." + Language)
            ?? throw new InvalidDataException("Language resources are missing.");
        using var reader = new StreamReader(stream);
        values = Parse(reader.ReadToEnd());
        using var pluralStream = typeof(Localization).Assembly.GetManifestResourceStream("DevDeck.Plurals." + Language)
            ?? throw new InvalidDataException("Plural resources are missing.");
        using var xml = XmlReader.Create(pluralStream, new XmlReaderSettings { DtdProcessing = DtdProcessing.Ignore, XmlResolver = null });
        var root = XDocument.Load(xml).Root?.Element("dict") ?? throw new InvalidDataException("Plural resources are invalid.");
        static Dictionary<string, XElement> Entries(XElement dictionary) {
            var children = dictionary.Elements().ToArray();
            return Enumerable.Range(0, children.Length / 2).ToDictionary(index => children[index * 2].Value, index => children[index * 2 + 1], StringComparer.Ordinal);
        }
        plurals = Entries(root).ToDictionary(entry => entry.Key, entry => Entries(Entries(entry.Value)["count"]).ToDictionary(rule => rule.Key, rule => rule.Value.Value), StringComparer.Ordinal);
        using var extraStream = typeof(Localization).Assembly.GetManifestResourceStream("DevDeck.Windows.Strings")
            ?? throw new InvalidDataException("Windows language resources are missing.");
        var extra = JsonSerializer.Deserialize<Dictionary<string, string[]>>(extraStream)!;
        var index = Array.IndexOf(Languages, Language);
        foreach (var entry in extra)
        {
            if (entry.Value.Length != Languages.Length || entry.Value.Any(string.IsNullOrWhiteSpace))
                throw new InvalidDataException("Windows translation must cover all six languages.");
            if (!values.TryAdd(entry.Key, entry.Value[index])) throw new InvalidDataException("Windows translation shadows an original key.");
        }
    }
    public static Dictionary<string, string> Parse(string source)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (Match entry in Regex.Matches(source, "(?m)^\\s*(\"(?:\\\\.|[^\"\\\\])*\")\\s*=\\s*(\"(?:\\\\.|[^\"\\\\])*\")\\s*;"))
        {
            var key = JsonSerializer.Deserialize<string>(entry.Groups[1].Value)!;
            var value = JsonSerializer.Deserialize<string>(entry.Groups[2].Value)!;
            if (!result.TryAdd(key, value)) throw new InvalidDataException("Duplicate localization key.");
        }
        return result;
    }
    public string Get(string key, params object[] arguments)
    {
        if (!values.TryGetValue(key, out var value)) return key;
        return Format(value, arguments);
    }
    public string Plural(string key, int count)
    {
        if (!plurals.TryGetValue(key, out var forms)) return key;
        var number = Math.Abs((long)count);
        var rule = Language switch {
            "ru" when number % 10 == 1 && number % 100 != 11 => "one",
            "ru" when number % 10 is >= 2 and <= 4 && number % 100 is not (>= 12 and <= 14) => "few",
            "ru" => "many", "fr" when number is 0 or 1 => "one", _ when number == 1 => "one", _ => "other"
        };
        return Format(forms.GetValueOrDefault(rule) ?? forms["other"], [count]);
    }
    private string Format(string value, object[] arguments)
    {
        var next = 0;
        return Regex.Replace(value, @"%%|%(?:(\d+)\$)?[@df]", match =>
        {
            if (match.Value == "%%") return "%";
            var index = match.Groups[1].Success ? int.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture) - 1 : next++;
            return index < arguments.Length ? Convert.ToString(arguments[index], CultureInfo.GetCultureInfo(Language)) ?? "" : match.Value;
        });
    }
}
