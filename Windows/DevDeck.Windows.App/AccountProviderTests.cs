using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Input;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Captures provider applicability through current owned forms and real request/save bodies.
/// All credential and transport dependencies are fake; no worker, discovery or provider starts.
internal static class AccountProviderTests
{
    private const string Distribution = "Owned Linux", LabID = "owned.lab", GitHubID = "owned.github";

    // Individual scenarios let the baseline retain each independent old-production failure.
    internal static async Task RunAsync(Application application, List<object> checks, string? scenario = null)
    {
        var language = Text.Language;
        try {
            Text.Use("en");
            switch (scenario) {
                case null:
                    foreach (var locale in DevDeck.Windows.Core.Localization.Languages) {
                        Text.Use(locale);
                        await FormAsync(application, checks);
                        await NotificationsAsync(application, checks);
                        await SwitchAsync(application, checks);
                    }
                    Text.Use("en");
                    await RequestsAsync(application, checks);
                    await MetadataAsync(application, checks);
                    await GitHubRequestsAsync(application, checks);
                    await ScopeEditsAsync(application, checks);
                    await CredentialFailuresAsync(application, checks);
                    await CredentialCommitsAsync(application, checks);
                    await BrowserAsync(application, checks);
                    await NewCommitAsync(application, checks);
                    break;
                case "form": await FormAsync(application, checks); break;
                case "notifications": await NotificationsAsync(application, checks); break;
                case "requests": await RequestsAsync(application, checks); break;
                case "metadata": await MetadataAsync(application, checks); break;
                default: throw new ArgumentException("Unknown account-provider scenario.", nameof(scenario));
            }
        } finally { Text.Use(language); }
    }

    private static async Task FormAsync(Application application, List<object> checks)
    {
        using var owned = new Owned(application);
        var original = owned.Lab;
        using var form = new AccountSettingsForm(owned.Controller, original, live:false, changed:_ =>
            throw new IOException("Provider presentation invoked a metadata callback."), browserPickerFactory:FakeBrowser);
        using var owner = new Shown(form);
        await Turns(); owner.Window.UpdateLayout();
        Require(form.IsLoaded && form.IsVisible, "The actual owned account form was not loaded and visible.");
        foreach (var expander in Elements<Expander>(form)) expander.IsExpanded = true;
        await Turns(); owner.Window.UpdateLayout();
        var organizations = Field<TextBox>(form, "organizations");
        var repositories = Field<TextBox>(form, "repositories");
        var runs = Field<CheckBox>(form, "runs");
        var endpoint = Field<TextBox>(form, "endpoint");
        var token = Field<PasswordBox>(form, "token");
        var labels = Elements<TextBlock>(form).Where(value => value.IsVisible).Select(value => value.Text).ToArray();
        var hasGitHubCaptions = labels.Contains(Text.L("windows.organizations")) || labels.Contains(Text.L("windows.repositories"));
        var addressName = AutomationProperties.GetName(endpoint);
        var addressY = endpoint.IsVisible ? endpoint.TransformToAncestor(form).Transform(new Point()).Y : double.NaN;
        var tokenY = token.TransformToAncestor(form).Transform(new Point()).Y;
        var help = labels.Any(text => text.Contains(Text.L("account.gitlab.token.help"), StringComparison.Ordinal));
        owned.RequireUnchanged();
        Require(!organizations.IsVisible && !repositories.IsVisible && !runs.IsVisible && !hasGitHubCaptions
            && endpoint.IsVisible && addressName == Text.L("account.gitlab.address") && addressY < tokenY && help,
            "GitLab provider form exposes unsupported controls or hides its identity: "
            + $"organizationsVisible={organizations.IsVisible}, repositoriesVisible={repositories.IsVisible}, runsVisible={runs.IsVisible}, "
            + $"GitHubCaptions={hasGitHubCaptions}, endpointVisible={endpoint.IsVisible}, AddressCaption={addressName == Text.L("account.gitlab.address")}, "
            + $"addressY={addressY:F2}, tokenY={tokenY:F2}, providerHelp={help}.");
        Require(Field<ComboBox>(form, "provider").IsEnabled == false && endpoint.Text == original.Endpoint,
            "Provider presentation changed an existing account provider or endpoint draft.");
        using var github = new AccountSettingsForm(owned.Controller, owned.GitHub, live:false, changed:_ =>
            throw new IOException("GitHub provider presentation invoked a metadata callback."), browserPickerFactory:FakeBrowser);
        owner.View.Content=github; await Turns();
        foreach (var expander in Elements<Expander>(github)) expander.IsExpanded=true;
        owner.Window.UpdateLayout();
        Require(Field<TextBox>(github,"organizations").IsVisible && Field<TextBox>(github,"repositories").IsVisible
            && Field<CheckBox>(github,"runs").IsVisible && Elements<TextBlock>(github).Any(value=>value.IsVisible
                && value.Text.Contains(Text.L("account.github.token.help"),StringComparison.Ordinal)), "Applicable GitHub fields/help disappeared.");
        foreach(var font in new[]{13d,18d}) foreach(var size in new[]{new Size(880,440),new Size(1020,720)}) {
            owner.Window.FontSize=font; owner.Window.Width=size.Width; owner.Window.Height=size.Height;
            foreach(var current in new[]{form,github}) {
                owner.View.Content=current; await Turns(); owner.Window.UpdateLayout(); RequireBounds(current);
            }
        }
        owned.RequireUnchanged();
        checks.Add(new { name="accounts.provider.gitlabForm", language=Text.Language, actualLoadedForm=true,
            unsupportedControlsAndCaptionsHidden=true, currentAddressBeforeToken=true, providerHelp=true,
            applicableGitHubFieldsRetained=true, measuredDimensions=2, measuredFonts=2,
            settingsValidLegacyArraysRetained=true, noVaultWorkerOrDiscovery=true });
    }

