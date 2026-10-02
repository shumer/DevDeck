using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Offline native settings checks. Every reader, verifier and browser catalog below is synthetic.
internal static class SettingsCheckTests
{
    internal static async Task RunAsync(Application application, DeckController controller, List<object> checks)
    {
        foreach (var language in DevDeck.Windows.Core.Localization.Languages) {
            Text.Use(language);
            await QuietMetadataAsync(controller, language, checks);
            await CheckRowsAsync(language, checks);
            await ProjectFormsAsync(controller, language, checks);
            CheckBrowsers(language, checks);
        }
        Text.Use("en");
    }

    private static async Task QuietMetadataAsync(DeckController controller, string language, List<object> checks)
    {
        using (var form = new MetadataForm(controller)) {
            using var scope = new Scope(new Window { Content=form, Width=680, Height=300 }); scope.Window.Show(); scope.Window.Activate(); scope.Window.UpdateLayout();
            var first = new TaskCompletionSource(); var second = new TaskCompletionSource();
            form.Saves.Enqueue(() => first.Task); form.Saves.Enqueue(() => second.Task);
            form.Token.Password="synthetic-unpersisted-token"; form.Input.Text="first metadata";
            form.Input.Focus(); form.Input.Select(2,4);
            var flush = form.FlushAsync();
            Require(form.IsEnabled && form.Input.IsKeyboardFocused && form.Input.SelectionStart==2 && form.Input.SelectionLength==4 && !flush.IsCompleted, "Quiet autosave disables the form or moves its cursor.");
            checks.Add(new { name=language+".settings.quietSave.editable", delayedFakePersistence=true, formEnabled=true, focusAndCursorRetained=true, noWorkerOrVault=true });
            var concurrent = form.FlushAsync(); form.Input.Text="second metadata"; form.Input.Select(3,2);
            first.SetResult(); await Dispatcher.Yield(DispatcherPriority.Background);
            Require(form.Values.SequenceEqual(new[] { "first metadata", "second metadata" }) && !flush.IsCompleted && !concurrent.IsCompleted && form.IsEnabled, "Concurrent flush returns before the later edit has finished saving.");
            second.SetResult(); await Task.WhenAll(flush, concurrent);
            Require(form.MessageText.Length==0 && form.Input.IsKeyboardFocused && form.Input.SelectionStart==3 && form.Input.SelectionLength==2 && form.Token.Password=="synthetic-unpersisted-token", "Quiet persistence changes the draft/cursor or displays a generic Saved response.");
            checks.Add(new { name=language+".settings.quietSave.concurrentEdits", bothWaitLatestSave=true, serializedOnlyTwoWrites=true, noSavedMessage=true, tokenDraftAndCursorRetained=true });
        }
        using (var form = new MetadataForm(controller)) {
            var first = new TaskCompletionSource(); var second = new TaskCompletionSource();
            form.Saves.Enqueue(() => first.Task); form.Saves.Enqueue(() => second.Task);
            form.Input.Text="stale metadata"; var flush=form.FlushAsync(); form.Input.Text="current metadata";
            form.Answer("Current row answer"); first.SetException(new InvalidOperationException("Synthetic old metadata refused."));
            await Dispatcher.Yield(DispatcherPriority.Background);
            Require(form.Values.Count==2 && form.MessageText=="Current row answer" && form.IsEnabled, "A late error for old metadata overwrites the newer row answer.");
            var error=new InvalidOperationException("Synthetic current metadata refused."); second.SetException(error); await flush;
            Require(form.MessageText==Text.Failure(error) && form.MessageBrush==Brushes.Firebrick && form.Input.Text=="current metadata" && form.HasUncommittedChanges, "Current metadata validation does not retain the unsaved draft and show its own error.");
            checks.Add(new { name=language+".settings.quietSave.revisionErrors", staleErrorIgnored=true, currentErrorDisplayed=true, currentDraftRetained=true, invalidDraftRemainsUncommitted=true });
            form.Input.Text="corrected metadata"; await form.FlushAsync();
            Require(form.MessageText.Length==0 && !form.HasUncommittedChanges, "Successful correction leaves the previous metadata error/unsaved flag or replaces it with Saved.");
            checks.Add(new { name=language+".settings.quietSave.correction", oldErrorCleared=true, noGenericSaved=true, correctedDraftCommitted=true });
        }
        using (var form = new MetadataForm(controller)) {
            var delayed=new TaskCompletionSource(); form.Saves.Enqueue(() => delayed.Task); form.Input.Text="pending metadata"; var flush=form.FlushAsync();
            form.Answer("Answer at disposal"); form.Dispose(); delayed.SetException(new InvalidOperationException("Synthetic late closed-form error.")); await flush;
            Require(form.MessageText=="Answer at disposal" && form.Values.Count==1, "A disposed form receives a late metadata answer or starts another save.");
            checks.Add(new { name=language+".settings.quietSave.disposal", lateAnswerIgnored=true, noLaterSave=true });
        }
        using (var form = new MetadataForm(controller)) {
            await form.ExplicitAsync(() => { form.Answer(Text.L("token.works")); return Task.CompletedTask; });
            Require(form.MessageText==Text.L("token.works") && form.IsEnabled, "Explicit verification answer is overwritten by a generic Saved message.");
            checks.Add(new { name=language+".settings.quietSave.explicitAnswer", actionSpecificTextRetained=true, noGenericSaved=true, fakeActionOnly=true });
        }
    }

