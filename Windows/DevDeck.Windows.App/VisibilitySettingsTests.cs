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
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Synthetic settings files and controls only. No WSL discovery, worker, token or browser action.
internal static class VisibilitySettingsTests
{
    internal static async Task RunAsync(Application application, List<object> checks)
    {
        try {
            foreach (var language in DevDeck.Windows.Core.Localization.Languages) {
                await InvalidDraftAsync(application, language, checks);
                await CapturedMetadataAsync(application, language, checks);
                await ProjectCheckboxAsync(application, language, checks);
                await CardsCheckboxesAsync(application, language, checks);
                await NewProjectAsync(application, language, checks);
                await OtherIdentityAsync(application, language, checks);
            }
        } finally { Text.Use("en"); }
    }

    private static async Task InvalidDraftAsync(Application application, string language, List<object> checks)
    {
        using var fixture = new Fixture(application, language);
        var form = fixture.Project(); var folder = Named<TextBox>(form, "windows.linuxFolder");
        folder.Text = "invalid synthetic folder";
        await form.FlushAsync();
        var message = Field<TextBlock>(form, "Message", typeof(SettingsForm)); var failure = message.Text;
        Require(form.HasUncommittedChanges && failure.Length > 0, "The invalid-draft fixture must have a current unsaved error.");
        var drafts = Field<Dictionary<string,string>>(fixture.Window, "tokenDrafts");
        drafts["account:synthetic.github"] = "synthetic window-only token draft";
        fixture.Window.Show(); await FocusOwnedAsync(fixture.Window,folder);
        folder.Select(3, 7); await PumpAsync(fixture.Window);
        Require(folder.IsKeyboardFocused, "The synthetic folder must own focus before visibility reconciliation."
            +(folder.IsKeyboardFocused?"":" "+FocusDiagnostic(fixture.Window,folder)));
        var page = fixture.Window.Page.Content; var selected = fixture.Window.SelectedPage;
        await fixture.Controller.SetCardVisibleAsync("arc.primary", false);
        Require(!fixture.Store.Load().Cards.Single(card => card.Project.Id == "arc.primary").Enabled
            && !Shown(form) && !Field<CardSettings>(form, "original").Enabled,
            "External hiding did not reconcile the selected form's checkbox and baseline.");
        Require(ReferenceEquals(page, fixture.Window.Page.Content) && fixture.Window.SelectedPage == selected
            && folder.Text == "invalid synthetic folder" && folder.IsKeyboardFocused && folder.SelectionStart == 3 && folder.SelectionLength == 7
            && form.HasUncommittedChanges && form.IsEnabled && message.Text == failure
            && drafts["account:synthetic.github"] == "synthetic window-only token draft",
            "Visibility reconciliation rebuilt the form or changed its invalid draft, cursor, error, or token draft.");
        checks.Add(new { name=language+".visibility.settings.invalidDraft", savedHide=true, inPlaceCheckbox=true, baselineUpdated=true,
            invalidDraftErrorAndCursorRetained=true, tokenDraftRetained=true, noDiscoveryOrWorker=true });
    }

    private static async Task CapturedMetadataAsync(Application application, string language, List<object> checks)
    {
        using var fixture = new Fixture(application, language);
        var form = fixture.Project(); Named<TextBox>(form, "account.name").Text = "Captured synthetic metadata";
        StopDebounce(form);
        var gate = Field<SemaphoreSlim>(fixture.Controller, "actions"); await gate.WaitAsync();
        Task? pending = null;
        try {
            pending = Save(form);
            Require(!pending.IsCompleted && Shown(form), "The metadata fixture did not capture the visible draft before the action gate.");
            var hide = fixture.Controller.SetCardVisibleAsync("arc.primary", false);
            Require(hide.IsCompleted, "An external hide waits behind an unrelated project action.");
            await hide;
            Require(!Shown(form), "A pending metadata save prevents the current visibility checkbox from updating.");
        } finally {
            gate.Release();
            if (pending is not null) await pending;
        }
        var saved = fixture.Store.Load().Cards.Single(card => card.Project.Id == "arc.primary");
        Require(saved.Title == "Captured synthetic metadata" && !saved.Enabled && !Shown(form)
            && saved.X == 64 && saved.Y == 80 && saved.Collapsed,
            "An already captured metadata draft resurrects a hidden project or loses committed geometry.");
        checks.Add(new { name=language+".visibility.settings.capturedMetadata", actualActionGate=true, draftCapturedBeforeHide=true,
            oldCapturedEnabledIgnoredAtCommit=true, unrelatedMetadataSaved=true, placementAndCompactRetained=true });
    }