    private static async Task NotificationsAsync(Application application, List<object> checks)
    {
        using var owned = new Owned(application);
        var panel = NotificationSettingsWindow.CreateContent(owned.Controller);
        using var owner = new Shown(panel);
        await Turns(); owner.Window.UpdateLayout();
        var lab = AccountRow(panel, owned.Lab.Label);
        var github = AccountRow(panel, owned.GitHub.Label);
        var labRuns = lab.Children.Cast<UIElement>().Where(value => Grid.GetColumn(value) == 3).ToArray();
        var githubRuns = github.Children.OfType<CheckBox>().Single(value => Grid.GetColumn(value) == 3);
        Require(githubRuns.IsVisible && githubRuns.IsEnabled && githubRuns.IsChecked == true,
            "The applicable GitHub failed-run positive control was absent or disabled.");
        Require(lab.Children.OfType<CheckBox>().Count(value => value.IsVisible) >= 2,
            "GitLab review/blocked preferences disappeared with the unsupported runs setting.");
        owned.RequireUnchanged();
        Require(labRuns.Length == 1 && labRuns[0] is not CheckBox
            && !Elements<CheckBox>(labRuns[0]).Any(value => value.IsVisible),
            "Actual Notifications page offers a GitLab failed-run switch: "
            + $"runsColumnChildren={labRuns.Length}, runsColumnCheckboxes={labRuns.OfType<CheckBox>().Count()}, "
            + $"retainedLegacyFlag={owned.Lab.NotifiesFailedRuns}.");
        var review=lab.Children.OfType<CheckBox>().Single(value=>Grid.GetColumn(value)==1);
        review.IsChecked=false; review.RaiseEvent(new RoutedEventArgs(CheckBox.ClickEvent)); await Turns();
        Require(Json(owned.Store.Load().AccountList.Single(value=>value.Id==LabID) with {NotifiesReviewRequests=true})==Json(owned.Lab)
            && Json(owned.Store.Load().AccountList.Single(value=>value.Id==GitHubID))==Json(owned.GitHub),
            "GitLab review preference save changed hidden arrays/runs or its sibling.");
        var master=panel.Children.OfType<CheckBox>().Single(); master.IsChecked=false;
        master.RaiseEvent(new RoutedEventArgs(CheckBox.ClickEvent)); await Turns();
        Require(!review.IsEnabled && !githubRuns.IsEnabled && !owned.Controller.Settings.Notifications,
            "Master-off left applicable notification preferences enabled.");
        owned.RequireIsolation();
        checks.Add(new { name="accounts.provider.gitlabNotifications", language=Text.Language, actualLoadedPage=true,
            gitlabRunsColumnInert=true, gitlabReviewAndBlockedPreserved=true, githubRunsPositiveControl=true,
            hiddenLegacyFlagAndArraysRetained=true, actualSelectedPreferenceSave=true, masterOffDisables=true,
            noActualNotificationOrProvider=true });
    }