    private static ProjectStatus Status(ProjectReference reference, string state, string detail, string tone="good") =>
        new(reference.Id,"running",null,null,null,null,CheckSummary:new(tone,state,detail),CheckedAt:42);

    private static async Task CheckRowsAsync(string language, List<object> checks)
    {
        var original = new ProjectReference("project.settings.check","Ubuntu-24.04","local","/tmp/synthetic-settings","npm run dev",HealthURL:"http://localhost:4112/health",OpenURL:"http://localhost:4112/front");
        foreach (var tone in new[] { "good", "bad", "busy", "idle" }) {
            using var row=new ProjectCheckRow(() => original, (reference,_) => Task.FromResult(Status(reference,"Synthetic state "+tone,"Synthetic detail "+tone,tone)),CancellationToken.None);
            Require(row.State==Text.L("check.notChecked.yet") && row.CheckButton.IsEnabled, "Configured project does not begin with an available unchecked row.");
            await row.CheckOnArrivalAsync();
            var color=Descendants<TextBlock>(row).Single(label => label.Text==row.State).Foreground;
            var expected=tone switch { "good"=>Brushes.ForestGreen,"bad"=>Brushes.Firebrick,"busy"=>Brushes.DarkGoldenrod,_=>Brushes.DimGray };
            Require(row.State=="Synthetic state "+tone && row.Detail=="Synthetic detail "+tone && color==expected && row.CheckButton.IsEnabled, "Settings check does not use the worker's scoped summary/tone.");
            checks.Add(new { name=language+".settings.check.summary."+tone, workerSummaryRetained=true, toneRetained=true, arrivalReadOnly=true });
        }
        {
            var pending=new Queue<TaskCompletionSource<ProjectStatus>>(); var first=new TaskCompletionSource<ProjectStatus>(); var second=new TaskCompletionSource<ProjectStatus>(); pending.Enqueue(first); pending.Enqueue(second);
            var tokens=new List<CancellationToken>();
            using var row=new ProjectCheckRow(() => original, (_,token) => { tokens.Add(token); return pending.Dequeue().Task; },CancellationToken.None);
            var old=row.CheckAsync(); var current=row.CheckAsync();
            Require(tokens.Count==2 && tokens[0].IsCancellationRequested && row.State==Text.L("token.checking") && !row.CheckButton.IsEnabled, "A newer settings check does not cancel/supersede the old request.");
            second.SetResult(Status(original,"Current healthy state","Newest answer")); await current;
            first.SetResult(Status(original,"Stale failure state","Old answer","bad")); await old;
            Require(row.State=="Current healthy state" && row.Detail=="Newest answer" && row.CheckButton.IsEnabled, "An older settings check replaces the newest answer.");
            checks.Add(new { name=language+".settings.check.latestRequest", canceledOldRead=true, newestAnswerWins=true, delayedFakeReader=true });
        }
        foreach (var field in new[] { "id", "distribution", "folder", "health", "command", "kind", "arcURL", "arcHealth" }) {
            ProjectReference? current=field.StartsWith("arc",StringComparison.Ordinal) ? original with { Kind="arc",Arc=new("example","news","http://localhost:5112/front","/release") } : original;
            var captured=current!; var pending=new TaskCompletionSource<ProjectStatus>(); CancellationToken canceled=default;
            using var row=new ProjectCheckRow(() => current, (_,token) => { canceled=token; return pending.Task; },CancellationToken.None);
            var old=row.CheckAsync(); current=field switch {
                "id" => current with { Id="project.new.identity" }, "distribution" => current with { Distribution="Debian" },
                "folder" => current with { Path="/tmp/new-synthetic" }, "health" => current with { HealthURL="http://localhost:4223/ready" },
                "command" => current with { StartCommand="bun run dev" }, "kind" => current with { Kind="arc",Arc=new("example","news","http://localhost:5112/front","/release") },
                "arcURL" => current with { Arc=current.Arc! with { LocalURL="http://localhost:5223/front" } },
                _ => current with { Arc=current.Arc! with { HealthPath="/new-health" } }
            };
            row.RefreshIdentity(autoCheck:false); pending.SetResult(Status(captured,"Stale identity answer","Must not appear")); await old;
            Require(canceled.IsCancellationRequested && row.State==Text.L("check.notChecked.yet") && row.Detail.Length==0 && row.CheckButton.IsEnabled, "A settings answer is painted after its "+field+" changed.");
            checks.Add(new { name=language+".settings.check.identity."+field, changedIdentityCancels=true, noStalePaint=true, newIdentityUnchecked=true });
        }
        {
            ProjectReference? current=original; var pending=new TaskCompletionSource<ProjectStatus>();
            using var row=new ProjectCheckRow(() => current, (_,_) => pending.Task,CancellationToken.None);
            using var scope=new Scope(new Window { Content=row,Width=650,Height=180 }); scope.Window.Show(); scope.Window.UpdateLayout();
            row.CheckButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Require(!row.CheckButton.IsEnabled, "Actual Check click does not remain disabled during its request.");
            current=null; row.RefreshIdentity(autoCheck:false); pending.SetResult(Status(original,"Late previous project","Ignored"));
            await Dispatcher.Yield(DispatcherPriority.Background);
            Require(row.State==Text.L("project.notConfigured") && row.Detail==Text.L("project.notConfigured.detail") && !row.CheckButton.IsEnabled, "A late actual Check-button completion re-enables an invalid project row.");
            checks.Add(new { name=language+".settings.check.invalidAfterClick", actualButtonClick=true, invalidIdentityRetainsExplanation=true, lateCompletionCannotEnable=true });
        }
        {
            var pending=new TaskCompletionSource<ProjectStatus>(); using var row=new ProjectCheckRow(() => original, (_,_) => pending.Task,CancellationToken.None);
            var check=row.CheckAsync(); pending.SetResult(Status(original with { Id="wrong-project" },"Foreign answer","Ignored")); await check;
            Require(row.State==Text.L("windows.refreshFailed") && row.Detail.Length>0 && row.CheckButton.IsEnabled && row.Detail!="Ignored", "A foreign worker project ID is rendered as a valid check.");
            checks.Add(new { name=language+".settings.check.responseIdentity", foreignProjectRejected=true, ownRowError=true });
        }
        {
            var first=new TaskCompletionSource<ProjectStatus>(); var second=new TaskCompletionSource<ProjectStatus>(); var reads=0;
            using var row=new ProjectCheckRow(() => original, (_,_) => ++reads==1 ? first.Task : second.Task,CancellationToken.None);
            var old=row.CheckAsync(); var latest=row.CheckAsync(); second.SetResult(Status(original,"Current success","Scoped good answer")); await latest;
            first.SetException(new InvalidOperationException("Synthetic stale read failure.")); await old;
            Require(row.State=="Current success" && row.Detail=="Scoped good answer" && row.CheckButton.IsEnabled, "A stale error overwrites the current settings answer.");
            checks.Add(new { name=language+".settings.check.staleFailure", newerSuccessRetained=true, lateErrorIgnored=true });
        }
        {
            var pending=new TaskCompletionSource<ProjectStatus>(); CancellationToken token=default;
            using var row=new ProjectCheckRow(() => original, (_,cancellation) => { token=cancellation;return pending.Task; },CancellationToken.None);
            var check=row.CheckAsync(); var before=row.State; row.Dispose(); pending.SetResult(Status(original,"Late disposed answer","Ignored")); await check;
            Require(token.IsCancellationRequested && row.State==before && row.Detail.Length==0 && !row.CheckButton.IsEnabled, "A disposed settings row repaints or leaves an actionable Check button.");
            await row.CheckAsync();
            Require(row.State==before, "A disposed settings row starts a new read.");
            checks.Add(new { name=language+".settings.check.disposal", inFlightCanceled=true, noLatePaint=true, checkStaysDisabled=true });
        }
        {
            var pending=new TaskCompletionSource<ProjectStatus>(); using var lifetime=new CancellationTokenSource(); CancellationToken token=default;
            using var row=new ProjectCheckRow(() => original, (_,cancellation) => { token=cancellation;return pending.Task; },lifetime.Token);
            var check=row.CheckAsync(); var before=row.State; lifetime.Cancel(); pending.SetResult(Status(original,"Canceled lifetime answer","Ignored")); await check;
            Require(token.IsCancellationRequested && row.State==before && row.Detail.Length==0, "A canceled form lifetime still paints its pending settings check.");
            checks.Add(new { name=language+".settings.check.lifetime", linkedCancellation=true, noCanceledAnswer=true });
        }
        {
            var reads=0; using var unconfigured=new ProjectCheckRow(() => null, (reference,_) => { reads++; return Task.FromResult(Status(reference,"No read","Ignored")); },CancellationToken.None);
            using var unavailable=new ProjectCheckRow(() => original,null,CancellationToken.None);
            await unconfigured.CheckAsync(); await unavailable.CheckOnArrivalAsync();
            Require(reads==0 && !unconfigured.CheckButton.IsEnabled && unconfigured.State==Text.L("project.notConfigured") && !unavailable.CheckButton.IsEnabled && unavailable.State==Text.L("check.notChecked.yet"), "A missing reference/reader starts a settings check or enables its button.");
            checks.Add(new { name=language+".settings.check.noSource", missingReferenceOrReaderDisabled=true, noRead=true });
        }
    }

