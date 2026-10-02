using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Saved synthetic scopes and the actual controller delivery queue, without a tray or worker.
internal static class VisibilityAttentionTests
{
    private const string Local="local:Test Linux",Other="local:Other Linux",Pull="legacy.pr",Runs="legacy.actions",Lab="legacy.lab";

    internal static async Task RunAsync(Application application,List<object> checks)
    {
        await Check("visibility.attention.preserve-sibling-observation",async fixture=>{
            var controller=fixture.Controller;
            controller.ObserveAttention(new(Local,[Item("a","a"),Item("b","b")],[LocalAlert("old-a","a"),LocalAlert("old-b","b")]));
            controller.ObserveAttention(new(Runs,[Item("run",null,mark:"github")],[RemoteAlert("old-run","failedRun")]));
            controller.ObserveAttention(new(Other,[Item("c","c")],[LocalAlert("old-c","c")]));
            var last=controller.LastCheckedAt;var seen=controller.Settings.AnnouncedAlerts.ToArray();
            await controller.SetCardVisibleAsync("a",false);
            Require(controller.LastCheckedAt==last && controller.Settings.AnnouncedAlerts.SequenceEqual(seen),"Hide reset the completed-check time or seen identities.");
            Require(Items(controller).Select(item=>item.Id).ToHashSet().SetEquals(new[]{"b","run","c"}),"Hide globally retained/reset attention scopes.");
            controller.ObserveAttention(new(Local,[Item("b","b")],[LocalAlert("fresh-b","b")]),controller.CaptureLocalAttention("Test Linux"));
            controller.ObserveAttention(new(Runs,[Item("run",null,mark:"github")],[RemoteAlert("fresh-run","failedRun")]));
            Require(Pending(controller).Select(source=>source.Alert.Id).ToHashSet().SetEquals(new[]{"fresh-b","fresh-run"}),"Hide reset a sibling or shared-account Actions notification baseline.");
            Require(seen.All(id=>controller.Settings.AnnouncedAlerts.Contains(id)),"Later observation lost earlier seen history.");
            Require(fixture.Store.Load().AnnouncedAlerts.SequenceEqual(controller.Settings.AnnouncedAlerts),"Seen metadata no longer persists in the owned fixture.");
        });
        await Check("visibility.attention.local-docker-retarget",async fixture=>{
            var controller=fixture.Controller;
            controller.ObserveAttention(new(Local,[Item("a","a"),Item("b","b"),Item("docker-old",null,new("startDocker"),"docker")],[]));
            controller.ObserveAttention(new(Other,[Item("c","c")],[]));controller.ObserveAttention(new(Pull,[Item("pr",null,mark:"github")],[]));
            var docker=LocalAlert("docker-old-alert","a") with { Source="docker",Subject="A and B require Docker" };
            controller.ObserveAttention(new(Local,Items(controller).Where(item=>item.Id is "a" or "b" or "docker-old").ToArray(),
                [LocalAlert("a-new","a"),LocalAlert("b-new","b"),docker]));
            await controller.SetCardVisibleAsync("a",false);
            Require(Items(controller).Select(item=>item.Id).ToHashSet().SetEquals(new[]{"b","c","pr"}),"Cached local Docker aggregate or hidden project survived; unrelated scope disappeared.");
            Require(Pending(controller).Select(source=>source.Alert.Id).SequenceEqual(new[]{"b-new"}),"Hidden local/Docker candidates were not pruned from the pending batch.");
            var fresh=controller.CaptureLocalAttention("Test Linux");
            controller.ObserveAttention(new(Local,[Item("b","b"),Item("docker-b","b",new("showCard",CardID:"b"),"docker")],
                [LocalAlert("docker-b-alert","b") with { Source="docker",Subject="B requires Docker" }],"unavailable",false),fresh);
            Require(Items(controller).Any(item=>item.Id=="docker-b" && item.Action.CardID=="b") && !Items(controller).Any(item=>item.Id=="docker-old"),
                "Current filtered producer response failed to replace the stale aggregate with the visible owner.");
            Require(Pending(controller).Any(source=>source.Alert.Id=="docker-b-alert" && source.Alert.Target.CardID=="b"),"Fresh visible Docker episode was suppressed globally.");
        });
        await Check("visibility.attention.stale-context-hide-and-reveal",async fixture=>{
            var controller=fixture.Controller;var beforeHide=controller.CaptureLocalAttention("Test Linux");
            controller.ObserveAttention(new(Local,[Item("a","a"),Item("b","b")],[]),beforeHide);
            await controller.SetCardVisibleAsync("a",false);
            var hidden=controller.CaptureLocalAttention("Test Linux");var clock=controller.LastCheckedAt;var seen=controller.Settings.AnnouncedAlerts.ToArray();
            controller.ObserveAttention(new(Local,[Item("late-a","a"),Item("late-b","b")],[LocalAlert("late-alert-b","b")]),beforeHide);
            Require(controller.LastCheckedAt==clock && controller.Settings.AnnouncedAlerts.SequenceEqual(seen) && Pending(controller).Length==0
                && Items(controller).Select(item=>item.Id).SequenceEqual(new[]{"b"}),"Pre-hide response restored signals, changed check time, seeded history or queued a sibling alert.");
            await controller.SetCardVisibleAsync("a",true);
            clock=controller.LastCheckedAt;
            controller.ObserveAttention(new(Local,[Item("late-hidden-b","b")],[LocalAlert("late-hidden-alert","b")]),hidden);
            Require(controller.LastCheckedAt==clock && Pending(controller).Length==0 && !Items(controller).Any(item=>item.Id=="late-hidden-b"),"A pre-reveal response escaped the visibility revision guard.");
            var current=controller.CaptureLocalAttention("Test Linux");
            Require(current.Revision>hidden.Revision && current.ActiveProjectIDs.SequenceEqual(new[]{"a","b"}),"Reveal lost permanent identity or did not advance its context.");
            controller.ObserveAttention(new(Local,[Item("current-a","a"),Item("current-b","b")],[LocalAlert("current-b-alert","b")]),current);
            Require(Pending(controller).Single().Alert.Id=="current-b-alert" && Items(controller).Length==2,"Fresh current context was rejected with stale responses.");
        });
        await Check("visibility.attention.reveal-own-quiet-sibling-fresh",async fixture=>{
            var controller=fixture.Controller;
            controller.ObserveAttention(new(Local,[Item("a","a"),Item("b","b")],[]));
            await controller.SetCardVisibleAsync("a",false);await controller.SetCardVisibleAsync("a",true);
            var ownOld=LocalAlert("unseen-existing-a","a");var siblingNew=LocalAlert("new-b-during-reveal","b");
            controller.ObserveAttention(new(Local,[Item("a","a"),Item("b","b")],[ownOld,siblingNew]),controller.CaptureLocalAttention("Test Linux"));
            Require(Pending(controller).Select(source=>source.Alert.Id).SequenceEqual(new[]{siblingNew.Id}),"Reveal announced its old episode or quietly reset the sibling aggregate.");
            Require(controller.Settings.AnnouncedAlerts.Contains(ownOld.Id) && controller.Settings.AnnouncedAlerts.Contains("retained-episode"),"Own quiet seed was not remembered or erased unrelated history.");
            var ownLater=LocalAlert("genuinely-new-a","a");
            controller.ObserveAttention(new(Local,[Item("a","a"),Item("b","b")],[ownOld,siblingNew,ownLater]),controller.CaptureLocalAttention("Test Linux"));
            Require(Pending(controller).Select(source=>source.Alert.Id).ToHashSet().SetEquals(new[]{siblingNew.Id,ownLater.Id}),"Quiet reveal persisted forever or duplicate-announced a prior episode.");
        });
        await Check("visibility.attention.shared-account-queued-source-pruning",async fixture=>{
            var controller=fixture.Controller;Baseline(controller,Pull,Runs,Local);
            controller.ObserveAttention(new(Pull,[Item("pr",null,mark:"github")],[RemoteAlert("pr-review"),RemoteAlert("pr-blocked","blocked")]));
            controller.ObserveAttention(new(Runs,[Item("run",null,mark:"github")],[RemoteAlert("run-failure","failedRun")]));
            controller.ObserveAttention(new(Local,[Item("b","b")],[LocalAlert("b-down","b")]));Flush(controller);
            Require(Queued(controller).Length==1 && Sources(Queued(controller).Single()).Length==4,"Batch did not retain all four original scoped candidates.");
            var seen=controller.Settings.AnnouncedAlerts.ToArray();var clock=controller.LastCheckedAt;
            await controller.SetCardVisibleAsync(Pull,false);
            var retained=Sources(Queued(controller).Single());
            Require(retained.Select(source=>source.Scope).ToHashSet().SetEquals(new[]{Runs,Local})
                && retained.Select(source=>source.Alert.Id).ToHashSet().SetEquals(new[]{"run-failure","b-down"}),"PR hide discarded a shared account's Actions or unrelated project source.");
            Require(Items(controller).Select(item=>item.Id).ToHashSet().SetEquals(new[]{"run","b"}) && controller.Settings.AnnouncedAlerts.SequenceEqual(seen)
                && controller.LastCheckedAt==clock,"Queued source pruning reset histories, clocks or surviving signals.");
        });
        await Check("visibility.attention.summary-recomputed-six-languages",async fixture=>{
            var controller=fixture.Controller;Baseline(controller,Pull,Runs,Lab,Local);
            controller.ObserveAttention(new(Pull,[],[RemoteAlert("pr-review"),RemoteAlert("pr-blocked","blocked")]));
            controller.ObserveAttention(new(Runs,[],[RemoteAlert("run-failure","failedRun")]));
            controller.ObserveAttention(new(Local,[],[LocalAlert("project-b-down","b")]));
            controller.ObserveAttention(new(Lab,[],[RemoteAlert("lab-blocked","blocked","gitlab","lab-account")]));Flush(controller);
            var original=Sources(Queued(controller).Single());Require(original.Length==5,"Summary fixture omitted an original source.");
            await controller.SetCardVisibleAsync(Pull,false);
            var retained=Sources(Queued(controller).Single());Require(retained.Length==3,"Summary did not retain the three unrelated source candidates.");
            foreach(var language in DevDeck.Windows.Core.Localization.Languages){
                Text.Use(language);
                var old=Summary(original.Select(source=>source.Alert).ToArray());var summary=Summary(retained.Select(source=>source.Alert).ToArray());
                Require(old.Body.Contains("pr-review",StringComparison.Ordinal) && !summary.Body.Contains("pr-review",StringComparison.Ordinal)
                    && summary.Body.Contains("run-failure",StringComparison.Ordinal) && summary.Body.Contains("project-b-down",StringComparison.Ordinal),
                    language+": summary text used hidden original subjects.");
                Require(summary.Title.Contains(Text.LN("alert.summary.wentDown",1),StringComparison.Ordinal)
                    && summary.Title.Contains(Text.LN("alert.summary.stuck",1),StringComparison.Ordinal)
                    && summary.Title.Contains(Text.LN("alert.summary.failedRun",1),StringComparison.Ordinal)
                    && !summary.Title.Contains(Text.LN("alert.summary.reviews",1),StringComparison.Ordinal),language+": summary counts/types were cached before pruning.");
                Require(summary.Target.Kind=="menu" && summary.Id=="summary" && !summary.Quiet,language+": recomputation lost the original summary delivery contract.");
            }
        });
        await Check("visibility.attention.remote-reveal-baseline-is-scoped",async fixture=>{
            var controller=fixture.Controller;
            var oldPR=RemoteAlert("old-pr");var oldRun=RemoteAlert("old-run","failedRun");
            controller.ObserveAttention(new(Pull,[],[oldPR]));controller.ObserveAttention(new(Runs,[],[oldRun]));
            await controller.SetCardVisibleAsync(Pull,false);await controller.SetCardVisibleAsync(Pull,true);
            var revealPR=RemoteAlert("existing-pr-at-reveal");var freshRun=RemoteAlert("fresh-run-after-pr-hide","failedRun");
            controller.ObserveAttention(new(Pull,[],[oldPR,revealPR]));controller.ObserveAttention(new(Runs,[],[oldRun,freshRun]));
            Require(Pending(controller).Select(source=>source.Alert.Id).SequenceEqual(new[]{freshRun.Id}),"Remote reveal announced old events or reset Actions' shared-account baseline.");
            Require(controller.Settings.AnnouncedAlerts.ToHashSet().IsSupersetOf(new[]{oldPR.Id,oldRun.Id,revealPR.Id,"retained-episode"}),"Scoped remote reset erased previous history.");
            var laterPR=RemoteAlert("later-pr");controller.ObserveAttention(new(Pull,[],[oldPR,revealPR,laterPR]));
            Require(Pending(controller).Select(source=>source.Alert.Id).ToHashSet().SetEquals(new[]{freshRun.Id,laterPR.Id}),"Revealed remote scope never resumed fresh episode delivery.");
        });
        await Check("visibility.attention.hidden-removed-unknown-remote-ingress",async fixture=>{
            var controller=fixture.Controller;Baseline(controller,Pull,Runs);
            await controller.SetCardVisibleAsync(Pull,false);
            var clock=controller.LastCheckedAt;var seen=controller.Settings.AnnouncedAlerts.ToArray();
            var failure=RemoteAlert("hidden-cant-check","cantCheck") with { Target=new("accountSettings",Service:"github",AccountID:"work") };
            controller.ObserveAttention(new(Pull,[Item("hidden-failure",null,mark:"token")],[failure]));
            controller.ObserveAttention(new("removed.unknown",[Item("unknown-failure",null,mark:"token")],[failure with { Id="unknown-cant-check" }]));
            fixture.RemoveSavedRemote(Pull);
            controller.ObserveAttention(new(Pull,[Item("removed-failure",null,mark:"token")],[failure with { Id="removed-cant-check" }]));
            Require(controller.LastCheckedAt==clock && controller.Settings.AnnouncedAlerts.SequenceEqual(seen) && Pending(controller).Length==0
                && Items(controller).Length==0,"Hidden/removed/unknown remote cantCheck bypassed saved scope validation.");
            controller.ObserveAttention(new(Runs,[Item("live-run",null,mark:"github")],[RemoteAlert("fresh-valid-run","failedRun")]));
            Require(Pending(controller).Single().Alert.Id=="fresh-valid-run","Rejecting an unknown remote response lost a valid sibling baseline.");
        });
        await Check("visibility.attention.all-local-hidden-filters-future-aggregate",async fixture=>{
            var controller=fixture.Controller;
            controller.ObserveAttention(new(Local,[Item("a","a"),Item("b","b"),Item("docker",null,new("startDocker"),"docker")],[LocalAlert("old-a","a")]));
            controller.ObserveAttention(new(Other,[Item("c","c")],[]));controller.ObserveAttention(new(Pull,[Item("pr",null,mark:"github")],[]));
            await controller.SetCardVisibleAsync("a",false);await controller.SetCardVisibleAsync("b",false);
            var context=controller.CaptureLocalAttention("Test Linux");Require(context.ActiveProjectIDs.Length==0,"Last local hide retained an active owner.");
            controller.ObserveAttention(new(Local,[Item("ghost-a","a"),Item("ghost-docker",null,new("startDocker"),"docker")],
                [LocalAlert("ghost-alert","a"),RemoteAlert("ghost-cant-check","cantCheck") with { Source="docker" }],"unavailable",false),context);
            Require(Items(controller).Select(item=>item.Id).ToHashSet().SetEquals(new[]{"c","pr"}) && Pending(controller).Length==0,
                "All-hidden local response emitted project/Docker events or erased an unrelated scope.");
            controller.ObserveAttention(new(Other,[Item("c","c")],[LocalAlert("fresh-other-distro","c")]),controller.CaptureLocalAttention("Other Linux"));
            Require(Pending(controller).Single().Alert.Id=="fresh-other-distro","Hiding another distribution reset a surviving scope's first observation.");
        });
        await Check("visibility.attention.active-summary-retains-and-requeues-sources",async fixture=>{
            var controller=fixture.Controller;Baseline(controller,Pull,Runs,Lab,Local);
            controller.ObserveAttention(new(Pull,[],[RemoteAlert("pr-one"),RemoteAlert("pr-two","blocked")]));
            controller.ObserveAttention(new(Runs,[],[RemoteAlert("run-one","failedRun"),RemoteAlert("run-two","failedRun")]));
            controller.ObserveAttention(new(Local,[],[LocalAlert("b-one","b")]));Flush(controller);
            var queue=Field(controller,"deliveries");var active=queue.GetType().GetMethod("Dequeue")!.Invoke(queue,null)!;
            SetField(controller,"activeDelivery",active);SetField(controller,"activeAlert",Summary(Sources(active).Select(source=>source.Alert).ToArray()));
            controller.ObserveAttention(new(Lab,[],[RemoteAlert("lab-one","blocked","gitlab","lab-account"),RemoteAlert("lab-two","blocked","gitlab","lab-account")]));Flush(controller);
            var later=Queued(controller).SelectMany(Sources).Select(source=>source.Alert.Id).ToArray();Require(later.SequenceEqual(new[]{"lab-one","lab-two"}),"Fixture later queue was not retained individually.");
            await controller.SetCardVisibleAsync(Pull,false);
            var retained=Queued(controller);
            Require(FieldOrNull(controller,"activeAlert") is null && FieldOrNull(controller,"activeDelivery") is null,"A displayed summary retained a hidden source.");
            Require(retained.Length==3 && Sources(retained[0]).Select(source=>source.Alert.Id).SequenceEqual(new[]{"run-one","run-two","b-one"})
                && retained.Skip(1).SelectMany(Sources).Select(source=>source.Alert.Id).SequenceEqual(later),"Active summary prune lost source identity/order or unrelated queued deliveries.");
            await controller.SetCardVisibleAsync(Runs,false);
            Require(Sources(Queued(controller)[0]).Single().Alert.Id=="b-one" && Queued(controller).Skip(1).SelectMany(Sources).Select(source=>source.Alert.Id).SequenceEqual(later),
                "A second scope prune discarded surviving queued summary sources.");
        });

        async Task Check(string name,Func<Fixture,Task> action)
        {
            using var fixture=new Fixture(application);
            await action(fixture);
            fixture.RequireIsolation();
            checks.Add(new { name, noWorkerStarted=true, noCredentialRead=true, noActualBalloon=true, exactSavedScopes=true });
        }
    }

