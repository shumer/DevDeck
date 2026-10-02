using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Automation;
using System.Windows.Media;
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
    private long replacementRevision;
    private long endpointRevision;
    private bool syncingCommittedEndpoint;
    private bool tokenPresent, tokenActionPending;
    private readonly TextBlock tokenPresence = new() { TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock tokenResult = new() { TextWrapping = TextWrapping.Wrap, Margin = new(0,8,0,8) };
    private readonly TextBlock tokenProgress = new() { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DimGray };
    private readonly Button createToken, verifyStored;
    internal RemoteAccountSettings? CommittedTokenAccount => original;
    internal bool TokenActionPending => tokenActionPending;
    internal bool InitialTokenPresent { get; }
    internal Func<bool>? TokenOwnerCurrent { get; }
    internal Func<RemoteAccountSettings,string?>? StoredCredentialReader { get; }
    internal Func<WorkerSettings,CancellationToken,Task<StoredTokenVerifier>>? AcquireStoredVerifier { get; }
    internal Action<RemoteAccountSettings,bool>? StoredPresenceChanged { get; }
    internal Func<string,CancellationToken,Task<string?>>? EnterpriseAddressPrompt { get; }
    internal Func<long>? TokenOwnerGeneration { get; }
    internal string TokenDraft { get => token.Password; set => token.Password = value; }
    internal AccountSettingsForm(DeckController controller, RemoteAccountSettings? original, bool live, Action<string> changed, string newProvider = "github", Func<SettingsRemovalRequest,bool>? confirmation = null, Action<RemoteAccountSettings>? clearCredential = null, Func<Task>? verifyToken = null,
        Action<string>? credentialChanged = null, Func<RemoteAccountSettings,string,string,CancellationToken,Task>? verifyCredential = null,
        Action<RemoteAccountSettings,string?>? credentialWriter = null,
        Func<CancellationToken,Task<string[]>>? discoverDistributions = null,
        Action<string,string?,string>? browserOpener = null,
        Func<string,string?,BrowserPicker>? browserPickerFactory = null,
        bool tokenPresent = false, Func<bool>? ownerCurrent = null,
        Func<RemoteAccountSettings,string?>? storedCredentialReader = null,
        Func<WorkerSettings,CancellationToken,Task<StoredTokenVerifier>>? acquireStoredVerifier = null,
        Action<RemoteAccountSettings,bool>? storedPresenceChanged = null,
        Func<string,CancellationToken,Task<string?>>? enterpriseAddressPrompt = null,
        Func<long>? ownerGeneration = null) : base(controller, live)
    {
        this.original = original; id = original?.Id ?? "account-" + Guid.NewGuid().ToString("N"); this.changed = changed; this.confirmation = confirmation; this.clearCredential = clearCredential; this.verifyToken = verifyToken; Autosaves = original is not null;
        this.credentialChanged = credentialChanged; this.verifyCredential = verifyCredential; this.credentialWriter = credentialWriter;
        this.discoverDistributions = discoverDistributions; this.browserOpener = browserOpener;
        InitialTokenPresent = tokenPresent; this.tokenPresent = tokenPresent; TokenOwnerCurrent = ownerCurrent;
        StoredCredentialReader = storedCredentialReader; AcquireStoredVerifier = acquireStoredVerifier;
        StoredPresenceChanged = storedPresenceChanged; EnterpriseAddressPrompt = enterpriseAddressPrompt;
        TokenOwnerGeneration = ownerGeneration;
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
        AutomationProperties.SetAutomationId(tokenPresence,"account.token.presence");
        AutomationProperties.SetAutomationId(tokenResult,"account.token.result");
        panel.Children.Add(tokenPresence);
        createToken = TokenButton("account.token.create",CreateTokenAsync);
        verifyStored = TokenButton("account.token.verifyStored",VerifyStoredTokenAsync);
        verifyStored.Content = new TextBlock { Text=Text.L("windows.verifyStoredToken"), TextWrapping=TextWrapping.Wrap };
        AutomationProperties.SetName(verifyStored,Text.L("windows.verifyStoredToken"));
        panel.Children.Add(createToken); panel.Children.Add(verifyStored);
        Field(panel, Text.L("token.field"), token); Field(panel, Text.L("windows.verifyDistribution"), distribution);
        panel.Children.Add(Button(Text.L("windows.verifySaveToken"), VerifyTokenAsync));
        token.KeyDown += async (_, args) => {
            if (args.Key != Key.Return || Keyboard.Modifiers != ModifierKeys.None) return;
            args.Handled = true; await VerifyTokenAsync();
        };
        token.PasswordChanged += (_,_) => { replacementRevision++; tokenResult.Text=""; };
        panel.Children.Add(tokenProgress); panel.Children.Add(tokenResult);
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
        UpdateTokenPresentation();
        provider.SelectionChanged += (_, _) => {
            if (this.original is not null) { provider.SelectedItem = this.original.Provider; return; }
            var next = provider.SelectedItem as string;
            if (next is not ("github" or "gitlab") || next == presentedProvider) return;
            endpointDrafts[presentedProvider] = endpoint.Text;
            endpoint.Text = endpointDrafts[next]; presentedProvider = next; ApplyProviderPresentation();
        };
        foreach (var field in new[] { label, organizations, repositories }) Watch(field);
        organizations.TextChanged += (_, _) => organizationRevision++;
        repositories.TextChanged += (_, _) => repositoryRevision++;
        browser.ValueChanged += (_,_) => Changed(); foreach (var field in new[] { enabled, reviews, blocked, runs }) Watch(field);
        endpoint.TextChanged += (_,_) => {
            if (syncingCommittedEndpoint) return;
            endpointRevision++; Changed(); tokenResult.Text=""; UpdateTokenPresentation();
        };
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
        UpdateTokenPresentation();
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
    internal Task VerifyTokenAsync() => !IsEnabled ? Task.CompletedTask
        : verifyToken is not null ? ExecuteAsync(verifyToken)
        : original is not null && token.Password.Length == 0 ? VerifyStoredTokenAsync() : ExecuteAsync(SaveTokenAsync);
    internal void ReconcileTokenPresence(bool present)
    {
        if (IsDisposed) return;
        tokenPresent=present; UpdateTokenPresentation();
    }
    private Button TokenButton(string automationID,Func<Task> action)
    {
        var button = new Button { Padding=new(12,7,12,7), Margin=new(0,6,8,4), HorizontalAlignment=HorizontalAlignment.Left };
        AutomationProperties.SetAutomationId(button,automationID);
        button.Click += async (_,_) => { await action(); if (!IsDisposed) UpdateTokenPresentation(); };
        return button;
    }
    private void UpdateTokenPresentation()
    {
        if (createToken is null || verifyStored is null) return;
        var host = Uri.TryCreate(endpoint.Text,UriKind.Absolute,out var url) && url.Host.Length>0 ? url.Host : "GitLab";
        var title=Text.L(presentedProvider=="github" ? "account.github.create" : "account.gitlab.create",host);
        createToken.Content=new TextBlock { Text=title, TextWrapping=TextWrapping.Wrap };
        AutomationProperties.SetName(createToken,title);
        createToken.IsEnabled=!tokenActionPending;
        verifyStored.IsEnabled=original is not null && tokenPresent && !tokenActionPending;
        tokenPresence.Text=Text.L(tokenPresent ? "windows.tokenStored" : "token.none")+" · "+Text.L(tokenPresent ? "token.saved.detail" : "token.none.detail");
        AutomationProperties.SetName(tokenPresence,tokenPresence.Text);
    }
    private long OwnerGeneration => TokenOwnerGeneration?.Invoke() ?? 0;
    private bool CurrentOwner(long generation) => !IsDisposed && !Lifetime.IsCancellationRequested
        && generation==OwnerGeneration && (TokenOwnerCurrent?.Invoke() ?? true);
    private sealed record CreationTicket(string Provider,string Endpoint,string Browser,string? Profile,long Generation);
    private bool Current(CreationTicket ticket) => CurrentOwner(ticket.Generation)
        && provider.SelectedItem as string==ticket.Provider && endpoint.Text==ticket.Endpoint
        && browser.BrowserID==ticket.Browser && browser.SelectedProfile==ticket.Profile;
    private sealed record StoredTicket(RemoteAccountSettings Account,WorkerSettings Route,long Generation,long ReplacementRevision);
    private bool Current(StoredTicket ticket)
    {
        if (!CurrentOwner(ticket.Generation) || replacementRevision!=ticket.ReplacementRevision
            || endpoint.Text!=ticket.Account.Endpoint || provider.SelectedItem as string!=ticket.Account.Provider
            || distribution.SelectedItem as string!=ticket.Route.Distribution || !Controller.Settings.Workers.Contains(ticket.Route)) return false;
        var committed=Controller.Settings.AccountList.FirstOrDefault(account=>account.Id==ticket.Account.Id);
        return committed is not null && committed.Provider==ticket.Account.Provider && committed.Endpoint==ticket.Account.Endpoint
            && committed.CredentialTarget==ticket.Account.CredentialTarget && original?.CredentialTarget==ticket.Account.CredentialTarget;
    }
    private void Admit(bool current) { if (!current) throw new OperationCanceledException(Lifetime.Token); }
    private async Task RunTokenActionAsync(Func<Task> action,Func<bool> current,string progress)
    {
        if (!Live || !IsEnabled || tokenActionPending || IsDisposed || !current()) return;
        tokenActionPending=true; IsEnabled=false; tokenResult.Text=""; tokenProgress.Text=progress; UpdateTokenPresentation();
        try {
            using var pause=await PauseAutosaveAsync(Lifetime.Token);
            Admit(current()); await action();
        } catch (OperationCanceledException) { }
        catch (Exception error) {
            if (current()) { tokenResult.Text=Text.Failure(error); tokenResult.Foreground=Brushes.Firebrick; }
        } finally {
            tokenActionPending=false;
            if (!IsDisposed) { IsEnabled=true; tokenProgress.Text=""; UpdateTokenPresentation(); }
        }
    }
    internal Task CreateTokenAsync()
    {
        var ticket=new CreationTicket(provider.SelectedItem as string ?? "",endpoint.Text,browser.BrowserID,browser.SelectedProfile,OwnerGeneration);
        return RunTokenActionAsync(async ()=> {
            var destination=CreationAddress(()=>AccountTokenActions.Creation(ticket.Provider,ticket.Endpoint));
            var address=destination.Address;
            if (destination.NeedsEnterpriseAddress) {
                address=await (EnterpriseAddressPrompt ?? ((apiEndpoint,cancellation)=> {
                    cancellation.ThrowIfCancellationRequested();
                    return Task.FromResult(EnterpriseTokenAddressDialog.Show(apiEndpoint,Window.GetWindow(this)));
                }))(ticket.Endpoint,Lifetime.Token);
                Admit(Current(ticket)); if (address is null) return;
                address=CreationAddress(()=>AccountTokenActions.EnterpriseCreationAddress(address));
            }
            Admit(Current(ticket));
            _=BrowserLaunch.Arguments(ticket.Browser,ticket.Profile,address!);
            (browserOpener ?? ((browserID,profile,url)=>BrowserLaunch.Open(browserID,profile,url)))(ticket.Browser,ticket.Profile,address!);
        },()=>Current(ticket),Text.L("windows.openingTokenPage"));
    }
    private static T CreationAddress<T>(Func<T> project)
    {
        try {return project();}
        catch (InvalidDataException) {throw new InvalidOperationException(Text.L("windows.tokenCreationInvalid"));}
    }
    internal Task VerifyStoredTokenAsync()
    {
        var generation=OwnerGeneration;
        var revision=replacementRevision;
        StoredTicket? ticket=null;
        bool Admitted()=>ticket is null ? CurrentOwner(generation) && replacementRevision==revision : Current(ticket);
        return RunTokenActionAsync(async ()=> {
            if (original is null || !tokenPresent) throw new InvalidOperationException(Text.L("token.needed"));
            var saved=Controller.Settings.AccountList.FirstOrDefault(account=>account.Id==original.Id);
            if (saved is null || saved.Provider!=original.Provider || saved.Endpoint!=original.Endpoint
                || saved.CredentialTarget!=original.CredentialTarget || endpoint.Text!=saved.Endpoint)
                throw new InvalidOperationException(Text.L("windows.tokenEndpointChanged"));
            var route=Controller.Settings.Workers.FirstOrDefault(worker=>worker.Distribution==distribution.SelectedItem as string)
                ?? throw new InvalidOperationException(Text.L("windows.chooseDistribution"));
            var owned=saved with { Organizations=saved.Organizations?.ToArray()!, Repositories=saved.Repositories?.ToArray()! };
            ticket=new(owned,route,generation,revision); Admit(Current(ticket));
            var verifier=await (AcquireStoredVerifier ?? Controller.AcquireStoredTokenVerifierAsync)(route,Lifetime.Token);
            Admit(Current(ticket) && verifier.Route==route);
            string? value=null;
            try {
                Admit(Current(ticket)); value=(StoredCredentialReader ?? Controller.Tokens.Read)(owned);
                Admit(Current(ticket));
                if (string.IsNullOrEmpty(value)) throw new InvalidOperationException(Text.L("token.needed"));
                await verifier.VerifyAsync(owned,value,Lifetime.Token);
                Admit(Current(ticket));
                tokenResult.Text=Text.L("token.works"); tokenResult.Foreground=Brushes.SeaGreen;
                StoredPresenceChanged?.Invoke(owned,true);
            } finally { value=null; }
        },Admitted,Text.L("windows.verifying"));
    }
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
    private RemoteAccountSettings Draft(bool normalizeEndpoint = false)
    {
        string[] Split(string value) => value.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        var kind = (string)provider.SelectedItem;
        var github = RemoteAccountApplicability.HasGitHubScopes(kind);
        var enteredEndpoint = endpoint.Text;
        var chosenEndpoint = !normalizeEndpoint && original is { } saved && string.Equals(enteredEndpoint, saved.Endpoint, StringComparison.Ordinal)
            ? saved.Endpoint : enteredEndpoint.Trim().TrimEnd('/');
        var account = new RemoteAccountSettings(id, label.Text.Trim(), kind, chosenEndpoint,
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
        if (credentialSaved) { ReconcileTokenPresence(true); credentialChanged?.Invoke(id); }
        changed(id);
    }
    private async Task SaveTokenAsync()
    {
        if (!Live) return;
        var account = Draft(normalizeEndpoint: true); var value = token.Password;
        var capturedEndpointRevision = endpointRevision; var capturedOwnerGeneration = OwnerGeneration;
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
        if (CurrentOwner(capturedOwnerGeneration) && endpointRevision == capturedEndpointRevision
            && original?.CredentialTarget == account.CredentialTarget
            && Controller.Settings.AccountList.Any(current => current.Id == account.Id && current.CredentialTarget == account.CredentialTarget)
            && endpoint.Text != account.Endpoint) {
            syncingCommittedEndpoint = true;
            try { endpoint.Text = account.Endpoint; }
            finally { syncingCommittedEndpoint = false; }
            UpdateTokenPresentation();
        }
        token.Clear(); Message.Text = Text.L("token.works"); Message.Foreground = System.Windows.Media.Brushes.SeaGreen;
    }
    public override void Dispose() { base.Dispose(); token.Clear(); }
}
