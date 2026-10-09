using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using Button = System.Windows.Controls.Button;

namespace DevDeck.Shell;

public static class CardRenderer
{
    public static bool CanRender(JsonElement model)
    {
        if (model.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        var kinds = model.EnumerateObject().ToArray();
        return kinds.Length == 1 && kinds[0].Name is
            "reviewList" or "inbox" or "actions" or "workInFlight" or "project";
    }

    public static FrameworkElement Create(JsonElement model, Action<DeckCommand> command)
    {
        var kind = model.EnumerateObject().Single();
        return kind.Name switch
        {
            "reviewList" => WindowsCardRenderer.ReviewList(kind.Value, command),
            "inbox" => Inbox(kind.Value, command),
            "actions" => Actions(kind.Value, command),
            "workInFlight" => WorkInFlight(kind.Value, command),
            "project" => WindowsCardRenderer.Project(kind.Value, command),
            _ => new Grid(),
        };
    }

    public static FrameworkElement CreateStopped(JsonElement stopped, JsonElement? status)
    {
        var content = WindowsCardRenderer.Stopped(stopped, _ => { });
        if (status is { } stoppedStatus)
        {
            content.ToolTip = JsonModel.String(stoppedStatus, "tooltip");
            content.SetValue(
                AutomationProperties.NameProperty,
                JsonModel.String(stoppedStatus, "accessibilityValue"));
        }

        return content;
    }

    private static FrameworkElement ReviewList(JsonElement model, Action<DeckCommand> command)
    {
        if (JsonModel.Bool(model, "isCollapsed") && JsonModel.Object(model, "collapsed", out var collapsed))
        {
            return Collapsed(collapsed, command);
        }

        var stack = CardStack();
        stack.Children.Add(Header(model, "mark", "title", "timestamp"));
        if (JsonModel.Object(model, "content", out var content))
        {
            stack.Children.Add(CountLine(content, "count", "unit", "pill"));
            if (JsonModel.Array(content, "shares", out var shares))
            {
                stack.Children.Add(Shares(shares));
            }
            AddRows(stack, content, row => ReviewRow(row, command));
            AddExpander(stack, content, command);
            AddFooter(stack, content);
        }
        else
        {
            AddPlaceholder(stack, model);
        }

        return Frame(stack);
    }

    private static FrameworkElement Inbox(JsonElement model, Action<DeckCommand> command)
    {
        if (JsonModel.Bool(model, "isCollapsed") && JsonModel.Object(model, "collapsed", out var collapsed))
        {
            return Collapsed(collapsed, command);
        }

        var stack = CardStack();
        stack.Children.Add(Header(model, null, "title", null, "pill"));
        if (JsonModel.Object(model, "content", out var content))
        {
            stack.Children.Add(CountLine(content, "count", "unit", null, "countTone"));
            AddRows(stack, content, row => InboxRow(row, command));
            AddExpander(stack, content, command);
            if (JsonModel.Object(content, "footer", out var footer))
            {
                var footerLine = new WrapPanel();
                AddText(footerLine, JsonModel.String(footer, "progress"));
                if (JsonModel.Object(footer, "clearing", out var clearing))
                {
                    AddLink(footerLine, clearing, command);
                }
                AddText(footerLine, JsonModel.String(footer, "leading"));
                AddText(footerLine, JsonModel.String(footer, "clock"));
                stack.Children.Add(footerLine);
            }
        }
        else
        {
            AddPlaceholder(stack, model);
        }

        return Frame(stack);
    }

    private static FrameworkElement Actions(JsonElement model, Action<DeckCommand> command)
    {
        if (JsonModel.Bool(model, "isCollapsed") && JsonModel.Object(model, "collapsed", out var collapsed))
        {
            return Collapsed(collapsed, command);
        }

        var stack = CardStack();
        stack.Children.Add(Header(model, null, "title", null, "pill"));
        if (!JsonModel.Object(model, "content", out var content))
        {
            AddPlaceholder(stack, model);
            return Frame(stack);
        }

        var variant = content.EnumerateObject().FirstOrDefault();
        if (variant.Value.ValueKind == JsonValueKind.Object)
        {
            if (variant.Name == "runs")
            {
                var headline = new WrapPanel();
                AddText(headline, JsonModel.String(variant.Value, "headline"), JsonModel.String(variant.Value, "headlineTone"));
                AddText(headline, JsonModel.String(variant.Value, "caption"));
                stack.Children.Add(headline);
                AddRows(stack, variant.Value, row => ActionRow(row, command));
                AddFooter(stack, variant.Value);
            }
            else
            {
                AddText(stack, JsonModel.String(variant.Value, "title"));
                AddText(stack, JsonModel.String(variant.Value, "detail"));
                if (JsonModel.Object(variant.Value, "link", out var link))
                {
                    AddLink(stack, link, command);
                }
                AddFooter(stack, variant.Value);
            }
        }

        return Frame(stack);
    }

    private static FrameworkElement WorkInFlight(JsonElement model, Action<DeckCommand> command)
    {
        if (JsonModel.Bool(model, "isCollapsed") && JsonModel.Object(model, "collapsed", out var collapsed))
        {
            return Collapsed(collapsed, command);
        }

        var stack = CardStack();
        stack.Children.Add(Header(model, null, "title", "timestamp", "pill"));
        stack.Children.Add(CountLine(model, "count", "unit", null));
        AddRows(stack, model, row => WorkRow(row, command));
        AddExpander(stack, model, command);
        AddFooter(stack, model);
        return Frame(stack);
    }

    private static FrameworkElement Project(JsonElement model, Action<DeckCommand> command)
    {
        if (JsonModel.Bool(model, "isCollapsed") && JsonModel.Object(model, "collapsed", out var collapsed))
        {
            return Collapsed(collapsed, command);
        }

        var stack = CardStack();
        stack.Children.Add(Header(model, "mark", "title", "timestamp"));
        if (JsonModel.Object(model, "header", out var header) && JsonModel.Command(header, "log") is { } log)
        {
            stack.Children.Add(CommandButton(JsonModel.String(header, "logHelp"), log, true, command));
        }
        if (JsonModel.Object(model, "hero", out var hero))
        {
            AddText(stack, JsonModel.String(hero, "text"), JsonModel.String(hero, "tone"), 20);
            AddText(stack, JsonModel.String(hero, "note"));
            stack.ToolTip = JsonModel.String(hero, "help");
        }
        if (JsonModel.Object(model, "meta", out var meta))
        {
            var metaLine = new WrapPanel();
            var branch = JsonModel.String(meta, "branch");
            if (JsonModel.Command(meta, "repository") is { } repository)
            {
                metaLine.Children.Add(CommandButton(branch, repository, true, command));
            }
            else
            {
                AddText(metaLine, branch);
            }
            AddText(metaLine, JsonModel.String(meta, "place"));
            AddText(metaLine, JsonModel.String(meta, "leading"));
            AddText(metaLine, JsonModel.String(meta, "trailing"));
            stack.Children.Add(metaLine);
        }
        AddChips(stack, model, "tools", command);
        AddChips(stack, model, "environments", command);
        if (JsonModel.Array(model, "actions", out var actions))
        {
            var buttons = new WrapPanel();
            foreach (var action in actions.EnumerateArray())
            {
                buttons.Children.Add(ActionButton(action, command));
            }
            stack.Children.Add(buttons);
        }

        return Frame(stack);
    }

    private static FrameworkElement Collapsed(JsonElement model, Action<DeckCommand> command)
    {
        var row = new DockPanel { LastChildFill = true };
        AddText(row, JsonModel.String(model, "mark"));
        AddText(row, JsonModel.String(model, "title"), null, 14);
        if (JsonModel.Array(model, "actions", out var actions))
        {
            foreach (var action in actions.EnumerateArray())
            {
                var button = ActionButton(action, command);
                DockPanel.SetDock(button, Dock.Right);
                row.Children.Add(button);
            }
        }
        AddText(row, JsonModel.String(model, "note"), JsonModel.String(model, "tone"));
        row.ToolTip = JsonModel.String(model, "help");
        return Frame(row);
    }

    private static FrameworkElement Header(
        JsonElement model,
        string? markName,
        string titleName,
        string? timeName,
        string? pillName = null)
    {
        var row = new DockPanel { Margin = new Thickness(0, 0, 0, 8) };
        if (timeName is not null)
        {
            var time = Text(JsonModel.String(model, timeName));
            DockPanel.SetDock(time, Dock.Right);
            row.Children.Add(time);
        }
        if (pillName is not null && JsonModel.Object(model, pillName, out var pill))
        {
            var pillText = Text(JsonModel.String(pill, "text"), JsonModel.String(pill, "tone"));
            DockPanel.SetDock(pillText, Dock.Right);
            row.Children.Add(pillText);
        }
        if (markName is not null)
        {
            AddText(row, JsonModel.String(model, markName));
        }
        AddText(row, JsonModel.String(model, titleName), null, 13);
        return row;
    }

    private static FrameworkElement CountLine(
        JsonElement model,
        string countName,
        string unitName,
        string? pillName,
        string? toneName = null)
    {
        var row = new WrapPanel { Margin = new Thickness(0, 0, 0, 6) };
        var count = JsonModel.String(model, countName) ?? JsonModel.NumberText(model, countName);
        AddText(row, count, toneName is null ? null : JsonModel.String(model, toneName), 22);
        AddText(row, JsonModel.String(model, unitName));
        if (pillName is not null && JsonModel.Object(model, pillName, out var pill))
        {
            AddText(row, JsonModel.String(pill, "text"), JsonModel.String(pill, "tone"));
        }
        return row;
    }

    private static FrameworkElement Shares(JsonElement shares)
    {
        var row = new WrapPanel();
        foreach (var share in shares.EnumerateArray())
        {
            AddText(row, JsonModel.NumberText(share, "count"), JsonModel.String(share, "tone"));
        }
        return row;
    }

    private static FrameworkElement ReviewRow(JsonElement row, Action<DeckCommand> command)
    {
        var content = new DockPanel();
        AddText(content, JsonModel.String(row, "key"), JsonModel.String(row, "tone"));
        AddText(content, JsonModel.String(row, "title"));
        AddText(content, JsonModel.String(row, "trailing"), JsonModel.String(row, "tone"));
        return ClickableRow(content, row, command);
    }

    private static FrameworkElement InboxRow(JsonElement row, Action<DeckCommand> command)
    {
        var content = new DockPanel();
        AddText(content, JsonModel.String(row, "chip"));
        AddText(content, JsonModel.String(row, "account"));
        AddText(content, JsonModel.String(row, "title"));
        AddText(content, JsonModel.String(row, "age"));
        return ClickableRow(content, row, command);
    }

    private static FrameworkElement ActionRow(JsonElement row, Action<DeckCommand> command)
    {
        var content = new DockPanel();
        AddText(content, JsonModel.String(row, "title"), JsonModel.String(row, "tone"));
        AddText(content, JsonModel.String(row, "trailing"));
        return ClickableRow(content, row, command);
    }

    private static FrameworkElement WorkRow(JsonElement row, Action<DeckCommand> command)
    {
        var content = new StackPanel();
        AddText(content, JsonModel.String(row, "title"), JsonModel.String(row, "tone"));
        AddText(content, JsonModel.String(row, "branch"));
        AddText(content, JsonModel.String(row, "summary"));
        return ClickableRow(content, row, command);
    }

    private static FrameworkElement ClickableRow(
        FrameworkElement content,
        JsonElement model,
        Action<DeckCommand> command)
    {
        content.ToolTip = JsonModel.String(model, "help");
        if (JsonModel.Command(model) is not { } rowCommand)
        {
            return content;
        }

        return CommandButton(content, rowCommand, true, command);
    }

    private static void AddRows(
        Panel stack,
        JsonElement parent,
        Func<JsonElement, FrameworkElement> create)
    {
        if (!JsonModel.Array(parent, "rows", out var rows))
        {
            return;
        }

        foreach (var row in rows.EnumerateArray())
        {
            stack.Children.Add(create(row));
        }
    }

    private static void AddExpander(Panel stack, JsonElement parent, Action<DeckCommand> command)
    {
        if (JsonModel.Object(parent, "expander", out var expander) && JsonModel.Command(expander) is { } expanderCommand)
        {
            stack.Children.Add(CommandButton(JsonModel.String(expander, "label"), expanderCommand, true, command));
        }
    }

    private static void AddFooter(Panel stack, JsonElement parent)
    {
        if (!JsonModel.Object(parent, "footer", out var footer))
        {
            return;
        }

        var line = new WrapPanel { Margin = new Thickness(0, 5, 0, 0) };
        AddText(line, JsonModel.String(footer, "leading"));
        AddText(line, JsonModel.String(footer, "trailing"));
        stack.Children.Add(line);
    }

    private static void AddPlaceholder(Panel stack, JsonElement model)
    {
        if (JsonModel.Object(model, "placeholder", out var placeholder))
        {
            AddText(stack, JsonModel.String(placeholder, "message"));
            AddText(stack, JsonModel.String(placeholder, "hint"));
        }
    }

    private static void AddChips(
        Panel stack,
        JsonElement model,
        string name,
        Action<DeckCommand> command)
    {
        if (!JsonModel.Array(model, name, out var chips))
        {
            return;
        }

        var row = new WrapPanel();
        foreach (var chip in chips.EnumerateArray())
        {
            if (JsonModel.Command(chip) is { } chipCommand)
            {
                row.Children.Add(CommandButton(
                    JsonModel.String(chip, "label"),
                    chipCommand,
                    !JsonModel.Bool(chip, "isDimmed"),
                    command));
            }
            else
            {
                AddText(row, JsonModel.String(chip, "label"));
            }
        }
        stack.Children.Add(row);
    }

    private static void AddLink(Panel stack, JsonElement link, Action<DeckCommand> command)
    {
        if (JsonModel.Command(link) is { } linkCommand)
        {
            stack.Children.Add(CommandButton(JsonModel.String(link, "title"), linkCommand, true, command));
        }
    }

    private static FrameworkElement ActionButton(JsonElement action, Action<DeckCommand> command)
    {
        if (JsonModel.Command(action) is not { } actionCommand)
        {
            return Text(JsonModel.String(action, "title"));
        }

        var enabled = !DeckEvent.TryProperty(action, "isEnabled", out var value) || value.GetBoolean();
        var button = CommandButton(JsonModel.String(action, "title"), actionCommand, enabled, command);
        button.ToolTip = JsonModel.String(action, "help");
        return button;
    }

    private static Button CommandButton(
        object? content,
        DeckCommand deckCommand,
        bool enabled,
        Action<DeckCommand> command)
    {
        var button = new Button
        {
            Content = content,
            IsEnabled = enabled,
            Margin = new Thickness(2),
            Padding = new Thickness(5, 2, 5, 2),
        };
        button.Click += (_, _) => command(deckCommand);
        return button;
    }

    private static Border Frame(FrameworkElement content)
    {
        return new Border
        {
            Background = Brushes.White,
            BorderBrush = Brushes.Gray,
            BorderThickness = new Thickness(1),
            Padding = new Thickness(8),
            Child = content,
        };
    }

    private static StackPanel CardStack()
    {
        return new StackPanel();
    }

    private static TextBlock Text(string? value, string? tone = null, double size = 12)
    {
        return new TextBlock
        {
            Text = value ?? "",
            Foreground = Tone(tone),
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = size,
            Margin = new Thickness(2),
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    private static void AddText(Panel panel, string? value, string? tone = null, double size = 12)
    {
        if (value is not null)
        {
            panel.Children.Add(Text(value, tone, size));
        }
    }

    private static Brush Tone(string? tone)
    {
        return tone switch
        {
            "good" => Brushes.DarkGreen,
            "attention" => Brushes.DarkGoldenrod,
            "alert" => Brushes.DarkRed,
            "personal" => Brushes.DarkViolet,
            _ => Brushes.Black,
        };
    }
}
