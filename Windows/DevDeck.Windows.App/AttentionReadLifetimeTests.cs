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

/// Production owner/controller paths with owned settings and held fake reads/writes only.
internal static class AttentionReadLifetimeTests
{
    private const string Distribution = "Test Linux";
    private const string CardID = "owned.inbox";
    private const string SiblingID = "owned.inbox.sibling";
    private const string PullsID = "owned.pulls";
    private const string Origin = "https://api.example.test";
    private const string OtherOrigin = "https://other.example.test";
    private const string ReviewURL = "https://example.test/repo/pull/42";
    private static InboxReadTarget Target => new(CardID,"account-a","42",Origin);

    internal static async Task RunAsync(Application application,List<object> checks)
    {
        await CheckExactOptimisticAsync(application,checks);
        await CheckPendingPollAsync(application,checks);
        await CheckAdmissionAfterPollAsync(application,checks);
        await CheckQueuedHideAsync(application,checks);
        await CheckQueuedScopeAsync(application,checks);
        await CheckEarlyAdmissionAsync(application,checks);
        await CheckHiddenCompletionAsync(application,checks,fail:false);
        await CheckHiddenCompletionAsync(application,checks,fail:true);
        await CheckLostWriteAsync(application,checks);
        await CheckCloseAsync(application,checks);
        await CheckCapturedChoiceAsync(application,checks);
    }

    private static async Task CheckExactOptimisticAsync(Application application,List<object> checks)
    {
        using var fixture=new Owned(application);
        var release=Pending<bool>();Task<bool>? operation=null;
        fixture.Writer=(_,request,token,_)=>release.Task.WaitAsync(token);
        try {
            var before=fixture.Card.Latest!;var authorization=fixture.Card.AuthorizationSnapshot;
            var checkedAt=fixture.Controller.LastCheckedAt;var clock=Get<TextBlock>(fixture.Card,"timestamp").Text;
            var ownHandle=Handle(fixture.Card);var siblingHandle=Handle(fixture.Sibling);var pullsHandle=Handle(fixture.Pulls);
            var siblingSnapshot=fixture.Sibling.Latest;
            var siblingSignals=fixture.Scope(SiblingID);var pullsSignals=fixture.Scope(PullsID);
            fixture.Card.SetExpanded(true);Invoke(fixture.Card,"ShowAll");var list=Get<Window>(fixture.Card,"listWindow");var listHandle=Handle(list);
            operation=fixture.Read();
            Require(!operation.IsCompleted && fixture.Card.IsMutating && fixture.Card.PendingInboxRead==Target
                && fixture.WriteCalls==1 && fixture.TokenReads==1,"Typed read did not enter the held production mutation exactly once.");
            var masked=fixture.Card.Latest??throw new IOException("Optimistic read discarded its previously qualified snapshot.");
            Require(!Has(masked,Target) && Has(masked,Target with{AccountID="account-b",Endpoint=OtherOrigin})
                && masked.Rows.Length==before.Rows.Length-1 && masked.Total==before.Total-1,
                "Optimism removed the same-number sibling account or another row.");
            Require(ReferenceEquals(fixture.Card.AuthorizationSnapshot,authorization) && Has(authorization!,Target)
                && masked.RepositoryCount==before.RepositoryCount && masked.NamespaceCount==before.NamespaceCount
                && masked.PollIntervalSeconds==before.PollIntervalSeconds && masked.Capped==before.Capped,
                "Optimism rewrote raw authorization or non-row snapshot metadata.");
            Require(fixture.Controller.LastCheckedAt==checkedAt && Get<TextBlock>(fixture.Card,"timestamp").Text==clock,
                "Optimistic click invented a successful network-check time.");
            Require(!fixture.Scope(CardID).Any(item=>item.InboxRead==Target)
                && fixture.Scope(CardID).Any(item=>item.InboxRead?.AccountID=="account-b" && item.InboxRead.ThreadID=="42")
                && ReferenceEquals(fixture.Scope(SiblingID),siblingSignals) && ReferenceEquals(fixture.Scope(PullsID),pullsSignals)
                && pullsSignals.All(item=>item.InboxRead is null),"Read removed a sibling scope or grafted an alternate onto the existing PR representative.");
            Require(Handle(fixture.Card)==ownHandle && Handle(fixture.Sibling)==siblingHandle && Handle(fixture.Pulls)==pullsHandle
                && ReferenceEquals(fixture.Sibling.Latest,siblingSnapshot) && ReferenceEquals(Get<Window>(fixture.Card,"listWindow"),list)
                && Handle(list)==listHandle && list.IsVisible && Get<bool>(fixture.Card,"expanded")
                && Get<StackPanel>(fixture.Card,"fullRows").Children.Count==2*masked.Rows.Length,
                "Optimistic read rebuilt a window/list, lost expansion or failed to update its own full list.");
            var sent=fixture.LastWrite!;
            Require(sent.CardID==CardID && sent.Kind=="inbox" && sent.Accounts.Length==1 && sent.Accounts[0].Id=="account-a"
                && sent.Accounts[0].Endpoint==Origin && sent.ThreadIDs!.SequenceEqual(new[]{"42"}),"Recorded write did not target the exact captured account/origin/raw thread.");
            release.SetResult(true);Require(await operation,"Valid owned write was not admitted.");
            Require(fixture.WriteCalls==1 && fixture.Reads==1 && !fixture.Card.IsMutating && fixture.Card.PendingInboxRead is null,
                "Successful write was replayed or did not release owned busy state.");
            checks.Add(new{name="attention.read.exactOptimisticTuple",sameNumberSameReviewUrlAcrossAccounts=true,rawAuthorizationRetained=true,
                onlySelectedScopeAndRowRemoved=true,independentPrRepresentativeRetained=true,noClickClockChange=true,sameHwndFullListAndExpansion=true,oneCapturedWrite=true});
        } finally {release.TrySetResult(true);if(operation is not null)await Settle(operation);}
    }

