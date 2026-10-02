using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed class AccountSettingsForm : SettingsForm
{
    private RemoteAccountSettings? original;
    private readonly string id;
    private readonly Action<string> changed;
    private readonly TextBox label, endpoint, organizations, repositories;
    private readonly ComboBox provider, distribution;
    private readonly BrowserPicker browser;
    private readonly PasswordBox token = new();
    private readonly CheckBox enabled, reviews, blocked, runs;
    private readonly Func<SettingsRemovalRequest,bool>? confirmation;
    private readonly Action<RemoteAccountSettings>? clearCredential;
    private readonly Func<Task>? verifyToken;
    private readonly Action<string>? credentialChanged;
    private readonly Func<RemoteAccountSettings,string,string,CancellationToken,Task>? verifyCredential;
    private readonly Action<RemoteAccountSettings,string?>? credentialWriter;
    private readonly Func<CancellationToken,Task<string[]>>? discoverDistributions;
    private readonly Action<string,string?,string>? browserOpener;
    private readonly StackPanel scopeFields, gitlabInstance, advanced;
    private readonly FrameworkElement endpointRow;
    private readonly TextBlock endpointCaption, providerHelp;
    private readonly Dictionary<string,string> endpointDrafts = new(StringComparer.Ordinal);
    private string presentedProvider;
    private long organizationRevision, repositoryRevision, savedOrganizationRevision, savedRepositoryRevision;
    internal string TokenDraft { get => token.Password; set => token.Password = value; }
    internal AccountSettingsForm(DeckController controller, RemoteAccountSettings? original, bool live, Action<string> changed, string newProvider = "github", Func<SettingsRemovalRequest,bool>? confirmation = null, Action<RemoteAccountSettings>? clearCredential = null, Func<Task>? verifyToken = null,
        Action<string>? credentialChanged = null, Func<RemoteAccountSettings,string,string,CancellationToken,Task>? verifyCredential = null,
        Action<RemoteAccountSettings,string?>? credentialWriter = null,
        Func<CancellationToken,Task<string[]>>? discoverDistributions = null,
        Action<string,string?,string>? browserOpener = null,
        Func<string,string?,BrowserPicker>? browserPickerFactory = null) : base(controller, live)
    {
        this.original = original; id = original?.Id ?? "account-" + Guid.NewGuid().ToString("N"); this.changed = changed; this.confirmation = confirmation; this.clearCredential = clearCredential; this.verifyToken = verifyToken; Autosaves = original is not null;
        this.credentialChanged = credentialChanged; this.verifyCredential = verifyCredential; this.credentialWriter = credentialWriter;
        this.discoverDistributions = discoverDistributions; this.browserOpener = browserOpener;
        var panel = Page(original?.Label ?? Text.L("windows.newAccount")); if (original is not null) Note(panel, Text.L("windows.autosave"));
        enabled = Toggle(Text.L("windows.enableAccount"), original?.Enabled ?? true); panel.Children.Add(enabled);
        provider = new() { ItemsSource = new[] { "github", "gitlab" }, SelectedItem = original?.Provider ?? newProvider, IsEnabled = original is null };
        label = new() { Text = original?.Label ?? "" }; endpoint = new() { Text = original?.Endpoint ?? (newProvider == "gitlab" ? "https://gitlab.com" : "https://api.github.com") };
        organizations = new() { Text = string.Join(", ", original?.Organizations ?? []) }; repositories = new() { Text = string.Join(", ", original?.Repositories ?? []) };
        browser = browserPickerFactory?.Invoke(original?.Browser ?? "system", original?.BrowserProfile)
            ?? new(original?.Browser ?? "system",original?.BrowserProfile);
        presentedProvider = original?.Provider ?? newProvider;
        endpointDrafts["github"] = "https://api.github.com"; endpointDrafts["gitlab"] = "https://gitlab.com";
        endpointDrafts[presentedProvider] = endpoint.Text;
        distribution = new() { ItemsSource = controller.Settings.Workers.Select(worker => worker.Distribution).ToArray(), SelectedIndex = 0 };
        Field(panel, Text.L("windows.provider"), provider); Field(panel, Text.L("account.name"), label);
        gitlabInstance = new(); Section(gitlabInstance, Text.L("account.section.instance")); panel.Children.Add(gitlabInstance);
        scopeFields = new(); Field(scopeFields, Text.L("windows.organizations"), organizations); Field(scopeFields, Text.L("windows.repositories"), repositories); panel.Children.Add(scopeFields);
        Section(panel, Text.L("account.section.token")); providerHelp = Note(panel, ""); Note(panel, Text.L("windows.accountTokenStorage"));
        if (original is not null) Note(panel, Text.L("windows.replaceToken"));
        Field(panel, Text.L("token.field"), token); Field(panel, Text.L("windows.verifyDistribution"), distribution);
        panel.Children.Add(Button(Text.L("windows.verifySaveToken"), VerifyTokenAsync));
        token.KeyDown += async (_, args) => {
            if (args.Key != Key.Return || Keyboard.Modifiers != ModifierKeys.None) return;
            args.Handled = true; await VerifyTokenAsync();
        };
        Field(panel, Text.L("account.openLinksIn"), browser.Picker);
        var profileRow = new StackPanel(); Field(profileRow,Text.L("windows.profile"),browser.Profile);
        profileRow.SetBinding(VisibilityProperty,new System.Windows.Data.Binding(nameof(Visibility)){Source=browser.Profile}); panel.Children.Add(profileRow);
        panel.Children.Add(Button(Text.L("button.test"), () => ExecuteAsync(() => {
            if (Live) { var draft = Draft(); (browserOpener ?? ((browserID,profile,address) => BrowserLaunch.Open(browserID,profile,address)))(draft.Browser,draft.BrowserProfile,RemotePresentation.Dashboard(draft,draft.Provider == "gitlab" ? "mergeRequests" : "pullRequests")); }
            return Task.CompletedTask;
        })));
        advanced = new(); Field(advanced, Text.L("windows.endpoint"), endpoint);
        endpointRow = (FrameworkElement)advanced.Children[0];
        endpointCaption = ((Grid)((Border)endpointRow).Child).Children.OfType<TextBlock>().Single();
        reviews = Toggle(Text.L("settings.notifications.column.review"), original?.NotifiesReviewRequests ?? true);
        blocked = Toggle(Text.L("settings.notifications.column.stuck"), original?.NotifiesBlocked ?? false); runs = Toggle(Text.L("settings.notifications.column.runs"), original?.NotifiesFailedRuns ?? false);
        reviews.IsEnabled = blocked.IsEnabled = runs.IsEnabled = controller.Settings.Notifications;
        advanced.Children.Add(reviews); advanced.Children.Add(blocked); advanced.Children.Add(runs);
        panel.Children.Add(new Expander { Header = Text.L("windows.advanced"), Content = advanced, Margin = new(0, 24, 0, 12) });
        if (original is not null) panel.Children.Add(Button(Text.L("windows.removeSelected"), RemoveAsync));
        panel.Children.Add(Message); Content = panel;
        ApplyProviderPresentation();
        provider.SelectionChanged += (_, _) => {
            if (this.original is not null) { provider.SelectedItem = this.original.Provider; return; }
            var next = provider.SelectedItem as string;
            if (next is not ("github" or "gitlab") || next == presentedProvider) return;
            endpointDrafts[presentedProvider] = endpoint.Text;
            endpoint.Text = endpointDrafts[next]; presentedProvider = next; ApplyProviderPresentation();
        };
        foreach (var field in new[] { label, endpoint, organizations, repositories }) Watch(field);
        organizations.TextChanged += (_, _) => organizationRevision++;
        repositories.TextChanged += (_, _) => repositoryRevision++;
        browser.ValueChanged += (_,_) => Changed(); foreach (var field in new[] { enabled, reviews, blocked, runs }) Watch(field);
        Loaded += async (_, _) => await DiscoverDistributionsAsync();
    }
    private void ApplyProviderPresentation()
    {
        var github = RemoteAccountApplicability.HasGitHubScopes(presentedProvider);
        scopeFields.Visibility = github ? Visibility.Visible : Visibility.Collapsed;
        gitlabInstance.Visibility = github ? Visibility.Collapsed : Visibility.Visible;
        runs.Visibility = RemoteAccountApplicability.HasFailedRunPreference(presentedProvider) ? Visibility.Visible : Visibility.Collapsed;
        endpointCaption.Text = Text.L(github ? "windows.endpoint" : "account.gitlab.address");
        System.Windows.Automation.AutomationProperties.SetName(endpoint, endpointCaption.Text);
        if (endpointRow.Parent is Panel parent) parent.Children.Remove(endpointRow);
        if (github) advanced.Children.Insert(0, endpointRow); else gitlabInstance.Children.Add(endpointRow);
        providerHelp.Text = Text.L(github ? "account.github.token.help" : "account.gitlab.token.help");
        token.ToolTip = github ? "github_pat_… / ghp_…" : "glpat-…";
        System.Windows.Automation.AutomationProperties.SetHelpText(token, providerHelp.Text);
    }
    private async Task DiscoverDistributionsAsync()
    {
        if (discoverDistributions is null) { await DiscoverAsync(distribution); return; }
        if (!Live) return;
        try {
            var names = await discoverDistributions(Lifetime.Token);
            if (Lifetime.IsCancellationRequested) return;
            var selected = distribution.SelectedItem as string;
            distribution.ItemsSource = names;
            distribution.SelectedItem = selected is not null && names.Contains(selected, StringComparer.Ordinal) ? selected : names.FirstOrDefault();
        } catch (OperationCanceledException) { } catch (Exception error) { if (!IsDisposed) Message.Text = Text.Failure(error); }
    }
    internal Task VerifyTokenAsync() => IsEnabled ? ExecuteAsync(verifyToken ?? SaveTokenAsync) : Task.CompletedTask;
    internal async Task RemoveAsync()
    {
        if (original is null || !IsEnabled || (!Live && confirmation is null)) return;
        await FlushAsync();
        var account = original;
        if (account is null || !IsEnabled || !SettingsConfirmation.ForAccount(this, account, confirmation)) return;
        if (!Live) return;
        await ExecuteAsync(async () => {
            await Controller.SaveSettingsAsync(current => RemoteCardCatalog.RemoveAccount(current,id));
            Autosaves = false; original = null; token.Clear();
            if (clearCredential is not null) clearCredential(account); else Controller.Tokens.Write(account, null);
            changed("");
        });
    }
    private RemoteAccountSettings Draft()
    {
        string[] Split(string value) => value.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        var kind = (string)provider.SelectedItem;
        var github = RemoteAccountApplicability.HasGitHubScopes(kind);
        var account = new RemoteAccountSettings(id, label.Text.Trim(), kind, endpoint.Text.Trim().TrimEnd('/'),
            !github || original is not null && organizationRevision == savedOrganizationRevision ? original?.Organizations.ToArray() ?? [] : Split(organizations.Text),
            !github || original is not null && repositoryRevision == savedRepositoryRevision ? original?.Repositories.ToArray() ?? [] : Split(repositories.Text),
            enabled.IsChecked == true, browser.BrowserID, browser.SelectedProfile, reviews.IsChecked == true, blocked.IsChecked == true,
            RemoteAccountApplicability.HasFailedRunPreference(kind) ? runs.IsChecked == true : original?.NotifiesFailedRuns ?? false);
        account.Validate(); return account;
    }
    protected override async Task SaveMetadataAsync()
    {
        if (!Live || original is null) return;
        var account = Draft();
        if (account.CredentialTarget != original.CredentialTarget) throw new InvalidOperationException(Text.L("windows.validationToken"));
        await PersistAsync(account, organizationRevision, repositoryRevision);
    }
    private async Task PersistAsync(RemoteAccountSettings account, long capturedOrganizationRevision, long capturedRepositoryRevision, bool credentialSaved = false)
    {
        await Controller.SaveSettingsAsync(current => current with { Accounts = current.AccountList.Any(item => item.Id == id) ? current.AccountList.Select(item => item.Id == id ? account : item).ToArray() : current.AccountList.Append(account).ToArray() });
        original = account; Autosaves = true; provider.IsEnabled = false;
        savedOrganizationRevision = capturedOrganizationRevision; savedRepositoryRevision = capturedRepositoryRevision;
        if (credentialSaved) credentialChanged?.Invoke(id);
        changed(id);
    }
    private async Task SaveTokenAsync()
    {
        if (!Live) return;
        var account = Draft(); var value = token.Password;
        var capturedOrganizationRevision = organizationRevision; var capturedRepositoryRevision = repositoryRevision;
        if (value.Length == 0) throw new InvalidOperationException(Text.L("windows.validationToken"));
        Message.Text = Text.L("windows.verifying");
        await (verifyCredential ?? Controller.VerifyTokenAsync)(account, value, distribution.SelectedItem as string ?? throw new InvalidOperationException(Text.L("windows.chooseDistribution")), Lifetime.Token);
        Lifetime.Token.ThrowIfCancellationRequested();
        var previous = original;
        var write = credentialWriter ?? Controller.Tokens.Write;
        write(account, value);
        await PersistAsync(account, capturedOrganizationRevision, capturedRepositoryRevision, credentialSaved: true);
        if (previous is not null && previous.CredentialTarget != account.CredentialTarget) write(previous, null);
        token.Clear(); Message.Text = Text.L("token.works"); Message.Foreground = System.Windows.Media.Brushes.SeaGreen;
    }
    public override void Dispose() { base.Dispose(); token.Clear(); }
}
