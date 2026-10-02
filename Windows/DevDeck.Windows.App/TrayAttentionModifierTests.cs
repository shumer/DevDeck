using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using DevDeck.Windows.Core;
using Forms = System.Windows.Forms;

namespace DevDeck.Windows.App;

/// Queued input targets only disposable menu HWNDs; clicks record choices, never run actions.
internal static class TrayAttentionModifierTests
{
    private const int KeyDown = 0x100, SystemKeyDown = 0x104, SystemKeyUp = 0x105;
    private const int Alt = 0x12, Enter = 0x0D, Escape = 0x1B;
    private static readonly DateTimeOffset Now = new(2026, 10, 2, 16, 30, 0, TimeSpan.Zero);

    internal static async Task RunAsync(Application application, List<object> checks)
    {
        Require(application.Dispatcher.CheckAccess(), "Owned menu qualification must run on the WPF UI thread.");
        try {
            foreach (var language in new[] { "en", "ru", "de", "fr", "es", "it" }) {
                Text.Use(language);
                await HeldTransitionsAsync(language, checks);
                await EscapeReopenAsync(language, checks);
            }
            Text.Use("en");
            await KeyboardActionAsync("read.main", overflow: false, dismiss: false, checks);
            await KeyboardActionAsync("read.overflow", overflow: true, dismiss: false, checks);
            await KeyboardActionAsync("dismiss.main", overflow: false, dismiss: true, checks);
            await DisabledKeyboardAsync(checks);
            await MouseActionAsync("read.main", overflow: false, dismiss: false, checks);
            await MouseActionAsync("dismiss.overflow", overflow: true, dismiss: true, checks);
            await DisposeIsolationAsync(checks);
            await UnrelatedOwnedInputAsync(checks);
            await RebuiltOverflowActionAsync("keyboard", "44", keyboard: true, checks);
            await RebuiltOverflowActionAsync("mouse", "45", keyboard: false, checks);
        } finally { Text.Use("en"); }
    }

