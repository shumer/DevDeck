using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using DevDeck.Windows.Core;

// Synthetic transport and delivery policy only; no WSL process, account, browser or desktop state.
internal static class VisibilityChecks
{
    internal static async Task RunAsync(Func<string, Func<Task>, Task> check)
    {
        await check("visibility wire distinguishes omitted context from an empty active set", () => {
            var legacy = JsonSerializer.Deserialize<WorkerRequest>("{\"protocolVersion\":1,\"id\":\"legacy\",\"operation\":\"hello\"}", WorkerProtocol.Json)!;
            Require(legacy.ActiveProjectIDs is null, "Legacy requests acquired an empty active set.");
            var empty = new WorkerRequest(1,"empty","project.status",Project(),ActiveProjectIDs:[]);
            var decoded = JsonSerializer.Deserialize<WorkerRequest>(JsonSerializer.Serialize(empty,WorkerProtocol.Json),WorkerProtocol.Json)!;
            Require(decoded.ActiveProjectIDs is { Length:0 }, "An explicit empty active set became legacy/null.");
            var unicode = empty with { ActiveProjectIDs = ["проект 🧩"] };
            Require(JsonSerializer.Deserialize<WorkerRequest>(JsonSerializer.Serialize(unicode,WorkerProtocol.Json),WorkerProtocol.Json)!.ActiveProjectIDs!.Single()=="проект 🧩",
                "Unicode permanent IDs changed across the wire.");
            return Task.CompletedTask;
        });
        await check("visibility active IDs enforce distinct bounded Unicode identities", () => {
            Require(AttentionVisibility.ValidProjectIDs(null) && AttentionVisibility.ValidProjectIDs([]), "Legacy/empty contexts must be valid.");
            Require(AttentionVisibility.ValidProjectIDs([new string('Ж',64),"Project","project"]), "The UTF-8 boundary or ordinal identity changed.");
            Require(AttentionVisibility.ValidProjectIDs(Enumerable.Range(0,1024).Select(index=>"id-"+index).ToArray()), "The count boundary was rejected.");
            foreach(var invalid in new string[][] { [""], ["a","a"], ["a\n"], ["a\0"], [new string('Ж',65)], [null!],
                Enumerable.Range(0,1025).Select(index=>"id-"+index).ToArray() })
                Require(!AttentionVisibility.ValidProjectIDs(invalid), "Malformed active context was accepted.");
            return Task.CompletedTask;
        });
        await check("visibility project context selects saved enabled local identities and owns its array", () => {
            var settings = Settings() with { Cards = [new(Project("b"),"B"),new(Project("a"),"A"),
                new(Project("hidden"),"Hidden",Enabled:false),new(Project("other","Other Linux"),"Other"),
                new(Project("links") with { Path="" },"Links")] };
            var ids = AttentionVisibility.ProjectIDs(settings,"Test Linux");
            Require(ids.SequenceEqual(new[]{"a","b"}), "Context included hidden/link-only/other-distribution cards or used title order.");
            ids[0]="mutated";
            Require(AttentionVisibility.ProjectIDs(settings,"Test Linux").SequenceEqual(new[]{"a","b"}) && settings.Cards[1].Project.Id=="a",
                "A caller can mutate saved or subsequently captured identities.");
            return Task.CompletedTask;
        });
        await check("visibility local ingress filters card and terminal owners but preserves physical Docker facts", () => {
            var settings=Settings() with { Cards=[new(Project("a"),"A"),new(Project("hidden"),"Hidden",Enabled:false)] };
            var source=new AttentionSnapshot("local:Test Linux",[Item("a","a"),Item("hidden","hidden"),Item("unknown","unknown"),
                Item("terminal-a",null,new("openTerminal",Path:"/tmp/a")),Item("terminal-hidden",null,new("openTerminal",Path:"/tmp/hidden")),
                Item("docker",null,new("startDocker"))],[LocalAlert("a-alert","a"),LocalAlert("hidden-alert","hidden")],"unavailable",false);
            var filtered=AttentionVisibility.Filter(source,settings)!;
            Require(filtered.Items.Select(item=>item.Id).SequenceEqual(new[]{"a","terminal-a","docker"})
                && filtered.Alerts.Select(alert=>alert.Id).SequenceEqual(new[]{"a-alert"}),"Hidden or foreign local owners survived ingress filtering.");
            var none=AttentionVisibility.Filter(source,settings with { Cards=settings.Cards.Select(card=>card with { Enabled=false }).ToArray() })!;
            Require(none.Items.Length==0 && none.Alerts.Length==0 && none.DockerState=="unavailable" && none.ContainerStartAllowed==false,
                "An empty active set emitted events or lost physical Docker/start eligibility.");
            return Task.CompletedTask;
        });
        await check("visibility remote scope uses saved card identity even when PR and Actions share an account", () => {
            var settings=Settings();
            var pull=new AttentionSnapshot("legacy.pr",[Item("pull",null)],[]);
            var actions=new AttentionSnapshot("legacy.actions",[Item("run",null)],[]);
            var hidden=settings with { RemoteCards=settings.RemoteCardList.Select(card=>card.Id=="legacy.pr"?card with { Enabled=false }:card).ToArray() };
            Require(AttentionVisibility.Filter(pull,hidden) is null && ReferenceEquals(AttentionVisibility.Filter(actions,hidden),actions),
                "Hiding PR removed the shared account's Actions scope.");
            Require(AttentionVisibility.Filter(pull,settings with { RemoteCards=settings.RemoteCardList.Where(card=>card.Id!="legacy.pr").ToArray() }) is null
                && AttentionVisibility.Filter(pull with { Scope="removed.unknown" },settings) is null,
                "Removed/unknown remote scope was admitted.");
            return Task.CompletedTask;
        });
        await check("visibility tracker prunes one local aggregate without global retain or reset", () => {
            var tracker=new AttentionTracker();
            tracker.Observe(new AttentionSnapshot("local:Test Linux",[Item("a","a"),Item("b","b"),Item("docker",null,mark:"docker")],[]));
            tracker.Observe(new AttentionSnapshot("local:Other Linux",[Item("c","c")],[]));
            tracker.Observe(new AttentionSnapshot("legacy.pr",[Item("pr",null)],[]));
            tracker.Observe(new AttentionSnapshot("legacy.actions",[Item("run",null)],[]));
            tracker.PruneScope("local:Test Linux",item=>item.Action.CardID=="b");
            Require(tracker.SignalItems.Select(item=>item.Id).ToHashSet().SetEquals(new[]{"b","c","pr","run"}),
                "Local pruning dropped a sibling/other distribution/remote scope.");
            tracker.RemoveScope("legacy.pr");
            Require(tracker.SignalItems.Select(item=>item.Id).ToHashSet().SetEquals(new[]{"b","c","run"}),"Exact remote removal affected another scope.");
            return Task.CompletedTask;
        });
        await check("visibility quiet reveal seeds own episode while a sibling remains fresh", () => {
            var settings=Settings();var ledger=new NotificationLedger(["previous-sibling"]);
            Require(ledger.Observe(new("local:Test Linux",[],[]),settings).Length==0,"Initial aggregate read was not quiet.");
            var oldA=LocalAlert("old-a","a");var newB=LocalAlert("new-b","b");
            ledger.Seed([oldA],settings);
            Require(ledger.Observe(new("local:Test Linux",[],[oldA,newB]),settings).Select(alert=>alert.Id).SequenceEqual(new[]{"new-b"}),
                "Reveal globally reset the aggregate baseline or announced its own existing episode.");
            Require(ledger.Seen.ToHashSet().SetEquals(new[]{"previous-sibling","old-a","new-b"}),"Quiet seeding lost unrelated seen identities.");
            ledger.Seed(Enumerable.Range(0,NotificationLedger.Memory+2).Select(index=>LocalAlert("seed-"+index,"a")),settings);
            Require(ledger.Seen.Length==NotificationLedger.Memory && ledger.Seen[0]=="seed-2","Quiet seed bypassed the bounded memory policy.");
            return Task.CompletedTask;
        });
        await check("visibility hidden source pruning distinguishes local Docker aggregates from siblings and remote cards", () => {
            var own=LocalAlert("a","a");var sibling=LocalAlert("b","b");var docker=own with { Id="docker",Source="docker",Target=new("showCard",CardID:"b") };
            Require(AttentionVisibility.RemoveAfterHide("local:Test Linux",own,"a","Test Linux")
                && AttentionVisibility.RemoveAfterHide("local:Test Linux",docker,"a","Test Linux"),"Hidden local/Docker aggregate source was retained.");
            Require(!AttentionVisibility.RemoveAfterHide("local:Test Linux",sibling,"a","Test Linux")
                && !AttentionVisibility.RemoveAfterHide("local:Other Linux",docker,"a","Test Linux")
                && !AttentionVisibility.RemoveAfterHide("legacy.actions",RemoteAlert("run"),"legacy.pr",null),"Unrelated source was pruned.");
            Require(AttentionVisibility.RemoveAfterHide("legacy.pr",RemoteAlert("review"),"legacy.pr",null),"Remote saved scope was not pruned.");
            return Task.CompletedTask;
        });
        await check("visibility remote baseline reset is scoped and retains seen history", () => {
            var settings=Settings();var ledger=new NotificationLedger();
            var oldPR=RemoteAlert("old-pr");var oldRun=RemoteAlert("old-run","failedRun");
            ledger.Observe(new("legacy.pr",[],[oldPR]),settings);ledger.Observe(new("legacy.actions",[],[oldRun]),settings);
            ledger.ResetScope("legacy.pr");
            var revealPR=RemoteAlert("reveal-pr");var freshRun=RemoteAlert("fresh-run","failedRun");
            Require(ledger.Observe(new("legacy.pr",[],[oldPR,revealPR]),settings).Length==0,"Remote reveal's first observation announced existing events.");
            Require(ledger.Observe(new("legacy.actions",[],[oldRun,freshRun]),settings).Select(alert=>alert.Id).SequenceEqual(new[]{"fresh-run"}),
                "Resetting a shared-account PR scope reset Actions observation.");
            Require(ledger.Seen.ToHashSet().SetEquals(new[]{"old-pr","old-run","reveal-pr","fresh-run"}),"Scope reset erased prior seen IDs.");
            return Task.CompletedTask;
        });
        await check("visibility worker transport snapshots active arrays before its gate and requires capability", async () => {
            await using(var legacy=new WorkerClient("Test Linux",Fake("normal"))){
                await legacy.CallAsync("hello");
                await Fails(()=>legacy.CallAsync("project.status",Project(),activeProjectIDs:[]),"protocolMismatch");
                Require(legacy.IsConnected,"Rejecting an old worker capability killed the transport.");
            }
            await using var worker=new WorkerClient("Test Linux",Fake("visibility-copy"));
            await worker.CallAsync("hello");
            var gate=(SemaphoreSlim)typeof(WorkerClient).GetField("gate",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(worker)!;
            await gate.WaitAsync();
            var active=new[]{"a","b"};Task<WorkerResponse> pending;
            try { pending=worker.CallAsync("project.status",Project(),activeProjectIDs:active);active[0]="mutated";active[1]="hidden"; }
            finally { gate.Release(); }
            Require((await pending).Status?.VersionsLine=="a|b","Queued request read the caller's mutated visibility array.");
            Require((await worker.CallAsync("project.status",Project(),activeProjectIDs:[])).Status?.VersionsLine=="","Explicit empty context was not sent.");
            foreach(var operation in new[]{"project.status","project.check"})
                await Fails(()=>worker.CallAsync(operation,Project(),activeProjectIDs:["a","a"]),"invalidRequest");
            await Fails(()=>worker.CallAsync("project.check",Project(),activeProjectIDs:["a"]),"invalidRequest");
            Require((await worker.CallAsync("hello")).Capabilities!.Contains("attention.activeProjects"),"Invalid context disrupted subsequent valid requests.");
        });
    }

    private static ProjectReference Project(string id="a",string distribution="Test Linux")=>new(id,distribution,"local","/tmp/"+id);
    private static DeckSettings Settings()=>new(1,[new("Test Linux","/tmp/synthetic-visibility"),new("Other Linux","/tmp/synthetic-other")],
        [new(Project("a"),"A"),new(Project("b"),"B")],Accounts:[new("work","Work","github","https://api.github.com",[],[],NotifiesBlocked:true,NotifiesFailedRuns:true)],
        RemoteCards:[new("legacy.pr","PR","pullRequests","Test Linux",["work"]),new("legacy.actions","Actions","actions","Test Linux",["work"])],Notifications:true);
    private static AttentionItem Item(string id,string? cardID,AttentionAction? action=null,string mark="project")=>
        new(id,id,"needsFixing",mark,id,"Synthetic fixture",1,action??new("showCard",CardID:cardID),true,false);
    private static DeckAlert LocalAlert(string id,string cardID)=>new(id,"wentDown","project",id,"Fixture",id,id,new("showCard",CardID:cardID),false);
    private static DeckAlert RemoteAlert(string id,string kind="reviewRequest")=>new(id,kind,"github",id,"Fixture",id,id,new("open","https://example.test/"+id,"github","work"),false);
    private static ProcessStartInfo Fake(string mode)
    {
        var start=new ProcessStartInfo(Environment.ProcessPath!);
        foreach(var argument in new[]{"--fake-worker","--fake-distribution","Test Linux",mode})start.ArgumentList.Add(argument);
        return start;
    }
    private static async Task Fails(Func<Task> action,string code)
    {
        try { await action(); }
        catch(WorkerException error) when(error.Code==code){return;}
        throw new IOException("Expected worker rejection: "+code);
    }
    private static void Require(bool condition,string message){if(!condition)throw new IOException(message);}
}
