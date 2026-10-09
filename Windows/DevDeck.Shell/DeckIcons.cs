using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace DevDeck.Shell;

public static class DeckIcons
{
    private static readonly IReadOnlyDictionary<string, string> Glyphs =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["start"] = "\uE768",
            ["stop"] = "\uE7E8",
            ["restart"] = "\uE72C",
            ["folder"] = "\uE8B7",
            ["terminal"] = "\uE756",
            ["open"] = "\uE8A7",
            ["openExternal"] = "\uE8A7",
            ["review"] = "\uE890",
            ["log"] = "\uEA37",
            ["phone"] = "\uED14",
            ["expand"] = "\uE70D",
            ["collapse"] = "\uE70E",
        };

    public static FrameworkElement Create(string? name, double size = 14)
    {
        if (name == "docker")
        {
            return BrandMarks.Create("docker", size);
        }

        var text = Glyphs.TryGetValue(name ?? "", out var glyph) ? glyph : "";
        return new TextBlock
        {
            Text = text,
            FontFamily = new FontFamily("Segoe Fluent Icons"),
            FontSize = size,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    public static string Text(string name)
    {
        return Glyphs[name];
    }
}