    private static async Task RequestsAsync(Application application, List<object> checks)
    {
        using var owned = new Owned(application);
        var captured = new List<(string Operation, RemoteRequest Request)>();
        var reads = 0;
        using var lifetime = new CancellationTokenSource();
        owned.Controller.RemoteTokenReader = account => {
            Require(account.Id == LabID && account.CredentialTarget == owned.Lab.CredentialTarget,
                "The actual snapshot body requested a foreign account credential.");
            reads++; return "Owned in-memory token";
        };
        owned.Controller.RemoteRequestSender = (distribution, operation, request, cancellation) => {
            Require(distribution == Distribution && cancellation == lifetime.Token && !cancellation.IsCancellationRequested
                && (operation is "remote.snapshot" or "remote.verify") && request.Kind == "mergeRequests"
                && request.Accounts.Length == 1 && request.Accounts[0].Id == LabID
                && request.Accounts[0].Endpoint == owned.Lab.Endpoint,
                "The actual remote body lost its provider/identity/distribution/operation/lifetime boundary.");
            captured.Add((operation, request));
            var snapshot = operation == "remote.snapshot" ? new RemoteSnapshot(request.CardID, request.Kind, 0, 0, null, [], [], false) : null;
            return Task.FromResult(new WorkerResponse(1,"owned-capture",Distribution,null,null,null,null,Remote:snapshot));
        };
        var card = owned.Controller.Settings.RemoteCardList.Single(value => value.Kind == "mergeRequests");
        var result = await owned.Controller.FetchRemoteAsync(card, lifetime.Token);
        await owned.Controller.VerifyTokenAsync(owned.Lab, "Owned explicit replacement", Distribution, lifetime.Token);
        Require(result.CardID == card.Id && captured.Select(value => value.Operation).SequenceEqual(new[] { "remote.snapshot", "remote.verify" })
            && reads == 1 && captured[0].Request.Accounts[0].Token == "Owned in-memory token"
            && captured[1].Request.Accounts[0].Token == "Owned explicit replacement"
            && captured[1].Request.CardID == "verify." + LabID,
            "Actual snapshot/verify did not reach the fake sender with their distinct admitted credentials.");
        owned.RequireUnchanged();
        var snapshotAccount = captured[0].Request.Accounts[0];
        var verifyAccount = captured[1].Request.Accounts[0];
        Require(snapshotAccount.Organizations.Length == 0 && snapshotAccount.Repositories.Length == 0
            && verifyAccount.Organizations.Length == 0 && verifyAccount.Repositories.Length == 0,
            "Actual GitLab requests contain inactive saved arrays: "
            + $"snapshotOrganizations={snapshotAccount.Organizations.Length}, snapshotRepositories={snapshotAccount.Repositories.Length}, "
            + $"verifyOrganizations={verifyAccount.Organizations.Length}, verifyRepositories={verifyAccount.Repositories.Length}; "
            + "original settings JSON remains unchanged.");
        checks.Add(new { name="accounts.provider.gitlabRequests", actualSnapshotAndVerifyBodies=true,
            bothUnusedArraysEmpty=true, savedInvalidForWorkerArraysUnchanged=true,
            capturedExactIdentityAndCancellation=true, fakeTokenReads=reads, fakeRequests=captured.Count,
            noActualVaultWorkerProviderOrAttention=true });
    }

    private static async Task MetadataAsync(Application application, List<object> checks)
    {
        using var owned = new Owned(application);
        var original = owned.Lab; var changes = 0;
        using var form = new AccountSettingsForm(owned.Controller, original, live:true, changed:id => {
            Require(id == LabID, "Metadata commit used a foreign account ID."); changes++;
        }, verifyCredential:(_, _, _, _) => throw new IOException("Metadata save invoked token verification."),
            credentialWriter:(_, _) => throw new IOException("Metadata save invoked a credential write."), browserPickerFactory:FakeBrowser);
        form.TokenDraft = "Owned unsaved token draft";
        Field<TextBox>(form, "label").Text = "Renamed owned GitLab";
        BaseField<DispatcherTimer>(form, "debounce").Stop();
        await form.FlushAsync();
        var saved = owned.Store.Load().AccountList.Single(value => value.Id == LabID);
        Require(!form.IsLoaded && changes == 1 && saved.Label == "Renamed owned GitLab"
            && form.TokenDraft == "Owned unsaved token draft", "Actual metadata save failed its isolated body/draft premise.");
        var exact = Json(saved with { Label=original.Label }) == Json(original);
        Require(exact && Json(owned.Store.Load().AccountList.Single(value => value.Id == GitHubID)) == Json(owned.GitHub),
            "A GitLab name-only save modified inactive legacy fields: "
            + $"exactInactiveFields={exact}, originalOrganizations={original.Organizations.Length}, savedOrganizations={saved.Organizations.Length}, "
            + $"originalRepositories={original.Repositories.Length}, savedRepositories={saved.Repositories.Length}, retainedRuns={saved.NotifiesFailedRuns}.");
        owned.RequireIsolation();
        checks.Add(new { name="accounts.provider.gitlabMetadata", actualAutosaveBody=true,
            exactInactiveArraysAndFlagRetained=true, siblingAccountUnchanged=true, tokenDraftRetained=true,
            noActualVaultWorkerProviderOrDiscovery=true });
    }

