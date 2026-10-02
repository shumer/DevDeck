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
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Actual log UI bodies with owned positive premises, independent pending work and scoped state.
/// No provider, vault, browser, WSL, global input, process lifecycle or real deck is used.
internal static class LogCompletenessTests
{
    private const string Distribution = "OwnedLogsLinux";
    private const string ProjectID = "owned.logs.primary";
    internal const string HeaderFailure = "Log header second click did not close the owned log window.";
    internal const string FollowFailure = "Log Follow did not resume after manual return to the bottom.";
    internal const string StaleFailure = "A previous log source error overwrote the current project source.";

    internal static async Task RunAsync(Application application,List<object> checks)
    {
        await HeaderAsync(application,checks);
        await FollowAsync(application,checks);
        await StaleAsync(application,checks);
    }

    internal static async Task RunRedAsync(Application application, List<object> checks, string scenario)
    {
        switch (scenario) {
            case "header-toggle": await HeaderAsync(application,checks); break;
            case "follow-return": await FollowAsync(application,checks); break;
            case "stale-error": await StaleAsync(application,checks); break;
            default: throw new IOException("Unknown isolated log completeness case.");
        }
    }

    private static async Task HeaderAsync(Application application,List<object> checks)
    {
        await using var owned = new Owned(application);
        await owned.ShowAsync(); var before = owned.Capture();
        var button = Field<Button>(owned.Card,"logButton");
        Require(button.IsLoaded && button.IsVisible && button.IsEnabled && button.ActualWidth > 0
            && Field<Dictionary<string,LogWindow>>(owned.Controller,"logWindows").Count == 0,
            "Header baseline lacks its actual loaded enabled log control/empty-window premise.");
        var width=button.ActualWidth;var height=button.ActualHeight;var content=button.Content;
        var siblingButton=Field<Button>(owned.Sibling,"logButton");
        var siblingPresentation=ButtonPresentation(siblingButton);
        RequireIndicator(button,false); RequireIndicator(siblingButton,false);
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        await UntilAsync(() => owned.Controller.IsShowingLogs(ProjectID),"Header first click did not open its owned log window.");
        var first = Field<Dictionary<string,LogWindow>>(owned.Controller,"logWindows")[ProjectID];
        var snapshot = new WorkerLogs(["Owned first log line"],"Owned exact log source",null);
        first.Apply(snapshot); await Turns();
        var handle = new WindowInteropHelper(first).Handle;
        Require(first.IsVisible && first.IsLoaded && handle != 0 && ReferenceEquals(first.Latest,snapshot)
            && first.Latest?.Source == "Owned exact log source" && Field<ProjectReference>(first,"project") == owned.Card.Reference
            && Field<Dictionary<string,LogWindow>>(owned.Controller,"logWindows").Count == 1,
            "Header first click lost its singleton/current-source/nonzero-HWND premise.");
        owned.RequireUnchanged(before);
        RequireIndicator(button,true); RequireMetrics();
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); await Turns();
        owned.RequireUnchanged(before);
        var retained = Field<Dictionary<string,LogWindow>>(owned.Controller,"logWindows");
        Require(!retained.ContainsKey(ProjectID) && !owned.Controller.IsShowingLogs(ProjectID) && !first.IsVisible,
            HeaderFailure);
        RequireIndicator(button,false);RequireMetrics();
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));await Turns();
        var reopened=retained[ProjectID];
        Require(!ReferenceEquals(first,reopened) && reopened.IsVisible && new WindowInteropHelper(reopened).Handle != 0
            && retained.Count == 1,"Header reopen did not create exactly one new owned current window.");
        RequireIndicator(button,true);RequireMetrics();owned.RequireUnchanged(before);
        await owned.Card.ShowLogsAsync();await owned.Card.ShowLogsAsync();await Turns();
        Require(ReferenceEquals(retained[ProjectID],reopened) && retained.Count == 1 && reopened.IsVisible,
            "The attention show primitive toggled or replaced an already open log window.");
        RequireIndicator(button,true);RequireMetrics();owned.RequireUnchanged(before);
        reopened.Hide();await Turns();
        Require(!reopened.IsVisible && ReferenceEquals(retained[ProjectID],reopened),"External hide discarded its owned singleton.");
        RequireIndicator(button,false);RequireMetrics();owned.RequireUnchanged(before);
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));await Turns();
        Require(reopened.IsVisible && ReferenceEquals(retained[ProjectID],reopened) && retained.Count == 1,
            "Header show replaced a hidden retained log window.");
        RequireIndicator(button,true);RequireMetrics();owned.RequireUnchanged(before);
        reopened.Close();await Turns();
        Require(!retained.ContainsKey(ProjectID) && !reopened.IsVisible,"External close retained a stale log singleton.");
        RequireIndicator(button,false);RequireMetrics();owned.RequireUnchanged(before);
        checks.Add(new { name="completeness.logs.header-toggle", actualHeaderClick=true,
            positiveFirstSingletonSourceAndHandle=true, secondClickCloses=true, reopenAndExternalVisibility=true,
            idempotentAttentionShow=true, currentAccessibleIndicatorAndStableMetrics=true, ownedGlobalsPreserved=true });

        void RequireMetrics()
        {
            Require(Math.Abs(button.ActualWidth-width)<0.01 && Math.Abs(button.ActualHeight-height)<0.01
                && ReferenceEquals(button.Content,content) && ButtonPresentation(siblingButton)==siblingPresentation,
                "Log indicator resized/replaced its header glyph or changed an unrelated hidden card.");
        }
    }

    private static async Task FollowAsync(Application application,List<object> checks)
    {
        await using var owned = new Owned(application); await owned.ShowAsync();
        var window = owned.Controller.ShowLogs(owned.Primary.Project);
        window.Apply(new(Enumerable.Range(1,250).Select(index=>"Owned log line "+index.ToString("D4")).ToArray(),"Owned scroll source",null));
        window.UpdateLayout(); await Turns();
        var lines = Field<TextBox>(window,"lines");
        var scroll = Descendants<ScrollViewer>(lines).Single(value=>value.Name == "PART_ContentHost");
        var initialLineCount = lines.LineCount;
        Require(window.IsVisible && window.IsLoaded && new WindowInteropHelper(window).Handle != 0
            && lines.IsLoaded && lines.ActualHeight > 0 && initialLineCount == 250
            && scroll.ViewportHeight > 0 && scroll.ScrollableHeight > 100 && window.IsFollowing,
            "Follow baseline lacks positive rendered content, viewport, extent and default-follow premises.");
        await UntilAsync(()=>AtEnd(scroll),"Initial owned log tail did not scroll to the end.");
        var before = owned.Capture();
        lines.ScrollToHome(); window.UpdateLayout(); await Turns();
        Require(scroll.VerticalOffset <= 1 && scroll.ScrollableHeight > 100 && !window.IsFollowing,
            "Manual upward scroll did not reach the top and turn off Follow through actual ScrollChanged.");
        lines.ScrollToEnd(); window.UpdateLayout(); await Turns();
        Require(AtEnd(scroll),"Manual downward scroll did not actually reach the current bottom.");
        var followedAtBottom = window.IsFollowing;
        window.Apply(new(Enumerable.Range(1,300).Select(index=>"Owned log line "+index.ToString("D4")).ToArray(),"Owned scroll source",null));
        window.UpdateLayout(); await Turns();
        Require(lines.LineCount == 300 && window.Latest?.Lines.Length == 300 && scroll.ScrollableHeight > 100,
            "Follow append did not positively increase the actual tail extent.");
        owned.RequireUnchanged(before);
        Require(followedAtBottom && window.IsFollowing && AtEnd(scroll),FollowFailure);
        lines.ScrollToHome();window.UpdateLayout();await Turns();
        Require(scroll.VerticalOffset<=1 && !window.IsFollowing,"Search off-intent lacks a positive prior upward scroll.");
        window.Search("Owned log line 0299");window.UpdateLayout();await Turns();
        Require(window.Selection=="Owned log line 0299" && AtEnd(scroll) && !window.IsFollowing,
            "Programmatic near-end Find reenabled Follow after selecting its actual match.");
        var offset=scroll.VerticalOffset;
        window.Apply(new(Enumerable.Range(1,350).Select(index=>"Owned log line "+index.ToString("D4")).ToArray(),"Owned scroll source",null));
        window.UpdateLayout();await Turns();
        Require(lines.LineCount==350 && !window.IsFollowing && !AtEnd(scroll) && Math.Abs(scroll.VerticalOffset-offset)<=1,
            "Programmatic tail replacement lost the off choice or its retained offset after Find.");
        var changed=owned.Primary.Project with {Path="/owned/programmatic-log-replacement",Title="Owned source replacement"};
        window.UpdateProject(changed);window.UpdateLayout();await Turns();
        Require(window.Latest is null && lines.Text.Length==0 && !window.IsFollowing,
            "Programmatic source clear turned on Follow or retained old content.");
        window.Apply(new(Enumerable.Range(1,350).Select(index=>"Owned replacement line "+index.ToString("D4")).ToArray(),"Owned replacement source",null));
        window.UpdateLayout();await Turns();
        Require(lines.LineCount==350 && scroll.VerticalOffset<=1 && !window.IsFollowing,
            "New source tail did not preserve the programmatic off choice and cleared offset.");
        var follow=Field<CheckBox>(window,"follow");
        Require(follow.IsLoaded && follow.IsVisible && follow.IsEnabled && follow.IsChecked==false,
            "Explicit Follow lacks its actual loaded visible off checkbox.");
        typeof(ToggleButton).GetMethod("OnClick",BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(follow,[]);
        window.UpdateLayout();await Turns();
        Require(window.IsFollowing && AtEnd(scroll),"Actual explicit Follow click did not enable and reach the new tail.");
        owned.RequireUnchanged(before);
        checks.Add(new { name="completeness.logs.follow-return", actualQueuedScrollChanged=true,
            initialLineCount, appendedLineCount=300, positiveUpwardOffAndManualBottom=true, appendedTailFollows=true,
            programmaticFindOffsetAndSourceClearPreserveOff=true, actualExplicitFollowClick=true, ownedGlobalsPreserved=true });
    }

    private static async Task StaleAsync(Application application,List<object> checks)
    {
        var receipt = new TaskCompletionSource<WorkerLogs?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var closeReceipt = new TaskCompletionSource<WorkerLogs?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        await using var owned = new Owned(application); await owned.ShowAsync();
        var calls = 0; ProjectReference? captured = null; CancellationToken capturedToken = default;
        var requests=new List<ProjectReference>();var tokens=new List<CancellationToken>();Task? closeRead=null;
        var fresh = new WorkerLogs(["Owned new-source line 1","Owned new-source line 2"],"Owned new current source",null,"/owned/new-log.txt");
        var currentError=new IOException("Owned current log source failed.");
        var window = new LogWindow(owned.Controller,owned.Primary.Project,live:false,logsReader:(reference,cancellation)=> {
            calls++;requests.Add(reference);tokens.Add(cancellation);
            if(calls==1){captured=reference;capturedToken=cancellation;entered.TrySetResult();return receipt.Task;}
            return calls switch { 2=>Task.FromResult<WorkerLogs?>(fresh),3=>Task.FromException<WorkerLogs?>(currentError),4=>closeReceipt.Task,
                _=>throw new IOException("Owned log fixture received an unexpected read.") };
        });
        Field<Dictionary<string,LogWindow>>(owned.Controller,"logWindows").Add(ProjectID,window);
        var polling = Field<DispatcherTimer>(window,"polling");
        try {
            window.Show(); window.Activate(); window.UpdateLayout(); await Turns();
            window.Apply(new(["Owned old-source tail"],"Owned old source",null,"/owned/old-log.txt"));
            Require(window.IsVisible && window.IsLoaded && new WindowInteropHelper(window).Handle != 0
                && WindowVisibility.CanRead(window) && window.Latest is not null && !polling.IsEnabled,
                "Stale baseline lacks visible readable owned log/current old-source/disabled-timer premises.");
            var before = owned.Capture();
            polling.Interval=TimeSpan.FromMilliseconds(20); polling.Start();
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(3)); polling.Stop();
            Require(calls == 1 && captured == owned.Primary.Project && capturedToken.CanBeCanceled
                && !capturedToken.IsCancellationRequested && Field<bool>(window,"reading") && !receipt.Task.IsCompleted,
                "Actual owned timer tick did not hold exactly one original-source read.");
            var current = owned.Primary.Project with { Distribution="OwnedOtherLogsLinux",Path="/owned/new-log-source",Title="Owned changed log" };
            window.UpdateProject(current); await Turns();
            var source = Field<TextBlock>(window,"source"); var lines = Field<TextBox>(window,"lines");
            Require(Field<ProjectReference>(window,"project") == current && window.Latest is null && lines.Text.Length == 0
                && source.Text == Text.L("card.log.reading") && Field<Button>(window,"file").Visibility == Visibility.Collapsed
                && !Field<Button>(window,"terminal").IsEnabled && !capturedToken.IsCancellationRequested,
                "Actual project replacement did not clear the old tail/source/file while retaining the admitted reader.");
            owned.RequireUnchanged(before);
            receipt.SetException(new IOException("Owned previous log source failed."));
            await UntilAsync(()=>!Field<bool>(window,"reading"),"Original owned log failure did not finish its actual read body.");
            Require(calls == 1 && !polling.IsEnabled && window.Latest is null && lines.Text.Length == 0
                && !capturedToken.IsCancellationRequested,"Old-source completion changed read count/timer/new tail/lifetime premises.");
            owned.RequireUnchanged(before);
            Require(source.Text == Text.L("card.log.reading"),StaleFailure);
            await window.RefreshAsync().WaitAsync(TimeSpan.FromSeconds(3));await Turns();
            Require(calls==2 && requests[1]==current && !tokens[1].IsCancellationRequested && ReferenceEquals(window.Latest,fresh)
                && source.Text==fresh.Source && lines.Text==string.Join(Environment.NewLine,fresh.Lines)
                && Field<Button>(window,"file").Visibility==Visibility.Visible && Field<Button>(window,"terminal").IsEnabled,
                "The actual current-reference reader did not publish its fresh tail/source/file/tool state.");
            owned.RequireUnchanged(before);
            await window.RefreshAsync().WaitAsync(TimeSpan.FromSeconds(3));await Turns();
            Require(calls==3 && requests[2]==current && !tokens[2].IsCancellationRequested && ReferenceEquals(window.Latest,fresh)
                && source.Text==Text.Failure(currentError) && lines.Text==string.Join(Environment.NewLine,fresh.Lines),
                "The failure fence suppressed a current-source error or replaced its valid cached tail.");
            owned.RequireUnchanged(before);
            closeRead=window.RefreshAsync();
            Require(calls==4 && requests[3]==current && !closeRead.IsCompleted && !tokens[3].IsCancellationRequested
                && Field<bool>(window,"reading"),"Close cancellation lacks a positively held current-source read.");
            window.Close();await Turns();
            Require(tokens[3].IsCancellationRequested && !window.IsVisible && !polling.IsEnabled,
                "Closing an owned log did not cancel only its lifetime and stop its timer.");
            closeReceipt.SetResult(new(["Owned late closed lines"],"Owned late closed source",null));
            await closeRead.WaitAsync(TimeSpan.FromSeconds(3));await Turns();
            Require(calls==4 && !Field<bool>(window,"reading") && ReferenceEquals(window.Latest,fresh)
                && source.Text==Text.Failure(currentError) && lines.Text==string.Join(Environment.NewLine,fresh.Lines),
                "Closed-window completion changed its previous validated content or kept an admitted read alive.");
            owned.RequireUnchanged(before);
            checks.Add(new { name="completeness.logs.stale-error", actualTimerTickAndReadCatch=true,
                positiveOldPendingAndNewClearedSource=true, oldExceptionIgnored=true, freshCurrentReaderPublishes=true,
                currentErrorsRemainVisible=true, closedLifetimeCancelledAndLateReplyIgnored=true, ownedGlobalsPreserved=true });
        } finally {
            polling.Stop(); receipt.TrySetResult(null);closeReceipt.TrySetResult(null);
            if(closeRead is not null)await closeRead.WaitAsync(TimeSpan.FromSeconds(3));
            await UntilAsync(()=>!Field<bool>(window,"reading"),"Owned stale-log reader did not finish during teardown.");
        }
    }

    private sealed class Owned : IAsyncDisposable
    {
        internal readonly SettingsStore Store;
        internal readonly DeckController Controller;
        internal readonly CardSettings Primary;
        internal readonly ProjectCard Card, Sibling;
        private readonly SemaphoreSlim actions;
        private readonly TaskCompletionSource<WorkerResponse> siblingReceipt = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private Task? siblingRead;
        private CancellationToken siblingToken;
        private bool held;

        internal Owned(Application application)
        {
            Store=new(Path.Combine(Path.GetTempPath(),"devdeck-completeness-logs-"+Guid.NewGuid().ToString("N")+".json"));
            Primary=new(new(ProjectID,Distribution,"local","/owned/logs-primary",StartCommand:"owned-never-run",HoldsProcess:true),"Owned logs primary");
            var sibling=new CardSettings(new("owned.logs.sibling",Distribution,"local","/owned/logs-sibling",StartCommand:"owned-never-run",HoldsProcess:true),"Owned logs sibling",Enabled:false);
            var seed=new DeckSettings(1,[new(Distribution,"/owned/logs-runtime",Text.Language)],[Primary,sibling],Language:Text.Language,
                Notifications:true,SeenAlerts:["owned.logs.seen"],RemoteCards:RemoteCardCatalog.All.Select(descriptor=>
                    new RemoteCardSettings(descriptor.Id,descriptor.Kind,descriptor.Kind,Distribution,[],Enabled:false)).ToArray());
            Store.Save(seed); Store.Save(seed);
            Controller=new(application,Store,live:false,settingsCheckWorkerFactory:_=>throw new IOException("Owned logs must not acquire a real worker."));
            Card=new(Controller,Primary,live:false,phoneAddress:()=>null,copyPhoneLink:_=>{},statusReader:(_,_)=>Task.FromResult(Response(ProjectID)));
            Sibling=new(Controller,sibling,live:false,phoneAddress:()=>null,copyPhoneLink:_=>{},statusReader:(_,cancellation)=> {
                siblingToken=cancellation;return siblingReceipt.Task;
            });
            Field<List<ProjectCard>>(Controller,"cards").AddRange([Card,Sibling]);
            var configurations=Field<Dictionary<string,CardSettings>>(Controller,"localConfigurations");
            configurations.Add(ProjectID,Primary);configurations.Add(sibling.Project.Id,sibling);
            Card.ApplySnapshot(Status(ProjectID));Sibling.ApplySnapshot(Status(sibling.Project.Id));
            new WindowInteropHelper(Sibling).EnsureHandle(); SeedGlobals();
            actions=Field<SemaphoreSlim>(Controller,"actions");
        }

        internal async Task ShowAsync()
        {
            Card.Show();Card.UpdateLayout();await Turns();
            Require(Card.IsVisible && Card.IsLoaded && new WindowInteropHelper(Card).Handle != 0
                && Card.Latest?.State == "running", "Owned log baseline requires its actual rendered project card.");
            Require(await actions.WaitAsync(TimeSpan.FromSeconds(3)),"Owned log action gate was already held before fixture admission.");held=true;
            Require(actions.CurrentCount == 0,"Owned log baseline did not positively hold its action gate.");
            siblingRead=Sibling.RefreshAsync();Sibling.SetDeckVisible(false);await Turns();
            Require(siblingRead is { IsCompleted:false } && siblingToken.CanBeCanceled && !siblingToken.IsCancellationRequested
                && !Sibling.IsVisible && new WindowInteropHelper(Sibling).Handle != 0 && Sibling.Latest?.State == "running",
                "Owned log baseline lacks its hidden cached sibling HWND/pending uncancelled status reader.");
            Require(Controller.LastCheckedAt is not null && Field<AttentionTracker>(Controller,"attention").SignalItems.Length > 0
                && Field<NotificationLedger>(Controller,"notifications").Seen.Length > 0
                && Field<IList>(Controller,"pendingAlerts").Count > 0
                && ((IEnumerable)Field<object>(Controller,"deliveries")).Cast<object>().Any()
                && File.ReadAllBytes(Store.Path+".bak").Length > 0,"Owned globals/Seen/queue/clock/preexisting backup must be positive.");
            RequireIsolation();
        }

        private void SeedGlobals()
        {
            Field<AttentionTracker>(Controller,"attention").Observe(new AttentionSnapshot("local:"+Distribution,
                [new("owned.logs.item","owned.logs.key","waiting","github","Owned retained item","Owned retained facts",1000,new("none"),false,false)],[]));
            var alert=new DeckAlert("owned.logs.pending","cantCheck",ProjectID,"Owned retained alert","Owned detail","Owned body","",new("menu"),true);
            var scopedType=typeof(DeckController).GetNestedType("ScopedAlert",BindingFlags.NonPublic)!;
            var scoped=Activator.CreateInstance(scopedType,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,null,["local:"+Distribution,alert],null)!;
            Field<IList>(Controller,"pendingAlerts").Add(scoped);
            var sources=Array.CreateInstance(scopedType,1);sources.SetValue(scoped,0);
            var deliveryType=typeof(DeckController).GetNestedType("Delivery",BindingFlags.NonPublic)!;
            var delivery=Activator.CreateInstance(deliveryType,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,null,[sources,false],null)!;
            Field<object>(Controller,"deliveries").GetType().GetMethod("Enqueue")!.Invoke(Field<object>(Controller,"deliveries"),[delivery]);
            SetField(Controller,"activeDelivery",delivery);SetField(Controller,"activeAlert",alert);SetField(Controller,"lastCheckedAt",DateTimeOffset.FromUnixTimeSeconds(1000));
        }

        internal string Capture()=>JsonSerializer.Serialize(new {
            settings=Controller.Settings,file=Convert.ToHexString(File.ReadAllBytes(Store.Path)),backup=Convert.ToHexString(File.ReadAllBytes(Store.Path+".bak")),
            clock=Controller.LastCheckedAt,signals=Field<AttentionTracker>(Controller,"attention").SignalItems,
            seen=Field<NotificationLedger>(Controller,"notifications").Seen,pending=Field<IList>(Controller,"pendingAlerts").Cast<object>().ToArray(),
            queue=((IEnumerable)Field<object>(Controller,"deliveries")).Cast<object>().ToArray(),active=Field<object?>(Controller,"activeDelivery"),alert=Field<DeckAlert?>(Controller,"activeAlert"),
            timers=new[]{"localPolling","sharedPolling","notificationBatch","notificationExpiry","nextNotification"}.Select(name=>Field<DispatcherTimer>(Controller,name).IsEnabled).ToArray(),
            primaryHandle=new WindowInteropHelper(Card).Handle.ToInt64(),primaryStatus=Card.Latest,
            siblingHandle=new WindowInteropHelper(Sibling).Handle.ToInt64(),siblingStatus=Sibling.Latest,siblingHidden=!Sibling.IsVisible,
            primaryConfiguration=Card.Reference,siblingConfiguration=Sibling.Reference,gate=actions.CurrentCount
        },WorkerProtocol.Json);

        internal void RequireUnchanged(string before)
        {
            Require(Capture() == before && siblingRead is { IsCompleted:false } && !siblingToken.IsCancellationRequested
                && actions.CurrentCount == 0,"Log UI changed owned settings/backup/globals/queue/clock/hidden sibling/read/gate.");
            RequireIsolation();
        }
        private void RequireIsolation()
        {
            var managers=typeof(DeckController).GetFields(BindingFlags.Instance|BindingFlags.NonPublic).Where(field=>field.FieldType == typeof(WorkerManager));
            var count=managers.Sum(field=>((IDictionary)typeof(WorkerManager).GetField("workers",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(field.GetValue(Controller))!).Count);
            Require(count == 0 && !Controller.LocalPollEnabled && !Controller.SharedPollEnabled && Field<object?>(Controller,"tray") is null,
                "Owned log baseline acquired a worker/polling loop/actual tray.");
        }
        public async ValueTask DisposeAsync()
        {
            if(held){held=false;actions.Release();}
            siblingReceipt.TrySetResult(Response("owned.logs.sibling"));
            try { if(siblingRead is not null)await siblingRead.WaitAsync(TimeSpan.FromSeconds(5)); }
            finally {
                Controller.CloseViews();
                foreach(var manager in typeof(DeckController).GetFields(BindingFlags.Instance|BindingFlags.NonPublic).Where(field=>field.FieldType == typeof(WorkerManager))
                    .Select(field=>(WorkerManager)field.GetValue(Controller)!))await manager.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(5));
                foreach(var file in new[]{Store.Path,Store.Path+".bak"})if(File.Exists(file))File.Delete(file);
            }
        }
    }

    private static ProjectStatus Status(string id)=>new(id,"running","owned.logs.branch","http://localhost:54321",null,null);
    private static WorkerResponse Response(string id)=>new(1,"owned-log-status",Distribution,null,Status(id),null,null);
    private static bool AtEnd(ScrollViewer scroll)=>scroll.VerticalOffset >= scroll.ScrollableHeight-1;
    private static System.Windows.Shapes.Path LogIcon(Button button)=>(System.Windows.Shapes.Path)((Panel)button.Content).Children[0];
    private static void RequireIndicator(Button button,bool active)
    {
        var expected=Text.L(active?"menu.card.hideLog":"menu.card.showLog");
        var tint=active?CardTheme.Blue:CardTheme.Ink;
        Require(button.ToolTip as string==expected && System.Windows.Automation.AutomationProperties.GetName(button)==expected
            && ReferenceEquals(button.Foreground,tint) && ReferenceEquals(LogIcon(button).Stroke,tint)
            && button.Background is SolidColorBrush background && (active?background.Color.A>0:background.Color.A==0)
            && button.BorderBrush is SolidColorBrush border && (active?border.Color.A>0:border.Color.A==0),
            "Log visibility did not reconcile its current accessible name, tooltip, icon, foreground and active surface.");
    }
    private static string ButtonPresentation(Button button)=>JsonSerializer.Serialize(new {
        name=System.Windows.Automation.AutomationProperties.GetName(button),tooltip=button.ToolTip as string,
        foreground=button.Foreground.ToString(),icon=LogIcon(button).Stroke.ToString(),
        background=button.Background.ToString(),border=button.BorderBrush.ToString(),fontWeight=button.FontWeight.ToString(),
        button.Width,button.Height
    },WorkerProtocol.Json);
    private static T Field<T>(object owner,string name)=>(T)owner.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(owner)!;
    private static void SetField(object owner,string name,object? value)=>owner.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(owner,value);
    private static IEnumerable<T> Descendants<T>(DependencyObject root)where T:DependencyObject
    {
        if(root is T item)yield return item;
        for(var index=0;index<VisualTreeHelper.GetChildrenCount(root);index++)foreach(var child in Descendants<T>(VisualTreeHelper.GetChild(root,index)))yield return child;
    }
    private static async Task Turns(){for(var turn=0;turn<3;turn++)await Dispatcher.Yield(DispatcherPriority.Background);}
    private static async Task UntilAsync(Func<bool> ready,string failure)
    {
        var deadline=DateTime.UtcNow.AddSeconds(3);
        while(!ready() && DateTime.UtcNow < deadline){await Turns();await Task.Delay(10);}
        Require(ready(),failure);
    }
    private static void Require(bool value,string message){if(!value)throw new IOException(message);}
}