    private static async Task HeldTransitionsAsync(string language, List<object> checks)
    {
        using var fixture = new Fixture(initialHeld: true);
        await fixture.ShowAsync(overflow: true);
        var rows = fixture.AllRows;
        var originalTags = rows.Select(row => row.Tag).ToArray();
        var originalSubtitle = rows.Select(row => row.Subtitle).ToArray();
        var menuCount = fixture.Menu.Items.Count;
        var overflowCount = fixture.Overflow.DropDownItems.Count;
        Require(fixture.Host.Active && fixture.Host.Held && fixture.MainRead.Enabled && fixture.MainRead.CurrentChoice.Kind == "read"
            && fixture.OverflowRead.Enabled && fixture.OverflowRead.CurrentChoice.Kind == "read"
            && fixture.MainDismiss.CurrentChoice.Kind == "dismiss" && fixture.OverflowDismiss.CurrentChoice.Kind == "dismiss",
            "Holding Alt when the owned menu opens did not present both main and overflow alternates.");
        Require(!fixture.Inert.Enabled && fixture.Inert.CurrentChoice.Kind == "primary"
            && fixture.PrimaryOnly.CurrentChoice.Kind == "primary" && fixture.PrimaryOnly.Enabled,
            "A row without an alternate acquired one, or a status-only row became actionable.");
        Require(rows.Where(row => row.CurrentChoice.IsAlternate).All(row => row.Age is null), "An alternate retained the primary age badge.");
        fixture.OverflowDismiss.Select();
        await PumpAsync();
        Require(fixture.OverflowDismiss.Selected, "The actual overflow selection was not retained for the input fixture.");
        var before = Geometry(fixture);
        var observed = fixture.Host.ObservedKeyboardMessages;
        PostKey(fixture.Overflow.DropDown, SystemKeyUp, Alt);
        await PumpAsync();
        Require(fixture.Host.Active && !fixture.Host.Held && fixture.Menu.Visible && fixture.Overflow.DropDown.Visible
            && !fixture.MainRead.Enabled && !fixture.OverflowRead.Enabled && fixture.MainDismiss.CurrentChoice.Kind == "primary"
            && fixture.MainDismiss.Age is not null && fixture.OverflowDismiss.Selected,
            "Releasing Alt closed the menu, lost selection or failed to restore the original primary choices.");
        var released = Geometry(fixture);
        Require(released.SequenceEqual(before), "Modifier release changed an actual shown menu or row rectangle. Before: "
            + string.Join(" | ", before.Select(rectangle => rectangle.ToString())) + "; after: "
            + string.Join(" | ", released.Select(rectangle => rectangle.ToString())));
        PostKey(fixture.Overflow.DropDown, SystemKeyDown, Alt);
        PostKey(fixture.Overflow.DropDown, SystemKeyDown, Alt, repeat: true);
        await PumpAsync();
        Require(fixture.Host.Held && fixture.Host.ObservedKeyboardMessages == observed + 3 && fixture.Clicks.Count == 0
            && fixture.OverflowDismiss.Selected && fixture.MainRead.CurrentChoice.Kind == "read",
            "Queued Alt press/repeat activated an action, was missed by the host or lost selection.");
        Require(Geometry(fixture).SequenceEqual(before) && rows.SequenceEqual(fixture.AllRows)
            && rows.Select(row => row.Tag).SequenceEqual(originalTags) && rows.Select(row => row.Subtitle).SequenceEqual(originalSubtitle)
            && fixture.Menu.Items.Count == menuCount && fixture.Overflow.DropDownItems.Count == overflowCount,
            "Modifier input rebuilt rows, changed source facts, counts or shown geometry.");
        Require(rows.Where(row => row.CurrentChoice.IsAlternate).All(row => row.AccessibleName?.Contains(Text.L(
            row.CurrentChoice.Kind == "read" ? "menu.markRead" : "menu.dismiss", ((AttentionItem)row.Tag!).Title), StringComparison.Ordinal) == true),
            "The chosen alternate was missing from its localized accessible name.");
        checks.Add(new { name = language + ".tray.modifier.queuedTransitions", heldAtOpenMainAndOverflow = true,
            actualQueuedAltPressReleaseRepeat = true, noActionOnModifierOrSelection = true, sameNativeRowsSelectionAndGeometry = true,
            exactSourceTagsSubtitleAndCounts = true, urlLessReadEnabled = true, statusOnlyInert = true, localizedAccessibleAlternate = true });
    }

    private static async Task EscapeReopenAsync(string language, List<object> checks)
    {
        using var fixture = new Fixture(initialHeld: true);
        await fixture.ShowAsync();
        var observed = fixture.Host.ObservedKeyboardMessages;
        PostKey(fixture.Menu, KeyDown, Escape);
        await PumpAsync();
        Require(!fixture.Menu.Visible && !fixture.Host.Active && !fixture.Host.Held && fixture.Clicks.Count == 0,
            "Queued Escape did not close and unhook the owned menu without an action.");
        PostKey(fixture.Menu, SystemKeyDown, Alt);
        await PumpAsync();
        Require(fixture.Host.ObservedKeyboardMessages == observed && !fixture.Host.Active && !fixture.MainRead.Enabled,
            "A closed menu still consumed queued modifier input or retained its alternate presentation.");
        fixture.InitialHeld = false;
        await fixture.ShowAsync();
        Require(fixture.Host.Active && !fixture.Host.Held && !fixture.MainRead.Enabled && fixture.MainRead.CurrentChoice.Kind == "primary",
            "Reopening the same owned menu retained a prior held modifier or a stale disabled choice.");
        PostKey(fixture.Menu, SystemKeyDown, Alt);
        PostKey(fixture.Menu, SystemKeyUp, Alt);
        await PumpAsync();
        Require(fixture.Host.ObservedKeyboardMessages == observed + 2 && fixture.Clicks.Count == 0 && fixture.Menu.Visible && !fixture.Host.Held,
            "Reopening doubled the keyboard subscriptions or Alt dismissed the menu before the scoped host.");
        checks.Add(new { name = language + ".tray.modifier.escapeReopen", actualQueuedEscape = true,
            closedMenuUnhooksAndResets = true, sameMenuReopensWithCurrentHeldState = true, oneObservationPerMessage = true, noRecordedActions = true });
    }

