using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using DevDeck.Windows.Core;

// Only owned fake-process IPC and pure values. No WSL, Docker, DDEV or real project actions.
internal static class PowerOffChecks
{
    private const string Distribution = "Test Linux";
    private const string Token = "owned-group";
    private const string Instance = "owned-worker-instance";
    private static readonly DDEVPowerOffProject[] Plan = [new("visible", Distribution, "ddev", "/tmp/visible", "Visible"),
        new("hidden", Distribution, "ddev", "/tmp/hidden", "Hidden"), new("alias", Distribution, "ddev", "/tmp/visible", "Alias")];

    internal static async Task RunAsync(Func<string, Func<Task>, Task> check)
    {
        await check("poweroff additive wire retains legacy omission and exact Swift field names", () => {
            var legacy = JsonSerializer.Deserialize<WorkerRequest>("{\"protocolVersion\":1,\"id\":\"old\",\"operation\":\"hello\"}", WorkerProtocol.Json)!;
            Require(legacy.PowerOff is null && legacy.ActiveProjectIDs is null, "An old request acquired a transaction.");
            var request = new WorkerRequest(1,"new","ddev.poweroff.prepare",PowerOff:new(Token,Plan));
            using var encoded = JsonDocument.Parse(JsonSerializer.Serialize(request,WorkerProtocol.Json));
            var context = encoded.RootElement.GetProperty("powerOff");
            Require(context.GetProperty("groupToken").GetString()==Token && context.GetProperty("projects")[0].GetProperty("kind").GetString()=="ddev",
                "The wire names no longer match Swift.");
            var result = Result("finalized",statuses:Statuses());
            var roundTrip = JsonSerializer.Deserialize<DDEVPowerOffResult>(JsonSerializer.Serialize(result,WorkerProtocol.Json),WorkerProtocol.Json)!;
            Require(roundTrip.WorkerInstanceID==Instance && roundTrip.Statuses!.Select(status=>status.ProjectID).SequenceEqual(Plan.Select(project=>project.Id)),
                "Stable worker/project IDs changed across JSON.");
            return Task.CompletedTask;
        });
        await check("poweroff preparation accepts bounded Unicode distinct IDs and same-path aliases without probing", () => {
            var projects = Enumerable.Range(0,1024).Select(index=>new DDEVPowerOffProject("id-"+index,Distribution,"ddev","/missing/folder","Missing")).ToArray();
            PowerOffValidation.ValidateRequest(new(Token,projects),"ddev.poweroff.prepare",Distribution);
            var boundary = new DDEVPowerOffProject(new string('Ж',64),Distribution,"ddev","/"+new string('x',4095),new string('Ж',256));
            PowerOffValidation.ValidateRequest(new(new string('Ж',64),[boundary,boundary with { Id="CASE",Path="/tmp/same" },boundary with { Id="case",Path="/tmp/same" }]),
                "ddev.poweroff.prepare",Distribution);
            Require(projects[0].Path=="/missing/folder", "Validation rewrote or resolved a path.");
            return Task.CompletedTask;
        });
        await check("poweroff malformed plans fail pure validation before transport or filesystem work", () => {
            foreach (var token in new string?[] { null,""," ","bad\n",new string('Ж',65) })
                Reject(()=>PowerOffValidation.ValidateRequest(new(token!,Plan),"ddev.poweroff.prepare",Distribution),"invalidRequest");
            foreach (var project in new[] { Plan[0] with { Id="" },Plan[0] with { Id="a\0" },Plan[0] with { Id=new string('Ж',65) },
                Plan[0] with { Distribution="Other Linux" },Plan[0] with { Kind="local" },Plan[0] with { Path="relative" },Plan[0] with { Path="//host/path" },
                Plan[0] with { Path="/tmp/../secret" },Plan[0] with { Path="/tmp\\bad" },Plan[0] with { Path="/tmp/\n" },Plan[0] with { Path="/"+new string('x',4096) },
                Plan[0] with { Title="" },Plan[0] with { Title="bad\t" },Plan[0] with { Title=new string('Ж',257) },null! })
                Reject(()=>PowerOffValidation.ValidateRequest(new(Token,[project]),"ddev.poweroff.prepare",Distribution),"invalidRequest");
            foreach(var projects in new[] { Array.Empty<DDEVPowerOffProject>(),new[]{Plan[0],Plan[0]},Enumerable.Range(0,1025).Select(index=>Plan[0] with { Id="id-"+index }).ToArray() })
                Reject(()=>PowerOffValidation.ValidateRequest(new(Token,projects),"ddev.poweroff.prepare",Distribution),"invalidRequest");
            return Task.CompletedTask;
        });
        await check("poweroff envelope allows active attention IDs only on finalization and abort", () => {
            foreach(var operation in new[]{"ddev.poweroff.run","ddev.poweroff.finalize","ddev.poweroff.abort"}) {
                PowerOffValidation.ValidateRequest(new(Token),operation,Distribution);
                Reject(()=>PowerOffValidation.ValidateRequest(new(Token,[]),operation,Distribution),"invalidRequest");
            }
            foreach(var operation in new[]{"ddev.poweroff.finalize","ddev.poweroff.abort"}) {
                PowerOffValidation.ValidateRequest(new(Token),operation,Distribution,activeProjectIDs:[]);
                Reject(()=>PowerOffValidation.ValidateRequest(new(Token),operation,Distribution,activeProjectIDs:["a","a"]),"invalidRequest");
            }
            Reject(()=>PowerOffValidation.ValidateRequest(new(Token,Plan),"ddev.poweroff.prepare",Distribution,activeProjectIDs:[]),"invalidRequest");
            Reject(()=>PowerOffValidation.ValidateRequest(new(Token),"ddev.poweroff.run",Distribution,activeProjectIDs:[]),"invalidRequest");
            Reject(()=>PowerOffValidation.ValidateRequest(new(Token,Plan),"ddev.poweroff.prepare",Distribution,project:new("a",Distribution,"ddev","/tmp/a")),"invalidRequest");
            Reject(()=>PowerOffValidation.ValidateRequest(new(Token,Plan),"ddev.poweroff.prepare",Distribution,remote:new("r","pullRequests",[])),"invalidRequest");
            Reject(()=>PowerOffValidation.ValidateRequest(new(Token,Plan),"ddev.poweroff.prepare",Distribution,refreshCycle:"cycle"),"invalidRequest");
            Reject(()=>PowerOffValidation.ValidateRequest(null,"ddev.poweroff.prepare",Distribution),"invalidRequest");
            Reject(()=>PowerOffValidation.ValidateRequest(new(Token,Plan),"project.stop",Distribution),"invalidRequest");
            return Task.CompletedTask;
        });
        await check("poweroff phase validation preserves renewal outcomes and sibling-route physical reconciliation", () => {
            Validate(Result("prepared"),"prepare"); Validate(Result("ran","succeeded",0),"run");
            Validate(Result("prepared","failed",7,diagnostic:new("commandFailed","First line\r\n\tSecond line")),"prepare");
            Validate(Result("finalized",statuses:Statuses()),"finalize");
            Validate(Result("aborted"),"abort");
            foreach(var state in new[]{"succeeded","failed","timedOut","cancelled","unavailable"})
                Validate(Result("aborted",state,state=="succeeded"?0:state=="failed"?9:null,Statuses(),new("outcomeNotConfirmed","Physical state is independent.")),"abort");
            return Task.CompletedTask;
        });
        await check("poweroff replies reject foreign token actor phase lease outcome and diagnostics", () => {
            var valid=Result("ran","succeeded",0);
            foreach(var result in new[]{valid with { GroupToken="foreign" },valid with { WorkerInstanceID="replacement" },valid with { Phase="prepared" },
                valid with { LeaseSecondsRemaining=-1 },valid with { LeaseSecondsRemaining=601 },valid with { CommandState="success" },
                valid with { CommandExitCode=null },valid with { CommandExitCode=2 },valid with { CommandState="failed",CommandExitCode=0 },
                valid with { CommandState="timedOut",CommandExitCode=1 },valid with { InventoryState="empty" },valid with { Statuses=null },
                valid with { Statuses=Statuses() },valid with { InventoryState="available" },valid with { Diagnostic=new("bad\n","Safe") },
                valid with { Diagnostic=new("failure",new string('Ж',8193)) },valid with { Diagnostic=new("failure","bad\0") },null! })
                Reject(()=>Validate(result,"run"),"protocolMismatch");
            Reject(()=>Validate(Result("finalized",statuses:Statuses()) with { LeaseSecondsRemaining=1 },"finalize"),"protocolMismatch");
            Reject(()=>Validate(Result("finalized",statuses:Statuses()) with { InventoryState="notChecked" },"finalize"),"protocolMismatch");
            return Task.CompletedTask;
        });
        await check("poweroff bulk replies require every prepared identity fresh date and ordinary status field limits", () => {
            var statuses=Statuses(); var result=Result("finalized",statuses:statuses);
            foreach(var changed in new[] { statuses[..2],statuses.Concat([statuses[0]]).ToArray(),new[]{statuses[1],statuses[0],statuses[2]},
                new[]{statuses[0],statuses[0],statuses[2]},new[]{statuses[0],statuses[1] with { ProjectID="foreign" },statuses[2]} })
                Reject(()=>Validate(result with { Statuses=changed },"finalize"),"protocolMismatch");
            foreach(var invalid in new[]{ statuses[0] with { CheckedAt=null },statuses[0] with { CheckedAt=-1 },statuses[0] with { CheckedAt=double.NaN },
                statuses[0] with { CheckedAt=253402300800 },statuses[0] with { State="success" },statuses[0] with { RepositoryURL="file:///tmp/secret" },
                statuses[0] with { LocalEditorURL="javascript:alert(1)" },statuses[0] with { ToolLinks=[new("Tool","file:///tmp/secret")] },
                statuses[0] with { ToolLinks=[null!] },statuses[0] with { VersionsLine=new string('Ж',257) },statuses[0] with { VersionsLine="php\n8.4" },
                statuses[0] with { CheckSummary=new("wrong","state","detail") },null! })
                Reject(()=>Validate(result with { Statuses=[invalid,statuses[1],statuses[2]] },"finalize"),"protocolMismatch");
            Validate(result with { Statuses=[statuses[0] with { CheckedAt=0 },statuses[1] with { CheckedAt=253402300799 },statuses[2]] },"finalize");
            return Task.CompletedTask;
        });
        await check("poweroff final attention uses the original local scope and never leaks into staging", () => {
            var attention=Attention(["visible"]);
            foreach(var operation in new[]{"ddev.poweroff.finalize","ddev.poweroff.abort"})
                PowerOffValidation.ValidateAttention(attention,Distribution,operation);
            foreach(var operation in new[]{"ddev.poweroff.prepare","ddev.poweroff.run"})
                Reject(()=>PowerOffValidation.ValidateAttention(attention,Distribution,operation),"protocolMismatch");
            Reject(()=>PowerOffValidation.ValidateAttention(attention with { Scope="local:Other Linux" },Distribution,"ddev.poweroff.finalize"),"protocolMismatch");
            Reject(()=>PowerOffValidation.ValidateAttention(attention with { Items=[attention.Items[0] with { Action=new("openTerminal",Path:"/tmp/../secret") }] },Distribution,"ddev.poweroff.finalize"),"protocolMismatch");
            return Task.CompletedTask;
        });
        await check("poweroff capability rejection sends no mutation and leaves legacy worker reusable", async () => {
            await using var worker=new WorkerClient(Distribution,Fake("legacy")); await worker.CallAsync("hello");
            await Fails(()=>worker.CallAsync("ddev.poweroff.prepare",powerOff:new(Token,Plan)),"protocolMismatch");
            Require(worker.IsConnected && (await worker.CallAsync("hello")).Capabilities!.SequenceEqual(new[]{"hello"}),"An old valid worker was disconnected.");
            await Fails(()=>worker.CallAsync("hello",powerOff:new(Token,Plan)),"invalidRequest");
            Require(worker.IsConnected,"Malformed local input damaged the worker.");
        });
        await check("poweroff transport captures project and active arrays before its serialization gate", async () => {
            await using var worker=new WorkerClient(Distribution,Fake("normal"));await worker.CallAsync("hello");
            var gate=(SemaphoreSlim)typeof(WorkerClient).GetField("gate",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(worker)!;
            var projects=Plan.ToArray();Task<WorkerResponse> preparation;
            await gate.WaitAsync();
            try { preparation=worker.CallAsync("ddev.poweroff.prepare",powerOff:new(Token,projects));projects[0]=projects[0] with { Path="/mutated",Title="Changed" }; }
            finally { gate.Release(); }
            await preparation;
            var active=new[]{"visible","hidden"};Task<WorkerResponse> finalization;
            await gate.WaitAsync();
            try { finalization=worker.CallAsync("ddev.poweroff.finalize",activeProjectIDs:active,powerOff:new(Token));active[0]="mutated";active[1]="other"; }
            finally { gate.Release(); }
            var response=await finalization;
            Require(response.PowerOff!.Statuses![0].Framework=="/tmp/visible|Visible" && response.Attention!.Items.Select(item=>item.Action.CardID).SequenceEqual(new[]{"visible","hidden"}),
                "A queued transaction read the caller's mutated project/visibility arrays.");
        });
        await check("poweroff actual IPC keeps progress nested diagnostics and all hidden bulk statuses through renewal", async () => {
            await using var worker=new WorkerClient(Distribution,Fake("command-failed"));await worker.CallAsync("hello");
            await worker.CallAsync("ddev.poweroff.prepare",powerOff:new(Token,Plan));var progress=new List<string>();
            var ran=await worker.CallAsync("ddev.poweroff.run",onProgress:progress.Add,powerOff:new(Token));
            Require(ran.PowerOff!.CommandState=="failed" && ran.PowerOff.CommandExitCode==9 && ran.PowerOff.Diagnostic?.Code=="commandFailed" && progress.SequenceEqual(new[]{"Owned fake progress"}),
                "A nested command outcome was flattened or correlated progress was lost.");
            var renewed=await worker.CallAsync("ddev.poweroff.prepare",powerOff:new(Token,Plan));
            Require(renewed.PowerOff!.Phase=="prepared" && renewed.PowerOff.CommandState=="failed" && renewed.PowerOff.Statuses!.Length==0,
                "Lease renewal erased the command outcome or manufactured statuses.");
            var finished=await worker.CallAsync("ddev.poweroff.finalize",activeProjectIDs:[],powerOff:new(Token));
            Require(finished.PowerOff!.Statuses!.Select(status=>status.ProjectID).SequenceEqual(Plan.Select(project=>project.Id))
                && finished.PowerOff.Diagnostic?.Code=="commandFailed" && finished.Attention!.Items.Length==0 && worker.IsConnected,
                "Hidden results, nested diagnostic or explicit empty attention was lost.");
        });
        await check("poweroff actual IPC aborts a never-run preparation without inventing inventory", async () => {
            await using var worker=new WorkerClient(Distribution,Fake("normal"));await worker.CallAsync("hello");
            await worker.CallAsync("ddev.poweroff.prepare",powerOff:new(Token,Plan));
            var response=await worker.CallAsync("ddev.poweroff.abort",activeProjectIDs:[],powerOff:new(Token));
            Require(response.PowerOff!.CommandState=="notRun" && response.PowerOff.InventoryState=="notChecked" && response.PowerOff.Statuses!.Length==0
                && response.PowerOff.LeaseSecondsRemaining==0,"A cancelled preparation was reported as an executed/fresh physical check.");
        });
        await check("poweroff worker admission failure remains typed and does not poison later requests", async () => {
            await using var worker=new WorkerClient(Distribution,Fake("reject-once"));await worker.CallAsync("hello");
            await Fails(()=>worker.CallAsync("ddev.poweroff.prepare",powerOff:new(Token,Plan)),"groupBusy");
            Require(worker.IsConnected,"A normal admission failure killed the transport.");
            await worker.CallAsync("ddev.poweroff.prepare",powerOff:new(Token,Plan));
            Require((await worker.CallAsync("ddev.poweroff.abort",powerOff:new(Token))).PowerOff!.Phase=="aborted","The rejected token could not later be prepared.");
        });
        await check("poweroff untrusted IPC fails closed before a foreign bulk result reaches consumers", async () => {
            foreach(var mode in new[]{"foreign-token","foreign-instance","foreign-phase","missing-result","bad-lease","bulk-missing","bulk-link","bulk-date","extra-status","staging-attention","foreign-attention"}) {
                await using var worker=new WorkerClient(Distribution,Fake(mode));await worker.CallAsync("hello");
                await worker.CallAsync("ddev.poweroff.prepare",powerOff:new(Token,Plan));
                await Fails(()=>worker.CallAsync(mode.StartsWith("bulk",StringComparison.Ordinal)||mode=="foreign-attention"?"ddev.poweroff.finalize":"ddev.poweroff.run",powerOff:new(Token)),"protocolMismatch");
                Require(!worker.IsConnected,"Malformed "+mode+" output left an untrusted process connected.");
            }
        });
        await check("poweroff wire requires explicit lease and inventory fields instead of accepting DTO defaults", async () => {
            foreach(var mode in new[]{"omit-lease","omit-inventory"}) {
                await using var worker=new WorkerClient(Distribution,Fake(mode));await worker.CallAsync("hello");
                await Fails(()=>worker.CallAsync("ddev.poweroff.prepare",powerOff:new(Token,Plan)),"invalidResponse");
                Require(!worker.IsConnected,"An incomplete result left its process connected.");
            }
        });
        await check("poweroff payload is forbidden on an unrelated legacy reply", async () => {
            await using var worker=new WorkerClient(Distribution,Fake("unexpected-hello"));
            await Fails(()=>worker.CallAsync("hello"),"protocolMismatch");Require(!worker.IsConnected,"An unsolicited group payload was admitted.");
        });
        await check("poweroff renewal preserves the frozen plan and refuses unprepared follow-up locally", async () => {
            await using var worker=new WorkerClient(Distribution,Fake("normal"));await worker.CallAsync("hello");
            await Fails(()=>worker.CallAsync("ddev.poweroff.run",powerOff:new(Token)),"invalidRequest");
            await worker.CallAsync("ddev.poweroff.prepare",powerOff:new(Token,Plan));
            await Fails(()=>worker.CallAsync("ddev.poweroff.prepare",powerOff:new(Token,[Plan[0] with { Path="/changed" },Plan[1],Plan[2]])),"invalidRequest");
            Require(worker.IsConnected,"A malformed renewal killed the staged endpoint.");
            await worker.CallAsync("ddev.poweroff.abort",powerOff:new(Token));
        });
    }

    // Called only by a dedicated Program entry point, not by any production executable.
    internal static async Task<int> RunFakeAsync(string[] args)
    {
        var mode=args.Last();DDEVPowerOffProject[]? projects=null;var command="notRun";int? exit=null;WorkerFailure? diagnostic=null;var rejected=false;
        while(await Console.In.ReadLineAsync() is { } line) {
            var request=JsonSerializer.Deserialize<WorkerRequest>(line,WorkerProtocol.Json)!;
            var response=new WorkerResponse(1,request.Id,Distribution,null,null,null,null);
            if(request.Operation=="hello") {
                response=response with { Capabilities=mode=="legacy"?["hello"]:["hello","attention.activeProjects",PowerOffValidation.Capability] };
                if(mode=="unexpected-hello")response=response with { PowerOff=Result("prepared") };
            } else if(!PowerOffValidation.IsOperation(request.Operation)||mode=="legacy")response=response with { Error=new("unsupportedOperation","Fake operation unavailable.") };
            else if(mode=="reject-once"&&!rejected&&request.Operation=="ddev.poweroff.prepare") {
                rejected=true;response=response with { Error=new("groupBusy","Another owned fake group is busy.") };
            } else {
                if(request.Operation=="ddev.poweroff.prepare")projects=request.PowerOff!.Projects!.ToArray();
                if(request.Operation=="ddev.poweroff.run") {
                    command=mode=="command-failed"?"failed":"succeeded";exit=command=="failed"?9:0;
                    diagnostic=command=="failed"?new("commandFailed","Owned fake failure\nDetails"):null;
                    if(mode=="command-failed")Console.WriteLine(JsonSerializer.Serialize(response with { Event=new("progress","Owned fake progress") },WorkerProtocol.Json));
                }
                var terminal=request.Operation is "ddev.poweroff.finalize" or "ddev.poweroff.abort";
                var reconciled=request.Operation=="ddev.poweroff.finalize"||request.Operation=="ddev.poweroff.abort"&&command!="notRun";
                var statuses=reconciled?projects!.Select(project=>new ProjectStatus(project.Id,"stopped",null,null,project.Path+"|"+project.Title,null,CheckedAt:0)).ToArray():[];
                var phase=request.Operation["ddev.poweroff.".Length..] switch {"prepare"=>"prepared","run"=>"ran","finalize"=>"finalized",_=>"aborted"};
                var result=new DDEVPowerOffResult(request.PowerOff!.GroupToken,Instance,phase,terminal?0:600,command,exit,diagnostic,reconciled?"available":"notChecked",statuses);
                response=response with { PowerOff=result,Attention=terminal?Attention(request.ActiveProjectIDs??projects!.Select(project=>project.Id).ToArray()):null };
                if(request.Operation!="ddev.poweroff.prepare") {
                    response=mode switch {
                        "foreign-token"=>response with { PowerOff=result with { GroupToken="foreign" } },
                        "foreign-instance"=>response with { PowerOff=result with { WorkerInstanceID="replacement" } },
                        "foreign-phase"=>response with { PowerOff=result with { Phase="prepared" } },
                        "missing-result"=>response with { PowerOff=null },
                        "bad-lease"=>response with { PowerOff=result with { LeaseSecondsRemaining=601 } },
                        "bulk-missing"=>response with { PowerOff=result with { Statuses=statuses[..2] } },
                        "bulk-link"=>response with { PowerOff=result with { Statuses=[statuses[0] with { ToolLinks=[new("Tool","file:///tmp/secret")] },statuses[1],statuses[2]] } },
                        "bulk-date"=>response with { PowerOff=result with { Statuses=[statuses[0] with { CheckedAt=-1 },statuses[1],statuses[2]] } },
                        "extra-status"=>response with { Status=new("visible","stopped",null,null,null,null) },
                        "staging-attention"=>response with { Attention=Attention(["visible"]) },
                        "foreign-attention"=>response with { Attention=Attention(["visible"]) with { Scope="local:Other Linux" } },
                        _=>response
                    };
                }
            }
            var encoded=JsonSerializer.Serialize(response,WorkerProtocol.Json);
            if(request.Operation=="ddev.poweroff.prepare"&&mode=="omit-lease")encoded=encoded.Replace("\"leaseSecondsRemaining\":600,","",StringComparison.Ordinal);
            if(request.Operation=="ddev.poweroff.prepare"&&mode=="omit-inventory")encoded=encoded.Replace("\"inventoryState\":\"notChecked\",","",StringComparison.Ordinal);
            Console.WriteLine(encoded);
        }
        return 0;
    }

    private static DDEVPowerOffResult Result(string phase,string command="notRun",int? exit=null,ProjectStatus[]? statuses=null,WorkerFailure? diagnostic=null)=>
        new(Token,Instance,phase,phase is "finalized" or "aborted"?0:600,command,exit,diagnostic,statuses is null?"notChecked":"available",statuses??[]);
    private static ProjectStatus[] Statuses()=>Plan.Select(project=>new ProjectStatus(project.Id,"stopped",null,null,null,null,CheckedAt:0)).ToArray();
    private static AttentionSnapshot Attention(string[] active)=>new("local:"+Distribution,active.Select(id=>new AttentionItem("project:"+id,"project:"+id,"needsFixing","ddev",id,
        "Owned fake detail",0,new("showCard",CardID:id),true,false)).ToArray(),[],"unknown",true);
    private static void Validate(DDEVPowerOffResult result,string phase)=>PowerOffValidation.ValidateResponse(result,"ddev.poweroff."+phase,Plan,Instance,Token);
    private static ProcessStartInfo Fake(string mode) { var start=new ProcessStartInfo(Environment.ProcessPath!);start.ArgumentList.Add("--fake-poweroff-worker");start.ArgumentList.Add(mode);return start; }
    private static void Reject(Action action,string code) { try { action(); }catch(WorkerException error)when(error.Code==code){return;}throw new IOException("Expected pure rejection: "+code); }
    private static async Task Fails(Func<Task> action,string code) { try { await action(); }catch(WorkerException error)when(error.Code==code){return;}throw new IOException("Expected transport rejection: "+code); }
    private static void Require(bool condition,string message){if(!condition)throw new IOException(message);}
}