    private static async Task SwitchAsync(Application application,List<object> checks)
    {
        using var owned=new Owned(application);
        using var form=Form(owned,null,live:false);
        using var owner=new Shown(form); await Turns();
        var name=Field<TextBox>(form,"label"); name.Text="Owned draft identity";
        var endpoint=Field<TextBox>(form,"endpoint"); endpoint.Text="https://github.owned.test/api";
        Field<TextBox>(form,"organizations").Text="alpha, beta";
        Field<TextBox>(form,"repositories").Text="alpha/site, beta/site";
        Field<CheckBox>(form,"runs").IsChecked=true; form.TokenDraft="Owned unsaved password";
        var browser=Field<BrowserPicker>(form,"browser"); browser.Picker.SelectedValue="edge"; browser.Profile.SelectedValue="Profile 7";
        var advanced=Elements<Expander>(form).Single(); advanced.IsExpanded=true; owner.Window.UpdateLayout();
        await FocusOwnedAsync(owner,name);
        name.Select(3,5);
        var selector=Field<ComboBox>(form,"provider"); selector.SelectedItem="gitlab"; await Turns();
        Require(name.IsKeyboardFocusWithin && name.SelectionStart==3 && name.SelectionLength==5
            && !Field<TextBox>(form,"organizations").IsVisible && !Field<CheckBox>(form,"runs").IsVisible
            && endpoint.IsVisible && advanced.IsExpanded,"Provider switch replaced focus/cursor or showed unsupported controls.");
        endpoint.Text="invalid edited instance";
        selector.SelectedItem="github"; await Turns();
        Require(endpoint.Text=="https://github.owned.test/api" && Field<TextBox>(form,"organizations").Text=="alpha, beta"
            && Field<TextBox>(form,"repositories").Text=="alpha/site, beta/site" && Field<CheckBox>(form,"runs").IsChecked==true,
            "Returning to GitHub lost its endpoint or scope draft.");
        selector.SelectedItem="gitlab"; await Turns();
        Require(endpoint.Text=="invalid edited instance" && form.TokenDraft=="Owned unsaved password"
            && browser.BrowserID=="edge" && browser.SelectedProfile=="Profile 7" && advanced.IsExpanded
            && name.Text=="Owned draft identity" && name.IsKeyboardFocusWithin && name.SelectionStart==3 && name.SelectionLength==5,
            "Returning to GitLab lost invalid endpoint/password/browser/profile/focus or Expander draft.");
        owned.RequireUnchanged();
        checks.Add(new{name="accounts.provider.retainedNewDraft",language=Text.Language,actualOwnedKeyboardFocus=true,
            invalidAndValidEndpointDraftsRetained=true,githubScopeAndRunsDraftRetained=true,
            passwordBrowserProfileCursorAndExpanderRetained=true,noSettingsCredentialOrRpcMutation=true});
    }

    private static async Task GitHubRequestsAsync(Application application,List<object> checks)
    {
        using var owned=new Owned(application);
        var captured=new List<RemoteRequest>(); var reads=0;
        owned.Controller.RemoteTokenReader=account=>{Require(account.Id==GitHubID,"GitHub request read another account token.");reads++;return "Owned GH token";};
        owned.Controller.RemoteRequestSender=(_,operation,request,_)=>{
            Require(request.Kind=="pullRequests" && request.Accounts.Single().Id==GitHubID,"GitHub request changed provider/identity.");
            captured.Add(request); return Task.FromResult(Reply(request,operation=="remote.snapshot"));
        };
        await owned.Controller.FetchRemoteAsync(owned.Controller.Settings.RemoteCardList.Single(value=>value.Kind=="pullRequests"),CancellationToken.None);
        await owned.Controller.VerifyTokenAsync(owned.GitHub,"Owned GH replacement",Distribution,CancellationToken.None);
        Require(reads==1 && captured.Count==2 && captured.All(request=>request.Accounts[0].Organizations.SequenceEqual(owned.GitHub.Organizations)
            && request.Accounts[0].Repositories.SequenceEqual(owned.GitHub.Repositories)
            && !ReferenceEquals(request.Accounts[0].Organizations,owned.Controller.Settings.AccountList.Single(value=>value.Id==GitHubID).Organizations)),
            "GitHub active scopes were dropped, changed or shared with mutable settings.");
        captured[0].Accounts[0].Organizations[0]="changed owned capture"; owned.RequireUnchanged();
        checks.Add(new{name="accounts.provider.githubRequests",actualSnapshotAndVerifyBodies=true,
            applicableRawScopesRetained=true,ownedCredentialArrays=true,noActualVaultWorkerOrProvider=true});
    }