    private static async Task KeyboardActionAsync(string name, bool overflow, bool dismiss, List<object> checks)
    {
        using var fixture = new Fixture();
        await fixture.ShowAsync(overflow);
        var menu = overflow ? fixture.Overflow.DropDown : fixture.Menu;
        PostKey(menu, SystemKeyDown, Alt);
        await PumpAsync();
        var row = dismiss ? fixture.MainDismiss : overflow ? fixture.OverflowRead : fixture.MainRead;
        row.Select();
        await PumpAsync();
        Require(row.Selected && fixture.Clicks.Count == 0, "Selecting a permitted actual row dispatched its action.");
        var expected = row.CurrentChoice;
        Require(expected.Kind == (dismiss ? "dismiss" : "read"), "The queued keyboard fixture did not select its promised alternate.");
        PostKey(menu, SystemKeyDown, Enter);
        PostKey(menu, SystemKeyDown, Enter, repeat: true);
        await PumpAsync();
        Require(fixture.Clicks.Count == 1 && fixture.Clicks[0] == (row, expected)
            && !fixture.Menu.Visible && !fixture.Host.Active,
            "Alt+Enter did not record exactly one captured alternate and close/unhook the owned menu chain. "
            + System.Text.Json.JsonSerializer.Serialize(new { name, count=fixture.Clicks.Count, expected,
                recorded=fixture.Clicks.Select(click=>new {id=((AttentionItem)click.Row.Tag!).Id,click.Choice}),
                visible=fixture.Menu.Visible,active=fixture.Host.Active,held=fixture.Host.Held,
                observed=fixture.Host.ObservedKeyboardMessages,current=row.CurrentChoice }));
        checks.Add(new { name = "tray.modifier.keyboard." + name, actualQueuedAltEnter = true,
            exactCapturedChoiceOnce = true, repeatEnterDoesNotDispatchTwice = true, closedAndUnhooked = true, noExternalAction = true });
    }

    private static async Task DisabledKeyboardAsync(List<object> checks)
    {
        using var fixture = new Fixture(onlyInert: true);
        await fixture.ShowAsync();
        PostKey(fixture.Menu, SystemKeyDown, Alt);
        PostKey(fixture.Menu, SystemKeyDown, Enter);
        PostKey(fixture.Menu, SystemKeyDown, Enter, repeat: true);
        await PumpAsync();
        Require(fixture.Host.Active && fixture.Host.Held && fixture.Menu.Visible && !fixture.Inert.Enabled
            && fixture.Inert.CurrentChoice is { Kind: "primary", Enabled: false } && fixture.Clicks.Count == 0,
            "A disabled row without an alternate executed or closed the menu on Alt+Enter.");
        checks.Add(new { name = "tray.modifier.keyboard.disabled", actualQueuedInput = true,
            disabledNoAlternateInert = true, menuRetained = true, noAction = true });
    }

    private static async Task MouseActionAsync(string name, bool overflow, bool dismiss, List<object> checks)
    {
        using var fixture = new Fixture();
        await fixture.ShowAsync(overflow);
        var menu = overflow ? fixture.Overflow.DropDown : fixture.Menu;
        PostKey(menu, SystemKeyDown, Alt);
        await PumpAsync();
        var row = dismiss ? fixture.OverflowDismiss : fixture.MainRead;
        var expected = row.CurrentChoice;
        Require(row.Enabled && expected.Kind == (dismiss ? "dismiss" : "read"), "The mouse fixture had no permitted alternate.");
        var x = row.Bounds.Left + row.Bounds.Width / 2;
        var y = row.Bounds.Top + row.Bounds.Height / 2;
        var location = (nint)((y << 16) | (x & 0xFFFF));
        Post(menu, 0x200, 0, location);
        Post(menu, 0x201, 1, location);
        Post(menu, 0x202, 0, location);
        await PumpAsync();
        Require(fixture.Clicks.Count == 1 && fixture.Clicks[0] == (row, expected)
            && !fixture.Menu.Visible && !fixture.Host.Active,
            "Owned queued mouse messages did not record exactly the shown alternate and close the owned menu.");
        checks.Add(new { name = "tray.modifier.mouse." + name, actualOwnedQueuedMouseMessages = true,
            exactShownAlternateOnce = true, closedAndUnhooked = true, noGlobalInputOrExternalAction = true });
    }