    private static async Task ProjectCheckboxAsync(Application application, string language, List<object> checks)
    {
        using var fixture = new Fixture(application, language);
        var form = fixture.Project(); Named<TextBox>(form, "windows.linuxFolder").Text = "invalid synthetic folder";
        await form.FlushAsync();
        var failure = Field<TextBlock>(form, "Message", typeof(SettingsForm)).Text;
        var gate = Field<SemaphoreSlim>(fixture.Controller, "actions"); await gate.WaitAsync();
        try {
            var toggle = Named<CheckBox>(form, "account.showOnDeck");
            toggle.IsChecked = false; toggle.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
            Require(!fixture.Store.Load().Cards.Single(card => card.Project.Id == "arc.primary").Enabled && !Shown(form),
                "The existing shown checkbox queues a whole metadata write or waits for valid metadata.");
            toggle.IsChecked = true; toggle.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
            Require(fixture.Store.Load().Cards.Single(card => card.Project.Id == "arc.primary").Enabled && Shown(form),
                "The explicit shown checkbox does not restore only the selected visibility.");
            Require(form.HasUncommittedChanges && Field<TextBlock>(form, "Message", typeof(SettingsForm)).Text == failure
                && fixture.Store.Load().Cards.Single(card => card.Project.Id == "arc.primary").Project.Path.Length == 0,
                "Shown-checkbox actions commit an invalid metadata draft or clear its current error.");
        } finally { gate.Release(); }
        checks.Add(new { name=language+".visibility.settings.projectCheckbox", fastCentralAction=true, invalidMetadataNotCommitted=true,
            hideAndRevealWhileActionGateHeld=true, currentErrorRetained=true });
    }

    private static async Task CardsCheckboxesAsync(Application application, string language, List<object> checks)
    {
        using var fixture = new Fixture(application, language);
        await fixture.Window.SelectPageAsync("cards");
        var page = fixture.Window.Page.Content!;
        var legacy = Descendants<CheckBox>((DependencyObject)page).Single(toggle => toggle.Tag as string == "pullRequests");
        var canonical = Descendants<CheckBox>((DependencyObject)page).Single(toggle => toggle.Tag as string == "github.pullRequests");
        var custom = Descendants<CheckBox>((DependencyObject)page).Single(toggle => toggle.Tag as string == "custom.pulls");
        var ids = fixture.Controller.Settings.RemoteCardList.Select(card => card.Id).ToArray();
        var gate = Field<SemaphoreSlim>(fixture.Controller, "actions"); await gate.WaitAsync();
        try {
            await fixture.Controller.SetCardVisibleAsync("legacy.pulls", false);
            Require(legacy.IsChecked == false && canonical.IsChecked == true && custom.IsChecked == true
                && ReferenceEquals(page, fixture.Window.Page.Content), "An external legacy hide rebuilds the Cards page or changes a later canonical/custom card.");
            legacy.IsChecked = true; legacy.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
            Require(fixture.Controller.Settings.RemoteCardList.Single(card => card.Id == "legacy.pulls").Enabled && legacy.IsChecked == true,
                "The built-in checkbox does not use the first saved legacy role through the fast visibility path.");
            canonical.IsChecked = false; canonical.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
            custom.IsChecked = false; custom.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
            Require(fixture.Controller.Settings.RemoteCardList.Single(card => card.Id == "legacy.pulls").Enabled
                && !fixture.Controller.Settings.RemoteCardList.Single(card => card.Id == "github.pullRequests").Enabled
                && !fixture.Controller.Settings.RemoteCardList.Single(card => card.Id == "custom.pulls").Enabled
                && ReferenceEquals(page, fixture.Window.Page.Content)
                && fixture.Controller.Settings.RemoteCardList.Select(card => card.Id).SequenceEqual(ids),
                "Custom checkbox actions wait on the global save gate, rebuild controls or rewrite role identity/order.");
        } finally { gate.Release(); }
        checks.Add(new { name=language+".visibility.settings.cardsCheckboxes", legacyRoleResolved=true, canonicalAndCustomIndependent=true,
            externalChangesInPlace=true, allClicksBypassActionGate=true, pageAndArrayOrderRetained=true });
    }