    private static async Task CheckPendingPollAsync(Application application,List<object> checks)
    {
        using var fixture=new Owned(application);
        var poll=Pending<RemoteSnapshot>();var write=Pending<bool>();Task? read=null;Task<bool>? operation=null;
        var pollToken=default(CancellationToken);var writeToken=default(CancellationToken);
        fixture.Reader=async token=>{pollToken=token;var snapshot=await poll.Task.WaitAsync(token);fixture.Controller.ObserveAttention(snapshot.Signals);return snapshot;};
        fixture.Writer=(_,_,token,_)=>{writeToken=token;return write.Task.WaitAsync(token);};
        try {
            read=fixture.Card.RefreshAsync();Require(fixture.Reads==1 && !read.IsCompleted,"Fixture did not hold a real in-flight owner refresh.");
            operation=fixture.Read();Require(!operation.IsCompleted && fixture.WriteCalls==0 && !pollToken.IsCancellationRequested
                && !Has(fixture.Card.Latest!,Target),"Typed mutation cancelled the prior read or waited before applying its optimistic projection.");
            var stale=fixture.Initial with{RepositoryCount=9};poll.SetResult(stale);await read;await Turns();
            Require(fixture.WriteCalls==1 && !operation.IsCompleted && !pollToken.IsCancellationRequested && !writeToken.IsCancellationRequested
                && ReferenceEquals(fixture.Card.AuthorizationSnapshot,stale) && !Has(fixture.Card.Latest!,Target)
                && fixture.Card.Latest!.RepositoryCount==9 && !fixture.Scope(CardID).Any(item=>item.InboxRead==Target),
                "Late stale poll resurrected the selected row/signal, lost physical metadata or cancelled the mutation.");
            Require(!await fixture.Read() && fixture.WriteCalls==1,"Repeated activation during a pending read sent a duplicate write.");
            await fixture.Card.RefreshAsync();Require(fixture.Reads==1,"Busy typed mutation admitted another owner poll.");
            fixture.Reader=token=>{fixture.Controller.ObserveAttention(fixture.After.Signals);return Task.FromResult(fixture.After);};
            write.SetResult(true);Require(await operation,"Valid write after prior poll did not complete.");
            Require(fixture.Reads==2 && fixture.WriteCalls==1 && !Has(fixture.Card.Latest!,Target),"Completion replayed the write or failed one safe fresh reconciliation.");
            checks.Add(new{name="attention.read.pendingPollMask",realRefreshAndMutationTokens=true,pendingPollNotCancelled=true,
                physicalMetadataRetained=true,lateSignalAndRowMasked=true,busyRepeatCoalesced=true,oneWriteOneFreshRead=true});
        } finally {poll.TrySetResult(fixture.Initial);write.TrySetResult(true);if(read is not null)await Settle(read);if(operation is not null)await Settle(operation);}
    }

