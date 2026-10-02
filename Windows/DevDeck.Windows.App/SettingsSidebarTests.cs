using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Actual owned settings/sidebar controls and project cache, with no worker or credential access.
internal static class SettingsSidebarTests
{
    internal static async Task RunAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        try {
            await RunRedAsync(application, checks);
            await StatePolicyAsync(application, checks);
            await InvalidDraftViewportAsync(application, checks);
            await PasswordFilteringAsync(application, checks);
            await AvailabilityCacheAsync(application, checks);
            await QueuedAvailabilityAsync(application, checks);
            await EmptyIdentityFallbackAsync(application, checks);
            foreach (var locale in DevDeck.Windows.Core.Localization.Languages) await GeometryAsync(application, locale, checks);
        } finally { Text.Use(language); }
    }

    internal static async Task RunRedAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        try {
            var ordering = await OrderingAsync(application);
            var presentation = await PresentationAsync(application);
            checks.Add(new { name = "settings.sidebar.baseline.ordering", ordering.Pass, ordering.Accounts, ordering.Projects,
                unchangedSerializedSourceArrays = true, actualSettingsNavigation = true });
            checks.Add(new { name = "settings.sidebar.baseline.presentation", presentation.Pass, presentation.RunningDot,
                presentation.BusyDot, presentation.DisabledSelectable, presentation.DisabledTitleDim,
                presentation.DisabledIconDim, hiddenRetainedPhysicalCache = true, actualProjectPresentation = true });
            Require(ordering.Pass && presentation.Pass,
                "Actual settings-sidebar behavior does not match natural order/runtime presentation: "
                + JsonSerializer.Serialize(new { ordering, presentation }, WorkerProtocol.Json));
        } finally { Text.Use(language); }
    }

    private sealed record OrderingResult(bool Pass, string[] Accounts, string[] Projects);
    private sealed record PresentationResult(bool Pass, bool RunningDot, bool BusyDot, bool DisabledSelectable,
        bool DisabledTitleDim, bool DisabledIconDim);

    private static async Task<OrderingResult> OrderingAsync(Application application)
    {
        await using var fixture = new Fixture(application);
        await fixture.ShowAsync();
        var accounts = Entries(fixture.Window, "account:").Select(entry => entry.ID).ToArray();
        var projects = Entries(fixture.Window, "project:").Select(entry => entry.ID).ToArray();
        return new(accounts.SequenceEqual(new[] { "account:account.one", "account:account.two", "account:account.ten" })
            && projects.SequenceEqual(new[] { "project:site.one", "project:site.two", "project:site.ten" }), accounts, projects);
    }

    private static async Task<PresentationResult> PresentationAsync(Application application)
    {
        await using var fixture = new Fixture(application, owners: true);
        var running = fixture.Controller.AllLocalViews.Single(owner => owner.Reference.Id == "site.ten");
        var working = fixture.Controller.AllLocalViews.Single(owner => owner.Reference.Id == "site.one");
        var accepted = new ProjectStatus(running.Reference.Id, "running", "develop", null, "Drupal", "DDEV");
        running.ApplySnapshot(accepted);
        working.ApplySnapshot(new(working.Reference.Id, "stopped", "main", null, "Node", null));
        await fixture.ShowAsync();
        var runningRow = Entries(fixture.Window, "project:").Single(entry => entry.ID == "project:site.ten").Item;
        var green = HasDot(runningRow, CardTheme.Green);
        var selectable = runningRow.IsEnabled;
        var title = Descendants<TextBlock>(runningRow).Single(text => text.Text == "Site10");
        var titleDim = SameColor(title.Foreground, SystemColors.GrayTextBrush);
        var iconDim = Descendants<Border>(runningRow).Any(border => border.Child is not null && Math.Abs(border.Opacity - .45) < .001);
        working.ShowOperation("start");
        // The baseline has no cache publication hook. Explicitly render its existing
        // navigation again to inspect the real current presentation without a worker read.
        fixture.Window.ReloadNavigation(); fixture.Window.UpdateLayout();
        await Dispatcher.Yield(DispatcherPriority.Background);
        var busy = HasDot(Entries(fixture.Window, "project:").Single(entry => entry.ID == "project:site.one").Item, CardTheme.Amber);
        Require(!running.IsVisible && !working.IsVisible && !running.DeckVisible && !working.DeckVisible
            && fixture.Controller.AllLocalViews.Any(owner => ReferenceEquals(owner, running))
            && ReferenceEquals(running.Latest, accepted), "The sidebar presentation fixture did not retain its hidden physical owners.");
        return new(green && busy && selectable && titleDim && iconDim, green, busy, selectable, titleDim, iconDim);
    }

    private static async Task StatePolicyAsync(Application application, List<object> checks)
    {
        await using var fixture = new Fixture(application, owners: true);
        await fixture.ShowAsync();
        var ddev = fixture.Owner("site.ten"); var local = fixture.Owner("site.one"); var arc = fixture.Owner("site.two");
        foreach (var owner in new[] { ddev, local, arc }) {
            foreach (var state in new[] { "running", "working", "starting", "paused", "stopped", "unknown", "unavailable" }) {
                owner.ApplySnapshot(new(owner.Reference.Id, state, "main", null, null, null));
                fixture.Window.ReconcileProjectSidebar(owner.Reference.Id);
                var row = Row(fixture.Window, "project:" + owner.Reference.Id);
                var expected = state == "running" ? CardTheme.Green : state == "working" || state == "starting" && owner.Reference.Kind == "local" ? CardTheme.Amber : null;
                Require(expected is null ? row.Dot.Visibility != Visibility.Visible : HasDot(row, expected), "Sidebar physical state mapping is wrong: " + owner.Reference.Kind + "/" + state);
            }
        }
        ddev.ApplySnapshot(new(ddev.Reference.Id, "running", "main", null, null, null));
        fixture.Window.ReconcileProjectSidebar(ddev.Reference.Id);
        var retained = Row(fixture.Window, "project:" + ddev.Reference.Id); var dot = retained.Dot;
        ddev.BeginDDEVPowerOff("owned.sidebar.group"); fixture.Window.ReconcileProjectSidebar(ddev.Reference.Id);
        Require(HasDot(retained, CardTheme.Amber), "A pending DDEV group must override a running physical cache.");
        ddev.CompleteDDEVPowerOff("owned.sidebar.group"); fixture.Window.ReconcileProjectSidebar(ddev.Reference.Id);
        Require(HasDot(retained, CardTheme.Green) && ReferenceEquals(dot, retained.Dot) && !ddev.IsVisible,
            "Never-run DDEV completion fails to restore the retained hidden running dot/control.");
        local.ShowOperation("restart"); fixture.Window.ReconcileProjectSidebar(local.Reference.Id);
        Require(HasDot(Row(fixture.Window, "project:" + local.Reference.Id), CardTheme.Amber), "A real operation presentation without an operation CTS must remain busy.");
        fixture.CheckUnchanged();
        checks.Add(new { name = "settings.sidebar.statePolicy", physicalStateByKind = true, operationPresentationOverridesCache = true,
            ddevGroupBusyAndNeverRunRestore = true, hiddenOwnerNotShown = true, dotControlRetained = true, noSuccessfulReceiptOrSettingsChange = true });
    }

    private static async Task InvalidDraftViewportAsync(Application application, List<object> checks)
    {
        await using var fixture = new Fixture(application, seed: ManyProjects());
        await fixture.ShowAsync(); await fixture.Window.SelectPageAsync("project:site.20");
        ((ProjectSettingsForm)fixture.Window.Page.Content).Dispose();
        var configured = fixture.Controller.Settings.Cards.Single(card => card.Project.Id == "site.20");
        // Exercise the actual live metadata draft/validation body, while this owned
        // form's arrival check and discovery remain isolated from all real workers.
        var form = new ProjectSettingsForm(fixture.Controller, configured, live: true, changed: _ => { },
            checker: (reference, _) => Task.FromResult(new ProjectStatus(reference.Id,"stopped",null,null,null,null)),
            discoverDistributions: false);
        typeof(SettingsWindow).GetField("form",BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(fixture.Window,form);
        fixture.Window.Page.Content = form;
        var folder = Named<TextBox>(form, "windows.linuxFolder");
        folder.Text = "invalid owned draft folder"; await form.FlushAsync();
        var message = Field<TextBlock>(form, "Message", typeof(SettingsForm)); var error = message.Text;
        Require(form.HasUncommittedChanges && error.Length > 0, "The preservation fixture has no invalid unsaved project draft.");
        await FocusOwnedAsync(fixture.Window,folder); folder.Select(4, 7); await PumpAsync();
        Require(folder.IsKeyboardFocused, "The owned invalid folder did not obtain keyboard focus.");
        var tokens = Field<Dictionary<string,string>>(fixture.Window, "tokenDrafts"); tokens["account:account.one"] = "owned unsaved secret draft";
        var page = fixture.Window.Page.Content; var row = Row(fixture.Window, "project:site.20"); var title = row.TitleText;
        var scroll = Visual<ScrollViewer>(fixture.Window.Navigation)!;
        scroll.ScrollToVerticalOffset(650); await PumpAsync(); fixture.Window.Navigation.UpdateLayout();
        var anchor = VisibleAnchor(fixture.Window, scroll); var anchorTop = anchor.TranslatePoint(new(0,0), scroll).Y;
        var owner = fixture.Owner("site.20"); owner.ApplySnapshot(new(owner.Reference.Id, "running", "main", null, null, null));
        fixture.Window.ReconcileProjectSidebar(owner.Reference.Id);
        fixture.Commit(fixture.Controller.Settings with { Cards = fixture.Controller.Settings.Cards.Select(card => card.Project.Id == "site.1" ? card with { Title = "Zulu99" } : card).ToArray() });
        fixture.Window.ReloadNavigation(); await PumpAsync();
        Require(ReferenceEquals(page, fixture.Window.Page.Content) && ReferenceEquals(row, Row(fixture.Window, "project:site.20"))
            && ReferenceEquals(title, row.TitleText) && folder.Text == "invalid owned draft folder" && folder.SelectionStart == 4 && folder.SelectionLength == 7
            && folder.IsKeyboardFocused && form.HasUncommittedChanges && message.Text == error
            && tokens["account:account.one"] == "owned unsaved secret draft" && fixture.Window.SelectedPage == "project:site.20"
            && Math.Abs(anchor.TranslatePoint(new(0,0), scroll).Y - anchorTop) < 1.1 && HasDot(row, CardTheme.Green),
            "Runtime/reorder reconciliation loses invalid draft, error, focus/caret, token draft, retained controls or the surviving sidebar viewport anchor.");
        fixture.CheckUnchanged();
        var ordered = Entries(fixture.Window, "project:").Select(entry => (SettingsSidebarRow)entry.Item).ToArray();
        var anchorIndex = Array.IndexOf(ordered, anchor);
        Require(anchorIndex > 0 && scroll.VerticalOffset > 0, "The viewport fixture lacks an above-anchor project and a scrolled position.");
        var offsetBefore = scroll.VerticalOffset;
        var above = Math.Min(8, anchorIndex);
        var rowHeight = anchor.ActualHeight + anchor.Margin.Top + anchor.Margin.Bottom;
        var below = Math.Max(1, (int)Math.Ceiling((scroll.ScrollableHeight - offsetBefore) / rowHeight) + 1 - above);
        var removableBelow = ordered.Skip(anchorIndex + 1).Where(candidate => !ReferenceEquals(candidate,row)).Reverse().Take(below).ToArray();
        Require(removableBelow.Length == below, "The viewport fixture lacks below-anchor rows for forced extent coercion.");
        var removed = ordered.Take(above).Concat(removableBelow).Select(candidate => candidate.Tag!.GetType().GetProperty("ID")!.GetValue(candidate.Tag) as string
            ?? throw new IOException("The surviving viewport fixture contains a row without its compound identity.")).ToHashSet(StringComparer.Ordinal);
        var beforeCoercionTop = anchor.TranslatePoint(new(0,0), scroll).Y;
        fixture.Commit(fixture.Controller.Settings with { Cards = fixture.Controller.Settings.Cards.Where(card => !removed.Contains("project:" + card.Project.Id)).ToArray() });
        fixture.Window.ReloadNavigation(); await PumpAsync();
        Require(scroll.ScrollableHeight < offsetBefore && Math.Abs(anchor.TranslatePoint(new(0,0),scroll).Y - beforeCoercionTop) < 1.1
            && folder.IsKeyboardFocused && folder.SelectionStart == 4 && folder.SelectionLength == 7 && message.Text == error
            && form.HasUncommittedChanges && ReferenceEquals(page, fixture.Window.Page.Content),
            "Shrinking the sidebar above and below a surviving anchor coerces its extent and loses viewport/draft focus preservation.");
        fixture.CheckUnchanged();
        checks.Add(new { name = "settings.sidebar.invalidDraftViewport", currentErrorAndDraftRetained = true, sameFormRowTitleAndDot = true,
            focusAndSelectionRetained = true, windowTokenDraftRetained = true, scrolledRenamePreservesSurvivingAnchor = true,
            coercedExtentAboveAndBelowAnchor = true, injectedCurrentMetadataOnly = true });
    }

    private static async Task PasswordFilteringAsync(Application application, List<object> checks)
    {
        await using var fixture = new Fixture(application);
        await fixture.ShowAsync(); await fixture.Window.SelectPageAsync("account:account.one");
        var form = (AccountSettingsForm)fixture.Window.Page.Content;
        var password = Descendants<PasswordBox>(form).Single(); password.Password = "owned unsaved password";
        await FocusOwnedAsync(fixture.Window,password);
        Require(password.IsKeyboardFocused, "The owned password field did not obtain keyboard focus.");
        var page = fixture.Window.Page.Content; var row = Row(fixture.Window, "account:account.one"); var icon = row.IconFrame;
        fixture.Window.Search.Text = "Site"; fixture.Window.Search.Select(1,2); await PumpAsync();
        Require(fixture.Window.SelectedPage == "account:account.one" && !fixture.Window.Navigation.Items.Contains(row)
            && ReferenceEquals(page, fixture.Window.Page.Content) && password.Password == "owned unsaved password" && password.IsKeyboardFocused,
            "Filtering out the selected account replaced its active form/password or treated filtering as removal.");
        fixture.Commit(fixture.Controller.Settings with { Accounts = fixture.Controller.Settings.AccountList.Select(account => account.Id == "account.one" ? account with { Label = "Renamed work account" } : account).ToArray() });
        fixture.Window.ReconcileAccountSidebar("account.one"); await PumpAsync();
        Require(fixture.Window.Title == Text.L("settings.window.titleFor", "Renamed work account") && fixture.Window.Search.Text == "Site"
            && fixture.Window.Search.SelectionStart == 1 && fixture.Window.Search.SelectionLength == 2 && password.IsKeyboardFocused
            && password.Password == "owned unsaved password" && ReferenceEquals(page, fixture.Window.Page.Content),
            "A filtered-out committed title does not update the window title or disturbs password/query/cursor state.");
        fixture.Window.Search.Clear(); await PumpAsync();
        Require(ReferenceEquals(row, Row(fixture.Window, "account:account.one")) && ReferenceEquals(icon, row.IconFrame)
            && row.IsSelected && SameColor(row.TitleText.Foreground, Brushes.White), "Restoring a filtered selected row replaces its controls or loses selected-white presentation.");
        fixture.CheckUnchanged();
        checks.Add(new { name = "settings.sidebar.passwordFiltering", filteredSelectionKeepsActiveForm = true, passwordFocusAndValueRetained = true,
            fullListSelectedWindowTitle = true, queryCaretPreserved = true, survivingCompoundRowAndIconRetained = true });
    }

    private static async Task AvailabilityCacheAsync(Application application, List<object> checks)
    {
        var calls = new List<string>(); var present = new HashSet<string>(StringComparer.Ordinal);
        await using var fixture = new Fixture(application, availability: account => {
            calls.Add(account.CredentialTarget);
            if (account.Id == "account.ten") throw new UnauthorizedAccessException("Owned unreadable credential metadata.");
            return present.Contains(account.CredentialTarget);
        });
        Require(calls.Count == 3, "Explicit settings opening must read each current credential identity exactly once.");
        await fixture.ShowAsync();
        foreach (var query in new[] { "Account", "Site", "", "Test Linux", "" }) { fixture.Window.Search.Text = query; fixture.Window.ReloadNavigation(); }
        fixture.Window.ReconcileProjectSidebar("site.one"); fixture.Window.ReconcileAccountSidebar("account.ten");
        Require(calls.Count == 3 && HasDot(Row(fixture.Window, "account:account.ten"), CardTheme.Amber), "Search/runtime/plain reconcile retries an unavailable cached credential.");
        var original = fixture.Controller.Settings.AccountList.Single(account => account.Id == "account.one"); present.Add(original.CredentialTarget);
        fixture.Window.ReconcileAccountSidebar(original.Id, refreshAvailability: true);
        Require(calls.Count == 4 && Row(fixture.Window, "account:account.one").Dot.Visibility != Visibility.Visible,
            "Explicit credential-commit availability does not refresh exactly the current identity.");
        var changed = original with { Endpoint = "https://api.example.invalid" };
        fixture.Commit(fixture.Controller.Settings with { Accounts = fixture.Controller.Settings.AccountList.Select(account => account.Id == original.Id ? changed : account).ToArray() });
        fixture.Window.ReloadNavigation();
        Require(calls.Count == 4 && HasDot(Row(fixture.Window, "account:account.one"), CardTheme.Amber), "Plain metadata reload implicitly reads or reuses a former credential target.");
        present.Add(changed.CredentialTarget); fixture.Window.ReconcileAccountSidebar(changed.Id, refreshAvailability: true);
        Require(calls.Count == 5 && calls[^1] == changed.CredentialTarget && Row(fixture.Window, "account:account.one").Dot.Visibility != Visibility.Visible,
            "Explicit newly committed credential identity refreshes the wrong target or duplicates its read.");
        fixture.CheckUnchanged();
        checks.Add(new { name = "settings.sidebar.availabilityCache", booleanIdentityOnly = true, explicitOpeningReadsOnce = true,
            unreadableFalseNotRetried = true, searchRuntimeMetadataCachedOnly = true, explicitCommitRefreshesExactIdentity = true, changedEndpointNotReused = true });
    }

    private static async Task QueuedAvailabilityAsync(Application application, List<object> checks)
    {
        var calls = 0;
        await using var fixture = new Fixture(application, availability: _ => { calls++; return true; });
        await fixture.ShowAsync();
        var account = fixture.Controller.Settings.AccountList.Single(account => account.Id == "account.one");
        // Join only the enqueueing task without pumping this owning dispatcher. Change
        // identity before its queued callback can perform a credential lookup.
        Task.Run(() => fixture.Window.ReconcileAccountSidebar(account.Id, refreshAvailability: true)).GetAwaiter().GetResult();
        fixture.Commit(fixture.Controller.Settings with { Accounts = fixture.Controller.Settings.AccountList.Select(current => current.Id == account.Id ? current with { Endpoint = "https://queued.example.invalid" } : current).ToArray() });
        await PumpAsync();
        Require(calls == 3, "An ID-only delayed credential callback queried a later replacement target.");
        Task.Run(() => fixture.Window.ReconcileAccountSidebar(account.Id, refreshAvailability: true)).GetAwaiter().GetResult();
        await fixture.Window.CloseSettingsAsync(); await PumpAsync();
        Require(calls == 3 && Field<Dictionary<string,bool>>(fixture.Window, "tokenAvailability").Count == 0,
            "A queued closed settings callback reads credentials or retains availability cache.");
        checks.Add(new { name = "settings.sidebar.queuedAvailability", invocationTargetCaptured = true,
            dispatcherCurrentIdentityRecheckedBeforeLookup = true, closedWindowNoRead = true, cacheClearedOnClose = true });
    }

    private static async Task EmptyIdentityFallbackAsync(Application application, List<object> checks)
    {
        await using var empty = new Fixture(application, seed: DeckSettings.Empty with { Language = "en" });
        await empty.ShowAsync();
        Require(empty.Window.Navigation.Items.OfType<SettingsSidebarRow>().Count(row => row.TitleText.Text == Text.L("settings.sidebar.empty")) == 2,
            "Unfiltered empty groups lose their existing localized hints.");
        empty.Window.Search.Text = "no owned match";
        Require(empty.Window.Navigation.Items.Count == 0, "Filtered-empty groups retain headings or empty placeholders.");
        await using var fixture = new Fixture(application);
        var extra = fixture.Controller.Settings.Cards[0] with { Project = fixture.Controller.Settings.Cards[0].Project with { Id = "account.one", Path = "/tmp/devdeck-sidebar-shared" }, Title = "Site3" };
        fixture.Commit(fixture.Controller.Settings with { Cards = fixture.Controller.Settings.Cards.Append(extra).ToArray() }); fixture.Window.ReloadNavigation();
        await fixture.ShowAsync();
        Require(!ReferenceEquals(Row(fixture.Window, "account:account.one"), Row(fixture.Window, "project:account.one")), "Compound sidebar IDs collide between an account and a project.");
        await fixture.Window.SelectPageAsync("project:site.ten");
        var page = fixture.Window.Page.Content;
        fixture.Commit(fixture.Controller.Settings with { Cards = fixture.Controller.Settings.Cards.Where(card => card.Project.Id != "site.ten").ToArray() });
        fixture.Window.ReloadNavigation();
        Require(fixture.Window.SelectedPage == "project:account.one" && ReferenceEquals(page, fixture.Window.Page.Content),
            "List-only removal fallback fails to select the first same-kind project or replaces the active detail.");
        fixture.Commit(fixture.Controller.Settings with { Cards = fixture.Controller.Settings.Cards.Where(card => card.Project.Kind != "ddev").ToArray() }); fixture.Window.ReloadNavigation();
        Require(fixture.Window.SelectedPage == "general", "Removing the final same-kind row crosses into another module instead of General.");
        fixture.CheckUnchanged();
        checks.Add(new { name = "settings.sidebar.emptyIdentityFallback", unfilteredEmptyHints = true, filteredEmptyGroupsDisappear = true,
            accountProjectCompoundIDsSeparate = true, firstNaturalSameModuleThenGeneral = true, listOnlyFallbackKeepsDetail = true });
    }

    private static async Task GeometryAsync(Application application, string locale, List<object> checks)
    {
        var longTitle = "Work2 " + string.Concat(Enumerable.Repeat("e\u0301😀Ж長", 35));
        var seed = Seed(locale);
        seed = seed with { Cards = seed.Cards.Select(card => card.Project.Id == "site.ten" ? card with { Title = longTitle } : card).ToArray() };
        await using var fixture = new Fixture(application, owners: true, seed: seed);
        var owner = fixture.Owner("site.ten"); owner.ApplySnapshot(new(owner.Reference.Id, "running", "main", null, null, null));
        await fixture.ShowAsync();
        var row = Row(fixture.Window, "project:site.ten"); var icon = row.IconFrame; var dot = row.Dot; var title = row.TitleText;
        foreach (var font in new[] { 13d, 19.5d }) {
            fixture.Window.FontSize = font; fixture.Window.ReloadNavigation(); fixture.Window.Navigation.ScrollIntoView(row); fixture.Window.UpdateLayout(); await PumpAsync();
            var caption = System.Windows.Automation.AutomationProperties.GetName(row);
            var titleBounds = title.TransformToAncestor(row).TransformBounds(new Rect(new Point(), title.RenderSize));
            var dotBounds = dot.TransformToAncestor(row).TransformBounds(new Rect(new Point(), dot.RenderSize));
            var dotInNavigation = dot.TransformToAncestor(fixture.Window.Navigation).TransformBounds(new Rect(new Point(), dot.RenderSize));
            var rowInNavigation = row.TransformToAncestor(fixture.Window.Navigation).TransformBounds(new Rect(new Point(), row.RenderSize));
            Require(ReferenceEquals(row, Row(fixture.Window, "project:site.ten")) && ReferenceEquals(icon, row.IconFrame) && ReferenceEquals(dot, row.Dot)
                && row.Style == fixture.Window.Resources[typeof(ListBoxItem)] && row.IsEnabled && row.Opacity == 1 && icon.Opacity == .45
                && dot.Width == 7 && dot.Height == 7 && dot.Opacity == 1 && HasDot(row, CardTheme.Green)
                && title.TextTrimming == TextTrimming.CharacterEllipsis && titleBounds.Right <= dotBounds.Left
                && dotBounds.Right <= row.ActualWidth && dotBounds.Bottom <= row.ActualHeight
                && rowInNavigation.Left >= 0 && rowInNavigation.Right <= fixture.Window.Navigation.ActualWidth
                && dotInNavigation.Left >= 0 && dotInNavigation.Right <= fixture.Window.Navigation.ActualWidth
                && caption.Contains(longTitle, StringComparison.Ordinal) && caption.Contains(owner.Reference.Path, StringComparison.Ordinal) && caption.Contains(Text.L("settings.list.notOnDeck"), StringComparison.Ordinal)
                && (row.ToolTip as string)?.Contains(longTitle, StringComparison.Ordinal) == true && title.FontSize >= font,
                "Localized/enlarged sidebar clips its dot, loses full accessible detail/style or dims the entire disabled row: " + locale + "/" + font);
        }
        await fixture.Window.SelectPageAsync("project:site.ten");
        Require(row.IsSelected && SameColor(title.Foreground, Brushes.White) && icon.Opacity == .45 && dot.Opacity == 1,
            "Selected disabled title is not white or selection dims its semantic dot: " + locale);
        await fixture.Window.SelectPageAsync("general");
        Require(SameColor(title.Foreground, SystemColors.GrayTextBrush), "Unselected disabled title does not return to dim presentation: " + locale);
        fixture.CheckUnchanged();
        checks.Add(new { name = locale + ".settings.sidebar.geometry", normalAndEnlargedFonts = true, retainedNativeStyleAndControls = true,
            ellipsisReservesUndimmedSevenDipDot = true, selectedWhiteUnselectedDisabledDim = true, fullUnicodeLocalizedAutomationAndTooltip = true });
    }

    private static DeckSettings ManyProjects() => Seed("en") with { Cards = Enumerable.Range(1,40).Select(index =>
        new CardSettings(new("site." + index, "Test Linux", "local", "/tmp/devdeck-sidebar-" + index, StartCommand: "npm run dev"), "Site" + index)).ToArray() };
    private static DeckSettings Seed(string language) => new(1, [new("Test Linux", "/tmp/devdeck-sidebar-runtime")], [
        new(new("site.ten", "Test Linux", "ddev", "/tmp/devdeck-sidebar-ten"), "Site10", Enabled: false),
        new(new("site.two", "Test Linux", "arc", "/tmp/devdeck-sidebar-two"), "Site2"),
        new(new("site.one", "Test Linux", "local", "/tmp/devdeck-sidebar-one", StartCommand: "npm run dev"), "Site1")
    ], Accounts: [
        new("account.ten", "Account10", "github", "https://api.github.com", [], []),
        new("account.two", "Account2", "gitlab", "https://gitlab.example.invalid", [], []),
        new("account.one", "Account1", "github", "https://api.github.com", [], [])
    ], Language: language, Notifications: false, SeenAlerts: ["owned.sidebar.seen"]);
    private static SettingsSidebarRow Row(SettingsWindow window, string id) => (SettingsSidebarRow)Entries(window, id.StartsWith("account:", StringComparison.Ordinal) ? "account:" : "project:").Single(entry => entry.ID == id).Item;
    private static T Named<T>(DependencyObject source, string key) where T : FrameworkElement => Descendants<T>(source).Single(control =>
        System.Windows.Automation.AutomationProperties.GetName(control) == Text.L(key));
    private static T Field<T>(object source, string name, Type? owner = null) => (T)(owner ?? source.GetType()).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(source)!;
    private static T? Visual<T>(DependencyObject source) where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(source); index++) {
            var child = VisualTreeHelper.GetChild(source,index); if (child is T found) return found;
            if (Visual<T>(child) is { } nested) return nested;
        }
        return null;
    }
    private static SettingsSidebarRow VisibleAnchor(SettingsWindow window, ScrollViewer scroll) => window.Navigation.Items.OfType<SettingsSidebarRow>().First(row =>
        row.ActualHeight > 0 && PresentationSource.FromVisual(row) is not null && row.TranslatePoint(new(0,0),scroll).Y >= 0 && row.TranslatePoint(new(0,0),scroll).Y < scroll.ViewportHeight);
    private static async Task PumpAsync() { for (var turn=0; turn<3; turn++) await Dispatcher.Yield(DispatcherPriority.Background); }
    private static async Task FocusOwnedAsync(SettingsWindow window, FrameworkElement control)
    {
        // Page replacement is deferred by WPF. Lay out and reveal this owned field
        // before establishing the actual keyboard-focus premise to preserve later.
        window.UpdateLayout(); await PumpAsync();
        control.BringIntoView(); window.UpdateLayout(); await PumpAsync();
        var bounds = control.TransformToAncestor(window.Page).TransformBounds(new Rect(new Point(),control.RenderSize));
        Require(control.IsLoaded && control.IsVisible && control.IsEnabled && control.Focusable
            && PresentationSource.FromVisual(control) is not null && bounds.Height > 0
            && bounds.Bottom > 0 && bounds.Top < window.Page.ViewportHeight,
            "The owned focus fixture field is not rendered within its page viewport.");
        window.Activate(); await PumpAsync(); Keyboard.Focus(control); await PumpAsync();
        Require(control.IsKeyboardFocused,
            "The rendered owned field did not obtain keyboard focus: loaded=" + control.IsLoaded + "; visible=" + control.IsVisible
            + "; enabled=" + control.IsEnabled + "; active=" + window.IsActive + "; focused=" + Keyboard.FocusedElement?.GetType().Name);
    }

    private static bool HasDot(DependencyObject row, Brush expected) => Descendants<Ellipse>(row).Any(dot =>
        Math.Abs(dot.Width - 7) < .001 && Math.Abs(dot.Height - 7) < .001
        && dot.Visibility == Visibility.Visible && Math.Abs(dot.Opacity - 1) < .001 && SameColor(dot.Fill, expected));
    private static bool SameColor(Brush? left, Brush right) => left is SolidColorBrush actual && right is SolidColorBrush expected && actual.Color == expected.Color;
    private static (string ID, ListBoxItem Item)[] Entries(SettingsWindow window, string prefix) => window.Navigation.Items.OfType<ListBoxItem>()
        .Select(item => (ID: item.Tag?.GetType().GetProperty("ID")?.GetValue(item.Tag) as string ?? "", Item: item))
        .Where(entry => entry.ID.StartsWith(prefix, StringComparison.Ordinal)).ToArray();
    private static IEnumerable<T> Descendants<T>(DependencyObject source) where T : DependencyObject
    {
        foreach (var child in LogicalTreeHelper.GetChildren(source).OfType<DependencyObject>()) {
            if (child is T item) yield return item;
            foreach (var nested in Descendants<T>(child)) yield return nested;
        }
    }

    private sealed class Fixture : IAsyncDisposable
    {
        private readonly string path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "devdeck-settings-sidebar-" + Guid.NewGuid().ToString("N") + ".json");
        private byte[] persisted;
        private string accounts, projects;
        private readonly SettingsStore store;
        private static readonly DateTimeOffset Receipt = new(2026,10,2,12,0,0,TimeSpan.Zero);
        internal DeckController Controller { get; }
        internal SettingsWindow Window { get; }
        internal Fixture(Application application, bool owners = false, DeckSettings? seed = null, bool live = false,
            Func<RemoteAccountSettings,bool>? availability = null)
        {
            store = new SettingsStore(path); store.Save(seed ?? Seed("en"));
            Controller = new(application, store, live: false);
            typeof(DeckController).GetField("lastCheckedAt", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(Controller, Receipt);
            accounts = JsonSerializer.Serialize(Controller.Settings.AccountList, WorkerProtocol.Json);
            projects = JsonSerializer.Serialize(Controller.Settings.Cards, WorkerProtocol.Json);
            persisted = File.ReadAllBytes(path);
            if (owners) {
                var list = (List<ProjectCard>)typeof(DeckController).GetField("cards", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(Controller)!;
                foreach (var settings in Controller.Settings.Cards.Where(card => card.Project.Id is "site.ten" or "site.one")) {
                    var owner = new ProjectCard(Controller, settings, live: false);
                    owner.SetDeckVisible(false); list.Add(owner);
                    Field<Dictionary<string,CardSettings>>(Controller,"localConfigurations")[settings.Project.Id] = settings;
                }
            }
            Window = new(Controller, live: live, tokenAvailable: availability ?? (_ => false));
        }
        internal ProjectCard Owner(string id)
        {
            if (Controller.AllLocalViews.FirstOrDefault(owner => owner.Reference.Id == id) is { } current) return current;
            var settings = Controller.Settings.Cards.Single(card => card.Project.Id == id);
            var owner = new ProjectCard(Controller, settings, live: false);
            owner.SetDeckVisible(false);
            ((List<ProjectCard>)typeof(DeckController).GetField("cards", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(Controller)!).Add(owner);
            Field<Dictionary<string,CardSettings>>(Controller,"localConfigurations")[settings.Project.Id] = settings;
            return owner;
        }
        internal void Commit(DeckSettings current)
        {
            var IDs = current.AccountList.Select(account => account.Id).ToHashSet(StringComparer.Ordinal);
            current = current with { RemoteCards = current.RemoteCardList.Select(card => card with { AccountIDs = card.AccountIDs.Where(IDs.Contains).ToArray(), UseAllAccounts = true }).ToArray() };
            store.Save(current);
            typeof(DeckController).GetProperty("Settings", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(Controller,current);
            AcceptCurrent();
        }
        internal void AcceptCurrent()
        {
            accounts = JsonSerializer.Serialize(Controller.Settings.AccountList, WorkerProtocol.Json);
            projects = JsonSerializer.Serialize(Controller.Settings.Cards, WorkerProtocol.Json);
            persisted = File.ReadAllBytes(path);
        }
        internal void CheckUnchanged() => Require(accounts == JsonSerializer.Serialize(Controller.Settings.AccountList, WorkerProtocol.Json)
            && projects == JsonSerializer.Serialize(Controller.Settings.Cards, WorkerProtocol.Json)
            && File.ReadAllBytes(path).SequenceEqual(persisted) && !Controller.LocalPollEnabled && !Controller.SharedPollEnabled
            && Controller.LastCheckedAt == Receipt,
            "The sidebar fixture changed saved arrays/receipt or started a worker poll.");
        internal async Task ShowAsync()
        {
            Window.Show(); Window.UpdateLayout();
            await Dispatcher.Yield(DispatcherPriority.Background);
            Require(Window.IsVisible && Window.Navigation.Items.Count > 0, "The actual owned settings sidebar did not render.");
        }
        public async ValueTask DisposeAsync()
        {
            try {
                CheckUnchanged();
            } finally {
                // Discard only this owned synthetic form at teardown. Do not correct or
                // flush its invalid draft to make a sidebar preservation check pass.
                var formField = typeof(SettingsWindow).GetField("form", BindingFlags.Instance | BindingFlags.NonPublic)!;
                if (formField.GetValue(Window) is SettingsForm current) current.Dispose();
                formField.SetValue(Window,null);
                await Window.CloseSettingsAsync(); Controller.CloseViews();
                foreach (var file in new[] { path, path + ".bak" }) if (File.Exists(file)) File.Delete(file);
            }
        }
    }
    private static void Require(bool value, string message) { if (!value) throw new IOException(message); }
}