    private static async Task ScopeEditsAsync(Application application,List<object> checks)
    {
        using var owned=new Owned(application,invalidGitHub:true); var commits=0;
        using var form=Form(owned,owned.GitHub,live:true,changed:_=>commits++);
        Field<TextBox>(form,"label").Text="Renamed GH only"; StopDebounce(form); await form.FlushAsync();
        var renamed=owned.Store.Load().AccountList.Single(value=>value.Id==GitHubID);
        Require(Json(renamed with{Label=owned.GitHub.Label})==Json(owned.GitHub),"A GitHub name-only save silently repaired invalid active legacy arrays.");
        var gate=Field<SemaphoreSlim>(owned.Controller,"actions"); await gate.WaitAsync();
        Task? saving=null;
        try {
            Field<TextBox>(form,"organizations").Text="first-org"; StopDebounce(form); saving=form.FlushAsync(); await Turns();
            Require(!saving.IsCompleted,"The actual metadata save did not wait behind its owned action gate.");
            Field<TextBox>(form,"organizations").Text="second-org, third-org"; StopDebounce(form);
        } finally {gate.Release();}
        await saving!.WaitAsync(TimeSpan.FromSeconds(5));
        var saved=owned.Store.Load().AccountList.Single(value=>value.Id==GitHubID);
        Require(saved.Organizations.SequenceEqual(new[]{"second-org","third-org"}) && Json(saved.Repositories)==Json(owned.GitHub.Repositories)
            && commits==3,"An older scope commit consumed a newer edit revision or reparsed an untouched repository array.");
        Field<TextBox>(form,"repositories").Text=" owner/repo, other/site "; StopDebounce(form); await form.FlushAsync();
        saved=owned.Store.Load().AccountList.Single(value=>value.Id==GitHubID);
        Require(saved.Repositories.SequenceEqual(new[]{"owner/repo","other/site"}) && saved.Organizations.SequenceEqual(new[]{"second-org","third-org"}),
            "Explicit scope correction did not preserve the other committed field.");
        owned.RequireIsolation();
        checks.Add(new{name="accounts.provider.githubScopeEdits",invalidLegacyUnchangedUntilExplicitEdit=true,
            actualHeldSaveAndNewerEdit=true,fieldRevisionsPreserved=true,otherRawArrayUntouched=true});
    }

    private static async Task CredentialFailuresAsync(Application application,List<object> checks)
    {
        foreach(var cancelled in new[]{false,true}) {
            using var owned=new Owned(application); var entered=Pending<CancellationToken>(); var release=Pending<WorkerResponse>();
            var writes=0; var changes=0; var availability=0;
            owned.Controller.RemoteTokenReader=_=>throw new IOException("Explicit replacement verification read a stored token.");
            owned.Controller.RemoteRequestSender=(_,operation,request,token)=>{
                Require(operation=="remote.verify" && request.Accounts.Single().Endpoint=="https://edited.gitlab.example.test/owned"
                    && request.Accounts[0].Organizations.Length==0 && request.Accounts[0].Repositories.Length==0,
                    "Failed verification used the old identity or inactive request scopes.");
                entered.TrySetResult(token);
                return cancelled ? release.Task : Task.FromException<WorkerResponse>(new WorkerException("credentialsRejected","Owned refusal"));
            };
            using var form=Form(owned,owned.Lab,live:true,changed:_=>changes++,credentialChanged:_=>availability++,writer:(_,_)=>writes++);
            Field<TextBox>(form,"endpoint").Text="https://edited.gitlab.example.test/owned"; StopDebounce(form);
            form.TokenDraft="Owned rejected replacement"; var verifying=form.VerifyTokenAsync();
            var token=await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
            if(cancelled){BaseField<CancellationTokenSource>(form,"Lifetime").Cancel();release.SetResult(new(1,"owned-cancel",Distribution,null,null,null,null));}
            await verifying.WaitAsync(TimeSpan.FromSeconds(5));
            Require(writes==0 && changes==0 && availability==0 && form.TokenDraft=="Owned rejected replacement"
                && Field<TextBox>(form,"endpoint").Text=="https://edited.gitlab.example.test/owned" && form.IsEnabled
                && (!cancelled || token.IsCancellationRequested),"Rejected/cancelled provider verification committed or cleared its draft.");
            owned.RequireUnchanged();
        }
        checks.Add(new{name="accounts.provider.gitlabCredentialAdmission",actualControllerVerifyAndSaveBody=true,
            rejectedAndCancelledReplacementPreservesDraftAndLegacy=true,noPrematureWriteMetadataOrAvailability=true});
    }

