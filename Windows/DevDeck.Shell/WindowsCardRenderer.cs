using System.Globalization;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using Button = System.Windows.Controls.Button;

namespace DevDeck.Shell;

public static class WindowsCardRenderer
{
    public static FrameworkElement Stopped(JsonElement model, Action<DeckCommand> command)
    {
        return Collapsed(model, command);
    }

    public static FrameworkElement ReviewList(JsonElement model, Action<DeckCommand> command)
    {
        if (JsonModel.Bool(model, "isCollapsed") && JsonModel.Object(model, "collapsed", out var collapsed))
        {
            return Collapsed(collapsed, command);
        }

        var stack = Stack();
        stack.Children.Add(Header(
            JsonModel.String(model, "mark"),
            JsonModel.String(model, "title"),
            JsonModel.String(model, "timestamp")));
        if (!JsonModel.Object(model, "content", out var content))
        {
            AddPlaceholder(stack, model);
            return WindowsTheme.CardFrame(stack);
        }

        stack.Children.Add(ReviewHero(content));
        if (JsonModel.Array(content, "shares", out var shares))
        {
            stack.Children.Add(Shares(shares));
        }
        if (JsonModel.Array(content, "rows", out var rows))
        {
            var rowIndex = 0;
            foreach (var row in rows.EnumerateArray())
            {
                stack.Children.Add(ReviewRow(row, rowIndex > 0, command));
                rowIndex++;
            }
        }
        if (JsonModel.Object(content, "expander", out var expander) && JsonModel.Command(expander) is { } expanderCommand)
        {
            var expanderContent = new StackPanel { Orientation = Orientation.Horizontal };
            expanderContent.Children.Add(Text(ExpanderLabel(JsonModel.String(expander, "label")), 12, WindowsTheme.Brush("TextSecondary")));
            var expanderIcon = DeckIcons.Create(JsonModel.Bool(expander, "isExpanded") ? "collapse" : "expand", 12);
            expanderIcon.Margin = new Thickness(4, 0, 0, 0);
            expanderContent.Children.Add(expanderIcon);
            var button = CommandButton(expanderContent, expanderCommand, true, command, "ExpanderButton");
            button.Foreground = WindowsTheme.Brush("TextSecondary");
            button.Margin = new Thickness(0, 2, 0, 0);
            stack.Children.Add(button);
        }
        if (JsonModel.Object(content, "footer", out var footer))
        {
            var footerRow = new DockPanel { Margin = new Thickness(2, 7, 2, 0) };
            footerRow.Children.Add(Text(JsonModel.String(footer, "leading"), 12, WindowsTheme.Brush("TextTertiary")));
            if (JsonModel.String(footer, "trailing") is { } trailing)
            {
                var trailingText = Text(trailing, 12, WindowsTheme.Brush("TextTertiary"));
                DockPanel.SetDock(trailingText, Dock.Right);
                footerRow.Children.Add(trailingText);
            }
            stack.Children.Add(footerRow);
        }
        return WindowsTheme.CardFrame(stack);
    }

