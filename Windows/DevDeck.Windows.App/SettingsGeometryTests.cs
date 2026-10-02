using System;
using System.Collections.Generic;
using System.Collections;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal static class SettingsGeometryTests
{
    private const int EnterSizeMove = 0x0231, ExitSizeMove = 0x0232;
    private const double ChosenWidth = 940, ChosenHeight = 560;
    private static readonly DateTimeOffset Receipt = new(2026,10,2,12,0,0,TimeSpan.Zero);

    internal static async Task RunAsync(Application application,List<object> checks)
    {
        var language=Text.Language;
        try {
            await RunRedAsync(application,checks);
            await RunFooterRedAsync(application,checks);
            await RunClosingRedAsync(application,checks);
            await NoIntentAsync(application,checks);
            await ScopedCommitAsync(application,checks);
            await FailedCommitAsync(application,checks);
            await StaleMetadataAsync(application,checks);
            await AdmissionAsync(application,checks);
            await PendingReceiptAsync(application,checks);
            await RestoreChoiceAsync(application,checks);
            await DraftAsync(application,checks);
            await PasswordAsync(application,checks);
            foreach(var locale in DevDeck.Windows.Core.Localization.Languages)await PageLayoutAsync(application,locale,checks);
        }finally{Text.Use(language);}
    }

    internal static async Task RunFailureAsync(Application application,List<object> checks)
    {
        var language=Text.Language;
        try{await FailedCommitAsync(application,checks);}
        finally{Text.Use(language);}
    }

    private static async Task NoIntentAsync(Application application,List<object> checks)
    {
        await using var fixture=new GeometryFixture(application);
        var before=fixture.Capture();
        await fixture.ShowAsync();
        var hwnd=new WindowInteropHelper(fixture.Window).Handle;
        fixture.Window.Width=950;fixture.Window.Height=570;await RenderAsync(fixture.Window);
        SendMessage(hwnd,ExitSizeMove,0,0);await RenderAsync(fixture.Window);
        await fixture.Window.SelectPageAsync("deck");fixture.Window.Search.Text="deck";await RenderAsync(fixture.Window);
        fixture.Window.ReloadNavigation();await RenderAsync(fixture.Window);
        SendMessage(hwnd,EnterSizeMove,0,0);fixture.Window.Left+=8;fixture.Window.Top+=8;
        SendMessage(hwnd,ExitSizeMove,0,0);await RenderAsync(fixture.Window);
        fixture.Window.WindowState=WindowState.Minimized;await RenderAsync(fixture.Window);
        fixture.Window.WindowState=WindowState.Normal;await RenderAsync(fixture.Window);
        fixture.Window.WindowState=WindowState.Maximized;await RenderAsync(fixture.Window);
        fixture.Window.WindowState=WindowState.Normal;await RenderAsync(fixture.Window);
        fixture.RequireSame(before);
        Require(fixture.Attempts==0&&fixture.Controller.Settings.SettingsWindow is null,
            "Initial/programmatic/page/search/sidebar/move-only/minimize/maximize events materialized settings geometry.");
        await using var sample=new GeometryFixture(application,windowLive:false);
        await sample.ShowAsync();await ResizeAsync(sample.Window,940,560);
        Require(sample.Attempts==0&&sample.Controller.Settings.SettingsWindow is null,
            "A live:false sample window persisted a simulated resize.");
        checks.Add(new{name="settings.geometry.noIntent",unpairedExitAndProgrammaticChangesNoSave=true,
            moveOnlyAndWindowStatesNoSave=true,initialPagesQueryCachedSidebarNoSave=true,liveFalseSampleNoSave=true});
    }

    private static async Task ScopedCommitAsync(Application application,List<object> checks)
    {
        await using var fixture=new GeometryFixture(application);
        fixture.AddOwner();fixture.SeedAttention();await fixture.ShowAsync();
        var read=fixture.StartOwnerRead();
        var before=fixture.Capture();
        var gate=Field<SemaphoreSlim>(fixture.Controller,"actions");await gate.WaitAsync();
        try {
            Require(fixture.Signals().Length>0&&fixture.Pending().Length>0&&fixture.Queued().Length>0
                &&fixture.Controller.Settings.AnnouncedAlerts.Length>1&&!read.IsCompleted&&!fixture.ReadToken.IsCancellationRequested,
                "The geometry fixture lacks positive attention/Seen/pending/queued or pending-read premises.");
            await ResizeAsync(fixture.Window,940,560);
            fixture.RequireSame(before);
            Require(fixture.Attempts==1&&fixture.Store.Load().SettingsWindow==new SettingsWindowGeometry(940,560)
                &&fixture.Controller.Settings.SettingsWindow==new SettingsWindowGeometry(940,560)
                &&!read.IsCompleted&&!fixture.ReadToken.IsCancellationRequested,
                "A completed resize waits for the held project gate, writes more than once or cancels a retained read.");
        }finally{gate.Release();}
        await fixture.CompleteReadAsync();
        Require(fixture.Owner?.Latest?.Branch=="owned-read-result","The preserved injected read failed to publish after a geometry-only save.");
        checks.Add(new{name="settings.geometry.scopedCommit",heldActionGateBypassed=true,oneAtomicCurrentModelCommit=true,
            nonemptyAttentionSeenPendingQueueAndClockPreserved=true,sameOwnerHwndSnapshotAndUncancelledRead=true});
    }

    private static async Task FailedCommitAsync(Application application,List<object> checks)
    {
        await using var fixture=new GeometryFixture(application);
        var form=new AccountSettingsForm(fixture.Controller,null,live:false,_=>{});
        InstallForm(fixture.Window,form,"new-account");
        var label=Field<TextBox>(form,"label");label.Text="Owned unsaved caption";
        form.TokenDraft="owned unsaved password";
        var message=Field<TextBlock>(form,"Message",typeof(SettingsForm));message.Text="Owned current row error";
        await fixture.ShowAsync();await FocusAsync(fixture.Window,label);label.Select(2,5);
        var page=fixture.Window.Page.Content;var before=fixture.Capture();
        var targetBytes=File.ReadAllBytes(fixture.Store.Path);
        var backupPath=fixture.Store.Path+".bak";
        var backupBytes=File.Exists(backupPath)?File.ReadAllBytes(backupPath):null;
        fixture.FailCommit=true;await ResizeAsync(fixture.Window,940,560);
        var banner=Field<Border>(fixture.Window,"geometryBanner");var error=Field<TextBlock>(fixture.Window,"geometryError");
        fixture.RequireSame(before);
        Require(File.ReadAllBytes(fixture.Store.Path).SequenceEqual(targetBytes)
            &&(backupBytes is null?!File.Exists(backupPath):File.Exists(backupPath)&&File.ReadAllBytes(backupPath).SequenceEqual(backupBytes)),
            "The injected pre-store size-save failure changed exact owned target/backup bytes.");
        Require(fixture.Attempts==1&&fixture.Controller.Settings.SettingsWindow is null&&fixture.Store.Load().SettingsWindow is null
            &&banner.Visibility==Visibility.Visible&&error.Text.StartsWith(Text.L("windows.settingsSizeSaveFailed","").TrimEnd(),StringComparison.Ordinal)
            &&ReferenceEquals(page,fixture.Window.Page.Content)&&label.Text=="Owned unsaved caption"&&label.IsKeyboardFocused
            &&label.SelectionStart==2&&label.SelectionLength==5&&form.TokenDraft=="owned unsaved password"&&message.Text=="Owned current row error",
            "A failed size write altered committed geometry, active form/error/draft/focus, or failed to show its separate banner.");
        fixture.FailCommit=false;await ResizeAsync(fixture.Window,960,580);
        Require(fixture.Attempts==2&&fixture.Controller.Settings.SettingsWindow==new SettingsWindowGeometry(960,580)
            &&fixture.Store.Load().SettingsWindow==new SettingsWindowGeometry(960,580)&&banner.Visibility==Visibility.Collapsed
            &&message.Text=="Owned current row error"&&label.IsKeyboardFocused&&form.TokenDraft=="owned unsaved password",
            "A later successful resize did not clear only its size-error banner or did not persist the usable size.");
        fixture.RequireSame(before);
        checks.Add(new{name="settings.geometry.failedCommit",priorModelAndFileRetained=true,exactTargetAndBackupBytesRetained=true,
            injectedPreStoreFailure=true,separateNonmodalLocalizedBanner=true,
            rowErrorPasswordDraftAndCursorPreserved=true,explicitLaterResizeRetriesAndClearsOnlyBanner=true});
    }

    private static async Task StaleMetadataAsync(Application application,List<object> checks)
    {
        await using var fixture=new GeometryFixture(application);await fixture.ShowAsync();
        var old=fixture.Controller.Settings;
        var gate=Field<SemaphoreSlim>(fixture.Controller,"actions");await gate.WaitAsync();
        Task? save=null;
        try {
            save=fixture.Controller.SaveSettingsAsync(old with{NotifiesUpdates=!old.NotifiesUpdates});
            Require(!save.IsCompleted,"The stale metadata fixture did not wait on the actual project action semaphore.");
            await ResizeAsync(fixture.Window,940,560);
            Require(!save.IsCompleted&&fixture.Controller.Settings.SettingsWindow==new SettingsWindowGeometry(940,560),
                "An independent current size commit waited behind a queued old metadata save.");
        }finally{gate.Release();}
        await save!;
        Require(fixture.Store.Load().SettingsWindow==new SettingsWindowGeometry(940,560)
            &&fixture.Controller.Settings.SettingsWindow==new SettingsWindowGeometry(940,560)
            &&fixture.Controller.Settings.NotifiesUpdates!=old.NotifiesUpdates&&fixture.Attempts==1,
            "Actual queued metadata discarded the newer geometry or failed to commit its authorized field.");
        checks.Add(new{name="settings.geometry.staleMetadata",actualHeldQueuedSettingsSave=true,
            latestSizeSurvivesOlderSnapshot=true,metadataFieldStillCommits=true,noExtraGeometryCommit=true});
    }

    private static async Task AdmissionAsync(Application application,List<object> checks)
    {
        await using var fixture=new GeometryFixture(application);await fixture.ShowAsync();
        var hwnd=new WindowInteropHelper(fixture.Window).Handle;var size=new SettingsWindowGeometry(940,560);var before=fixture.Capture();
        Require(!fixture.Controller.SaveSettingsWindowGeometry(fixture.Window,size,hwnd+1),"A wrong HWND admitted size persistence.");
        Require(!await Task.Run(()=>fixture.Controller.SaveSettingsWindowGeometry(fixture.Window,size,hwnd)),"An off-dispatcher caller admitted a WPF size write.");
        fixture.Window.Hide();
        Require(!fixture.Controller.SaveSettingsWindowGeometry(fixture.Window,size,hwnd),"A hidden settings owner admitted size persistence.");
        fixture.Window.Show();await RenderAsync(fixture.Window);
        fixture.Window.WindowState=WindowState.Minimized;
        Require(!fixture.Controller.SaveSettingsWindowGeometry(fixture.Window,size,hwnd),"A minimized owner admitted size persistence.");
        fixture.Window.WindowState=WindowState.Normal;await RenderAsync(fixture.Window);
        SetField(fixture.Controller,"closing",true);
        try{Require(!fixture.Controller.SaveSettingsWindowGeometry(fixture.Window,size,hwnd),"A closing controller admitted size persistence.");}
        finally{SetField(fixture.Controller,"closing",false);}
        SetField(fixture.Controller,"shuttingDown",true);
        try{Require(!fixture.Controller.SaveSettingsWindowGeometry(fixture.Window,size,hwnd),"A shutting-down controller admitted size persistence.");}
        finally{SetField(fixture.Controller,"shuttingDown",false);}
        var replacement=new SettingsWindow(fixture.Controller,live:false,tokenAvailable:_=>false);
        SetField(fixture.Controller,"settingsWindow",replacement);replacement.Show();await RenderAsync(replacement);
        try {
            Require(!fixture.Controller.SaveSettingsWindowGeometry(fixture.Window,size,hwnd)
                &&!fixture.Controller.SaveSettingsWindowGeometry(replacement,size,new WindowInteropHelper(replacement).Handle),
                "A replaced owner or live:false current owner admitted a geometry write.");
        }finally{await replacement.CloseSettingsAsync();SetField(fixture.Controller,"settingsWindow",fixture.Window);}
        Require(await fixture.Window.CloseSettingsAsync(),"The clean admission fixture did not close.");
        Require(!fixture.Controller.SaveSettingsWindowGeometry(fixture.Window,size,hwnd),"A closed settings owner admitted a geometry write.");
        fixture.RequireSame(before);Require(fixture.Attempts==0,"Rejected size writers reached atomic persistence.");
        checks.Add(new{name="settings.geometry.ownerAdmission",wrongHwndThreadHiddenMinimizedClosedAndReplacedRefused=true,
            inactiveSampleClosingAndShutdownRefused=true,noAtomicWriteOrRuntimeMutation=true});
    }

    private static async Task PendingReceiptAsync(Application application,List<object> checks)
    {
        await using var fixture=new GeometryFixture(application);await fixture.ShowAsync();
        var before=fixture.Capture();var hwnd=new WindowInteropHelper(fixture.Window).Handle;
        SendMessage(hwnd,EnterSizeMove,0,0);fixture.Window.Width=940;fixture.Window.Height=560;await RenderAsync(fixture.Window);
        SendMessage(hwnd,ExitSizeMove,0,0);fixture.Window.Hide();await RenderAsync(fixture.Window);
        fixture.Window.Show();await RenderAsync(fixture.Window);
        SendMessage(hwnd,EnterSizeMove,0,0);fixture.Window.Width=960;fixture.Window.Height=580;await RenderAsync(fixture.Window);
        SendMessage(hwnd,ExitSizeMove,0,0);fixture.Window.Width=980;await RenderAsync(fixture.Window);
        SendMessage(hwnd,EnterSizeMove,0,0);fixture.Window.Width=990;fixture.Window.Height=590;await RenderAsync(fixture.Window);
        SendMessage(hwnd,ExitSizeMove,0,0);
        var replacement=OwnedWindow(fixture.Controller);replacement.Show();await RenderAsync(replacement);
        try{Require(fixture.Attempts==0,"A hidden/replaced receipt or a superseding programmatic size committed its stale exit callback.");}
        finally{await replacement.CloseSettingsAsync();SetField(fixture.Controller,"settingsWindow",fixture.Window);}
        fixture.RequireSame(before);
        checks.Add(new{name="settings.geometry.pendingReceipt",hideGenerationInvalidates=true,
            currentOwnerRevalidatedAfterQueue=true,supersedingProgrammaticSizeNotSaved=true});
    }

    private static async Task RestoreChoiceAsync(Application application,List<object> checks)
    {
        var chosen=new SettingsWindowGeometry(4000,3000);
        await using var fixture=new GeometryFixture(application,seed:GeometrySeed("en") with{SettingsWindow=chosen});
        var bytes=File.ReadAllBytes(fixture.Store.Path);await fixture.ShowAsync();
        var area=SystemParameters.WorkArea;
        Require(area.Width>=880&&area.Height>=440,"The native restore fixture requires its supported logical work-area floor.");
        Require(Close(fixture.Window.Width,Math.Min(chosen.Width,area.Width))&&Close(fixture.Window.Height,Math.Min(chosen.Height,area.Height))
            &&fixture.Controller.Settings.SettingsWindow==chosen&&fixture.Store.Load().SettingsWindow==chosen
            &&File.ReadAllBytes(fixture.Store.Path).SequenceEqual(bytes)&&fixture.Attempts==0,
            "Opening a saved large size failed temporary work-area clamping or rewrote the remembered user choice.");
        RequireNativeSize(fixture.Window,Bounds(new WindowInteropHelper(fixture.Window).Handle));RequirePageBounds(fixture.Window);
        checks.Add(new{name="settings.geometry.restoreChoice",supportedEffectiveSizeFitsCurrentWorkArea=true,
            rememberedChoiceAndExactFileRetained=true,noInitialLayoutWrite=true});
    }

    private static async Task DraftAsync(Application application,List<object> checks)
    {
        await using var fixture=new GeometryFixture(application);
        // Select and replace before Show: the discarded default live form never
        // receives Loaded, so no real health/distribution discovery can begin.
        await fixture.Window.SelectPageAsync("project:geometry.local");
        ((SettingsForm)fixture.Window.Page.Content).Dispose();
        var pending=new TaskCompletionSource<ProjectStatus>(TaskCreationOptions.RunContinuationsAsynchronously);
        CancellationToken token=default;var reads=0;
        var configured=fixture.Controller.Settings.Cards.Single(card=>card.Project.Id=="geometry.local");
        var form=new ProjectSettingsForm(fixture.Controller,configured,live:true,_=>{},
            checker:(_,cancellation)=>{reads++;token=cancellation;return pending.Task;},discoverDistributions:false);
        InstallForm(fixture.Window,form,"project:geometry.local");
        try {
            await fixture.ShowAsync();
            Require(reads==1&&!pending.Task.IsCompleted&&!token.IsCancellationRequested,"The owned draft fixture did not establish its injected pending arrival check.");
            var name=Field<TextBox>(form,"title");name.Text="   ";await form.FlushAsync();
            var message=Field<TextBlock>(form,"Message",typeof(SettingsForm));var error=message.Text;
            Require(form.HasUncommittedChanges&&error.Length>0,"The geometry draft fixture did not exercise actual invalid metadata validation.");
            fixture.Window.Search.Text="Geometry";await FocusAsync(fixture.Window,name);name.Select(1,1);
            var drafts=Field<Dictionary<string,string>>(fixture.Window,"tokenDrafts");drafts["account:geometry.github"]="owned unsaved token";
            var page=fixture.Window.Page.Content;var health=form.HealthCheck;var before=fixture.Capture();
            await ResizeAsync(fixture.Window,880,440);
            Require(ReferenceEquals(page,fixture.Window.Page.Content)&&ReferenceEquals(health,form.HealthCheck)
                &&name.Text=="   "&&name.IsKeyboardFocused&&name.SelectionStart==1&&name.SelectionLength==1
                &&form.HasUncommittedChanges&&message.Text==error&&fixture.Window.Search.Text=="Geometry"
                &&fixture.Window.SelectedPage=="project:geometry.local"&&drafts["account:geometry.github"]=="owned unsaved token"
                &&reads==1&&!token.IsCancellationRequested&&!pending.Task.IsCompleted,
                "A normal resize disturbed invalid metadata/error, query, token draft, field cursor or the pending health-check owner.");
            Require(!await fixture.Window.CloseSettingsAsync()&&fixture.Window.IsVisible&&form.HasUncommittedChanges
                &&fixture.Store.Load().SettingsWindow==new SettingsWindowGeometry(880,440),
                "Invalid metadata close discarded its draft or rolled back a separately committed normal size.");
            fixture.RequireSame(before);
            checks.Add(new{name="settings.geometry.invalidDraft",actualValidationErrorAndUnsavedMetadataRetained=true,
                sameFormAndHealthOwnerUncancelled=true,queryTokenDraftFocusCaretAndSelectionPreserved=true,
                refusedCloseRetainsCommittedSize=true});
        }finally{
            pending.TrySetResult(new(configured.Project.Id,"stopped","owned-check",null,null,null));
            await RenderAsync(fixture.Window);
        }
    }

    private static async Task PasswordAsync(Application application,List<object> checks)
    {
        await using var fixture=new GeometryFixture(application);
        await fixture.Window.SelectPageAsync("account:geometry.github");
        ((SettingsForm)fixture.Window.Page.Content).Dispose();
        var configured=fixture.Controller.Settings.AccountList.Single(account=>account.Id=="geometry.github");
        var form=new AccountSettingsForm(fixture.Controller,configured,live:false,_=>{});
        InstallForm(fixture.Window,form,"account:geometry.github");form.TokenDraft="owned retained password";
        var password=Field<PasswordBox>(form,"token");
        await fixture.ShowAsync();fixture.Window.Search.Text="Geometry";await FocusAsync(fixture.Window,password);
        var page=fixture.Window.Page.Content;var before=fixture.Capture();var currentSelection=fixture.Window.SelectedPage;
        await ResizeAsync(fixture.Window,880,440);
        Require(ReferenceEquals(page,fixture.Window.Page.Content)&&form.TokenDraft=="owned retained password"
            &&password.IsKeyboardFocused&&fixture.Window.Search.Text=="Geometry"&&fixture.Window.SelectedPage==currentSelection,
            "Normal window sizing reconstructed the active account, lost its password/focus or changed selection/query.");
        fixture.RequireSame(before);
        checks.Add(new{name="settings.geometry.password",sameActualAccountFormAndPasswordControl=true,
            unsavedPasswordAndKeyboardFocusPreserved=true,selectionAndQueryUnchanged=true});
    }

    private static async Task PageLayoutAsync(Application application,string locale,List<object> checks)
    {
        await using var fixture=new GeometryFixture(application,locale,windowLive:false);
        await fixture.ShowAsync();
        var pages=new[]{"general","deck","cards","notifications","project:geometry.local","project:geometry.ddev",
            "project:geometry.arc","account:geometry.github","account:geometry.gitlab"};
        var layouts=0;var reachable=0;
        foreach(var font in new[]{13d,18d}) {
            fixture.Window.FontSize=font;
            foreach(var selected in pages) {
                await fixture.Window.SelectPageAsync(selected);await RenderAsync(fixture.Window);
                foreach(var expanded in Descendants<Expander>(fixture.Window.Page).ToArray())expanded.IsExpanded=true;
                await RenderAsync(fixture.Window);
                var page=fixture.Window.Page.Content;
                foreach(var size in new[]{(Width:1020d,Height:720d),(Width:880d,Height:440d)}) {
                    fixture.Window.Width=size.Width;fixture.Window.Height=size.Height;await RenderAsync(fixture.Window);
                    Require(ReferenceEquals(page,fixture.Window.Page.Content)&&fixture.Window.Page.ViewportWidth>0
                        &&fixture.Window.Page.ViewportHeight>0&&fixture.Window.Page.HorizontalOffset==0,
                        locale+"/"+selected+": normal page resizing replaced the form or lost its usable vertical viewport.");
                    var controls=Descendants<Control>(fixture.Window.Page).Where(control=>control.IsVisible&&control.ActualWidth>0&&control.ActualHeight>0
                        &&AutomationName(control).Length>0
                        &&control is TextBox or PasswordBox or ComboBox or Button or CheckBox).ToArray();
                    Require(controls.Length>0,locale+"/"+selected+": this actual page/size/font layout has no named real controls to validate."
                        +(controls.Length==0?" "+PageLayoutDiagnostic(fixture.Window,selected,page,font,size.Width,size.Height,controls.Length):""));
                    foreach(var control in controls) {
                        var bounds=control.TransformToAncestor(fixture.Window.Page).TransformBounds(new Rect(new Point(),control.RenderSize));
                        Require(bounds.Left>=-.6&&bounds.Right<=fixture.Window.Page.ViewportWidth+.6,
                            locale+"/"+selected+": an actual labeled control escapes the page's horizontal viewport: "
                            +AutomationName(control)+" "+bounds);
                    }
                    foreach(var control in controls.Take(1).Concat(controls.TakeLast(3)).Distinct()) {
                        control.BringIntoView();await RenderAsync(fixture.Window);
                        var bounds=control.TransformToAncestor(fixture.Window.Page).TransformBounds(new Rect(new Point(),control.RenderSize));
                        Require(bounds.Top>=-.6&&bounds.Bottom<=fixture.Window.Page.ViewportHeight+.6,
                            locale+"/"+selected+": a page-bottom control cannot be reached at its actual normal size: "
                            +AutomationName(control)+" "+bounds);
                        reachable++;
                    }
                    RequirePageBounds(fixture.Window);layouts++;
                }
            }
        }
        Require(layouts==36&&reachable>0&&fixture.Attempts==0&&fixture.Controller.Settings.SettingsWindow is null,
            "The locale layout fixture missed page/size/font coverage or persisted its programmatic resize.");
        checks.Add(new{name="settings.geometry.pages."+locale,layouts,reachable,
            minimumAndDefaultNormalSize=true,normalAndEnlargedFonts=true,existingPagesAndAdvancedSections=true,
            actualLabeledHorizontalBoundsAndBottomReachability=true,sameActiveFormPerResize=true,noProgrammaticSave=true});
    }

    // Observe only on failure: do not UpdateLayout, create peers, reselect, retry or wait.
    private static string PageLayoutDiagnostic(SettingsWindow window,string requested,object? capturedPage,
        double requestedFont,double requestedWidth,double requestedHeight,int matchedCount)
    {
        static double? Finite(double value)=>double.IsFinite(value)?value:null;
        static object? State(FrameworkElement? element)=>element is null?null:new {
            type=element.GetType().Name,visibility=element.Visibility.ToString(),visible=element.IsVisible,
            loaded=element.IsLoaded,enabled=element.IsEnabled,connected=PresentationSource.FromVisual(element)is not null,
            width=Finite(element.ActualWidth),height=Finite(element.ActualHeight),
            measureValid=element.IsMeasureValid,arrangeValid=element.IsArrangeValid
        };
        static string ObservedName(Control control)
        {
            var attached=System.Windows.Automation.AutomationProperties.GetName(control);
            return attached.Length>0?attached:System.Windows.Automation.Peers.UIElementAutomationPeer.FromElement(control)?.GetName()??"";
        }
        var form=Field<SettingsForm?>(window,"form");
        var configured=(form is ProjectSettingsForm)?Field<CardSettings?>(form,"original"):null;
        var candidates=Descendants<Control>(window.Page)
            .Where(control=>control is TextBox or PasswordBox or ComboBox or Button or CheckBox)
            .Select(control=>new{control,name=ObservedName(control)}).ToArray();
        return JsonSerializer.Serialize(new {
            requested,selected=window.SelectedPage,selectedMatches=window.SelectedPage==requested,
            changing=Field<bool>(window,"changing"),requestedFont,actualFont=Finite(window.FontSize),
            requestedWidth,requestedHeight,windowState=window.WindowState.ToString(),
            sameCapturedPage=ReferenceEquals(capturedPage,window.Page.Content),
            currentFormIsPage=ReferenceEquals(form,window.Page.Content),
            projectID=configured?.Project.Id,projectKind=configured?.Project.Kind,
            window=State(window),page=State(window.Page),content=State(window.Page.Content as FrameworkElement),form=State(form),
            viewportWidth=Finite(window.Page.ViewportWidth),viewportHeight=Finite(window.Page.ViewportHeight),
            horizontalOffset=Finite(window.Page.HorizontalOffset),verticalOffset=Finite(window.Page.VerticalOffset),
            eligible=candidates.Length,visible=candidates.Count(item=>item.control.IsVisible),
            sized=candidates.Count(item=>item.control.ActualWidth>0&&item.control.ActualHeight>0),
            named=candidates.Count(item=>item.name.Length>0),matchedCount,
            samples=candidates.Take(8).Select(item=>new {
                name=item.name.Length>128?item.name[..128]:item.name,state=State(item.control)
            }).ToArray()
        },WorkerProtocol.Json);
    }

    private static async Task ResizeAsync(SettingsWindow window,double width,double height)
    {
        var hwnd=new WindowInteropHelper(window).Handle;
        Require(window.IsVisible&&window.WindowState==WindowState.Normal&&hwnd!=0,"A resize must start on its actual owned visible normal HWND.");
        SendMessage(hwnd,EnterSizeMove,0,0);window.Width=width;window.Height=height;await RenderAsync(window);
        Require(Close(window.ActualWidth,width)&&Close(window.ActualHeight,height),"The owned normal window did not reach the requested resize dimensions.");
        SendMessage(hwnd,ExitSizeMove,0,0);await RenderAsync(window);
    }
    private static async Task FocusAsync(SettingsWindow window,FrameworkElement control)
    {
        await RenderAsync(window);control.BringIntoView();await RenderAsync(window);
        var bounds=control.TransformToAncestor(window.Page).TransformBounds(new Rect(new Point(),control.RenderSize));
        Require(control.IsLoaded&&control.IsVisible&&control.IsEnabled&&control.Focusable&&PresentationSource.FromVisual(control)is not null
            &&bounds.Top<window.Page.ViewportHeight&&bounds.Bottom>0,"The owned geometry focus field is not rendered within its page viewport.");
        window.Activate();await RenderAsync(window);Keyboard.Focus(control);await RenderAsync(window);
        Require(control.IsKeyboardFocused,"The rendered owned geometry field did not obtain actual keyboard focus.");
    }
    private static void InstallForm(SettingsWindow window,SettingsForm form,string selected)
    {
        typeof(SettingsWindow).GetField("form",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(window,form);
        typeof(SettingsWindow).GetField("selected",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(window,selected);
        window.Page.Content=form;
    }
    private static T Field<T>(object owner,string name,Type? declaring=null)=> (T)(declaring??owner.GetType())
        .GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(owner)!;
    private static string AutomationName(Control control)
    {
        var attached=System.Windows.Automation.AutomationProperties.GetName(control);
        return attached.Length>0?attached:System.Windows.Automation.Peers.UIElementAutomationPeer.CreatePeerForElement(control)?.GetName()??"";
    }

    private static DeckSettings GeometrySeed(string locale)=>new(1,[new("Test Linux","/tmp/owned-geometry-runtime")],
        [new(new("geometry.local","Test Linux","local","/tmp/owned-geometry-local",StartCommand:"npm run dev",HoldsProcess:true),"Geometry local"),
         new(new("geometry.ddev","Test Linux","ddev","/tmp/owned-geometry-ddev"),"Geometry DDEV",Enabled:false),
         new(new("geometry.arc","Test Linux","arc","/tmp/owned-geometry-arc",Arc:new("geometry.example.invalid","geometry-site","http://localhost:3000","/release")),"Geometry Arc",Enabled:false,
             Links:ProjectLinks.Defaults("arc").Select(ProjectLinks.MigrateArc).ToArray())],
        Accounts:[new("geometry.github","Geometry GitHub","github","https://api.github.example.invalid",["retained"],["retained/repo"],Enabled:false,Browser:"chrome",BrowserProfile:"Profile 2"),
                  new("geometry.gitlab","Geometry GitLab","gitlab","https://gitlab.example.invalid",[],[],Enabled:false,Browser:"firefox")],
        Language:locale,SeenAlerts:["owned.geometry.seen"],WorkInFlight:new(Enabled:false,X:137,Y:179,Collapsed:true));

    private sealed record GeometryOwner(Window Window,nint Hwnd,ProjectStatus? Status);
    private sealed record GeometryCaptured(JsonNode Model,JsonNode Persisted,DateTimeOffset? Clock,string Signals,string Pending,string Queued,GeometryOwner[] Owners);
    // Report only bounded property paths from this owned synthetic fixture, never values.
    private static string[] ChangedPaths(JsonNode? before,JsonNode? after)
    {
        var paths=new List<string>();
        Visit(before,after,"$");
        return paths.ToArray();
        void Visit(JsonNode? oldNode,JsonNode? newNode,string path)
        {
            if(paths.Count>=32||JsonNode.DeepEquals(oldNode,newNode))return;
            if(oldNode is JsonObject oldObject&&newNode is JsonObject newObject){
                foreach(var key in oldObject.Select(pair=>pair.Key).Union(newObject.Select(pair=>pair.Key),StringComparer.Ordinal).OrderBy(key=>key,StringComparer.Ordinal))
                    Visit(oldObject[key],newObject[key],path+"."+key);
            }else if(oldNode is JsonArray oldArray&&newNode is JsonArray newArray){
                for(var index=0;index<Math.Max(oldArray.Count,newArray.Count)&&paths.Count<32;index++)
                    Visit(index<oldArray.Count?oldArray[index]:null,index<newArray.Count?newArray[index]:null,path+"["+index+"]");
            }else paths.Add(path);
        }
    }
    private sealed class GeometryFixture:IAsyncDisposable
    {
        internal SettingsStore Store{get;}
        internal DeckController Controller{get;}
        internal SettingsWindow Window{get;}
        internal int Attempts{get;private set;}
        internal bool FailCommit{get;set;}
        internal ProjectCard? Owner{get;private set;}
        internal CancellationToken ReadToken{get;private set;}
        private readonly TaskCompletionSource<WorkerResponse> readSource=new(TaskCreationOptions.RunContinuationsAsynchronously);
        private Task? read;
        internal GeometryFixture(Application application,string locale="en",bool windowLive=true,DeckSettings? seed=null)
        {
            Store=new(System.IO.Path.Combine(System.IO.Path.GetTempPath(),"devdeck-geometry-proof-"+Guid.NewGuid().ToString("N")+".json"));
            Store.Save(seed??GeometrySeed(locale));
            Controller=new(application,Store,live:false,settingsGeometryCommit:value=>{
                Attempts++;if(FailCommit)throw new IOException("Owned geometry write failure.");Store.Save(value);
            });
            SetField(Controller,"lastCheckedAt",Receipt);
            Window=new(Controller,live:windowLive,tokenAvailable:_=>false);
            SetField(Controller,"settingsWindow",Window);
        }
        internal async Task ShowAsync(){Window.Show();await RenderAsync(Window);RequirePageBounds(Window);}
        internal void AddOwner()
        {
            var configuration=Controller.Settings.Cards.Single(card=>card.Project.Id=="geometry.local");
            Owner=new(Controller,configuration,live:false,statusReader:(_,cancellation)=>{ReadToken=cancellation;return readSource.Task;});
            Field<List<ProjectCard>>(Controller,"cards").Add(Owner);
            Field<Dictionary<string,CardSettings>>(Controller,"localConfigurations")[configuration.Project.Id]=configuration;
            new WindowInteropHelper(Owner).EnsureHandle();Owner.ApplySnapshot(new(configuration.Project.Id,"stopped","owned-cache",null,null,null));
        }
        internal Task StartOwnerRead()=>read=Owner!.RefreshAsync();
        internal async Task CompleteReadAsync()
        {
            if(read is null)return;
            readSource.TrySetResult(new(1,null,"Test Linux",null,new("geometry.local","running","owned-read-result",null,null,null),null,null));
            await read;read=null;
        }
        internal void SeedAttention()
        {
            var settings=Controller.Settings with{Notifications=true};Store.Save(settings);
            typeof(DeckController).GetProperty("Settings",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(Controller,settings);
            const string scope="local:Test Linux";
            AttentionItem Item(string id)=>new(id,id,"needsFixing","project",id,"Owned synthetic signal",1,new("showCard",CardID:"geometry.local"),true,false);
            DeckAlert Alert(string id)=>new(id,"wentDown","project",id,"Owned synthetic alert",id,id,new("showCard",CardID:"geometry.local"),false);
            Controller.ObserveAttention(new AttentionSnapshot(scope,[],[]));
            Controller.ObserveAttention(new AttentionSnapshot(scope,[Item("owned.geometry.signal")],[Alert("owned.geometry.queued")]));
            typeof(DeckController).GetMethod("FlushNotifications",BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(Controller,null);
            Controller.ObserveAttention(new AttentionSnapshot(scope,[Item("owned.geometry.signal")],[Alert("owned.geometry.pending")]));
            Field<DispatcherTimer>(Controller,"notificationBatch").Stop();
        }
        internal AttentionItem[] Signals()=>Field<AttentionTracker>(Controller,"attention").SignalItems;
        internal object[] Pending()=>Field<IEnumerable>(Controller,"pendingAlerts").Cast<object>().ToArray();
        internal object[] Queued()=>Field<IEnumerable>(Controller,"deliveries").Cast<object>().ToArray();
        internal GeometryCaptured Capture()=>new(Unrelated(JsonSerializer.SerializeToUtf8Bytes(Controller.Settings,WorkerProtocol.Json)),
            Unrelated(File.ReadAllBytes(Store.Path)),Controller.LastCheckedAt,JsonSerializer.Serialize(Signals(),WorkerProtocol.Json),
            JsonSerializer.Serialize(Pending(),WorkerProtocol.Json),JsonSerializer.Serialize(Queued(),WorkerProtocol.Json),
            Controller.AllLocalViews.Select(owner=>new GeometryOwner(owner,new WindowInteropHelper(owner).EnsureHandle(),owner.Latest)).ToArray());
        internal void RequireSame(GeometryCaptured before)
        {
            var model=Unrelated(JsonSerializer.SerializeToUtf8Bytes(Controller.Settings,WorkerProtocol.Json));
            var persisted=Unrelated(File.ReadAllBytes(Store.Path));
            var flags=new Dictionary<string,bool>{
                ["modelSame"]=JsonNode.DeepEquals(before.Model,model),
                ["persistedSame"]=JsonNode.DeepEquals(before.Persisted,persisted),
                ["clockSame"]=Controller.LastCheckedAt==before.Clock,
                ["signalsSame"]=before.Signals==JsonSerializer.Serialize(Signals(),WorkerProtocol.Json),
                ["pendingSame"]=before.Pending==JsonSerializer.Serialize(Pending(),WorkerProtocol.Json),
                ["queuedSame"]=before.Queued==JsonSerializer.Serialize(Queued(),WorkerProtocol.Json),
                ["localPollDisabled"]=!Controller.LocalPollEnabled,
                ["sharedPollDisabled"]=!Controller.SharedPollEnabled
            };
            var failures=flags.Where(flag=>!flag.Value).Select(flag=>flag.Key).ToArray();
            Require(failures.Length==0,"Geometry-only behavior changed unrelated state: "+string.Join(", ",failures)+"; "
                +JsonSerializer.Serialize(new{flags,modelPaths=ChangedPaths(before.Model,model),persistedPaths=ChangedPaths(before.Persisted,persisted),
                    beforeClock=before.Clock,afterClock=Controller.LastCheckedAt,
                    localPollEnabled=Controller.LocalPollEnabled,sharedPollEnabled=Controller.SharedPollEnabled},WorkerProtocol.Json));
            Require(before.Owners.Length==Controller.AllLocalViews.Length&&before.Owners.All(saved=>Controller.AllLocalViews.Any(owner=>
                ReferenceEquals(saved.Window,owner)&&saved.Hwnd==new WindowInteropHelper(owner).Handle&&ReferenceEquals(saved.Status,owner.Latest))),
                "Geometry-only behavior replaced a retained widget owner/HWND or its physical snapshot.");
        }
        public async ValueTask DisposeAsync()
        {
            await CompleteReadAsync();
            if(Field<SettingsForm?>(Window,"form")is{} form)form.Dispose();
            typeof(SettingsWindow).GetField("form",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(Window,null);
            if(!Window.GeometryOwnerClosed)await Window.CloseSettingsAsync();
            SetField(Controller,"settingsWindow",null);Controller.CloseViews();
            foreach(var owned in new[]{Store.Path,Store.Path+".bak"})if(File.Exists(owned))File.Delete(owned);
        }
    }

    internal static async Task RunClosingRedAsync(Application application, List<object> checks)
    {
        var language=Text.Language; var results=new List<object>(); var passed=true;
        try {
            foreach(var nativeClosing in new[]{false,true}) {
                var path=System.IO.Path.Combine(System.IO.Path.GetTempPath(),"devdeck-settings-closing-"+Guid.NewGuid().ToString("N")+".json");
                DeckController? controller=null;SettingsWindow? window=null;GeometryHeldFlushForm? form=null;Task<bool>? close=null;
                try {
                    var store=new SettingsStore(path);store.Save(DeckSettings.Empty with{Language="en",SeenAlerts=["owned.closing.seen"]});
                    var commits=0;
                    controller=new(application,store,live:false,settingsGeometryCommit:value=>{commits++;store.Save(value);});
                    SetField(controller,"lastCheckedAt",Receipt);
                    var persisted=Unrelated(File.ReadAllBytes(path));var model=Unrelated(JsonSerializer.SerializeToUtf8Bytes(controller.Settings,WorkerProtocol.Json));
                    window=OwnedWindow(controller);window.Show();await RenderAsync(window);
                    form=new(controller);
                    typeof(SettingsWindow).GetField("form",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(window,form);
                    window.Page.Content=form;await RenderAsync(window);
                    var hwnd=new WindowInteropHelper(window).Handle;
                    SendMessage(hwnd,EnterSizeMove,0,0);window.Width=ChosenWidth;window.Height=ChosenHeight;await RenderAsync(window);
                    form.Arm();
                    SendMessage(hwnd,ExitSizeMove,0,0);
                    if(nativeClosing)window.Close();else close=window.CloseSettingsAsync();
                    await RenderAsync(window);
                    Require(form.Started&&!form.Completion.Task.IsCompleted&&window.IsVisible
                        &&(close is null||!close.IsCompleted),"The closing race did not establish an actual pending SettingsForm.Flush on a still-visible owned window.");
                    RequireUnrelated(controller,path,persisted,model);
                    var pass=commits==0&&controller.Settings.SettingsWindow is null;
                    passed&=pass;
                    results.Add(new{nativeClosing,pass,commits,settingsWindow=controller.Settings.SettingsWindow,
                        actualFlushPending=true,currentVisibleOwner=true,completedResizeCallbackPumped=true});
                }finally{
                    form?.Completion.TrySetResult();
                    if(close is not null)await close;
                    if(window?.IsVisible==true){await RenderAsync(window);if(window.IsVisible)await window.CloseSettingsAsync();}
                    if(controller is not null){SetField(controller,"settingsWindow",null);controller.CloseViews();}
                    foreach(var owned in new[]{path,path+".bak"})if(File.Exists(owned))File.Delete(owned);
                }
            }
            checks.Add(new{name="settings.geometry.pendingExitClosing",pass=passed,explicitCloseAndNativeClosing=true,results});
            Require(passed,"A pending completed-resize receipt was committed after settings close began while its actual form Flush was still pending: "
                +JsonSerializer.Serialize(results,WorkerProtocol.Json));
        }finally{Text.Use(language);}
    }

    private sealed class GeometryHeldFlushForm:SettingsForm
    {
        internal readonly TaskCompletionSource Completion=new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal bool Started{get;private set;}
        internal GeometryHeldFlushForm(DeckController controller):base(controller,live:true)
        {Autosaves=true;Content=new TextBlock{Text="Owned pending metadata flush",Margin=new(32)};}
        internal void Arm()=>Changed();
        protected override async Task SaveMetadataAsync(){Started=true;await Completion.Task;}
    }

    internal static async Task RunFooterRedAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        var failures = new List<string>();
        try {
            foreach (var locale in DevDeck.Windows.Core.Localization.Languages) {
                var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "devdeck-settings-footer-" + Guid.NewGuid().ToString("N") + ".json");
                DeckController? controller = null; SettingsWindow? window = null;
                try {
                    var store = new SettingsStore(path); store.Save(DeckSettings.Empty with { Language = locale });
                    controller = new(application,store,live:false);
                    var persisted = File.ReadAllBytes(path);
                    window = new(controller,live:false,tokenAvailable:_=>false); window.Show();
                    var results = new List<object>();
                    foreach (var font in new[] { 13d,18d }) {
                        window.FontSize = font;
                        foreach (var size in new[] { (Width:1020d,Height:720d),(Width:880d,Height:440d) }) {
                            window.Width = size.Width; window.Height = size.Height;
                            foreach (var selected in new[] { "general","deck" }) {
                                await window.SelectPageAsync(selected); await RenderAsync(window);
                                var root = (FrameworkElement)window.Content;
                                var buttons = Descendants<Button>(root).Where(button => new[] {
                                    Text.L("windows.newProject"),Text.L("windows.newAccount"),Text.L("settings.sidebar.remove")
                                }.Contains(System.Windows.Automation.AutomationProperties.GetName(button),StringComparer.Ordinal)).ToArray();
                                Require(buttons.Length == 3 && root.ActualWidth > 0 && window.IsVisible,
                                    "The owned footer fixture did not render all three actual sidebar actions.");
                                var contained = true;
                                foreach (var button in buttons) {
                                    var bounds = button.TransformToAncestor(root).TransformBounds(new Rect(new Point(),button.RenderSize));
                                    var text = button.Content as TextBlock;
                                    var textBounds = text?.TransformToAncestor(button).TransformBounds(new Rect(new Point(),text.RenderSize));
                                    var pass = button.IsVisible && button.ActualWidth > 0 && button.ActualHeight > 0
                                        && bounds.Left >= -.5 && bounds.Right <= 245.5 && bounds.Top >= -.5 && bounds.Bottom <= root.ActualHeight+.5
                                        && (textBounds is null || textBounds.Value.Left >= -.5 && textBounds.Value.Right <= button.ActualWidth+.5
                                            && textBounds.Value.Top >= -.5 && textBounds.Value.Bottom <= button.ActualHeight+.5);
                                    contained &= pass;
                                    results.Add(new { selected,font,size.Width,size.Height,title=System.Windows.Automation.AutomationProperties.GetName(button),
                                        buttonBounds=bounds.ToString(System.Globalization.CultureInfo.InvariantCulture),
                                        textBounds=textBounds?.ToString(System.Globalization.CultureInfo.InvariantCulture), pass });
                                }
                                if (!contained) failures.Add(locale+"/"+selected+"/"+font+"/"+size.Width+"×"+size.Height);
                            }
                        }
                    }
                    Require(File.ReadAllBytes(path).SequenceEqual(persisted) && controller.Settings.SettingsWindow is null
                        && !controller.LocalPollEnabled && !controller.SharedPollEnabled,
                        "Programmatic footer layout changed settings or started worker polling.");
                    checks.Add(new { name="settings.geometry.footer."+locale, pass=!failures.Any(failure=>failure.StartsWith(locale+"/",StringComparison.Ordinal)),
                        actualButtonAndTextBounds=true, normalAndEnlargedFonts=true, minimumAndDefaultSizes=true,
                        generalAndDeckPages=true, noClicksOrSettingsWrites=true, results });
                } finally {
                    if (window is not null) await window.CloseSettingsAsync();
                    controller?.CloseViews();
                    foreach (var owned in new[] { path,path+".bak" }) if (File.Exists(owned)) File.Delete(owned);
                }
            }
            Require(failures.Count==0,"Actual settings footer actions/text escape their rendered sidebar/client: "+string.Join(", ",failures));
        } finally { Text.Use(language); }
    }

    // This baseline exercises the current production window, not an absent helper.
    // Only its two owned HWNDs and its local synthetic settings file are touched.
    internal static async Task RunRedAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "devdeck-settings-geometry-" + Guid.NewGuid().ToString("N") + ".json");
        DeckController? first = null, second = null;
        SettingsWindow? initial = null, reopened = null;
        try {
            Require(!path.StartsWith("\\\\", StringComparison.Ordinal), "The geometry fixture requires its own local Windows settings store.");
            var store = new SettingsStore(path);
            store.Save(DeckSettings.Empty with {
                Language = "en", Floating = true, Locked = true, RefreshSeconds = 120,
                NotifiesUpdates = false, SeenAlerts = ["owned.geometry.seen"],
                Accounts = [new("owned.geometry.account", "Geometry account", "gitlab", "https://gitlab.example.invalid", ["retained-org"], ["retained/repository"],
                    Enabled: false, Browser: "firefox", BrowserProfile: "retained-profile", NotifiesBlocked: true)],
                WorkInFlight = new(Enabled: false, X: 131, Y: 173, Collapsed: true)
            });
            first = new(application, store, live: false);
            SetField(first, "lastCheckedAt", Receipt);
            // DiscoverCards may normalize built-in entries in the constructor.
            // Capture only the canonical configuration established by that constructor.
            var persisted = Unrelated(File.ReadAllBytes(path));
            var model = Unrelated(JsonSerializer.SerializeToUtf8Bytes(first.Settings, WorkerProtocol.Json));
            initial = OwnedWindow(first);
            initial.Show(); await RenderAsync(initial);
            await initial.SelectPageAsync("deck"); await RenderAsync(initial);
            Require(SystemParameters.WorkArea.Width >= ChosenWidth && SystemParameters.WorkArea.Height >= ChosenHeight,
                "This owned resize baseline requires a logical work area that contains 940×560 DIP.");
            var hwnd = new WindowInteropHelper(initial).Handle;
            var before = Bounds(hwnd);
            var content = initial.Page.Content;
            Require(hwnd != 0 && initial.WindowState == WindowState.Normal && content is FrameworkElement,
                "The owned settings window did not establish a rendered normal Deck page.");
            RequirePageBounds(initial);

            SendMessage(hwnd, EnterSizeMove, 0, 0);
            initial.Width = ChosenWidth; initial.Height = ChosenHeight;
            await RenderAsync(initial);
            var resized = Bounds(hwnd);
            Require(Close(initial.ActualWidth, ChosenWidth) && Close(initial.ActualHeight, ChosenHeight)
                && before.Width != resized.Width && before.Height != resized.Height
                && ReferenceEquals(content, initial.Page.Content),
                "The completed resize fixture did not resize both actual native dimensions while retaining its Deck page.");
            RequireNativeSize(initial, resized); RequirePageBounds(initial);
            SendMessage(hwnd, ExitSizeMove, 0, 0);
            await RenderAsync(initial);
            RequireUnrelated(first, path, persisted, model);
            Require(await initial.CloseSettingsAsync(), "The owned Deck window refused a clean close.");
            SetField(first, "settingsWindow", null);
            RequireUnrelated(first, path, persisted, model);

            // Reload the same owned file through a fresh controller and a fresh HWND.
            second = new(application, new SettingsStore(path), live: false);
            SetField(second, "lastCheckedAt", Receipt);
            reopened = OwnedWindow(second);
            reopened.Show(); await RenderAsync(reopened);
            var reopenedHandle = new WindowInteropHelper(reopened).Handle;
            Require(reopenedHandle != 0 && reopened.IsVisible && reopened.WindowState == WindowState.Normal,
                "The owned settings window did not reopen as a rendered normal window.");
            RequireNativeSize(reopened, Bounds(reopenedHandle)); RequirePageBounds(reopened);
            RequireUnrelated(second, path, persisted, model);
            var pass = Close(reopened.ActualWidth, ChosenWidth) && Close(reopened.ActualHeight, ChosenHeight);
            checks.Add(new {
                name = "settings.geometry.baseline.reopen", pass,
                expectedWidth = ChosenWidth, expectedHeight = ChosenHeight,
                actualWidth = reopened.ActualWidth, actualHeight = reopened.ActualHeight,
                actualOwnedNativeResizeBoundary = true, freshControllerAndWindowSameOwnedStore = true,
                retainedPageDuringResize = true, renderedNativeAndViewportBounds = true,
                unrelatedConfigurationAndClockPreserved = true, fakeAvailabilityAndNoWorkerPoll = true
            });
            Require(pass, "Actual settings size was not restored after a completed owned resize: expected 940×560 DIP; reopened "
                + reopened.ActualWidth + "×" + reopened.ActualHeight + " DIP.");
        } finally {
            try {
                if (reopened is not null) await reopened.CloseSettingsAsync();
                if (initial?.IsVisible == true) await initial.CloseSettingsAsync();
            } finally {
                if (first is not null) { SetField(first, "settingsWindow", null); first.CloseViews(); }
                if (second is not null) { SetField(second, "settingsWindow", null); second.CloseViews(); }
                foreach (var owned in new[] { path, path + ".bak" }) if (File.Exists(owned)) File.Delete(owned);
                Text.Use(language);
            }
        }
    }

    private static SettingsWindow OwnedWindow(DeckController controller)
    {
        // The controller remains inert; live window behavior admits its own completed
        // resize. General/Deck have no arrival health/discovery or credential action.
        var window = new SettingsWindow(controller, live: true, tokenAvailable: _ => false);
        SetField(controller, "settingsWindow", window);
        return window;
    }
    private static async Task RenderAsync(SettingsWindow window)
    {
        window.UpdateLayout();
        for (var turn = 0; turn < 3; turn++) await Dispatcher.Yield(DispatcherPriority.Background);
        window.UpdateLayout();
    }
    private static void RequirePageBounds(SettingsWindow window)
    {
        var bounds = window.Page.TransformToAncestor(window).TransformBounds(new Rect(new Point(), window.Page.RenderSize));
        Require(window.IsVisible && window.Page.IsLoaded && window.Page.ViewportWidth > 0 && window.Page.ViewportHeight > 0
            && bounds.Width > 0 && bounds.Height > 0 && bounds.Left >= -1 && bounds.Top >= -1
            && bounds.Right <= window.ActualWidth + 1 && bounds.Bottom <= window.ActualHeight + 1,
            "The actual settings page is not rendered within its resized window viewport.");
    }
    private static void RequireNativeSize(SettingsWindow window, NativeBounds bounds)
    {
        var dpi = VisualTreeHelper.GetDpi(window);
        Require(Math.Abs(bounds.Width - window.ActualWidth * dpi.DpiScaleX) <= 2
            && Math.Abs(bounds.Height - window.ActualHeight * dpi.DpiScaleY) <= 2,
            "The actual owned HWND frame does not agree with its rendered WPF dimensions.");
    }
    private static void RequireUnrelated(DeckController controller, string path, JsonNode persisted, JsonNode model)
        => Require(JsonNode.DeepEquals(persisted, Unrelated(File.ReadAllBytes(path)))
            && JsonNode.DeepEquals(model, Unrelated(JsonSerializer.SerializeToUtf8Bytes(controller.Settings, WorkerProtocol.Json)))
            && controller.LastCheckedAt == Receipt && !controller.LocalPollEnabled && !controller.SharedPollEnabled
            && controller.AllLocalViews.Length == 0 && controller.AllRemoteViews.Length == 0,
            "The owned geometry exercise changed unrelated settings, its receipt, physical owners or worker polling.");
    private static JsonNode Unrelated(byte[] bytes)
    {
        var value = JsonNode.Parse(bytes) as JsonObject ?? throw new IOException("Owned settings JSON is not an object.");
        // The accepted additive field is the only permitted difference. This keeps
        // the baseline assertion useful when the actual producer is implemented.
        value.Remove("settingsWindow");
        return value;
    }
    private static bool Close(double actual, double expected) => Math.Abs(actual - expected) < .01;
    private static IEnumerable<T> Descendants<T>(DependencyObject source) where T : DependencyObject
    {
        for (var index=0;index<VisualTreeHelper.GetChildrenCount(source);index++) {
            var child=VisualTreeHelper.GetChild(source,index);
            if(child is T item) yield return item;
            foreach(var nested in Descendants<T>(child)) yield return nested;
        }
    }
    private static void SetField(DeckController controller, string name, object? value)
        => typeof(DeckController).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(controller, value);
    private static NativeBounds Bounds(nint hwnd)
    {
        var bounds = default(NativeBounds);
        Require(hwnd != 0 && GetWindowRect(hwnd, out bounds), "An actual owned HWND frame could not be measured.");
        return bounds;
    }
    private static void Require(bool value, string message) { if (!value) throw new IOException(message); }
    [StructLayout(LayoutKind.Sequential)]
    private struct NativeBounds
    {
        internal int Left, Top, Right, Bottom;
        internal readonly int Width => Right - Left;
        internal readonly int Height => Bottom - Top;
    }
    [DllImport("user32.dll")]
    private static extern nint SendMessage(nint hwnd, int message, nint wParam, nint lParam);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(nint hwnd, out NativeBounds bounds);
}
