using System;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal static class BrandMarks
{
    private static readonly JsonDocument Data = JsonDocument.Parse(typeof(BrandMarks).Assembly.GetManifestResourceStream("DevDeck.Windows.BrandMarks")!);
    internal static UIElement Create(string kind, double size = 18, bool tile = false)
    {
        var panel = new Grid { Width = size, Height = size };
        if (kind == "arc")
        {
            // The same two polygons/gradient as Mac CardGlyph.ArcMark, in its 100-unit canvas.
            var canvas = new Canvas { Width = 100, Height = 100 };
            canvas.Children.Add(new Path { Data = Geometry.Parse("M 44,14 L 64,14 L 34,86 L 8,86 Z"), Fill = Brushes.White });
            canvas.Children.Add(new Path { Data = Geometry.Parse("M 64,14 L 92,86 L 62,86 L 48,50 Z"), Fill = new LinearGradientBrush(Color.FromRgb(51,168,222),Color.FromRgb(79,194,161),90) });
            panel.Children.Add(new Viewbox { Child = canvas });
        }
        else if (Data.RootElement.TryGetProperty(kind, out var value))
        {
            var group = new GeometryGroup { FillRule = kind == "ddev" ? FillRule.EvenOdd : FillRule.Nonzero };
            if (value.ValueKind == JsonValueKind.Array) foreach (var path in value.EnumerateArray()) group.Children.Add(Geometry.Parse(path.GetString()!));
            else group.Children.Add(Geometry.Parse(value.GetString()!));
            panel.Children.Add(new Path { Data = group, Stretch = Stretch.Uniform,
                Fill = kind switch { "ddev" => new SolidColorBrush(Color.FromRgb(2,168,226)), "gitlab" => new SolidColorBrush(Color.FromRgb(252,111,29)), "node" => new SolidColorBrush(Color.FromRgb(140,200,75)), "nest" => new SolidColorBrush(Color.FromRgb(224,35,78)), "bun" => new SolidColorBrush(Color.FromRgb(251,240,223)), "docker" => new SolidColorBrush(Color.FromRgb(37,150,237)), _ => Brushes.White } });
        }
        else panel.Children.Add(CardTheme.Icon(kind switch { "general" => "gear", "deck" => "folder", "cards" => "qr", "notifications" => "bell", "make" => "hammer", "other" => "box", _ => "terminal" }));
        if (!tile) return panel;
        return new Border { Width = size + 12, Height = size + 12, CornerRadius = new(6), Child = panel,
            Background = kind switch { "general" => Brushes.Gray, "deck" => new SolidColorBrush(Color.FromRgb(54,120,240)), "cards" => new SolidColorBrush(Color.FromRgb(106,82,219)), "notifications" => new SolidColorBrush(Color.FromRgb(226,76,88)), _ => new SolidColorBrush(Color.FromRgb(35,37,40)) } };
    }
    internal static string ProjectKind(string kind, string? framework = null, string? startCommand = null) => kind is "arc" or "ddev" ? kind : ProjectDetection.Glyph(startCommand,framework);
}
