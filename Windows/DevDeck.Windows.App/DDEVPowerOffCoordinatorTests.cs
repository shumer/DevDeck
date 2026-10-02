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

/// Owned endpoints exercise barriers and actual tray/controller behavior without WSL or Docker.
internal static class DDEVPowerOffCoordinatorTests
{
    internal static async Task RunAsync(Application application,List<object> checks)
    {
        var language=Text.Language; Text.Use("en");
        try
        {
            await CoordinatorChecks(checks);
            await GateAndProgressCheck(application,checks);
            foreach(var locale in DevDeck.Windows.Core.Localization.Languages)
                await ControllerChecks(application,locale,checks);
        }
        finally { Text.Use(language); }
    }

    private static DDEVPowerOffRoute[] Routes() => [
        new("Test One",[new("one","Test One","ddev","/owned/missing", "Visible"),
            new("alias","Test One","ddev","/owned/missing","Hidden alias")]),
        new("Test Two",[new("two","Test Two","ddev","/owned/second","Hidden")])];

    private static async Task CoordinatorChecks(List<object> checks)
    {
        async Task<(DDEVPowerOffOutcome,Endpoint[],List<string>)> Run(Action<Endpoint[]>? configure=null,CancellationToken cancellation=default)
        {
            var routes=Routes(); var trace=new List<string>(); var endpoints=routes.Select(route=>new Endpoint(route,trace)).ToArray();
            configure?.Invoke(endpoints);
            var outcome=await DDEVPowerOffCoordinator.RunAsync("owned-token",routes,endpoints,
                distribution=>new(distribution,7,[]),(_,_)=>{},cancellation);
            return(outcome,endpoints,trace);
        }
        var (ordinary,owners,trace)=await Run();
        Require(ordinary.AnyCommandAttempted && ordinary.UnconfirmedDistributions.Length==0
            && trace.SequenceEqual(new[]{"Test One:prepare","Test Two:prepare","Test One:prepare","Test Two:prepare","Test One:run",
                "Test One:prepare","Test Two:prepare","Test Two:run","Test One:finalize","Test Two:finalize"})
            && owners.All(endpoint=>endpoint.Runs==1) && ordinary.Routes[0].Response!.PowerOff!.Statuses!.Length==2,
            "Shared-server intent barrier/order or aliased hidden result was lost.");
        checks.Add(new{name="ddev.powerOff.allActorBarrier",serialOncePerRoute=true,allActorsRenewBeforeEveryCLI=true,hiddenAliasesRetained=true});

        var (old,oldEndpoints,oldTrace)=await Run(endpoints=>endpoints[1].Capabilities=[]);
        Require(!old.AnyCommandAttempted && oldTrace.Count==0 && oldEndpoints.All(endpoint=>endpoint.Runs==0),"Old participant was checked after another was prepared.");
        checks.Add(new{name="ddev.powerOff.capabilityBarrier",noPreparationOrCLIWithOldWorker=true});

        var (prepareFailure,_,prepareTrace)=await Run(endpoints=>endpoints[1].PrepareFailureAt=1);
        Require(!prepareFailure.AnyCommandAttempted && prepareTrace.All(line=>!line.EndsWith(":run",StringComparison.Ordinal))
            && prepareTrace.Contains("Test One:abort") && prepareTrace.Contains("Test Two:abort")
            && prepareFailure.Routes.Where(route=>route.Response is not null).All(route=>route.Response!.PowerOff!.Statuses!.Length==0),
            "Failed/lost preparation did not abort observed actors without a command.");
        checks.Add(new{name="ddev.powerOff.prepareFailure",noCLI=true,attemptedPreparationCleanup=true,noManufacturedPhysicalState=true});

        var (partial,partialEndpoints,_)=await Run(endpoints=>endpoints[0].FailCommand=true);
        Require(partialEndpoints.All(endpoint=>endpoint.Runs==1) && partial.UnconfirmedDistributions.SequenceEqual(["Test One"])
            && partial.Routes.All(route=>route.Response!.PowerOff!.Statuses!.All(status=>status.State=="stopped")),
            "One command failure cancelled another route or discarded its physical result.");
        checks.Add(new{name="ddev.powerOff.commandFailure",otherRouteContinues=true,physicalStatusesPreserved=true,diagnosticRemainsHonest=true});

        var (renewFailure,renewEndpoints,renewTrace)=await Run(endpoints=>endpoints[1].PrepareFailureAt=3);
        Require(renewFailure.AnyCommandAttempted && renewEndpoints[0].Runs==1 && renewEndpoints[1].Runs==0
            && renewTrace.Contains("Test One:finalize") && renewTrace.Contains("Test Two:finalize")
            && renewFailure.Routes[1].Response!.PowerOff!.CommandState=="notRun", "Failed renewal allowed another CLI or lost sibling physical reconciliation.");
        checks.Add(new{name="ddev.powerOff.renewalBarrier",noFurtherCLI=true,notRunSiblingFinalized=true});

        var (lost,lostEndpoints,_)=await Run(endpoints=>endpoints[0].DisconnectOnRun=true);
        Require(lost.AnyCommandAttempted && lostEndpoints[0].Runs==1 && lostEndpoints[1].Runs==0
            && lost.Routes[0].Response is null && lost.UnconfirmedDistributions.Contains("Test One"), "Lost run was retried or fabricated a completed physical status.");
        checks.Add(new{name="ddev.powerOff.lostRun",noRunRetryOrReconnect=true,unconfirmedRouteRetained=true});

        var (foreign,foreignEndpoints,_)=await Run(endpoints=>endpoints[1].ForeignToken=true);
        Require(!foreign.AnyCommandAttempted && foreignEndpoints.All(endpoint=>endpoint.Runs==0),"Foreign token acknowledgement crossed the barrier.");
        checks.Add(new{name="ddev.powerOff.foreignToken",noPhysicalActionBeforeValidatedIdentity=true});

        var (wrongScope,scopeEndpoints,_)=await Run(endpoints=>endpoints[1].WrongAttention=true);
        Require(wrongScope.AnyCommandAttempted && scopeEndpoints.All(endpoint=>endpoint.Runs==1)
            && wrongScope.Routes[1].Response is null, "Foreign final attention reached a native projection.");
        checks.Add(new{name="ddev.powerOff.finalAttentionIdentity",malformedFinalScopeRejectsEntireProjection=true});

        using var cancellation=new CancellationTokenSource();
        var (cancelled,cancelEndpoints,cancelTrace)=await Run(endpoints=>endpoints[0].OnRun=()=>{cancellation.Cancel();throw new OperationCanceledException(cancellation.Token);},cancellation.Token);
        Require(cancelled.AnyCommandAttempted && cancelEndpoints[0].Runs==1 && cancelEndpoints[1].Runs==0
            && cancelTrace.Contains("Test One:finalize") && cancelTrace.Contains("Test Two:finalize")
            && cancelEndpoints.All(endpoint=>!endpoint.CleanupCancellation),"Cancellation aborted the cleanup or ran another command.");
        checks.Add(new{name="ddev.powerOff.ownedCancellation",cleanupIndependentFromCancelledRunToken=true,noSiblingCLI=true});
    }