    private static async Task CredentialCommitsAsync(Application application,List<object> checks)
    {
        foreach(var cleanupFails in new[]{false,true}) {
            using var owned=new Owned(application); var events=new List<string>();
            var target=(owned.Lab with{Endpoint="https://committed.gitlab.example.test/owned"}).CredentialTarget;
            owned.Controller.RemoteRequestSender=(_,operation,request,_)=>{
                Require(operation=="remote.verify" && request.Accounts[0].Organizations.Length==0 && request.Accounts[0].Repositories.Length==0,
                    "The actual verification did not project inactive scopes.");events.Add("verify");return Task.FromResult(Reply(request,false));
            };
            using var form=Form(owned,owned.Lab,live:true,changed:_=>events.Add("changed"),credentialChanged:id=>{
                Require(id==LabID && owned.Store.Load().AccountList.Single(value=>value.Id==id).CredentialTarget==target
                    && events.SequenceEqual(new[]{"verify","write"}),"Availability preceded the exact credential write/persisted commit.");events.Add("availability");
            },writer:(account,value)=>{
                if(value is not null){Require(account.CredentialTarget==target,"Write used old endpoint identity.");events.Add("write");}
                else {Require(account.CredentialTarget==owned.Lab.CredentialTarget && events.Last()=="changed","Old-target cleanup preceded current commit.");events.Add("delete");if(cleanupFails)throw new IOException("Owned cleanup failure");}
            });
            form.TokenDraft="Owned accepted replacement"; Field<TextBox>(form,"endpoint").Text="https://committed.gitlab.example.test/owned";StopDebounce(form);
            await form.VerifyTokenAsync();
            var saved=owned.Store.Load().AccountList.Single(value=>value.Id==LabID);
            Require(events.SequenceEqual(new[]{"verify","write","availability","changed","delete"})
                && Json(saved with{Endpoint=owned.Lab.Endpoint})==Json(owned.Lab)
                && form.TokenDraft==(cleanupFails?"Owned accepted replacement":"") && form.IsEnabled,
                "Provider commit/cleanup changed inactive values, callback order or password outcome.");
            owned.RequireIsolation();
        }
        checks.Add(new{name="accounts.provider.gitlabCredentialCommit",actualControllerVerifyAndSaveBody=true,
            exactTargetWritePersistAvailabilityCleanupOrder=true,successAndCleanupFailurePreserveLegacy=true});
    }

