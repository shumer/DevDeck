using System;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed class RemoteSettingsWindow : Window
{
    private readonly DeckController controller;
    private readonly ListBox accounts = new() { Height = 120, Margin = new(0, 10, 0, 12) };
    private readonly ListBox cards = new() { Height = 110, Margin = new(0, 10, 0, 12) };
    private sealed record KindChoice(string ID, string Label) { public override string ToString() => Label; }
    private static string KindTitle(string value) => Text.L(value switch { "pullRequests" => "card.title.pulls", "inbox" => "card.title.inbox",
        "actions" => "card.title.actions", _ => "card.title.merges.gitlab" });
    private readonly ComboBox kind = new() { ItemsSource = new[] { "pullRequests", "inbox", "actions", "mergeRequests" }.Select(value => new KindChoice(value, KindTitle(value))).ToArray(), SelectedIndex = 0, Margin = new(0, 8, 0, 12) };
    private readonly ComboBox distribution = new() { Margin = new(0, 8, 0, 12) };
    private readonly TextBlock message = new() { TextWrapping = TextWrapping.Wrap, Margin = new(0, 10, 0, 0) };
    private readonly StackPanel panel = new() { Margin = new(24) };
    private bool busy;

    internal RemoteSettingsWindow(DeckController controller, bool live = true)
    {
        this.controller = controller;
        Title = "DevDeck · " + Text.L("windows.accounts"); Width = 540; Height = 680; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        panel.Children.Add(new TextBlock { Text = "GitHub / GitLab", FontSize = 24 });
        panel.Children.Add(new TextBlock { Text = Text.L("windows.tokenHint"), TextWrapping = TextWrapping.Wrap, Margin = new(0, 10, 0, 0) });
        panel.Children.Add(accounts);
        var buttons = new WrapPanel();
        buttons.Children.Add(Button(Text.L("windows.addAccount"), () => { new AccountWindow(controller, null, Reload).ShowDialog(); return Task.CompletedTask; }));
        buttons.Children.Add(Button(Text.L("windows.editSelected"), () => { if (accounts.SelectedIndex >= 0) new AccountWindow(controller, controller.Settings.AccountList[accounts.SelectedIndex], Reload).ShowDialog(); return Task.CompletedTask; }));
        buttons.Children.Add(Button(Text.L("windows.removeSelected"), RemoveAccount)); panel.Children.Add(buttons);
        panel.Children.Add(new TextBlock { Text = Text.L("windows.cardType"), Margin = new(0, 20, 0, 0) }); panel.Children.Add(kind);
        panel.Children.Add(new TextBlock { Text = Text.L("windows.distribution") }); panel.Children.Add(distribution);
        panel.Children.Add(Button(Text.L("windows.addRemoteCard"), AddCard));
        panel.Children.Add(cards); panel.Children.Add(Button(Text.L("windows.removeCard"), RemoveCard)); panel.Children.Add(message);
        Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Reload();
        if (live) Loaded += async (_, _) => { Reload(); try { distribution.ItemsSource = await WslDistributions.DiscoverAsync(); distribution.SelectedIndex = 0; } catch (Exception error) { message.Text = Text.Failure(error); } };
    }
    private Button Button(string title, Func<Task> action)
    {
        var button = new Button { Content = title, Padding = new(10, 6, 10, 6), Margin = new(0, 0, 8, 4) };
        button.Click += async (_, _) =>
        {
            if (busy) return; busy = true; panel.IsEnabled = false;
            try { await action(); Reload(); message.Text = Text.L("windows.saved"); } catch (Exception error) { message.Text = Text.Failure(error); }
            finally { busy = false; panel.IsEnabled = true; }
        };
        return button;
    }
    private void Reload()
    {
        accounts.ItemsSource = controller.Settings.AccountList.Select(account => account.Label + " · " + account.Provider + " · " + account.Endpoint + (account.Enabled ? "" : " · " + Text.L("windows.disabled"))).ToArray();
        cards.ItemsSource = controller.Settings.RemoteCardList.Select(card => card.Title + " · " + card.Distribution).ToArray();
    }
    private async Task AddCard()
    {
        var selectedKind = ((KindChoice)kind.SelectedItem).ID;
        var provider = selectedKind == "mergeRequests" ? "gitlab" : "github";
        var accountIDs = controller.Settings.AccountList.Where(account => account.Provider == provider && account.Enabled).Select(account => account.Id).ToArray();
        if (accountIDs.Length == 0) throw new InvalidOperationException(Text.L("windows.validationAccount"));
        var selectedDistribution = distribution.SelectedItem as string ?? throw new InvalidOperationException(Text.L("windows.chooseDistribution"));
        await controller.EnsureWorkerAsync(selectedDistribution);
        await controller.SetRemoteVisibleAsync(selectedKind, true);
        await controller.SaveSettingsAsync(current => current with { RemoteCards = current.RemoteCardList.Select(card =>
            card.Id == RemoteCardCatalog.Resolve(current, selectedKind)?.Id ? card with { Distribution = selectedDistribution } : card).ToArray() });
    }
    private async Task RemoveCard()
    {
        if (cards.SelectedIndex < 0) return;
        var card = controller.Settings.RemoteCardList[cards.SelectedIndex];
        if (RemoteCardCatalog.Resolve(controller.Settings, card.Kind)?.Id == card.Id) await controller.SetRemoteVisibleAsync(card.Kind, false);
        else await controller.SaveSettingsAsync(controller.Settings with { RemoteCards = controller.Settings.RemoteCardList.Where(item => item.Id != card.Id).ToArray() });
    }
    private async Task RemoveAccount()
    {
        if (accounts.SelectedIndex < 0) return;
        var account = controller.Settings.AccountList[accounts.SelectedIndex];
        if (!SettingsConfirmation.ForAccount(this,account)) return;
        await controller.SaveSettingsAsync(current => RemoteCardCatalog.RemoveAccount(current,account.Id));
        controller.Tokens.Write(account, null);
    }
}

