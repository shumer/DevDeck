using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Text.Json;

namespace DevDeck.Shell;

public interface IMenuDialogs
{
    bool Confirm(DeckMenuDialogModel model);
    string? Prompt(DeckMenuPromptModel model);
}

public sealed class MenuActionRunner
{
    private readonly IMenuDialogs dialogs;
    private readonly Action<DeckCommand> send;

    public MenuActionRunner(IMenuDialogs dialogs, Action<DeckCommand> send)
    {
        this.dialogs = dialogs;
        this.send = send;
    }

    public void Invoke(DeckMenuItemModel item, bool useAlternate)
    {
        var command = useAlternate && item.Alternate is { } alternate
            ? alternate.Command
            : item.Command;
        if (command is not { } value)
        {
            return;
        }
        if (!useAlternate && item.Confirmation is { } confirmation && !dialogs.Confirm(confirmation))
        {
            return;
        }
        if (!useAlternate && item.Prompt is { } prompt)
        {
            var name = dialogs.Prompt(prompt);
            if (name is null)
            {
                return;
            }
            value = DeckCommandPrompt.WithName(value, name);
        }
        send(value);
    }
}

public sealed class MenuPresenter
{
    private readonly ContextMenu menu = new();
    private readonly MenuActionRunner actions;
    private IReadOnlyList<DeckMenuEntryModel> entries = [];
    private bool alternateIsDown;

    public MenuPresenter(Action<DeckCommand> command, IMenuDialogs? dialogs = null)
    {
        WindowsTheme.EnsureLoaded();
        actions = new MenuActionRunner(dialogs ?? new MenuDialogs(), command);
        menu.Style = WindowsTheme.Style("DeckContextMenu");
        menu.Placement = PlacementMode.MousePoint;
        menu.FontFamily = WindowsTheme.Sans;
        menu.FontSize = 13;
        menu.Opened += (_, _) => SetAlternate(Keyboard.Modifiers.HasFlag(ModifierKeys.Alt));
        menu.PreviewKeyDown += (_, eventArguments) =>
        {
            if (eventArguments.Key is Key.LeftAlt or Key.RightAlt or Key.System)
            {
                SetAlternate(true);
            }
        };
        menu.PreviewKeyUp += (_, _) =>
        {
            SetAlternate(Keyboard.Modifiers.HasFlag(ModifierKeys.Alt));
        };
    }

    public ContextMenu View => menu;
    public IReadOnlyList<DeckMenuEntryModel> Entries => entries;

    public void Update(JsonElement menuValue)
    {
        Update(DeckMenuEntryModel.ParseList(menuValue));
    }

    public void Update(IReadOnlyList<DeckMenuEntryModel> newEntries)
    {
        entries = newEntries;
        var wasOpen = menu.IsOpen;
        Populate(menu.Items, entries);
        if (wasOpen)
        {
            menu.UpdateLayout();
        }
    }

    public void Open()
    {
        menu.IsOpen = true;
    }

    private void Populate(ItemCollection target, IReadOnlyList<DeckMenuEntryModel> source)
    {
        target.Clear();
        foreach (var entry in source)
        {
            switch (entry.Kind)
            {
                case DeckMenuEntryKind.Separator:
                    target.Add(new Separator
                    {
                        Style = WindowsTheme.Style("DeckMenuSeparator"),
                        Margin = new Thickness(8, 4, 8, 4),
                    });
                    break;
                case DeckMenuEntryKind.Header:
                    target.Add(Header(entry.Header ?? ""));
                    break;
                case DeckMenuEntryKind.Item:
                    target.Add(Item(entry.Item ?? throw new InvalidOperationException()));
                    break;
                case DeckMenuEntryKind.Submenu:
                    var submenu = Item(entry.Item ?? throw new InvalidOperationException());
                    Populate(submenu.Items, entry.Children);
                    target.Add(submenu);
                    break;
            }
        }
    }

