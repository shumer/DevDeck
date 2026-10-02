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
using System.Windows.Interop;
using System.Windows.Threading;
using DevDeck.Windows.Core;
using Forms=System.Windows.Forms;

namespace DevDeck.Windows.App;

/// Actual controller/menu paths over owned synthetic settings/widgets and injected pending work.
internal static class NativeArrangementTests
{
    private const string Local="local:Test Linux",Pull="legacy.pr",Runs="legacy.actions";

    internal static async Task RunAsync(Application application,List<object> checks)
    {
        await Check("arrangements.save.scoped-state-and-pending-work",async fixture=>{
            fixture.SeedAttention();fixture.StartPendingWork();
            var before=fixture.Capture();
            fixture.Controller.SaveArrangement("  Work & card  ");
            fixture.RequireUnchangedExceptArrangements(before);
            var saved=fixture.Controller.Settings.ArrangementList.Single();
            Require(saved.Name=="Work & card" && saved.Cards.Length==fixture.Controller.Settings.Cards.Length+fixture.Controller.Settings.RemoteCardList.Length,
                "Native save did not capture a trimmed name and every configured permanent identity.");
            Require(saved.Cards.Single(card=>card.Id=="a").Collapsed && fixture.ActionTask is{IsCompleted:false}
                && fixture.LocalReadTask is{IsCompleted:false} && fixture.RemoteReadTask is{IsCompleted:false}
                && !fixture.ActionToken.IsCancellationRequested && !fixture.LocalReadToken.IsCancellationRequested && !fixture.RemoteReadToken.IsCancellationRequested,
                "Save captured temporary busy layout or cancelled/replaced pending work.");
            await fixture.CompletePendingWorkAsync();
            Require(fixture.A.Latest?.State=="running" && fixture.B.Latest?.Branch=="read-result" && fixture.PR.Latest?.Total==3,
                "Save prevented existing injected tasks from publishing their results.");
        });
        await Check("arrangements.forget.scoped-state-and-missing-noop",async fixture=>{
            fixture.Controller.SaveArrangement("Morning");fixture.Controller.SaveArrangement("Work");fixture.Controller.SaveArrangement("Evening");
            fixture.SeedAttention();fixture.StartPendingWork();var before=fixture.Capture();
            fixture.Controller.ForgetArrangement("WORK");fixture.RequireUnchangedExceptArrangements(before);
            Require(fixture.Controller.Settings.ArrangementList.Select(item=>item.Name).SequenceEqual(new[]{"Morning","Evening"}),"Native forget changed another name or its order.");
            var bytes=File.ReadAllBytes(fixture.Store.Path);fixture.Controller.ForgetArrangement("missing");
            Require(File.ReadAllBytes(fixture.Store.Path).SequenceEqual(bytes),"Missing forget rewrote settings/backup or reset a live state.");
            fixture.RequireUnchangedExceptArrangements(before);
            Require(!fixture.ActionToken.IsCancellationRequested && !fixture.LocalReadToken.IsCancellationRequested && !fixture.RemoteReadToken.IsCancellationRequested,
                "Forget cancelled a project action or read.");
            await fixture.CompletePendingWorkAsync();
        });
        await Check("arrangements.apply.fast-with-held-action-gate-and-native-owners",async fixture=>{
            fixture.Controller.SaveArrangement("Work");var saved=fixture.Controller.Settings.ArrangementList.Single();
            await fixture.Controller.SetCardVisibleAsync("b",false);fixture.Controller.SetCardCollapsed("a",false);fixture.Move("a",160,170);fixture.Move(Pull,220,230);
            fixture.SeedAttention();var clock=fixture.Controller.LastCheckedAt;var seen=fixture.Controller.Settings.AnnouncedAlerts.ToArray();var owners=fixture.Windows();
            var gate=(SemaphoreSlim)Field(fixture.Controller,"actions");await gate.WaitAsync();Task? apply=null;
            try {
                apply=fixture.Controller.ApplyArrangementAsync("WORK");
                for(var turn=0;turn<3;turn++)await Dispatcher.Yield(DispatcherPriority.Background);
                Require(apply.IsCompleted,"Applying a saved deck waits for an unrelated mutation gate.");await apply;
            } finally { gate.Release();if(apply is not null)await apply; }
            fixture.RequireOwners(owners);fixture.RequireSavedLayout(saved);
            Require(fixture.Controller.Settings.ArrangementMatches("Work") && fixture.Controller.LastCheckedAt==clock
                && fixture.Controller.Settings.AnnouncedAlerts.SequenceEqual(seen),"Apply restored layout through a global attention/history/check-time reset.");
        });
        await Check("arrangements.apply.current-metadata-new-and-deleted-identities",async fixture=>{
            fixture.Controller.SaveArrangement("Work");var saved=fixture.Controller.Settings.ArrangementList.Single();
            var current=fixture.Controller.Settings;
            var a=current.Cards.Single(card=>card.Project.Id=="a") with { Title="Current title",Project=current.Cards[0].Project with {
                Path="/tmp/current-a",StartCommand="npm run current",HealthURL="http://localhost:4321/health" },
                Browser="edge",BrowserProfile="Profile current",Links=[new("TEST","https://example.test/current")],NotifiesWhenDown=false,Enabled=false,Collapsed=false,X=310,Y=320 };
            var added=new CardSettings(new("new","Test Linux","local","/tmp/new",StartCommand:"npm run added"),"Added",X:710,Y:80);
            var pull=current.RemoteCardList.Single(card=>card.Id==Pull) with { Title="Current PR",AccountIDs=["work","second"],UseAllAccounts=true,Enabled=false,Collapsed=true,X=610,Y=420 };
            fixture.ReplaceSettings(current with { Cards=[a,added],RemoteCards=current.RemoteCardList.Select(card=>card.Id==Pull?pull:card).ToArray(),
                Accounts=current.AccountList.Append(new("second","Second","github","https://api.github.com",[],[])).ToArray(),Locked=true });
            var metadata=fixture.Controller.Settings;var owners=fixture.Windows();
            await fixture.Controller.ApplyArrangementAsync("work");fixture.RequireOwners(owners);
            var restored=fixture.Controller.Settings;var placed=saved.Cards.Single(card=>card.Id=="a");var placedPull=saved.Cards.Single(card=>card.Id==Pull);
            Require(restored.Cards.Single(card=>card.Project.Id=="a")== (a with { X=placed.X,Y=placed.Y,Enabled=placed.Enabled,Collapsed=placed.Collapsed })
                && restored.RemoteCardList.Single(card=>card.Id==Pull)== (pull with { X=placedPull.X,Y=placedPull.Y,Enabled=placedPull.Enabled,Collapsed=placedPull.Collapsed }),
                "Native apply restored old metadata/account scope instead of just the saved layout.");
            Require(!restored.Cards.Any(card=>card.Project.Id=="b") && restored.Cards.Single(card=>card.Project.Id=="new")==added
                && ReferenceEquals(restored.Accounts,metadata.Accounts) && ReferenceEquals(restored.Workers,metadata.Workers) && restored.Locked,
                "Native apply recreated a deleted identity, moved a new card or changed runtime/preferences/accounts.");
            Require(!restored.ArrangementMatches("Work"),"A saved deck still matched after its full configured identity set changed.");
        });
        await Check("arrangements.apply.busy-remote-compact-is-partial-with-matching-preference-allowed",async fixture=>{
            fixture.Controller.SetCardCollapsed(Pull,true);fixture.Controller.SaveArrangement("Compact");
            fixture.Controller.SetCardCollapsed(Pull,false);fixture.Move(Pull,260,270);fixture.PR.SetMutationPresentation(true);
            var handle=new WindowInteropHelper(fixture.PR).Handle;var lifetime=(CancellationTokenSource)Field(fixture.PR,"lifetime");
            await fixture.Controller.ApplyArrangementAsync("Compact");
            var saved=fixture.Controller.Settings.ArrangementList.Single().Cards.Single(card=>card.Id==Pull);var current=fixture.Controller.Settings.RemoteCardList.Single(card=>card.Id==Pull);
            Require(fixture.PR.IsMutating && !current.Collapsed && !fixture.Controller.Settings.ArrangementMatches("Compact")
                && current.X==saved.X && current.Y==saved.Y && new WindowInteropHelper(fixture.PR).Handle==handle && !lifetime.IsCancellationRequested,
                "Busy remote compact refusal cancelled the task, blocked positioning, replaced its owner or claimed a complete match.");
            fixture.PR.SetMutationPresentation(false);await fixture.Controller.ApplyArrangementAsync("Compact");
            Require(fixture.Controller.Settings.ArrangementMatches("Compact") && fixture.Controller.Settings.RemoteCardList.Single(card=>card.Id==Pull).Collapsed,
                "An idle retry did not finish the partial arrangement.");
            fixture.PR.SetMutationPresentation(true);fixture.Move(Pull,280,290);await fixture.Controller.ApplyArrangementAsync("Compact");
            Require(fixture.PR.IsMutating && fixture.Controller.Settings.ArrangementMatches("Compact") && !lifetime.IsCancellationRequested,
                "Already-chosen busy compact state prevented an otherwise matching layout.");fixture.PR.SetMutationPresentation(false);
        });
        await Check("arrangements.apply.hides-selected-live-job-without-cancelling-owner-or-sibling-reads",async fixture=>{
            await fixture.Controller.SetCardVisibleAsync("a",false);fixture.Controller.SaveArrangement("Hidden job");await fixture.Controller.SetCardVisibleAsync("a",true);
            fixture.StartPendingWork();var owners=fixture.Windows();var localRead=fixture.LocalReadTask;var remoteRead=fixture.RemoteReadTask;
            await fixture.Controller.ApplyArrangementAsync("Hidden job");fixture.RequireOwners(owners);
            Require(!fixture.A.DeckVisible && !fixture.A.IsVisible && fixture.ActionTask is{IsCompleted:false}
                && ReferenceEquals(fixture.LocalReadTask,localRead) && ReferenceEquals(fixture.RemoteReadTask,remoteRead)
                && !fixture.ActionToken.IsCancellationRequested && !fixture.LocalReadToken.IsCancellationRequested && !fixture.RemoteReadToken.IsCancellationRequested,
                "Applying hidden visibility destroyed a running selected job or an unrelated in-flight read.");
            await fixture.CompletePendingWorkAsync();
            Require(fixture.A.Latest?.State=="running" && !fixture.A.DeckVisible && fixture.B.Latest?.Branch=="read-result" && fixture.PR.Latest?.Total==3,
                "Hidden selected job completion re-showed its card or failed to update retained results.");
        });
        await Check("arrangements.apply.scoped-attention-pruning-stale-context-and-quiet-reveal",async fixture=>{
            var controller=fixture.Controller;controller.SaveArrangement("Shown");
            await controller.SetCardVisibleAsync("a",false);await controller.SetCardVisibleAsync(Pull,false);controller.SaveArrangement("Hidden");
            await controller.SetCardVisibleAsync("a",true);await controller.SetCardVisibleAsync(Pull,true);
            Baseline(controller,Local,Pull,Runs);
            controller.ObserveAttention(new(Local,[Item("a","a"),Item("b","b"),Item("docker",null,mark:"docker")],
                [LocalAlert("a-old","a"),LocalAlert("b-old","b"),LocalAlert("docker-old","a") with { Source="docker" }]));
            controller.ObserveAttention(new(Pull,[Item("pr",null)],[RemoteAlert("pr-old")]));controller.ObserveAttention(new(Runs,[Item("run",null)],[RemoteAlert("run-old","failedRun")]));Flush(controller);
            var stale=controller.CaptureLocalAttention("Test Linux");var clock=controller.LastCheckedAt;var seen=controller.Settings.AnnouncedAlerts.ToArray();
            await controller.ApplyArrangementAsync("Hidden");
            Require(Items(controller).Select(item=>item.Id).ToHashSet().SetEquals(new[]{"b","run"})
                && QueuedSources(controller).Select(source=>source.Alert.Id).ToHashSet().SetEquals(new[]{"b-old","run-old"}),"Arrangement hide globally reset attention or retained hidden project/Docker/remote queued sources.");
            controller.ObserveAttention(new(Local,[Item("late-a","a")],[LocalAlert("late-b","b")]),stale);
            Require(controller.LastCheckedAt==clock && controller.Settings.AnnouncedAlerts.SequenceEqual(seen) && PendingSources(controller).Length==0,
                "Applying visibility failed to invalidate an older aggregate attention response.");
            await controller.ApplyArrangementAsync("Shown");
            controller.ObserveAttention(new(Local,[Item("a-current","a"),Item("b-current","b")],
                [LocalAlert("unseen-existing-a","a"),LocalAlert("new-b-after-reveal","b")]),controller.CaptureLocalAttention("Test Linux"));
            controller.ObserveAttention(new(Pull,[Item("pr-current",null)],[RemoteAlert("existing-pr-at-reveal")]));
            Require(PendingSources(controller).Select(source=>source.Alert.Id).SequenceEqual(new[]{"new-b-after-reveal"})
                && controller.Settings.AnnouncedAlerts.Contains("unseen-existing-a") && controller.Settings.AnnouncedAlerts.Contains("retained-episode"),
                "Arrangement reveal announced an old selected episode or suppressed a new sibling episode.");
        });
        await Check("arrangements.menu.real-save-cancel-forget-and-stale-apply-paths",async fixture=>{
            fixture.NextName="  Work & пример  ";using var menu=Build(fixture.Controller);
            Row(menu,"arrangement.save").PerformClick();await Turns();
            Require(fixture.NameRequests==1 && fixture.Controller.Settings.ArrangementList.Single().Name=="Work & пример","Tray Save bypassed the name provider or used an untrimmed/lost name.");
            Rebuild(fixture.Controller,menu);var savedRow=Row(menu,"arrangement.apply:Work & пример");
            Require(savedRow.Text=="Work && пример" && savedRow.Checked,"Saved tray row lost its original name/ampersand or current-state tick.");
            fixture.NextName=null;var cancel=File.ReadAllBytes(fixture.Store.Path);Row(menu,"arrangement.save").PerformClick();await Turns();
            Require(fixture.NameRequests==2 && File.ReadAllBytes(fixture.Store.Path).SequenceEqual(cancel),"Cancelling the actual tray Save wrote settings.");
            Row(menu,"arrangement.forget:Work & пример").PerformClick();await Turns();var forgotten=File.ReadAllBytes(fixture.Store.Path);
            Require(fixture.Controller.Settings.ArrangementList.Length==0,"Actual nested Forget action did not remove the selected name.");
            savedRow.PerformClick();await Turns();
            Require(File.ReadAllBytes(fixture.Store.Path).SequenceEqual(forgotten),"An already-open apply row for a removed name changed settings or failed its no-op contract.");
        });
        foreach(var language in DevDeck.Windows.Core.Localization.Languages){
            await Check(language+".arrangements.menu.dynamic-layout-ticks-and-owned-disposal",async fixture=>{
                Text.Use(language);var controller=fixture.Controller;
                controller.SaveArrangement("Morning & triage");controller.SaveArrangement("Evening");using var menu=Build(controller);
                var parent=Row(menu,"tray.arrangements");var apply=Row(menu,"arrangement.apply:Morning & triage");var forget=Row(menu,"arrangement.forget:Morning & triage");
                Require(parent.Text==Text.L("menu.arrangements") && apply.Owner==parent.DropDown && apply.Checked && Row(menu,"arrangement.apply:Evening").Checked,
                    language+": submenu does not reflect both saved decks matching the same current state.");
                Require(Row(menu,"arrangement.save").Text==Text.L("arrangements.save") && Row(menu,"arrangement.forgetMenu").Text==Text.L("button.remove")
                    && forget.Text==Text.L("arrangements.forget","Morning & triage").Replace("&","&&",StringComparison.Ordinal),language+": saved/forget/save labels or explicit remove group are missing.");
                var origin=controller.Settings.Cards.Single(card=>card.Project.Id=="a");fixture.Move("a",origin.X+40,origin.Y);Rebuild(controller,menu);
                Require(!Row(menu,"arrangement.apply:Morning & triage").Checked && !Row(menu,"arrangement.apply:Evening").Checked,
                    language+": dragging out of saved geometry leaves a last-chosen-name tick.");
                Require(apply.IsDisposed && forget.IsDisposed,"Rebuilding arrangements detached native owned apply/forget rows without disposing them.");
                fixture.Move("a",origin.X,origin.Y);await controller.SetCardVisibleAsync("a",false);Rebuild(controller,menu);
                Require(!Row(menu,"arrangement.apply:Morning & triage").Checked,language+": changed visibility did not invalidate the checkmark.");
                await controller.SetCardVisibleAsync("a",true);controller.SetCardCollapsed("a",!origin.Collapsed);Rebuild(controller,menu);
                Require(!Row(menu,"arrangement.apply:Morning & triage").Checked,language+": changed preferred compact state did not invalidate the checkmark.");
                controller.SetCardCollapsed("a",origin.Collapsed);Rebuild(controller,menu);
                Require(Row(menu,"arrangement.apply:Morning & triage").Checked && Row(menu,"arrangement.apply:Evening").Checked,
                    language+": restoring current geometry/visibility/compact did not restore matching ticks.");
                var remove=Row(menu,"arrangement.forget:Evening");remove.PerformClick();await Turns();Rebuild(controller,menu);
                Require(!Rows(menu).Any(row=>row.Tag as string=="arrangement.apply:Evening") && Row(menu,"arrangement.apply:Morning & triage").Checked,
                    language+": forgetting a name removed another saved row or left the removed one reachable.");
            });
        }

        async Task Check(string name,Func<Fixture,Task> action)
        {
            await using var fixture=new Fixture(application);await action(fixture);fixture.RequireIsolation();
            checks.Add(new { name, syntheticController=true, noWorkerOrCredential=true, noActualTrayOrBalloon=true, cachedOwnersRetained=true });
        }
    }

