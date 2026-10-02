using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace DevDeck.Windows.App;

internal static class CardTheme
{
    internal const double Width = 410;
    internal static readonly Brush Ink = Brush(242, 245, 247);
    internal static readonly Brush Secondary = Brush(181, 191, 205);
    internal static readonly Brush Quiet = Brush(139, 152, 173);
    internal static readonly Brush Green = Brush(112, 199, 153);
    internal static readonly Brush Red = Brush(232, 132, 132);
    internal static readonly Brush Amber = Brush(240, 194, 107);
    internal static readonly Brush Blue = Brush(127, 174, 221);
    internal static readonly Brush PanelBackground = Brush(30, 31, 29);
    internal static readonly Brush PanelBorder = Brush(255, 255, 255, 48);
    private static readonly Brush Surface = Brush(255, 255, 255, 16);

    private static SolidColorBrush Brush(byte red, byte green, byte blue, byte alpha = 255)
    {
        var brush = new SolidColorBrush(Color.FromArgb(alpha, red, green, blue));
        brush.Freeze(); return brush;
    }

    internal static Border Frame(UIElement content) => new()
    {
        // Native layered-window translucency; the original Mac blur is a separate OS material.
        Background = new LinearGradientBrush(Color.FromArgb(232, 31, 33, 29), Color.FromArgb(238, 30, 29, 27), 0),
        BorderBrush = PanelBorder, BorderThickness = new(1), CornerRadius = new(20), Child = content
    };

    internal static TextBlock Heading(string title) => new()
    {
        Text = title, FontSize = 11.5, FontWeight = FontWeights.SemiBold, Foreground = Brush(242,245,247,165),
        VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis,
        ToolTip = title, Margin = new(0, 0, 8, 0)
    };

    internal static Border Badge(string text) => new()
    {
        Background = Surface, CornerRadius = new(5), Padding = new(7, 3, 7, 3), Margin = new(0, 0, 6, 0),
        Child = new TextBlock { Text = text, FontSize = 10, Foreground = Secondary }
    };

    internal static UIElement Icon(string name, Brush? ink = null)
    {
        var geometry = name switch
        {
            "collapse" => "M 4,10 L 8,6 L 12,10",
            "expand" => "M 4,6 L 8,10 L 12,6",
            "refresh" => "M 12,5 A 5,5 0 1 0 12,10 M 12,1 L 12,5 L 8,5",
            "settings" => "M 2,8 L 3,8 M 7,8 L 8,8 M 12,8 L 13,8",
            "gear" => "M 8,5 A 3,3 0 1 0 8,11 A 3,3 0 1 0 8,5 M 8,1 L 8,3 M 8,13 L 8,15 M 1,8 L 3,8 M 13,8 L 15,8 M 3,3 L 5,5 M 11,11 L 13,13 M 3,13 L 5,11 M 11,5 L 13,3",
            "bell" => "M 4,7 C 4,2 12,2 12,7 L 12,11 L 14,12 L 2,12 L 4,11 Z M 6,14 L 10,14 M 8,1 L 8,2",
            "terminal" => "M 1,3 L 15,3 L 15,13 L 1,13 Z M 4,6 L 6,8 L 4,10 M 8,10 L 11,10",
            "log" => "M 2,3 L 14,3 M 2,6 L 14,6 M 2,9 L 10,9 M 2,12 L 12,12",
            "branch" => "M 4,5 L 4,11 M 4,9 C 9,9 12,8 12,5 M 2,3 A 2,2 0 1 0 6,3 A 2,2 0 1 0 2,3 M 2,13 A 2,2 0 1 0 6,13 A 2,2 0 1 0 2,13 M 10,3 A 2,2 0 1 0 14,3 A 2,2 0 1 0 10,3",
            "folder" => "M 1,4 L 1,13 L 15,13 L 15,5 L 7,5 L 5,3 L 1,3 Z",
            "site" => "M 9,1 L 15,1 L 15,7 M 15,1 L 7,9 M 6,3 L 2,3 L 2,14 L 13,14 L 13,10",
            "qr" => "M 1,1 L 6,1 L 6,6 L 1,6 Z M 10,1 L 15,1 L 15,6 L 10,6 Z M 1,10 L 6,10 L 6,15 L 1,15 Z M 10,10 L 12,10 L 12,13 M 15,10 L 15,15 L 10,15",
            "start" => "M 4,2 L 13,8 L 4,14 Z",
            "stop" => "M 8,1 L 8,7 M 4,3 A 6,6 0 1 0 12,3",
            "cancel" => "M 4,4 L 12,12 M 12,4 L 4,12",
            "hammer" => "M 2,13 L 8,7 M 5,3 L 8,1 L 14,7 L 11,10 Z",
            "box" => "M 2,4 L 8,1 L 14,4 L 14,12 L 8,15 L 2,12 Z M 2,4 L 8,7 L 14,4 M 8,7 L 8,15",
            _ => throw new ArgumentException("Unknown card icon.", nameof(name))
        };
        return new Path { Data = Geometry.Parse(geometry), Width = 14, Height = 14, Stretch = Stretch.Uniform,
            Stroke = ink ?? Ink, StrokeThickness = 1.4, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
            StrokeLineJoin = PenLineJoin.Round, VerticalAlignment = VerticalAlignment.Center };
    }

