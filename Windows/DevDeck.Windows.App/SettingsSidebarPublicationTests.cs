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
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Actual owned controller/cache publications and credential-save bodies, with fake IO only.
internal static class SettingsSidebarPublicationTests
{
    private const string Selected = "owned.ddev", Sibling = "owned.local", Arc = "owned.arc";
    internal static async Task RunAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        try {
            await HiddenReceiptAsync(application, checks);
            await OperationAndGroupAsync(application, checks);
            await PhysicalStatesAsync(application, checks);
            await AdmissionAsync(application, checks);
            await ReplacementAsync(application, checks);
            await CredentialCommitAsync(application, checks, cleanupFails:false);
            await CredentialCommitAsync(application, checks, cleanupFails:true);
            await CredentialFailuresAsync(application, checks);
            await MetadataOnlyAsync(application, checks);
            await CredentialCancellationAsync(application, checks);
        } finally { Text.Use(language); }
    }

    private static async Task HiddenReceiptAsync(Application application, List<object> checks)
    {
        await using var owned = new Owned(application);
        await owned.ShowAsync();
        var selected = owned.Owner(Selected); var sibling = owned.Owner(Sibling);
        var row = owned.Row(Selected); var form = owned.Window.Page.Content;
        var selectedHandle = Handle(selected); var siblingHandle = Handle(sibling);
        var untouched = sibling.Latest;
        var completion = Pending<WorkerResponse>(); CancellationToken pollToken = default;
        owned.Read = (_, token) => { pollToken=token; return completion.Task; };
        selected.SetDeckVisible(true); var reading=selected.RefreshAsync("owned-held-sidebar");
        Require(pollToken.CanBeCanceled, "The actual project poll did not enter the fake reader with its owner lifetime.");
        selected.SetDeckVisible(false); var globals = owned.CaptureGlobals();
        var receipt = Status(Selected, "running");
        completion.SetResult(new(1,"owned-held-sidebar","Owned Linux",null,receipt,null,null));
        await reading.WaitAsync(TimeSpan.FromSeconds(5));
        await Turns();
        Require(Dot(row, SidebarProjectActivity.Running) && ReferenceEquals(row, owned.Row(Selected))
            && ReferenceEquals(form, owned.Window.Page.Content) && ReferenceEquals(selected.Latest, receipt)
            && !pollToken.IsCancellationRequested && selected.LastRefreshSucceeded
            && !selected.IsVisible && !selected.DeckVisible && Handle(selected) == selectedHandle
            && sibling.IsVisible && Handle(sibling) == siblingHandle && ReferenceEquals(sibling.Latest, untouched),
            "Accepted hidden receipt did not update only its retained sidebar row/physical cache.");
        owned.RequireGlobals(globals);
        checks.Add(new { name="settings.sidebar.publication.hiddenReceipt", actualHeldReadAndOwnerToken=true,
            retainedHiddenOwner=true, retainedRowAndPage=true,
            nonemptyAttentionSeenPendingDeliveryAndClockPreserved=true, unrelatedHwndAndCachePreserved=true });
    }

    private static async Task OperationAndGroupAsync(Application application, List<object> checks)
    {
        await using var owned = new Owned(application);
        await owned.ShowAsync(); var local = owned.Owner(Sibling); var selected = owned.Owner(Selected);
        local.ApplySnapshot(Status(Sibling, "running")); selected.ApplySnapshot(Status(Selected, "running"));
        var globals = owned.CaptureGlobals(); var running = selected.Latest;
        var oldTimestamp = Get<TextBlock>(selected, "timestamp").Text;
        var completion = Pending<WorkerResponse>(); var entered = Pending<bool>();
        owned.Action = (_, token, _) => { Require(token.CanBeCanceled, "The actual per-card operation did not carry its lifetime CTS."); entered.TrySetResult(true); return completion.Task; };
        // PerformAsync reconciles once more after cleanup; its physical reader agrees with the stop receipt.
        owned.Read = (_, _) => Task.FromResult(new WorkerResponse(1,"owned-stop-recheck","Owned Linux",null,Status(Sibling,"stopped"),null,null));
        var operation = (Task)typeof(ProjectCard).GetMethod("PerformAsync", BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(local, ["stop"])!;
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5)); await Turns();
        Require(local.SidebarActivity == SidebarProjectActivity.Busy && Dot(owned.Row(Sibling), SidebarProjectActivity.Busy)
            && Get<CancellationTokenSource?>(local, "operation") is not null, "Actual in-flight stop did not override a running sidebar cache.");
        completion.SetResult(new(1, "owned-stop", "Owned Linux", null, Status(Sibling, "stopped"), null, null));
        await operation.WaitAsync(TimeSpan.FromSeconds(5)); await Turns();
        Require(Get<CancellationTokenSource?>(local, "operation") is null && Dot(owned.Row(Sibling), SidebarProjectActivity.None),
            "Actual operation cleanup did not restore the final physical sidebar state.");
        selected.BeginDDEVPowerOff("owned-never-ran");
        Require(Dot(owned.Row(Selected), SidebarProjectActivity.Busy), "DDEV group presentation did not override a hidden running cache.");
        selected.CompleteDDEVPowerOff("owned-never-ran");
        Require(Dot(owned.Row(Selected), SidebarProjectActivity.Running) && ReferenceEquals(selected.Latest, running)
            && Get<TextBlock>(selected, "timestamp").Text == oldTimestamp, "Never-run group completion did not restore the prior receipt/presentation exactly.");
        selected.BeginDDEVPowerOff("owned-completed"); selected.CompleteDDEVPowerOff("foreign-token", Status(Selected, "stopped"));
        Require(Dot(owned.Row(Selected), SidebarProjectActivity.Busy), "Foreign group token altered sidebar state.");
        selected.CompleteDDEVPowerOff("owned-completed", Status(Selected, "stopped"));
        Require(Dot(owned.Row(Selected), SidebarProjectActivity.None) && !selected.IsVisible, "Group physical completion failed to publish without revealing its owner.");
        owned.RequireGlobals(globals);
        checks.Add(new { name="settings.sidebar.publication.operationAndGroup", actualOperationCtsAndFinally=true,
            groupOverridesCache=true, neverRunRestoresReceiptAndTimestamp=true, foreignTokenRefused=true });
    }

    private static async Task PhysicalStatesAsync(Application application, List<object> checks)
    {
        await using var owned = new Owned(application);
        await owned.ShowAsync(); var globals = owned.CaptureGlobals();
        foreach (var owner in owned.Controller.AllLocalViews) {
            foreach (var state in new[] { "working", "starting", "running", "paused", "stopped", "unknown", "unavailable" }) {
                owner.ApplySnapshot(Status(owner.Reference.Id, state));
                var expected = state == "working" || state == "starting" && owner.Reference.Kind == "local" ? SidebarProjectActivity.Busy
                    : state == "running" ? SidebarProjectActivity.Running : SidebarProjectActivity.None;
                Require(owner.SidebarActivity == expected && Dot(owned.Row(owner.Reference.Id), expected),
                    owner.Reference.Kind + "/" + state + " sidebar state follows header warning color instead of physical semantics.");
            }
            owner.ApplySnapshot(Status(owner.Reference.Id, "running") with { NotAnswering="Owned health warning", SyncBroken="Owned sync warning" });
            Require(Dot(owned.Row(owner.Reference.Id), SidebarProjectActivity.Running), "Health/sync presentation manufactured a busy sidebar dot.");
        }
        var local = owned.Owner(Sibling); var accepted = local.Latest;
        owned.Read = (_, _) => Task.FromException<WorkerResponse>(new IOException("Owned failed read"));
        await local.RefreshAsync("owned-failure");
        Require(!local.LastRefreshSucceeded && ReferenceEquals(local.Latest, accepted) && Dot(owned.Row(Sibling), SidebarProjectActivity.Running),
            "A failed poll discarded a retained running cache or invented busy presentation.");
        owned.RequireGlobals(globals);
        checks.Add(new { name="settings.sidebar.publication.physicalStates", allOriginalKindsAndStates=true,
            warningsDoNotInventBusy=true, failedReadRetainsAcceptedCache=true, noFalseSuccessfulReceipt=true });
    }

    private static async Task AdmissionAsync(Application application, List<object> checks)
    {
        await using var owned = new Owned(application);
        await owned.ShowAsync(); var owner = owned.Owner(Selected); var row = owned.Row(Selected);
        owner.ApplySnapshot(Status(Selected, "running")); var configured = owned.Controller.Settings.Cards.Single(card => card.Project.Id == Selected);
        var globals = owned.CaptureGlobals();
        var variants = new Func<ProjectReference,ProjectReference>[] {
            reference => reference with { Path="/owned/moved" }, reference => reference with { Distribution="Other Linux" },
            reference => reference with { Kind="local" }, reference => reference with { StartCommand="different command" },
            reference => reference with { StopCommand="different stop" }, reference => reference with { RequiresDocker=true },
            reference => reference with { HoldsProcess=true }, reference => reference with { HealthURL="http://localhost:4545/health" },
            reference => reference with { OpenURL="http://localhost:4545" }, reference => reference with { Subtitle="changed runtime" },
            reference => reference with { Arc=new("Owned", "site", "http://localhost", "/health") }
        };
        foreach (var change in variants) {
            owned.ChangeConfigured(configured with { Project=change(configured.Project) });
            owner.ApplySnapshot(Status(Selected, "working"));
            Require(Dot(row, SidebarProjectActivity.Running), "An obsolete path/distribution/kind/runtime owner updated the current settings row.");
            owned.ChangeConfigured(configured); owner.ApplySnapshot(Status(Selected, "running"));
        }
        var prior = owner.Latest;
        owner.ApplySnapshot(Status("foreign.id", "working"));
        Require(ReferenceEquals(prior, owner.Latest) && Dot(row, SidebarProjectActivity.Running), "Wrong-ID physical receipt was admitted.");
        SetProperty(owner, "Latest", Status("foreign.id", "working")); owned.Controller.NotifySidebarProjectPresentation(owner);
        Require(Dot(row, SidebarProjectActivity.Running), "Wrong-ID cached receipt passed controller publication admission.");
        SetProperty(owner, "Latest", prior);
        foreach (var flag in new[] { "closing", "shuttingDown" }) {
            SetField(owned.Controller, flag, true); owner.ApplySnapshot(Status(Selected, "working"));
            Require(Dot(row, SidebarProjectActivity.Running), "Closing/shutting-down controller updated the visible sidebar.");
            SetField(owned.Controller, flag, false); owner.ApplySnapshot(Status(Selected, "running"));
        }
        owned.Window.Hide(); owner.ApplySnapshot(Status(Selected, "working"));
        Require(Dot(row, SidebarProjectActivity.Running), "Hidden settings window received an automatic publication.");
        owned.Window.Show();
        Require(Dot(row, SidebarProjectActivity.Busy), "Reopening settings did not reconcile the accepted hidden-owner cache.");
        owned.RequireGlobals(globals);
        owner.ApplySnapshot(Status(Selected, "running"));
        using (var outsider = new CloseOwner(new ProjectCard(owned.Controller, configured, live:false))) {
            outsider.Card.ApplySnapshot(Status(Selected, "working"));
            Require(Dot(row, SidebarProjectActivity.Running), "An unregistered same-ID physical owner updated the sidebar.");
        }
        owned.ChangeConfigured(configured with { Title="Display-only rename", X=128, Y=160, Collapsed=true });
        owner.ApplySnapshot(Status(Selected, "working"));
        Require(Dot(row, SidebarProjectActivity.Busy) && row.TitleText.Text == "Display-only rename", "Display-only edits incorrectly invalidate logical owner publication.");
        owned.ChangeConfigured(configured); owner.ApplySnapshot(Status(Selected, "running"));
        SetProperty(owner, "Latest", Status(Selected, "working"));
        // Hold the UI thread only until this bounded non-UI call posts its hint; reject after dispatch.
        Task.Run(() => owned.Controller.NotifySidebarProjectPresentation(owner)).GetAwaiter().GetResult();
        owner.Close(); await Turns();
        Require(owner.SidebarOwnerClosed && Dot(row, SidebarProjectActivity.Running), "Queued/closed-owner hint bypassed dispatcher-boundary lifetime admission.");
        owned.Controller.NotifySidebarProjectPresentation(owner);
        Require(Dot(row, SidebarProjectActivity.Running), "Closed owner updated the retained sidebar row.");
        owned.RequireGlobals(globals);
        checks.Add(new { name="settings.sidebar.publication.currentOwnerAdmission", fullLogicalReferenceGuard=true,
            wrongIdUnregisteredClosedOwnersRefused=true, queuedHintRevalidated=true, hiddenSettingsSkipped=true, displayOnlyEditsAllowed=true });
    }

    private static async Task ReplacementAsync(Application application, List<object> checks)
    {
        await using var owned = new Owned(application);
        await owned.ShowAsync(); var old = owned.Owner(Selected); var sibling = owned.Owner(Sibling);
        old.ApplySnapshot(Status(Selected, "running")); var row = owned.Row(Selected); var seen = Get<NotificationLedger>(owned.Controller, "notifications").Seen.ToArray();
        await owned.Controller.SaveSettingsAsync(current => current with { Cards=current.Cards.Select(card => card.Project.Id == Selected
            ? card with { Project=card.Project with { Path="/owned/new-reference" }, Enabled=false } : card).ToArray() });
        await Turns(); var replacement = owned.Owner(Selected);
        Require(!ReferenceEquals(old, replacement) && old.SidebarOwnerClosed && replacement.Latest is null && !replacement.IsVisible
            && ReferenceEquals(row, owned.Row(Selected)) && Dot(row, SidebarProjectActivity.None)
            && ReferenceEquals(sibling, owned.Owner(Sibling)), "Actual settings reconciliation left the former owner's dot on a fresh hidden replacement.");
        old.ApplySnapshot(Status(Selected, "running")); owned.Controller.NotifySidebarProjectPresentation(old);
        Require(Dot(row, SidebarProjectActivity.None), "Old replacement callback restored a foreign physical dot.");
        Require(owned.Controller.LastCheckedAt is null && Get<AttentionTracker>(owned.Controller, "attention").SignalItems.Length == 0
            && Get<NotificationLedger>(owned.Controller, "notifications").Seen.SequenceEqual(seen)
            && Get<IList>(owned.Controller, "pendingAlerts").Count == 0,
            "The fixture no longer preserves actual existing SaveSettings attention-reset/Seen semantics.");
        owned.RequireNoWorkers();
        checks.Add(new { name="settings.sidebar.publication.replacement", actualSaveAndRebuild=true,
            freshHiddenOwnerClearsOldDot=true, oldCallbackRefused=true, existingSettingsResetAndSeenPolicyRetained=true });
    }

    private static async Task CredentialCommitAsync(Application application, List<object> checks, bool cleanupFails)
    {
        await using var owned = new Owned(application, presentation:false);
        var original = owned.Controller.Settings.AccountList[0]; var events = new List<string>();
        var newEndpoint = "https://new.github.example"; var expectedTarget = (original with { Endpoint=newEndpoint }).CredentialTarget;
        var failure = new IOException("Owned old-target cleanup failure"); var verified = 0;
        using var form = new AccountSettingsForm(owned.Controller, original, live:true, changed:id => {
            Require(id == original.Id && events.LastOrDefault() == "credential", "Ordinary metadata callback ran before committed credential availability."); events.Add("changed");
        }, credentialChanged:id => {
            Require(id == original.Id && owned.Controller.Settings.AccountList.Single(account => account.Id == id).CredentialTarget == expectedTarget
                && owned.Store.Load().AccountList.Single(account => account.Id == id).CredentialTarget == expectedTarget
                && events.SequenceEqual(new[] { "verify", "write" }), "Credential callback did not follow exact-target write and persisted commit."); events.Add("credential");
        }, verifyCredential:(account, value, distribution, token) => {
            Require(account.CredentialTarget == expectedTarget && value == "Owned fixture value" && distribution == "Owned Linux" && token.CanBeCanceled,
                "Actual verification body did not capture the draft target/value/distribution/lifetime."); verified++; events.Add("verify"); return Task.CompletedTask;
        }, credentialWriter:(account, value) => {
            if (value is not null) { Require(account.CredentialTarget == expectedTarget, "Credential body wrote a foreign target."); events.Add("write"); }
            else { Require(account.CredentialTarget == original.CredentialTarget && events.LastOrDefault() == "changed", "Former target cleanup preceded committed callbacks."); events.Add("delete"); if (cleanupFails) throw failure; }
        });
        form.TokenDraft="Owned fixture value"; Get<TextBox>(form, "endpoint").Text=newEndpoint; StopDebounce(form);
        await form.VerifyTokenAsync();
        Require(!form.IsLoaded && verified == 1 && events.SequenceEqual(new[] { "verify", "write", "credential", "changed", "delete" })
            && owned.Store.Load().AccountList[0].Endpoint == newEndpoint && form.IsEnabled,
            "Actual save body lost its write/commit/callback/cleanup order or discovered a live distribution.");
        var message = GetBase<TextBlock>(form, "Message");
        Require(cleanupFails ? form.TokenDraft == "Owned fixture value" && message.Text == Text.Failure(failure) && SameColor(message.Foreground, Brushes.Firebrick)
            : form.TokenDraft.Length == 0 && message.Text == Text.L("token.works"), "Credential cleanup outcome did not retain draft/error or clear a successful draft.");
        owned.RequireNoWorkers();
        checks.Add(new { name=cleanupFails ? "settings.sidebar.credential.cleanupFailure" : "settings.sidebar.credential.commitOrder",
            actualVerifyAndSaveBody=true, exactTargetWriteThenPersist=true, credentialCallbackBeforeMetadataAndOldDelete=true,
            committedAvailabilitySurvivesCleanupFailure=cleanupFails, noActualVaultOrProvider=true });
    }

    private static async Task CredentialFailuresAsync(Application application, List<object> checks)
    {
        foreach (var failWrite in new[] { false, true }) {
            await using var owned = new Owned(application, presentation:false); var before = File.ReadAllBytes(owned.Store.Path);
            var error = failWrite ? (Exception)new HostFailure("credentialWriteFailed", "Owned write failure") : new WorkerException("credentialsRejected", "Owned verification failure");
            var verifies=0; var writes=0; var commits=0; var changes=0;
            using var form = new AccountSettingsForm(owned.Controller, owned.Controller.Settings.AccountList[0], live:true,
                changed:_ => changes++, credentialChanged:_ => commits++, verifyCredential:(_, _, _, _) => {
                    verifies++; return failWrite ? Task.CompletedTask : Task.FromException(error);
                }, credentialWriter:(_, _) => { writes++; throw error; });
            form.TokenDraft="Owned fixture value"; await form.VerifyTokenAsync();
            Require(verifies == 1 && writes == (failWrite ? 1 : 0) && commits == 0 && changes == 0 && form.IsEnabled
                && form.TokenDraft == "Owned fixture value" && GetBase<TextBlock>(form, "Message").Text == Text.Failure(error)
                && File.ReadAllBytes(owned.Store.Path).SequenceEqual(before), "Failed verification/write manufactured a credential commit or discarded its draft/error.");
            owned.RequireNoWorkers();
        }
        checks.Add(new { name="settings.sidebar.credential.failures", actualVerificationAndWriteFailurePaths=true,
            noAvailabilityOrMetadataCommit=true, persistedBytesAndTokenDraftRetained=true });
    }

    private static async Task MetadataOnlyAsync(Application application, List<object> checks)
    {
        await using var owned = new Owned(application, presentation:false); var original = owned.Controller.Settings.AccountList[0];
        var commits=0; var changes=0; var verifies=0; var writes=0;
        using var form = new AccountSettingsForm(owned.Controller, original, live:true, changed:_ => changes++, credentialChanged:_ => commits++,
            verifyCredential:(_, _, _, _) => { verifies++; return Task.CompletedTask; }, credentialWriter:(_, _) => writes++);
        form.TokenDraft="Unsaved owned draft"; Get<TextBox>(form, "label").Text="Renamed metadata only"; StopDebounce(form);
        await form.FlushAsync();
        Require(changes == 1 && commits == 0 && verifies == 0 && writes == 0 && form.TokenDraft == "Unsaved owned draft"
            && owned.Store.Load().AccountList[0].Label == "Renamed metadata only" && !form.HasUncommittedChanges,
            "Ordinary metadata autosave performed credential work, changed token draft or failed to persist.");
        owned.RequireNoWorkers();
        checks.Add(new { name="settings.sidebar.credential.metadataOnly", actualFlushBody=true, noCredentialCallbackOrIO=true,
            tokenDraftPreserved=true });
    }

    private static async Task CredentialCancellationAsync(Application application, List<object> checks)
    {
        await using var owned = new Owned(application, presentation:false); var before = File.ReadAllBytes(owned.Store.Path);
        var entered=Pending<CancellationToken>(); var release=Pending<bool>(); var writes=0; var commits=0; var changes=0;
        using var form = new AccountSettingsForm(owned.Controller, owned.Controller.Settings.AccountList[0], live:true,
            changed:_ => changes++, credentialChanged:_ => commits++, verifyCredential:async (_, _, _, token) => { entered.TrySetResult(token); await release.Task; },
            credentialWriter:(_, _) => writes++);
        form.TokenDraft="Owned fixture value"; var task=form.VerifyTokenAsync(); var token=await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Require(!form.IsEnabled && !token.IsCancellationRequested, "The fake verifier did not hold the actual save body/lifetime.");
        GetBase<CancellationTokenSource>(form, "Lifetime").Cancel(); release.SetResult(true); await task.WaitAsync(TimeSpan.FromSeconds(5));
        Require(token.IsCancellationRequested && writes == 0 && commits == 0 && changes == 0 && form.IsEnabled
            && form.TokenDraft == "Owned fixture value" && File.ReadAllBytes(owned.Store.Path).SequenceEqual(before),
            "Cancelled verification admitted a late credential write/commit or lost the draft.");
        owned.RequireNoWorkers();
        checks.Add(new { name="settings.sidebar.credential.cancelledVerification", actualHeldVerifierAndLifetime=true,
            cancellationBeforeWrite=true, noLateAvailabilityCommit=true, draftAndPersistedBytesRetained=true });
    }

    private sealed class Owned : IAsyncDisposable
    {
        internal readonly SettingsStore Store;
        internal readonly DeckController Controller;
        private readonly SettingsWindow? window;
        internal SettingsWindow Window => window ?? throw new IOException("This fixture has no settings window.");
        internal Func<string?,CancellationToken,Task<WorkerResponse>>? Read;
        internal Func<string,CancellationToken,Action<string>,Task<WorkerResponse>>? Action;
        internal Owned(Application application, bool presentation=true)
        {
            Store = new(Path.Combine(Path.GetTempPath(), "devdeck-sidebar-publication-"+Guid.NewGuid().ToString("N")+".json"));
            Store.Save(new(1, [new("Owned Linux", "/owned/runtime"), new("Other Linux", "/owned/runtime")], [
                new(new(Selected, "Owned Linux", "ddev", "/owned/ddev"), "Owned DDEV", Enabled:false, X:64, Y:80),
                new(new(Sibling, "Owned Linux", "local", "/owned/local", StartCommand:"npm run dev"), "Owned local", Enabled:presentation, X:520, Y:80),
                new(new(Arc, "Other Linux", "arc", "/owned/arc"), "Owned Arc", Enabled:false, X:976, Y:80)
            ], Accounts:[new("owned.account", "Owned account", "github", "https://api.github.com", [], [])], Language:"en", Notifications:false,
                SeenAlerts:["owned.seen.original"]));
            Controller = new(application, Store, live:false);
            if (presentation) {
                foreach (var setting in Controller.Settings.Cards) {
                    var owner=new ProjectCard(Controller, setting, live:false, statusReader:(cycle,token) => Read?.Invoke(cycle,token)
                        ?? Task.FromResult(new WorkerResponse(1,"owned-read",setting.Project.Distribution,null,Status(setting.Project.Id,"running"),null,null)),
                        actionRunner:(action,token,progress) => Action?.Invoke(action,token,progress)
                        ?? Task.FromResult(new WorkerResponse(1,"owned-action",setting.Project.Distribution,null,Status(setting.Project.Id,"stopped"),null,null)));
                    Get<List<ProjectCard>>(Controller,"cards").Add(owner);
                    Get<Dictionary<string,CardSettings>>(Controller,"localConfigurations")[setting.Project.Id]=setting;
                    owner.SetDeckVisible(true); if (!setting.Enabled) owner.SetDeckVisible(false);
                }
                window=new(Controller, live:false, tokenAvailable:_ => false);
                SetField(Controller,"settingsWindow",window);
            }
            SeedGlobals();
        }
        internal ProjectCard Owner(string id) => Controller.AllLocalViews.Single(owner => owner.Reference.Id == id);
        internal SettingsSidebarRow Row(string id) => Window.Navigation.Items.OfType<SettingsSidebarRow>().Single(row =>
            row.Tag?.GetType().GetProperty("ID")?.GetValue(row.Tag) as string == "project:"+id);
        internal async Task ShowAsync() { Window.Show(); Window.UpdateLayout(); await Turns(); Require(Window.IsVisible, "Owned settings window failed to show."); }
        internal void ChangeConfigured(CardSettings value) => SetProperty(Controller,"Settings", Controller.Settings with {
            Cards=Controller.Settings.Cards.Select(card => card.Project.Id == value.Project.Id ? value : card).ToArray() });
        private void SeedGlobals()
        {
            var tracker=Get<AttentionTracker>(Controller,"attention");
            foreach (var scope in new[] { "synthetic:sidebar.local", "synthetic:sidebar.remote" })
                tracker.Observe(new AttentionSnapshot(scope,[new(scope+":item",scope+":key","waiting","github","Retained owned attention","Retained facts",1000,new("none"),false,false)],[]));
            tracker.Observe(new RemoteSnapshot("owned.legacy","pullRequests",1,0,null,[],[],false,
                Attention:[new("legacy-item","legacy-key","owned.account","review","Owned legacy attention",null)]));
            var alert=new DeckAlert("owned.pending.alert","cantCheck","owned","Owned pending","Owned detail","Owned body","",new("menu"),true);
            var ledger=Get<NotificationLedger>(Controller,"notifications"); ledger.Observe(new("synthetic:ledger",[],[alert]),Controller.Settings with { Notifications=true });
            var scopedType=typeof(DeckController).GetNestedType("ScopedAlert",BindingFlags.NonPublic)!;
            var scoped=Activator.CreateInstance(scopedType, BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,null,["synthetic:pending",alert],null)!;
            Get<IList>(Controller,"pendingAlerts").Add(scoped);
            var sources=Array.CreateInstance(scopedType,1); sources.SetValue(scoped,0);
            var deliveryType=typeof(DeckController).GetNestedType("Delivery",BindingFlags.NonPublic)!;
            var delivery=Activator.CreateInstance(deliveryType, BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,null,[sources,false],null)!;
            var queue=Get<object>(Controller,"deliveries"); queue.GetType().GetMethod("Enqueue")!.Invoke(queue,[delivery]);
            SetField(Controller,"activeDelivery",delivery); SetField(Controller,"activeAlert",alert);
            SetField(Controller,"lastCheckedAt",DateTimeOffset.FromUnixTimeSeconds(1000));
        }
        internal string CaptureGlobals() => JsonSerializer.Serialize(new {
            settings=Controller.Settings, bytes=Convert.ToHexString(File.ReadAllBytes(Store.Path)), clock=Controller.LastCheckedAt,
            signals=Get<Dictionary<string,AttentionItem[]>>(Get<AttentionTracker>(Controller,"attention"),"signals"),
            legacy=Get<AttentionTracker>(Controller,"attention").Items,
            announced=Get<HashSet<string>>(Get<AttentionTracker>(Controller,"attention"),"announced").OrderBy(value=>value).ToArray(),
            seen=Get<NotificationLedger>(Controller,"notifications").Seen,
            observed=Get<HashSet<string>>(Get<NotificationLedger>(Controller,"notifications"),"observed").OrderBy(value=>value).ToArray(),
            pending=Get<IList>(Controller,"pendingAlerts").Cast<object>().ToArray(),
            deliveries=((IEnumerable)Get<object>(Controller,"deliveries")).Cast<object>().ToArray(),
            activeDelivery=Get<object?>(Controller,"activeDelivery"),activeAlert=Get<DeckAlert?>(Controller,"activeAlert"),
            timers=new[] { "localPolling","sharedPolling","notificationBatch","notificationExpiry","nextNotification" }
                .Select(name=>Get<DispatcherTimer>(Controller,name).IsEnabled).ToArray()
        },WorkerProtocol.Json);
        internal void RequireGlobals(string before) { Require(CaptureGlobals()==before,"Sidebar publication changed nonempty attention/Seen/delivery/clock/persistence/timers."); RequireNoWorkers(); }
        internal void RequireNoWorkers()
        {
            var managers=typeof(DeckController).GetFields(BindingFlags.Instance|BindingFlags.NonPublic).Where(field=>field.FieldType==typeof(WorkerManager));
            var count=managers.Select(field=>field.GetValue(Controller)).Sum(manager=>((IDictionary)typeof(WorkerManager)
                .GetField("workers",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(manager)!).Count);
            Require(count==0 && !Controller.LocalPollEnabled && !Controller.SharedPollEnabled,"Owned sidebar fixture started a real worker or polling loop.");
        }
        public async ValueTask DisposeAsync()
        {
            try { if(window is not null) await window.CloseSettingsAsync(); }
            finally { SetField(Controller,"settingsWindow",null); Controller.CloseViews(); foreach(var file in new[]{Store.Path,Store.Path+".bak"})if(File.Exists(file))File.Delete(file); }
        }
    }
    private sealed class CloseOwner(ProjectCard card) : IDisposable { internal ProjectCard Card => card; public void Dispose()=>card.Close(); }
    private static ProjectStatus Status(string id,string state)=>new(id,state,"owned.branch",null,"Owned framework",null);
    private static bool Dot(SettingsSidebarRow row,SidebarProjectActivity expected)=>expected==SidebarProjectActivity.None
        ? row.Dot.Visibility!=Visibility.Visible : row.Dot.Visibility==Visibility.Visible && SameColor(row.Dot.Fill,expected==SidebarProjectActivity.Running?CardTheme.Green:CardTheme.Amber);
    private static bool SameColor(Brush? actual,Brush expected)=>actual is SolidColorBrush left && expected is SolidColorBrush right && left.Color==right.Color;
    private static nint Handle(Window window)=>new WindowInteropHelper(window).Handle;
    private static T Get<T>(object owner,string name)=>(T)owner.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(owner)!;
    private static T GetBase<T>(object owner,string name)=>(T)typeof(SettingsForm).GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(owner)!;
    private static void SetField(object owner,string name,object? value)=>owner.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(owner,value);
    private static void SetProperty(object owner,string name,object? value)=>owner.GetType().GetProperty(name,BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(owner,value);
    private static void StopDebounce(SettingsForm form)=>GetBase<DispatcherTimer>(form,"debounce").Stop();
    private static TaskCompletionSource<T> Pending<T>()=>new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static async Task Turns(){for(var turn=0;turn<3;turn++)await Dispatcher.Yield(DispatcherPriority.Background);}
    private static void Require(bool value,string message){if(!value)throw new IOException(message);}
}