    private static async Task ControllerChecks(Application application,string locale,List<object> checks)
    {
        var routes=Routes(); var path=Path.Combine(Path.GetTempPath(),"devdeck-poweroff-controller-"+Guid.NewGuid().ToString("N")+".json");
        var store=new SettingsStore(path);
        store.Save(new(1,routes.Select(route=>new WorkerSettings(route.Distribution,"/owned/fake-runtime")).ToArray(),
            [new(new("one","Test One","ddev","/owned/missing"),"Visible",X:70,Y:90,Collapsed:true),
             new(new("alias","Test One","ddev","/owned/missing"),"Hidden alias",Enabled:false),
             new(new("two","Test Two","ddev","/owned/second"),"Hidden",Enabled:false),
             new(new("arc","Test Two","arc","/owned/arc"),"Arc")],Language:locale,Notifications:false));
        var trace=new List<string>(); var endpoints=routes.Select(route=>new Endpoint(route,trace)).ToArray();
        var confirmed=false; string[]? confirmedRoutes=null;
        var controller=new DeckController(application,store,live:false,
            powerOffConfirmation:names=>{confirmedRoutes=names;return confirmed;},
            powerOffEndpointFactory:distribution=>Task.FromResult<IDDEVPowerOffEndpoint>(endpoints.Single(endpoint=>endpoint.Route.Distribution==distribution)));
        try
        {
            Text.Use(locale); Invoke(controller,"RebuildCards");
            var persisted=File.ReadAllBytes(path); var cached=controller.AllLocalViews.ToArray();
            var handles=cached.Select(card=>new WindowInteropHelper(card).Handle).ToArray();
            foreach(var card in cached)card.ApplySnapshot(new(card.Reference.Id,"running","main","http://localhost:8080",null,null,VersionsLine:"php 8.4 · mysql 8.0"));
            using var menu=new Forms.ContextMenuStrip(); Invoke(controller,"BuildMenu",menu);
            var action=menu.Items.OfType<Forms.ToolStripMenuItem>().Single(item=>item.Tag as string=="tray.ddevPowerOff");
            Require(action.Enabled && action.Text==Text.L("menu.ddev.powerOff"),"Configured hidden DDEV did not expose localized poweroff.");
            action.PerformClick(); await DispatcherPump();
            Require(trace.Count==0 && confirmedRoutes!.SequenceEqual(["Test One","Test Two"])
                && File.ReadAllBytes(path).SequenceEqual(persisted) && cached.All(card=>card.Latest!.State=="running"), "Cancel wrote settings or invoked a worker.");
            checks.Add(new{name=locale+".ddev.powerOff.trayCancel",actualMenuClick=true,allConfiguredDDEVRoutes=true,noWorkerOrSettingsWrite=true});

            confirmed=true; await controller.PowerOffDDEVAsync();
            Require(endpoints.All(endpoint=>endpoint.Runs==1) && controller.LastDDEVPowerOffOutcome?.UnconfirmedDistributions.Length==0
                && controller.AllLocalViews.SequenceEqual(cached) && cached.Select(card=>new WindowInteropHelper(card).Handle).SequenceEqual(handles)
                && cached.Where(card=>card.Reference.Kind=="ddev").All(card=>card.Latest!.State=="stopped")
                && cached.Single(card=>card.Reference.Id=="arc").Latest!.State=="running"
                && File.ReadAllBytes(path).SequenceEqual(persisted) && controller.LocalViews.Length==2
                && !controller.DDEVPowerOffBusy,"Global DDEV changed unrelated owners/config or left hidden DDEV stale/busy.");
            checks.Add(new{name=locale+".ddev.powerOff.cachedOwners",physicalHiddenResults=true,arcPreserved=true,sameHWNDAndPreferences=true,noConfigMutation=true});
        }
        finally { controller.CloseViews(); Delete(path); }
    }

