using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using DevDeck.Windows.Core;
using Forms = System.Windows.Forms;

namespace DevDeck.Windows.App;

/// Real production menu clicks with owned recorders/pending readers. No WSL, token or browser.
internal static class TrayCommandActionTests
{
    internal static async Task RunAsync(Application application,List<object> checks)
    {
        var language=Text.Language;
        try {
            foreach(var locale in DevDeck.Windows.Core.Localization.Languages) CheckDashboard(application,locale,checks);
            Text.Use("en");
            await CheckRefreshAsync(application,checks);
        } finally { Text.Use(language); }
    }

    private static DeckSettings DashboardFixture() => new(1,[new("Test Linux","/tmp/devdeck-tray-action-runtime")],[],
        Accounts:[
            new("lab","Synthetic GitLab","gitlab","https://git.example.test",[],[],Browser:"chrome",BrowserProfile:"Lab"),
            new("disabled","Disabled GitHub","github","https://api.github.com",[],[],Enabled:false,Browser:"firefox",BrowserProfile:"Old Firefox profile"),
            new("z-first","First enabled GitHub","github","https://github.enterprise.test/api/v3",[],[],Browser:"brave",BrowserProfile:"Profile 7"),
            new("a-later","Later enabled GitHub","github","https://api.github.com",[],[],Browser:"edge",BrowserProfile:"Profile 4")
        ], RemoteCards:[
            new("legacy.pulls","Hidden pull requests","pullRequests","Test Linux",["a-later"],Enabled:false),
            new("github.inbox","Hidden inbox","inbox","Test Linux",["z-first"],Enabled:false),
            new("github.actions","Hidden Actions","actions","Test Linux",["z-first"],Enabled:false),
            new("gitlab.mergeRequests","Hidden merges","mergeRequests","Test Linux",["lab"],Enabled:false)
        ],Language:"en",Notifications:false);

    private static void CheckDashboard(Application application,string language,List<object> checks)
    {
        var first=DashboardFixture();
        DashboardClick(application,first,language,"brave","Profile 7");
        var none=first with { Accounts=first.AccountList.Select(account => account.Provider == "github" ? account with { Enabled=false } : account).ToArray() };
        DashboardClick(application,none,language,"system",null);
        var reordered=first with { Accounts=[first.AccountList[0],first.AccountList[1],first.AccountList[3],first.AccountList[2]] };
        DashboardClick(application,reordered,language,"edge","Profile 4");
        checks.Add(new { name=language+".tray.openPulls.action", actualMenuClick=true, firstEnabledGithubInSavedOrder=true,
            providerAndDisabledAccountsSkipped=true, selectedBrowserAndProfileRetained=true,
            fixedGithubPullsUrl=true, cardHiddenAndEndpointIndependent=true, noEnabledAccountUsesSystem=true,
            noActualBrowserWorkerCredentialOrSettingsMutation=true });
    }

    private static void DashboardClick(Application application,DeckSettings settings,string language,string browser,string? profile)
    {
        var path=TemporaryPath("dashboard"); var store=new SettingsStore(path); store.Save(settings);
        var opened=new List<(string Browser,string? Profile,string URL)>();
        var controller=new DeckController(application,store,live:false,dashboardOpener:(selected,selectedProfile,url) => opened.Add((selected,selectedProfile,url)));
        try {
            Text.Use(language); var persisted=File.ReadAllBytes(path); var original=JsonSerializer.Serialize(controller.Settings,WorkerProtocol.Json);
            using var menu=Build(controller);
            Row(menu,"tray.openPulls").PerformClick();
            Require(opened.Count == 1 && opened[0] == (browser,profile,"https://github.com/pulls"),
                "Actual tray open-pulls click loses saved account order/profile, uses API endpoint/card scope, or fails the default-browser fallback: "+language);
            Require(File.ReadAllBytes(path).SequenceEqual(persisted) && JsonSerializer.Serialize(controller.Settings,WorkerProtocol.Json) == original
                && controller.AllLocalViews.Length == 0 && controller.AllRemoteViews.Length == 0 && !controller.LocalPollEnabled,
                "Opening the recorded tray dashboard changes settings or starts widgets/polling.");
        } finally { controller.CloseViews(); DeleteSettings(path); }
    }

