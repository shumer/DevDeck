using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Actual ACC-03 production baselines. Dependencies and stores are owned/fake; no vault or worker is used.
internal static class AccountTokenActionTests
{
    private const string Distribution = "Owned Token Linux";
    private const string StoredValue = "Owned synthetic stored credential";
    private const string Replacement = "Owned half-entered replacement";

    // Historical scenarios remain separately runnable; the full owned suite has thirty groups.
    internal static async Task RunAsync(Application application, List<object> checks, string? scenario = null)
    {
        var language = Text.Language;
        try {
            Text.Use("en");
            if (scenario is not (null or "all")) {
                switch(scenario) {
                    case "creation": await CreationAsync(application,checks);break;
                    case "empty-existing":await EmptyExistingAsync(application,checks);break;
                    case "separate-stored":await SeparateStoredAsync(application,checks);break;
                    case "manager-route":await ManagerRouteBodyAsync(application);checks.Add(new{name="account.token.managerRoute",actualDefaultManagerRoute=true});break;
                    default:throw new ArgumentException("Unknown account-token scenario.",nameof(scenario));
                }
                return;
            }
            foreach(var locale in DevDeck.Windows.Core.Localization.Languages) {
                Text.Use(locale); await PresentationAsync(application,checks);await CreationPresentationAsync(application,checks);
            }
            Text.Use("en");
            await EnterpriseAsync(application,checks); await EnterpriseCancelAsync(application,checks);
            await EnterpriseHeldAsync(application,checks); await CreationLifetimeAsync(application,checks);
            await StoredProvidersAsync(application,checks); await CachedPresenceAsync(application,checks);
            await MissingReaderAsync(application,checks); await RejectionAsync(application,checks);
            await AcquisitionMatrixAsync(application,checks); await ReaderMutationAsync(application,checks);
            await ReplyMatrixAsync(application,checks); await PasswordRevisionAsync(application,checks);
            await AutosaveAsync(application,checks); await ManagerAsync(application,checks);
            await ReturnAsync(application,checks); await ReplacementAsync(application,checks);
            await ParentAsync(application,checks); await GlobalsAsync(application,checks);
        } finally { Text.Use(language); }
    }

    private static async Task CreationAsync(Application application, List<object> checks)
    {
        await using var owned = new Owned(application);
        await owned.ShowAsync();
        var before = owned.Capture();
        var create = Elements<Button>(owned.Form).SingleOrDefault(button =>
            AutomationProperties.GetAutomationId(button) == "account.token.create");
        if (create is not null) {
            Require(create.IsVisible && create.IsEnabled && ContentName(create).Length > 0,
                "The admitted creation action must have a real enabled, named control.");
            create.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            await Turns();
        }
        owned.RequireUnchanged(before);
        Require(create is not null && owned.Opened.Count == 1
            && owned.Opened[0] == ("chrome", "Profile 2", "https://github.com/settings/personal-access-tokens/new")
            && owned.ReadCalls == 0 && owned.Acquisitions == 0 && owned.StoredVerifications == 0
            && owned.ReplacementVerifications == 0 && owned.WriteCalls == 0 && owned.ChangedCalls == 0,
            "Actual account token creation is unavailable or does not route the current provider/browser/profile exactly once. "
            + owned.Facts(create is not null));
        checks.Add(new { name="account.token.creation", actualCreateButton=true, currentProviderBrowserProfile=true,
            noCredentialOrWorkerAccess=true, ownedSettingsAndPositiveGlobalsPreserved=true });
    }

    private static async Task EmptyExistingAsync(Application application, List<object> checks)
    {
        await using var owned = new Owned(application);
        await owned.ShowAsync();
        Require(owned.Form.TokenDraft.Length == 0 && owned.Form.InitialTokenPresent,
            "The committed cached-present account must start with an empty replacement.");
        var before = owned.Capture();
        // Existing real route, without the whole-action verifyToken override.
        await owned.Form.VerifyTokenAsync();
        await Turns();
        owned.RequireUnchanged(before);
        Require(owned.Acquisitions == 1 && owned.ReadCalls == 1 && owned.StoredVerifications == 1
            && owned.ReadTarget == owned.Account.CredentialTarget && owned.SubmittedTarget == owned.Account.CredentialTarget
            && owned.SubmittedEndpoint == owned.Account.Endpoint && owned.SubmittedValueWasStored
            && owned.Form.TokenDraft.Length == 0 && owned.WriteCalls == 0 && owned.ReplacementVerifications == 0
            && owned.ChangedCalls == 0,
            "Actual empty-existing VerifyTokenAsync rejects the stored credential instead of one exact read-only check. "
            + owned.Facts(true));
        checks.Add(new { name="account.token.emptyExisting", actualExistingVerifyRoute=true, exactSavedSlashTarget=true,
            oneAdmittedReadAndVerify=true, noCredentialOrMetadataWrite=true, positiveGlobalsPreserved=true });
    }

    private static async Task SeparateStoredAsync(Application application, List<object> checks)
    {
        await using var owned = new Owned(application);
        owned.Form.TokenDraft = Replacement;
        await owned.ShowAsync();
        var before = owned.Capture();
        var stored = Elements<Button>(owned.Form).SingleOrDefault(button =>
            AutomationProperties.GetAutomationId(button) == "account.token.verifyStored");
        if (stored is not null) {
            Require(stored.IsVisible && stored.IsEnabled && ContentName(stored).Length > 0,
                "A cached-present committed account must have an enabled, named stored Verify control.");
            stored.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            await Turns();
        }
        owned.RequireUnchanged(before);
        Require(stored is not null && owned.Acquisitions == 1 && owned.ReadCalls == 1 && owned.StoredVerifications == 1
            && owned.ReadTarget == owned.Account.CredentialTarget && owned.SubmittedValueWasStored
            && owned.Form.TokenDraft == Replacement && owned.WriteCalls == 0 && owned.ReplacementVerifications == 0
            && owned.ChangedCalls == 0,
            "The separate stored Verify action is missing or replaces/clears the half-entered password. "
            + owned.Facts(stored is not null));
        checks.Add(new { name="account.token.separateStored", actualStoredButton=true, storedValueSubmitted=true,
            replacementRetained=true, noCredentialOrMetadataWrite=true, positiveGlobalsPreserved=true });
    }