    private static MenuItem Header(string title)
    {
        return new MenuItem
        {
            Header = new TextBlock
            {
                Text = title,
                FontFamily = WindowsTheme.Sans,
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                Foreground = WindowsTheme.Brush("TextSecondary"),
                Margin = new Thickness(2, 5, 2, 2),
            },
            IsEnabled = false,
            Style = WindowsTheme.Style("DeckMenuItem"),
        };
    }

    private MenuItem Item(DeckMenuItemModel model)
    {
        var item = new MenuItem
        {
            Header = ItemContent(model, false),
            IsEnabled = model.IsEnabled,
            IsCheckable = model.IsOn,
            IsChecked = model.IsOn,
            InputGestureText = model.KeyEquivalent,
            ToolTip = model.Help,
            Foreground = WindowsTheme.Brush("TextPrimary"),
            Padding = new Thickness(model.IsIndented ? 22 : 8, 4, 8, 4),
            Tag = model,
            Style = WindowsTheme.Style("DeckMenuItem"),
        };
        AutomationProperties.SetName(item, model.Title);
        item.Click += (_, _) => actions.Invoke(model, alternateIsDown);
        return item;
    }

    private static Grid ItemContent(DeckMenuItemModel model, bool alternate)
    {
        var grid = new Grid { MinWidth = 270 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var image = MenuImage(model.Image);
        image.Margin = new Thickness(0, 1, 6, 0);
        grid.Children.Add(image);

        var words = new StackPanel();
        words.Children.Add(new TextBlock
        {
            Text = alternate && model.Alternate is { } alternateModel ? alternateModel.Title : model.Title,
            FontFamily = WindowsTheme.Sans,
            FontSize = 13,
            Foreground = WindowsTheme.Brush("TextPrimary"),
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        if (!alternate && model.Subtitle is { Length: > 0 } subtitle)
        {
            words.Children.Add(new TextBlock
            {
                Text = subtitle,
                FontFamily = WindowsTheme.Sans,
                FontSize = 11,
                Foreground = WindowsTheme.Brush("TextSecondary"),
                TextTrimming = TextTrimming.CharacterEllipsis,
            });
        }
        Grid.SetColumn(words, 1);
        grid.Children.Add(words);

        if (!alternate && model.Badge is { Length: > 0 } badge)
        {
            var badgeText = new TextBlock
            {
                Text = badge,
                FontFamily = WindowsTheme.Sans,
                FontSize = 11,
                Foreground = WindowsTheme.Brush("TextSecondary"),
                Margin = new Thickness(12, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(badgeText, 2);
            grid.Children.Add(badgeText);
        }
        return grid;
    }

    private static FrameworkElement MenuImage(DeckMenuImageModel? image)
    {
        if (image is null)
        {
            return new FrameworkElement { Width = 14, Height = 14 };
        }
        if (image.Kind == "attention")
        {
            return BrandMarks.Create(image.Mark, 14);
        }
        if (image.Kind == "more")
        {
            return new TextBlock
            {
                Text = "\uE712",
                FontFamily = new FontFamily("Segoe Fluent Icons"),
                FontSize = 13,
                Foreground = WindowsTheme.Brush("TextSecondary"),
            };
        }
        return new Ellipse
        {
            Width = 10,
            Height = 10,
            Stroke = WindowsTheme.Brush("TextSecondary"),
            StrokeThickness = 1.5,
        };
    }

    private void SetAlternate(bool value)
    {
        if (alternateIsDown == value)
        {
            return;
        }
        alternateIsDown = value;
        UpdateHeaders(menu.Items);
    }

    private void UpdateHeaders(ItemCollection items)
    {
        foreach (var child in items.OfType<MenuItem>())
        {
            if (child.Tag is DeckMenuItemModel model && model.Alternate is not null)
            {
                child.Header = ItemContent(model, alternateIsDown);
                child.IsEnabled = alternateIsDown ? model.Alternate.IsEnabled : model.IsEnabled;
                AutomationProperties.SetName(child, alternateIsDown ? model.Alternate.Title : model.Title);
            }
            UpdateHeaders(child.Items);
        }
    }
}
