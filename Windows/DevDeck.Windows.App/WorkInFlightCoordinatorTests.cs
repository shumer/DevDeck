using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal static class WorkInFlightCoordinatorTests
{
    internal static async Task RunAsync(Application application,List<object> checks)
    {
        await RoutesAsync(checks);
        await FailuresAsync(checks);
        await RetainedOwnerAsync(application,checks);
        await CurrentTargetsAsync(application,checks);
        await PlacementAsync(application,checks);
    }

    private static async Task RoutesAsync(List<object> checks)
    {
        var first = Pending<CheckoutResult>(); var calls = new List<CheckoutRequest>(); var tokens = new List<CancellationToken>();
        var refs = new[]{Ref("a","Alpha"),Ref("a2","Alpha"),Ref("b","Beta"),Ref("b2","Beta")};
        var published = new List<CheckoutEntry[]>(); var current = true;
        var endpoint = new Endpoint((request,token) => {
            calls.Add(request);tokens.Add(token);
            return request.Reference.ProjectID=="a" ? first.Task : Task.FromResult(Result(request));
        });
        using var lifetime = new CancellationTokenSource();
        var coordinator = new WorkInFlightScanCoordinator(_=>Task.FromResult<IWorkInFlightEndpoint>(endpoint));
        var run = coordinator.RunAsync(refs,"pass",()=>current,lifetime.Token,published.Add);
        Require(calls.Select(call=>call.Reference.ProjectID).SequenceEqual(new[]{"a","b","b2"}) && published.Count==1
            && published[0].Select(entry=>entry.Reference.ProjectID).SequenceEqual(new[]{"b","b2"}),
            "Slow first distro blocks its independent sibling or same-route reads are not sequential.");
        Add(checks,"wif.scan.independentRoutes",new{serialPerRoute=true, siblingCompletesWhileFirstHeld=true});
        first.SetResult(Result(calls[0])); var result=await run;
        Require(result.Completed && result.Entries.Select(entry=>entry.Reference.ProjectID).SequenceEqual(refs.Select(reference=>reference.ProjectID))
            && calls.Count==4 && tokens.All(token=>!token.IsCancellationRequested),"Scan loses frozen global selection order or cancels readers.");
        Add(checks,"wif.scan.frozenMerge",new{allResultsOrderedAfterMerge=true,noCancellation=true});

        first=Pending<CheckoutResult>(); calls.Clear();published.Clear();current=true;
        run=coordinator.RunAsync(refs,"next",()=>current,lifetime.Token,published.Add); current=false;
        Require(!tokens.Any(token=>token.IsCancellationRequested),"Supersession cancels a started checkout read.");
        first.SetResult(Result(calls[0]));result=await run;
        Require(!result.Completed && !calls.Any(call=>call.Reference.ProjectID=="a2") && result.Entries.Length==3,
            "Superseded pass admits another read or fabricates an outcome for an unstarted checkout.");
        Add(checks,"wif.scan.supersession",new{currentReadFinishes=true,nextAdmissionStopped=true,notSuccessfulFullPass=true});
    }

    private static async Task FailuresAsync(List<object> checks)
    {
        var factories=0;var reads=0;
        var endpoint=new Endpoint((request,_)=>{reads++;return Task.FromResult(Result(request));},[]);
        var coordinator=new WorkInFlightScanCoordinator(_=>{factories++;return Task.FromResult<IWorkInFlightEndpoint>(endpoint);});
        var result=await coordinator.RunAsync([Ref("a","Alpha"),Ref("b","Alpha")],"pass",()=>true,CancellationToken.None);
        Require(factories==1 && reads==0 && result.Completed && result.Entries.All(entry=>entry.State is null && entry.Result.Failure?.Code=="runnerUnavailable"),
            "Missing route capability reconnects per checkout or claims a clean repository.");
        Add(checks,"wif.scan.capabilityFailure",new{oneRouteSetup=true,noRead=true,allFailedHonest=true});
        endpoint=new Endpoint((request,_)=>Task.FromResult(Result(request) with{Path="/tmp/foreign",State=new("main",0,0,0,true,0,null,false,false,[])}));
        coordinator=new(_=>Task.FromResult<IWorkInFlightEndpoint>(endpoint));
        result=await coordinator.RunAsync([Ref("a","Alpha")],"pass",()=>true,CancellationToken.None);
        Require(!result.Completed && result.Entries.Length==0,"Malformed endpoint identity enters the aggregate cache or is a qualified full pass.");
        Add(checks,"wif.scan.malformedIdentity",new{foreignStateAndTargetDiscarded=true,incompleteReceipt=true});
        var calls=new List<string>();
        endpoint=new Endpoint((request,_)=>{
            calls.Add(request.Reference.ProjectID);
            return request.Reference.ProjectID=="b"?Task.FromException<CheckoutResult>(new WorkerException("disconnected","owned fixture transport lost")):Task.FromResult(Result(request));
        });coordinator=new(_=>Task.FromResult<IWorkInFlightEndpoint>(endpoint));
        result=await coordinator.RunAsync([Ref("a","Alpha"),Ref("b","Alpha"),Ref("c","Alpha")],"pass",()=>true,CancellationToken.None);
        Require(!result.Completed&&calls.SequenceEqual(new[]{"a","b"})&&result.Entries.Select(entry=>entry.Reference.ProjectID).SequenceEqual(new[]{"a"}),
            "Lost transport is replayed or manufactures outcomes for unstarted reads.");
        Add(checks,"wif.scan.lostTransport",new{qualifiedEarlierDataRetained=true,noReplayOrLaterAdmission=true,fullPassIncomplete=true});
    }

    private static async Task RetainedOwnerAsync(Application app,List<object> checks)
    {
        var path=Temp();var store=new SettingsStore(path);store.Save(Fixture());
        var pending=Pending<CheckoutResult>(); var calls=new List<CheckoutRequest>();var token=default(CancellationToken);
        var endpoint=new Endpoint((request,cancellation)=>{calls.Add(request);token=cancellation;return calls.Count==1?pending.Task:Task.FromResult(Result(request,true));});
        var controller=new DeckController(app,store,live:false,checkoutEndpointFactory:_=>Task.FromResult<IWorkInFlightEndpoint>(endpoint));
        Task<WorkInFlightSnapshot>? read=null;var gate=Get<SemaphoreSlim>(controller,"actions");var held=false;
        try{
            Rebuild(controller);var owner=controller.WorkInFlightView!;var handle=new WindowInteropHelper(owner).Handle;
            await gate.WaitAsync();held=true;read=controller.FetchWorkInFlightAsync(CancellationToken.None);
            var repeated=controller.FetchWorkInFlightAsync(CancellationToken.None);
            Require(ReferenceEquals(read,repeated) && calls.Count==1 && !read.IsCompleted && !token.IsCancellationRequested,
                "WIF blocks on lifecycle gate or stacks repeated passes.");
            Add(checks,"wif.controller.gateAndCoalescing",new{lifecycleGateIndependent=true,onePendingPass=true});
            var before=controller.Settings;await controller.SetWIFVisibleAsync(false);
            Require(!owner.IsVisible && ReferenceEquals(controller.WorkInFlightView,owner) && new WindowInteropHelper(owner).Handle==handle
                && !token.IsCancellationRequested && controller.Settings.Cards.SequenceEqual(before.Cards) && controller.Settings.AnnouncedAlerts.SequenceEqual(before.AnnouncedAlerts),
                "WIF hide replaces owner/cancels read/writes project visibility or Seen while lifecycle gate is held.");
            pending.SetResult(Result(calls[0],true));var hidden=await read;
            Require(hidden.Stale && hidden.CheckedAt is null && calls.Count==1 && Get<AttentionTracker>(controller,"attention").SignalItems.Length==0,
                "Hidden pending result admits another checkout or restores attention/full-pass time.");
            Add(checks,"wif.controller.hiddenPending",new{sameHwnd=true,tokenRetained=true,noHiddenNextReadOrAttention=true,incompleteTimestampHonest=true});
            await controller.SetWIFVisibleAsync(true);var fresh=await controller.FetchWorkInFlightAsync(CancellationToken.None);
            Require(!fresh.Stale && fresh.CheckedAt is not null && fresh.SuccessfulCount==2 && ReferenceEquals(controller.WorkInFlightView,owner)
                && new WindowInteropHelper(owner).Handle==handle && Get<AttentionTracker>(controller,"attention").BadgeCount==0
                && Get<AttentionTracker>(controller,"attention").SignalItems.Length==2,"Reveal loses owner or informational age signals become badges.");
            Add(checks,"wif.controller.revealFresh",new{sameOwner=true,allConfiguredHiddenSourcesRead=true,informationalBadgeZero=true});
            var metadataPending=Pending<CheckoutResult>();calls.Clear();
            endpoint.Reader=(request,cancellation)=>{calls.Add(request);token=cancellation;return calls.Count==1?metadataPending.Task:Task.FromResult(Result(request));};
            read=controller.FetchWorkInFlightAsync(CancellationToken.None);
            gate.Release();held=false;
            await controller.SaveSettingsAsync(settings=>settings with{Cards=settings.Cards.Select(card=>card.Project.Id=="one"?card with{Project=card.Project with{Path="/tmp/moved"}}:card).ToArray()});
            Require(ReferenceEquals(controller.WorkInFlightView,owner) && !token.IsCancellationRequested,"Metadata change closes aggregate reader/owner.");
            metadataPending.SetResult(Result(calls[0],true));var stale=await read;
            Require(stale.Stale && !stale.Entries.Any(entry=>entry.Reference.Path=="/tmp/one")
                && !Get<AttentionTracker>(controller,"attention").SignalItems.Any(item=>item.Action.Checkout?.Path=="/tmp/one"),
                "Superseded folder read retains an old terminal target or attention.");
            Add(checks,"wif.controller.metadataRevision",new{changedFolderResultDropped=true,sameAggregateOwner=true,readNotCancelled=true});
            var renamePending=Pending<CheckoutResult>();calls.Clear();
            endpoint.Reader=(request,cancellation)=>{calls.Add(request);token=cancellation;return calls.Count==1?renamePending.Task:Task.FromResult(Result(request));};
            read=controller.FetchWorkInFlightAsync(CancellationToken.None);
            await controller.SaveSettingsAsync(settings=>settings with{Cards=settings.Cards.Select(card=>card.Project.Id=="one"?card with{Title="Renamed authoritative title"}:card).ToArray()});
            renamePending.SetResult(Result(calls[0],true));var renamed=await read;
            Require(renamed.Stale && renamed.Entries.Single(entry=>entry.Reference.ProjectID=="one") is{State:not null,Reference.Title:"Renamed authoritative title"}
                && !token.IsCancellationRequested && Get<AttentionTracker>(controller,"attention").SignalItems.Length==0,
                "Title-only metadata change discards current tuple physical data or restores old attention.");
            Add(checks,"wif.controller.renameRebase",new{sameTuplePhysicalCacheRetained=true,currentTitleRebased=true,staleAttentionSuppressed=true});
        }finally{if(held)gate.Release();pending.TrySetResult(calls.Count>0?Result(calls[0]):Result(new(CheckoutCatalog.CardID,"cleanup",Ref("one","Alpha"))));controller.CloseViews();Delete(path);}
    }

    private static async Task CurrentTargetsAsync(Application app,List<object> checks)
    {
        var path=Temp();var store=new SettingsStore(path);store.Save(Fixture() with{Cards=[Card("one","Alpha","/tmp/shared"),Card("two","Beta","/tmp/shared")]});
        var opened=new List<CheckoutTarget>();var controller=new DeckController(app,store,live:false,checkoutTerminalOpener:opened.Add);
        try{
            controller.OpenCheckoutTerminal(new("Beta","two","/tmp/shared"));
            controller.OpenCheckoutTerminal(new("Alpha","two","/tmp/shared"));
            controller.OpenCheckoutTerminal(new("Beta","two","/tmp/foreign"));
            Require(opened.SequenceEqual(new[]{new CheckoutTarget("Beta","two","/tmp/shared")}),"Terminal chooses first enabled path or accepts a borrowed target.");
            Add(checks,"wif.terminal.exactHiddenDistro",new{hiddenSourceEligible=true,samePathDifferentDistrosExact=true,foreignTargetsNoOp=true,recordedOnly=true});
            await controller.SaveSettingsAsync(settings=>settings with{Cards=settings.Cards.Where(card=>card.Project.Id!="two").ToArray()});
            controller.OpenCheckoutTerminal(new("Beta","two","/tmp/shared"));await controller.SetWIFVisibleAsync(false);
            controller.OpenCheckoutTerminal(new("Alpha","one","/tmp/shared"));
            Require(opened.Count==1,"Removed source or disabled aggregate still launches terminal.");
            Add(checks,"wif.terminal.currentEligibility",new{removedAndParentHiddenNoOp=true,noExternalTerminal=true});
        }finally{controller.CloseViews();Delete(path);}
    }

    private static async Task PlacementAsync(Application app,List<object> checks)
    {
        var path=Temp();var store=new SettingsStore(path);store.Save(new(1,[],[],Language:"en",SeenAlerts:["remember"],WorkInFlight:new(true,84,96,true)));
        var controller=new DeckController(app,store,live:false);
        try{
            Rebuild(controller);var owner=controller.WorkInFlightView!;var handle=new WindowInteropHelper(owner).Handle;
            controller.SaveArrangement("Only Git");await controller.SetWIFVisibleAsync(false);controller.SavePosition(CheckoutCatalog.CardID,240,260);controller.SetCardCollapsed(CheckoutCatalog.CardID,false);
            await controller.ApplyArrangementAsync("Only Git");
            Require(controller.Settings.ArrangementMatches("Only Git") && controller.Settings.WorkInFlight==new WorkInFlightSettings(true,84,96,true)
                && ReferenceEquals(controller.WorkInFlightView,owner) && new WindowInteropHelper(owner).Handle==handle && owner.IsVisible
                && controller.Settings.AnnouncedAlerts.SequenceEqual(new[]{"remember"}) && controller.Settings.RemoteCards is null,
                "Aggregate arrangement omits placement or replaces owner/Seen/unrelated optional array.");
            Add(checks,"wif.arrangement.nativeApply",new{visibilityCompactXYRestored=true,sameHwnd=true,noAccountsOrWorkers=true,seenRetained=true});
            await controller.ArrangeAsync(new Rect(0,0,1200,900));controller.SetFloating(true);controller.SetFloating(false);controller.ShowCards();
            Require(owner.IsVisible && new WindowInteropHelper(owner).Handle==handle && WidgetWindow.IsExcluded(owner)
                && owner.Left==controller.Settings.WorkInFlight!.X && owner.Top==controller.Settings.WorkInFlight.Y && controller.Settings.RemoteCards is null,
                "Aggregate-only tidy/modes/summon misses native owner or its precise saved position.");
            Add(checks,"wif.deck.aggregateOnly",new{tidyModesSummonIncluded=true,precisePlacement=true,altTabExcluded=true});
        }finally{controller.CloseViews();Delete(path);}
    }

    private sealed class Endpoint(Func<CheckoutRequest,CancellationToken,Task<CheckoutResult>> reader,string[]? capabilities=null):IWorkInFlightEndpoint
    {
        internal Func<CheckoutRequest,CancellationToken,Task<CheckoutResult>> Reader=reader;
        public string[] Capabilities{get;}=capabilities??[CheckoutValidation.Capability];
        public Task<CheckoutResult> ReadAsync(CheckoutRequest request,CancellationToken cancellation)=>Reader(request,cancellation);
    }
    private static CheckoutReference Ref(string id,string distro)=>new(id,distro,"/tmp/"+id,id);
    private static CardSettings Card(string id,string distro,string path)=>new(new(id,distro,"local",path,StartCommand:"npm run dev"),id,Enabled:false);
    private static DeckSettings Fixture()=>new(1,[new("Alpha","/tmp/devdeck-owned-alpha"),new("Beta","/tmp/devdeck-owned-beta")],[Card("one","Alpha","/tmp/one"),Card("two","Alpha","/tmp/two")],Language:"en",WorkInFlight:new(true,64,80,true));
    internal static CheckoutResult Result(CheckoutRequest request,bool aged=false)
    {
        var now=(double)DateTimeOffset.UtcNow.ToUnixTimeSeconds();var since=now-4*86400;
        var state=aged?new CheckoutState("main",0,1,0,true,1,since,true,true,[new("unpushed",1)]):new("main",0,0,0,true,0,null,false,false,[]);
        var id=CheckoutValidation.SignalIdentity(request.Reference,true);
        return new(request.CardID,request.PassToken,request.Reference.ProjectID,request.Reference.Path,now,state,null,
            aged?[new(id,id,"goodToKnow","unpushed","One local commit","main · four days",since,new("openTerminal",Path:request.Reference.Path,Checkout:new(request.Reference.Distribution,request.Reference.ProjectID,request.Reference.Path)),true,false)]:[]);
    }
    private static void Add(List<object> checks,string name,object details)=>checks.Add(new{name,details});
    private static void Require(bool condition,string message){if(!condition)throw new IOException(message);}
    private static TaskCompletionSource<T> Pending<T>()=>new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static T Get<T>(object owner,string name)=>(T)owner.GetType().GetField(name,BindingFlags.NonPublic|BindingFlags.Instance)!.GetValue(owner)!;
    private static void Rebuild(DeckController controller)=>typeof(DeckController).GetMethod("RebuildCards",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(controller,null);
    private static string Temp()=>Path.Combine(Path.GetTempPath(),"devdeck-wif-controller-"+Guid.NewGuid().ToString("N")+".json");
    private static void Delete(string path){foreach(var file in new[]{path,path+".bak"})if(File.Exists(file))File.Delete(file);}
}
