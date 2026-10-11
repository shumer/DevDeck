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
            ["settings"] = "\uE713",
            ["deck"] = "\uE80A",
            ["grid"] = "\uECA5",
            ["notification"] = "\uEA8F",
            ["remove"] = "\uE74D",
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

    // Segoe Fluent Icons has no branch glyph that reads as one, so this is the reference mock's
    // vector on its 16 unit grid, drawn at the size the branch row asks for.
    public static FrameworkElement Branch(Brush stroke, double size = 13)
    {
        var geometry = new GeometryGroup();
        geometry.Children.Add(new EllipseGeometry(new Point(4.5, 3.5), 1.6, 1.6));
        geometry.Children.Add(new EllipseGeometry(new Point(4.5, 12.5), 1.6, 1.6));
        geometry.Children.Add(new EllipseGeometry(new Point(11.5, 5.5), 1.6, 1.6));
        geometry.Children.Add(Geometry.Parse("M4.5,5.1 v5.8 M11.5,7.1 c0,2.4 -2.2,3.2 -5.6,3.9"));
        var canvas = new Canvas { Width = 16, Height = 16 };
        canvas.Children.Add(new System.Windows.Shapes.Path
        {
            Data = geometry,
            Stroke = stroke,
            StrokeThickness = 1.3,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
        });
        return new Viewbox
        {
            Width = size,
            Height = size,
            VerticalAlignment = VerticalAlignment.Center,
            Child = canvas,
        };
    }
}