    public static FrameworkElement Project(JsonElement model, Action<DeckCommand> command)
    {
        if (JsonModel.Bool(model, "isCollapsed") && JsonModel.Object(model, "collapsed", out var collapsed))
        {
            return Collapsed(collapsed, command);
        }

        var stack = Stack();
        stack.Children.Add(ProjectHeader(model, command));
        if (JsonModel.Object(model, "hero", out var hero))
        {
            var heroRow = new DockPanel { Margin = new Thickness(1, 2, 1, 4) };
            var heroText = Text(JsonModel.String(hero, "text"), 22, WindowsTheme.Tone(JsonModel.String(hero, "tone")));
            heroText.FontWeight = FontWeights.SemiBold;
            heroRow.Children.Add(StatusDot(JsonModel.String(hero, "tone"), 9));
            heroRow.Children.Add(heroText);
            if (JsonModel.String(hero, "aside") is { } aside)
            {
                var asideText = Text(aside, 11, WindowsTheme.Brush("TextTertiary"), true);
                DockPanel.SetDock(asideText, Dock.Right);
                heroRow.Children.Add(asideText);
            }
            heroRow.ToolTip = JsonModel.String(hero, "help");
            stack.Children.Add(heroRow);
            if (JsonModel.String(hero, "note") is { } note)
            {
                stack.Children.Add(Text(note, 12, WindowsTheme.Brush("TextSecondary")));
            }
        }
        if (JsonModel.Object(model, "meta", out var meta))
        {
            stack.Children.Add(ProjectMeta(meta, command));
        }
        stack.Children.Add(Chips(model, command));
        if (JsonModel.Array(model, "actions", out var actions))
        {
            stack.Children.Add(Actions(actions, command));
        }
        return WindowsTheme.CardFrame(stack);
    }

    private static FrameworkElement Header(string? mark, string? title, string? timestamp)
    {
        var row = new DockPanel { Height = 20, Margin = new Thickness(1, 0, 1, 8) };
        if (timestamp is not null)
        {
            var time = Text(timestamp, 11, WindowsTheme.Brush("TextTertiary"), true);
            DockPanel.SetDock(time, Dock.Right);
            row.Children.Add(time);
        }
        row.Children.Add(Mark(mark));
        var titleText = Eyebrow(title);
        titleText.Margin = new Thickness(8, 0, 6, 0);
        row.Children.Add(titleText);
        return row;
    }

    private static FrameworkElement ProjectHeader(JsonElement model, Action<DeckCommand> command)
    {
        var row = new DockPanel { Height = 20, Margin = new Thickness(1, 0, 1, 8) };
        var time = Text(JsonModel.String(model, "timestamp"), 11, WindowsTheme.Brush("TextTertiary"), true);
        DockPanel.SetDock(time, Dock.Right);
        row.Children.Add(time);
        if (JsonModel.Object(model, "header", out var header))
        {
            if (JsonModel.String(header, "phoneURL") is not null)
            {
                var phone = IconButton("phone", JsonModel.String(header, "phoneHelp"), "project.header.phone");
                DockPanel.SetDock(phone, Dock.Right);
                row.Children.Add(phone);
            }
            if (JsonModel.Command(header, "log") is { } log)
            {
                var logButton = IconButton("log", JsonModel.String(header, "logHelp"), "project.header.log");
                if (JsonModel.Bool(header, "logIsOn"))
                {
                    logButton.Foreground = WindowsTheme.Brush("ToneGood");
                    logButton.Background = ColorBrush(Color.FromArgb(34, 112, 199, 153));
                    if (logButton.Content is TextBlock icon)
                    {
                        icon.Foreground = WindowsTheme.Brush("ToneGood");
                    }
                }
                logButton.Click += (_, _) => command(log);
                DockPanel.SetDock(logButton, Dock.Right);
                row.Children.Add(logButton);
            }
        }
        row.Children.Add(Mark(JsonModel.String(model, "mark")));
        var title = Eyebrow(JsonModel.String(model, "title"));
        title.Margin = new Thickness(8, 0, 6, 0);
        row.Children.Add(title);
        return row;
    }