    private sealed class Fixture:IDisposable
    {
        private readonly string path=Path.Combine(Path.GetTempPath(),"devdeck-visibility-attention-"+Guid.NewGuid().ToString("N")+".json");
        internal SettingsStore Store{get;}
        internal DeckController Controller{get;}
        internal Fixture(Application application)
        {
            Store=new(path);
            Store.Save(new DeckSettings(1,[new("Test Linux","/tmp/synthetic-visibility-runtime"),new("Other Linux","/tmp/synthetic-other-runtime")],
                [new(new("a","Test Linux","local","/tmp/a"),"A"),new(new("b","Test Linux","local","/tmp/b"),"B"),new(new("c","Other Linux","local","/tmp/c"),"C")],
                Accounts:[new("work","Work","github","https://api.github.com",[],[],NotifiesBlocked:true,NotifiesFailedRuns:true),
                    new("lab-account","Lab","gitlab","https://gitlab.com",[],[],NotifiesBlocked:true,NotifiesFailedRuns:true)],
                RemoteCards:[new(Pull,"PR","pullRequests","Test Linux",["work"]),new(Runs,"Actions","actions","Test Linux",["work"]),
                    new(Lab,"MR","mergeRequests","Test Linux",["lab-account"]),new("legacy.inbox","Inbox","inbox","Test Linux",["work"],Enabled:false)],
                Language:"en",Notifications:true,SeenAlerts:["retained-episode"]));
            Controller=new(application,Store,live:false);
            // Existing configured owners avoid the fallback rebuild. No HWND is shown until a test
            // reveals its own synthetic card; the real deck and its settings remain untouched.
            var locals=(List<ProjectCard>)Field(Controller,"cards");
            var localConfiguration=(Dictionary<string,CardSettings>)Field(Controller,"localConfigurations");
            foreach(var card in Controller.Settings.Cards){locals.Add(new(Controller,card,live:false));localConfiguration.Add(card.Project.Id,card);}
            var remotes=(List<RemoteCard>)Field(Controller,"remoteCards");
            var remoteConfiguration=(Dictionary<string,RemoteCardSettings>)Field(Controller,"remoteConfigurations");
            foreach(var card in Controller.Settings.RemoteCardList){
                var view=new RemoteCard(Controller,card,live:false);if(!card.Enabled)view.SetDeckVisible(false);
                remotes.Add(view);remoteConfiguration.Add(card.Id,card);
            }
        }
        internal void RemoveSavedRemote(string id)
        {
            var value=Controller.Settings with { RemoteCards=Controller.Settings.RemoteCardList.Where(card=>card.Id!=id).ToArray() };
            typeof(DeckController).GetProperty(nameof(DeckController.Settings),BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(Controller,value);
            Store.Save(value);
        }
        internal void RequireIsolation()
        {
            Require(FieldOrNull(Controller,"tray") is null && !Controller.LocalPollEnabled,"Synthetic fixture registered a tray or local polling loop.");
            var count=typeof(DeckController).GetFields(BindingFlags.Instance|BindingFlags.NonPublic).Where(field=>field.FieldType==typeof(WorkerManager))
                .Select(field=>(WorkerManager)field.GetValue(Controller)!).Sum(manager=>((IDictionary)typeof(WorkerManager).GetField("workers",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(manager)!).Count);
            Require(count==0,"Synthetic attention handling started a local/remote/settings worker.");
            Require(Store.Load().AnnouncedAlerts.SequenceEqual(Controller.Settings.AnnouncedAlerts),"Controller histories diverged from its owned settings fixture.");
        }
        public void Dispose()
        {
            Controller.CloseViews();Text.Use("en");
            foreach(var file in new[]{path,path+".bak"})if(File.Exists(file))File.Delete(file);
        }
    }

    private sealed record Source(string Scope,DeckAlert Alert);
    private static object? FieldOrNull(DeckController controller,string name)=>typeof(DeckController).GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(controller);
    private static object Field(DeckController controller,string name)=>FieldOrNull(controller,name)??throw new IOException("Missing fixture field "+name);
    private static void SetField(DeckController controller,string name,object? value)=>typeof(DeckController).GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(controller,value);
    private static Source ReadSource(object source)=>new((string)source.GetType().GetProperty("Scope")!.GetValue(source)!,
        (DeckAlert)source.GetType().GetProperty("Alert")!.GetValue(source)!);
    private static Source[] Pending(DeckController controller)=>((IEnumerable)Field(controller,"pendingAlerts")).Cast<object>().Select(ReadSource).ToArray();
    private static object[] Queued(DeckController controller)=>((IEnumerable)Field(controller,"deliveries")).Cast<object>().ToArray();
    private static Source[] Sources(object delivery)=>((IEnumerable)delivery.GetType().GetProperty("Sources")!.GetValue(delivery)!).Cast<object>().Select(ReadSource).ToArray();
    private static AttentionItem[] Items(DeckController controller)=>((AttentionTracker)Field(controller,"attention")).SignalItems;
    private static void Flush(DeckController controller)=>typeof(DeckController).GetMethod("FlushNotifications",BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(controller,null);
    private static DeckAlert Summary(DeckAlert[] alerts)=>(DeckAlert)typeof(DeckController).GetMethod("Summary",BindingFlags.Static|BindingFlags.NonPublic)!.Invoke(null,[alerts])!;
    private static void Baseline(DeckController controller,params string[] scopes){foreach(var scope in scopes)controller.ObserveAttention(new(scope,[],[]));}
    private static AttentionItem Item(string id,string? cardID,AttentionAction? action=null,string mark="project")=>new(id,id,"needsFixing",mark,id,"Synthetic fixture",1,
        action??(cardID is not null?new("showCard",CardID:cardID):new("open","https://example.test/"+id,"github","work")),true,false);
    private static DeckAlert LocalAlert(string id,string cardID)=>new(id,"wentDown","project",id,"Synthetic fixture",id,id,new("showCard",CardID:cardID),false);
    private static DeckAlert RemoteAlert(string id,string kind="reviewRequest",string service="github",string account="work")=>new(id,kind,service,id,"Synthetic fixture",id,id,
        new("open","https://example.test/"+id,service,account),false);
    private static void Require(bool condition,string message){if(!condition)throw new IOException(message);}
}
