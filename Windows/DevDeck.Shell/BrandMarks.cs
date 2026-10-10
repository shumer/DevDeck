using System.Reflection;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace DevDeck.Shell;

public static class BrandMarks
{
    private static readonly Lazy<IReadOnlyDictionary<string, Mark>> Marks = new(Load);

    public static IReadOnlyCollection<string> Names => Marks.Value.Keys.ToArray();

    public static FrameworkElement Create(string? name, double size = 16, Brush? tint = null)
    {
        if (name is null || !Marks.Value.TryGetValue(name, out var mark))
        {
            return new FrameworkElement { Width = size, Height = size };
        }

        var canvas = new Canvas
        {
            Width = mark.ViewBox[0],
            Height = mark.ViewBox[1],
        };
        foreach (var path in mark.Paths)
        {
            var geometry = Geometry.Parse(path.Data).Clone();
            if (mark.IsEvenOdd && geometry is StreamGeometry streamGeometry)
            {
                streamGeometry.FillRule = FillRule.EvenOdd;
            }
            canvas.Children.Add(new System.Windows.Shapes.Path
            {
                Data = geometry,
                Fill = tint ?? (Brush)new BrushConverter().ConvertFromString(path.Color)!,
            });
        }

        return new Viewbox
        {
            Width = size,
            Height = size,
            Stretch = Stretch.Uniform,
            Child = canvas,
        };
    }

    private static IReadOnlyDictionary<string, Mark> Load()
    {
        var assembly = Assembly.GetExecutingAssembly();
        using var stream = assembly.GetManifestResourceStream("DevDeck.BrandMarks.json")
            ?? throw new InvalidOperationException("Brand mark resource is missing.");
        var root = JsonSerializer.Deserialize<Root>(stream, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
        }) ?? throw new JsonException();
        return root.Marks;
    }

    private sealed record Root(Dictionary<string, Mark> Marks);
    private sealed record Mark(double[] ViewBox, bool IsEvenOdd, MarkPath[] Paths);
    private sealed record MarkPath(string Data, string Color);
}