    private static FrameworkElement ReviewHero(JsonElement content)
    {
        var grid = new Grid { Margin = new Thickness(1, 0, 1, 7) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var count = Text(JsonModel.NumberText(content, "count"), 30, WindowsTheme.Brush("TextPrimary"));
        count.FontWeight = FontWeights.SemiBold;
        grid.Children.Add(count);
        var unit = Text(JsonModel.String(content, "unit"), 14, WindowsTheme.Brush("TextSecondary"));
        unit.Margin = new Thickness(7, 11, 0, 0);
        Grid.SetColumn(unit, 1);
        grid.Children.Add(unit);
        if (JsonModel.Object(content, "pill", out var pill))
        {
            var pillText = Text(JsonModel.String(pill, "text"), 12, WindowsTheme.Tone(JsonModel.String(pill, "tone")));
            pillText.FontWeight = FontWeights.SemiBold;
            pillText.Margin = new Thickness(0, 11, 0, 0);
            Grid.SetColumn(pillText, 2);
            grid.Children.Add(pillText);
        }
        return grid;
    }

    private static FrameworkElement Shares(JsonElement shares)
    {
        var grid = new Grid { Height = 3, Margin = new Thickness(1, 0, 1, 8) };
        foreach (var share in shares.EnumerateArray())
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(Math.Max(1, Number(share, "count")), GridUnitType.Star),
            });
            var segment = new Border
            {
                Background = WindowsTheme.Tone(JsonModel.String(share, "tone")),
                CornerRadius = new CornerRadius(2),
                Margin = new Thickness(grid.Children.Count == 0 ? 0 : 1, 0, 0, 0),
            };
            Grid.SetColumn(segment, grid.Children.Count);
            grid.Children.Add(segment);
        }
        return grid;
    }

    private static FrameworkElement ReviewRow(JsonElement model, bool hasSeparator, Action<DeckCommand> command)
    {
        var row = new Grid();
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(StatusDot(JsonModel.String(model, "tone"), 7));
        var key = JsonModel.String(model, "key");
        if (key is not null)
        {
            var keyBorder = new Border
            {
                Background = ColorBrush(Color.FromArgb(18, 255, 255, 255)),
                CornerRadius = new CornerRadius(3),
                Margin = new Thickness(6, 5, 5, 5),
                Padding = new Thickness(4, 0, 4, 0),
                Child = Text(key, 11, WindowsTheme.Brush("TextSecondary"), true),
            };
            Grid.SetColumn(keyBorder, 1);
            row.Children.Add(keyBorder);
        }
        if (JsonModel.Object(model, "icon", out var icon))
        {
            var iconView = DeckIcons.Create(JsonModel.String(icon, "glyph"), 12);
            iconView.ToolTip = JsonModel.String(icon, "help");
            iconView.Margin = new Thickness(4, 0, 4, 0);
            if (iconView is TextBlock iconText)
            {
                iconText.Foreground = WindowsTheme.Tone(JsonModel.String(icon, "tone"));
            }
            Grid.SetColumn(iconView, 2);
            row.Children.Add(iconView);
        }
        var title = Text(JsonModel.String(model, "title"), 13, WindowsTheme.Brush("TextPrimary"));
        title.Margin = new Thickness(4, 0, 6, 0);
        Grid.SetColumn(title, 3);
        row.Children.Add(title);
        var trailing = Text(JsonModel.String(model, "trailing"), 11, WindowsTheme.Brush("TextTertiary"), true);
        trailing.Margin = new Thickness(6, 0, 0, 0);
        Grid.SetColumn(trailing, 4);
        row.Children.Add(trailing);
        if (JsonModel.Command(model) is not { } rowCommand)
        {
            return ReviewRowFrame(row, hasSeparator);
        }
        var button = CommandButton(row, rowCommand, true, command, "RowButton");
        button.ToolTip = JsonModel.String(model, "help");
        return ReviewRowFrame(button, hasSeparator);
    }

    private static FrameworkElement ProjectMeta(JsonElement meta, Action<DeckCommand> command)
    {
        var stack = new StackPanel();
        if (JsonModel.String(meta, "branch") is { } branch)
        {
            var branchRow = new DockPanel { Height = 24 };
            var branchIcon = BranchIcon();
            branchRow.Children.Add(branchIcon);
            FrameworkElement branchText = Text(branch, 12, WindowsTheme.Brush("LinkInfo"), true);
            if (JsonModel.Command(meta, "repository") is { } repository)
            {
                var button = CommandButton(branchText, repository, true, command, "RowButton");
                button.ToolTip = JsonModel.String(meta, "branchHelp");
                branchText = button;
            }
            branchRow.Children.Add(branchText);
            stack.Children.Add(branchRow);
        }
        var details = new Grid { Margin = new Thickness(1, 3, 1, 4) };
        details.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        details.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var leading = Text(JsonModel.String(meta, "leading"), 12, WindowsTheme.Brush("TextSecondary"));
        details.Children.Add(leading);
        var trailing = TrackedText(
            JsonModel.String(meta, "trailing"),
            11,
            WindowsTheme.Brush("TextTertiary"),
            WindowsTheme.Mono,
            0,
            DeckTextTrimming.Middle);
        trailing.MaxWidth = 150;
        trailing.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(trailing, 1);
        details.Children.Add(trailing);
        stack.Children.Add(details);
        return stack;
    }

    private static FrameworkElement Chips(JsonElement model, Action<DeckCommand> command)
    {
        var row = new WrapPanel { Margin = new Thickness(0, 2, 0, 8) };
        AddChips(row, model, "tools", command);
        AddChips(row, model, "environments", command);
        if (JsonModel.Object(model, "meta", out var meta) && JsonModel.String(meta, "place") is { } place)
        {
            var placeText = Text(place, 12, WindowsTheme.Brush("TextPrimary"));
            var placeOutline = new System.Windows.Shapes.Rectangle
            {
                Stroke = WindowsTheme.Brush("ControlStroke"),
                StrokeThickness = 1,
                StrokeDashArray = new DoubleCollection { 2, 2 },
                RadiusX = 4,
                RadiusY = 4,
            };
            var placeChip = new Grid
            {
                Height = 24,
                Margin = new Thickness(1, 1, 4, 1),
            };
            placeText.Margin = new Thickness(7, 0, 7, 0);
            placeChip.Children.Add(placeOutline);
            placeChip.Children.Add(placeText);
            row.Children.Add(placeChip);
        }
        return row;
    }

    private static void AddChips(Panel row, JsonElement model, string name, Action<DeckCommand> command)
    {
        if (!JsonModel.Array(model, name, out var chips))
        {
            return;
        }
        foreach (var chip in chips.EnumerateArray())
        {
            FrameworkElement view;
            if (JsonModel.Command(chip) is { } chipCommand)
            {
                var button = CommandButton(JsonModel.String(chip, "label"), chipCommand, !JsonModel.Bool(chip, "isDimmed"), command, "ChipButton");
                button.ToolTip = JsonModel.String(chip, "help");
                view = button;
            }
            else
            {
                view = new Border
                {
                    Background = WindowsTheme.Brush("ControlFill"),
                    CornerRadius = new CornerRadius(4),
                    Padding = new Thickness(7, 3, 7, 3),
                    Child = Text(JsonModel.String(chip, "label"), 12, WindowsTheme.Brush("TextSecondary")),
                };
            }
            view.Margin = new Thickness(1, 1, 4, 1);
            view.Opacity = JsonModel.Bool(chip, "isDimmed") ? 0.42 : 1;
            row.Children.Add(view);
        }
    }

    private static FrameworkElement Actions(JsonElement actions, Action<DeckCommand> command)
    {
        var grid = new Grid { Margin = new Thickness(0, 0, 0, 0) };
        var index = 0;
        foreach (var action in actions.EnumerateArray())
        {
            var prominent = JsonModel.Bool(action, "isProminent");
            var glyph = JsonModel.String(action, "glyph");
            var iconOnly = glyph is "folder" or "terminal" or "openExternal";
            grid.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = prominent ? new GridLength(1, GridUnitType.Star) : GridLength.Auto,
            });
            FrameworkElement content;
            if (iconOnly)
            {
                content = DeckIcons.Create(glyph, 14);
            }
            else
            {
                var inner = new StackPanel { Orientation = Orientation.Horizontal };
                var icon = DeckIcons.Create(glyph, 14);
                icon.Margin = new Thickness(0, 0, 7, 0);
                inner.Children.Add(icon);
                inner.Children.Add(Text(JsonModel.String(action, "title"), 13, WindowsTheme.Brush("TextPrimary")));
                content = inner;
            }
            var actionCommand = JsonModel.Command(action);
            var button = actionCommand is { } actualCommand
                ? CommandButton(content, actualCommand, Enabled(action), command, "FluentButton")
                : new Button { Content = content };
            button.Style = WindowsTheme.Style("FluentButton");
            button.IsEnabled = Enabled(action);
            button.ToolTip = JsonModel.String(action, "help") ?? JsonModel.String(action, "title");
            AutomationProperties.SetName(button, JsonModel.String(action, "title") ?? "");
            button.Margin = new Thickness(index == 0 ? 0 : 4, 0, 0, 0);
            if (iconOnly)
            {
                button.Width = 36;
                button.Padding = new Thickness(0);
            }
            if (prominent)
            {
                button.Background = ToneFill(JsonModel.String(action, "tone"));
                button.BorderBrush = WindowsTheme.Tone(JsonModel.String(action, "tone"));
            }
            Grid.SetColumn(button, index);
            grid.Children.Add(button);
            index++;
        }
        return grid;
    }

    private static FrameworkElement Collapsed(JsonElement model, Action<DeckCommand> command)
    {
        var row = new DockPanel { Height = 30 };
        row.ToolTip = JsonModel.String(model, "help");
        if (JsonModel.Array(model, "actions", out var actions))
        {
            foreach (var action in actions.EnumerateArray().Reverse())
            {
                if (JsonModel.Command(action) is not { } actionCommand)
                {
                    continue;
                }
                var button = CommandButton(DeckIcons.Create(JsonModel.String(action, "glyph"), 13), actionCommand, Enabled(action), command, "HeaderIconButton");
                button.Width = 28;
                button.Height = 28;
                button.ToolTip = JsonModel.String(action, "help") ?? JsonModel.String(action, "title");
                AutomationProperties.SetName(button, JsonModel.String(action, "title") ?? "");
                DockPanel.SetDock(button, Dock.Right);
                row.Children.Add(button);
            }
        }
        row.Children.Add(Mark(JsonModel.String(model, "mark")));
        row.Children.Add(StatusDot(JsonModel.String(model, "tone"), 9));
        var title = Text(JsonModel.String(model, "title"), 14, WindowsTheme.Brush("TextPrimary"));
        title.FontWeight = FontWeights.SemiBold;
        title.Margin = new Thickness(6, 0, 4, 0);
        row.Children.Add(title);
        return WindowsTheme.CardFrame(row);
    }

    private static FrameworkElement Mark(string? name)
    {
        var mark = BrandMarks.Create(name, 16);
        mark.Margin = new Thickness(0, 2, 0, 2);
        return mark;
    }

    private static Border StatusDot(string? tone, double size)
    {
        return new Border
        {
            Width = size,
            Height = size,
            CornerRadius = new CornerRadius(size / 2),
            Background = WindowsTheme.Tone(tone),
            Margin = new Thickness(2, 0, 7, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    private static Button IconButton(string glyph, string? help, string automationId)
    {
        var button = new Button
        {
            Content = DeckIcons.Create(glyph, 13),
            Style = WindowsTheme.Style("HeaderIconButton"),
            ToolTip = help,
            Margin = new Thickness(3, 0, 0, 0),
        };
        AutomationProperties.SetAutomationId(button, automationId);
        AutomationProperties.SetName(button, help ?? "");
        return button;
    }

    private static Button CommandButton(object? content, DeckCommand deckCommand, bool enabled, Action<DeckCommand> command, string style)
    {
        var button = new Button
        {
            Content = content,
            IsEnabled = enabled,
            Style = WindowsTheme.Style(style),
        };
        button.Click += (_, _) => command(deckCommand);
        return button;
    }

    private static TextBlock Text(string? value, double size, Brush brush, bool mono = false)
    {
        WindowsTheme.EnsureLoaded();
        return new TextBlock
        {
            Text = value ?? "",
            Foreground = brush,
            FontFamily = mono ? WindowsTheme.Mono : WindowsTheme.Sans,
            FontSize = size,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    private static TrackedTextBlock Eyebrow(string? value)
    {
        return TrackedText(
            value?.ToUpper(CultureInfo.CurrentUICulture),
            11,
            WindowsTheme.Brush("TextSecondary"),
            WindowsTheme.Sans,
            0.07,
            DeckTextTrimming.Middle,
            FontWeights.SemiBold);
    }

    private static TrackedTextBlock TrackedText(
        string? value,
        double size,
        Brush brush,
        FontFamily family,
        double tracking,
        DeckTextTrimming trimming,
        FontWeight? weight = null)
    {
        return new TrackedTextBlock
        {
            Text = value ?? "",
            Foreground = brush,
            FontFamily = family,
            FontSize = size,
            FontWeight = weight ?? FontWeights.Normal,
            TrackingEm = tracking,
            Trimming = trimming,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    private static FrameworkElement ReviewRowFrame(FrameworkElement content, bool hasSeparator)
    {
        var frame = new Grid { Height = 30 };
        frame.Children.Add(content);
        if (hasSeparator)
        {
            frame.Children.Add(new Border
            {
                Height = 1,
                Background = WindowsTheme.Brush("SeparatorStroke"),
                VerticalAlignment = VerticalAlignment.Top,
                IsHitTestVisible = false,
            });
        }
        return frame;
    }

    private static string ExpanderLabel(string? label)
    {
        return (label ?? "").TrimEnd().TrimEnd('^', '⌃', '⌄').TrimEnd();
    }

    private static StackPanel Stack()
    {
        return new StackPanel();
    }

    private static void AddPlaceholder(Panel stack, JsonElement model)
    {
        if (!JsonModel.Object(model, "placeholder", out var placeholder))
        {
            return;
        }
        stack.Children.Add(Text(JsonModel.String(placeholder, "message"), 13, WindowsTheme.Brush("TextPrimary")));
        if (JsonModel.String(placeholder, "hint") is { } hint)
        {
            stack.Children.Add(Text(hint, 12, WindowsTheme.Brush("TextSecondary")));
        }
    }

    private static FrameworkElement BranchIcon()
    {
        var path = new System.Windows.Shapes.Path
        {
            Data = Geometry.Parse("M3,2 L3,9 C3,12 11,9 11,14 M3,2 L1,4 M3,2 L5,4"),
            Stroke = WindowsTheme.Brush("LinkInfo"),
            StrokeThickness = 1.2,
        };
        return new Viewbox
        {
            Width = 14,
            Height = 14,
            Margin = new Thickness(1, 0, 7, 0),
            Child = path,
        };
    }

    private static bool Enabled(JsonElement model)
    {
        return !DeckEvent.TryProperty(model, "isEnabled", out var enabled) || enabled.ValueKind == JsonValueKind.True;
    }

    private static double Number(JsonElement model, string name)
    {
        return DeckEvent.TryProperty(model, name, out var number) && number.TryGetDouble(out var value) ? value : 1;
    }

    private static Brush ToneFill(string? tone)
    {
        var color = tone switch
        {
            "good" => Color.FromArgb(35, 112, 199, 153),
            "attention" => Color.FromArgb(35, 240, 194, 107),
            "alert" => Color.FromArgb(35, 232, 132, 132),
            "personal" => Color.FromArgb(35, 169, 155, 224),
            _ => Color.FromArgb(15, 255, 255, 255),
        };
        return ColorBrush(color);
    }

    private static SolidColorBrush ColorBrush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}