    private static DeckSettings RefreshFixture()
    {
        CardSettings Local(string id,string distro,string kind="local",bool enabled=true) =>
            new(new(id,distro,kind,"/tmp/devdeck-refresh-"+id,StartCommand:kind == "local" ? "npm run dev" : null),id,enabled,X:64,Y:80,Collapsed:true);
        return new(1,[new("First Linux","/tmp/devdeck-refresh-first"),new("Second Linux","/tmp/devdeck-refresh-second")],[
            Local("ready.a","First Linux"),Local("ready.b","First Linux","ddev"),Local("ready.c","Second Linux"),
            Local("hidden","First Linux",enabled:false),Local("busy","First Linux"),
            new(new("hosted","First Linux","arc","",Arc:new("synthetic")),"Hosted Arc",X:64,Y:80,Collapsed:true)
        ], Accounts:[new("synthetic","Synthetic GitHub","github","https://api.github.com",[],[])],
        RemoteCards:[
            new("remote.ready","Ready remote","pullRequests","First Linux",["synthetic"],Collapsed:true),
            new("remote.hidden","Hidden remote","inbox","First Linux",["synthetic"],Enabled:false,Collapsed:true),
            new("remote.mutating","Mutating remote","actions","First Linux",["synthetic"],Collapsed:true)
        ],Language:"en",Notifications:false);
    }

    private sealed record LocalRead(string ID,string? Cycle,CancellationToken Token);