    private static async Task DisposeIsolationAsync(List<object> checks)
    {
        var prior = new Fixture(initialHeld: true);
        await prior.ShowAsync(overflow: true);
        var priorHost = prior.Host;
        var priorRows = prior.AllRows;
        var observations = priorHost.ObservedKeyboardMessages;
        prior.Dispose();
        await PumpAsync();
        Require(!priorHost.Active && priorRows.All(row => row.IsDisposed), "Disposing an open owned menu left an active host or undisposed rows.");
        using var fresh = new Fixture();
        await fresh.ShowAsync();
        PostKey(fresh.Menu, SystemKeyDown, Alt);
        PostKey(fresh.Menu, SystemKeyUp, Alt);
        await PumpAsync();
        Require(priorHost.ObservedKeyboardMessages == observations && fresh.Host.ObservedKeyboardMessages == 2
            && fresh.Clicks.Count == 0 && fresh.Menu.Visible && !fresh.Host.Held,
            "A disposed menu filter observed the next owned menu or caused duplicate/dangling keyboard processing.");
        checks.Add(new { name = "tray.modifier.disposeIsolation", disposeWhileOpenUnhooks = true,
            ownedRowsDisposed = true, replacementMenuOwnsOnlyItsMessages = true, noDuplicateSubscriptionsOrActions = true });
    }

    private static async Task UnrelatedOwnedInputAsync(List<object> checks)
    {
        using var fixture = new Fixture();
        await using var unrelated = new OwnedKeyboardQueue();
        var unrelatedHandle = await unrelated.WindowReady.WaitAsync(TimeSpan.FromSeconds(3));
        await fixture.ShowAsync();
        var before = fixture.Host.ObservedKeyboardMessages;
        Require(PostMessage(unrelatedHandle, SystemKeyDown, Alt, KeyFlags(SystemKeyDown)), "Could not queue input to an unrelated owned HWND.");
        var delivered = await unrelated.Delivery.WaitAsync(TimeSpan.FromSeconds(3));
        await PumpAsync();
        Require(delivered.Window == unrelatedHandle && delivered.Message == SystemKeyDown && delivered.Key == Alt
            && fixture.Host.ObservedKeyboardMessages == before && !fixture.Host.Held && fixture.Clicks.Count == 0,
            "An exact delivered keyboard message from an independent owned native queue reached the menu modifier host.");
        PostKey(fixture.Menu, SystemKeyDown, Alt);
        await PumpAsync();
        Require(fixture.Host.ObservedKeyboardMessages == before + 1 && fixture.Host.Held && fixture.Clicks.Count == 0,
            "The scoped filter did not resume processing its actual owned menu HWND.");
        checks.Add(new { name = "tray.modifier.ownedHandleScope", independentStaQueueIsolation = true,
            exactUnrelatedHwndMessageAndKeyDelivered = true, unrelatedOwnedQueuedKeyboardIgnored = true,
            productionDefaultModalMenu = true, currentVisibleMenuQueuedKeyboardObserved = true,
            noSameThreadRawInputRoutingClaim = true, noGlobalInputOrActions = true });
    }