    private static async Task CheckQueuedHideAsync(Application application,List<object> checks)
    {
        using var fixture=new Owned(application);var gate=Get<SemaphoreSlim>(fixture.Controller,"actions");Task<bool>? operation=null;
        var hwnd=Handle(fixture.Card);var sibling=Handle(fixture.Sibling);
        await gate.WaitAsync();
        try {
            operation=fixture.Read();await Turns();Require(!operation.IsCompleted && fixture.TokenReads==0 && fixture.WriteCalls==0,"Queued read bypassed the real controller gate.");
            await fixture.Controller.SetCardVisibleAsync(CardID,false);
            Require(!fixture.Card.DeckVisible && !fixture.Card.IsVisible && !fixture.Card.IsClosed && Handle(fixture.Card)==hwnd
                && fixture.Sibling.IsVisible && Handle(fixture.Sibling)==sibling,"Actual fast hide closed the retained owner or affected its sibling.");
        } finally {gate.Release();}
        Require(!await operation! && fixture.TokenReads==0 && fixture.WriteCalls==0 && fixture.Reads==0 && !fixture.Card.IsMutating
            && !fixture.Card.IsVisible,"Queued hidden read accessed a credential, wrote, fetched or revealed the owner.");
        checks.Add(new{name="attention.read.queuedHide",productionFastVisibilitySetter=true,realGateHeld=true,revalidateBeforeVaultAndWrite=true,
            hiddenOwnerAndSiblingHwndRetained=true,noHiddenFetchOrReveal=true});
    }

    private static async Task CheckAdmissionAfterPollAsync(Application application,List<object> checks)
    {
        using var fixture=new Owned(application);var poll=Pending<RemoteSnapshot>();Task? read=null;Task<bool>? operation=null;var first=true;
        fixture.Reader=async token=>{
            var snapshot=first?await poll.Task.WaitAsync(token):fixture.After;first=false;
            fixture.Controller.ObserveAttention(snapshot.Signals);return snapshot;
        };
        try {
            read=fixture.Card.RefreshAsync();operation=fixture.Read();
            Require(!operation.IsCompleted && fixture.TokenReads==0 && fixture.WriteCalls==0,"Mutation did not wait for the owned current poll.");
            poll.SetResult(fixture.After);await read;
            Require(!await operation && fixture.TokenReads==0 && fixture.WriteCalls==0 && !Has(fixture.Card.AuthorizationSnapshot!,Target)
                && !fixture.Card.IsMutating && fixture.Card.PendingInboxRead is null,"Pending refresh removed the unread row but stale action still accessed the vault or wrote.");
            checks.Add(new{name="attention.read.currentUnreadAfterPendingPoll",actualPriorReadHeld=true,
                revalidateFreshUnreadRowBeforeVault=true,noWriteForAlreadyReadOrRemovedRow=true,mutationReleased=true});
        } finally {poll.TrySetResult(fixture.After);if(read is not null)await Settle(read);if(operation is not null)await Settle(operation);}
    }