    private static async Task GateAndProgressCheck(Application application,List<object> checks)
    {
        var routes=Routes();var path=Path.Combine(Path.GetTempPath(),"devdeck-poweroff-gate-"+Guid.NewGuid().ToString("N")+".json");
        var store=new SettingsStore(path);
        store.Save(new(1,routes.Select(route=>new WorkerSettings(route.Distribution,"/owned/fake-runtime")).ToArray(),
            routes.SelectMany(route=>route.Projects.Select(project=>new CardSettings(
                new(project.Id,project.Distribution,"ddev",project.Path),project.Title!,Collapsed:true))).ToArray(),Language:"en",Notifications:false));
        var trace=new List<string>();var endpoints=routes.Select(route=>new Endpoint(route,trace){BackgroundProgress=true}).ToArray();
        var controller=new DeckController(application,store,live:false,powerOffConfirmation:_=>true,
            powerOffEndpointFactory:distribution=>Task.FromResult<IDDEVPowerOffEndpoint>(endpoints.Single(endpoint=>endpoint.Route.Distribution==distribution)));
        var gate=(SemaphoreSlim)typeof(DeckController).GetField("actions",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(controller)!;
        var held=false; Task? run=null;
        try
        {
            Invoke(controller,"RebuildCards");foreach(var card in controller.AllLocalViews)card.ApplySnapshot(new(card.Reference.Id,"running",null,null,null,null));
            await gate.WaitAsync();held=true;
            run=controller.PowerOffDDEVAsync();var repeated=controller.PowerOffDDEVAsync();
            using var menu=new Forms.ContextMenuStrip();Invoke(controller,"BuildMenu",menu);
            Require(ReferenceEquals(run,repeated) && !run.IsCompleted && trace.Count==0
                && !menu.Items.OfType<Forms.ToolStripMenuItem>().Single(item=>item.Tag as string=="tray.ddevPowerOff").Enabled,
                "Group request cancelled/bypassed an existing action or allowed duplicate menu action.");
            await controller.SetCardVisibleAsync("one",false);
            Require(!run.IsCompleted && !controller.AllLocalViews.Single(card=>card.Reference.Id=="one").DeckVisible,
                "Visibility waited for the queued poweroff/action gate.");
            gate.Release();held=false;await run;
            Require(controller.AllLocalViews.All(card=>card.Latest!.State=="stopped" && !card.DDEVPowerOffBusy)
                && !controller.AllLocalViews.Single(card=>card.Reference.Id=="one").DeckVisible
                && !controller.DDEVPowerOffBusy,"Group completion restored a hidden card or left stale busy presentation.");
            checks.Add(new{name="ddev.powerOff.actionGateAndVisibility",existingActionWaited=true,repeatCoalesces=true,actualMenuDisabled=true,fastHideRetained=true});
            checks.Add(new{name="ddev.powerOff.backgroundProgress",workerThreadCallbackMarshalledToDispatcher=true,lateProgressCannotOverwritePhysicalCompletion=true});
        }
        finally {if(held)gate.Release();if(run is not null)await run;controller.CloseViews();Delete(path);}
    }

    private sealed class Endpoint(DDEVPowerOffRoute route,List<string> trace) : IDDEVPowerOffEndpoint
    {
        internal readonly DDEVPowerOffRoute Route=route;
        public string[] Capabilities { get; set; }=["ddev.poweroff.transaction"];
        internal int Runs,Prepares,PrepareFailureAt;
        internal bool FailCommand,DisconnectOnRun,ForeignToken,WrongAttention,CleanupCancellation;
        internal bool BackgroundProgress;
        internal Action? OnRun;
        private bool disconnected;
        public async Task<WorkerResponse> CallAsync(string operation,DDEVPowerOffContext context,string[]? activeProjectIDs,CancellationToken cancellation,Action<string>? progress=null)
        {
            var phase=operation["ddev.poweroff.".Length..]; trace.Add(Route.Distribution+":"+phase);
            if(disconnected)throw new WorkerException("disconnected","Owned endpoint disconnected.");
            if(phase=="prepare" && ++Prepares==PrepareFailureAt)throw new WorkerException("workerBusy","Owned preparation failed.");
            if(phase=="run") {
                Runs++;OnRun?.Invoke();
                if(BackgroundProgress)await Task.Run(()=>progress?.Invoke("Owned synthetic progress"));
                else progress?.Invoke("Owned synthetic progress");
                if(DisconnectOnRun){disconnected=true;throw new WorkerException("disconnected","Owned run reply lost.");}
            }
            if(phase is "finalize" or "abort")CleanupCancellation|=cancellation.IsCancellationRequested;
            var command=Runs==0 ? "notRun" : FailCommand ? "failed" : "succeeded";
            var final=phase=="finalize" || phase=="abort" && Runs>0;
            var result=new DDEVPowerOffResult(ForeignToken ? "foreign-token" : context.GroupToken,"instance:"+Route.Distribution,
                phase switch{"prepare"=>"prepared","run"=>"ran","finalize"=>"finalized",_=>"aborted"},phase is "prepare" or "run" ? 600 : 0,
                command,Runs==0 ? null : FailCommand ? 1 : 0,FailCommand && Runs>0 ? new("commandFailed","Owned command failed.") : null,
                final ? "available" : "notChecked",final ? Route.Projects.Select(project=>new ProjectStatus(project.Id,"stopped","main",null,null,null,CheckedAt:10)).ToArray() : []);
            return new WorkerResponse(1,"owned",Route.Distribution,null,null,null,null,
                Attention:WrongAttention && final ? new("local:Foreign",[],[],"ready",true) : null,PowerOff:result);
        }
    }

    private static Task DispatcherPump() => Application.Current.Dispatcher.InvokeAsync(()=>{}).Task;
    private static void Require(bool value,string message){if(!value)throw new IOException(message);}
    private static void Invoke(DeckController controller,string method,params object[] parameters) =>
        typeof(DeckController).GetMethod(method,BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(controller,parameters);
    private static void Delete(string path){if(File.Exists(path))File.Delete(path);if(File.Exists(path+".bak"))File.Delete(path+".bak");}
}