    private static async Task RebuiltOverflowActionAsync(string input, string thread, bool keyboard, List<object> checks)
    {
        using var fixture = new Fixture();
        var originalHost = fixture.Host;
        var oldRows = fixture.AllRows;
        await fixture.ShowAsync(overflow: true);
        fixture.Menu.Close();
        await PumpAsync();
        Require(!fixture.Menu.Visible && !originalHost.Active && fixture.Clicks.Count == 0,
            "The first owned menu chain did not close cleanly before rebuilding its items.");

        // Match the production lifecycle: the root ContextMenuStrip is cached, while
        // every item and child dropdown is replaced before its next opening.
        static void DisposeItems(Forms.ToolStrip owner)
        {
            foreach (var old in owner.Items.Cast<Forms.ToolStripItem>().ToArray()) {
                if (old is Forms.ToolStripDropDownItem child && child.HasDropDownItems) DisposeItems(child.DropDown);
                old.Dispose();
            }
            owner.Items.Clear();
        }
        DisposeItems(fixture.Menu);
        Require(oldRows.All(row => row.IsDisposed) && fixture.Overflow.IsDisposed && fixture.Menu.Items.Count == 0,
            "Rebuilding the owned chain left original rows or its overflow owner undisposed.");

        using var overflow = new Forms.ToolStripMenuItem("Rebuilt owned overflow");
        var target = new InboxReadTarget("owned.inbox", "owned.account", thread, "https://api.example.invalid");
        var item = new AttentionItem("rebuilt." + input, "rebuilt." + input, "waiting", "github",
            "Owned rebuilt URL-less thread", "same cached menu · fresh exact thread " + thread,
            Now.AddDays(-3).ToUnixTimeSeconds(), new("none"), true, false, target);
        using var row = new TrayAttentionRow(item, Now);
        row.Click += (_, _) => fixture.Clicks.Add((row, row.CurrentChoice));
        overflow.DropDownItems.Add(row);
        fixture.Menu.Items.Add(overflow);
        Require(ReferenceEquals(TrayAttentionModifiers.Attach(fixture.Menu), originalHost),
            "Attaching the rebuilt root replaced its cached modifier host.");
        TrayAttentionRow.SizeMenu(fixture.Menu);
        await fixture.ShowAsync();
        overflow.ShowDropDown();
        await PumpAsync();
        Require(overflow.DropDown.Visible && originalHost.Active && !originalHost.Held && !row.Enabled,
            "The rebuilt actual overflow did not open with its primary URL-less row disabled.");
        var observed = originalHost.ObservedKeyboardMessages;
        PostKey(overflow.DropDown, SystemKeyDown, Alt);
        await PumpAsync();
        var expected = AttentionChoices.Alternate(item);
        Require(originalHost.Held && originalHost.ObservedKeyboardMessages == observed + 1
            && row.Enabled && row.CurrentChoice == expected && expected.InboxRead == target && fixture.Clicks.Count == 0,
            "The cached host missed or duplicated Alt on a freshly built child menu, or changed its exact read target.");
        if (keyboard) {
            row.Select();
            await PumpAsync();
            Require(row.Selected, "The rebuilt native overflow row could not be selected for keyboard activation.");
            PostKey(overflow.DropDown, SystemKeyDown, Enter);
            PostKey(overflow.DropDown, SystemKeyDown, Enter, repeat: true);
        } else {
            var x = row.Bounds.Left + row.Bounds.Width / 2;
            var y = row.Bounds.Top + row.Bounds.Height / 2;
            var location = (nint)((y << 16) | (x & 0xFFFF));
            Post(overflow.DropDown, 0x200, 0, location);
            Post(overflow.DropDown, 0x201, 1, location);
            Post(overflow.DropDown, 0x202, 0, location);
        }
        await PumpAsync();
        Require(fixture.Clicks.Count == 1 && fixture.Clicks[0] == (row, expected)
            && !fixture.Menu.Visible && !overflow.DropDown.Visible && !originalHost.Active && !originalHost.Held
            && oldRows.All(old => old.IsDisposed) && ReferenceEquals(TrayAttentionModifiers.Attach(fixture.Menu), originalHost),
            "A rebuilt actual child menu lost its captured alternate, dispatched twice or retained an active/visible old chain: " + input);
        var after = originalHost.ObservedKeyboardMessages;
        PostKey(fixture.Menu, SystemKeyDown, Alt);
        await PumpAsync();
        Require(originalHost.ObservedKeyboardMessages == after && fixture.Clicks.Count == 1,
            "The rebuilt closed root kept a dangling input observer or dispatched a late alternate: " + input);
        checks.Add(new { name = "tray.modifier.rebuiltOverflow." + input, cachedRootAndModifierHost = true,
            originalRowsAndChildOwnerDisposed = true, freshChildHooksOnReopen = true, actualQueuedInput = true,
            exactNewReadTargetOnce = true, wholeChainClosedAndUnhooked = true, noDanglingClosedObservations = true, noExternalAction = true });
    }