    private static async Task ProjectFormsAsync(DeckController controller, string language, List<object> checks)
    {
        foreach (var kind in new[] { "local", "arc", "ddev" }) {
            var card=controller.Settings.Cards[0] with { Project=controller.Settings.Cards[0].Project with {
                Kind=kind,StartCommand=kind=="local" ? "npm run dev" : null,HealthURL=kind=="local" ? "http://localhost:4112/ready" : null,
                OpenURL=kind=="local" ? "http://localhost:4112/front" : null,Arc=kind=="arc" ? new("example","news","http://localhost:5112/front","/release") : null } };
            var references=new List<ProjectReference>();
            using var form=new ProjectSettingsForm(controller,card,live:false,_ => { },checker:(reference,_) => { references.Add(reference);return Task.FromResult(Status(reference,"Synthetic configured check","Scoped row")); });
            using var scope=new Scope(new Window { Content=new ScrollViewer { Content=form },Width=1000,Height=780 }); scope.Window.Show(); scope.Window.UpdateLayout();
            await form.HealthCheck.CheckOnArrivalAsync();
            if (kind=="ddev") Require(references.Count==0 && !form.HealthCheck.IsVisible && !form.HealthCheck.CheckButton.IsEnabled, "DDEV form exposes an unrelated health checker or starts a check.");
            else {
                Require(references.Count>0 && form.HealthCheck.IsVisible && form.HealthCheck.State=="Synthetic configured check" && references.All(reference => reference.Id==card.Project.Id && reference.Path==card.Project.Path && reference.Kind==kind && reference.Distribution==card.Project.Distribution), "Local/Arc form loses its stable identity or hides the scoped health result.");
                var reference=references[^1];
                if(kind=="local") Require(reference.HealthURL=="http://localhost:4112/ready" && reference.OpenURL is null, "Local check uses opening URL instead of readiness URL.");
                else Require(reference.Arc is { LocalURL:"http://localhost:5112/front",HealthPath:"/release" }, "Arc settings check loses its configured origin/health path.");
            }
            checks.Add(new { name=language+".settings.check.form."+kind, visibleOnlyWhereRelevant=true, identityAndSourceRetained=true, fakeReaderOnly=true });
        }
        {
            var card=controller.Settings.Cards[0] with { Project=new("arc.hosted.synthetic","","arc","",Arc:new("example","news")) };
            var reads=0; using var form=new ProjectSettingsForm(controller,card,live:false,_ => { },checker:(reference,_) => { reads++;return Task.FromResult(Status(reference,"Unexpected","Ignored")); });
            await form.HealthCheck.CheckOnArrivalAsync();
            Require(reads==0 && form.HealthCheck.State==Text.L("project.notConfigured") && !form.HealthCheck.CheckButton.IsEnabled && form.CreateDraft().Project.Id==card.Project.Id, "Hosted-only Arc checks a missing folder or renames the configured card.");
            checks.Add(new { name=language+".settings.check.form.hostedArc", noMissingFolderRead=true, unavailableReason=true, stableID=true });
        }
        foreach (var kind in new[] { "local", "arc" }) {
            var pending=new TaskCompletionSource<ProjectStatus>(); ProjectReference? sent=null;
            using var form=new ProjectSettingsForm(controller,null,live:false,_ => { },checker:(reference,_) => { sent=reference;return pending.Task; });
            var type=Descendants<ComboBox>(form).Single(input => AutomationProperties.GetName(input)==Text.L("windows.projectType"));type.SelectedItem=kind;
            Named(form,"account.name").Text="New synthetic project";Named(form,"windows.linuxFolder").Text="/tmp/new-synthetic";
            if(kind=="local") { Named(form,"project.startCommand").Text="npm run dev";Named(form,"project.checkURL").Text="http://localhost:6112/ready"; }
            var draft=form.CreateDraft();var again=form.CreateDraft();var check=form.HealthCheck.CheckAsync();
            Require(sent is not null && sent.Id==draft.Project.Id && again.Project.Id==draft.Project.Id && sent.Kind==kind, "Unsaved form checks and persistence drafts use different IDs.");
            Named(form,"windows.linuxFolder").Text="/tmp/changed-before-answer";form.HealthCheck.RefreshIdentity(autoCheck:false);pending.SetResult(Status(sent!,"Previous folder answer","Ignored"));await check;
            Require(form.HealthCheck.State==Text.L("check.notChecked.yet") && form.HealthCheck.Detail.Length==0 && form.CreateDraft().Project.Id==draft.Project.Id && form.CreateDraft().Project.Path=="/tmp/changed-before-answer", "A stale form health answer survives an actual folder edit or changes the new ID.");
            checks.Add(new { name=language+".settings.check.form.new."+kind, stableDraftAndCheckID=true, actualFolderEditInvalidates=true, delayedFakeReader=true });
        }
    }