    private static async Task PresentationAsync(Application application,List<object> checks)
    {
        foreach(var provider in new[]{"github","gitlab"}) foreach(var present in new[]{true,false}) {
            await using var owned=new Owned(application,provider,present); owned.Window.Width=880;owned.Window.Height=440;owned.Window.FontSize=18;
            await owned.ShowAsync(); var before=owned.Capture();
            var create=Control(owned.Form,"account.token.create");var stored=Control(owned.Form,"account.token.verifyStored");
            Require(create.IsEnabled && stored.IsEnabled==present && AutomationProperties.GetName(create).Length>0
                && AutomationProperties.GetName(stored)==Text.L("windows.verifyStoredToken"),"Localized token controls lost names or cached eligibility.");
            Require(Result(owned).Text.Length==0 && Field<TextBlock>(owned.Form,"tokenPresence").Text.Contains(Text.L(present?"windows.tokenStored":"token.none"),StringComparison.Ordinal)
                && Elements<TextBlock>(owned.Form).All(text=>!text.Text.Contains(StoredValue,StringComparison.Ordinal)),"Presence text claims validity or exposes a stored credential.");
            HorizontalBounds(owned.Form,create);HorizontalBounds(owned.Form,stored);
            if(present) {
                var held=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                owned.VerifyHandler=(_,_,_)=>held.Task; var pending=owned.Form.VerifyStoredTokenAsync();
                Require(!pending.IsCompleted && !owned.Form.IsEnabled && !stored.IsEnabled && Field<TextBlock>(owned.Form,"tokenProgress").Text.Length>0,"Actual token pending state is absent.");
                held.SetResult();await pending;Require(Result(owned).Text==Text.L("token.works"),"Localized stored result is absent.");
            }
            owned.RequireUnchanged(before);
        }
        var dialog=new EnterpriseTokenAddressDialog("https://enterprise.example.test/api/v3") { FontSize=18 };
        try {
            dialog.Show();dialog.UpdateLayout();await Turns();
            Require(dialog.AddressInput.Text.Length==0 && !dialog.OpenButton.IsEnabled && dialog.CancelButton.IsDefault && dialog.CancelButton.IsCancel
                && AutomationProperties.GetAutomationId(dialog.AddressInput)=="account.token.enterpriseAddress"
                && AutomationProperties.GetName(dialog.AddressInput)==Text.L("windows.enterpriseTokenAddress")
                && !dialog.ShowInTaskbar && dialog.WindowStyle==WindowStyle.ToolWindow
                && Elements<TextBlock>(dialog).Any(text=>text.Text.Contains(dialog.APIEndpoint,StringComparison.Ordinal)),"Enterprise prompt lost exact API context, default-cancel, empty input or accessibility.");
            HorizontalBounds((FrameworkElement)((ScrollViewer)dialog.Content).Content,dialog.AddressInput);
            dialog.AddressInput.Text="https://enterprise.example.test/settings/tokens";Require(dialog.OpenButton.IsEnabled,"Valid owned Enterprise address is not admitted.");
            dialog.AddressInput.Text="http://enterprise.example.test/settings/tokens";Require(!dialog.OpenButton.IsEnabled,"Unsafe Enterprise address is enabled.");
        } finally {dialog.Close();}
        checks.Add(new{name="account.token.presentation."+Text.Language,actualProviderViews=true,minimumWidthFont18=true,pendingAndResult=true,enterpriseDefaultCancel=true});
    }
    private static async Task CreationPresentationAsync(Application application,List<object> checks)
    {
        foreach(var provider in new[]{"github","gitlab"}) {
            await using var owned=new Owned(application,provider,existing:false);
            ChooseOwnedBrowser(owned.Form);
            if(provider=="gitlab")Field<TextBox>(owned.Form,"endpoint").Text="https://gitlab.example.test/Customer/Prefix/";
            Field<TextBox>(owned.Form,"organizations").Text="invalid/name/for/creation";
            Field<TextBox>(owned.Form,"label").Text=""; await owned.ShowAsync();RequireOwnedBrowser(owned.Form);var before=owned.Capture();
            Control(owned.Form,"account.token.create").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));await Turns();
            var expected=provider=="github"?"https://github.com/settings/personal-access-tokens/new":"https://gitlab.example.test/Customer/Prefix/-/user_settings/personal_access_tokens?name=DevDeck&scopes=read_api";
            Require(owned.Opened.Count==1 && owned.Opened[0]==("chrome","Profile 2",expected) && owned.ReadCalls==0 && owned.Acquisitions==0 && owned.WriteCalls==0 && owned.ChangedCalls==0,
                "Creation incorrectly validates an unnamed account draft, discards the edited prefix or accesses credentials. "+CreationFacts(owned));
            owned.RequireUnchanged(before);
            Field<TextBox>(owned.Form,"label").Text="Owned valid browser draft";Field<TextBox>(owned.Form,"organizations").Text="owned";
            var test=Elements<Button>(owned.Form).Single(button=>ContentName(button)==Text.L("button.test"));
            test.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));await Turns();
            Require(owned.Opened.Count==2 && owned.Opened[1].Browser=="chrome" && owned.Opened[1].Profile=="Profile 2" && owned.Opened[1].Address!=expected,
                "Existing Browser Test no longer independently opens the current draft dashboard.");
        }
        checks.Add(new{name="account.token.creationViews."+Text.Language,unnamedDraft=true,currentGitLabPrefix=true,currentBrowser=true,noCredentialAccess=true,browserTestIndependent=true});
    }
    private static async Task EnterpriseAsync(Application application,List<object> checks)
    {
        await using var owned=new Owned(application,endpoint:"https://enterprise.example.test/api/v3");
        owned.PromptHandler=(_,_)=>Task.FromResult<string?>("https://enterprise.example.test/team/token-page");await owned.ShowAsync();var before=owned.Capture();
        await owned.Form.CreateTokenAsync();owned.RequireUnchanged(before);
        Require(owned.PromptCalls==1 && owned.Opened.Single()==("chrome","Profile 2","https://enterprise.example.test/team/token-page") && owned.ReadCalls==0 && owned.Acquisitions==0,"Enterprise creation guessed a host/path, persisted the address or skipped the explicit page.");
        checks.Add(new{name="account.token.enterprise",explicitHTTPSPage=true,oneOpenNoPersistence=true});
    }
    private static async Task EnterpriseCancelAsync(Application application,List<object> checks)
    {
        foreach(var value in new string?[]{null,"http://enterprise.example.test/tokens","https://user:pass@enterprise.example.test/tokens","https://enterprise.example.test/tokens?token=owned"}) {
            await using var owned=new Owned(application,endpoint:"https://enterprise.example.test/api/v3");
            owned.Form.TokenDraft=Replacement;owned.PromptHandler=(_,_)=>Task.FromResult(value);await owned.ShowAsync();var before=owned.Capture();
            await owned.Form.CreateTokenAsync();owned.RequireUnchanged(before);
            Require(owned.Opened.Count==0 && owned.PromptCalls==1 && owned.ReadCalls==0 && owned.Acquisitions==0,"Cancelled or unsafe Enterprise page opened or acquired credentials.");
        }
        var dialog=new EnterpriseTokenAddressDialog("https://enterprise.example.test/api/v3");dialog.Show();await Turns();dialog.AddressInput.Text="https://enterprise.example.test/tokens";
        Require(dialog.HandleKey(Key.Return,ModifierKeys.None) && dialog.SelectedAddress is null,"Default Return must cancel, not open an Enterprise page.");
        checks.Add(new{name="account.token.enterpriseCancel",unsafeAndCancelledInert=true,defaultReturnCancel=true,draftPreserved=true});
    }
    private static async Task EnterpriseHeldAsync(Application application,List<object> checks)
    {
        foreach(var mutation in new[]{"provider","endpoint","browser","profile","owner","epoch"}) {
            await using var owned=new Owned(application,existing:false,endpoint:"https://enterprise.example.test/api/v3");
            ChooseOwnedBrowser(owned.Form);
            Field<TextBox>(owned.Form,"endpoint").Text="https://enterprise.example.test/api/v3";
            var held=new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);owned.PromptHandler=(_,_)=>held.Task;
            await owned.ShowAsync();RequireOwnedBrowser(owned.Form);
            var capturedProvider=Field<ComboBox>(owned.Form,"provider").SelectedItem as string;
            var capturedEndpoint=Field<TextBox>(owned.Form,"endpoint").Text;var capturedGeneration=owned.generation;
            var pending=owned.Form.CreateTokenAsync();Require(!pending.IsCompleted && owned.PromptCalls==1,"Held Enterprise premise was not admitted. "+CreationFacts(owned));
            switch(mutation) {
                case "provider":Field<ComboBox>(owned.Form,"provider").SelectedItem="gitlab";break;
                case "endpoint":Field<TextBox>(owned.Form,"endpoint").Text="https://enterprise.example.test/other";break;
                case "browser":Field<BrowserPicker>(owned.Form,"browser").Picker.SelectedValue="system";break;
                case "profile":Field<BrowserPicker>(owned.Form,"browser").Profile.SelectedValue="Default";break;
                case "owner":owned.closed=true;break;
                default:owned.generation++;break;
            }
            Require(mutation switch {
                "provider"=>Field<ComboBox>(owned.Form,"provider").SelectedItem as string!=capturedProvider,
                "endpoint"=>Field<TextBox>(owned.Form,"endpoint").Text!=capturedEndpoint,
                "browser"=>Field<BrowserPicker>(owned.Form,"browser").BrowserID=="system",
                "profile"=>Field<BrowserPicker>(owned.Form,"browser").SelectedProfile=="Default",
                "owner"=>owned.closed,
                _=>owned.generation>capturedGeneration
            },"Owned held mutation did not change its captured "+mutation+" premise. "+CreationFacts(owned));
            var after=owned.Capture();held.SetResult("https://enterprise.example.test/tokens");await pending;
            owned.RequireUnchanged(after);Require(owned.Opened.Count==0 && owned.ReadCalls==0 && owned.Acquisitions==0,"Delayed Enterprise result opened a stale provider/browser/owner.");
        }
        checks.Add(new{name="account.token.enterpriseHeld",sixCapturedTupleChangesRejected=true,noLateOpen=true});
    }
    private static async Task CreationLifetimeAsync(Application application,List<object> checks)
    {
        foreach(var disposed in new[]{false,true}) {
            await using var owned=new Owned(application,endpoint:"https://enterprise.example.test/api/v3");
            var held=new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);owned.PromptHandler=(_,_)=>held.Task;
            await owned.ShowAsync();var first=owned.Form.CreateTokenAsync();await owned.Form.CreateTokenAsync();
            Require(owned.PromptCalls==1 && !first.IsCompleted,"Duplicate pending creation was admitted.");
            if(disposed)owned.Form.Dispose();else owned.closed=true;
            held.SetResult("https://enterprise.example.test/tokens");await first;
            Require(owned.Opened.Count==0 && owned.ReadCalls==0 && owned.WriteCalls==0,"Closed/disposed creation opened a late page.");
        }
        checks.Add(new{name="account.token.creationLifetime",duplicateClosedDisposedRejected=true});
    }
    private static async Task StoredProvidersAsync(Application application,List<object> checks)
    {
        foreach(var provider in new[]{"github","gitlab"}) {
            await using var owned=new Owned(application,provider,enabled:false);owned.Form.TokenDraft=Replacement;await owned.ShowAsync();
            Field<TextBox>(owned.Form,"label").Text="Owned unsaved label";
            Field<BrowserPicker>(owned.Form,"browser").Profile.SelectedValue="Default";
            var before=owned.Capture();await owned.Form.VerifyStoredTokenAsync();owned.RequireUnchanged(before);
            Require(owned.StoredVerifications==1 && owned.ReadCalls==1 && owned.SubmittedEndpoint==owned.Account.Endpoint
                && owned.SubmittedTarget==owned.Account.CredentialTarget && owned.Form.TokenDraft==Replacement && owned.PresenceCalls==1,
                "Disabled committed account or harmless label/browser draft prevented exact saved-target verification.");
        }
        checks.Add(new{name="account.token.storedProviders",disabledEditable=true,exactSavedSlash=true,metadataDraftNotIdentity=true});
    }
    private static async Task CachedPresenceAsync(Application application,List<object> checks)
    {
        await using var owned=new Owned(application,present:false);await owned.ShowAsync();var before=owned.Capture();
        Require(!Control(owned.Form,"account.token.verifyStored").IsEnabled,"Missing cached token enabled stored Verify.");
        owned.Form.ReconcileTokenPresence(true);Require(Control(owned.Form,"account.token.verifyStored").IsEnabled,"Known presence was not reconciled in place.");
        owned.Form.ReconcileTokenPresence(false);await owned.Form.VerifyStoredTokenAsync();owned.RequireUnchanged(before);
        Require(owned.ReadCalls==0 && owned.Acquisitions==0 && owned.StoredVerifications==0,"Cache rendering queried credentials or workers.");
        checks.Add(new{name="account.token.cachedPresence",booleanOnly=true,noImplicitRead=true,retainedControl=true});
    }
    private static async Task MissingReaderAsync(Application application,List<object> checks)
    {
        foreach(var mode in new[]{"null","empty","failure"}) {
            await using var owned=new Owned(application);owned.Form.TokenDraft=Replacement;
            owned.ReadHandler=_=>mode=="failure"?throw new HostFailure("credentialReadFailed","Do not expose owned credential diagnostics"):mode=="empty"?"":null;
            await owned.ShowAsync();var before=owned.Capture();await owned.Form.VerifyStoredTokenAsync();owned.RequireUnchanged(before);
            Require(owned.ReadCalls==1 && owned.StoredVerifications==0 && owned.WriteCalls==0 && owned.PresenceCalls==0 && Result(owned).Text.Length>0
                && !Result(owned).Text.Contains("Do not expose",StringComparison.Ordinal) && Control(owned.Form,"account.token.verifyStored").IsEnabled,
                "Missing/unreadable stored value was submitted, exposed diagnostics or confused cached presence with validity.");
        }
        checks.Add(new{name="account.token.missingReader",oneReadNoRPC=true,presenceNotValidity=true,sanitizedOwnResult=true});
    }
    private static async Task RejectionAsync(Application application,List<object> checks)
    {
        foreach(var code in new[]{"credentialsRejected","disconnected"}) {
            await using var owned=new Owned(application);owned.VerifyHandler=(account,_,_)=> {
                Require(account.Organizations.SequenceEqual(owned.Account.Organizations) && !ReferenceEquals(account.Organizations,owned.Account.Organizations),"Stored request did not own exact raw GitHub arrays.");
                return Task.FromException(new WorkerException(code,"Owned private server diagnostic"));
            };
            await owned.ShowAsync();var before=owned.Capture();await owned.Form.VerifyStoredTokenAsync();owned.RequireUnchanged(before);
            Require(owned.StoredVerifications==1 && owned.Acquisitions==1 && owned.ReadCalls==1 && owned.PresenceCalls==0 && Result(owned).Text.Length>0
                && !Result(owned).Text.Contains("Owned private",StringComparison.Ordinal),"Verifier error replayed or leaked transport diagnostics.");
        }
        checks.Add(new{name="account.token.rejection",noReplay=true,ownedRawGitHubArrays=true,sanitizedFailure=true});
    }
    private static void Mutate(Owned owned,string mutation)
    {
        switch(mutation) {
            case "removed":owned.ChangeSettings(current=>current with{Accounts=current.AccountList.Where(account=>account.Id!=owned.Account.Id).ToArray()});break;
            case "id":owned.ChangeSettings(current=>current with{Accounts=current.AccountList.Select(account=>account.Id==owned.Account.Id?account with{Id="changed.id"}:account).ToArray()});break;
            case "provider":owned.ChangeSettings(current=>current with{Accounts=current.AccountList.Select(account=>account.Id==owned.Account.Id?account with{Provider="gitlab"}:account).ToArray()});break;
            case "endpoint":owned.ChangeSettings(current=>current with{Accounts=current.AccountList.Select(account=>account.Id==owned.Account.Id?account with{Endpoint="https://changed.example.test"}:account).ToArray()});break;
            case "runtime":owned.ChangeSettings(current=>current with{Workers=[owned.Route with{RuntimeDirectory="/owned/changed"}]});break;
            case "language":owned.ChangeSettings(current=>current with{Workers=[owned.Route with{Language="de"}]});break;
            case "distribution":Field<ComboBox>(owned.Form,"distribution").ItemsSource=new[]{Distribution,"Changed Linux"};Field<ComboBox>(owned.Form,"distribution").SelectedItem="Changed Linux";break;
            case "owner":owned.closed=true;break;
            case "epoch":owned.generation++;break;
            default:throw new ArgumentException("Unknown owned mutation.",nameof(mutation));
        }
    }
    private static async Task AcquisitionMatrixAsync(Application application,List<object> checks)
    {
        foreach(var mutation in new[]{"removed","id","provider","endpoint","runtime","language","distribution","owner","epoch","wrongRoute"}) {
            await using var owned=new Owned(application);var held=new TaskCompletionSource<StoredTokenVerifier>(TaskCreationOptions.RunContinuationsAsynchronously);
            owned.AcquireHandler=(_,_)=>held.Task;await owned.ShowAsync();var pending=owned.Form.VerifyStoredTokenAsync();
            Require(!pending.IsCompleted && owned.Acquisitions==1 && owned.ReadCalls==0,"Held acquire was not a positive pre-read boundary.");
            if(mutation!="wrongRoute")Mutate(owned,mutation);var after=owned.Capture();
            held.SetResult(owned.Verifier(mutation=="wrongRoute"?owned.Route with{RuntimeDirectory="/owned/other"}:null));await pending;owned.RequireUnchanged(after);
            Require(owned.ReadCalls==0 && owned.StoredVerifications==0 && owned.PresenceCalls==0 && Result(owned).Text.Length==0,"Stale acquisition read/submitted/published to another identity or route.");
        }
        checks.Add(new{name="account.token.acquireAdmission",tenBoundaryChanges=true,noStaleReadOrRPC=true});
    }
    private static async Task ReaderMutationAsync(Application application,List<object> checks)
    {
        foreach(var mutation in new[]{"endpoint","runtime","owner","epoch"}) {
            await using var owned=new Owned(application);owned.ReadHandler=_=>{Mutate(owned,mutation);return StoredValue;};await owned.ShowAsync();
            await owned.Form.VerifyStoredTokenAsync();Require(owned.ReadCalls==1 && owned.StoredVerifications==0 && owned.PresenceCalls==0 && Result(owned).Text.Length==0 && owned.WriteCalls==0,"Synchronous reader mutation passed the final submission guard.");
        }
        checks.Add(new{name="account.token.readerAdmission",afterReadIdentityRouteOwnerGuard=true});
    }
    private static async Task ReplyMatrixAsync(Application application,List<object> checks)
    {
        foreach(var mutation in new[]{"removed","id","provider","endpoint","runtime","language","distribution","owner","epoch"}) foreach(var failure in new[]{false,true}) {
            await using var owned=new Owned(application);var held=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            owned.VerifyHandler=(account,value,_)=>{Require(account.Endpoint==owned.Account.Endpoint && value==StoredValue,"Admitted request was retargeted.");return held.Task;};
            await owned.ShowAsync();var pending=owned.Form.VerifyStoredTokenAsync();Require(owned.StoredVerifications==1 && !pending.IsCompleted,"Held RPC premise was not admitted.");
            Mutate(owned,mutation);var after=owned.Capture();if(failure)held.SetException(new WorkerException("credentialsRejected","Owned stale rejection"));else held.SetResult();
            await pending;owned.RequireUnchanged(after);Require(owned.PresenceCalls==0 && Result(owned).Text.Length==0 && owned.ReadCalls==1 && owned.StoredVerifications==1,"Late RPC result published to a stale target/owner or replayed.");
        }
        checks.Add(new{name="account.token.replyAdmission",immutableAdmittedRequest=true,eighteenLateResultsDiscarded=true});
    }
    private static async Task PasswordRevisionAsync(Application application,List<object> checks)
    {
        foreach(var stage in new[]{"acquire","rpc"}) {
            await using var owned=new Owned(application);var acquire=new TaskCompletionSource<StoredTokenVerifier>(TaskCreationOptions.RunContinuationsAsynchronously);var reply=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            if(stage=="acquire")owned.AcquireHandler=(_,_)=>acquire.Task;else owned.VerifyHandler=(_,_,_)=>reply.Task;
            await owned.ShowAsync();var pending=owned.Form.VerifyStoredTokenAsync();Require(!pending.IsCompleted,"Password revision fixture has no pending boundary.");
            owned.Form.TokenDraft=Replacement;var after=owned.Capture();if(stage=="acquire")acquire.SetResult(owned.Verifier());else reply.SetResult();await pending;
            owned.RequireUnchanged(after);Require(owned.Form.TokenDraft==Replacement && owned.PresenceCalls==0 && Result(owned).Text.Length==0 && owned.StoredVerifications==(stage=="rpc"?1:0),"Older token result cleared or validated the newer replacement.");
        }
        checks.Add(new{name="account.token.passwordRevision",newerDraftPreserved=true,noStaleResultOrPresence=true});
    }
    private static async Task AutosaveAsync(Application application,List<object> checks)
    {
        await using(var owned=new Owned(application)) {
            await owned.ShowAsync();Field<TextBox>(owned.Form,"label").Text="";await owned.Form.FlushAsync();
            var message=BaseField<TextBlock>(owned.Form,"Message").Text;var revision=BaseField<long>(owned.Form,"editRevision");var before=owned.Capture();
            Require(message.Length>0 && owned.Form.HasUncommittedChanges && BaseField<bool>(owned.Form,"saveFailed"),"Failed metadata premise is absent.");
            await owned.Form.VerifyStoredTokenAsync();
            Require(!BaseField<DispatcherTimer>(owned.Form,"debounce").IsEnabled,"Readonly stored check scheduled an automatic retry of unchanged failed metadata.");
            await Task.Delay(750);await Turns();owned.RequireUnchanged(before);
            Require(BaseField<TextBlock>(owned.Form,"Message").Text==message && BaseField<long>(owned.Form,"editRevision")==revision && BaseField<bool>(owned.Form,"saveFailed"),"Readonly token action erased/retried the failed autosave or its revision/error.");
        }
        await using(var owned=new Owned(application,endpoint:"https://api.github.com")) {
            await owned.ShowAsync();var gate=Field<SemaphoreSlim>(owned.Controller,"actions");await gate.WaitAsync();
            var held=new TaskCompletionSource<StoredTokenVerifier>(TaskCreationOptions.RunContinuationsAsynchronously);owned.AcquireHandler=(_,_)=>held.Task;
            Task flush;Task check;
            try {
                Field<TextBox>(owned.Form,"label").Text="First admitted metadata";flush=owned.Form.FlushAsync();
                Require(!flush.IsCompleted,"Existing metadata save did not wait on the owned action gate.");
                Field<TextBox>(owned.Form,"label").Text="Later retained metadata";check=owned.Form.VerifyStoredTokenAsync();
                await owned.Form.FlushAsync();Require(owned.Acquisitions==0 && !check.IsCompleted,"Token action failed to pause queued autosave before the admitted save completes.");
            } finally {gate.Release();}
            await flush;await Turns();Require(owned.Acquisitions==1 && owned.Controller.Settings.AccountList.Single(item=>item.Id==owned.Account.Id).Label=="First admitted metadata","Pause lost the admitted-save boundary or allowed another save during RPC.");
            held.SetResult(owned.Verifier());await check;await owned.Form.FlushAsync();
            Require(owned.Controller.Settings.AccountList.Single(item=>item.Id==owned.Account.Id).Label=="Later retained metadata" && !owned.Form.HasUncommittedChanges,"Later explicit flush lost the retained dirty revision.");
        }
        checks.Add(new{name="account.token.autosavePause",failedMessageAndRevisionRetained=true,noAutomaticFailureRetry=true,admittedSaveDrainedNoGateAcrossRPC=true,laterDirtyFlush=true});
    }
    private static async Task ManagerAsync(Application application,List<object> checks)
    {
        var receipt=Path.Combine(Path.GetTempPath(),"devdeck-token-wire-"+Guid.NewGuid().ToString("N")+".json");var creates=0;
        WorkerClient Create(WorkerSettings route) {
            creates++;var start=new ProcessStartInfo(Environment.ProcessPath ?? throw new IOException("Owned executable is unavailable."));
            if(Path.GetFileNameWithoutExtension(start.FileName).Equals("dotnet",StringComparison.OrdinalIgnoreCase))start.ArgumentList.Add(Assembly.GetEntryAssembly()!.Location);
            start.ArgumentList.Add("--account-token-fake-worker");start.ArgumentList.Add(receipt);return new(route.Distribution,start);
        }
        try {
            foreach(var provider in new[]{"github","gitlab"}) {
            var previousCreates=creates;
            await using var owned=new Owned(application,provider,workerFactory:Create,accountID:new string('a',128));await owned.ShowAsync();var before=owned.Capture();
            await owned.Form.VerifyStoredTokenAsync();owned.RequireUnchanged(before);
            Require(creates==previousCreates+1 && owned.ReadCalls==1 && owned.PresenceCalls==1 && Result(owned).Text==Text.L("token.works") && File.Exists(receipt),"Default real settingsChecks path did not use one owned fake client.");
            using var json=JsonDocument.Parse(File.ReadAllText(receipt));var root=json.RootElement;
            Require(root.GetProperty("operation").GetString()=="remote.verify" && root.GetProperty("cardID").GetString()=="verify"
                && root.GetProperty("accountIDLength").GetInt32()==128 && root.GetProperty("organizationCount").GetInt32()==(provider=="github"?2:0)
                && root.GetProperty("repositoryCount").GetInt32()==(provider=="github"?1:0),"Typed stored verification wire lost raw GitHub scopes or failed to project inactive GitLab scopes empty.");
            var managers=typeof(DeckController).GetFields(BindingFlags.Instance|BindingFlags.NonPublic).Where(field=>field.FieldType==typeof(WorkerManager));
            foreach(var manager in managers) {
                var count=((IDictionary)typeof(WorkerManager).GetField("workers",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(manager.GetValue(owned.Controller))!).Count;
                Require(count==(manager.Name=="settingsChecks"?1:0),"Stored verification adopted an owned client into a card/checkout channel.");
            }
            var clients=Field<object>(Field<WorkerManager>(owned.Controller,"settingsChecks"),"workers");
            var remoteKey=(ValueTuple<string,bool>)((IDictionary)clients).Keys.Cast<object>().Single();
            Require(remoteKey==(Distribution,true),"Stored verification entered the local-manager slot instead of the remote settings-check slot.");
            await owned.Form.VerifyStoredTokenAsync();owned.RequireUnchanged(before);
            using var second=JsonDocument.Parse(File.ReadAllText(receipt));
            Require(creates==previousCreates+1 && second.RootElement.GetProperty("helloCount").GetInt32()==1 && second.RootElement.GetProperty("verifyCount").GetInt32()==2,
                "Second explicit stored check reconnected/replayed hello instead of reusing the captured settings-check channel.");
            }
        } finally {if(File.Exists(receipt))File.Delete(receipt);}
        await ManagerRouteBodyAsync(application);
        checks.Add(new{name="account.token.realManager",ownedFakeChildOnly=true,isolatedSettingsChecks=true,maxID128=true,noCardAdoptionOrMetadata=true,changedRouteExact=true});
    }
    private static async Task ManagerRouteBodyAsync(Application application)
    {
        var receipt=Path.Combine(Path.GetTempPath(),"devdeck-token-route-"+Guid.NewGuid().ToString("N")+".json");
        var created=new List<WorkerSettings>();
        WorkerClient Create(WorkerSettings route) {
            created.Add(route);var start=new ProcessStartInfo(Environment.ProcessPath ?? throw new IOException("Owned executable is unavailable."));
            if(Path.GetFileNameWithoutExtension(start.FileName).Equals("dotnet",StringComparison.OrdinalIgnoreCase))start.ArgumentList.Add(Assembly.GetEntryAssembly()!.Location);
            start.ArgumentList.Add("--account-token-fake-worker");start.ArgumentList.Add(receipt);return new(route.Distribution,start);
        }
        try {
            await using var owned=new Owned(application,workerFactory:Create);await owned.ShowAsync();
            await owned.Form.VerifyStoredTokenAsync();
            Require(created.Count==1 && created[0]==owned.Route && owned.ReadCalls==1 && owned.PresenceCalls==1 && Result(owned).Text==Text.L("token.works"),
                "Exact-route baseline did not first acquire the actual old configured settings-check client.");
            var changedRoute=owned.Route with{RuntimeDirectory="/owned/token-runtime-new"};
            owned.ChangeSettings(current=>current with{Workers=[changedRoute]});var before=owned.Capture();
            await owned.Form.VerifyStoredTokenAsync();owned.RequireUnchanged(before);
            Require(created.Count==2 && created[1]==changedRoute && owned.ReadCalls==2 && owned.PresenceCalls==2 && Result(owned).Text==Text.L("token.works"),
                "Actual stored verification reused a cached worker from a different configured route. "+Json(new{created=created.Count,reads=owned.ReadCalls,presence=owned.PresenceCalls}));
        } finally {if(File.Exists(receipt))File.Delete(receipt);}
    }
    internal static int RunFakeWorker(string[] args)
    {
        var index=Array.IndexOf(args,"--account-token-fake-worker");if(index<0 || index+1>=args.Length)return 2;
        var receipt=args[index+1];var helloCount=0;var verifyCount=0;
        var frames=new BoundedFrameReader(Console.OpenStandardInput());
        for(var count=0;count<32;count++) {
            using var deadline=new CancellationTokenSource(TimeSpan.FromSeconds(15));
            byte[]? frame;
            try {frame=frames.ReadAsync(deadline.Token).GetAwaiter().GetResult();}
            catch(OperationCanceledException){return 2;}
            if(frame is null)return 0;
            var request=JsonSerializer.Deserialize<WorkerRequest>(frame,WorkerProtocol.Json);if(request is null)return 2;
            WorkerFailure? error=null;
            if(request.Operation=="remote.verify") {
                var credential=request.Remote?.Accounts?.SingleOrDefault();
                if(credential is null || credential.Token!=StoredValue)error=new("credentialsRejected","Owned fake rejected credential");
                else {verifyCount++;File.WriteAllText(receipt,Json(new{operation=request.Operation,cardID=request.Remote!.CardID,accountIDLength=credential.Id.Length,organizationCount=credential.Organizations.Length,repositoryCount=credential.Repositories.Length,helloCount,verifyCount}));}
            } else if(request.Operation=="hello")helloCount++;else error=new("unsupportedOperation","Owned fake operation unavailable");
            Console.WriteLine(Json(new WorkerResponse(1,request.Id,Distribution,["remote.verify"],null,null,error)));Console.Out.Flush();
        }
        return 0;
    }
    private static async Task ReturnAsync(Application application,List<object> checks)
    {
        await using(var owned=new Owned(application)) {
            await owned.ShowAsync();var before=owned.Capture();var password=Field<PasswordBox>(owned.Form,"token");
            await FocusAsync(owned.Window,password);
            Require(password.IsKeyboardFocused,"Owned Return target has no actual keyboard focus.");
            await password.Dispatcher.InvokeAsync(()=>password.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice,PresentationSource.FromVisual(password)!,Environment.TickCount,Key.Return){RoutedEvent=Keyboard.KeyDownEvent}),DispatcherPriority.Input);
            await Turns();owned.RequireUnchanged(before);Require(owned.StoredVerifications==1 && owned.ReadCalls==1 && owned.WriteCalls==0,"Queued owned WPF Return did not use the empty-existing stored route exactly once.");
        }
        await using(var owned=new Owned(application,existing:false,present:false)) {
            await owned.ShowAsync();var before=owned.Capture();await owned.Form.VerifyTokenAsync();owned.RequireUnchanged(before);
            Require(owned.ReadCalls==0 && owned.Acquisitions==0 && owned.WriteCalls==0 && BaseField<TextBlock>(owned.Form,"Message").Text.Length>0,"Empty new account read credentials or committed metadata.");
        }
        checks.Add(new{name="account.token.return",ownedQueuedWPFReturn=true,existingReadOnly=true,newEmptyStillNeedsToken=true});
    }
    private static async Task ReplacementAsync(Application application,List<object> checks)
    {
        await using var owned=new Owned(application);owned.Form.TokenDraft=Replacement;await owned.ShowAsync();var before=owned.Capture();
        Control(owned.Form,"account.token.verifyStored").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));await Turns();owned.RequireUnchanged(before);
        Require(owned.StoredVerifications==1 && owned.SubmittedValueWasStored && owned.Form.TokenDraft==Replacement,"Separate stored button used the replacement.");
        await owned.Form.VerifyTokenAsync();
        Require(owned.ReplacementVerifications==1 && owned.WriteCalls==2 && owned.ChangedCalls==1 && owned.Form.TokenDraft.Length==0
            && owned.Form.CommittedTokenAccount?.Endpoint==owned.Account.Endpoint.TrimEnd('/') && Control(owned.Form,"account.token.verifyStored").IsEnabled,
            "Ordinary nonempty replacement lost verify/write/persist/old-target cleanup or current presence ordering.");
        checks.Add(new{name="account.token.replacement",separateStoredRetainsDraft=true,legacyReplacementAndOldTargetCleanup=true});
    }
    private static async Task ParentAsync(Application application,List<object> checks)
    {
        foreach(var scenario in new[]{"success","failed-selection","failed-close","native-close","closing-wait","new-commit"}) {
            await using var owned=new Owned(application);await owned.ShowAsync();var reads=0;var queries=0;
            TaskCompletionSource? held=null;AccountSettingsForm? currentForm=null;SettingsWindow.AccountFormBinding? currentBinding=null;
            var written=new HashSet<string>(StringComparer.Ordinal);
            var parent=new SettingsWindow(owned.Controller,live:true,
                tokenAvailable:account=>{queries++;return account.Id==owned.Account.Id || written.Contains(account.CredentialTarget);},accountFormFactory:binding=> {
                currentBinding=binding;
                currentForm=new(binding.Controller,binding.Account,binding.Live,binding.Changed,binding.NewProvider,binding.Confirmation,
                    credentialChanged:binding.CredentialChanged,verifyCredential:(_,_,_,_)=>Task.CompletedTask,credentialWriter:(account,_)=>written.Add(account.CredentialTarget),
                    discoverDistributions:_=>Task.FromResult(new[]{Distribution}),browserOpener:(_,_,_)=>{},browserPickerFactory:FakeBrowser,
                    tokenPresent:binding.TokenPresent,ownerCurrent:binding.OwnerCurrent,storedCredentialReader:_=>{reads++;return StoredValue;},
                    acquireStoredVerifier:(route,_)=>Task.FromResult(new StoredTokenVerifier(route,(_,_,_)=>held?.Task ?? Task.CompletedTask)),
                    storedPresenceChanged:binding.PresenceChanged,enterpriseAddressPrompt:(_,_)=>Task.FromResult<string?>(null),ownerGeneration:binding.OwnerGeneration);
                return currentForm;
            });
            SetField(owned.Controller,"settingsWindow",parent);
            try {
                parent.Show();await parent.SelectPageAsync(scenario=="new-commit"?"new-account":"account:"+owned.Account.Id);await Turns();
                var form=currentForm ?? throw new IOException("Owned retained parent account form missing.");
                var binding=currentBinding ?? throw new IOException("Owned parent binding missing.");
                var initialQueries=queries;var generation=binding.OwnerGeneration();
                if(scenario=="new-commit") {
                    Field<TextBox>(form,"label").Text="Owned newly committed token account";form.TokenDraft=Replacement;
                    await form.VerifyTokenAsync();var committed=form.CommittedTokenAccount;
                    Require(committed is not null && ReferenceEquals(parent.Page.Content,form) && parent.SelectedPage=="account:"+committed.Id
                        && binding.OwnerGeneration()==generation && binding.OwnerCurrent() && written.Contains(committed.CredentialTarget)
                        && Field<Dictionary<string,bool>>(parent,"tokenAvailability")[committed.CredentialTarget]
                        && Control(form,"account.token.verifyStored").IsEnabled && queries==initialQueries+1 && reads==0,
                        "New-account commit replaced its form/epoch or lost exact-target cached credential presence.");
                    await form.VerifyStoredTokenAsync();Require(reads==1 && queries==initialQueries+1 && ReferenceEquals(parent.Page.Content,form),"Newly committed retained binding could not perform one stored check.");
                    continue;
                }
                form.TokenDraft=Replacement;
                if(scenario=="closing-wait") {
                    var saveGate=BaseField<SemaphoreSlim>(form,"saveGate");await saveGate.WaitAsync();
                    Task<bool> close;
                    try {
                        close=parent.CloseSettingsAsync();Require(!close.IsCompleted && !form.FormDisposed && parent.IsVisible && binding.OwnerGeneration()>generation && !binding.OwnerCurrent(),
                            "Explicit close did not invalidate currentness before waiting for an owned Flush gate.");
                        await form.VerifyStoredTokenAsync();Require(reads==0,"Closing alive form admitted a stored credential read.");
                    } finally {saveGate.Release();}
                    Require(await close,"Owned close did not finish after releasing Flush gate.");continue;
                }
                if(scenario!="success") {
                    Field<TextBox>(form,"label").Text="";await form.FlushAsync();
                    Require(form.HasUncommittedChanges && BaseField<TextBlock>(form,"Message").Text.Length>0,"Failed-transition metadata premise is absent.");
                }
                var message=BaseField<TextBlock>(form,"Message").Text;
                held=new(TaskCreationOptions.RunContinuationsAsynchronously);var pending=form.VerifyStoredTokenAsync();
                Require(!pending.IsCompleted && reads==1,"Actual parent held verifier was not pending.");
                if(scenario=="success") {
                    var cache=Field<Dictionary<string,bool>>(parent,"tokenAvailability");var sibling=owned.Controller.Settings.AccountList.First(account=>account.Id!=owned.Account.Id);
                    Require(cache[owned.Account.CredentialTarget] && !cache[sibling.CredentialTarget],"Selected/sibling cached presence prerequisites are not distinct.");
                    cache[owned.Account.CredentialTarget]=false;
                    var search=parent.Search;search.Text="Owned";await FocusAsync(parent,search);search.CaretIndex=2;
                    var before=owned.Capture();held.SetResult();await pending;owned.RequireUnchanged(before);
                    Require(cache[owned.Account.CredentialTarget] && !cache[sibling.CredentialTarget] && queries==initialQueries
                        && ReferenceEquals(parent.Page.Content,form) && search.IsKeyboardFocused && search.Text=="Owned" && search.CaretIndex==2 && form.TokenDraft==Replacement,
                        "Stored callback failed exact-target cache update, sibling preservation or retained search/draft focus.");
                    binding.PresenceChanged(sibling,true);Require(!cache[sibling.CredentialTarget],"Forged sibling presence bypassed committed binding guard.");
                    var beforeEpoch=binding.OwnerGeneration();
                    Task.Run(()=>binding.PresenceChanged(owned.Account,false)).GetAwaiter().GetResult();
                    await parent.SelectPageAsync("deck");await Turns();
                    Require(form.FormDisposed && binding.OwnerGeneration()>beforeEpoch && cache[owned.Account.CredentialTarget] && queries==initialQueries,
                        "Queued old presence callback survived actual selection/epoch replacement.");
                } else {
                    if(scenario=="native-close") {
                        parent.Close();Require(!form.FormDisposed && binding.OwnerGeneration()>generation && Field<int>(parent,"tokenOwnerTransitions")>0 && !binding.OwnerCurrent(),
                            "Native Closing did not invalidate the alive form before Dispatcher.Yield.");await Turns();
                    } else if(scenario=="failed-close")Require(!await parent.CloseSettingsAsync(),"Invalid metadata close unexpectedly discarded the draft.");
                    else await parent.SelectPageAsync("deck");
                    Require(parent.IsVisible && ReferenceEquals(parent.Page.Content,form) && parent.SelectedPage=="account:"+owned.Account.Id
                        && binding.OwnerGeneration()>generation && binding.OwnerCurrent() && !form.FormDisposed,
                        "Refused transition did not restore the same draft with a newer token-owner epoch.");
                    var cacheBefore=Json(Field<Dictionary<string,bool>>(parent,"tokenAvailability"));held.SetResult();await pending;
                    Require(ResultText(form).Length==0 && queries==initialQueries && Json(Field<Dictionary<string,bool>>(parent,"tokenAvailability"))==cacheBefore
                        && BaseField<TextBlock>(form,"Message").Text==message && form.TokenDraft==Replacement,
                        "Refused-transition ABA revived an old result/cache callback or erased the invalid draft/error.");
                }
            } finally {
                if(currentForm is {FormDisposed:false})currentForm.Dispose();
                SetField(parent,"form",null);parent.Page.Content=null;
                if(!parent.GeometryOwnerClosed)await parent.CloseSettingsAsync();SetField(owned.Controller,"settingsWindow",null);
            }
        }
        checks.Add(new{name="account.token.parent",actualRetainedBindings=true,exactCacheAndSiblingGuard=true,searchFocusPreserved=true,
            failedSelectionAndCloseABA=true,nativeClosingBeforeYield=true,explicitCloseHeldFlush=true,newCommitRetainsEpochAndForm=true});
    }
    private static async Task GlobalsAsync(Application application,List<object> checks)
    {
        await using var owned=new Owned(application);await owned.ShowAsync();
        var configured=owned.Controller.Settings.RemoteCardList.First(card=>card.Kind=="pullRequests");
        var remote=new RemoteCard(owned.Controller,configured,live:false,snapshotReader:_=>throw new IOException("Readonly token test must not poll a card."));
        Field<List<RemoteCard>>(owned.Controller,"remoteCards").Add(remote);Field<Dictionary<string,RemoteCardSettings>>(owned.Controller,"remoteConfigurations")[configured.Id]=configured;
        remote.ApplySnapshot(new(configured.Id,configured.Kind,0,0,null,[],[],false));new WindowInteropHelper(remote).EnsureHandle();remote.SetDeckVisible(false);
        var remoteHwnd=new WindowInteropHelper(remote).Handle;var remoteSnapshot=remote.Latest;
        Require(remoteHwnd!=0 && remoteSnapshot is not null && !remote.IsVisible,"Positive hidden remote owner prerequisite is absent.");
        var gate=Field<SemaphoreSlim>(owned.Controller,"actions");await gate.WaitAsync();
        try {
            var before=owned.Capture();await owned.Form.VerifyStoredTokenAsync().WaitAsync(TimeSpan.FromSeconds(5));owned.RequireUnchanged(before);
            Require(owned.StoredVerifications==1 && new WindowInteropHelper(remote).Handle==remoteHwnd && ReferenceEquals(remote.Latest,remoteSnapshot) && !remote.IsVisible,
                "Read-only action waited behind a global gate or replaced/refreshed the positive hidden remote owner.");
        } finally {gate.Release();}
        var hwnd=new WindowInteropHelper(owned.LocalOwner).Handle;owned.CompleteRead();await owned.AwaitReadAsync();
        Require(owned.LocalOwner.Latest?.State=="running" && new WindowInteropHelper(owned.LocalOwner).Handle==hwnd && !owned.LocalOwner.IsVisible,
            "The retained pending card read failed to remain eligible after explicit stored verification.");
        checks.Add(new{name="account.token.globalPreservation",positiveSeenAttentionPendingQueueActiveDelivery=true,hiddenOwnerHWNDPreserved=true,heldGlobalGateIndependent=true,laterReadCompletes=true});
    }
    private static BrowserPicker FakeBrowser(string id,string? profile)=>new(id,profile,[new("chrome","Owned Chrome",@"C:\Fixture\chrome.exe",true)],_=>[new("Default","Default"),new("Profile 2","Owned profile")]);
    private static void ChooseOwnedBrowser(AccountSettingsForm form)
    {
        var browser=Field<BrowserPicker>(form,"browser");browser.Picker.SelectedValue="chrome";browser.Profile.SelectedValue="Profile 2";
        RequireOwnedBrowser(form);
    }
    private static void RequireOwnedBrowser(AccountSettingsForm form)
    {
        var browser=Field<BrowserPicker>(form,"browser");
        Require(browser.BrowserID=="chrome" && browser.SelectedProfile=="Profile 2","Owned creation fixture did not establish its chosen browser/profile premise.");
    }
    private static string CreationFacts(Owned owned)
    {
        var browser=Field<BrowserPicker>(owned.Form,"browser");
        return Json(new{provider=Field<ComboBox>(owned.Form,"provider").SelectedItem,browser=browser.BrowserID,profile=browser.SelectedProfile,
            opened=owned.Opened.Select(value=>new{value.Browser,value.Profile,value.Address}).ToArray(),reads=owned.ReadCalls,acquisitions=owned.Acquisitions,writes=owned.WriteCalls,changed=owned.ChangedCalls});
    }
    private static Button Control(AccountSettingsForm form,string id)=>Elements<Button>(form).Single(button=>AutomationProperties.GetAutomationId(button)==id);
    private static TextBlock Result(Owned owned)=>Field<TextBlock>(owned.Form,"tokenResult");
    private static string ResultText(AccountSettingsForm form)=>Field<TextBlock>(form,"tokenResult").Text;
    private static async Task FocusAsync(Window owner,FrameworkElement control)
    {
        await Turns();owner.UpdateLayout();control.BringIntoView();await Turns();owner.UpdateLayout();
        Require(control.IsLoaded && control.IsVisible && control.IsEnabled && control.Focusable && PresentationSource.FromVisual(control) is not null && control.ActualWidth>0,
            "Owned keyboard target is not rendered and reachable.");
        owner.Activate();await Turns();Keyboard.Focus(control);await Turns();
        Require(control.IsKeyboardFocused,"Owned rendered keyboard target did not receive focus.");
    }
    private static void HorizontalBounds(FrameworkElement root,FrameworkElement control)
    {
        root.UpdateLayout();var bounds=control.TransformToAncestor(root).TransformBounds(new Rect(new Point(),control.RenderSize));
        Require(control.ActualWidth>0 && bounds.Left>=-1 && bounds.Right<=root.ActualWidth+1,"Named token control clips horizontal content bounds.");
    }
    private static T BaseField<T>(object owner,string name)
    {
        for(var type=owner.GetType();type is not null;type=type.BaseType)
            if(type.GetField(name,BindingFlags.Instance|BindingFlags.NonPublic|BindingFlags.DeclaredOnly) is { } field)return (T)field.GetValue(owner)!;
        throw new IOException("Owned field missing: "+name);
    }
    private sealed class Owned : IAsyncDisposable
    {
        internal readonly SettingsStore Store;
        internal readonly DeckController Controller;
        internal readonly RemoteAccountSettings Account;
        internal readonly WorkerSettings Route;
        internal readonly AccountSettingsForm Form;
        internal readonly Window Window;
        internal readonly ProjectCard LocalOwner;
        internal readonly List<(string Browser,string? Profile,string Address)> Opened = [];
        internal int ReadCalls, Acquisitions, StoredVerifications, ReplacementVerifications, WriteCalls, ChangedCalls, PresenceCalls;
        internal string? ReadTarget, SubmittedTarget, SubmittedEndpoint;
        internal bool SubmittedValueWasStored;
        internal bool closed;
        internal long generation;
        internal Func<RemoteAccountSettings,string?>? ReadHandler;
        internal Func<WorkerSettings,CancellationToken,Task<StoredTokenVerifier>>? AcquireHandler;
        internal Func<RemoteAccountSettings,string,CancellationToken,Task>? VerifyHandler;
        internal Func<string,CancellationToken,Task<string?>> PromptHandler = (_,_)=>throw new IOException("Hosted baseline must not prompt for Enterprise.");
        internal int PromptCalls;
        private readonly bool realManager;
        private readonly TaskCompletionSource<WorkerResponse> read = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private Task? pendingRead;
        private CancellationToken pendingReadToken;

        internal Owned(Application application,string provider="github",bool present=true,bool existing=true,string? endpoint=null,
            bool enabled=true,Func<WorkerSettings,WorkerClient>? workerFactory=null,string? accountID=null)
        {
            Store = new(Path.Combine(Path.GetTempPath(), "devdeck-account-token-" + Guid.NewGuid().ToString("N") + ".json"));
            Route = new(Distribution, "/owned/token-runtime", Text.Language);
            Account = new(accountID ?? "owned.token.github", "Owned token account", provider, endpoint ?? (provider=="github" ? "https://api.github.com/" : "https://gitlab.example.test/team/"),
                ["retained", "retained"], ["owned/repo"], Browser:"chrome", BrowserProfile:"Profile 2");
            Account=Account with { Enabled=enabled };
            if(provider=="gitlab")Account=Account with { Organizations=["legacy inactive",null!,"legacy inactive"],Repositories=["legacy/inactive",null!],NotifiesFailedRuns=true };
            var lab = new RemoteAccountSettings("owned.token.lab", "Owned other account", "gitlab", "https://gitlab.example.test",
                ["legacy inactive", null!], ["legacy/inactive"], NotifiesFailedRuns:true);
            var local = new CardSettings(new("owned.token.local", Distribution, "local", "/owned/token-checkout",
                Title:"Owned retained card"), "Owned retained card", Enabled:false);
            var cards = RemoteCardCatalog.All.Select(descriptor => new RemoteCardSettings(descriptor.Id,
                descriptor.Kind, descriptor.Kind, Distribution, existing ? descriptor.Provider==provider ? [Account.Id] : descriptor.Provider=="gitlab" ? [lab.Id] : [] : [],
                Enabled:existing && (descriptor.Provider==provider || descriptor.Provider=="gitlab") && descriptor.Kind is "pullRequests" or "mergeRequests")).ToArray();
            var seed = new DeckSettings(1, [Route], [local], Language:Text.Language, Notifications:true,
                SeenAlerts:["owned.token.retained.episode"], Accounts:existing ? [Account,lab] : [lab], RemoteCards:cards);
            Store.Save(seed); Store.Save(seed); // Positive preexisting owned backup, not an empty-byte preservation assertion.
            realManager=workerFactory is not null;
            Controller = new(application, Store, live:false,settingsCheckWorkerFactory:workerFactory);
            LocalOwner = new(Controller, Controller.Settings.Cards[0], live:false, statusReader:(_, cancellation) => {
                pendingReadToken = cancellation; return read.Task;
            });
            Field<List<ProjectCard>>(Controller,"cards").Add(LocalOwner);
            Field<Dictionary<string,CardSettings>>(Controller,"localConfigurations")[local.Project.Id] = local;
            LocalOwner.ApplySnapshot(Status());
            new WindowInteropHelper(LocalOwner).EnsureHandle();
            SeedGlobals();
            Form = new(Controller, existing ? Account : null, live:true, changed:_ => ChangedCalls++,newProvider:provider,
                verifyCredential:(_,_,_,_) => { ReplacementVerifications++; return Task.CompletedTask; },
                credentialWriter:(_,_) => WriteCalls++,
                discoverDistributions:_ => Task.FromResult(new[] { Distribution }),
                browserOpener:(browser,profile,address) => Opened.Add((browser,profile,address)),
                browserPickerFactory:(browser,profile) => new(browser,profile,
                    [new("chrome","Owned Chrome",@"C:\Fixture\chrome.exe",true)],
                    _ => [new("Default","Default"), new("Profile 2","Owned profile")]),
                tokenPresent:present, ownerCurrent:() => !closed,
                storedCredentialReader:account => {
                    ReadCalls++; ReadTarget=account.CredentialTarget; return ReadHandler is null ? StoredValue : ReadHandler(account);
                }, acquireStoredVerifier:realManager ? null : (route,cancellation) => {
                    Require(route == Route && cancellation.CanBeCanceled && !cancellation.IsCancellationRequested,
                        "Stored verification acquisition lost the exact configured route/lifetime.");
                    Acquisitions++;
                    return AcquireHandler is null ? Task.FromResult(Verifier()) : AcquireHandler(route,cancellation);
                }, storedPresenceChanged:(_,_) => PresenceCalls++,
                enterpriseAddressPrompt:(address,cancellation)=> { PromptCalls++; return PromptHandler(address,cancellation); },
                ownerGeneration:() => generation);
            var scroll = new ScrollViewer { Content=Form, VerticalScrollBarVisibility=ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled };
            Window = new() { Title="Owned account-token fixture", Width=1020, Height=720, ShowInTaskbar=false, Content=scroll };
            SettingsStyles.AddTo(Window.Resources);
        }
        internal StoredTokenVerifier Verifier(WorkerSettings? route=null) => new(route ?? Route,(account,value,token) => {
                        Require(token.CanBeCanceled && !token.IsCancellationRequested,
                            "Stored verification submitted without the current owned lifetime.");
                        StoredVerifications++; SubmittedTarget=account.CredentialTarget; SubmittedEndpoint=account.Endpoint;
                        SubmittedValueWasStored=value == StoredValue;
                        return VerifyHandler?.Invoke(account,value,token) ?? Task.CompletedTask;
                    });
        internal void ChangeSettings(Func<DeckSettings,DeckSettings> change) => typeof(DeckController).GetProperty("Settings",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(Controller,change(Controller.Settings));
        internal void CompleteRead()=>read.TrySetResult(new(1,"owned-token-status",Distribution,null,Status(),null,null));
        internal Task AwaitReadAsync()=>pendingRead?.WaitAsync(TimeSpan.FromSeconds(5)) ?? Task.CompletedTask;

        internal async Task ShowAsync()
        {
            Window.Show(); Window.UpdateLayout(); await Turns();
            Require(Window.IsVisible && Form.IsLoaded && Form.IsVisible && Form.IsEnabled
                && PresentationSource.FromVisual(Form) is not null && Form.ActualWidth > 0
                && Field<PasswordBox>(Form,"token").IsVisible && Field<ComboBox>(Form,"distribution").SelectedItem as string == Distribution,
                "The actual English provider form/token/route must render before the baseline action.");
            pendingRead ??= LocalOwner.RefreshAsync(); LocalOwner.SetDeckVisible(false); await Turns();
            Require(pendingRead is { IsCompleted:false } && pendingReadToken.CanBeCanceled
                && !pendingReadToken.IsCancellationRequested && LocalOwner.Latest?.State == "running"
                && new WindowInteropHelper(LocalOwner).Handle != 0 && !LocalOwner.IsVisible,
                "The owned hidden cached HWND/snapshot and injected pending read must be positive prerequisites.");
            Require(Controller.Settings.AnnouncedAlerts.Length > 0 && Controller.LastCheckedAt is not null
                && Field<AttentionTracker>(Controller,"attention").SignalItems.Length > 0
                && Field<IList>(Controller,"pendingAlerts").Count > 0
                && ((IEnumerable)Field<object>(Controller,"deliveries")).Cast<object>().Any()
                && File.Exists(Store.Path+".bak") && new FileInfo(Store.Path+".bak").Length > 0,
                "The preservation fixture must have actual retained Seen/clock/attention/pending/queue and backup state.");
            Require(ReadCalls == 0 && Acquisitions == 0 && StoredVerifications == 0 && WriteCalls == 0,
                "Construction or Loaded read a credential/acquired a verifier before explicit action.");
            RequireIsolation();
        }

        private void SeedGlobals()
        {
            Field<AttentionTracker>(Controller,"attention").Observe(new AttentionSnapshot("local:"+Distribution,
                [new("owned.token.attention","owned.token.key","waiting","github","Owned waiting work","Owned facts",1000,
                    new("none"),false,false)],[]));
            var alert = new DeckAlert("owned.token.pending","cantCheck","owned.token.local","Owned pending",
                "Owned detail","Owned body","",new("menu"),true);
            var scopedType=typeof(DeckController).GetNestedType("ScopedAlert",BindingFlags.NonPublic)!;
            var scoped=Activator.CreateInstance(scopedType,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,
                null,["local:"+Distribution,alert],null)!;
            Field<IList>(Controller,"pendingAlerts").Add(scoped);
            var sources=Array.CreateInstance(scopedType,1); sources.SetValue(scoped,0);
            var deliveryType=typeof(DeckController).GetNestedType("Delivery",BindingFlags.NonPublic)!;
            var delivery=Activator.CreateInstance(deliveryType,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,
                null,[sources,false],null)!;
            var queue=Field<object>(Controller,"deliveries"); queue.GetType().GetMethod("Enqueue")!.Invoke(queue,[delivery]);
            SetField(Controller,"activeDelivery",delivery); SetField(Controller,"activeAlert",alert);
            SetField(Controller,"lastCheckedAt",DateTimeOffset.FromUnixTimeSeconds(1000));
        }

        internal string Capture(bool includePassword=true) => Json(new {
            settings=Controller.Settings, file=Convert.ToHexString(File.ReadAllBytes(Store.Path)),
            backup=Convert.ToHexString(File.ReadAllBytes(Store.Path+".bak")), clock=Controller.LastCheckedAt,
            signals=Field<AttentionTracker>(Controller,"attention").SignalItems,
            seen=Field<NotificationLedger>(Controller,"notifications").Seen,
            pending=Field<IList>(Controller,"pendingAlerts").Cast<object>().ToArray(),
            queue=((IEnumerable)Field<object>(Controller,"deliveries")).Cast<object>().ToArray(),
            activeDelivery=Field<object?>(Controller,"activeDelivery"), activeAlert=Field<DeckAlert?>(Controller,"activeAlert"),
            timers=new[] {"localPolling","sharedPolling","notificationBatch","notificationExpiry","nextNotification"}
                .Select(name => Field<DispatcherTimer>(Controller,name).IsEnabled).ToArray(),
            hwnd=new WindowInteropHelper(LocalOwner).Handle.ToInt64(), status=LocalOwner.Latest,
            hidden=!LocalOwner.IsVisible, configured=LocalOwner.Reference, token=includePassword ? Form.TokenDraft : ""
        });

        internal void RequireUnchanged(string before)
        {
            Require(Capture() == before && pendingRead is { IsCompleted:false } && !pendingReadToken.IsCancellationRequested,
                "Readonly token action changed owned settings/backup, replacement, clocks/history/queue or retained pending owner.");
            RequireIsolation();
        }

        internal string Facts(bool controlPresent) => Json(new {controlPresent,reader=ReadCalls,acquisition=Acquisitions,
            storedVerify=StoredVerifications,replacementVerify=ReplacementVerifications,writes=WriteCalls,
            changed=ChangedCalls,opened=Opened.Count,presenceCallback=PresenceCalls});

        private void RequireIsolation()
        {
            var managers=typeof(DeckController).GetFields(BindingFlags.Instance|BindingFlags.NonPublic)
                .Where(field => field.FieldType == typeof(WorkerManager));
            var count=managers.Sum(field => ((IDictionary)typeof(WorkerManager).GetField("workers",BindingFlags.Instance|BindingFlags.NonPublic)!
                .GetValue(field.GetValue(Controller))!).Count);
            Require((realManager ? count<=1 : count==0) && !Controller.LocalPollEnabled && !Controller.SharedPollEnabled && Field<object?>(Controller,"tray") is null,
                "The owned token baseline started a worker, polling loop or actual notification tray.");
        }

        public async ValueTask DisposeAsync()
        {
            closed=true; Form.Dispose(); Window.Close();
            read.TrySetResult(new(1,"owned-token-status",Distribution,null,Status(),null,null));
            try { if(pendingRead is not null) await pendingRead.WaitAsync(TimeSpan.FromSeconds(5)); }
            finally {
                Controller.CloseViews();
                await Field<WorkerManager>(Controller,"settingsChecks").DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(5));
                foreach(var file in new[]{Store.Path,Store.Path+".bak"}) if(File.Exists(file)) File.Delete(file);
            }
        }
    }

    private static ProjectStatus Status() => new("owned.token.local","running","owned.branch",null,"Owned framework",null);
    private static string ContentName(Button button) => button.Content is TextBlock text ? text.Text : button.Content?.ToString() ?? "";
    private static IEnumerable<T> Elements<T>(DependencyObject root) where T:DependencyObject
    {
        if(root is T match) yield return match;
        for(var index=0;index<VisualTreeHelper.GetChildrenCount(root);index++)
            foreach(var item in Elements<T>(VisualTreeHelper.GetChild(root,index))) yield return item;
    }
    private static T Field<T>(object owner,string name) => (T)owner.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(owner)!;
    private static void SetField(object owner,string name,object? value) => owner.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(owner,value);
    private static string Json<T>(T value) => JsonSerializer.Serialize(value,WorkerProtocol.Json);
    private static async Task Turns() { for(var turn=0;turn<3;turn++) await Dispatcher.Yield(DispatcherPriority.Background); }
    private static void Require(bool value,string message) { if(!value) throw new IOException(message); }
}
