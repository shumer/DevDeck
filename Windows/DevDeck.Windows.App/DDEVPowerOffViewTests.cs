using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Owned fake tasks, settings files and windows only; never calls WSL, Docker or the modal product entry point.
internal static class DDEVPowerOffViewTests
{
    internal static async Task RunAsync(Application application,List<object> checks)
    {
        var language=Text.Language;
        try {
            Text.Use("en"); await CardChecksAsync(application,checks);
            foreach (var locale in DevDeck.Windows.Core.Localization.Languages) {
                Text.Use(locale); await DialogChecksAsync(locale,checks);
            }
        } finally { Text.Use(language); }
    }

    private static async Task CardChecksAsync(Application application,List<object> checks)
    {
        using (var fixture=new Fixture(application)) {
            var source=Pending<WorkerResponse>(); var token=default(CancellationToken); var calls=0;
            var card=fixture.Card((_,cancellation)=>{ calls++; token=cancellation; return source.Task; });
            var initial=Status(card,"running","initial"); card.ApplySnapshot(initial); card.Show();
            var clock=fixture.Controller.LastCheckedAt; var read=card.RefreshAsync("owned-old-cycle");
            card.BeginDDEVPowerOff("group-active"); card.ReportDDEVPowerOffProgress("group-active","Owned route progress");
            await card.RefreshAsync();
            source.SetResult(Response(Status(card,"stopped","stale"),new("local:Test Linux",[],[],"ready",false))); await read;
            Require(calls==1 && !token.IsCancellationRequested && card.DDEVPowerOffBusy && !card.CanRefresh
                && ReferenceEquals(card.Latest,initial) && Get<TextBlock>(card,"detail").Text=="Owned route progress"
                && Get<TextBlock>(card,"state").Text==Text.L("windows.ddevPowerOff.progress")
                && fixture.Controller.LastCheckedAt==clock && !Get<Button>(card,"openDocker").IsEnabled,
                "Pending read replaces active group presentation/attention or group busy cancels/duplicates the read.");
            card.CompleteDDEVPowerOff("group-active",Status(card,"stopped","physical"));
            Require(card.Latest?.Branch=="physical" && !card.DDEVPowerOffBusy && card.CanRefresh,"Matching final group result did not release polling.");
            checks.Add(new { name="ddev.powerOff.view.pendingActive", sameReadNotCancelled=true, noNewReadWhileBusy=true,
                staleStatusAndAttentionDiscarded=true, matchingPhysicalResultResumesPolling=true });
        }
        using (var fixture=new Fixture(application)) {
            var source=Pending<WorkerResponse>(); var token=default(CancellationToken);
            var card=fixture.Card((_,cancellation)=>{ token=cancellation; return source.Task; }); card.Show();
            card.ApplySnapshot(Status(card,"running","initial")); var read=card.RefreshAsync();
            card.BeginDDEVPowerOff("group-final"); var final=Status(card,"stopped","physical"); card.CompleteDDEVPowerOff("group-final",final);
            var timestamp=Get<TextBlock>(card,"timestamp").Text; var detail=Get<TextBlock>(card,"detail").Text;
            source.SetResult(Response(Status(card,"running","old-read"))); await read;
            Require(!token.IsCancellationRequested && ReferenceEquals(card.Latest,final) && card.LastRefreshSucceeded
                && Get<TextBlock>(card,"timestamp").Text==timestamp && Get<TextBlock>(card,"detail").Text==detail,
                "Read that began before group completion overwrites final physical state/check time.");
            checks.Add(new { name="ddev.powerOff.view.pendingAfterFinal", finalPhysicalSnapshotAndCheckTimeRetained=true, oldReadNotCancelled=true });
        }
        using (var fixture=new Fixture(application)) {
            var source=Pending<WorkerResponse>(); var reads=0;
            var card=fixture.Card((_,_)=>reads++==0
                ? Task.FromResult(Response(new("owned-ddev","running","retained","http://localhost:8112","drupal","10.6.3")))
                : source.Task);
            card.Show(); await card.RefreshAsync(); var initial=card.Latest!;
            Require(card.LastRefreshSucceeded,"The abort fixture must begin with an actual successful injected status read.");
            var initialState=Get<TextBlock>(card,"state").Text; var initialDetail=Get<TextBlock>(card,"detail").Text;
            var timestamp=Get<TextBlock>(card,"timestamp").Text; var succeeded=card.LastRefreshSucceeded;
            var stateBrush=Get<TextBlock>(card,"state").Foreground;
            var controls=new[] { "start","stop","restart","site","phone","refreshButton" }.Select(name=>Get<Button>(card,name)).ToArray();
            var enabled=controls.Select(button=>button.IsEnabled).ToArray();
            var read=card.RefreshAsync(); card.BeginDDEVPowerOff("never-run"); card.ReportDDEVPowerOffProgress("never-run","Prepared only");
            card.CompleteDDEVPowerOff("never-run"); source.SetException(new IOException("Owned stale read failure")); await read;
            Require(ReferenceEquals(card.Latest,initial) && card.LastRefreshSucceeded==succeeded
                && Get<TextBlock>(card,"state").Text==initialState && ReferenceEquals(Get<TextBlock>(card,"state").Foreground,stateBrush)
                && Get<TextBlock>(card,"detail").Text==initialDetail && Get<TextBlock>(card,"timestamp").Text==timestamp
                && controls.Select(button=>button.IsEnabled).SequenceEqual(enabled) && !card.DDEVPowerOffBusy,
                "Never-run abort manufactures a new snapshot/check time or late read failure replaces restored presentation.");
            await card.RefreshAsync();
            Require(!card.LastRefreshSucceeded && Get<TextBlock>(card,"detail").Text.Contains("Owned stale read failure",StringComparison.Ordinal),
                "The second abort fixture must begin with a real prior refresh failure.");
            var failedState=Get<TextBlock>(card,"state").Text; var failedDetail=Get<TextBlock>(card,"detail").Text;
            var failedBrush=Get<TextBlock>(card,"state").Foreground; var failedEnabled=controls.Select(button=>button.IsEnabled).ToArray();
            source=Pending<WorkerResponse>(); read=card.RefreshAsync();
            card.BeginDDEVPowerOff("never-run-after-error"); card.CompleteDDEVPowerOff("never-run-after-error");
            source.SetResult(Response(Status(card,"stopped","old-result"))); await read;
            Require(ReferenceEquals(card.Latest,initial) && !card.LastRefreshSucceeded
                && Get<TextBlock>(card,"state").Text==failedState && ReferenceEquals(Get<TextBlock>(card,"state").Foreground,failedBrush)
                && Get<TextBlock>(card,"detail").Text==failedDetail && Get<TextBlock>(card,"timestamp").Text==timestamp
                && controls.Select(button=>button.IsEnabled).SequenceEqual(failedEnabled),
                "Never-run abort replaces a pre-existing refresh failure with manufactured healthy presentation.");
            checks.Add(new { name="ddev.powerOff.view.neverRunAbort", exactPreviousSnapshotPresentationAndEligibility=true,
                previousSuccessAndFailureBothRetained=true, checkTimeNotManufactured=true, lateFailureDiscarded=true });
        }
        using (var fixture=new Fixture(application)) {
            var card=fixture.Card(); card.ApplySnapshot(Status(card,"running","compact")); card.SetCollapsed(true); card.Show(); card.UpdateLayout();
            var handle=new WindowInteropHelper(card).Handle; var position=new Point(card.Left,card.Top);
            card.BeginDDEVPowerOff("compact-group"); card.BeginDDEVPowerOff("replacement-must-not-win");
            card.ReportDDEVPowerOffProgress("wrong-token","Wrong progress"); card.CompleteDDEVPowerOff("wrong-token",Status(card,"stopped","wrong"));
            card.CompleteDDEVPowerOff("compact-group",Status(card,"stopped","wrong-id") with { ProjectID="foreign" });
            card.UpdateLayout(); card.ContextMenu!.RaiseEvent(new RoutedEventArgs(ContextMenu.OpenedEvent));
            Require(card.DDEVPowerOffBusy && card.Latest!.State=="running" && card.ActualHeight<=76
                && new WindowInteropHelper(card).Handle==handle && new Point(card.Left,card.Top)==position
                && new[] { "start","stop","restart" }.All(name=>!Get<Button>(card,name).IsEnabled)
                && Get<Button>(card,"stop").MinWidth==0 && Get<Button>(card,"stop").ActualWidth<=40
                && Get<Button>(card,"cancel").Visibility==Visibility.Collapsed
                && !card.ContextMenu.Items.OfType<MenuItem>().Single(item=>item.Tag as string=="qr").IsEnabled,
                "Group token/identity guard fails or compact busy state expands Stop/exposes dead Cancel/QR.");
            card.SetCollapsed(false); card.SetCollapsed(true); card.UpdateLayout();
            Require(!Get<Button>(card,"stop").IsEnabled && Get<Button>(card,"stop").MinWidth==0 && card.ActualHeight<=76,
                "Compact/full transition removes group gating or enlarges lifecycle controls.");
            card.CompleteDDEVPowerOff("compact-group",Status(card,"stopped","finished"));
            checks.Add(new { name="ddev.powerOff.view.compactAndToken", noDeadCancelOrExpandedStop=true,
                wrongTokenAndProjectIDDiscarded=true, sameNativeHandleAndPosition=true, compactTransitionsRemainGated=true });
        }
        using (var fixture=new Fixture(application)) {
            var card=fixture.Card(); var initial=Status(card,"running","hidden"); card.ApplySnapshot(initial);
            card.SetCollapsed(true); card.Show(); var handle=new WindowInteropHelper(card).Handle;
            card.SetDeckVisible(false); var position=new Point(card.Left,card.Top); var persisted=File.ReadAllBytes(fixture.Path);
            card.BeginDDEVPowerOff("hidden-group"); var physical=initial with { State="stopped", SiteURL=null };
            card.CompleteDDEVPowerOff("hidden-group",physical,"Owned command diagnostic"); card.UpdateLayout();
            Require(!card.IsVisible && !card.DeckVisible && !card.CanRefresh && !card.DDEVPowerOffBusy
                && new WindowInteropHelper(card).Handle==handle && new Point(card.Left,card.Top)==position && Get<bool>(card,"collapsed")
                && ReferenceEquals(card.Latest,physical) && card.Latest?.State=="stopped" && !card.LastRefreshSucceeded
                && Get<TextBlock>(card,"versions").Text=="php 8.4 · mysql 8.0"
                && Get<TextBlock>(card,"detail").Text.Contains("Owned command diagnostic",StringComparison.Ordinal)
                && File.ReadAllBytes(fixture.Path).SequenceEqual(persisted),
                "Hidden group completion changes HWND/preferences/config, reopens the owner or discards physical state/metadata on a diagnostic.");
            checks.Add(new { name="ddev.powerOff.view.hiddenPhysicalFailure", hiddenOwnerHandlePositionAndCompactRetained=true,
                physicalStoppedStateAndVersionsRetained=true, diagnosticHonest=true, noSettingsMutation=true });
        }
        using (var fixture=new Fixture(application)) {
            var card=fixture.Card(); card.Show(); var initial=Status(card,"running","metadata"); card.ApplySnapshot(initial);
            card.BeginDDEVPowerOff("lost-result"); card.CompleteDDEVPowerOff("lost-result",failure:"Owned unavailable inventory");
            Require(card.Latest is { State:"unavailable", Branch:"metadata", Framework:"drupal", EngineVersion:"10.6.3" }
                && card.Latest.VersionsLine==initial.VersionsLine && card.Latest.RepositoryURL==initial.RepositoryURL
                && card.Latest.SiteURL is null && !card.LastRefreshSucceeded && card.CurrentPhoneLink.Issue==PhoneLinkIssue.Unavailable
                && new[] { "start","stop","restart" }.All(name=>!Get<Button>(card,name).IsEnabled),
                "Missing physical result fabricates a stopped state, drops metadata or enables runtime/QR actions.");
            card.BeginDDEVPowerOff("next-group"); card.CompleteDDEVPowerOff("lost-result",initial);
            Require(card.DDEVPowerOffBusy && card.Latest?.State=="unavailable","Old completion replaces a later group.");
            card.CompleteDDEVPowerOff("next-group",Status(card,"stopped","final")); await card.RefreshAsync();
            Require(card.Latest!.State=="running" && card.LastRefreshSucceeded && Get<Button>(card,"stop").IsEnabled,
                "Fresh owned status cannot recover from unknown group outcome.");
            checks.Add(new { name="ddev.powerOff.view.unconfirmed", honestUnavailableWithMetadata=true, runtimeAndQrDisabled=true,
                previousGroupCannotCompleteNext=true, freshStatusRecovers=true });
        }
        using (var fixture=new Fixture(application)) {
            var source=Pending<WorkerResponse>(); var token=default(CancellationToken); Action<string>? progress=null;
            var card=fixture.Card(action:(_,cancellation,report)=>{ token=cancellation; progress=report; return source.Task; });
            card.Show(); card.ApplySnapshot(Status(card,"running","normal"));
            var action=(Task)typeof(ProjectCard).GetMethod("PerformAsync",BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(card,["stop"])!;
            var actual=Get<CancellationTokenSource>(card,"operation");
            card.BeginDDEVPowerOff("overlay-with-action"); progress!("Old per-card progress"); await Dispatcher.Yield(DispatcherPriority.Background);
            Require(ReferenceEquals(actual,Get<CancellationTokenSource>(card,"operation")) && !token.IsCancellationRequested
                && Get<Button>(card,"cancel").Visibility==Visibility.Visible
                && Get<TextBlock>(card,"detail").Text!= "Old per-card progress",
                "Group overlay replaces/cancels the actual per-card CTS or accepts its queued progress.");
            card.CompleteDDEVPowerOff("overlay-with-action");
            Require(ReferenceEquals(actual,Get<CancellationTokenSource>(card,"operation")) && !token.IsCancellationRequested
                && Get<Button>(card,"cancel").Visibility==Visibility.Visible,"Never-run abort destroys actual per-card cancellation ownership.");
            source.SetResult(Response(Status(card,"stopped","action-result"))); await action;
            Require(Get<CancellationTokenSource?>(card,"operation") is null && !card.DDEVPowerOffBusy
                && card.Latest?.State=="running" && card.CanRefresh && Get<Button>(card,"cancel").Visibility==Visibility.Collapsed,
                "Ordinary action result/follow-up read/lifetime differs after an aborted group overlay.");
            checks.Add(new { name="ddev.powerOff.view.actualActionOwnership", originalCtsNotReplacedOrCancelled=true,
                groupProgressOverridesQueuedPerCardProgress=true, validCancelRetained=true, ordinaryCompletionUnchanged=true });
        }
        using (var fixture=new Fixture(application)) {
            var arc=fixture.Card(kind:"arc"); arc.Show(); var initial=Status(arc,"running","arc"); arc.ApplySnapshot(initial);
            arc.BeginDDEVPowerOff("not-ddev"); arc.ReportDDEVPowerOffProgress("not-ddev","Must not replace Arc"); arc.CompleteDDEVPowerOff("not-ddev",Status(arc,"stopped","wrong"));
            Require(!arc.DDEVPowerOffBusy && ReferenceEquals(arc.Latest,initial) && arc.CanRefresh,"DDEV group changes an unrelated Arc owner.");
            var source=Pending<WorkerResponse>(); var token=default(CancellationToken);
            var ddev=fixture.Card((_,cancellation)=>{ token=cancellation; return source.Task; }); ddev.Show(); ddev.ApplySnapshot(Status(ddev,"running","closed"));
            var read=ddev.RefreshAsync(); ddev.BeginDDEVPowerOff("closing-group"); var retained=ddev.Latest; ddev.Close();
            ddev.CompleteDDEVPowerOff("closing-group",Status(ddev,"stopped","late")); source.SetResult(Response(Status(ddev,"running","late-read"))); await read;
            Require(token.IsCancellationRequested && !ddev.CanRefresh && ReferenceEquals(ddev.Latest,retained),
                "Actual disposal no longer cancels its own lifetime or late group/read result repaints it.");
            checks.Add(new { name="ddev.powerOff.view.unrelatedAndClosed", arcOwnerUnaffected=true, actualCloseOwnsLifetimeCancellation=true, lateClosedResultsIgnored=true });
        }
    }

    private static async Task DialogChecksAsync(string locale,List<object> checks)
    {
        using (var owned=new DialogScope()) {
            var dialog=owned.Dialog; dialog.ConfirmButton.ApplyTemplate(); dialog.CancelButton.ApplyTemplate();
            Require(dialog.Title==Text.L("menu.ddev.confirm.title") && dialog.Heading.Text==dialog.Title
                && dialog.Detail.Text==Text.L("windows.ddevPowerOff.scope") && dialog.Detail.Text!="windows.ddevPowerOff.scope"
                && dialog.Scope.Text==Text.L("menu.ddev.powerOff.tooltip")
                && dialog.Routes.Text==Text.L("windows.ddevPowerOff.routes","Ubuntu-24.04, Debian")
                && AutomationProperties.GetName(dialog)==dialog.Title && AutomationProperties.GetHelpText(dialog).Contains(dialog.Detail.Text,StringComparison.Ordinal)
                && AutomationProperties.GetHelpText(dialog.ConfirmButton).Contains(dialog.Routes.Text,StringComparison.Ordinal)
                && AutomationProperties.GetHelpText(dialog.ConfirmButton).Contains(dialog.Detail.Text,StringComparison.Ordinal)
                && AutomationProperties.GetName(dialog.ConfirmButton)==Text.L("button.powerOff")
                && AutomationProperties.GetName(dialog.CancelButton)==Text.L("button.cancel")
                && dialog.CancelButton.IsDefault && dialog.CancelButton.IsCancel && !dialog.ConfirmButton.IsDefault
                && ReferenceEquals(dialog.Resources[typeof(Button)],SettingsStyles.ButtonStyle)
                && dialog.ConfirmButton.Template.FindName("frame",dialog.ConfirmButton) is Border confirm && confirm.CornerRadius==new CornerRadius(6)
                && dialog.CancelButton.Template.FindName("frame",dialog.CancelButton) is Border cancel && cancel.CornerRadius==new CornerRadius(6),
                "DDEV confirmation loses localized global scope/routes/accessibility/default Cancel or shared rounded templates: "+locale);
            checks.Add(new { name=locale+".ddev.powerOff.dialog.presentation", originalTitleAndExplicitConnectedDockerScopeRoutes=true,
                accessibleScopeAndActions=true, cancelDefault=true, exactSharedRoundedFallback=true });
        }
        using (var owned=new DialogScope()) {
            var dialog=owned.Dialog; dialog.Show(); dialog.Activate(); dialog.UpdateLayout(); await Dispatcher.Yield(DispatcherPriority.Background);
            Require(dialog.CancelButton.IsKeyboardFocused,"DDEV confirmation does not initially focus Cancel: "+locale);
            dialog.ConfirmButton.Focus(); var args=RaiseKey(dialog,Key.Return);
            Require(args.Handled && !dialog.WasConfirmed && !dialog.IsVisible,"Enter while confirmation owns focus powers off: "+locale);
            checks.Add(new { name=locale+".ddev.powerOff.dialog.enter", cancelInitiallyFocused=true, returnFromConfirmCancels=true });
        }
        using (var owned=new DialogScope()) {
            var dialog=owned.Dialog; dialog.Show(); dialog.UpdateLayout(); dialog.ConfirmButton.Focus(); var args=RaiseKey(dialog,Key.Escape);
            Require(args.Handled && !dialog.WasConfirmed && !dialog.IsVisible,"Escape confirms or keeps the DDEV prompt open: "+locale);
            using var cancelled=new DialogScope(); cancelled.Dialog.Show(); cancelled.Dialog.CancelButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Require(!cancelled.Dialog.WasConfirmed && !cancelled.Dialog.IsVisible,"Explicit Cancel confirms DDEV poweroff: "+locale);
            using var closed=new DialogScope(); closed.Dialog.Show(); closed.Dialog.Close();
            Require(!closed.Dialog.WasConfirmed,"Closing the DDEV prompt produces confirmation: "+locale);
            checks.Add(new { name=locale+".ddev.powerOff.dialog.cancel", escapeCancelAndWindowCloseAllFalse=true });
        }
        using (var owned=new DialogScope()) {
            var dialog=owned.Dialog; dialog.Show(); dialog.UpdateLayout(); dialog.ConfirmButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Require(dialog.WasConfirmed && !dialog.IsVisible,"Explicit Power off click does not return confirmation: "+locale);
            checks.Add(new { name=locale+".ddev.powerOff.dialog.explicitConfirm", actualClickOnly=true, promptClosed=true, noControllerOrWorker=true });
        }
        var owner=new Window { Title="Owned DDEV dialog style fixture", Width=600, Height=350, ShowInTaskbar=false, Topmost=false };
        var style=new Style(typeof(Button)); style.Setters.Add(new Setter(Control.BorderBrushProperty,Brushes.SlateGray)); owner.Resources[typeof(Button)]=style;
        try {
            owner.Show(); owner.UpdateLayout();
            foreach (var font in new[] { 13d,19.5d,26d }) {
                using var owned=new DialogScope(owner); var dialog=owned.Dialog; dialog.FontSize=font; dialog.Show(); dialog.UpdateLayout();
                Require(dialog.Owner==owner && !dialog.Topmost && !dialog.ShowInTaskbar && dialog.WindowStyle==WindowStyle.ToolWindow
                    && dialog.ResizeMode==ResizeMode.NoResize && dialog.WindowStartupLocation==WindowStartupLocation.CenterOwner
                    && ReferenceEquals(dialog.ConfirmButton.Style,style) && ReferenceEquals(dialog.CancelButton.Style,style),
                    "DDEV confirmation ignores supplied owner/style/topmost or exposes a normal task window: "+locale);
                var scroll=(ScrollViewer)dialog.Content; var content=(FrameworkElement)scroll.Content;
                foreach (var control in new FrameworkElement[] { dialog.Heading,dialog.Detail,dialog.Scope,dialog.Routes,dialog.CancelButton,dialog.ConfirmButton }) {
                    var point=control.TranslatePoint(new Point(0,0),content);
                    Require(control.ActualWidth>0 && control.ActualHeight>0 && point.X>=-1 && point.Y>=-1
                        && point.X+control.ActualWidth<=content.ActualWidth+1 && point.Y+control.ActualHeight<=content.ActualHeight+1,
                        "DDEV confirmation clips copy/routes/buttons at an enlarged font: "+locale);
                }
                Require(scroll.HorizontalScrollBarVisibility==ScrollBarVisibility.Disabled && scroll.VerticalScrollBarVisibility==ScrollBarVisibility.Auto,
                    "DDEV confirmation cannot scroll its wrapped full scope/routes on a smaller work area.");
            }
            checks.Add(new { name=locale+".ddev.powerOff.dialog.layout", ownerTopmostAndStylesInherited=true, toolWindowNoTaskbar=true,
                allCopyAndActionsFitAtThreeFonts=true, verticalOverflowReachable=true });
        } finally { owner.Close(); }
        var names=new[] { "Ubuntu-24.04","Debian" };
        using (var owned=new DialogScope(names:names)) {
            var dialog=owned.Dialog; var routes=dialog.Routes.Text; names[0]="Changed caller draft";
            Require(dialog.AffectedNames.SequenceEqual(new[] { "Ubuntu-24.04","Debian" }) && dialog.Routes.Text==routes
                && !dialog.WasConfirmed && dialog.AffectedNames is not string[],"DDEV prompt scope follows a mutated caller array.");
            checks.Add(new { name=locale+".ddev.powerOff.dialog.frozenRoutes", distributionNamesCopiedAndReadOnly=true, laterCallerChangeCannotChangeConsent=true });
        }
    }

    private sealed class Fixture : IDisposable
    {
        internal string Path { get; }=System.IO.Path.Combine(System.IO.Path.GetTempPath(),"devdeck-poweroff-view-"+Guid.NewGuid().ToString("N")+".json");
        internal DeckController Controller { get; }
        private readonly List<ProjectCard> cards=[];
        internal Fixture(Application application)
        {
            var store=new SettingsStore(Path);
            store.Save(new(1,[new("Test Linux","/owned/fake-runtime")],
                [new(new("owned-ddev","Test Linux","ddev","/owned/fake-project"),"Owned DDEV",X:64,Y:80)],Language:"en",Notifications:false));
            Controller=new(application,store,live:false);
        }
        internal ProjectCard Card(Func<string?,CancellationToken,Task<WorkerResponse>>? reader=null,
            Func<string,CancellationToken,Action<string>,Task<WorkerResponse>>? action=null,string kind="ddev")
        {
            var settings=Controller.Settings.Cards[0] with { Project=Controller.Settings.Cards[0].Project with { Kind=kind } };
            var card=new ProjectCard(Controller,settings,live:false,phoneAddress:()=>"192.168.1.8",copyPhoneLink:_=>{},
                statusReader:reader ?? ((_,_)=>Task.FromResult(Response(new(settings.Project.Id,"running","fresh","http://localhost:8112","drupal","10.6.3")))),actionRunner:action);
            cards.Add(card); return card;
        }
        public void Dispose()
        {
            foreach (var card in cards) card.Close(); Controller.CloseViews();
            if (File.Exists(Path)) File.Delete(Path); if (File.Exists(Path+".bak")) File.Delete(Path+".bak");
        }
    }
    private sealed class DialogScope : IDisposable
    {
        internal DDEVPowerOffDialog Dialog { get; }
        internal DialogScope(Window? owner=null,string[]? names=null) => Dialog=new(names ?? ["Ubuntu-24.04","Debian"],owner);
        public void Dispose() => Dialog.Close();
    }
    private static ProjectStatus Status(ProjectCard card,string state,string branch)=>new(card.Reference.Id,state,branch,"http://localhost:8112","drupal","10.6.3",
        RepositoryURL:"https://example.invalid/owned/repository",VersionsLine:"php 8.4 · mysql 8.0");
    private static WorkerResponse Response(ProjectStatus status,AttentionSnapshot? attention=null)=>new(WorkerProtocol.Version,null,"Test Linux",null,status,null,null,Attention:attention);
    private static TaskCompletionSource<T> Pending<T>()=>new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static T Get<T>(object owner,string field)=>(T)owner.GetType().GetField(field,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(owner)!;
    private static KeyEventArgs RaiseKey(DDEVPowerOffDialog dialog,Key key)
    {
        var args=new KeyEventArgs(Keyboard.PrimaryDevice,PresentationSource.FromVisual(dialog)!,Environment.TickCount,key) { RoutedEvent=Keyboard.PreviewKeyDownEvent };
        dialog.ConfirmButton.RaiseEvent(args); return args;
    }
    private static void Require(bool value,string message) { if (!value) throw new IOException(message); }
}