    private static void CheckBrowsers(string language, List<object> checks)
    {
        InstalledBrowser[] installed=[new("chrome","Google Chrome",@"C:\Fixture\chrome.exe",true),new("firefox","Firefox",@"C:\Fixture\firefox.exe",false)];
        BrowserProfile[] Profiles(string id) => id=="chrome" ? [new("Default","Primary"),new("Profile 2","Work")] : [];
        var picker=new BrowserPicker("chrome","Profile 2",installed,Profiles);var changes=0;picker.ValueChanged+=(_,_)=>changes++;
        Require(picker.BrowserID=="chrome" && picker.SelectedProfile=="Profile 2" && Label(picker.Profile)=="Work" && picker.Profile.Visibility==Visibility.Visible && picker.Picker.Items.Count==3 && changes==0, "Browser selector loses the saved profile directory/friendly name or fabricates unavailable choices.");
        checks.Add(new { name=language+".settings.browser.friendlyProfile", namedWorkProfile=true, storedDirectoryRetained=true, onlyInstalledChoices=true });
        picker.Profile.SelectedValue="Default";
        Require(picker.SelectedProfile=="Default" && Label(picker.Profile)=="Primary" && changes==1, "A profile choice does not persist the directory with exactly one change event.");
        picker.Profile.SelectedIndex=0;
        Require(picker.SelectedProfile is null && Label(picker.Profile)==Text.L("windows.lastUsedProfile") && changes==2, "Last-used profile does not clear the explicit directory exactly once.");
        checks.Add(new { name=language+".settings.browser.profileEdits", directoriesPersisted=true, lastUsedRestored=true, exactlyOneChangePerEdit=true });
        picker.Picker.SelectedValue="firefox";
        Require(picker.BrowserID=="firefox" && picker.Profile.Visibility==Visibility.Collapsed && picker.SelectedProfile is null && changes==3, "Switching to Firefox leaves a Chromium profile active or emits duplicate events.");
        checks.Add(new { name=language+".settings.browser.browserChange", irrelevantProfileHidden=true, resetOnlyByUserChange=true, oneChange=true });
        var forbiddenReads=0;var firefox=new BrowserPicker("firefox","Old named Firefox profile",installed,_ => { forbiddenReads++;return []; });
        Require(firefox.BrowserID=="firefox" && firefox.SelectedProfile=="Old named Firefox profile" && firefox.Profile.Visibility==Visibility.Collapsed && forbiddenReads==0, "Constructing Firefox erases its stored legacy profile or reads Chromium data.");
        checks.Add(new { name=language+".settings.browser.firefoxLegacy", savedChoiceRetained=true, irrelevantProfileHidden=true, noProfileRead=true });
        var missing=new BrowserPicker("brave","Profile 9",installed,_ => []);
        Require(missing.BrowserID=="brave" && missing.SelectedProfile=="Profile 9" && missing.Profile.Visibility==Visibility.Visible && Label(missing.Picker).Contains(Text.L("windows.unavailable"),StringComparison.Ordinal) && Label(missing.Profile).Contains(Text.L("windows.unavailable"),StringComparison.Ordinal), "An absent saved browser/profile is silently replaced or hidden without its unavailable state.");
        checks.Add(new { name=language+".settings.browser.missingSaved", browserAndDirectoryRetained=true, unavailableChoicesShown=true });
        var empty=new BrowserPicker("chrome",null,installed,_ => []);
        Require(empty.SelectedProfile is null && empty.Profile.Visibility==Visibility.Collapsed && empty.Profile.Items.Count==1, "Chromium with no profiles shows an empty profile selector.");
        checks.Add(new { name=language+".settings.browser.noProfiles", optionalSelectorHidden=true, defaultChoiceRetained=true });
        var system=new BrowserPicker("system","Old saved profile",installed,_ => { forbiddenReads++;return []; });
        Require(system.BrowserID=="system" && system.SelectedProfile=="Old saved profile" && system.Profile.Visibility==Visibility.Collapsed && forbiddenReads==0, "Default-browser construction erases a saved profile or queries a Chromium profile store.");
        checks.Add(new { name=language+".settings.browser.default", irrelevantLegacyChoiceRetained=true, profileHidden=true, noRead=true });
    }