    private sealed record NativeOwner(Window Window,nint Handle,object? Snapshot);
    private sealed record Captured(DeckSettings Settings,string Json,DateTimeOffset? Clock,string Signals,string Pending,string Queued,Dictionary<string,NativeOwner> Owners);
    private sealed record Source(string Scope,DeckAlert Alert);

    private sealed class Fixture:IAsyncDisposable
    {
        private readonly string path=Path.Combine(Path.GetTempPath(),"devdeck-native-arrangement-"+Guid.NewGuid().ToString("N")+".json");
        private readonly TaskCompletionSource<WorkerResponse> actionSource=new(TaskCreationOptions.RunContinuationsAsynchronously),localReadSource=new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly TaskCompletionSource<RemoteSnapshot> remoteReadSource=new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal SettingsStore Store{get;}
        internal DeckController Controller{get;}
        internal ProjectCard A=>Controller.AllLocalViews.Single(card=>card.Reference.Id=="a");
        internal ProjectCard B=>Controller.AllLocalViews.Single(card=>card.Reference.Id=="b");
        internal RemoteCard PR=>Controller.AllRemoteViews.Single(card=>card.CardID==Pull);
        internal string? NextName{get;set;}
        internal int NameRequests{get;private set;}
        internal Task? ActionTask{get;private set;}
        internal Task? LocalReadTask{get;private set;}
        internal Task? RemoteReadTask{get;private set;}
        internal CancellationToken ActionToken{get;private set;}
        internal CancellationToken LocalReadToken{get;private set;}
        internal CancellationToken RemoteReadToken{get;private set;}