    private static Rectangle[] Geometry(Fixture fixture) => new[] { fixture.Menu.Bounds, fixture.Overflow.DropDown.Bounds, fixture.Overflow.Bounds }
        .Concat(fixture.AllRows.Select(row => row.Bounds)).ToArray();

    private static async Task PumpAsync()
    {
        // WPF's real dispatcher retrieves the native queue; no direct adapter/Click invocation.
        for (var turn = 0; turn < 4; turn++) await Dispatcher.Yield(DispatcherPriority.Background);
    }

    private static nint KeyFlags(int message, bool repeat = false) => message == SystemKeyUp
        ? (nint)unchecked((int)0xE0380001) : (nint)(repeat ? 0x60380002 : 0x20380001);
    private static void PostKey(Forms.ToolStrip menu, int message, int key, bool repeat = false) =>
        Post(menu, message, key, key == Enter ? (nint)(repeat ? 0x601C0002 : 0x201C0001)
            : key == Escape ? (nint)0x00010001 : KeyFlags(message, repeat));
    private static void Post(Forms.ToolStrip menu, int message, nint key, nint details)
    {
        Require(menu.IsHandleCreated && PostMessage(menu.Handle, message, key, details), "Could not queue a message to the owned menu HWND.");
    }

    private sealed class OwnedKeyboardQueue : IAsyncDisposable
    {
        private const int StopMessage = 0x8000 + 71;
        private readonly TaskCompletionSource<nint> ready = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly TaskCompletionSource<(nint Window, int Message, nint Key)> delivery = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly TaskCompletionSource<bool> stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly Thread thread;
        private int stopping;
        internal Task<nint> WindowReady => ready.Task;
        internal Task<(nint Window, int Message, nint Key)> Delivery => delivery.Task;

        internal OwnedKeyboardQueue()
        {
            thread = new Thread(Run) { IsBackground = true, Name = "DevDeck owned keyboard queue fixture" };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
        }

        private void Run()
        {
            var sink = new KeyboardSink(delivery);
            Exception? failure = null;
            try {
                // HWND_MESSAGE: no visible surface, activation or desktop input. A separate
                // STA queue avoids WinForms' intentional same-thread modal key retargeting.
                sink.CreateHandle(new Forms.CreateParams { Parent = (nint)(-3), Caption = "DevDeck owned message-only sink" });
                ready.TrySetResult(sink.Handle);
                if (Volatile.Read(ref stopping) == 0) Forms.Application.Run();
            } catch (Exception error) {
                failure = error; ready.TrySetException(error); delivery.TrySetException(error);
            } finally {
                try { if (sink.Handle != 0) sink.DestroyHandle(); }
                catch (Exception error) { failure ??= error; }
                if (failure is null) stopped.TrySetResult(true); else stopped.TrySetException(failure);
            }
        }

        public async ValueTask DisposeAsync()
        {
            Interlocked.Exchange(ref stopping, 1);
            if (!stopped.Task.IsCompleted && ready.Task.IsCompletedSuccessfully)
                Require(PostMessage(ready.Task.Result, StopMessage, 0, 0), "Could not stop the owned native queue fixture.");
            await stopped.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Require(await Task.Run(() => thread.Join(TimeSpan.FromSeconds(3))), "The owned native queue fixture did not terminate.");
        }