internal sealed class AccountWindow : Window
{
    internal AccountWindow(DeckController controller, RemoteAccountSettings? original, Action saved, bool live = true)
    {
        Title = "DevDeck · " + (original is null ? Text.L("windows.addAccount") : Text.L("windows.editSelected")); Width = 520; SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterScreen; MaxHeight = SystemParameters.WorkArea.Height - 80;
        var panel = new StackPanel { Margin = new(24) };
        var provider = new ComboBox { ItemsSource = new[] { "github", "gitlab" }, SelectedItem = original?.Provider ?? "github", IsEnabled = original is null };
        var label = new TextBox { Text = original?.Label ?? "" };
        var endpoint = new TextBox { Text = original?.Endpoint ?? "https://api.github.com" };
        var organizations = new TextBox { Text = string.Join(", ", original?.Organizations ?? []) };
        var repositories = new TextBox { Text = string.Join(", ", original?.Repositories ?? []) };
        var token = new PasswordBox();
        var distribution = new ComboBox();
        var browser = new BrowserPicker(original?.Browser ?? "system",original?.BrowserProfile);
        var cancellation = new System.Threading.CancellationTokenSource();
        var enabled = new CheckBox { Content = Text.L("windows.enableAccount"), IsChecked = original?.Enabled ?? true, Margin = new(0, 12, 0, 12) };
        var reviews = new CheckBox { Content = Text.L("settings.notifications.column.review"), IsChecked = original?.NotifiesReviewRequests ?? true };
        var blocked = new CheckBox { Content = Text.L("settings.notifications.column.stuck"), IsChecked = original?.NotifiesBlocked ?? false };
        var runs = new CheckBox { Content = Text.L("settings.notifications.column.runs"), IsChecked = original?.NotifiesFailedRuns ?? false };
        reviews.IsEnabled = blocked.IsEnabled = runs.IsEnabled = controller.Settings.Notifications;
        var message = new TextBlock { TextWrapping = TextWrapping.Wrap, Margin = new(0, 10, 0, 0) };
        void Field(string text, UIElement input) { panel.Children.Add(new TextBlock { Text = text, Margin = new(0, 10, 0, 5) }); panel.Children.Add(input); }
        Field(Text.L("windows.provider"), provider); Field(Text.L("account.name"), label); Field(Text.L("windows.endpoint"), endpoint);
        Field(Text.L("windows.organizations"), organizations);
        Field(Text.L("windows.repositories"), repositories);
        Field(original is null ? Text.L("account.section.token") : Text.L("windows.replaceToken"), token); panel.Children.Add(enabled);
        Field(Text.L("windows.verifyDistribution"), distribution);
        Field(Text.L("account.openLinksIn"), browser.Picker);
        var profileRow=new StackPanel();profileRow.Children.Add(new TextBlock { Text=Text.L("windows.profile"),Margin=new(0,10,0,5) });profileRow.Children.Add(browser.Profile);
        profileRow.SetBinding(VisibilityProperty,new System.Windows.Data.Binding(nameof(Visibility)){Source=browser.Profile});panel.Children.Add(profileRow);
        panel.Children.Add(reviews); panel.Children.Add(blocked); panel.Children.Add(runs);
        if (live) Loaded += async (_, _) => { try { distribution.ItemsSource = await WslDistributions.DiscoverAsync(cancellation.Token); distribution.SelectedIndex = 0; } catch (Exception error) { message.Text = Text.Failure(error); } };
        provider.SelectionChanged += (_, _) => { if (original is null) endpoint.Text = (string)provider.SelectedItem == "github" ? "https://api.github.com" : "https://gitlab.com"; };
        var save = new Button { Content = Text.L("windows.saveAccount"), Padding = new(10, 6, 10, 6) }; panel.Children.Add(save); panel.Children.Add(message);
        save.Click += async (_, _) =>
        {
            save.IsEnabled = false;
            try
            {
                string[] Split(string value) => value.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
                var account = new RemoteAccountSettings(original?.Id ?? "account-" + Guid.NewGuid().ToString("N"), label.Text.Trim(), (string)provider.SelectedItem,
                    endpoint.Text.Trim().TrimEnd('/'), Split(organizations.Text), Split(repositories.Text), enabled.IsChecked == true, browser.BrowserID, browser.SelectedProfile,
                    reviews.IsChecked == true, blocked.IsChecked == true, runs.IsChecked == true);
                account.Validate();
                if (token.Password.Length > 0)
                {
                    message.Text = Text.L("windows.verifying");
                    await controller.VerifyTokenAsync(account, token.Password, distribution.SelectedItem as string ?? throw new InvalidOperationException(Text.L("windows.chooseDistribution")), cancellation.Token);
                    if (cancellation.IsCancellationRequested) return;
                    controller.Tokens.Write(account, token.Password);
                }
                else if (original is null || original.CredentialTarget != account.CredentialTarget)
                    throw new InvalidOperationException(Text.L("windows.validationToken"));
                var values = controller.Settings.AccountList.Where(item => item.Id != account.Id).Append(account).ToArray();
                await controller.SaveSettingsAsync(controller.Settings with { Accounts = values });
                if (original is not null && original.CredentialTarget != account.CredentialTarget) controller.Tokens.Write(original, null);
                token.Clear(); saved(); Close();
            }
            catch (Exception error) { message.Text = Text.Failure(error); }
            finally { save.IsEnabled = true; }
        };
        Closed += (_, _) => { cancellation.Cancel(); token.Clear(); };
        Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }
}
