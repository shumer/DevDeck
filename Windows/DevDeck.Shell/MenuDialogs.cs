using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace DevDeck.Shell;

public sealed class MenuDialogs : IMenuDialogs
{
    public bool Confirm(DeckMenuDialogModel model)
    {
        var window = Build(model, null, out _, out var accepted);
        _ = window.ShowDialog();
        return accepted();
    }

    public string? Prompt(DeckMenuPromptModel model)
    {
        var window = Build(model, model.Placeholder, out var field, out var accepted);
        window.Loaded += (_, _) => field?.Focus();
        _ = window.ShowDialog();
        return accepted() ? field?.Text : null;
    }

    public static Window Build(
        DeckMenuDialogModel model,
        string? placeholder,
        out TextBox? field,
        out Func<bool> accepted)
    {
        WindowsTheme.EnsureLoaded();
        var result = false;
        var window = new Window
        {
            Title = model.Title,
            Width = 420,
            SizeToContent = SizeToContent.Height,
            WindowStartupLocation = WindowStartupLocation.CenterScreen,
            ResizeMode = ResizeMode.NoResize,
            Background = WindowsTheme.CardBackground(false),
            Foreground = WindowsTheme.Brush("TextPrimary"),
            FontFamily = WindowsTheme.Sans,
            ShowInTaskbar = false,
        };
        var content = new StackPanel
        {
            Margin = new Thickness(24),
            Background = WindowsTheme.CardBackground(false),
        };
        content.Children.Add(new TextBlock
        {
            Text = model.Title,
            FontSize = 20,
            FontWeight = FontWeights.SemiBold,
            Foreground = WindowsTheme.Brush("TextPrimary"),
            TextWrapping = TextWrapping.Wrap,
        });
        content.Children.Add(new TextBlock
        {
            Text = model.Detail,
            Margin = new Thickness(0, 10, 0, 16),
            FontSize = 13,
            Foreground = WindowsTheme.Brush("TextSecondary"),
            TextWrapping = TextWrapping.Wrap,
        });
        field = null;
        if (placeholder is not null)
        {
            field = new TextBox
            {
                Style = WindowsTheme.Style("PromptTextBox"),
                Tag = placeholder,
                Margin = new Thickness(0, 0, 0, 16),
            };
            System.Windows.Automation.AutomationProperties.SetHelpText(field, placeholder);
            content.Children.Add(field);
        }

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        var cancel = DialogButton(model.Cancel);
        cancel.Click += (_, _) => window.Close();
        buttons.Children.Add(cancel);
        var confirm = DialogButton(model.Confirm);
        confirm.Margin = new Thickness(8, 0, 0, 0);
        confirm.Click += (_, _) =>
        {
            result = true;
            window.Close();
        };
        buttons.Children.Add(confirm);
        content.Children.Add(buttons);
        window.Content = content;
        accepted = () => result;
        return window;
    }

    private static Button DialogButton(string text)
    {
        return new Button
        {
            Content = text,
            Style = WindowsTheme.Style("FluentButton"),
            MinWidth = 88,
        };
    }
}