    private static async Task CheckRefreshAsync(Application application,List<object> checks)
    {
        var path=TemporaryPath("refresh"); var store=new SettingsStore(path); store.Save(RefreshFixture());
        // Controller is live to exercise its production global refresh. Every manually cached
        // owner is live:false with an injected reader/action, and Start is never called.
        var controller=new DeckController(application,store,live:true);
        var reads=new List<LocalRead>(); var counts=new Dictionary<string,int>(StringComparer.Ordinal);
        var localSources=new Dictionary<string,TaskCompletionSource<WorkerResponse>[]>(StringComparer.Ordinal) {
            ["ready.a"]=[Pending<WorkerResponse>(),Pending<WorkerResponse>()],
            ["ready.b"]=[Pending<WorkerResponse>(),Pending<WorkerResponse>()]
        };
        var remoteSources=new[] { Pending<RemoteSnapshot>(),Pending<RemoteSnapshot>() };
        var remoteReads=0; var invalidRemoteReads=0; var remoteToken=default(CancellationToken);
        var actionSource=Pending<WorkerResponse>(); var mutationSource=Pending<bool>();
        var actionToken=default(CancellationToken); var mutationToken=default(CancellationToken);
        Task? action=null; Task? mutation=null; Task? firstRefresh=null; Task? secondRefresh=null;
        var gate=Get<SemaphoreSlim>(controller,"actions"); var gateHeld=false;
        try {
            var locals=Get<List<ProjectCard>>(controller,"cards"); var remotes=Get<List<RemoteCard>>(controller,"remoteCards");
            foreach(var saved in controller.Settings.Cards) {
                var card=new ProjectCard(controller,saved,live:false,statusReader:(cycle,token) => {
                    reads.Add(new(saved.Project.Id,cycle,token)); var count=counts.GetValueOrDefault(saved.Project.Id); counts[saved.Project.Id]=count+1;
                    if(localSources.TryGetValue(saved.Project.Id,out var sources)) return sources[Math.Min(count,sources.Length-1)].Task;
                    return Task.FromResult(Response(saved.Project.Id,cycle ?? "no-cycle"));
                },actionRunner:(_,token,_) => { actionToken=token; return actionSource.Task; });
                locals.Add(card); card.SetDeckVisible(saved.Enabled);
            }
            foreach(var saved in controller.Settings.RemoteCardList) {
                var card=new RemoteCard(controller,saved,live:false,snapshotReader:token => {
                    if(saved.Id != "remote.ready") { invalidRemoteReads++; return Task.FromResult(Remote(saved)); }
                    var index=remoteReads++; remoteToken=token; return remoteSources[Math.Min(index,remoteSources.Length-1)].Task;
                });
                remotes.Add(card); card.SetDeckVisible(RemoteCardCatalog.Active(controller.Settings,saved));
            }
            var busy=locals.Single(card => card.Reference.Id == "busy");
            var mutating=remotes.Single(card => card.CardID == "remote.mutating");
            action=InvokeTask(busy,"PerformAsync","start");
            mutation=InvokeTask(mutating,"MutateAsync",new Func<CancellationToken,Task>(token => { mutationToken=token; return mutationSource.Task; }));
            var windows=locals.Cast<Window>().Concat(remotes).ToArray();
            var handles=windows.ToDictionary(window=>window,window=>new WindowInteropHelper(window).Handle);
            var persisted=File.ReadAllBytes(path);
            await gate.WaitAsync(); gateHeld=true;
            using var menu=Build(controller);
            Row(menu,"tray.refresh").PerformClick();
            Require(reads.Select(read=>read.ID).SequenceEqual(new[] { "ready.a","ready.b","ready.c" })
                && remoteReads == 1 && invalidRemoteReads == 0,
                "Actual tray Refresh click does not read eligible local/remote owners, or reads hidden/link-only/busy/mutating cards.");
            Require(!action.IsCompleted && !mutation.IsCompleted && actionToken.CanBeCanceled && mutationToken.CanBeCanceled && remoteToken.CanBeCanceled
                && !actionToken.IsCancellationRequested && !mutationToken.IsCancellationRequested && !remoteToken.IsCancellationRequested && !controller.LocalPollEnabled,
                "Global tray refresh cancels a pending action/read/mutation or starts the periodic poller in this owned manual fixture.");
            checks.Add(new { name="tray.refresh.eligibility", actualMenuClick=true, controllerLiveWithoutStart=true,
                activeOnly=true, hiddenHostedBusyAndMutatingSkipped=true, mutationGateHeldWithoutBlockingRefresh=true,
                allReadersAndActionsInjected=true, noPeriodicWorkerStarted=true });

            firstRefresh=controller.RefreshAllAsync();
            for(var index=0;index<3;index++) Row(menu,"tray.refresh").PerformClick();
            var firstCycle=reads[0].Cycle;
            Require(reads.Count == 3 && remoteReads == 1 && firstCycle is not null && Guid.TryParseExact(firstCycle,"N",out _)
                && reads.All(read=>read.Cycle == firstCycle && read.Token.CanBeCanceled && !read.Token.IsCancellationRequested),
                "Repeated tray refresh queues duplicate pending reads or loses the single local-cycle identity/owned request tokens.");
            checks.Add(new { name="tray.refresh.pendingCoalescing", repeatedActualClicks=4,
                onePendingReadPerEligibleOwner=true, oneSharedLocalCycle=true, pendingRequestTokensNotCancelled=true });

            var independent=locals.Single(card=>card.Reference.Id == "ready.c"); var readyRemote=remotes.Single(card=>card.CardID == "remote.ready");
            Require(independent.LastRefreshSucceeded && independent.Latest?.Branch == firstCycle
                && !localSources["ready.a"][0].Task.IsCompleted && !localSources["ready.b"][0].Task.IsCompleted,
                "Slow first-distribution reads prevent a second distribution from completing its status.");
            var remoteSnapshot=Remote(controller.Settings.RemoteCardList.Single(saved=>saved.Id == "remote.ready"));
            remoteSources[0].SetResult(remoteSnapshot); await Get<Task>(readyRemote,"refreshing");
            Require(ReferenceEquals(readyRemote.Latest,remoteSnapshot) && !firstRefresh.IsCompleted,
                "Slow local refresh prevents the independent remote snapshot from completing.");
            checks.Add(new { name="tray.refresh.independentResults", secondDistributionCompletesBeforeFirst=true,
                remoteCompletesBeforeSlowLocalBatch=true, noTransportOrActionCancellation=true });

            foreach(var id in new[] { "ready.a","ready.b" }) localSources[id][0].SetResult(Response(id,firstCycle!));
            await firstRefresh;
            Row(menu,"tray.refresh").PerformClick(); secondRefresh=controller.RefreshAllAsync();
            var secondCycle=reads.Last(read=>read.ID == "ready.a").Cycle;
            Require(reads.Count == 6 && remoteReads == 2 && secondCycle is not null && secondCycle != firstCycle
                && reads.Skip(3).All(read=>read.Cycle == secondCycle),
                "Refresh after completion fails to start one fresh local cycle and remote pass.");
            foreach(var id in new[] { "ready.a","ready.b" }) localSources[id][1].SetResult(Response(id,secondCycle!));
            remoteSources[1].SetResult(remoteSnapshot); await secondRefresh;
            Require(windows.All(window=>new WindowInteropHelper(window).Handle == handles[window])
                && File.ReadAllBytes(path).SequenceEqual(persisted) && !actionToken.IsCancellationRequested && !mutationToken.IsCancellationRequested
                && invalidRemoteReads == 0 && reads.All(read=>!read.Token.IsCancellationRequested),
                "Global refresh changes native owner identity/settings or cancels pending work.");
            checks.Add(new { name="tray.refresh.nextCycle", freshCycleAfterCompletion=true,
                noDuplicateEligibleRequests=true, widgetHandlesAndSettingsRetained=true,
                pendingActionsMutationsAndReadTokensPreserved=true });
        } finally {
            if(gateHeld) gate.Release();
            foreach(var owner in controller.AllLocalViews) owner.SetDeckVisible(false);
            foreach(var owner in controller.AllRemoteViews) owner.SetDeckVisible(false);
            actionSource.TrySetResult(Response("busy","cleanup")); mutationSource.TrySetResult(true);
            foreach(var pair in localSources) foreach(var source in pair.Value) source.TrySetResult(Response(pair.Key,"cleanup"));
            foreach(var source in remoteSources) source.TrySetResult(SampleDeck.Remote("pullRequests",0));
            if(action is not null) await action; if(mutation is not null) await mutation;
            if(firstRefresh is not null) await firstRefresh; if(secondRefresh is not null) await secondRefresh;
            controller.CloseViews(); DeleteSettings(path);
        }
    }