    internal static Button Button(string label, Func<Task> action, string? icon = null, bool iconOnly = false)
    {
        var button = new Button { HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center,
            Padding = new(9, 7, 9, 7), Margin = new(0, 0, 6, 0), FontSize = 12, Background = Surface,
            Foreground = Ink, BorderBrush = Brushes.Transparent, BorderThickness = new(1), ToolTip = label };
        AutomationProperties.SetName(button, label);
        if (icon is null) button.Content = label;
        else
        {
            var content = new StackPanel { Orientation = Orientation.Horizontal };
            content.Children.Add(Icon(icon));
            if (!iconOnly) content.Children.Add(new TextBlock { Text = label, Margin = new(6, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
            else { button.Width = 32; button.Height = 32; button.Padding = new(7); }
            button.Content = content;
        }
        var frame = new FrameworkElementFactory(typeof(Border));
        frame.Name = "Surface";
        frame.SetValue(Border.BackgroundProperty, new TemplateBindingExtension(Control.BackgroundProperty));
        frame.SetValue(Border.BorderBrushProperty, new TemplateBindingExtension(Control.BorderBrushProperty));
        frame.SetValue(Border.BorderThicknessProperty, new TemplateBindingExtension(Control.BorderThicknessProperty));
        frame.SetValue(Border.PaddingProperty, new TemplateBindingExtension(Control.PaddingProperty));
        frame.SetValue(Border.CornerRadiusProperty, new CornerRadius(8));
        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(ContentPresenter.ContentProperty, new TemplateBindingExtension(ContentControl.ContentProperty));
        presenter.SetValue(FrameworkElement.HorizontalAlignmentProperty, new TemplateBindingExtension(Control.HorizontalContentAlignmentProperty));
        presenter.SetValue(FrameworkElement.VerticalAlignmentProperty, new TemplateBindingExtension(Control.VerticalContentAlignmentProperty));
        frame.AppendChild(presenter);
        var template = new ControlTemplate(typeof(Button)) { VisualTree = frame };
        foreach (var (property, value, fill) in new[] {
            (UIElement.IsMouseOverProperty, true, Brush(255, 255, 255, 30)),
            (System.Windows.Controls.Button.IsPressedProperty, true, Brush(255, 255, 255, 43)) })
        {
            var trigger = new Trigger { Property = property, Value = value };
            trigger.Setters.Add(new Setter(Border.BackgroundProperty, fill, "Surface")); template.Triggers.Add(trigger);
        }
        var focus = new Trigger { Property = UIElement.IsKeyboardFocusedProperty, Value = true };
        focus.Setters.Add(new Setter(Border.BorderBrushProperty, Blue, "Surface")); template.Triggers.Add(focus);
        var disabled = new Trigger { Property = UIElement.IsEnabledProperty, Value = false };
        disabled.Setters.Add(new Setter(UIElement.OpacityProperty, 0.35)); template.Triggers.Add(disabled);
        button.Template = template;
        button.Click += async (_, _) => { try { await action(); } catch (OperationCanceledException) { } catch (Exception error) { MessageBox.Show(Text.Failure(error), "DevDeck"); } };
        return button;
    }

    internal static void Compact(Button button, string label, string icon, bool compact)
    {
        var content = new StackPanel { Orientation = Orientation.Horizontal };
        content.Children.Add(Icon(icon, button.Foreground));
        if (!compact) content.Children.Add(new TextBlock { Text = label, Margin = new(6,0,0,0), VerticalAlignment = VerticalAlignment.Center });
        button.Content = content; button.Width = compact ? 30 : double.NaN; button.Height = 32;
        button.MinWidth = compact ? 0 : 108; button.Padding = new(compact ? 6 : 8); button.Margin = new(0,0,5,0);
    }
    internal static void CollapseControl(Button button, bool collapsed)
    {
        var label = Text.L(collapsed ? "menu.card.showWhole" : "menu.card.collapse");
        button.Content = Icon(collapsed ? "expand" : "collapse"); button.ToolTip = label;
        AutomationProperties.SetName(button,label);
    }

    internal static void Emphasize(Button button, Brush tint)
    {
        button.Foreground = tint; button.FontWeight = FontWeights.SemiBold;
        if (button.Content is Panel panel && panel.Children.Count > 0 && panel.Children[0] is Path icon) icon.Stroke = tint;
        if (tint is SolidColorBrush solid)
        {
            var color = solid.Color;
            button.Background = Brush(color.R, color.G, color.B, 25);
            button.BorderBrush = Brush(color.R, color.G, color.B, 66);
        }
    }
}