    private static async Task NewProjectAsync(Application application, string language, List<object> checks)
    {
        using var fixture = new Fixture(application, language);
        var form = fixture.Project(isNew:true);
        Named<TextBox>(form, "account.name").Text = "New hidden synthetic project";
        Named<TextBox>(form, "windows.linuxFolder").Text = "/synthetic/new-hidden-project";
        var toggle = Named<CheckBox>(form, "account.showOnDeck");
        toggle.IsChecked = false; toggle.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
        var draft = form.CreateDraft(); await Save(form);
        var saved = fixture.Store.Load().Cards.Single(card => card.Project.Id == draft.Project.Id);
        Require(!saved.Enabled && saved.Title == "New hidden synthetic project" && saved.Project.Id == draft.Project.Id
            && fixture.Store.Load().Cards.Single(card => card.Project.Id == "arc.primary").Enabled,
            "Separating existing visibility actions loses the new project's explicit hidden draft or changes another card.");
        checks.Add(new { name=language+".visibility.settings.newProject", newDraftVisibilityPreserved=true, stableDraftID=true,
            existingCardUntouched=true, explicitAddOnly=true });
    }

    private static async Task OtherIdentityAsync(Application application, string language, List<object> checks)
    {
        using var fixture = new Fixture(application, language);
        var form = fixture.Project(); Named<TextBox>(form, "account.name").Text = "Uncommitted own title";
        StopDebounce(form); var page = fixture.Window.Page.Content;
        await fixture.Controller.SetCardVisibleAsync("arc.other", false);
        fixture.Window.ReconcileCardVisibility("unknown.synthetic.id");
        Require(Shown(form) && Field<CardSettings>(form, "original").Enabled && form.HasUncommittedChanges
            && Named<TextBox>(form, "account.name").Text == "Uncommitted own title" && ReferenceEquals(page, fixture.Window.Page.Content),
            "A different or unknown permanent ID changes the selected project's visibility or unsaved draft.");
        checks.Add(new { name=language+".visibility.settings.otherIdentity", exactPermanentID=true, unrelatedFormAndDraftUntouched=true });
    }

    private static async Task PumpAsync(SettingsWindow window)
    {
        window.UpdateLayout();
        for(var turn=0;turn<3;turn++)await Dispatcher.Yield(DispatcherPriority.Background);
        window.UpdateLayout();
    }
    private static async Task FocusOwnedAsync(SettingsWindow window,FrameworkElement control)
    {
        await PumpAsync(window);control.BringIntoView();await PumpAsync(window);
        var ready=window.IsVisible&&control.IsLoaded&&control.IsVisible&&control.IsEnabled&&control.Focusable
            &&PresentationSource.FromVisual(control)is not null;
        Require(ready,"The owned visibility focus field is not loaded, connected and available."
            +(ready?"":" "+FocusDiagnostic(window,control)));
        var bounds=control.TransformToAncestor(window.Page).TransformBounds(new Rect(new Point(),control.RenderSize));
        var inViewport=bounds.Height>0&&bounds.Bottom>0&&bounds.Top<window.Page.ViewportHeight
            &&window.Page.ViewportWidth>0&&window.Page.ViewportHeight>0;
        Require(inViewport,"The owned visibility focus field is not rendered in its page viewport."
            +(inViewport?"":" "+FocusDiagnostic(window,control)));
        var activated=window.Activate();await PumpAsync(window);Keyboard.Focus(control);await PumpAsync(window);
        Require(control.IsKeyboardFocused,"The rendered owned visibility field did not obtain keyboard focus."
            +(control.IsKeyboardFocused?"":" "+FocusDiagnostic(window,control,activated)));
    }
    private static string FocusDiagnostic(SettingsWindow window,FrameworkElement control,bool? activated=null)
    {
        static double? Finite(double value)=>double.IsFinite(value)?value:null;
        var focused=Keyboard.FocusedElement;
        return System.Text.Json.JsonSerializer.Serialize(new {
            activated,active=window.IsActive,windowVisible=window.IsVisible,windowLoaded=window.IsLoaded,
            windowEnabled=window.IsEnabled,windowState=window.WindowState.ToString(),
            contentType=window.Page.Content?.GetType().Name,
            fieldType=control.GetType().Name,loaded=control.IsLoaded,visible=control.IsVisible,
            enabled=control.IsEnabled,focusable=control.Focusable,keyboardFocused=control.IsKeyboardFocused,
            connected=PresentationSource.FromVisual(control)is not null,
            measureValid=control.IsMeasureValid,arrangeValid=control.IsArrangeValid,
            width=Finite(control.ActualWidth),height=Finite(control.ActualHeight),
            viewportWidth=Finite(window.Page.ViewportWidth),viewportHeight=Finite(window.Page.ViewportHeight),
            focusedType=focused?.GetType().Name,focusedIsField=ReferenceEquals(focused,control)
        },WorkerProtocol.Json);
    }

