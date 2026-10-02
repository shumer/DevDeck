using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Threading;
using DevDeck.Windows.Core;
using Forms = System.Windows.Forms;
using Size = System.Drawing.Size;

namespace DevDeck.Windows.App;

/// Owned native view fixtures only. All actions are injected fakes, with no providers or workers.
internal static class TrayAttentionActionsChecks
{
    internal static async Task RunAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        try {
            foreach (var locale in DevDeck.Windows.Core.Localization.Languages) {
                Text.Use(locale);
                using var fixture = new Fixture(application);
                CheckFullList(fixture, locale, checks);
                await CheckDispatchAsync(fixture, locale, checks);
                CheckChoices(locale, checks);
                CheckGeometry(locale, checks);
            }
        } finally { Text.Use(language); }
    }

    private static void CheckFullList(Fixture fixture, string locale, List<object> checks)
    {
        var none = Item("none", new("none"));
        var inbox = Inbox("inbox", url: false);
        var dismiss = Item("dismiss", new("showCard", CardID: "owned.project"), dismissible: true);
        var wrong = Item("wrong", new("open", Url: "https://example.test"), dismissible: true);
        var precedence = Inbox("precedence") with { Action = new("showCard", CardID: "owned.project"), Dismissible = true };
        var called = 0;
        var window = fixture.Window([none, inbox, dismiss, wrong, precedence], (_, _) => { called++; return Task.FromResult(true); });
        var primary = Descendants<Button>(window).Where(button => button.Tag is AttentionItem).ToArray();
        var alternate = Descendants<Button>(window).Where(button => button.Tag is AttentionChoice).ToArray();
        Require(primary.Length == 5 && alternate.Length == 3 && !Primary(window, none).IsEnabled
            && !Primary(window, inbox).IsEnabled && Alternate(window, inbox).IsEnabled
            && Alternate(window, dismiss).Content as string == Text.L("menu.dismiss", dismiss.Title)
            && Alternate(window, inbox).Content as string == Text.L("menu.markRead", inbox.Title)
            && ((AttentionChoice)Alternate(window, precedence).Tag).Kind == "read"
            && alternate.All(button => button.Focusable && button.IsTabStop
                && AutomationProperties.GetName(button).Contains(button.Content as string ?? "missing", StringComparison.Ordinal))
            && called == 0, "Full attention list lacks explicit keyboard/accessibility read, enables status-only, loses precedence or executes while constructing: " + locale);
        Primary(window, none).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Require(called == 0, "Raising a disabled status-only primary admits an action: " + locale);
        checks.Add(new { name = locale + ".attention.actions.fullList", explicitUrlLessRead = true, primaryNoneDisabled = true,
            readBeforePermittedDismiss = true, oneAlternatePerLogicalItem = true, keyboardAndAutomationNames = true, constructionHasNoAction = true });
    }

    private static async Task CheckDispatchAsync(Fixture fixture, string locale, List<object> checks)
    {
        var inbox = Inbox("exact-thread");
        var sibling = Inbox("other-thread") with { InboxRead = new("github.inbox", "other-account", "0041", "https://api.other.test") };
        var pending = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = new List<(AttentionItem Item, AttentionChoice Choice)>();
        Func<AttentionItem, AttentionChoice, Task<bool>> handler = (item, choice) => { calls.Add((item, choice)); return pending.Task; };
        var window = fixture.Window([inbox, sibling], (item, choice) => handler(item, choice));
        var read = Alternate(window, inbox); var primary = Primary(window, inbox);
        read.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        read.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        primary.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Require(calls.Count == 1 && ReferenceEquals(calls[0].Item, inbox) && calls[0].Choice.Kind == "read"
            && calls[0].Choice.InboxRead == inbox.InboxRead && !read.IsEnabled && !primary.IsEnabled
            && Alternate(window, sibling).IsEnabled, "Pending explicit read duplicates admission, loses exact account/thread/endpoint or blocks an unrelated row: " + locale);
        const string failure = "Owned injected read failure.";
        pending.SetException(new IOException(failure));
        await UntilAsync(window, () => read.IsEnabled && primary.IsEnabled
            && Descendants<TextBlock>(window).Any(text => text.Text == failure && text.Visibility == Visibility.Visible));
        handler = (item, choice) => { calls.Add((item, choice)); return Task.FromResult(false); };
        read.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        await UntilAsync(window, () => calls.Count == 2 && read.IsEnabled && primary.IsEnabled);
        handler = (item, choice) => { calls.Add((item, choice)); return Task.FromResult(true); };
        read.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        await UntilAsync(window, () => calls.Count == 3 && !read.IsEnabled && !primary.IsEnabled);
        Require(Alternate(window, sibling).IsEnabled && calls.All(call => call.Choice.InboxRead == inbox.InboxRead),
            "A completed read disables a different account's matching thread or dispatches a browser/foreign target: " + locale);
        checks.Add(new { name = locale + ".attention.actions.exactDispatch", exactCapturedFourPartTarget = true, pendingDuplicateBlocked = true,
            unrelatedMatchingThreadRetained = true, failureVisibleAndRetryable = true, staleNoOpNotPresentedAsSuccess = true, successDisablesOnlyOwnedRow = true, injectedActionsOnly = true });
    }

    private static void CheckChoices(string locale, List<object> checks)
    {
        var now = new DateTimeOffset(2026, 10, 2, 12, 0, 0, TimeSpan.Zero);
        var read = Inbox("read") with { Dismissible = true, Since = now.AddDays(-4).ToUnixTimeSeconds() };
        var urlLess = Inbox("url-less", url: false);
        var dismiss = Item("dismiss", new("showCard", CardID: "owned.project"), dismissible: true);
        var forbidden = Item("foreign-dismiss", new("open", Url: "https://example.test"), dismissible: true);
        var none = Item("none", new("none"));
        foreach (var item in new[] { read, urlLess, dismiss, forbidden, none }) {
            using var row = new TrayAttentionRow(item, now);
            var subtitle = row.Subtitle; var originalAge = row.Age; var primary = AttentionChoices.Primary(item);
            row.SetAlternate(true);
            var expected = AttentionChoices.Select(item, true);
            var expectedText = expected.Kind switch { "read" => Text.L("menu.markRead", item.Title), "dismiss" => Text.L("menu.dismiss", item.Title), _ => item.Title };
            Require(ReferenceEquals(row.Tag, item) && row.CurrentChoice == expected && row.Enabled == expected.Enabled
                && row.Subtitle == subtitle && row.Age == (expected.IsAlternate ? null : originalAge)
                && row.AccessibleName!.Contains(expectedText, StringComparison.Ordinal)
                && row.AccessibleDescription!.Contains(item.Subtitle, StringComparison.Ordinal),
                "Alternate row changes logical identity/subtitle, loses read precedence, retains primary age or enables forbidden dismiss: " + locale);
            row.SetAlternate(false); row.SetAlternate(false);
            Require(row.CurrentChoice == primary && row.Age == originalAge && row.Enabled == primary.Enabled
                && ReferenceEquals(row.Tag, item), "Releasing/repeating modifier does not restore original primary state: " + locale);
        }
        using var calm = new TrayAttentionRow(Text.L("menu.calm"), "12:00");
        calm.SetAlternate(true);
        Require(calm.Tag is null && !calm.Enabled && calm.Age is null, "Status-only calm menu row acquires an alternate action.");
        checks.Add(new { name = locale + ".attention.actions.choices", readPrecedence = true, urlLessAlternateEnabled = true,
            permittedProjectDismissOnly = true, primaryAgeOnly = true, sameLogicalTagAndSubtitle = true, pressReleaseIdempotent = true, noActionOnModifier = true });
    }

    private static void CheckGeometry(string locale, List<object> checks)
    {
        var title = "Review & " + string.Concat(Enumerable.Repeat("e\u0301😀Ж長", 80));
        var subtitle = string.Concat(Enumerable.Repeat("Account e\u0301😀 · full detail ", 30));
        var item = Inbox("geometry") with { Title = title, Subtitle = subtitle };
        var now = DateTimeOffset.FromUnixTimeSeconds((long)item.Since!.Value + 4 * 86400);
        using var menu = new Forms.ContextMenuStrip();
        using var overflow = new Forms.ToolStripMenuItem("Overflow");
        menu.Items.Add(overflow);
        using var row = new TrayAttentionRow(item, now); overflow.DropDownItems.Add(row);
        using var direct = new TrayAttentionRow(item with { Id = "geometry-main" }, now); menu.Items.Insert(0, direct);
        foreach (var multiplier in new[] { 1f, 1.5f, 2f }) {
            using var font = new Font(System.Drawing.SystemFonts.MenuFont?.FontFamily ?? FontFamily.GenericSansSerif, 9 * multiplier);
            row.Font = direct.Font = font;
            row.SetAlternate(false); direct.SetAlternate(false); TrayAttentionRow.SizeMenu(menu);
            foreach (var (surface, active) in new[] { (Surface: (Forms.ToolStrip)menu, Row: direct), (Surface: (Forms.ToolStrip)overflow.DropDown, Row: row) }) {
                _ = surface.Handle; surface.PerformLayout(); surface.Size = surface.GetPreferredSize(Size.Empty); surface.PerformLayout();
                var preferred = active.GetPreferredSize(Size.Empty); var bounds = active.Bounds; var menuSize = surface.Size;
                var parentBounds = overflow.Bounds;
                active.SetAlternate(true); surface.PerformLayout();
                var diagnostic = new {
                    locale, fontMultiplier = multiplier, mainMenu = ReferenceEquals(surface, menu), dpi = surface.DeviceDpi,
                    preferredStable = active.GetPreferredSize(Size.Empty) == preferred,
                    rowStable = active.Bounds == bounds, menuStable = surface.Size == menuSize,
                    ordinaryParentStable = overflow.Bounds == parentBounds,
                    graphemeBounded = StringInfo.ParseCombiningCharacters(active.Subtitle).Length <= 72,
                    accessibleCaption = active.AccessibleName?.Contains(Text.L("menu.markRead", title), StringComparison.Ordinal) == true,
                    accessibleSubtitle = active.AccessibleDescription?.Contains(subtitle, StringComparison.Ordinal) == true,
                    fullTooltip = active.ToolTipText?.Contains(subtitle, StringComparison.Ordinal) == true,
                    leftInside = active.Bounds.Left >= surface.ClientRectangle.Left,
                    rightInside = active.Bounds.Right <= surface.ClientRectangle.Right,
                    topInside = active.Bounds.Top >= surface.ClientRectangle.Top,
                    bottomInside = active.Bounds.Bottom <= surface.ClientRectangle.Bottom,
                    twoLineHeight = active.Height >= active.Font.Height * 2,
                    beforePreferred = preferred.ToString(), afterPreferred = active.GetPreferredSize(Size.Empty).ToString(),
                    beforeRow = bounds.ToString(), afterRow = active.Bounds.ToString(),
                    beforeMenu = menuSize.ToString(), afterMenu = surface.Size.ToString(), client = surface.ClientRectangle.ToString(),
                    beforeParent = parentBounds.ToString(), afterParent = overflow.Bounds.ToString()
                };
                Require(diagnostic.preferredStable && diagnostic.rowStable && diagnostic.menuStable && diagnostic.ordinaryParentStable && diagnostic.graphemeBounded
                    && diagnostic.accessibleCaption && diagnostic.accessibleSubtitle && diagnostic.fullTooltip
                    && diagnostic.leftInside && diagnostic.rightInside && diagnostic.topInside && diagnostic.bottomInside && diagnostic.twoLineHeight,
                    "Alternate native row resizes menu, loses full Unicode accessibility/tooltip or clips actual client bounds: " + JsonSerializer.Serialize(diagnostic));
                active.SetAlternate(false); surface.PerformLayout();
                Require(active.GetPreferredSize(Size.Empty) == preferred && active.Bounds == bounds && overflow.Bounds == parentBounds && active.Age is not null,
                    "Returning from alternate changes measured geometry or loses primary age: " + locale);
            }
            row.Font = direct.Font = menu.Font;
        }
        checks.Add(new { name = locale + ".attention.actions.geometry", mainAndOverflowSameLogicalRow = true,
            fontMultipliers = new[] { 1, 1.5, 2 }, bothCaptionsReserved = true, primaryAlternateBoundsStable = true,
            ordinarySubmenuOwnerBoundsStable = true, actualClientContainsRow = true, fullUnicodeAccessibilityAndTooltip = true, graphemeBoundedSubtitle = true });
    }

    private sealed class Fixture : IDisposable
    {
        private readonly string path = Path.Combine(Path.GetTempPath(), "devdeck-attention-action-checks-" + Guid.NewGuid().ToString("N") + ".json");
        private readonly byte[] persisted;
        private readonly List<AttentionWindow> windows = [];
        internal DeckController Controller { get; }
        internal Fixture(Application application)
        {
            var store = new SettingsStore(path); store.Save(DeckSettings.Empty with { Workers = [], Cards = [], Notifications = false });
            Controller = new(application, store, live: false); persisted = File.ReadAllBytes(path);
        }
        internal AttentionWindow Window(AttentionItem[] items, Func<AttentionItem, AttentionChoice, Task<bool>> action)
        {
            var window = new AttentionWindow(Controller, items, action);
            window.Measure(new(620, 580)); window.Arrange(new(0, 0, 620, 580)); window.UpdateLayout();
            windows.Add(window); return window;
        }
        public void Dispose()
        {
            try {
                Require(!Controller.SharedPollEnabled && !Controller.LocalPollEnabled && File.ReadAllBytes(path).SequenceEqual(persisted),
                    "Attention view fixtures start a poll/worker or rewrite settings.");
            } finally {
                foreach (var window in windows) window.Close(); Controller.CloseViews();
                foreach (var file in new[] { path, path + ".bak" }) if (File.Exists(file)) File.Delete(file);
            }
        }
    }
    private static Button Primary(AttentionWindow window, AttentionItem item) => Descendants<Button>(window).Single(button => button.Tag is AttentionItem source && source.Id == item.Id);
    private static Button Alternate(AttentionWindow window, AttentionItem item)
    {
        var expected = AttentionChoices.Alternate(item);
        // The fixture has a read-precedence item and a separate dismissible item for
        // the same project. Match the complete promised choice, not each candidate's
        // own branch, which could also select that unrelated dismiss button.
        return Descendants<Button>(window).Single(button => button.Tag is AttentionChoice choice && choice == expected);
    }
    private static AttentionItem Inbox(string id, bool url = true) => Item(id, url ? new("open", Url: "https://example.test/review/41", Service: "github", AccountID: "owned-account") : new("none"), enabled: url)
        with { InboxRead = new("github.inbox", "owned-account", id == "precedence" ? "0042" : "0041", "https://api.example.test") };
    private static AttentionItem Item(string id, AttentionAction action, bool enabled = true, bool dismissible = false) =>
        new(id, id, "waiting", "github", "Review & deployment " + id, "Owned work account · example/shop · full diagnostic", 1_780_000_000, action, enabled, dismissible);
    private static IEnumerable<T> Descendants<T>(DependencyObject source) where T : DependencyObject
    {
        foreach (var child in LogicalTreeHelper.GetChildren(source).OfType<DependencyObject>()) {
            if (child is T item) yield return item;
            foreach (var nested in Descendants<T>(child)) yield return nested;
        }
    }
    private static async Task UntilAsync(AttentionWindow window, Func<bool> ready)
    {
        var deadline = DateTime.UtcNow.AddSeconds(3);
        while (!ready()) {
            if (DateTime.UtcNow > deadline) throw new IOException("Injected attention view action did not settle within three seconds.");
            await window.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle); await Task.Delay(5);
        }
    }
    private static void Require(bool value, string message) { if (!value) throw new IOException(message); }
}