        private sealed class KeyboardSink(TaskCompletionSource<(nint Window, int Message, nint Key)> delivered) : Forms.NativeWindow
        {
            protected override void WndProc(ref Forms.Message message)
            {
                if (message.Msg == StopMessage) { Forms.Application.ExitThread(); message.Result = 0; return; }
                if (message.Msg == SystemKeyDown && message.WParam == Alt) {
                    delivered.TrySetResult((message.HWnd, message.Msg, message.WParam));
                    message.Result = 0; return;
                }
                base.WndProc(ref message);
            }
        }
    }

    private static void Require(bool value, string message) { if (!value) throw new IOException(message); }
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessage(nint window, int message, nint wparam, nint lparam);

    private sealed class Fixture : IDisposable
    {
        internal readonly Forms.ContextMenuStrip Menu = new() { ShowImageMargin = false, ShowCheckMargin = false };
        internal readonly Forms.ToolStripMenuItem Overflow = new("Owned overflow");
        internal readonly List<(TrayAttentionRow Row, AttentionChoice Choice)> Clicks = [];
        internal readonly TrayAttentionModifiers Host;
        internal readonly TrayAttentionRow MainRead, MainDismiss, Inert, PrimaryOnly, OverflowRead, OverflowDismiss;
        internal bool InitialHeld;
        internal TrayAttentionRow[] AllRows => [MainRead, MainDismiss, Inert, PrimaryOnly, OverflowRead, OverflowDismiss];

        internal Fixture(bool initialHeld = false, bool onlyInert = false)
        {
            InitialHeld = initialHeld;
            MainRead = Row(ReadItem("main.read", "42"));
            MainDismiss = Row(DismissItem("main.dismiss"));
            Inert = Row(new("inert", "inert", "goodToKnow", "network", "Owned status only", "No action promised", null, new("none"), false, false));
            PrimaryOnly = Row(new("primary", "primary", "waiting", "github", "Owned browser primary", "Owned account", Now.AddDays(-2).ToUnixTimeSeconds(),
                new("open", "https://example.invalid/owned", "github", "owned.account"), true, false));
            OverflowRead = Row(ReadItem("overflow.read", "43"));
            OverflowDismiss = Row(DismissItem("overflow.dismiss"));
            if (onlyInert) Menu.Items.Add(Inert);
            else {
                Menu.Items.AddRange([MainRead, MainDismiss, Inert, PrimaryOnly, Overflow]);
                Overflow.DropDownItems.AddRange([OverflowRead, OverflowDismiss]);
            }
            Host = TrayAttentionModifiers.Attach(Menu, () => InitialHeld);
            TrayAttentionRow.SizeMenu(Menu);
        }

        private TrayAttentionRow Row(AttentionItem item)
        {
            var row = new TrayAttentionRow(item, Now);
            row.Click += (_, _) => Clicks.Add((row, row.CurrentChoice));
            return row;
        }

        internal async Task ShowAsync(bool overflow = false)
        {
            Menu.Show(new System.Drawing.Point(48, 48));
            await PumpAsync();
            Require(Menu.Visible && Host.Active, "The actual owned native menu did not open with its modifier host.");
            if (overflow) {
                Overflow.ShowDropDown();
                await PumpAsync();
                Require(Overflow.DropDown.Visible, "The actual owned overflow menu did not open.");
            }
        }

        public void Dispose()
        {
            Menu.Close(); Menu.Dispose();
            // The disabled-only fixture intentionally leaves its other rows unattached.
            foreach (var row in AllRows) if (!row.IsDisposed) row.Dispose();
            if (!Overflow.IsDisposed) Overflow.Dispose();
        }

        private static AttentionItem ReadItem(string id, string thread) => new(id, id, "waiting", "github",
            "Owned URL-less personal thread & review", "example/repo · exact account", Now.AddDays(-4).ToUnixTimeSeconds(), new("none"), true, false,
            new("owned.inbox", "owned.account", thread, "https://api.example.invalid"));
        private static AttentionItem DismissItem(string id) => new(id, id, "needsFixing", "project",
            "Owned stopped project", "same configured project", Now.AddHours(-2).ToUnixTimeSeconds(), new("showCard", CardID: "owned.project"), true, true);
    }
}