    private static bool Shown(ProjectSettingsForm form) => Named<CheckBox>(form, "account.showOnDeck").IsChecked == true;
    private static Task Save(ProjectSettingsForm form) => (Task)typeof(ProjectSettingsForm)
        .GetMethod("SaveMetadataAsync", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(form, null)!;
    private static void StopDebounce(SettingsForm form) => Field<DispatcherTimer>(form, "debounce", typeof(SettingsForm)).Stop();
    private static T Field<T>(object owner, string name, Type? declared = null) => (T)(declared ?? owner.GetType())
        .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(owner)!;
    private static void SetField(object owner, string name, object? value) => owner.GetType()
        .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(owner, value);
    private static T Named<T>(DependencyObject root, string key) where T : DependencyObject => Descendants<T>(root)
        .Single(input => AutomationProperties.GetName(input) == Text.L(key));
    private static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
    {
        foreach (var child in LogicalTreeHelper.GetChildren(root).OfType<DependencyObject>()) {
            if (child is T value) yield return value;
            foreach (var descendant in Descendants<T>(child)) yield return descendant;
        }
    }
    private static void Require(bool condition, string message) { if (!condition) throw new IOException(message); }

    private sealed class Fixture : IDisposable
    {
        private readonly string path = Path.Combine(Path.GetTempPath(), "devdeck-visibility-settings-" + Guid.NewGuid().ToString("N") + ".json");
        internal SettingsStore Store { get; }
        internal DeckController Controller { get; }
        internal SettingsWindow Window { get; }
        internal Fixture(Application application, string language)
        {
            Store = new(path); Store.Save(Settings(language)); Controller = new(application, Store, live:false);
            Window = new(Controller, live:true, tokenAvailable:_=>false); SetField(Controller, "settingsWindow", Window);
        }
        internal ProjectSettingsForm Project(bool isNew = false)
        {
            var form = new ProjectSettingsForm(Controller, isNew ? null : Controller.Settings.Cards[0], live:true, _=>{},
                checker: (_,_)=>throw new IOException("The synthetic hosted/DDEV settings must never call a health worker."),
                discoverDistributions:false);
            SetField(Window, "form", form); SetField(Window, "selected", isNew ? "new-project" : "project:arc.primary"); Window.Page.Content = form;
            return form;
        }
        public void Dispose()
        {
            if (Window.Page.Content is SettingsForm form) form.Dispose();
            SetField(Window, "allowingClose", true); Window.Close(); SetField(Controller, "settingsWindow", null);
            Controller.CloseViews();
            foreach (var file in new[] { path, path + ".bak" }) if (File.Exists(file)) File.Delete(file);
        }
        private static DeckSettings Settings(string language) => new(1, [new("Test Linux", "/tmp/synthetic-visibility-runtime")],
            [new(new("arc.primary", "Test Linux", "arc", "", Arc:new("synthetic", "primary")), "Synthetic primary", X:64, Y:80, Collapsed:true),
             new(new("arc.other", "Test Linux", "arc", "", Arc:new("synthetic", "other")), "Synthetic other", X:64, Y:260)],
            Accounts:[new("synthetic.github", "Synthetic GitHub", "github", "https://api.github.com", [], []),
                new("synthetic.gitlab", "Synthetic GitLab", "gitlab", "https://gitlab.com", [], [])],
            RemoteCards:[new("legacy.pulls", "Synthetic legacy pulls", "pullRequests", "Test Linux", ["synthetic.github"]),
                new("github.pullRequests", "Synthetic extra canonical", "pullRequests", "Test Linux", ["synthetic.github"], X:520),
                new("custom.pulls", "Synthetic custom pulls", "pullRequests", "Test Linux", ["synthetic.github"], X:980),
                new("github.inbox", "Synthetic inbox", "inbox", "Test Linux", ["synthetic.github"]),
                new("github.actions", "Synthetic actions", "actions", "Test Linux", ["synthetic.github"], Enabled:false),
                new("gitlab.mergeRequests", "Synthetic merges", "mergeRequests", "Test Linux", ["synthetic.gitlab"])],
            Language:language, Notifications:false);
    }
}