    private static async Task BrowserAsync(Application application,List<object> checks)
    {
        using var owned=new Owned(application); var opened=new List<(string Browser,string? Profile,string Address)>(); var discoveries=0;
        using var form=Form(owned,owned.Lab,live:true,opener:(browser,profile,address)=>opened.Add((browser,profile,address)),
            discover:_=>{discoveries++;return Task.FromResult(new[]{Distribution});});
        using var owner=new Shown(form); await Turns();
        var browser=Field<BrowserPicker>(form,"browser");browser.Picker.SelectedValue="edge";browser.Profile.SelectedValue="Profile 7";
        Field<TextBox>(form,"endpoint").Text="https://draft.gitlab.example.test/team";StopDebounce(form);
        var button=Elements<Button>(form).Single(value=>AutomationProperties.GetName(value)==Text.L("button.test"));
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));await Turns();
        Require(opened.SequenceEqual(new[]{("edge",(string?)"Profile 7","https://draft.gitlab.example.test/team/dashboard/merge_requests")})
            && discoveries==1,"Actual Test action ignored the current provider/endpoint/browser/profile or used real distribution discovery.");
        Field<TextBox>(form,"endpoint").Text="http://invalid.owned.test";StopDebounce(form);
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));await Turns();
        Require(opened.Count==1 && BaseField<TextBlock>(form,"Message").Text.Length>0,"Invalid endpoint opened a browser or lost its validation result.");
        owned.RequireUnchanged();
        checks.Add(new{name="accounts.provider.currentDraftBrowserTest",actualLoadedFormAndTestButton=true,
            currentEndpointBrowserProfile=true,invalidEndpointNeverOpened=true,fakeDiscoveryCalls=discoveries,noActualBrowserOrVault=true});
    }

    private static async Task NewCommitAsync(Application application,List<object> checks)
    {
        using var owned=new Owned(application); var events=new List<string>(); string? verifiedID=null;
        owned.Controller.RemoteRequestSender=(_,operation,request,_)=>{
            var credential=request.Accounts.Single();verifiedID=credential.Id;
            Require(operation=="remote.verify" && request.Kind=="mergeRequests" && credential.Organizations.Length==0 && credential.Repositories.Length==0,
                "A new GitLab verification leaked its unsaved GitHub scope draft.");events.Add("verify");return Task.FromResult(Reply(request,false));
        };
        using var form=Form(owned,null,live:true,changed:id=>{Require(id==verifiedID,"New account commit changed its permanent ID.");events.Add("changed");},
            credentialChanged:_=>events.Add("availability"),writer:(account,value)=>{Require(account.Id==verifiedID && value is not null,"New account wrote/deleted another credential.");events.Add("write");});
        using var owner=new Shown(form);await Turns();
        Field<TextBox>(form,"label").Text="New owned GitLab";Field<TextBox>(form,"organizations").Text="invalid unsaved GH org";
        Field<TextBox>(form,"repositories").Text="invalid unsaved GH repo";Field<CheckBox>(form,"runs").IsChecked=true;
        var selector=Field<ComboBox>(form,"provider");selector.SelectedItem="gitlab";
        Field<TextBox>(form,"endpoint").Text="https://new.gitlab.example.test/team";form.TokenDraft="Owned new token";StopDebounce(form);
        await form.VerifyTokenAsync();
        var created=owned.Store.Load().AccountList.Single(value=>value.Id==verifiedID);
        Require(created.Provider=="gitlab" && created.Organizations.Length==0 && created.Repositories.Length==0 && !created.NotifiesFailedRuns
            && !selector.IsEnabled && form.TokenDraft.Length==0 && events.SequenceEqual(new[]{"verify","write","availability","changed"}),
            "New GitLab commit retained inactive GH values, unlocked provider or changed save ordering.");
        selector.SelectedItem="github";
        Require(selector.SelectedItem as string=="gitlab" && !selector.IsEnabled,"The retained newly saved form allowed provider/credential identity changes.");
        Require(Json(owned.Store.Load().AccountList.Single(value=>value.Id==LabID))==Json(owned.Lab)
            && Json(owned.Store.Load().AccountList.Single(value=>value.Id==GitHubID))==Json(owned.GitHub),"New-account commit changed an existing account.");
        owned.RequireIsolation();
        checks.Add(new{name="accounts.provider.newGitlabCommit",actualLoadedFormVerifyAndSaveBody=true,
            unsavedGitHubScopesExcluded=true,stableIDAndProviderLockedAfterPersist=true,siblingAccountsRetained=true});
    }

    private static AccountSettingsForm Form(Owned owned,RemoteAccountSettings? account,bool live,Action<string>? changed=null,
        Action<string>? credentialChanged=null,Action<RemoteAccountSettings,string?>? writer=null,
        Action<string,string?,string>? opener=null,Func<CancellationToken,Task<string[]>>? discover=null) => new(owned.Controller,account,live,
        changed??(_=>{}),credentialChanged:credentialChanged,credentialWriter:writer??((_,_)=>throw new IOException("Unexpected owned credential write.")),
        discoverDistributions:discover??(_=>Task.FromResult(new[]{Distribution})),browserOpener:opener??((_,_,_)=>throw new IOException("Unexpected owned browser action.")),
        browserPickerFactory:FakeBrowser);
    private static BrowserPicker FakeBrowser(string browser,string? profile) => new(browser,profile,
        [new("edge","Owned Edge","C:/owned/msedge.exe",true)],_=>[new("Profile 7","Owned profile")]);
    private static WorkerResponse Reply(RemoteRequest request,bool snapshot) => new(1,"owned-provider",Distribution,null,null,null,null,
        Remote:snapshot?new(request.CardID,request.Kind,0,0,null,[],[],false):null);
    private static TaskCompletionSource<T> Pending<T>() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static void StopDebounce(SettingsForm form) => BaseField<DispatcherTimer>(form,"debounce").Stop();
    private static void RequireBounds(FrameworkElement root)
    {
        Require(root.ActualWidth>0,"Owned provider form was not arranged.");
        foreach(var control in Elements<Control>(root).Where(value=>value.IsVisible && value.ActualWidth>0 && value.ActualHeight>0
            && (value is TextBox or ComboBox or PasswordBox or CheckBox or Button))) {
            var bounds=control.TransformToAncestor(root).TransformBounds(new Rect(new Point(),control.RenderSize));
            Require(double.IsFinite(bounds.Left) && bounds.Left>=-0.5 && bounds.Right<=root.ActualWidth+0.5,
                "Provider control exceeds its arranged horizontal bounds: "+control.GetType().Name+" "+bounds);
        }
        foreach(var text in Elements<TextBlock>(root).Where(value=>value.IsVisible && value.ActualWidth>0)) {
            var bounds=text.TransformToAncestor(root).TransformBounds(new Rect(new Point(),text.RenderSize));
            Require(bounds.Left>=-0.5 && bounds.Right<=root.ActualWidth+0.5,"Provider caption exceeds horizontal bounds: "+text.Text);
        }
    }
    private static async Task FocusOwnedAsync(Shown owner,FrameworkElement control)
    {
        owner.Window.UpdateLayout();await Turns();control.BringIntoView();owner.Window.UpdateLayout();await Turns();
        var bounds=control.TransformToAncestor(owner.View).TransformBounds(new Rect(new Point(),control.RenderSize));
        Require(control.IsLoaded && control.IsVisible && control.IsEnabled && control.Focusable
            && PresentationSource.FromVisual(control) is not null && bounds.Bottom>0 && bounds.Top<owner.View.ViewportHeight,
            "The owned provider-switch focus field was not rendered in its viewport.");
        owner.Window.Activate();await Turns();Keyboard.Focus(control);await Turns();
        Require(control.IsKeyboardFocused,"Owned provider-switch field did not obtain keyboard focus: active="+owner.Window.IsActive
            +", focused="+Keyboard.FocusedElement?.GetType().Name);
    }

    private sealed class Owned : IDisposable
    {
        internal readonly SettingsStore Store;
        internal readonly DeckController Controller;
        internal readonly RemoteAccountSettings Lab, GitHub;
        private readonly byte[] bytes;
        private readonly string settings;
        internal Owned(Application application, bool invalidGitHub=false)
        {
            Store = new(Path.Combine(Path.GetTempPath(), "devdeck-account-provider-" + Guid.NewGuid().ToString("N") + ".json"));
            Lab = new(LabID,"Owned GitLab","gitlab","https://gitlab.example.test/team",
                new[] { "legacy org", "comma,name", "", null! }.Concat(Enumerable.Range(0,65).Select(index => "legacy-"+index)).ToArray(),
                ["legacy repo", "too/many/parts", " owner/repo ", null!], NotifiesBlocked:true, NotifiesFailedRuns:true);
            GitHub = new(GitHubID,"Owned GitHub","github","https://api.github.com",
                invalidGitHub ? ["unchanged invalid org",null!] : ["owned-org"],
                invalidGitHub ? ["unchanged/invalid/repo",null!] : ["owned/repo"],NotifiesFailedRuns:true);
            Store.Save(new(1,[new(Distribution,"/owned/provider-runtime",Text.Language)],[],Accounts:[Lab,GitHub],
                RemoteCards:RemoteCardCatalog.All.Select(descriptor => new RemoteCardSettings(descriptor.Id,descriptor.Kind,descriptor.Kind,Distribution,
                    [descriptor.Provider == "gitlab" ? LabID : GitHubID],Enabled:descriptor.Kind is "mergeRequests" or "pullRequests")).ToArray(),
                Language:Text.Language,Notifications:true,SeenAlerts:["owned.retained.episode"]));
            Controller = new(application,Store,live:false);
            bytes = File.ReadAllBytes(Store.Path); settings = Json(Controller.Settings);
            Require(Json(Controller.Settings.AccountList.Single(value => value.Id == LabID)) == Json(Lab)
                && Lab.Organizations.Length > 64 && Lab.Organizations.Any(value => value is null)
                && Lab.Repositories.Any(value => value is null), "The settings-valid invalid-for-worker legacy fixture was not retained on load.");
        }
        internal void RequireUnchanged()
        {
            Require(File.ReadAllBytes(Store.Path).SequenceEqual(bytes) && Json(Controller.Settings) == settings
                && Controller.LastCheckedAt is null, "Provider presentation/request capture changed settings bytes or attention clock.");
            RequireIsolation();
        }
        internal void RequireIsolation()
        {
            var managers = typeof(DeckController).GetFields(BindingFlags.Instance|BindingFlags.NonPublic).Where(value => value.FieldType == typeof(WorkerManager));
            var count = managers.Sum(value => ((IDictionary)typeof(WorkerManager).GetField("workers",BindingFlags.Instance|BindingFlags.NonPublic)!
                .GetValue(value.GetValue(Controller))!).Count);
            Require(count == 0 && !Controller.LocalPollEnabled && !Controller.SharedPollEnabled
                && Field<object?>(Controller,"tray") is null, "Owned provider fixture started a worker, polling loop or notification tray.");
        }
        public void Dispose()
        {
            Controller.RemoteTokenReader = null; Controller.RemoteRequestSender = null;
            Controller.CloseViews();
            foreach (var file in new[] { Store.Path, Store.Path+".bak" }) if (File.Exists(file)) File.Delete(file);
        }
    }

    private sealed class Shown : IDisposable
    {
        internal Window Window { get; }
        internal ScrollViewer View { get; }
        internal Shown(UIElement content)
        {
            View=new() { Content=content,VerticalScrollBarVisibility=ScrollBarVisibility.Auto, HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled };
            Window = new() { Title="Owned account-provider check",Width=960,Height=720,ShowInTaskbar=false,Content=View };
            SettingsStyles.AddTo(Window.Resources);
            Window.Show(); Window.UpdateLayout();
        }
        public void Dispose() => Window.Close();
    }
    private static Grid AccountRow(DependencyObject panel, string label) => Elements<Grid>(panel)
        .Single(row => row.Children.OfType<TextBlock>().Any(value => value.Text == label));
    private static IEnumerable<T> Elements<T>(DependencyObject root) where T : DependencyObject
    {
        if (root is T match) yield return match;
        for (var index=0;index<VisualTreeHelper.GetChildrenCount(root);index++)
            foreach (var item in Elements<T>(VisualTreeHelper.GetChild(root,index))) yield return item;
    }
    private static T Field<T>(object owner,string name) => (T)owner.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(owner)!;
    private static T BaseField<T>(object owner,string name) => (T)typeof(SettingsForm).GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(owner)!;
    private static string Json<T>(T value) => JsonSerializer.Serialize(value,WorkerProtocol.Json);
    private static async Task Turns() { for(var turn=0;turn<3;turn++) await Dispatcher.Yield(DispatcherPriority.Background); }
    private static void Require(bool value,string message) { if(!value) throw new IOException(message); }
}