    private static RemoteSnapshot Remote(RemoteCardSettings settings) => SampleDeck.Remote(settings.Kind,4) with { CardID=settings.Id };
    private static WorkerResponse Response(string id,string branch) => new(WorkerProtocol.Version,null,"Test Linux",null,new(id,"running",branch,"http://localhost:3112","Synthetic",null),null,null);
    private static TaskCompletionSource<T> Pending<T>() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static string TemporaryPath(string kind) => Path.Combine(Path.GetTempPath(),"devdeck-tray-action-"+kind+"-"+Guid.NewGuid().ToString("N")+".json");
    private static void DeleteSettings(string path) { foreach(var file in new[] { path,path+".bak" }) if(File.Exists(file)) File.Delete(file); }
    private static T Get<T>(object owner,string field) => (T)owner.GetType().GetField(field,BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(owner)!;
    private static Task InvokeTask(object owner,string method,params object?[] arguments) => (Task)owner.GetType().GetMethod(method,BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(owner,arguments)!;
    private static Forms.ContextMenuStrip Build(DeckController controller)
    {
        var menu=new Forms.ContextMenuStrip();
        try { typeof(DeckController).GetMethod("BuildMenu",BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(controller,[menu]); return menu; }
        catch { menu.Dispose(); throw; }
    }
    private static Forms.ToolStripMenuItem Row(Forms.ContextMenuStrip menu,string tag) => menu.Items.OfType<Forms.ToolStripMenuItem>().Single(item=>item.Tag as string == tag);
    private static void Require(bool condition,string message) { if(!condition) throw new IOException(message); }
}