    private static async Task CheckQueuedScopeAsync(Application application,List<object> checks)
    {
        var variants=new[]{"removedConfig","removedOwner","replacedOwner","accountDisabled","endpointChanged","scopeChanged","distributionChanged"};
        foreach(var variant in variants){
            using var fixture=new Owned(application);var gate=Get<SemaphoreSlim>(fixture.Controller,"actions");Task<bool>? operation=null;
            await gate.WaitAsync();
            try {
                operation=fixture.Read();await Turns();Require(!operation.IsCompleted && fixture.TokenReads==0,"Queued scope fixture bypassed the real gate.");
                var settings=fixture.Controller.Settings;
                settings=variant switch{
                    "removedConfig"=>settings with{RemoteCards=settings.RemoteCardList.Where(card=>card.Id!=CardID).ToArray()},
                    "accountDisabled"=>settings with{Accounts=settings.AccountList.Select(account=>account.Id=="account-a"?account with{Enabled=false}:account).ToArray()},
                    "endpointChanged"=>settings with{Accounts=settings.AccountList.Select(account=>account.Id=="account-a"?account with{Endpoint="https://edited.example.test"}:account).ToArray()},
                    "scopeChanged"=>settings with{RemoteCards=settings.RemoteCardList.Select(card=>card.Id==CardID?card with{AccountIDs=["account-b"]}:card).ToArray()},
                    "distributionChanged"=>settings with{RemoteCards=settings.RemoteCardList.Select(card=>card.Id==CardID?card with{Distribution="Other Linux"}:card).ToArray()},
                    _=>settings
                };
                // SaveSettingsAsync shares the held gate. This accepted owned setter seam
                // models an already committed external state at the next admission boundary.
                fixture.CommitState(settings);
                if(variant=="removedOwner")Get<List<RemoteCard>>(fixture.Controller,"remoteCards").Remove(fixture.Card);
                if(variant=="replacedOwner"){
                    var owners=Get<List<RemoteCard>>(fixture.Controller,"remoteCards");
                    var replacement=new RemoteCard(fixture.Controller,fixture.Card.Configuration,live:false);
                    replacement.ApplySnapshot(fixture.Initial);replacement.SetDeckVisible(true);
                    owners[owners.IndexOf(fixture.Card)]=replacement;
                    Require(!fixture.Card.IsClosed,"Replacement fixture cancelled the old owner instead of testing its current identity guard.");
                }
            } finally {gate.Release();}
            try {
                Require(!await operation! && fixture.TokenReads==0 && fixture.WriteCalls==0 && fixture.Reads==0 && !fixture.Card.IsMutating,
                    "Stale queued "+variant+" owner accessed a credential, wrote or launched an old-owner refresh.");
            } finally {if(operation is not null)await Settle(operation);}
        }
        checks.Add(new{name="attention.read.queuedCurrentScope",realGateAdmission=true,ownedCommittedStateSeam=true,
            cases=variants,noCredentialOrWriteAfterChanges=true,noOldOwnerRefresh=true});
    }

    private static async Task CheckEarlyAdmissionAsync(Application application,List<object> checks)
    {
        using var fixture=new Owned(application);var before=fixture.Card.Latest;var clock=fixture.Controller.LastCheckedAt;
        fixture.CommitState(fixture.Controller.Settings with{Accounts=fixture.Controller.Settings.AccountList.Select(account=>account.Id=="account-a"?account with{Enabled=false}:account).ToArray()});
        Require(!await fixture.Read() && fixture.WriteCalls==0 && fixture.TokenReads==0 && fixture.Reads==0
            && ReferenceEquals(fixture.Card.Latest,before) && !fixture.Card.IsMutating && fixture.Card.PendingInboxRead is null
            && fixture.Controller.LastCheckedAt==clock,"Initially stale action changed presentation or attempted admission.");
        checks.Add(new{name="attention.read.staleBeforeMutation",noOptimisticChange=true,noClockChange=true,noCredentialWriteOrRead=true});
    }

    private static async Task CheckHiddenCompletionAsync(Application application,List<object> checks,bool fail)
    {
        using var fixture=new Owned(application);var write=Pending<bool>();Task<bool>? operation=null;var token=default(CancellationToken);
        fixture.Writer=(_,_,cancellation,_)=>{token=cancellation;return write.Task.WaitAsync(cancellation);};
        fixture.Card.SetExpanded(true);Invoke(fixture.Card,"ShowAll");var list=Get<Window>(fixture.Card,"listWindow");
        var hwnd=Handle(fixture.Card);var listHandle=Handle(list);var clock=fixture.Controller.LastCheckedAt;
        try {
            operation=fixture.Read();Require(fixture.WriteCalls==1 && token.CanBeCanceled,"Hidden fixture did not enter its real owned mutation.");
            await fixture.Controller.SetCardVisibleAsync(CardID,false);await fixture.Card.RefreshAsync();fixture.Card.Summon();
            Require(!token.IsCancellationRequested && fixture.Card.IsMutating && !fixture.Card.IsVisible && fixture.Reads==0
                && list.IsVisible && Handle(list)==listHandle,"Hide cancelled mutation, fetched/revealed widget or closed its ordinary list.");
            if(fail)write.SetException(new WorkerException("disconnected","owned lost response"));else write.SetResult(true);
            if(fail)await Failure(operation,"disconnected");else Require(await operation,"Already entered hidden write did not finish.");
            Require(!fixture.Card.IsVisible && !fixture.Card.IsMutating && fixture.Card.PendingInboxRead is null && !token.IsCancellationRequested
                && fixture.Reads==0 && fixture.WriteCalls==1 && fixture.Controller.LastCheckedAt==clock && Handle(fixture.Card)==hwnd
                && ReferenceEquals(Get<Window>(fixture.Card,"listWindow"),list) && Handle(list)==listHandle && Get<bool>(fixture.Card,"expanded"),
                "Hidden completion lost identity/clock or replayed/fetched/revealed the owner.");
            if(fail)Require(Get<TextBlock>(fixture.Card,"footer").Text.Contains(Text.L("windows.workerDisconnected"),StringComparison.Ordinal)
                && !Get<TextBlock>(fixture.Card,"footer").Text.Contains("owned lost response",StringComparison.Ordinal)
                && Has(fixture.Card.AuthorizationSnapshot!,Target),"Hidden failure lost its message or physical cached unread state.");
            checks.Add(new{name=fail?"attention.read.hiddenFailure":"attention.read.hiddenSuccess",actualOwnedCts=true,
                hiddenOperationNotCancelled=true,oneWriteNoHiddenRefreshOrReveal=true,ordinaryListAndHwndRetained=true,failureRetained=fail});
        } finally {write.TrySetResult(true);if(operation is not null)await Settle(operation);}
    }

