using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Owned fixture windows/files and fake reads only. No Git, terminal, account or provider calls.
internal static class WorkInFlightViewTests
{
    internal static async Task RunAsync(Application application,List<object> checks)
    {
        var language=Text.Language;
        try {
            foreach (var locale in DevDeck.Windows.Core.Localization.Languages) {
                Text.Use(locale); await ScenesAsync(application,locale,checks); await SettingsAsync(application,locale,checks);
            }
            Text.Use("en"); await LifetimeAsync(application,checks);
        } finally { Text.Use(language); }
    }
    private static async Task ScenesAsync(Application application,string locale,List<object> checks)
    {
        using (var fixture=new Fixture(application,locale,folders:0)) {
            var reads=0; var card=fixture.Card(_=>{ reads++; return Task.FromResult(new WorkInFlightSnapshot([],0,10)); }); card.Show(); card.UpdateLayout();
            Require(Get<TextBlock>(card,"state").Text==Text.L("windows.connecting"),"An unchecked WIF owner initially claims all clean.");
            await card.RefreshAsync(); card.UpdateLayout();
            Require(reads==1 && card.Latest is { SelectedCount:0,SuccessfulCount:0 } && Rows(card).Length==0
                && Get<TextBlock>(card,"state").Text.Contains(Text.L("card.wif.clean"),StringComparison.Ordinal)
                && Get<TextBlock>(card,"footer").Text==Text.LN("card.wif.watched",0)
                && Get<TextBlock>(card,"timestamp").Text!="--:--:--" && fixture.Controller.Settings.AccountList.Length==0
                && !fixture.Controller.SharedPollEnabled && !fixture.Controller.LocalPollEnabled,
                "Empty WIF is not an honest zero-watched result or starts an account/polling channel: "+locale);
            checks.Add(new { name=locale+".wif.view.empty", uncheckedDoesNotClaimClean=true, zeroWatchedNoAccount=true, noAutomaticScanTimer=true });
        }
        using (var fixture=new Fixture(application,locale)) {
            var entries=new[] { Entry(fixture,0,dirty:2,ahead:1,behind:3), Entry(fixture,1,dirty:0,ahead:2), Entry(fixture,2,dirty:7), Entry(fixture,3,dirty:4) };
            var card=fixture.Card(); card.Show(); card.ApplySnapshot(new(entries,4,20)); card.UpdateLayout();
            var projection=CheckoutPresentation.Project(entries); var rows=Rows(card); var first=(CheckoutEntry)rows[0].Tag;
            Require(rows.Length==3 && rows.Select(row=>(CheckoutEntry)row.Tag).SequenceEqual(CheckoutPresentation.CardRows(projection,false))
                && Get<TextBlock>(card,"verdict").Text==Text.L("card.wif.unpushed",2)
                && Get<TextBlock>(card,"footer").Text==Text.LN("card.wif.watched",4)
                && Get<Button>(card,"expand").IsVisible && AutomationProperties.GetName(rows[0]).Contains(CheckoutWords.Summary(first.State!,Text.Resources),StringComparison.Ordinal),
                "WIF first-three/global urgency/count/footer/summary projection is wrong: "+locale);
            rows[0].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Require(fixture.Opened.SequenceEqual(new[] { first.Target }) && !fixture.Controller.Settings.Cards.Single(card=>card.Project.Id==first.Reference.ProjectID).Enabled,
                "Whole-row terminal click loses the exact hidden source checkout/distribution: "+locale);
            var original=fixture.Controller.Settings;
            Set(fixture.Controller,"Settings",original with { Cards=original.Cards.Where(card=>card.Project.Id!=first.Reference.ProjectID).ToArray() });
            rows[0].RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); fixture.Controller.OpenCheckoutTerminal(first.Target with { Distribution="Foreign Linux" });
            Require(fixture.Opened.Count==1,"Removed/foreign WIF row launches a terminal: "+locale);
            Set(fixture.Controller,"Settings",original);
            checks.Add(new { name=locale+".wif.view.rowsAndTerminal", defaultThreeGlobalRows=true, countsAndFirstTwoFacts=true,
                actualWholeRowClickExactHiddenSource=true, removedAndForeignTargetNoOp=true, fakeTerminalOnly=true });
        }
        using (var fixture=new Fixture(application,locale)) {
            var entries=Enumerable.Range(0,13).Select(index=>Entry(fixture,index,dirty:index+1)).ToArray(); var card=fixture.Card(); card.Show();
            card.ApplySnapshot(new(entries,13,30)); card.UpdateLayout(); Get<Button>(card,"expand").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); card.UpdateLayout();
            Require(card.IsExpanded && Rows(card).Length==12 && Get<Button>(card,"expand").Content as string==Text.L("card.showLess")
                && !Descendants<Button>(card).Any(button=>AutomationProperties.GetName(button)==Text.L("windows.allItems")),
                "WIF expansion differs from the original twelve-row cap or invents a full-list window: "+locale);
            card.SetCollapsed(true); card.SetCollapsed(false); card.UpdateLayout();
            Require(card.IsExpanded && Rows(card).Length==12,"Compact/full transition loses WIF session expansion.");
            Get<Button>(card,"expand").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); card.UpdateLayout();
            Require(!card.IsExpanded && Rows(card).Length==3 && Get<Button>(card,"expand").Content as string==Text.L("card.showMore",10),
                "WIF collapse does not return to three rows and honest overflow count.");
            checks.Add(new { name=locale+".wif.view.expansion", actualExpanderThreeTwelve=true, thirteenTotalBounded=true,
                sessionExpansionSurvivesCompact=true, noFullListOrUtilityActions=true });
        }
        using (var fixture=new Fixture(application,locale)) {
            var partial=new[] { Entry(fixture,0,dirty:2), Failed(fixture,1), Entry(fixture,2,dirty:0) };
            var card=fixture.Card(); card.Show(); card.ApplySnapshot(new(partial,3,40)); card.UpdateLayout();
            Require(Rows(card).Length==1 && Get<TextBlock>(card,"diagnostic").Text==Text.L("windows.wif.partial",2,1)
                && Get<TextBlock>(card,"footer").Text==Text.LN("card.wif.watched",2),"Full WIF partial scan hides read failure/watched distinction: "+locale);
            var failed=new[] { Failed(fixture,0),Failed(fixture,1) }; card.ApplySnapshot(new(failed,2,50)); card.UpdateLayout();
            Require(Rows(card).Length==0 && Get<TextBlock>(card,"state").Text==Text.L("windows.wif.readFailed",2)
                && Get<TextBlock>(card,"footer").Text==Text.LN("card.wif.watched",0),"All-failed WIF scan claims configured work is clean: "+locale);
            card.SetCollapsed(true); card.UpdateLayout();
            Require(Get<TextBlock>(card,"foldedNote").Text==Text.L("windows.wif.readFailed",2) && card.ActualHeight<=76,
                "All-failed compact WIF hides its diagnostic or expands.");
            checks.Add(new { name=locale+".wif.view.partialAndAllFailed", partialSuccessfulWatchedAndFailureHonest=true,
                zeroSuccessfulNeverAllClean=true, compactFailureBounded=true });
        }
        using (var fixture=new Fixture(application,locale)) {
            var entry=Entry(fixture,0,dirty:123,ahead:456,behind:789);
            entry=entry with { Reference=entry.Reference with { Title="長い見出し · Очень длинный проект · "+new string('Ж',80) },
                Result=entry.Result with { State=entry.State! with { Branch="feature/長い名前/очень-длинная-ветка/"+new string('界',70) } } };
            foreach (var scale in new[] { 1d,1.5d,2d }) {
                var card=fixture.Card(); card.Show(); card.ApplySnapshot(new([entry],1,60)); card.UpdateLayout();
                var row=Rows(card).Single(); foreach (var text in Descendants<TextBlock>(card)) text.FontSize*=scale; card.UpdateLayout();
                var summary=CheckoutWords.Summary(entry.State!,Text.Resources);
                Require(summary.Split(" · ").Length==2 && !summary.Contains(Text.L("windows.wif.behind",789),StringComparison.Ordinal)
                    && AutomationProperties.GetName(row).Contains(entry.Reference.Title,StringComparison.Ordinal)
                    && AutomationProperties.GetName(row).Contains(entry.State!.Branch,StringComparison.Ordinal)
                    && AutomationProperties.GetName(row).Contains(summary,StringComparison.Ordinal)
                    && AutomationProperties.GetHelpText(row)==entry.Reference.Distribution+" · "+entry.Reference.Path
                    && row.ToolTip as string==AutomationProperties.GetName(row)
                    && Descendants<System.Windows.Shapes.Path>(row).Any(path=>path.Data.ToString()==((System.Windows.Shapes.Path)CardTheme.Icon("branch")).Data.ToString()),
                    "Long WIF row loses full accessible/tooltip target, first-two facts or existing branch glyph: "+locale);
                foreach (var text in Descendants<TextBlock>(row)) {
                    var point=text.TranslatePoint(new Point(0,0),row);
                    Require(text.TextTrimming==TextTrimming.CharacterEllipsis && text.ActualWidth>0
                        && point.X>=-1 && point.X+text.ActualWidth<=row.ActualWidth+1
                        && point.Y>=-1 && point.Y+text.ActualHeight<=row.ActualHeight+1,
                        "Long title/branch/summary is not independently bounded at enlarged font: "+locale);
                }
            }
            checks.Add(new { name=locale+".wif.view.unicodeGeometry", fullUnicodeTitleBranchAndSummaryAccessible=true,
                firstTwoFactsAndExistingGlyph=true, independentEllipsisAtThreeFontScales=true });
        }
        using (var fixture=new Fixture(application,locale)) {
            var card=fixture.Card(); card.Show(); var snapshot=new WorkInFlightSnapshot([Entry(fixture,0,dirty:2)],1,70);
            card.ApplySnapshot(snapshot); card.SetCollapsed(true); card.UpdateLayout();
            var handle=new WindowInteropHelper(card).Handle; var point=new Point(card.Left,card.Top);
            card.SetChecking(); card.UpdateLayout();
            Require(card.ActualHeight<=76 && Get<TextBlock>(card,"foldedNote").Text==Text.L("windows.wif.checking")
                && Get<TextBlock>(card,"timestamp").Text==DateTimeOffset.FromUnixTimeSeconds(70).LocalDateTime.ToString("HH:mm:ss"),
                "Compact checking enlarges WIF or manufactures a new completed pass time.");
            card.SetChecking(false); card.ApplyMode(true); card.ApplyMode(false); card.ContextMenu!.RaiseEvent(new RoutedEventArgs(ContextMenu.OpenedEvent));
            var tags=card.ContextMenu.Items.OfType<MenuItem>().Select(item=>item.Tag as string).ToArray();
            Require(tags.SequenceEqual(new[] { "header","compact","hide","settings","lock","tidy","refresh" })
                && WidgetWindow.IsExcluded(card) && new WindowInteropHelper(card).Handle==handle
                && new Point(card.Left,card.Top)==point && ReferenceEquals(card.Latest,snapshot)
                && !Get<Button>(card,"settingsButton").IsVisible && !Get<Button>(card,"refreshButton").IsVisible,
                "WIF context exposes project/account tools or mode changes replace compact native owner/cache: "+locale);
            checks.Add(new { name=locale+".wif.view.compactOwner", compactCheckingAtMost76=true, previousPassTimeRetained=true,
                exactContextNoAccountLogQrTools=true, desktopFloatingSameExcludedHwndAndPlacement=true });
        }
    }

    private static async Task SettingsAsync(Application application,string locale,List<object> checks)
    {
        using var fixture=new Fixture(application,locale,folders:1,preference:false,hiddenSources:false);
        var window=new SettingsWindow(fixture.Controller,live:true,tokenAvailable:_=>false); fixture.SettingsWindow=window; Set(fixture.Controller,"settingsWindow",window);
        await window.SelectPageAsync("cards"); window.Show(); window.Activate(); window.UpdateLayout();
        var toggle=Get<CheckBox>(window,"wifVisibility"); var compact=Get<CheckBox>(window,"wifCompact");
        Require(toggle.IsEnabled && toggle.IsChecked==false && toggle.Tag as string==CheckoutCatalog.CardID && !compact.IsEnabled,
            "Cards WIF default-off remains disabled or compact materializes a missing preference.");
        var page=window.Page.Content; var drafts=Get<Dictionary<string,string>>(window,"tokenDrafts"); drafts["owned.fixture"]="memory-only draft";
        window.Search.Text=Text.L("card.title.workInFlight"); window.Search.Focus(); window.Search.Select(1,2);
        await Dispatcher.Yield(DispatcherPriority.Background);
        Require(window.Search.IsKeyboardFocused && window.Navigation.Items.OfType<ListBoxItem>().Any(item=>item.IsSelected),
            "WIF localized search does not retain/find the Cards sidebar entry.");
        var sibling=new AttentionItem("owned-sibling","owned-sibling","needsFixing","project","Owned sibling signal","Owned fixture",1,new("showCard",CardID:"source-0"),true,false);
        fixture.Controller.ObserveAttention(new("local:Test One",[sibling],[]));
        var clock=fixture.Controller.LastCheckedAt; var before=fixture.Controller.Settings;
        Require(clock is not null && Get<AttentionTracker>(fixture.Controller,"attention").SignalItems.Any(item=>item.Id==sibling.Id),
            "WIF settings fixture must start with a real nonempty sibling attention scope and check time.");
        var gate=Get<SemaphoreSlim>(fixture.Controller,"actions"); await gate.WaitAsync();
        try {
            toggle.IsChecked=true; toggle.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
            Require(fixture.Controller.WorkInFlightActive && fixture.Store.Load().WorkInFlight?.Enabled==true && compact.IsEnabled
                && fixture.Controller.WorkInFlightView is { IsVisible:true } && fixture.Controller.Settings.AccountList.Length==0,
                "Actual Cards WIF toggle waits for unrelated action gate or needs an account.");
            var owner=fixture.Controller.WorkInFlightView!; var handle=new WindowInteropHelper(owner).Handle;
            compact.IsChecked=true; compact.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent)); owner.UpdateLayout();
            Require(fixture.Store.Load().WorkInFlight?.Collapsed==true && owner.ActualHeight<=76,"WIF compact toggle does not use precise existing owner.");
            await fixture.Controller.SetWIFVisibleAsync(false);
            var preserved=new Dictionary<string,bool> {
                ["visibilityFalse"]=toggle.IsChecked==false, ["compactTrue"]=compact.IsChecked==true, ["compactEnabled"]=compact.IsEnabled,
                ["ownerHidden"]=!owner.IsVisible, ["sameOwner"]=ReferenceEquals(owner,fixture.Controller.WorkInFlightView),
                ["sameHwnd"]=new WindowInteropHelper(owner).Handle==handle, ["samePage"]=ReferenceEquals(page,window.Page.Content),
                ["cardsSelected"]=window.SelectedPage=="cards", ["searchFocused"]=window.Search.IsKeyboardFocused,
                ["cursorStart"]=window.Search.SelectionStart==1, ["cursorLength"]=window.Search.SelectionLength==2,
                ["tokenDraft"]=drafts["owned.fixture"]=="memory-only draft", ["sameClock"]=fixture.Controller.LastCheckedAt==clock,
                ["sameOutsidePreference"]=SameOutsidePreference(before,fixture.Store.Load()),
                ["siblingAttention"]=Get<AttentionTracker>(fixture.Controller,"attention").SignalItems.Any(item=>item.Id==sibling.Id),
                ["sharedTimerStopped"]=!fixture.Controller.SharedPollEnabled, ["localTimerStopped"]=!fixture.Controller.LocalPollEnabled
            };
            Require(preserved.Values.All(value=>value),"External WIF hide/reconciliation discards Cards search/focus/drafts, owner or unrelated settings/clock: "
                +locale+" "+JsonSerializer.Serialize(preserved));
        } finally { gate.Release(); }
        checks.Add(new { name=locale+".wif.settings.precise", actualToggleNoAccountOrLifecycleGate=true, compactSameRetainedOwner=true,
            localizedSidebarSearchAndExternalReconcileInPlace=true, draftCursorClockAndUnrelatedSettingsRetained=true, noActualWorkerTimer=true });
    }

    private static async Task LifetimeAsync(Application application,List<object> checks)
    {
        using (var fixture=new Fixture(application,"en")) {
            var first=Pending<WorkInFlightSnapshot>(); var second=Pending<WorkInFlightSnapshot>(); var reads=0; var token=default(CancellationToken);
            var card=fixture.Card(cancellation=>{ token=cancellation; return ++reads==1 ? first.Task : second.Task; });
            card.Show(); var handle=new WindowInteropHelper(card).Handle; var read=card.RefreshAsync();
            Require(ReferenceEquals(read,card.RefreshAsync()) && reads==1,"Repeated WIF refresh duplicates a pending pass.");
            card.SetDeckVisible(false); await card.RefreshAsync(); card.Summon();
            Require(!token.IsCancellationRequested && reads==1 && !card.IsVisible,"Hidden WIF cancels a read/admit new work or summons itself.");
            var completed=new WorkInFlightSnapshot([Entry(fixture,0,dirty:2)],1,80); first.SetResult(completed); await read;
            Require(!card.IsVisible && ReferenceEquals(card.Latest,completed),"Started WIF read does not update hidden retained physical cache.");
            card.SetDeckVisible(true); read=card.RefreshAsync(); card.SetDeckVisible(false); card.SetDeckVisible(true);
            Require(reads==2 && ReferenceEquals(read,card.RefreshAsync()) && new WindowInteropHelper(card).Handle==handle && !token.IsCancellationRequested,
                "Reveal duplicates WIF read or loses its native lifetime.");
            card.Close(); second.SetResult(new([],0,90)); await read;
            Require(token.IsCancellationRequested && ReferenceEquals(card.Latest,completed) && !card.CanRefresh,"Closed WIF accepts late reply or fails own lifetime cancellation.");
            checks.Add(new { name="wif.view.pendingLifetime", pendingPassCoalesced=true, hideNoCancelOrNewRead=true,
                hiddenPhysicalCacheRetained=true, revealSameHwndAndPendingRead=true, actualCloseOwnsCancellationAndLateReplyGuard=true });
        }
        using (var fixture=new Fixture(application,"en")) {
            var source=Pending<WorkInFlightSnapshot>(); var card=fixture.Card(_=>source.Task); card.Show();
            card.ApplySnapshot(new([],2,null,Stale:true)); card.SetCollapsed(true); card.UpdateLayout();
            Require(Get<TextBlock>(card,"state").Text.StartsWith(Text.L("windows.wif.unavailable"),StringComparison.Ordinal)
                && !Get<TextBlock>(card,"foldedNote").Text.Contains(Text.L("card.wif.allClean"),StringComparison.Ordinal)
                && Get<TextBlock>(card,"foldedNote").Text.Contains(Text.L("windows.wif.stale"),StringComparison.Ordinal),
                "Interrupted WIF without any qualified checkout receipt claims configured folders are clean.");
            var previous=new WorkInFlightSnapshot([Entry(fixture,0,dirty:2)],1,100); card.ApplySnapshot(previous); card.SetCollapsed(true);
            var read=card.RefreshAsync(); card.SetDeckVisible(false); source.SetException(new IOException("Owned WIF transport unavailable")); await read; card.UpdateLayout();
            Require(!card.IsVisible && card.Latest is { Stale:true,Checking:false,CheckedAt:100 } && card.Latest.Entries.SequenceEqual(previous.Entries)
                && Get<TextBlock>(card,"foldedNote").Text.Contains(Text.L("windows.wif.stale"),StringComparison.Ordinal) && card.ActualHeight<=76,
                "Hidden WIF read failure drops previous cache/time or compact state silently looks freshly clean.");
            source=Pending<WorkInFlightSnapshot>(); card.SetDeckVisible(true); read=card.RefreshAsync();
            var fresh=new WorkInFlightSnapshot([Entry(fixture,1,dirty:3)],1,110); source.SetResult(fresh); await read;
            Require(ReferenceEquals(card.Latest,fresh) && !Get<TextBlock>(card,"foldedNote").Text.Contains(Text.L("windows.wif.stale"),StringComparison.Ordinal),
                "Fresh WIF scan does not recover from retained incomplete/failure state.");
            checks.Add(new { name="wif.view.hiddenFailureRecovery", noQualifiedReceiptNeverClean=true, qualifiedCacheTimeRetainedAndMarkedStale=true, compactFailureHonest=true, freshReadRecovers=true });
        }
    }
    private sealed class Fixture : IDisposable
    {
        private readonly string path=Path.Combine(Path.GetTempPath(),"devdeck-wif-view-"+Guid.NewGuid().ToString("N")+".json");
        private readonly List<WorkInFlightCard> owners=[];
        internal DeckController Controller { get; }
        internal SettingsStore Store { get; }
        internal SettingsWindow? SettingsWindow;
        internal List<CheckoutTarget> Opened { get; }=[];
        internal Fixture(Application application,string locale,int folders=13,bool preference=true,bool hiddenSources=true)
        {
            Store=new(path);
            var cards=Enumerable.Range(0,folders).Select(index=>new CardSettings(new("source-"+index,index%2==0 ? "Test One" : "Test Two",
                index%3==0 ? "arc" : index%3==1 ? "ddev" : "local","/owned/checkout "+index),"Project "+index,Enabled:!hiddenSources)).ToArray();
            Store.Save(new(1,[new("Test One","/owned/fake-runtime"),new("Test Two","/owned/fake-runtime")],cards,
                Language:locale,Notifications:false,SeenAlerts:["owned-seen"],WorkInFlight:preference ? new(true,64,80) : null));
            Controller=new(application,Store,live:false,checkoutEndpointFactory:_=>throw new IOException("Unexpected owned fixture checkout worker."),
                checkoutTerminalOpener:target=>Opened.Add(target));
        }
        internal WorkInFlightCard Card(Func<CancellationToken,Task<WorkInFlightSnapshot>>? reader=null)
        {
            var card=new WorkInFlightCard(Controller,Controller.Settings.WorkInFlight ?? new(),live:false,
                snapshotReader:reader ?? (_=>Task.FromResult(new WorkInFlightSnapshot([],0,10))));
            owners.Add(card); return card;
        }
        public void Dispose()
        {
            foreach (var owner in owners) owner.Close();
            if (SettingsWindow is { } window) { if (window.Page.Content is SettingsForm form) form.Dispose(); Set(window,"allowingClose",true); window.Close(); Set(Controller,"settingsWindow",null); }
            Controller.CloseViews(); if (File.Exists(path)) File.Delete(path); if (File.Exists(path+".bak")) File.Delete(path+".bak");
        }
    }
    private static CheckoutEntry Entry(Fixture fixture,int index,int dirty=0,int ahead=0,int behind=0)
    {
        var card=fixture.Controller.Settings.Cards.Single(item=>item.Project.Id=="source-"+index);
        var reference=new CheckoutReference(card.Project.Id,card.Project.Distribution,card.Project.Path,card.Title);
        var facts=new List<CheckoutSummaryFact>(); if (dirty>0) facts.Add(new("changed",dirty)); if (ahead>0) facts.Add(new("unpushed",ahead)); if (behind>0) facts.Add(new("behind",behind));
        var state=new CheckoutState("feature/source-"+index,dirty,ahead,behind,true,ahead,ahead>0 ? 1 : null,dirty>0 || ahead>0 || behind>0,ahead>0,facts.Take(2).ToArray());
        return new(reference,new(CheckoutCatalog.CardID,"owned-pass",reference.ProjectID,reference.Path,10,state,null,[]));
    }
    private static CheckoutEntry Failed(Fixture fixture,int index)
    {
        var entry=Entry(fixture,index); return entry with { Result=entry.Result with { State=null,Failure=new("status","statusFailed") } };
    }
    private static Button[] Rows(WorkInFlightCard card)=>Get<StackPanel>(card,"rows").Children.OfType<Button>().ToArray();
    private static bool SameOutsidePreference(DeckSettings before,DeckSettings after)=>JsonSerializer.Serialize(before with { WorkInFlight=null },WorkerProtocol.Json)==JsonSerializer.Serialize(after with { WorkInFlight=null },WorkerProtocol.Json);
    private static IEnumerable<T> Descendants<T>(DependencyObject parent) where T : DependencyObject
    {
        for (var index=0;index<VisualTreeHelper.GetChildrenCount(parent);index++) {
            var child=VisualTreeHelper.GetChild(parent,index); if (child is T value) yield return value;
            foreach (var nested in Descendants<T>(child)) yield return nested;
        }
    }
    private static T Get<T>(object owner,string name)=>(T)owner.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(owner)!;
    private static void Set(object owner,string name,object? value)
    {
        var type=owner.GetType(); var property=type.GetProperty(name,BindingFlags.Instance|BindingFlags.NonPublic);
        if (property is not null) property.SetValue(owner,value); else type.GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(owner,value);
    }
    private static TaskCompletionSource<T> Pending<T>()=>new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static void Require(bool value,string message) { if (!value) throw new IOException(message); }
}
