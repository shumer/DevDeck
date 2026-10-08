using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Brush = System.Windows.Media.Brush;
using Button = System.Windows.Controls.Button;

namespace DevDeck.Shell;

public static class CardRenderer
{
    private static readonly Brush PrimaryText = Brush("#FFF4F4F5");
    private static readonly Brush SecondaryText = Brush("#FFA1A1AA");
    private static readonly Brush Surface = Brush("#F21C1C1F");
    private static readonly Brush Line = Brush("#FF3F3F46");

    public static FrameworkElement Create(CardModel card, Action<CardInteraction> interact)
    {
        var content = new StackPanel();
        content.Children.Add(Header(card));
        content.Children.Add(card.Kind == "list" ? ListBody(card, interact) : ProjectBody(card, interact));
        return new Border
        {
            Background = Surface,
            BorderBrush = Line,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(14),
            Padding = new Thickness(16, 14, 16, 14),
            Child = content,
            Effect = new System.Windows.Media.Effects.DropShadowEffect
            {
                BlurRadius = 22,
                ShadowDepth = 6,
                Opacity = 0.38,
                Color = Colors.Black,
            },
        };
    }

    private static FrameworkElement Header(CardModel card)
    {
        var grid = new Grid { Margin = new Thickness(0, 0, 0, 12) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var mark = Label(card.Mark, SecondaryText, 11, FontWeights.Bold);
        mark.Margin = new Thickness(0, 0, 9, 0);
        Grid.SetColumn(mark, 0);
        grid.Children.Add(mark);
        var title = Label(card.Title, PrimaryText, 13, FontWeights.SemiBold);
        title.TextTrimming = TextTrimming.CharacterEllipsis;
        Grid.SetColumn(title, 1);
        grid.Children.Add(title);
        var time = Label(card.TimeText, SecondaryText, 11, FontWeights.Normal);
        Grid.SetColumn(time, 2);
        grid.Children.Add(time);
        return grid;
    }

    private static FrameworkElement ListBody(CardModel card, Action<CardInteraction> interact)
    {
        var stack = new StackPanel();
        var hero = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 10) };
        hero.Children.Add(Label(card.Hero.Number ?? "", PrimaryText, 28, FontWeights.Bold));
        var unit = Label(card.Hero.Unit ?? "", SecondaryText, 13, FontWeights.Medium);
        unit.Margin = new Thickness(7, 9, 0, 0);
        hero.Children.Add(unit);
        if (card.Hero.Badge is { } badge)
        {
            var badgeText = Label(badge.Text, Tone(badge.Tone), 11, FontWeights.SemiBold);
            badgeText.Margin = new Thickness(12, 10, 0, 0);
            hero.Children.Add(badgeText);
        }
        stack.Children.Add(hero);
        foreach (var row in card.Rows)
        {
            stack.Children.Add(ListRow(card.Id, row, interact));
        }
        if (card.Expander is { } expander)
        {
            var button = TextButton(expander.Label, "quiet");
            button.HorizontalAlignment = HorizontalAlignment.Left;
            button.Click += (_, _) => interact(new CardInteraction(card.Id, "", !expander.IsExpanded));
            stack.Children.Add(button);
        }
        if (card.Footer is { } footer)
        {
            var footerText = Label(footer.Text, SecondaryText, 11, FontWeights.Normal);
            footerText.Margin = new Thickness(0, 8, 0, 0);
            stack.Children.Add(footerText);
        }
        return stack;
    }

    private static FrameworkElement ListRow(
        string cardId, CardRow row, Action<CardInteraction> interact)
    {
        var grid = new Grid { Margin = new Thickness(0, 2, 0, 2) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var leading = new StackPanel { Orientation = Orientation.Horizontal };
        if (row.Glyph is { } glyph)
        {
            leading.Children.Add(Label(Glyph(glyph), Tone(row.Tone), 11, FontWeights.Normal));
        }
        foreach (var chip in row.Chips)
        {
            var text = Label(chip.Text, Tone(chip.Tone), 10, FontWeights.SemiBold);
            text.Margin = new Thickness(0, 0, 6, 0);
            leading.Children.Add(text);
        }
        Grid.SetColumn(leading, 0);
        grid.Children.Add(leading);
        var title = Label(row.Title, PrimaryText, 12, FontWeights.Normal);
        title.TextTrimming = TextTrimming.CharacterEllipsis;
        Grid.SetColumn(title, 1);
        grid.Children.Add(title);
        var trailing = Label(row.Trailing, Tone(row.Tone), 11, FontWeights.Bold);
        trailing.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(trailing, 2);
        grid.Children.Add(trailing);
        var button = new Button
        {
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0),
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Content = grid,
            Cursor = System.Windows.Input.Cursors.Hand,
        };
        button.Click += (_, _) => interact(new CardInteraction(cardId, row.Action));
        return button;
    }

    private static FrameworkElement ProjectBody(CardModel card, Action<CardInteraction> interact)
    {
        var stack = new StackPanel();
        var state = Label(card.Hero.State ?? "", Tone(card.Hero.Tone ?? "quiet"), 20, FontWeights.SemiBold);
        state.Margin = new Thickness(0, 0, 0, 4);
        stack.Children.Add(state);
        if (card.Hero.Note is { } note)
        {
            stack.Children.Add(Label(note, SecondaryText, 11, FontWeights.Normal));
        }
        if (card.Branch is { } branch)
        {
            var branchText = Label(branch.Name, SecondaryText, 11, FontWeights.Normal);
            branchText.Margin = new Thickness(0, 7, 0, 0);
            stack.Children.Add(branchText);
        }
        foreach (var meta in card.Meta)
        {
            stack.Children.Add(Label(meta.Leading, SecondaryText, 11, FontWeights.Normal));
        }
        var chips = new WrapPanel { Margin = new Thickness(0, 9, 0, 0) };
        foreach (var chip in card.Chips)
        {
            var button = TextButton(chip.Label, chip.Tone);
            button.IsEnabled = chip.IsEnabled;
            button.Margin = new Thickness(0, 0, 7, 0);
            button.Click += (_, _) => interact(new CardInteraction(card.Id, chip.Action));
            chips.Children.Add(button);
        }
        stack.Children.Add(chips);
        var actions = new WrapPanel { Margin = new Thickness(0, 10, 0, 0) };
        foreach (var action in card.Actions)
        {
            var label = string.Join(" ", new[] { Glyph(action.Glyph), action.Label }.Where(value => value.Length > 0));
            var button = TextButton(label, action.Role == "primary" ? "accent" : "quiet");
            button.IsEnabled = action.IsEnabled;
            button.Opacity = action.IsBusy ? 0.65 : 1;
            button.Margin = new Thickness(0, 0, 7, 0);
            button.Click += (_, _) => interact(new CardInteraction(card.Id, action.Id));
            actions.Children.Add(button);
        }
        stack.Children.Add(actions);
        return stack;
    }

    private static Button TextButton(string text, string tone)
    {
        return new Button
        {
            Content = text,
            Foreground = Tone(tone),
            Background = Brush("#FF2A2A2E"),
            BorderBrush = Line,
            BorderThickness = new Thickness(1),
            Padding = new Thickness(9, 5, 9, 5),
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = 11,
            Cursor = System.Windows.Input.Cursors.Hand,
        };
    }

    private static TextBlock Label(string text, Brush foreground, double size, FontWeight weight)
    {
        return new TextBlock
        {
            Text = text,
            Foreground = foreground,
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = size,
            FontWeight = weight,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    private static Brush Tone(string tone) => tone switch
    {
        "good" => Brush("#FF62D49B"),
        "alert" => Brush("#FFF0B85A"),
        "bad" => Brush("#FFF07070"),
        "accent" => Brush("#FF71A7FF"),
        "info" => Brush("#FF71C7EC"),
        _ => SecondaryText,
    };

    private static string Glyph(string glyph) => glyph switch
    {
        "start" => "▶",
        "stop" => "⏻",
        "restart" => "↻",
        "folder" => "▱",
        "terminal" => ">_",
        "log" => "≡",
        "phone" => "▣",
        "open" => "↗",
        "review" => "◉",
        "expand" => "⌄",
        "collapse" => "⌃",
        "branch" => "⑂",
        _ => "",
    };

    private static Brush Brush(string color) => new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
}
