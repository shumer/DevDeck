using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed record SettingsRemovalRequest(string Title, string Detail);

/// A single removal path for form buttons and the sidebar. Return and Escape both cancel.
internal static class SettingsConfirmation
{
    internal static bool ForAccount(DependencyObject owner, RemoteAccountSettings account, Func<SettingsRemovalRequest,bool>? confirm = null) =>
        Confirm(owner, new(Text.L("settings.remove.account.title", account.Label), Text.L("windows.removeAccountDetail")), confirm);

    internal static bool ForProject(DependencyObject owner, CardSettings card, Func<SettingsRemovalRequest,bool>? confirm = null) =>
        Confirm(owner, new(Text.L("settings.remove.account.title", card.Title), Text.L("settings.remove.project.detail." + card.Project.Kind)), confirm);

    private static bool Confirm(DependencyObject owner, SettingsRemovalRequest request, Func<SettingsRemovalRequest,bool>? confirm)
    {
        if (confirm is not null) return confirm(request);
        var dialog = CreateDialog(request, Window.GetWindow(owner));
        return dialog.ShowDialog() == true;
    }

    internal static Window CreateDialog(SettingsRemovalRequest request, Window? owner = null)
    {
        var dialog = new Window {
            Title = Text.L("settings.window.title"), Width = 460, SizeToContent = SizeToContent.Height,
            ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false,
            WindowStartupLocation = owner is null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.CenterOwner,
            Background = Brushes.White, FontFamily = new("Segoe UI"), FontSize = 13
        };
        if (owner is not null) dialog.Owner = owner;
        var panel = new StackPanel { Margin = new(24) };
        panel.Children.Add(new TextBlock { Text = request.Title, FontSize = 19, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(new TextBlock { Text = request.Detail, Margin = new(0,12,0,20), TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DimGray });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var remove = new Button { Content = Text.L("button.remove"), Padding = new(16,7,16,7), Margin = new(0,0,8,0), Foreground = Brushes.Firebrick };
        var cancel = new Button { Content = Text.L("button.cancel"), Padding = new(16,7,16,7), IsDefault = true, IsCancel = true };
        System.Windows.Automation.AutomationProperties.SetName(remove, Text.L("button.remove"));
        System.Windows.Automation.AutomationProperties.SetName(cancel, Text.L("button.cancel"));
        remove.Click += (_, _) => dialog.DialogResult = true;
        cancel.Click += (_, _) => dialog.DialogResult = false;
        dialog.Loaded += (_, _) => cancel.Focus();
        buttons.Children.Add(remove); buttons.Children.Add(cancel); panel.Children.Add(buttons); dialog.Content = panel;
        return dialog;
    }
}