    private static string Label(ComboBox control) => control.SelectedItem?.GetType().GetProperty("Label")?.GetValue(control.SelectedItem) as string ?? "";
    private static TextBox Named(DependencyObject root,string key) => Descendants<TextBox>(root).Single(input => AutomationProperties.GetName(input)==Text.L(key));
    private static IEnumerable<T> Descendants<T>(DependencyObject root) where T:DependencyObject
    {
        foreach(var child in LogicalTreeHelper.GetChildren(root).OfType<DependencyObject>()) {
            if(child is T value)yield return value;
            foreach(var descendant in Descendants<T>(child))yield return descendant;
        }
    }
    private static void Require(bool condition,string message) { if(!condition)throw new IOException(message); }
    private sealed class Scope(Window window):IDisposable { internal Window Window { get; }=window;public void Dispose()=>Window.Close(); }
    private sealed class MetadataForm:SettingsForm
    {
        internal TextBox Input { get; }=new();internal PasswordBox Token { get; }=new();
        internal Queue<Func<Task>> Saves { get; }=new();internal List<string> Values { get; }=new();
        internal string MessageText=>Message.Text;internal Brush MessageBrush=>Message.Foreground;
        internal MetadataForm(DeckController controller):base(controller,live:true) { Autosaves=true;var panel=new StackPanel { Margin=new(24) };panel.Children.Add(Input);panel.Children.Add(Token);panel.Children.Add(Message);Content=panel;Watch(Input); }
        internal void Answer(string value)=>Message.Text=value;
        internal Task ExplicitAsync(Func<Task> action)=>ExecuteAsync(action);
        protected override Task SaveMetadataAsync() { Values.Add(Input.Text);return Saves.Count==0 ? Task.CompletedTask : Saves.Dequeue()(); }
    }
}