    private static async Task CheckLostWriteAsync(Application application,List<object> checks)
    {
        using var fixture=new Owned(application);var write=Pending<bool>();Task<bool>? operation=null;
        fixture.Reader=token=>{fixture.Controller.ObserveAttention(fixture.Initial.Signals);return Task.FromResult(fixture.Initial);};
        fixture.Writer=(_,_,token,_)=>write.Task.WaitAsync(token);
        var hwnd=Handle(fixture.Card);
        try {
            operation=fixture.Read();Require(!Has(fixture.Card.Latest!,Target),"Lost-write fixture did not first show the optimistic projection.");
            write.SetException(new WorkerException("disconnected","owned lost write response"));await Failure(operation,"disconnected");
            Require(fixture.WriteCalls==1 && fixture.TokenReads==1 && fixture.Reads==1 && Has(fixture.Card.Latest!,Target)
                && fixture.Scope(CardID).Any(item=>item.InboxRead==Target) && !fixture.Card.IsMutating
                && Get<TextBlock>(fixture.Card,"footer").Text.Contains(Text.L("windows.workerDisconnected"),StringComparison.Ordinal)
                && !Get<TextBlock>(fixture.Card,"footer").Text.Contains("owned lost write response",StringComparison.Ordinal) && Handle(fixture.Card)==hwnd,
                "Lost response retried the write, hid failure or could not restore unread state from one fresh response.");
            checks.Add(new{name="attention.read.lostWrite",writeNotReplayed=true,oneFreshReconciliation=true,
                freshUnreadRowAndSignalRestored=true,errorPropagatesAndFooterRetained=true,sameHwnd=true});
        } finally {write.TrySetResult(true);if(operation is not null)await Settle(operation);}
    }

    private static async Task CheckCloseAsync(Application application,List<object> checks)
    {
        using var fixture=new Owned(application);var write=Pending<bool>();Task<bool>? operation=null;var token=default(CancellationToken);
        fixture.Writer=(_,_,cancellation,_)=>{token=cancellation;return write.Task.WaitAsync(cancellation);};
        fixture.Card.SetExpanded(true);Invoke(fixture.Card,"ShowAll");var list=Get<Window>(fixture.Card,"listWindow");var listClosed=false;list.Closed+=(_,_)=>listClosed=true;
        try {
            operation=fixture.Read();var before=fixture.Card.Latest;
            fixture.Card.Close();await Turns();
            Require(token.IsCancellationRequested && fixture.Card.IsClosed && listClosed,"Actual disposal left its owned write or full list alive.");
            Require(!await operation && fixture.WriteCalls==1 && fixture.Reads==0 && ReferenceEquals(fixture.Card.Latest,before)
                && !fixture.Card.IsVisible && fixture.Card.PendingInboxRead is null,"Disposed owner accepted a late outcome, refetched or remained pending.");
            checks.Add(new{name="attention.read.closeCancels",actualWindowCloseAndWriteCts=true,ownFullListClosed=true,
                lateDisposedResultNotApplied=true,noRetryOrRefresh=true});
        } finally {write.TrySetResult(true);if(operation is not null)await Settle(operation);}
    }

