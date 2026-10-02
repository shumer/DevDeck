using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using DevDeck.Windows.Core;
using Forms = System.Windows.Forms;

namespace DevDeck.Windows.App;

/// Rebuild the real controller's open menu, then queue input only to its owned HWNDs.
internal static class TrayAttentionMenuRebuildTests
{
    internal static async Task RunAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        var path = Path.Combine(Path.GetTempPath(), "devdeck-tray-menu-rebuild-" + Guid.NewGuid().ToString("N") + ".json");
        var store = new SettingsStore(path);
        store.Save(new(1, [], [], Language:"en", Notifications:false));
        var controller = new DeckController(application, store, live:false);
        using var menu = new Forms.ContextMenuStrip { ShowImageMargin=false, ShowCheckMargin=false };
        var recorded = new List<AttentionChoice>();
        try {
            controller.InboxTokenReader = _ => throw new IOException("Unexpected visible-menu fixture credential access.");
            controller.InboxWriteSender = (_, _, _, _) => throw new IOException("Unexpected visible-menu fixture provider write.");
            var persisted = File.ReadAllBytes(path);
            var now = DateTimeOffset.UtcNow;
            var items = Enumerable.Range(0, 5).Select(index => {
                var thread = (100 + index).ToString(System.Globalization.CultureInfo.InvariantCulture);
                return new AttentionItem("owned-rebuild-" + thread, "owned-rebuild-" + thread, "waiting", "github",
                    "Owned URL-less thread " + thread, "Captured exact account and thread", now.AddDays(index - 5).ToUnixTimeSeconds(),
                    new("none"), false, false, new("owned.fixture.inbox", "owned.fixture.account", thread, "https://api.example.invalid"));
            }).ToArray();
            controller.ObserveAttention(new("synthetic:visible-menu-rebuild", items, []));
            var checkedAt = controller.LastCheckedAt;
            // Supply only the opening's modifier sample; later transitions use queued input.
            var host = TrayAttentionModifiers.Attach(menu, () => false);
            Rebuild(controller, menu);
            var oldRows = Rows(menu).ToArray();
            var oldItems = Items(menu).ToArray();
            Require(oldRows.Length == 5 && oldRows.All(row => !row.Enabled), "The actual controller did not build five disabled URL-less primary rows.");
            menu.Show(new System.Drawing.Point(48, 48));
            await PumpAsync();
            Require(menu.Visible && host.Active, "The real controller's owned menu did not open with its modifier host.");
            PostKey(menu, 0x104, 0x12, (nint)0x20380001);
            await PumpAsync();
            Require(host.Held && oldRows.All(row => row.CurrentChoice.Kind == "read" && row.Enabled) && recorded.Count == 0,
                "Queued Alt did not expose the original permitted choices before visible rebuild.");

            var rebuilding = false;
            var closedDuringRebuild = 0;
            var closedBeforeDisposeAndUnhooked = false;
            // Registered after Attach: the host's Closed handler must finish before this observation.
            menu.Closed += (_, _) => {
                if (!rebuilding) return;
                closedDuringRebuild++;
                closedBeforeDisposeAndUnhooked = !host.Active && !host.Held && oldItems.All(item => !item.IsDisposed);
            };
            Text.Use("ru");
            rebuilding = true;
            try { Rebuild(controller, menu); }
            finally { rebuilding = false; }
            Require(closedDuringRebuild == 1 && closedBeforeDisposeAndUnhooked && !menu.Visible && !host.Active && !host.Held,
                "Visible BuildMenu did not close/unhook before disposing its old chain: closes=" + closedDuringRebuild
                + ", cleanClose=" + closedBeforeDisposeAndUnhooked + ", visible=" + menu.Visible + ", active=" + host.Active + ".");
            Require(oldItems.All(item => item.IsDisposed) && ReferenceEquals(host, TrayAttentionModifiers.Attach(menu)),
                "Visible rebuild retained old items or replaced the cached root's modifier host.");
            var refresh = menu.Items.Cast<Forms.ToolStripItem>().Single(item => item.Tag as string == "tray.refresh");
            Require(refresh.Text == Text.L("menu.refresh"), "Rebuilt actual menu retained its previous language.");

            var overflow = menu.Items.OfType<Forms.ToolStripMenuItem>().Single(item => item.DropDownItems.OfType<TrayAttentionRow>().Any());
            var row = overflow.DropDownItems.OfType<TrayAttentionRow>().Single(candidate => candidate.Tag is AttentionItem value && value.Id == items[4].Id);
            var expected = AttentionChoices.Alternate(items[4]);
            row.Click += (_, _) => recorded.Add(row.CurrentChoice);
            menu.Show(new System.Drawing.Point(48, 48));
            await PumpAsync();
            overflow.ShowDropDown();
            await PumpAsync();
            Require(menu.Visible && overflow.DropDown.Visible && host.Active && !host.Held && !row.Enabled,
                "The cached root's rebuilt child did not reopen with its original disabled primary choice.");
            PostKey(overflow.DropDown, 0x104, 0x12, (nint)0x20380001);
            await PumpAsync();
            Require(host.Held && row.Enabled && row.CurrentChoice == expected
                && row.AccessibleName?.Contains(Text.L("menu.markRead", items[4].Title), StringComparison.Ordinal) == true,
                "Rebuilt child missed its current localized alternate or changed the exact read target.");
            row.Select();
            await PumpAsync();
            Require(row.Selected, "Rebuilt owned child row could not be selected for actual keyboard activation.");
            PostKey(overflow.DropDown, 0x104, 0x0D, (nint)0x201C0001);
            PostKey(overflow.DropDown, 0x104, 0x0D, (nint)0x601C0002);
            await PumpAsync();
            Require(recorded.SequenceEqual(new[] { expected }) && !menu.Visible && !overflow.DropDown.Visible && !host.Active && !host.Held,
                "Actual queued activation after visible rebuild lost its captured target, dispatched twice or retained the old menu host.");
            var workers = typeof(DeckController).GetFields(BindingFlags.Instance | BindingFlags.NonPublic)
                .Where(field => field.FieldType == typeof(WorkerManager)).Select(field => field.GetValue(controller))
                .Sum(manager => ((IDictionary)typeof(WorkerManager).GetField("workers", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(manager)!).Count);
            Require(workers == 0 && !controller.LocalPollEnabled && !controller.SharedPollEnabled
                && File.ReadAllBytes(path).SequenceEqual(persisted) && controller.LastCheckedAt == checkedAt,
                "Synthetic menu rebuild accessed a worker/poll, changed settings or manufactured a completed read.");
            checks.Add(new { name="tray.modifier.controllerVisibleRebuild", actualPrivateBuildMenuWhileShown=true,
                closeAndUnhookBeforeOldDisposal=true, sameRootAndCachedHost=true, currentLanguageAndExactChoice=true,
                rebuiltOverflowQueuedActivationOnce=true, noWorkerCredentialProviderOrSettingsChanges=true });
        } finally {
            menu.Close(); controller.CloseViews(); Text.Use(language);
            foreach (var file in new[] { path, path + ".bak" }) if (File.Exists(file)) File.Delete(file);
        }
    }

    private static void Rebuild(DeckController controller, Forms.ContextMenuStrip menu) =>
        typeof(DeckController).GetMethod("BuildMenu", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(controller, [menu]);
    private static IEnumerable<Forms.ToolStripItem> Items(Forms.ToolStrip owner)
    {
        foreach (Forms.ToolStripItem item in owner.Items) {
            yield return item;
            if (item is Forms.ToolStripDropDownItem child && child.HasDropDownItems)
                foreach (var descendant in Items(child.DropDown)) yield return descendant;
        }
    }
    private static IEnumerable<TrayAttentionRow> Rows(Forms.ToolStrip owner) => Items(owner).OfType<TrayAttentionRow>();
    private static async Task PumpAsync() { for (var turn=0; turn<4; turn++) await Dispatcher.Yield(DispatcherPriority.Background); }
    private static void PostKey(Forms.ToolStrip owner, int message, nint key, nint details) =>
        Require(owner.IsHandleCreated && PostMessage(owner.Handle, message, key, details), "Could not queue input to the owned menu HWND.");
    private static void Require(bool value, string message) { if (!value) throw new IOException(message); }
    [DllImport("user32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessage(nint window, int message, nint key, nint details);
}