        internal Fixture(Application application)
        {
            Store=new(path);Store.Save(new DeckSettings(1,[new("Test Linux","/tmp/synthetic-arrangements-runtime")],
                [new(new("a","Test Linux","local","/tmp/a",StartCommand:"npm run fixture"),"A",X:32,Y:40,Collapsed:true),
                 new(new("b","Test Linux","ddev","/tmp/b"),"B",X:500,Y:40)],
                Accounts:[new("work","Work","github","https://api.github.com",[],[],NotifiesBlocked:true,NotifiesFailedRuns:true),new("lab","Lab","gitlab","https://gitlab.com",[],[])],
                RemoteCards:[new(Pull,"PR","pullRequests","Test Linux",["work"],X:32,Y:450),new(Runs,"Actions","actions","Test Linux",["work"],X:500,Y:450,Collapsed:true),
                    new("legacy.inbox","Inbox","inbox","Test Linux",["work"],Enabled:false),new("legacy.lab","MR","mergeRequests","Test Linux",["lab"],Enabled:false)],
                Language:"en",Notifications:true,SeenAlerts:["retained-episode"]));
            Controller=new(application,Store,live:false,arrangementNameProvider:()=>{NameRequests++;return NextName;});
            var locals=(List<ProjectCard>)Field(Controller,"cards");var localConfigurations=(Dictionary<string,CardSettings>)Field(Controller,"localConfigurations");
            foreach(var card in Controller.Settings.Cards){
                var view=new ProjectCard(Controller,card,live:false,phoneAddress:()=>"192.0.2.1",copyPhoneLink:_=>{},
                    statusReader:(_,token)=>card.Project.Id=="b"?ReadLocal(token):Task.FromResult(Response(Status(card.Project.Id,"running","post-action"))),
                    actionRunner:(_,token,_)=>{ActionToken=token;return actionSource.Task;});
                locals.Add(view);localConfigurations.Add(card.Project.Id,card);
            }
            var remotes=(List<RemoteCard>)Field(Controller,"remoteCards");var remoteConfigurations=(Dictionary<string,RemoteCardSettings>)Field(Controller,"remoteConfigurations");
            foreach(var card in Controller.Settings.RemoteCardList){
                var view=new RemoteCard(Controller,card,live:false,snapshotReader:token=>card.Id==Pull?ReadRemote(token):Task.FromResult(Snapshot(card.Id,card.Kind)));
                remotes.Add(view);remoteConfigurations.Add(card.Id,card);
            }
            Invoke(Controller,"RebuildCards");
            foreach(var card in Controller.AllLocalViews){new WindowInteropHelper(card).EnsureHandle();card.ApplySnapshot(Status(card.Reference.Id,"stopped","original"));}
            foreach(var card in Controller.AllRemoteViews){new WindowInteropHelper(card).EnsureHandle();card.ApplySnapshot(Snapshot(card.CardID,Controller.Settings.RemoteCardList.Single(item=>item.Id==card.CardID).Kind));}
        }
        private Task<WorkerResponse> ReadLocal(CancellationToken token){LocalReadToken=token;return localReadSource.Task;}
        private Task<RemoteSnapshot> ReadRemote(CancellationToken token){RemoteReadToken=token;return remoteReadSource.Task;}
        internal void StartPendingWork(){ActionTask=(Task)Invoke(A,"PerformAsync","start")!;LocalReadTask=B.RefreshAsync();RemoteReadTask=PR.RefreshAsync();
            Require(ActionTask is{IsCompleted:false} && LocalReadTask is{IsCompleted:false} && RemoteReadTask is{IsCompleted:false},"Fixture did not start its actual injected action/read paths.");}
        internal async Task CompletePendingWorkAsync()
        {
            actionSource.TrySetResult(Response(Status("a","running","action-result")));localReadSource.TrySetResult(Response(Status("b","running","read-result")));
            remoteReadSource.TrySetResult(Snapshot(Pull,"pullRequests",3));
            await Task.WhenAll(new[]{ActionTask,LocalReadTask,RemoteReadTask}.OfType<Task>());
        }
        internal void SeedAttention()
        {
            Baseline(Controller,Local,Pull,Runs);
            Controller.ObserveAttention(new(Local,[Item("local-b","b")],[LocalAlert("initial-b","b")]));
            Controller.ObserveAttention(new(Runs,[Item("initial-run",null)],[RemoteAlert("initial-run-alert","failedRun"),RemoteAlert("initial-run-two","failedRun")]));Flush(Controller);
            Controller.ObserveAttention(new(Pull,[Item("initial-pr",null)],[RemoteAlert("pending-pr")]));
        }
        internal void Move(string id,double x,double y)
        {
            Controller.SavePosition(id,x,y);var window=Controller.AllLocalViews.FirstOrDefault(card=>card.Reference.Id==id) as Window??Controller.AllRemoteViews.FirstOrDefault(card=>card.CardID==id);
            if(window is not null){window.Left=x;window.Top=y;}
        }
        internal void ReplaceSettings(DeckSettings settings)
        {
            Store.Save(settings);typeof(DeckController).GetProperty(nameof(DeckController.Settings),BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(Controller,settings);
            Invoke(Controller,"RebuildCards");
        }
        internal Dictionary<string,NativeOwner> Windows()=>Controller.AllLocalViews.Select(card=>(Id:card.Reference.Id,Window:(Window)card,Snapshot:(object?)card.Latest))
            .Concat(Controller.AllRemoteViews.Select(card=>(Id:card.CardID,Window:(Window)card,Snapshot:(object?)card.Latest)))
            .ToDictionary(item=>item.Id,item=>new NativeOwner(item.Window,new WindowInteropHelper(item.Window).EnsureHandle(),item.Snapshot),StringComparer.Ordinal);
        internal Captured Capture()=>new(Controller.Settings,Json(Controller.Settings),Controller.LastCheckedAt,JsonSerializer.Serialize(Items(Controller),WorkerProtocol.Json),
            JsonSerializer.Serialize(PendingSources(Controller),WorkerProtocol.Json),JsonSerializer.Serialize(QueuedSources(Controller),WorkerProtocol.Json),Windows());
        internal void RequireOwners(Dictionary<string,NativeOwner> before)
        {
            var current=Windows();Require(current.Count==before.Count && before.All(pair=>current.TryGetValue(pair.Key,out var value)
                && ReferenceEquals(pair.Value.Window,value.Window) && pair.Value.Handle==value.Handle && ReferenceEquals(pair.Value.Snapshot,value.Snapshot)),
                "Arrangement operation replaced a native owner/HWND or discarded its validated snapshot.");
        }
        internal void RequireUnchangedExceptArrangements(Captured before)
        {
            Require(Json(Controller.Settings with { Arrangements=before.Settings.Arrangements })==before.Json && Controller.LastCheckedAt==before.Clock
                && JsonSerializer.Serialize(Items(Controller),WorkerProtocol.Json)==before.Signals && JsonSerializer.Serialize(PendingSources(Controller),WorkerProtocol.Json)==before.Pending
                && JsonSerializer.Serialize(QueuedSources(Controller),WorkerProtocol.Json)==before.Queued,"Arrangement metadata reset live attention, check time, Seen, queued sources or another saved setting.");
            RequireOwners(before.Owners);Require(Json(Store.Load())==Json(Controller.Settings),"Arrangement mutation was not persisted exactly in its owned settings fixture.");
        }
        internal void RequireSavedLayout(Arrangement saved)
        {
            foreach(var placed in saved.Cards){
                var local=Controller.Settings.Cards.FirstOrDefault(card=>card.Project.Id==placed.Id);var remote=Controller.Settings.RemoteCardList.FirstOrDefault(card=>card.Id==placed.Id);
                if(local is null && remote is null)continue;
                Require((local?.Enabled??remote!.Enabled)==placed.Enabled && (local?.Collapsed??remote!.Collapsed)==placed.Collapsed
                    && (local?.X??remote!.X)==placed.X && (local?.Y??remote!.Y)==placed.Y,"Saved visibility/compact/XY was not restored for "+placed.Id);
                var owner=Windows()[placed.Id].Window;var dpi=System.Windows.Media.VisualTreeHelper.GetDpi(owner);
                Require(Math.Abs(owner.Left-placed.X)<=1/dpi.DpiScaleX && Math.Abs(owner.Top-placed.Y)<=1/dpi.DpiScaleY,"Restored native geometry differs by more than one device pixel for "+placed.Id);
            }
        }
        internal void RequireIsolation()
        {
            var count=typeof(DeckController).GetFields(BindingFlags.Instance|BindingFlags.NonPublic).Where(field=>field.FieldType==typeof(WorkerManager))
                .Select(field=>(WorkerManager)field.GetValue(Controller)!).Sum(manager=>((IDictionary)typeof(WorkerManager).GetField("workers",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(manager)!).Count);
            Require(count==0 && Field(Controller,"tray",allowNull:true) is null && !Controller.LocalPollEnabled,"Synthetic arrangement test started a worker, tray or local poll.");
            Require(Json(Store.Load())==Json(Controller.Settings),"Owned settings persistence diverged from the actual controller.");
        }
        public async ValueTask DisposeAsync(){await CompletePendingWorkAsync();Controller.CloseViews();Text.Use("en");foreach(var file in new[]{path,path+".bak"})if(File.Exists(file))File.Delete(file);}
    }

    private static string Json(DeckSettings settings)=>JsonSerializer.Serialize(settings,WorkerProtocol.Json);
    private static object Field(object owner,string name,bool allowNull=false)=>owner.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(owner)
        ??(allowNull?null!:throw new IOException("Missing fixture field "+name));
    private static object? Invoke(object owner,string name,params object?[] arguments)=>owner.GetType().GetMethod(name,BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(owner,arguments);
    private static AttentionItem[] Items(DeckController controller)=>((AttentionTracker)Field(controller,"attention")).SignalItems;
    private static Source ReadSource(object source)=>new((string)source.GetType().GetProperty("Scope")!.GetValue(source)!, (DeckAlert)source.GetType().GetProperty("Alert")!.GetValue(source)!);
    private static Source[] PendingSources(DeckController controller)=>((IEnumerable)Field(controller,"pendingAlerts")).Cast<object>().Select(ReadSource).ToArray();
    private static Source[] QueuedSources(DeckController controller)=>((IEnumerable)Field(controller,"deliveries")).Cast<object>()
        .SelectMany(delivery=>((IEnumerable)delivery.GetType().GetProperty("Sources")!.GetValue(delivery)!).Cast<object>().Select(ReadSource)).ToArray();
    private static void Baseline(DeckController controller,params string[] scopes){foreach(var scope in scopes)controller.ObserveAttention(new(scope,[],[]));}
    private static void Flush(DeckController controller)=>Invoke(controller,"FlushNotifications");
    private static AttentionItem Item(string id,string? cardID,string mark="project")=>new(id,id,"needsFixing",mark,id,"Synthetic",1,
        cardID is not null?new("showCard",CardID:cardID):mark=="docker"?new("startDocker"):new("open","https://example.test/"+id,"github","work"),true,false);
    private static DeckAlert LocalAlert(string id,string cardID)=>new(id,"wentDown","project",id,"Synthetic",id,id,new("showCard",CardID:cardID),false);
    private static DeckAlert RemoteAlert(string id,string kind="reviewRequest")=>new(id,kind,"github",id,"Synthetic",id,id,new("open","https://example.test/"+id,"github","work"),false);
    private static ProjectStatus Status(string id,string state,string branch)=>new(id,state,branch,"http://localhost:4321","Synthetic",null);
    private static WorkerResponse Response(ProjectStatus status)=>new(1,null,"Test Linux",null,status,null,null);
    private static RemoteSnapshot Snapshot(string id,string kind,int count=2)=>new(id,kind,count,0,null,Enumerable.Range(0,count).Select(index=>
        new RemoteRow("row-"+index,kind=="mergeRequests"?"lab":"work","Synthetic request "+index,"example/shop","https://example.test/"+index,"ready","approved",false)).ToArray(),[],false);
    private static Forms.ContextMenuStrip Build(DeckController controller){var menu=new Forms.ContextMenuStrip();try{Rebuild(controller,menu);return menu;}catch{menu.Dispose();throw;}}
    private static void Rebuild(DeckController controller,Forms.ContextMenuStrip menu)=>Invoke(controller,"BuildMenu",menu);
    private static IEnumerable<Forms.ToolStripMenuItem> Rows(Forms.ToolStrip menu)=>Rows(menu.Items);
    private static IEnumerable<Forms.ToolStripMenuItem> Rows(Forms.ToolStripItemCollection items)=>items.OfType<Forms.ToolStripMenuItem>()
        .SelectMany(row=>new[]{row}.Concat(Rows(row.DropDownItems)));
    private static Forms.ToolStripMenuItem Row(Forms.ToolStrip menu,string tag)=>Rows(menu).Single(row=>row.Tag as string==tag);
    private static async Task Turns(){for(var turn=0;turn<3;turn++)await Dispatcher.Yield(DispatcherPriority.Background);}
    private static void Require(bool condition,string message){if(!condition)throw new IOException(message);}
}
