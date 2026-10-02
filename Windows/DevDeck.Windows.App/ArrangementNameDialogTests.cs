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
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Owned synthetic windows/settings only; no actual tray prompt, worker, vault or browser action.
internal static class ArrangementNameDialogTests
{
    internal static async Task RunAsync(Application application,List<object> checks)
    {
        try {
            foreach (var language in DevDeck.Windows.Core.Localization.Languages) {
                Text.Use(language);
                NativeCheckProgress.Current?.Mark("arrangement.name."+language+".presentation");
                using (var scope=new Scope()) {
                    var dialog=scope.Dialog;
                    dialog.NameInput.ApplyTemplate(); dialog.SaveButton.ApplyTemplate(); dialog.CancelButton.ApplyTemplate();
                    Require(ReferenceEquals(dialog.Resources[typeof(TextBox)],SettingsStyles.TextBoxStyle)
                        && ReferenceEquals(dialog.Resources[typeof(Button)],SettingsStyles.ButtonStyle)
                        && dialog.NameInput.Template.FindName("field",dialog.NameInput) is Border field && field.CornerRadius==new CornerRadius(6)
                        && dialog.SaveButton.Template.FindName("frame",dialog.SaveButton) is Border saveFrame && saveFrame.CornerRadius==new CornerRadius(6)
                        && dialog.CancelButton.Template.FindName("frame",dialog.CancelButton) is Border cancelFrame && cancelFrame.CornerRadius==new CornerRadius(6),
                        "Ownerless tray name prompt does not use the exact shared rounded settings fallback styles.");
                    Require(dialog.Title==Text.L("arrangements.save.title") && dialog.Heading.Text==dialog.Title
                        && dialog.Detail.Text==Text.L("arrangements.save.detail") && dialog.Placeholder.Text==Text.L("arrangements.name.placeholder")
                        && AutomationProperties.GetName(dialog.NameInput)==Text.L("account.name")
                        && AutomationProperties.GetHelpText(dialog.NameInput)==dialog.Detail.Text
                        && AutomationProperties.GetName(dialog.SaveButton)==Text.L("button.save")
                        && AutomationProperties.GetName(dialog.CancelButton)==Text.L("button.cancel")
                        && dialog.SaveButton.IsDefault && dialog.CancelButton.IsCancel && dialog.NameInput.MaxLength==128,
                        "Arrangement prompt loses localized copy, accessible names or Return/Escape/input policy.");
                    checks.Add(new { name=language+".arrangement.name.presentation", localizedCopy=true, accessibleNameAndDetail=true, defaultSaveCancelEscape=true,
                        inputLimit128=true, exactSharedFallbackStyles=true, actualRoundedInputSaveAndCancelTemplates=true });
                }
                NativeCheckProgress.Current?.Mark("arrangement.name."+language+".invalid");
                using (var scope=new Scope()) {
                    var dialog=scope.Dialog;
                    foreach (var invalid in new[] { "", "   ", "\tDesk", "Desk\u0001day", new string('x',129) }) {
                        dialog.NameInput.Text=invalid;
                        Require(!dialog.SaveButton.IsEnabled && !dialog.TrySave() && dialog.SelectedName is null,
                            "Blank/control/oversized arrangement names enable Save or produce a result.");
                    }
                    dialog.NameInput.Text=" "; ((Window)dialog).Show(); dialog.UpdateLayout();
                    var enter=RaiseKey(dialog,Key.Return);
                    Require(enter.Handled && dialog.IsVisible && dialog.SelectedName is null && !dialog.SaveButton.IsEnabled,
                        "Invalid Return closes the arrangement prompt or returns an invalid name.");
                    dialog.NameInput.Text="Valid synthetic name";
                    Require(dialog.SaveButton.IsEnabled,"A corrected arrangement name does not enable Save.");
                    checks.Add(new { name=language+".arrangement.name.invalid", blanksControlsAndLengthRefused=true, invalidEnterKeepsPrompt=true, correctionEnablesSave=true });
                }
                NativeCheckProgress.Current?.Mark("arrangement.name."+language+".save");
                using (var scope=new Scope()) {
                    var dialog=scope.Dialog; dialog.NameInput.Text="  Synthetic workday  ";
                    ((Window)dialog).Show(); dialog.UpdateLayout(); dialog.SaveButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                    Require(dialog.SelectedName=="Synthetic workday" && !dialog.IsVisible,
                        "Explicit Save does not trim and return the arrangement name without another dialog.");
                    checks.Add(new { name=language+".arrangement.name.trimmedSave", actualClickPath=true, trimmedName=true, promptClosed=true });
                }
                NativeCheckProgress.Current?.Mark("arrangement.name."+language+".enter");
                using (var scope=new Scope()) {
                    var dialog=scope.Dialog; dialog.NameInput.Text="  Keyboard workday  "; ((Window)dialog).Show(); dialog.Activate(); dialog.UpdateLayout();
                    await Dispatcher.Yield(DispatcherPriority.Background);
                    Require(dialog.NameInput.IsKeyboardFocused,"Arrangement input is not the initial keyboard target.");
                    var enter=RaiseKey(dialog,Key.Return);
                    Require(enter.Handled && dialog.SelectedName=="Keyboard workday" && !dialog.IsVisible,
                        "Return from the name field differs from the explicit Save result.");
                    checks.Add(new { name=language+".arrangement.name.enter", inputInitiallyFocused=true, routedReturnPath=true, sameTrimmedResult=true });
                }
                NativeCheckProgress.Current?.Mark("arrangement.name."+language+".cancel");
                using (var scope=new Scope()) {
                    var dialog=scope.Dialog; dialog.NameInput.Text="Unsaved synthetic name"; ((Window)dialog).Show(); dialog.UpdateLayout();
                    dialog.CancelButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                    Require(dialog.SelectedName is null && !dialog.IsVisible,"Cancel returns an unsaved arrangement name.");
                    using var escapeScope=new Scope(); var escape=escapeScope.Dialog;
                    escape.NameInput.Text="Another unsaved name"; ((Window)escape).Show(); escape.UpdateLayout();
                    var args=RaiseKey(escape,Key.Escape);
                    Require(args.Handled && escape.SelectedName is null && !escape.IsVisible,"Escape differs from Cancel or saves the current name.");
                    checks.Add(new { name=language+".arrangement.name.cancel", clickAndEscapeReturnNull=true, noControllerOrPersistence=true });
                }
                NativeCheckProgress.Current?.Mark("arrangement.name."+language+".layout");
                var owner=new Window { Title="Synthetic arrangement style owner", Width=550, Height=320, ShowInTaskbar=false, Topmost=false };
                var textStyle=new Style(typeof(TextBox)); textStyle.Setters.Add(new Setter(Control.BorderBrushProperty,Brushes.SlateGray));
                var buttonStyle=new Style(typeof(Button)); buttonStyle.Setters.Add(new Setter(Control.BorderBrushProperty,Brushes.SlateGray));
                owner.Resources[typeof(TextBox)]=textStyle; owner.Resources[typeof(Button)]=buttonStyle;
                try {
                    owner.Show(); owner.UpdateLayout();
                    foreach (var size in new[] { 13d, 19.5d, 26d }) {
                        using var scope=new Scope(owner); var dialog=scope.Dialog; dialog.FontSize=size; ((Window)dialog).Show(); dialog.UpdateLayout();
                        Require(dialog.Owner==owner && !dialog.Topmost && !dialog.ShowInTaskbar && dialog.ResizeMode==ResizeMode.NoResize
                            && dialog.WindowStyle==WindowStyle.ToolWindow && dialog.WindowStartupLocation==WindowStartupLocation.CenterOwner
                            && ReferenceEquals(dialog.NameInput.Style,textStyle) && ReferenceEquals(dialog.SaveButton.Style,buttonStyle),
                            "Arrangement prompt ignores its existing owner/style or forces normal settings topmost.");
                        var content=(FrameworkElement)dialog.Content;
                        foreach (var control in new FrameworkElement[] { dialog.Heading, dialog.Detail, dialog.NameInput, dialog.SaveButton, dialog.CancelButton }) {
                            var point=control.TranslatePoint(new Point(0,0),content);
                            Require(control.ActualWidth>0 && control.ActualHeight>0 && point.X>=-1 && point.Y>=-1
                                && point.X+control.ActualWidth<=content.ActualWidth+1 && point.Y+control.ActualHeight<=content.ActualHeight+1,
                                "Arrangement prompt clips title/detail/input/buttons at a supported enlarged font: "+language);
                        }
                    }
                    checks.Add(new { name=language+".arrangement.name.layout", ownerTopmostInherited=true, existingStylesReused=true,
                        autoHeightAndWrappedDetail=true, fieldsAndButtonsFitAtThreeFonts=true });
                } finally { owner.Close(); }
                NativeCheckProgress.Current?.Mark("arrangement.name."+language+".deck");
                await DeckChecksAsync(application,language,checks);
                NativeCheckProgress.Current?.Mark("arrangement.name."+language+".deckModes");
                await DeckModesAsync(application,language,checks);
            }
        } finally { Text.Use("en"); }
    }
    private static async Task DeckModesAsync(Application application,string language,List<object> checks)
    {
        using var fixture=new DeckFixture(application,language,notifications:true,localFolder:true);
        await fixture.Window.SelectPageAsync("deck");
        typeof(DeckController).GetMethod("RebuildCards",BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(fixture.Controller,null);
        var card=fixture.Controller.AllLocalViews.Single();
        card.ApplySnapshot(new(card.Reference.Id,"running","synthetic/main","http://localhost:4321","Synthetic modes only",null));
        var handle=new WindowInteropHelper(card).EnsureHandle(); var snapshot=card.Latest;
        var floating=Field<CheckBox>(fixture.Window,"deckFloating"); var locked=Field<CheckBox>(fixture.Window,"deckLocked");
        var name=Field<TextBox>(fixture.Window,"arrangementName"); var choices=Field<ComboBox>(fixture.Window,"arrangements");
        choices.SelectedItem="Morning"; name.Text="Retained mode-switch draft";
        fixture.Window.Show(); fixture.Window.Activate(); fixture.Window.UpdateLayout(); name.Focus(); name.Select(3,7);
        await Dispatcher.Yield(DispatcherPriority.Background);
        Require(name.IsKeyboardFocused,"The synthetic deck name must own focus before native mode changes.");
        var signal=new AttentionItem("mode-signal","mode-signal","needsFixing","project","Synthetic mode signal","Synthetic",1,
            new("showCard",CardID:"arc.synthetic"),true,false);
        DeckAlert Alert(string id)=>new(id,"wentDown","project",id,"Synthetic",id,id,new("showCard",CardID:"arc.synthetic"),false);
        const string scope="local:Test Linux";
        fixture.Controller.ObserveAttention(new AttentionSnapshot(scope,[signal],[]));
        fixture.Controller.ObserveAttention(new AttentionSnapshot(scope,[signal],[Alert("mode-queued")]));
        typeof(DeckController).GetMethod("FlushNotifications",BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(fixture.Controller,null);
        fixture.Controller.ObserveAttention(new AttentionSnapshot(scope,[signal],[Alert("mode-pending")]));
        Field<DispatcherTimer>(fixture.Controller,"notificationBatch").Stop();
        var queued=Field<System.Collections.IEnumerable>(fixture.Controller,"deliveries").Cast<object>().ToArray();
        var pending=Field<System.Collections.IEnumerable>(fixture.Controller,"pendingAlerts").Cast<object>().ToArray();
        Require(queued.Length==1 && pending.Length==1,"The mode test must start with actual nonempty queued and pending notification sources.");
        var clock=fixture.Controller.LastCheckedAt; var before=fixture.Controller.Settings; var page=fixture.Window.Page.Content;
        var navigation=fixture.Window.Navigation.Items.Cast<object>().ToArray();
        var gate=Field<SemaphoreSlim>(fixture.Controller,"actions"); await gate.WaitAsync();
        try {
            floating.IsChecked=true; floating.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
            locked.IsChecked=true; locked.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
            var saved=fixture.Store.Load();
            Require(saved.Floating && saved.Locked && fixture.Controller.Settings.Floating && fixture.Controller.Settings.Locked
                && floating.IsChecked==true && locked.IsChecked==true,
                "Actual Deck floating/lock clicks wait for the unrelated lifecycle gate or fail precise persistence.");
            fixture.Controller.SetFloating(false); fixture.Controller.SetLocked(false);
            Require(floating.IsChecked==false && locked.IsChecked==false && !fixture.Store.Load().Floating && !fixture.Store.Load().Locked
                && ReferenceEquals(page,fixture.Window.Page.Content) && name.Text=="Retained mode-switch draft" && choices.SelectedItem as string=="Morning"
                && name.IsKeyboardFocused && name.SelectionStart==3 && name.SelectionLength==7
                && navigation.SequenceEqual(fixture.Window.Navigation.Items.Cast<object>()) && fixture.Window.SelectedPage=="deck"
                && fixture.Controller.LastCheckedAt==clock && fixture.Controller.Settings.AnnouncedAlerts.SequenceEqual(before.AnnouncedAlerts)
                && Field<AttentionTracker>(fixture.Controller,"attention").SignalItems.SequenceEqual(new[] { signal })
                && queued.SequenceEqual(Field<System.Collections.IEnumerable>(fixture.Controller,"deliveries").Cast<object>())
                && pending.SequenceEqual(Field<System.Collections.IEnumerable>(fixture.Controller,"pendingAlerts").Cast<object>())
                && ReferenceEquals(card,fixture.Controller.AllLocalViews.Single()) && new WindowInteropHelper(card).Handle==handle
                && ReferenceEquals(card.Latest,snapshot) && SameOutsideArrangements(before,fixture.Store.Load())
                && !fixture.Controller.LocalPollEnabled && Field<object?>(fixture.Controller,"tray") is null,
                "Deck mode changes reset clock/Seen/attention/queues/HWND/snapshot or external reconciliation loses draft/focus/selection.");
        } finally { gate.Release(); }
        checks.Add(new { name=language+".arrangement.settings.deckModes", actualFloatingAndLockedClicksBypassLifecycleGate=true,
            externalModeChangesReconciledInPlace=true, draftFocusSelectionAndNavigationRetained=true,
            clockSeenAttentionPendingAndQueuedSourcesRetained=true, sameNativeOwnerHwndAndSnapshot=true, noWorkerTrayOrPoll=true });
    }
    private static async Task DeckChecksAsync(Application application,string language,List<object> checks)
    {
        using (var fixture=new DeckFixture(application,language)) {
            await fixture.Window.SelectPageAsync("deck");
            var name=Field<TextBox>(fixture.Window,"arrangementName"); var choices=Field<ComboBox>(fixture.Window,"arrangements");
            choices.SelectedItem="Morning"; name.Text="Unsaved arrangement name";
            var drafts=Field<Dictionary<string,string>>(fixture.Window,"tokenDrafts"); drafts["synthetic.account"]="window-only synthetic token";
            fixture.Window.Show(); fixture.Window.Activate(); fixture.Window.UpdateLayout(); name.Focus(); name.Select(3,7);
            await Dispatcher.Yield(DispatcherPriority.Background);
            Require(name.IsKeyboardFocused,"The synthetic arrangement draft must own focus before an external save.");
            var page=fixture.Window.Page.Content; var navigation=fixture.Window.Navigation.Items.Cast<object>().ToArray();
            var clock=Field<DateTimeOffset?>(fixture.Controller,"lastCheckedAt");
            fixture.Controller.SaveArrangement("External synthetic arrangement");
            Require(choices.Items.Cast<string>().Contains("External synthetic arrangement") && choices.SelectedItem as string=="Morning"
                && ReferenceEquals(page,fixture.Window.Page.Content) && Field<TextBox>(fixture.Window,"arrangementName")==name
                && name.Text=="Unsaved arrangement name" && name.IsKeyboardFocused && name.SelectionStart==3 && name.SelectionLength==7
                && fixture.Window.SelectedPage=="deck" && navigation.SequenceEqual(fixture.Window.Navigation.Items.Cast<object>())
                && drafts["synthetic.account"]=="window-only synthetic token" && Field<DateTimeOffset?>(fixture.Controller,"lastCheckedAt")==clock,
                "External arrangement reconciliation reloads the deck, loses selection/draft/focus, or resets unrelated state.");
            checks.Add(new { name=language+".arrangement.settings.reconcile", externalSaveListed=true, currentSelectionRetained=true,
                samePageAndControls=true, draftCursorAndFocusRetained=true, navigationTokenAndClockRetained=true });
        }
        using (var fixture=new DeckFixture(application,language)) {
            await fixture.Window.SelectPageAsync("deck");
            var name=Field<TextBox>(fixture.Window,"arrangementName"); var choices=Field<ComboBox>(fixture.Window,"arrangements");
            var save=Field<Button>(fixture.Window,"saveArrangement"); var apply=Field<Button>(fixture.Window,"applyArrangement");
            var forget=Field<Button>(fixture.Window,"forgetArrangement");
            Require(!save.IsEnabled && !apply.IsEnabled && !forget.IsEnabled,"Arrangement actions are enabled without a name/selection.");
            foreach (var invalid in new[] { " ", "Desk\u0001day", new string('x',129) }) {
                name.Text=invalid; Require(!save.IsEnabled,"Invalid arrangement names enable the deck Save button.");
            }
            choices.SelectedItem="Evening";
            Require(apply.IsEnabled && forget.IsEnabled && AutomationProperties.GetName(forget)==Text.L("arrangements.forget","Evening"),
                "The explicit Forget control is not tied to the selected saved name.");
            var before=fixture.Controller.Settings; var clock=Field<DateTimeOffset?>(fixture.Controller,"lastCheckedAt");
            var gate=Field<SemaphoreSlim>(fixture.Controller,"actions"); await gate.WaitAsync();
            try {
                name.Text="  morning  "; save.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                var saved=fixture.Store.Load();
                Require(saved.ArrangementList.Length==2 && saved.ArrangementList[0].Name=="Morning"
                    && saved.ArrangementList[0].Cards.Single().X==before.Cards[0].X && name.Text=="  morning  "
                    && choices.SelectedItem as string=="Evening" && save.IsEnabled,
                    "Deck Save uses the global action gate, fails trimmed overwrite identity/order, or rewrites the name draft.");
                forget.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                saved=fixture.Store.Load();
                Require(saved.ArrangementList.Select(item=>item.Name).SequenceEqual(new[] { "Morning" })
                    && choices.SelectedItem is null && !apply.IsEnabled && !forget.IsEnabled
                    && SameOutsideArrangements(before,saved) && Field<DateTimeOffset?>(fixture.Controller,"lastCheckedAt")==clock,
                    "Selected Forget resets unrelated metadata/clock or leaves selection-dependent actions enabled after finally.");
            } finally { gate.Release(); }
            checks.Add(new { name=language+".arrangement.settings.saveForget", blankControlAndLengthDisabled=true,
                actualClicksBypassLifecycleGate=true, trimmedOverwriteKeepsNameAndIndex=true, selectedForgetOnly=true,
                eligibilityAfterFinally=true, noGlobalMetadataOrClockReset=true });
        }
        using (var fixture=new DeckFixture(application,language)) {
            await fixture.Window.SelectPageAsync("deck");
            var name=Field<TextBox>(fixture.Window,"arrangementName"); var choices=Field<ComboBox>(fixture.Window,"arrangements");
            var apply=Field<Button>(fixture.Window,"applyArrangement"); name.Text="Keep this apply draft"; choices.SelectedItem="Morning";
            var page=fixture.Window.Page.Content; var clock=Field<DateTimeOffset?>(fixture.Controller,"lastCheckedAt");
            var gate=Field<SemaphoreSlim>(fixture.Controller,"actions"); await gate.WaitAsync();
            try {
                apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                var card=fixture.Store.Load().Cards.Single();
                Require(!card.Enabled && card.Collapsed && card.X==64 && card.Y==80 && fixture.Controller.Settings.ArrangementMatches("Morning")
                    && ReferenceEquals(page,fixture.Window.Page.Content) && name.Text=="Keep this apply draft" && choices.SelectedItem as string=="Morning"
                    && apply.IsEnabled && Field<DateTimeOffset?>(fixture.Controller,"lastCheckedAt")==clock,
                    "Deck Apply waits for generic settings save or loses scoped placement/visibility/compact, draft, selection, or clock.");
            } finally { gate.Release(); }
            checks.Add(new { name=language+".arrangement.settings.apply", actualClickBypassesLifecycleGate=true,
                selectedVisibilityCompactAndPlacementApplied=true, preciseControllerPath=true, samePageDraftSelectionAndClock=true });
        }
        using (var fixture=new DeckFixture(application,language)) {
            var form=new AccountSettingsForm(fixture.Controller,null,live:false,_=>{});
            SetField(fixture.Window,"form",form); SetField(fixture.Window,"selected","new-account"); fixture.Window.Page.Content=form;
            form.TokenDraft="unsaved synthetic credential";
            var label=Field<TextBox>(form,"label"); label.Text="Unsaved account caption";
            var message=Field<TextBlock>(form,"Message",typeof(SettingsForm)); message.Text="Current synthetic row error";
            fixture.Window.Show(); fixture.Window.Activate(); fixture.Window.UpdateLayout(); label.Focus(); label.Select(2,6);
            await Dispatcher.Yield(DispatcherPriority.Background);
            Require(label.IsKeyboardFocused,"The synthetic account draft must own focus before arrangement reconciliation.");
            var page=fixture.Window.Page.Content; var navigation=fixture.Window.Navigation.Items.Cast<object>().ToArray();
            fixture.Controller.SaveArrangement("External account-safe arrangement"); fixture.Controller.ForgetArrangement("Morning");
            await fixture.Controller.ApplyArrangementAsync("Evening");
            Require(ReferenceEquals(page,fixture.Window.Page.Content) && fixture.Window.SelectedPage=="new-account"
                && navigation.SequenceEqual(fixture.Window.Navigation.Items.Cast<object>()) && form.IsEnabled
                && form.TokenDraft=="unsaved synthetic credential" && label.Text=="Unsaved account caption"
                && label.IsKeyboardFocused && label.SelectionStart==2 && label.SelectionLength==6 && message.Text=="Current synthetic row error",
                "Arrangement Save/Forget/Apply refreshes a different page or loses its caption/token/error/focus draft.");
            checks.Add(new { name=language+".arrangement.settings.otherPage", saveForgetApplyKeepCurrentForm=true,
                tokenCaptionErrorCursorAndFocusRetained=true, navigationUnchanged=true, noDiscoveryVaultOrWorker=true });
        }
    }
    private static bool SameOutsideArrangements(DeckSettings left,DeckSettings right) =>
        System.Text.Json.JsonSerializer.Serialize(left with { Arrangements=null },WorkerProtocol.Json)==System.Text.Json.JsonSerializer.Serialize(right with { Arrangements=null },WorkerProtocol.Json);
    private static T Field<T>(object target,string name,Type? declaringType=null) =>
        (T)(declaringType ?? target.GetType()).GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(target)!;
    private static void SetField(object target,string name,object? value) => target.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(target,value);
    private sealed class DeckFixture : IDisposable
    {
        private readonly string path=Path.Combine(Path.GetTempPath(),"devdeck-arrangement-settings-"+Guid.NewGuid().ToString("N")+".json");
        internal SettingsStore Store { get; }
        internal DeckController Controller { get; }
        internal SettingsWindow Window { get; }
        internal DeckFixture(Application application,string language,bool notifications=false,bool localFolder=false)
        {
            Store=new(path);
            var settings=new DeckSettings(1,localFolder?[new("Test Linux","/tmp/devdeck-arrangement-mode-runtime")]:[],
                [new(new("arc.synthetic","Test Linux","arc",localFolder?"/tmp/devdeck-arrangement-mode-project":"",Arc:new("synthetic","site")),"Synthetic hosted Arc",X:120,Y:180)],
                Language:language, Notifications:notifications, SeenAlerts:["synthetic.retained.seen"], RefreshSeconds:120,
                Arrangements:[new("Morning",[new("arc.synthetic",64,80,false,true)]),new("Evening",[new("arc.synthetic",240,80,true,false)])]);
            Store.Save(settings); Controller=new(application,Store,live:false); Window=new(Controller,live:true);
            SetField(Controller,"settingsWindow",Window); SetField(Controller,"lastCheckedAt",(DateTimeOffset?)new DateTimeOffset(2026,10,2,12,0,0,TimeSpan.Zero));
        }
        public void Dispose()
        {
            if (Window.Page.Content is SettingsForm form) form.Dispose();
            SetField(Window,"allowingClose",true); Window.Close(); SetField(Controller,"settingsWindow",null); Controller.CloseViews();
            foreach (var file in new[] { path,path+".bak" }) if (File.Exists(file)) File.Delete(file);
        }
    }
    private static KeyEventArgs RaiseKey(ArrangementNameDialog dialog,Key key)
    {
        var args=new KeyEventArgs(Keyboard.PrimaryDevice,PresentationSource.FromVisual(dialog)!,Environment.TickCount,key) { RoutedEvent=Keyboard.PreviewKeyDownEvent };
        dialog.NameInput.RaiseEvent(args); return args;
    }
    private static void Require(bool condition,string message) { if (!condition) throw new IOException(message); }
    private sealed class Scope : IDisposable
    {
        internal ArrangementNameDialog Dialog { get; }
        internal Scope(Window? owner=null) { Dialog=new(owner); if (owner is null) Dialog.Topmost=false; }
        public void Dispose()=>Dialog.Close();
    }
}