    private static async Task CheckCapturedChoiceAsync(Application application,List<object> checks)
    {
        using var fixture=new Owned(application);var item=fixture.Selected;
        var forged=AttentionChoices.Alternate(item) with{InboxRead=Target with{AccountID="account-b",Endpoint=OtherOrigin}};
        Require(!await fixture.Controller.ExecuteAttentionChoiceAsync(item,forged)
            && !await fixture.Controller.ExecuteAttentionChoiceAsync(item,AttentionChoices.Alternate(item) with{Enabled=false}),"Dispatch accepted an altered displayed choice.");
        var none=item with{Action=new("none"),Enabled=false,InboxRead=null};
        Require(!await fixture.Controller.ExecuteAttentionChoiceAsync(none,AttentionChoices.Primary(none))
            && fixture.WriteCalls==0 && fixture.TokenReads==0 && fixture.Reads==0 && !fixture.Card.IsMutating,
            "Disabled no-action row performed a write or changed its owner.");
        Require(fixture.WorkerSessions==0,"Owned fixtures unexpectedly acquired a real worker.");
        checks.Add(new{name="attention.read.capturedChoice",forgedAndDisabledChoicesRefused=true,noPrimaryNoneDispatch=true,
            noCredentialWriteOrWorker=true});
    }

    private sealed class Owned : IDisposable
    {
        private readonly string path=Path.Combine(Path.GetTempPath(),"devdeck-attention-read-"+Guid.NewGuid().ToString("N")+".json");
        internal readonly SettingsStore Store;
        internal readonly DeckController Controller;
        internal readonly RemoteCard Card,Sibling,Pulls;
        internal readonly RemoteSnapshot Initial,After;
        internal Func<CancellationToken,Task<RemoteSnapshot>>? Reader;
        internal Func<RemoteCardSettings,RemoteRequest,CancellationToken,Action<string>?,Task>? Writer;
        internal int TokenReads,WriteCalls,Reads;
        internal RemoteRequest? LastWrite;
        internal AttentionItem Selected=>Initial.Signals!.Items.Single(item=>item.InboxRead==Target);
        internal int WorkerSessions=>Get<Dictionary<(string,bool),WorkerClient>>(Controller,"workerSessions").Count;

