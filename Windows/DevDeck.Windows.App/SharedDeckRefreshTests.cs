using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal static class SharedDeckRefreshTests
{
    internal static async Task RunAsync(Application app,List<object> checks)
    {
        var loop=new SharedDeckRefreshLoop();var first=Pending<SharedRefreshRead>();var order=new List<string>();var inbox=true;
        SharedRefreshSource Source(string id,Func<Task<SharedRefreshRead>> read,Func<bool>? eligible=null)=>new(id,eligible??(()=>true),()=>{order.Add(id);return read();});
        var sources=new[]{Source("pulls",()=>first.Task),Source("inbox",()=>Task.FromResult(new SharedRefreshRead([],300)),()=>inbox),
            Source("merge",()=>Task.FromResult(new SharedRefreshRead([],500))),Source("actions",()=>Task.FromResult(new SharedRefreshRead([],400)))};
        Task Logs(){order.Add("logs");return Task.CompletedTask;}Task Git(){order.Add("git");return Task.CompletedTask;}
        var pass=loop.RunAsync(sources,120,Logs,Git,()=>true,()=>DateTimeOffset.FromUnixTimeSeconds(100));
        var repeated=loop.RunAsync([],600,Logs,Git,()=>true);
        Require(ReferenceEquals(pass,repeated)&&order.SequenceEqual(new[]{"pulls"}),"Shared pass duplicates a pending provider or scans Git before providers finish.");
        Add(checks,"sharedRefresh.pendingCoalescing",new{onePass=true,noPrematureGit=true});
        inbox=false;first.SetResult(new([new(null,"forbidden")]));var result=await pass;
        Require(order.SequenceEqual(new[]{"pulls","merge","actions","logs","git"})&&result.Delay.TotalSeconds==240&&result.ConsecutiveFailures==1&&result.ReadSources==3,
            "Shared pass loses admission visibility, provider/log/Git order or first-failure backoff.");
        Add(checks,"sharedRefresh.orderAndBackoff",new{hiddenNextSourceSkipped=true,logsThenGit=true,successfulHintsDoNotOverrideFailedPass=true});
        order.Clear();result=await loop.RunAsync([Source("pulls",()=>Task.FromResult(new SharedRefreshRead([new(null,"unreachable")])) )],120,Logs,Git,()=>true);
        Require(result.ConsecutiveFailures==2&&result.Delay.TotalSeconds==480,"Shared failure streak does not span passes.");
        Add(checks,"sharedRefresh.failureStreak",new{sharedAcrossSourcesAndPasses=true});
        result=await loop.RunAsync([Source("inbox",()=>Task.FromResult(new SharedRefreshRead([],600)))],120,Logs,Git,()=>true);
        Require(result.ConsecutiveFailures==0&&result.Delay.TotalSeconds==600,"Successful shared pass does not reset failure streak or honor server hint.");
        Add(checks,"sharedRefresh.recoveryHint",new{streakReset=true,successfulServerHintHonored=true});
        result=await loop.RunAsync([Source("first",()=>Task.FromResult(new SharedRefreshRead([new(null,"rateLimited",2000)]))),
            Source("later",()=>Task.FromResult(new SharedRefreshRead([new(null,"rateLimited",150)])))],120,Logs,Git,()=>true,()=>DateTimeOffset.FromUnixTimeSeconds(100));
        Require(result.Delay.TotalSeconds==900,"Later rate-limit failure overrides the first failure or reset clamp.");
        Add(checks,"sharedRefresh.firstReset",new{firstFailureOwnsReset=true,boundedResetDelay=true});
        order.Clear();result=await loop.RunAsync([],120,Logs,Git,()=>true);
        Require(order.SequenceEqual(new[]{"logs","git"})&&result.Delay.TotalSeconds==120&&result.ConsecutiveFailures==0,
            "WIF-only shared pass depends on a provider/account or invents a fast local cadence.");
        Add(checks,"sharedRefresh.wifOnly",new{noAccountOrProvider=true,original120Cadence=true});
        order.Clear();result=await loop.RunAsync([Source("broken",()=>Task.FromException<SharedRefreshRead>(new IOException("fixture"))),
            Source("healthy",()=>Task.FromResult(new SharedRefreshRead([])))],120,()=>Task.FromException(new IOException("owned log failure")),Git,()=>true);
        Require(order.SequenceEqual(new[]{"broken","healthy","git"})&&result.Delay.TotalSeconds==240,
            "One failed provider/open log prevents healthy sibling or checkout reads.");
        Add(checks,"sharedRefresh.failureIsolation",new{providerAndLogFailurePreserveGit=true,siblingReadContinues=true});
        await NativeCycleAsync(app,checks);
    }

    private static async Task NativeCycleAsync(Application app,List<object> checks)
    {
        var path=Path.Combine(Path.GetTempPath(),"devdeck-shared-pass-"+Guid.NewGuid().ToString("N")+".json");
        var store=new SettingsStore(path);store.Save(new(1,[new("Alpha","/tmp/shared-native-worker")],[],
            Accounts:[new("fake","Fake GitHub","github","https://api.github.com",[],[])],
            RemoteCards:[new("alias.pulls","Pulls","pullRequests","Alpha",["fake"]),new("alias.inbox","Inbox","inbox","Alpha",["fake"])],
            Language:"en",RefreshSeconds:120,WorkInFlight:new(true)));
        var controller=new DeckController(app,store,live:true);var first=Pending<RemoteSnapshot>();var order=new List<string>();
        var remotes=Get<List<RemoteCard>>(controller,"remoteCards");Task? run=null;
        try{
            foreach(var saved in controller.Settings.RemoteCardList.Where(saved=>saved.Id.StartsWith("alias.",StringComparison.Ordinal))){
                var card=new RemoteCard(controller,saved,live:false,snapshotReader:_=>{
                    order.Add(saved.Kind);return saved.Kind=="pullRequests"?first.Task:Task.FromResult(SampleDeck.Remote(saved.Kind) with{CardID=saved.Id});
                });remotes.Add(card);card.SetDeckVisible(true);
            }
            var aggregate=new WorkInFlightCard(controller,controller.Settings.WorkInFlight!,live:false,snapshotReader:_=>{
                order.Add("git");return Task.FromResult(new WorkInFlightSnapshot([],0,DateTimeOffset.UtcNow.ToUnixTimeSeconds()));
            });Set(controller,"workInFlightCard",aggregate);aggregate.SetDeckVisible(true);
            run=controller.RefreshAllAsync();var repeated=controller.RefreshAllAsync();
            Require(order.SequenceEqual(new[]{"pullRequests"})&&!controller.SharedPollEnabled&&!run.IsCompleted,
                "Controller starts another remote timer/Git read while provider is pending.");
            first.SetResult(SampleDeck.Remote("pullRequests") with{CardID="alias.pulls"});await Task.WhenAll(run,repeated);
            Require(order.SequenceEqual(new[]{"pullRequests","inbox","git"})&&controller.SharedPollEnabled&&controller.SharedPollInterval.TotalSeconds==120
                && !controller.LocalPollEnabled&&typeof(RemoteCard).GetField("polling",BindingFlags.NonPublic|BindingFlags.Instance) is null,
                "Actual controller loses shared provider→Git cadence or retains independent remote timers.");
            Add(checks,"sharedRefresh.actualController",new{savedAliasesSourceOrder=true,oneControllerTimer=true,noRemoteTimer=true,manualCoalescing=true,localChannelIndependent=true,allReadersInjected=true});
        }finally{
            first.TrySetResult(SampleDeck.Remote("pullRequests") with{CardID="alias.pulls"});if(run is not null)await run;
            controller.CloseViews();foreach(var file in new[]{path,path+".bak"})if(File.Exists(file))File.Delete(file);
        }
    }
    private static void Add(List<object> checks,string name,object details)=>checks.Add(new{name,details});
    private static void Require(bool condition,string message){if(!condition)throw new IOException(message);}
    private static TaskCompletionSource<T> Pending<T>()=>new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static T Get<T>(object owner,string name)=>(T)owner.GetType().GetField(name,BindingFlags.NonPublic|BindingFlags.Instance)!.GetValue(owner)!;
    private static void Set(object owner,string name,object value)=>owner.GetType().GetField(name,BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(owner,value);
}
