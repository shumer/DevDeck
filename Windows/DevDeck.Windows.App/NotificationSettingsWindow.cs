using System;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed class NotificationSettingsWindow : Window
{
    internal NotificationSettingsWindow(DeckController controller)
    {
        Title = "DevDeck · " + Text.L("settings.notifications.title"); Width = 720; SizeToContent = SizeToContent.Height;
        MaxHeight = SystemParameters.WorkArea.Height - 64; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Content = new ScrollViewer { Content = CreateContent(controller), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }
    internal static StackPanel CreateContent(DeckController controller)
    {
        var panel = new StackPanel { Margin = new(24) };
        panel.Children.Add(new TextBlock { Text = Text.L("settings.notifications.title"), FontSize = 24, FontWeight = FontWeights.SemiBold });
        void Note(string key) => panel.Children.Add(new TextBlock { Text = Text.L(key), TextWrapping = TextWrapping.Wrap,
            Foreground = Brushes.DimGray, Margin = new(0, 10, 0, 12) });
        Note("settings.notifications.subtitle");
        var master = new CheckBox { Content = Text.L("settings.notifications.allow"), IsChecked = controller.Settings.Notifications, Margin = new(0, 0, 0, 12) };
        panel.Children.Add(master);
        var preferences = new StackPanel { IsEnabled = controller.Settings.Notifications }; panel.Children.Add(preferences);
        master.Click += async (_, _) => await controller.RunMenuAsync(() => {
            controller.SaveNotificationPreferences(controller.Settings with { Notifications = master.IsChecked == true });
            preferences.IsEnabled = controller.Settings.Notifications; return Task.CompletedTask;
        });
        Grid Row(string title, params UIElement[] columns) {
            var row = new Grid { Margin = new(0, 0, 0, 9) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.Children.Add(new TextBlock { Text = title, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center, Margin = new(0, 0, 12, 0) });
            for (var index = 0; index < columns.Length; index++) {
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(128) });
                Grid.SetColumn(columns[index], index + 1); row.Children.Add(columns[index]);
            }
            preferences.Children.Add(row); return row;
        }
        void Header(string title, params string[] keys) => Row(Text.L(title), keys.Select(key => (UIElement)new TextBlock { Text = Text.L(key),
            TextWrapping = TextWrapping.Wrap, FontWeight = FontWeights.SemiBold, TextAlignment = TextAlignment.Center }).ToArray());
        CheckBox Switch(bool value, string name, Action<bool> save) {
            var toggle = new CheckBox { IsChecked = value, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, ToolTip = name };
            System.Windows.Automation.AutomationProperties.SetName(toggle, name);
            toggle.Click += async (_, _) => await controller.RunMenuAsync(() => { save(toggle.IsChecked == true); return Task.CompletedTask; });
            return toggle;
        }
        Header("settings.notifications.projects", "settings.notifications.column.down", "settings.notifications.column.startFailed");
        foreach (var card in controller.Settings.Cards) Row(card.Title,
            Switch(card.NotifiesWhenDown, card.Title + " · " + Text.L("settings.notifications.column.down"), enabled => controller.SaveNotificationPreferences(controller.Settings with {
                Cards = controller.Settings.Cards.Select(value => value.Project.Id == card.Project.Id ? value with { NotifiesWhenDown = enabled } : value).ToArray() })),
            Switch(card.NotifiesStartFailed, card.Title + " · " + Text.L("settings.notifications.column.startFailed"), enabled => controller.SaveNotificationPreferences(controller.Settings with {
                Cards = controller.Settings.Cards.Select(value => value.Project.Id == card.Project.Id ? value with { NotifiesStartFailed = enabled } : value).ToArray() })));
        Header("settings.notifications.accounts", "settings.notifications.column.review", "settings.notifications.column.stuck", "settings.notifications.column.runs");
        foreach (var account in controller.Settings.AccountList) {
            var unavailableRuns = new TextBlock { Text = "-", HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center, Focusable = false, IsHitTestVisible = false };
            System.Windows.Automation.AutomationProperties.SetName(unavailableRuns, Text.L("windows.accountRunsNotApplicable", account.Label));
            Row(account.Label,
            Switch(account.NotifiesReviewRequests, account.Label + " · " + Text.L("settings.notifications.column.review"), enabled => controller.SaveNotificationPreferences(controller.Settings with {
                Accounts = controller.Settings.AccountList.Select(value => value.Id == account.Id ? value with { NotifiesReviewRequests = enabled } : value).ToArray() })),
            Switch(account.NotifiesBlocked, account.Label + " · " + Text.L("settings.notifications.column.stuck"), enabled => controller.SaveNotificationPreferences(controller.Settings with {
                Accounts = controller.Settings.AccountList.Select(value => value.Id == account.Id ? value with { NotifiesBlocked = enabled } : value).ToArray() })),
            RemoteAccountApplicability.HasFailedRunPreference(account.Provider) ? Switch(account.NotifiesFailedRuns, account.Label + " · " + Text.L("settings.notifications.column.runs"), enabled => controller.SaveNotificationPreferences(controller.Settings with {
                Accounts = controller.Settings.AccountList.Select(value => value.Id == account.Id ? value with { NotifiesFailedRuns = enabled } : value).ToArray() }))
                : unavailableRuns);
        }
        var test = new Button { Content = Text.L("settings.notifications.test.button"), Padding = new(10, 6, 10, 6), HorizontalAlignment = HorizontalAlignment.Left };
        test.Click += (_, _) => controller.TestNotification(); preferences.Children.Add(test);
        Note("settings.notifications.down.footnote"); Note("settings.notifications.runs.footnote"); Note("settings.notifications.footnote");
        return panel;
    }
}