        internal Owned(Application application)
        {
            Store=new(path);Store.Save(Settings());Controller=new(application,Store,live:false);
            Initial=Inbox(CardID);After=Initial with{Rows=Initial.Rows.Where(row=>row.AccountID!="account-a" || row.Id!="42").ToArray(),Total=3,ActionableCount=3,
                Signals=Initial.Signals! with{Items=Initial.Signals.Items.Where(item=>item.InboxRead!=Target).ToArray()}};
            Card=new(Controller,Controller.Settings.RemoteCardList.Single(card=>card.Id==CardID),live:false,snapshotReader:token=>{
                Reads++;if(Reader is{} read)return read(token);Controller.ObserveAttention(After.Signals);return Task.FromResult(After);
            });
            Sibling=new(Controller,Controller.Settings.RemoteCardList.Single(card=>card.Id==SiblingID),live:false);
            Pulls=new(Controller,Controller.Settings.RemoteCardList.Single(card=>card.Id==PullsID),live:false);
            foreach(var card in new[]{Card,Sibling,Pulls}){
                Get<List<RemoteCard>>(Controller,"remoteCards").Add(card);
                Get<Dictionary<string,RemoteCardSettings>>(Controller,"remoteConfigurations")[card.CardID]=card.Configuration;
                card.SetDeckVisible(true);
            }
            var prSignal=new AttentionItem("review:own-pr","github:review:"+ReviewURL,"waiting","github","Independent PR representative","Original PR",1000,new("open",ReviewURL,"github","account-a"),true,false);
            var pr=new RemoteSnapshot(PullsID,"pullRequests",1,0,null,[new("pr42","account-a","Independent PR","example/repo",ReviewURL,"attention","review requested",true)],[],false,
                Signals:new(PullsID,[prSignal],[]));
            var sibling=Inbox(SiblingID);
            Card.ApplySnapshot(Initial);Sibling.ApplySnapshot(sibling);Pulls.ApplySnapshot(pr);
            Controller.ObserveAttention(pr.Signals);Controller.ObserveAttention(Initial.Signals);Controller.ObserveAttention(sibling.Signals);
            // Distinct owned sentinels expose a click-time rewrite even within one wall-clock second.
            Get<TextBlock>(Card,"timestamp").Text="01:02:03";
            typeof(DeckController).GetField("lastCheckedAt",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(Controller,DateTimeOffset.FromUnixTimeSeconds(1000));
            Controller.InboxTokenReader=account=>{TokenReads++;return "owned synthetic credential";};
            Controller.InboxWriteSender=(configuration,request,token,progress)=>{
                WriteCalls++;LastWrite=request;
                return Writer?.Invoke(configuration,request,token,progress)??Task.CompletedTask;
            };
        }
        internal Task<bool> Read()=>Controller.ExecuteAttentionChoiceAsync(Selected,AttentionChoices.Alternate(Selected));
        internal AttentionItem[] Scope(string scope)=>Get<Dictionary<string,AttentionItem[]>>(Get<AttentionTracker>(Controller,"attention"),"signals")[scope];
        internal void CommitState(DeckSettings settings){Store.Save(settings);typeof(DeckController).GetProperty("Settings",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(Controller,settings);}
        public void Dispose(){Card.Close();Sibling.Close();Pulls.Close();Controller.CloseViews();foreach(var file in new[]{path,path+".bak"})if(File.Exists(file))File.Delete(file);Text.Use("en");}
    }

    private static DeckSettings Settings()=>new(1,[new(Distribution,"/owned/runtime"),new("Other Linux","/owned/runtime")],[],
        Accounts:[new("account-a","Owned A","github",Origin,[],[]),new("account-b","Owned B","github",OtherOrigin,[],[])],
        RemoteCards:[new(PullsID,"Owned pulls","pullRequests",Distribution,["account-a"],X:1000,Y:80),
            new(CardID,"Owned inbox","inbox",Distribution,["account-a","account-b"],X:64,Y:80),
            new("owned.actions","Actions","actions",Distribution,["account-a"],Enabled:false),
            new("owned.merges","Merges","mergeRequests",Distribution,[],Enabled:false),
            new(SiblingID,"Sibling inbox","inbox",Distribution,["account-a","account-b"],X:520,Y:80)],Language:"en",Notifications:false);
    private static RemoteSnapshot Inbox(string cardID)
    {
        var rows=new RemoteRow[]{new("42","account-a","Account A same review","example/repo",ReviewURL,"attention","reviewRequested",true,UpdatedAt:1000),
            new("42","account-b","Account B same review","example/repo",ReviewURL,"attention","reviewRequested",true,UpdatedAt:1000),
            new("43","account-a","Other mention","example/other","https://example.test/other/issues/43","attention","mention",false,UpdatedAt:1000),
            new("44","account-a","URLless assignment","example/other",null,"attention","assigned",false,UpdatedAt:1000)};
        var items=rows.Select(row=>{
            var identity=InboxReadValidation.Identity(row.AccountID,row.Id);var endpoint=row.AccountID=="account-a"?Origin:OtherOrigin;
            return new AttentionItem(identity,row.Detail=="reviewRequested"?"github:review:"+row.Url:identity,"waiting","github",row.Title,"Original detail",row.UpdatedAt,
                row.Url is null?new("none"):new("open",row.Url,"github",row.AccountID),row.Url is not null,false,new(cardID,row.AccountID,row.Id,endpoint));
        }).ToArray();
        return new(cardID,"inbox",4,0,null,rows,[],false,PollIntervalSeconds:600,RepositoryCount:3,NamespaceCount:2,ActionableCount:4,Signals:new(cardID,items,[]));
    }
    private static bool Has(RemoteSnapshot snapshot,InboxReadTarget target)=>snapshot.Rows.Any(row=>row.AccountID==target.AccountID && row.Id==target.ThreadID);
    private static nint Handle(Window window)=>new WindowInteropHelper(window).Handle;
    private static TaskCompletionSource<T> Pending<T>()=>new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static T Get<T>(object source,string field)=>(T)source.GetType().GetField(field,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(source)!;
    private static void Invoke(object source,string method)=>source.GetType().GetMethod(method,BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(source,null);
    private static async Task Turns(){for(var index=0;index<3;index++)await Dispatcher.Yield(DispatcherPriority.Background);}
    private static async Task Failure(Task task,string code){try{await task;}catch(WorkerException error)when(error.Code==code){return;}throw new IOException("Expected owned write failure: "+code);}
    private static async Task Settle(Task task){try{await task.WaitAsync(TimeSpan.FromSeconds(5));}catch(Exception error)when(error is IOException or OperationCanceledException){} }
    private static void Require(bool value,string message){if(!value)throw new IOException(message);}
}
