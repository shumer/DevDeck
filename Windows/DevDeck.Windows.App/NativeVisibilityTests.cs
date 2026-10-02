using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Own synthetic widgets/settings only; no worker, credential, tray, browser or project action.
internal static class NativeVisibilityTests
{
    internal static async Task RunAsync(Application application, List<object> checks)
    {
        var path = Path.Combine(Path.GetTempPath(), "devdeck-native-visibility-" + Guid.NewGuid().ToString("N") + ".json");
        var store = new SettingsStore(path);
        store.Save(Fixture());
        var controller = new DeckController(application, store, live:false);
        try {
            Text.Use("en");
            typeof(DeckController).GetMethod("RebuildCards", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(controller, null);
            await Dispatcher.Yield(DispatcherPriority.Background);
            await CheckHideWhileUnrelatedActionHeldAsync(controller, store, checks);
            await CheckUnrelatedPendingOwnersAsync(controller,checks);
            await CheckProjectReadLifetimeAsync(controller,checks);
            await CheckProjectActionLifetimeAsync(controller,checks);
            await CheckRemoteReadLifetimeAsync(controller,checks);
            await CheckRemoteMutationLifetimeAsync(controller,checks);
            await CheckContextStateAsync(controller,checks);
        } finally {
            controller.CloseViews();
            foreach (var file in new[] { path, path + ".bak" }) if (File.Exists(file)) File.Delete(file);
            Text.Use("en");
        }
    }

    private static async Task CheckUnrelatedPendingOwnersAsync(DeckController controller,List<object> checks)
    {
        await controller.SetCardVisibleAsync("legacy.pulls",true);
        var projectSettings=controller.Settings.Cards.Single(card => card.Project.Id == "ddev.visibility");
        var remoteSettings=controller.Settings.RemoteCardList.Single(card => card.Id == "github.inbox");
        var actionSource=Pending<WorkerResponse>(); var readSource=Pending<RemoteSnapshot>();
        var actionToken=default(CancellationToken); var readToken=default(CancellationToken);
        var project=new ProjectCard(controller,projectSettings,live:false,
            statusReader:(_,_) => Task.FromResult(Response(Status(projectSettings.Project.Id,"running","post-action"))),
            actionRunner:(_,token,_) => { actionToken=token; return actionSource.Task; });
        var remote=new RemoteCard(controller,remoteSettings,live:false,snapshotReader:token => { readToken=token; return readSource.Task; });
        var locals=Get<List<ProjectCard>>(controller,"cards"); var remotes=Get<List<RemoteCard>>(controller,"remoteCards");
        var oldProject=locals.Single(card => card.Reference.Id == projectSettings.Project.Id);
        var oldRemote=remotes.Single(card => card.CardID == remoteSettings.Id);
        var projectIndex=locals.IndexOf(oldProject); var remoteIndex=remotes.IndexOf(oldRemote);
        oldProject.Close(); oldRemote.Close(); locals[projectIndex]=project; remotes[remoteIndex]=remote;
        Task? action=null; Task? read=null;
        try {
            project.SetDeckVisible(true); remote.SetDeckVisible(true);
            project.ApplySnapshot(Status(project.Reference.Id,"stopped","before-action"));
            var before=SampleDeck.Remote("inbox",6) with { CardID=remote.CardID }; remote.ApplySnapshot(before); remote.SetExpanded(true); Invoke(remote,"ShowAll");
            var list=Get<Window>(remote,"listWindow");
            var projectHandle=new WindowInteropHelper(project).Handle; var remoteHandle=new WindowInteropHelper(remote).Handle; var listHandle=new WindowInteropHelper(list).Handle;
            action=InvokeTask(project,"PerformAsync","start"); read=remote.RefreshAsync();
            await controller.SetCardVisibleAsync("legacy.pulls",false);
            Require(!action.IsCompleted && !read.IsCompleted && !actionToken.IsCancellationRequested && !readToken.IsCancellationRequested
                && controller.LocalViews.Any(card => ReferenceEquals(card,project)) && controller.RemoteViews.Any(card => ReferenceEquals(card,remote))
                && new WindowInteropHelper(project).Handle == projectHandle && new WindowInteropHelper(remote).Handle == remoteHandle
                && new WindowInteropHelper(list).Handle == listHandle && list.IsVisible && Get<bool>(remote,"expanded") && ReferenceEquals(remote.Latest,before),
                "Actual controller hide cancels/rebuilds an unrelated real pending project action or remote read/list.");
            var after=SampleDeck.Remote("inbox",4) with { CardID=remote.CardID }; readSource.SetResult(after); actionSource.SetResult(Response(Status(project.Reference.Id,"running","action-result")));
            await Task.WhenAll(action,read);
            Require(ReferenceEquals(remote.Latest,after) && project.Latest?.State == "running" && !actionToken.IsCancellationRequested && !readToken.IsCancellationRequested,
                "Unrelated retained pending operations cannot complete after a controller visibility change.");
            checks.Add(new { name="visibility.controller.unrelatedPendingOwners", exactProductionVisibilitySetter=true,
                actualProjectActionAndRemoteReadTokens=true, unrelatedTaskTokensNotCancelled=true,
                unrelatedHwndListExpansionAndSnapshotRetained=true, pendingResultsCompleteNormally=true });
        } finally {
            project.Close(); remote.Close(); actionSource.TrySetResult(Response(Status(project.Reference.Id,"stopped","cleanup")));
            readSource.TrySetResult(SampleDeck.Remote("inbox",0));
            if (action is not null) await action; if (read is not null) await read;
            var replacementProject=new ProjectCard(controller,projectSettings,live:false); locals[projectIndex]=replacementProject; replacementProject.SetDeckVisible(projectSettings.Enabled);
            var replacementRemote=new RemoteCard(controller,remoteSettings,live:false); remotes[remoteIndex]=replacementRemote;
            replacementRemote.SetDeckVisible(RemoteCardCatalog.Active(controller.Settings,remoteSettings));
        }
    }

    private static DeckSettings Fixture() => new(1,
        [new("Test Linux", "/tmp/devdeck-native-visibility-runtime")], [
            new(new("local.visibility", "Test Linux", "local", "/tmp/devdeck-native-visibility-local", StartCommand:"npm run dev"), "Synthetic local", X:520,Y:400),
            new(new("ddev.visibility", "Test Linux", "ddev", "/tmp/devdeck-native-visibility-ddev"), "Synthetic DDEV", X:976,Y:80)
        ],
        Accounts:[new("synthetic", "Synthetic account", "github", "https://api.github.com", [], [])],
        RemoteCards:[
            new("legacy.pulls", "Synthetic pull requests", "pullRequests", "Test Linux", ["synthetic"], X:64, Y:80),
            new("github.inbox", "Synthetic inbox", "inbox", "Test Linux", ["synthetic"], X:64, Y:400),
            new("github.actions", "Synthetic actions", "actions", "Test Linux", ["synthetic"], Enabled:false, X:520, Y:80)
        ], Language:"en", Notifications:false);

    private static async Task CheckHideWhileUnrelatedActionHeldAsync(DeckController controller, SettingsStore store, List<object> checks)
    {
        var hidden = controller.RemoteViews.Single(card => card.CardID == "legacy.pulls");
        var unrelated = controller.RemoteViews.Single(card => card.CardID == "github.inbox");
        var original = controller.Settings;
        var hiddenSnapshot = SampleDeck.Remote("pullRequests", 4) with { CardID=hidden.CardID };
        var unrelatedSnapshot = SampleDeck.Remote("inbox", 4) with { CardID=unrelated.CardID };
        hidden.ApplySnapshot(hiddenSnapshot); unrelated.ApplySnapshot(unrelatedSnapshot);
        unrelated.SetMutationPresentation(true);
        var hiddenHandle = new WindowInteropHelper(hidden).Handle;
        var unrelatedHandle = new WindowInteropHelper(unrelated).Handle;
        var hiddenClosed = false; var unrelatedClosed = false;
        hidden.Closed += (_, _) => hiddenClosed = true;
        unrelated.Closed += (_, _) => unrelatedClosed = true;
        Require(hiddenHandle != 0 && unrelatedHandle != 0 && hidden.IsVisible && unrelated.IsVisible,
            "Visibility regression fixture has no visible native widget handles.");
        var gate = (SemaphoreSlim)typeof(DeckController).GetField("actions", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(controller)!;
        await gate.WaitAsync();
        Task? visibility = null;
        try {
            // Exercise the existing production entrypoint while the real mutation gate is held.
            // Dispatcher turns let continuations run deterministically; no timed sleep or worker call.
            visibility = controller.SetRemoteVisibleAsync("pullRequests", false);
            for (var turn=0; turn<3; turn++) await Dispatcher.Yield(DispatcherPriority.Background);
            Require(visibility.IsCompleted,
                "Hiding a card waits for an unrelated project/account mutation gate; deck visibility must complete while that gate remains held.");
            await visibility;
            Require(!hidden.IsVisible && !hiddenClosed && new WindowInteropHelper(hidden).Handle == hiddenHandle,
                "Hiding the selected legacy role closes/replaces its widget instead of retaining the hidden native window.");
            Require(!unrelatedClosed && unrelated.IsVisible && new WindowInteropHelper(unrelated).Handle == unrelatedHandle
                && controller.RemoteViews.Any(card => ReferenceEquals(card, unrelated)) && unrelated.IsMutating,
                "Hiding one card closes/rebuilds an unrelated widget or loses its in-progress presentation.");
            Require(ReferenceEquals(hidden.Latest,hiddenSnapshot) && ReferenceEquals(unrelated.Latest,unrelatedSnapshot),
                "Visibility change discards a selected or unrelated validated snapshot.");
            Require(!RemoteCardCatalog.Resolve(controller.Settings,"pullRequests")!.Enabled
                && RemoteCardCatalog.Resolve(controller.Settings,"pullRequests")!.Id == hidden.CardID,
                "Visibility change hides the canonical ID instead of the existing selected legacy role.");
            var expected = original with { RemoteCards=original.RemoteCardList.Select(card => card.Id == hidden.CardID ? card with { Enabled=false } : card).ToArray() };
            Require(System.Text.Json.JsonSerializer.Serialize(controller.Settings,WorkerProtocol.Json)
                == System.Text.Json.JsonSerializer.Serialize(expected,WorkerProtocol.Json)
                && System.Text.Json.JsonSerializer.Serialize(store.Load(),WorkerProtocol.Json)
                == System.Text.Json.JsonSerializer.Serialize(expected,WorkerProtocol.Json),
                "Visibility change modifies array order, IDs, scope, geometry, compact state or unrelated saved preferences.");
            Require(!controller.LocalPollEnabled,"Synthetic visibility test starts the local worker polling loop.");
            checks.Add(new { name="visibility.remote.hideDuringUnrelatedMutation", productionEntrypoint=true,
                mutationGateHeld=true, completesWithoutMutationGate=true, selectedLegacyRoleHidden=true,
                hiddenWindowRetained=true, unrelatedNativeIdentityAndMutationRetained=true,
                snapshotsRetained=true, onlySelectedEnabledChanged=true, noWorkerOrCredential=true });
        } finally {
            gate.Release();
            // The old implementation queues on the gate. Release and settle it even after the
            // intended first assertion fails, so the red test never leaves a blocked task/window.
            if (visibility is not null) await visibility;
        }
    }

    private static async Task CheckProjectReadLifetimeAsync(DeckController controller,List<object> checks)
    {
        var source = Pending<WorkerResponse>(); var reads = 0; var token = default(CancellationToken);
        var settings = controller.Settings.Cards.Single(card => card.Project.Id == "local.visibility");
        var card = new ProjectCard(controller,settings,live:false,phoneAddress:() => "192.0.2.1",copyPhoneLink:_ => {},
            statusReader:(_,cancellation) => { reads++; token=cancellation; return source.Task; });
        Task? read = null;
        try {
            card.SetDeckVisible(true);
            var first = Status(card.Reference.Id,"running","before-read"); card.ApplySnapshot(first); card.ShowPhone();
            var handle = new WindowInteropHelper(card).Handle;
            Require(card.PhoneOpen && handle != 0,"Synthetic project read fixture did not create its own QR/native widget.");
            read = card.RefreshAsync();
            Require(reads == 1 && token.CanBeCanceled,"Project read does not use an owned cancellable lifetime.");
            card.SetDeckVisible(false); card.Summon(); card.ShowPhone(); await card.RefreshAsync();
            Require(!card.IsVisible && !card.CanRefresh && !card.PhoneOpen && reads == 1 && !token.IsCancellationRequested
                && ReferenceEquals(card.Latest,first),"Hiding a project cancels its current read, opens a QR/window or starts another read.");
            var completed = Status(card.Reference.Id,"running","completed-while-hidden"); source.SetResult(Response(completed)); await read;
            Require(!card.IsVisible && ReferenceEquals(card.Latest,completed) && card.LastRefreshSucceeded,
                "An already running project read loses its completed status or reopens the hidden widget.");
            card.SetDeckVisible(true);
            Require(card.IsVisible && new WindowInteropHelper(card).Handle == handle && ReferenceEquals(card.Latest,completed)
                && !card.PhoneOpen && reads == 1,"Showing a synthetic project replaces its native identity/snapshot or opens/fetches unexpectedly.");
            checks.Add(new { name="visibility.project.pendingRead", actualReadTask=true, ownedCancellationToken=true,
                hiddenStopsNewReads=true, hiddenResponseCached=true, hwndRetained=true, ownQrDismissed=true, noAutomaticQrReopen=true });

            source = Pending<WorkerResponse>(); read = card.RefreshAsync();
            card.SetDeckVisible(false); card.SetDeckVisible(true);
            Require(ReferenceEquals(read,card.RefreshAsync()) && reads == 2 && !token.IsCancellationRequested,
                "Hide/show does not coalesce the original pending project read.");
            card.Close();
            Require(token.IsCancellationRequested,"Actual project disposal leaves its owned read lifetime active.");
            source.SetResult(Response(Status(card.Reference.Id,"stopped","late-after-close"))); await read;
            Require(ReferenceEquals(card.Latest,completed),"A disposed project applies a late read response.");
            checks.Add(new { name="visibility.project.readClose", repeatedHideShowCoalesces=true,
                actualCloseCancels=true, lateDisposedResponseIgnored=true, noWorkerOrCredential=true });
        } finally {
            card.Close(); source.TrySetResult(Response(Status(card.Reference.Id,"stopped","cleanup")));
            if (read is not null) await read;
        }
    }

    private static async Task CheckProjectActionLifetimeAsync(DeckController controller,List<object> checks)
    {
        var source = Pending<WorkerResponse>(); var token = default(CancellationToken); Action<string>? progress = null; var reads = 0;
        var settings = controller.Settings.Cards.Single(card => card.Project.Id == "ddev.visibility") with { Collapsed=true };
        var card = new ProjectCard(controller,settings,live:false,
            statusReader:(_,_) => { reads++; return Task.FromResult(Response(Status(settings.Project.Id,"stopped","read"))); },
            actionRunner:(_,cancellation,update) => { token=cancellation; progress=update; return source.Task; });
        Task? action = null;
        try {
            card.SetDeckVisible(true); card.ApplySnapshot(Status(card.Reference.Id,"stopped","before-action"));
            var handle = new WindowInteropHelper(card).Handle;
            action = InvokeTask(card,"PerformAsync","start");
            Require(token.CanBeCanceled && Get<CancellationTokenSource>(card,"operation") is not null,"Project action fixture did not enter the production owned CTS path.");
            card.SetDeckVisible(false); progress!("synthetic hidden progress");
            await Dispatcher.Yield(DispatcherPriority.Background);
            Require(!token.IsCancellationRequested && Get<TextBlock>(card,"detail").Text == "synthetic hidden progress",
                "Hidden project action loses its actual token or queued progress.");
            card.SetDeckVisible(true); card.UpdateLayout();
            var cancel = Get<Button>(card,"cancel");
            Require(new WindowInteropHelper(card).Handle == handle && cancel.Visibility == Visibility.Visible
                && cancel.MinWidth == 0 && !card.CanRefresh && !token.IsCancellationRequested,
                "Revealing a running compact action replaces the widget or loses its compact cancel/busy state.");
            card.SetDeckVisible(false);
            var completed = Status(card.Reference.Id,"running","action-completed-hidden"); source.SetResult(Response(completed)); await action;
            Require(!card.IsVisible && ReferenceEquals(card.Latest,completed) && card.LastRefreshSucceeded && reads == 0
                && Get<CancellationTokenSource?>(card,"operation") is null && cancel.Visibility == Visibility.Collapsed,
                "Hidden project action completion loses returned status, starts a hidden read or keeps cancellation active.");
            checks.Add(new { name="visibility.project.pendingAction", actualActionTaskAndCts=true,
                hiddenProgressRetained=true, repeatedHideShowKeepsCompactCancel=true, hiddenCompletionStatusRetained=true,
                noHiddenFollowupRead=true, hwndRetained=true });

            card.SetDeckVisible(true); source=Pending<WorkerResponse>(); action=InvokeTask(card,"PerformAsync","restart"); card.SetDeckVisible(false);
            source.SetException(new IOException("synthetic hidden action failure")); await action;
            Require(!card.IsVisible && !token.IsCancellationRequested && Get<TextBlock>(card,"detail").Text.Contains("synthetic hidden action failure",StringComparison.Ordinal)
                && ReferenceEquals(card.Latest,completed),"Hidden project action failure is discarded or reopens/replaces its snapshot.");
            checks.Add(new { name="visibility.project.hiddenFailure", actualActionError=true, hiddenErrorRetained=true, previousStatusRetained=true, noReopen=true });
        } finally {
            card.Close(); source.TrySetResult(Response(Status(card.Reference.Id,"stopped","cleanup")));
            if (action is not null) await action;
        }
    }

    private static async Task CheckRemoteReadLifetimeAsync(DeckController controller,List<object> checks)
    {
        var firstSource=Pending<RemoteSnapshot>(); var secondSource=Pending<RemoteSnapshot>(); var reads=0; var token=default(CancellationToken);
        var settings=controller.Settings.RemoteCardList.Single(card => card.Id == "legacy.pulls");
        var card=new RemoteCard(controller,settings,live:true,snapshotReader:cancellation => {
            reads++; token=cancellation; return reads == 1 ? firstSource.Task : secondSource.Task;
        });
        Task? read=null;
        try {
            card.SetDeckVisible(false);
            Require(reads == 0 && typeof(RemoteCard).GetField("polling",BindingFlags.Instance|BindingFlags.NonPublic) is null,
                "Initially hidden remote owner reads or retains an independent provider timer.");
            var initial=SampleDeck.Remote("pullRequests",8) with { CardID=card.CardID }; card.ApplySnapshot(initial); card.SetExpanded(true);
            card.SetDeckVisible(true); read=card.RefreshAsync(); Invoke(card,"ShowAll");
            var list=Get<Window>(card,"listWindow"); var handle=new WindowInteropHelper(card).Handle; var listHandle=new WindowInteropHelper(list).Handle;
            Require(reads == 1 && card.DeckVisible && list.IsVisible && listHandle != 0,
                "The shared-pass read entry point did not start one owned read and ordinary list.");
            card.SetDeckVisible(false); card.Summon(); await card.RefreshAsync();
            Require(!card.IsVisible && !card.DeckVisible && !token.IsCancellationRequested
                && reads == 1 && list.IsVisible,"Hidden remote cancels its in-flight read/list or continues new polling/reads.");
            var completed=SampleDeck.Remote("pullRequests",4) with { CardID=card.CardID }; firstSource.SetResult(completed); await read;
            Require(!card.IsVisible && ReferenceEquals(card.Latest,completed) && ReferenceEquals(Get<Window>(card,"listWindow"),list)
                && Get<StackPanel>(card,"fullRows").Children.Count == completed.Rows.Length*2 && Get<bool>(card,"expanded"),
                "Remote pending result fails to update retained hidden snapshot/list/expansion.");
            checks.Add(new { name="visibility.remote.pendingRead", actualLifetimeRead=true, initiallyHiddenDoesNotRead=true,
                hiddenAdmissionStopped=true, independentTimerAbsent=true, ownReadNotCancelled=true, ordinaryListAndExpansionRetained=true, hiddenResultCached=true });

            card.SetDeckVisible(true); read=card.RefreshAsync(); card.SetDeckVisible(false); card.SetDeckVisible(true);
            Require(reads == 2 && ReferenceEquals(read,card.RefreshAsync()) && new WindowInteropHelper(card).Handle == handle
                && new WindowInteropHelper(list).Handle == listHandle && card.DeckVisible && !token.IsCancellationRequested,
                "Remote reveal duplicates its pending shared-pass read or loses HWND/list identity.");
            var listClosed=false; list.Closed+=(_,_)=>listClosed=true; card.Close();
            Require(token.IsCancellationRequested && listClosed,
                "Actual remote disposal leaves its own request/list alive.");
            secondSource.SetResult(initial); await read;
            Require(ReferenceEquals(card.Latest,completed),"Disposed remote accepts a late request response.");
            checks.Add(new { name="visibility.remote.revealAndClose", revealReadCoalesced=true, sharedPassEntryPoint=true,
                widgetAndListHwndRetained=true, actualCloseCancelsAndClosesOwnedList=true, lateDisposedResultIgnored=true });
        } finally {
            card.Close(); firstSource.TrySetResult(SampleDeck.Remote("pullRequests",0)); secondSource.TrySetResult(SampleDeck.Remote("pullRequests",0));
            if (read is not null) await read;
        }
    }

    private static async Task CheckRemoteMutationLifetimeAsync(DeckController controller,List<object> checks)
    {
        var source=Pending<bool>(); var token=default(CancellationToken); var reads=0;
        var settings=controller.Settings.RemoteCardList.Single(card => card.Id == "github.inbox");
        var snapshot=SampleDeck.Remote("inbox",6) with { CardID=settings.Id };
        var card=new RemoteCard(controller,settings,live:false,snapshotReader:_ => { reads++; return Task.FromResult(snapshot); });
        Task? mutation=null;
        try {
            card.SetDeckVisible(true); card.ApplySnapshot(snapshot); card.SetExpanded(true); Invoke(card,"ShowAll");
            var list=Get<Window>(card,"listWindow"); var handle=new WindowInteropHelper(card).Handle;
            mutation=InvokeTask(card,"MutateAsync",new Func<CancellationToken,Task>(cancellation => { token=cancellation; return source.Task; }));
            card.SetDeckVisible(false); Invoke(card,"ShowProgress","marking:1:3"); await Dispatcher.Yield(DispatcherPriority.Background);
            Require(card.IsMutating && !token.IsCancellationRequested && list.IsVisible && !Get<StackPanel>(card,"fullRows").IsEnabled,
                "Hidden remote mutation cancels actual CTS/closes ordinary list or loses mutation gating.");
            var progress=Get<TextBlock>(card,"footer").Text;
            card.SetDeckVisible(true);
            Require(new WindowInteropHelper(card).Handle == handle && card.IsMutating && Get<TextBlock>(card,"footer").Text == progress
                && !Get<Button>(card,"collapseButton").IsEnabled && !token.IsCancellationRequested,
                "Showing a mutating remote loses its progress, native identity or busy controls.");
            card.SetDeckVisible(false); source.SetResult(true); await mutation;
            Require(!card.IsVisible && !card.IsMutating && reads == 0 && ReferenceEquals(Get<Window>(card,"listWindow"),list)
                && Get<StackPanel>(card,"fullRows").IsEnabled && ReferenceEquals(card.Latest,snapshot),
                "Hidden remote mutation completion reopens/refetches or discards retained list/snapshot.");
            checks.Add(new { name="visibility.remote.pendingMutation", actualMutationTaskAndCts=true, hideShowKeepsProgressAndBusyControls=true,
                ordinaryListRetained=true, completionWhileHiddenNoReadOrReopen=true });

            card.SetDeckVisible(true); source=Pending<bool>(); mutation=InvokeTask(card,"MutateAsync",new Func<CancellationToken,Task>(cancellation => { token=cancellation; return source.Task; }));
            card.SetDeckVisible(false); source.SetException(new IOException("synthetic hidden inbox failure")); await mutation;
            Require(!card.IsVisible && !card.IsMutating && Get<TextBlock>(card,"footer").Text.Contains("synthetic hidden inbox failure",StringComparison.Ordinal)
                && ReferenceEquals(card.Latest,snapshot),"Hidden remote mutation failure is discarded or reopens the widget.");
            checks.Add(new { name="visibility.remote.hiddenMutationFailure", actualMutationError=true, hiddenFailureRetained=true, previousSnapshotRetained=true });
        } finally {
            card.Close(); source.TrySetResult(true); if (mutation is not null) await mutation;
        }
    }

    private static async Task CheckContextStateAsync(DeckController controller,List<object> checks)
    {
        var project=controller.LocalViews.Single(card => card.Reference.Id == "local.visibility");
        var remote=controller.RemoteViews.Single(card => card.CardID == "github.inbox");
        remote.SetMutationPresentation(false); remote.ApplySnapshot(SampleDeck.Remote("inbox",6) with { CardID=remote.CardID });
        foreach (var language in DevDeck.Windows.Core.Localization.Languages) {
            Text.Use(language); project.SetCollapsed(false); remote.SetCollapsed(false); controller.SetLocked(false);
            OpenMenu(project); OpenMenu(remote);
            foreach (var window in new Window[] { project,remote }) {
                var items=window.ContextMenu!.Items.OfType<MenuItem>().ToArray();
                Require(new[] { "compact","hide","settings","lock","tidy","refresh" }.All(tag => items.Any(item => item.Tag as string == tag)),
                    "Card context menu loses this-card or deck actions: " + language);
                Require(Menu(window,"hide").Header.ToString() == Text.L("menu.card.hide") && Menu(window,"hide").IsEnabled
                    && Menu(window,"settings").Header.ToString() == Text.L("menu.card.settings"),"Contextual Hide/Settings labels or availability are stale: " + language);
            }
            project.SetCollapsed(true); remote.SetCollapsed(true); controller.SetLocked(true); OpenMenu(project); OpenMenu(remote);
            Require(Menu(project,"compact").Header.ToString() == Text.L("menu.card.showWhole") && Menu(remote,"compact").Header.ToString() == Text.L("menu.card.showWhole")
                && Menu(project,"lock").IsChecked && Menu(remote,"lock").IsChecked && !Menu(project,"logs").IsEnabled,
                "Reopened context menu ignores external compact/lock/log eligibility: " + language);
            project.ShowOperation("start"); remote.SetMutationPresentation(true); OpenMenu(project); OpenMenu(remote);
            Require(!Menu(project,"qr").IsEnabled && !Menu(remote,"compact").IsEnabled && !Menu(remote,"readRest").IsEnabled && !Menu(remote,"readAll").IsEnabled
                && Menu(project,"hide").IsEnabled && Menu(remote,"hide").IsEnabled,
                "Reopened busy context menu gates QR/Inbox/compact or incorrectly disables Hide: " + language);
            project.ApplySnapshot(Status(project.Reference.Id,"stopped","idle")); remote.SetMutationPresentation(false);
            project.SetCollapsed(false); OpenMenu(project);
            await controller.ToggleLogsAsync(project.Reference); OpenMenu(project);
            Require(Menu(project,"logs").Header.ToString() == Text.L("menu.card.hideLog") && Menu(project,"logs").IsEnabled,
                "Context log label does not follow its actual ordinary window: " + language);
            await controller.ToggleLogsAsync(project.Reference); OpenMenu(project);
            Require(Menu(project,"logs").Header.ToString() == Text.L("menu.card.showLog"),"Context log label stays hidden after closing its actual window: " + language);
            checks.Add(new { name=language+".visibility.context.current", populatedOnOpening=true, hideAndContextualSettings=true,
                compactLockLogStateCurrent=true, busyInboxAndQrGated=true, hideAvailableWhileBusy=true,
                explicitInboxRestAllTwins=true, noWorkerOrCredential=true });
        }
        Text.Use("en"); controller.SetLocked(false); project.SetCollapsed(false); remote.SetCollapsed(false);
    }

    private static ProjectStatus Status(string id,string state,string branch) => new(id,state,branch,"http://localhost:3112","Synthetic",null);
    private static WorkerResponse Response(ProjectStatus status) => new(WorkerProtocol.Version,null,"Test Linux",null,status,null,null);
    private static TaskCompletionSource<T> Pending<T>() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static T Get<T>(object owner,string field) => (T)owner.GetType().GetField(field,BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(owner)!;
    private static object? Invoke(object owner,string method,params object?[] arguments) => owner.GetType().GetMethod(method,BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(owner,arguments);
    private static Task InvokeTask(object owner,string method,params object?[] arguments) => (Task)Invoke(owner,method,arguments)!;
    private static void OpenMenu(Window window) => window.ContextMenu!.RaiseEvent(new RoutedEventArgs(ContextMenu.OpenedEvent));
    private static MenuItem Menu(Window window,string tag) => window.ContextMenu!.Items.OfType<MenuItem>().Single(item => item.Tag as string == tag);

    private static void Require(bool condition, string message) { if (!condition) throw new IOException(message); }
}
