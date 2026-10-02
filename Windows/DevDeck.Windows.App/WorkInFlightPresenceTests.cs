using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using DevDeck.Windows.Core;
using Forms = System.Windows.Forms;

namespace DevDeck.Windows.App;

internal static class WorkInFlightPresenceTests
{
    internal static Task RunAsync(Application application, List<object> checks)
    {
        var path = Path.Combine(Path.GetTempPath(), "devdeck-wif-presence-" + Guid.NewGuid().ToString("N") + ".json");
        var store = new SettingsStore(path);
        store.Save(new(1, [], [], Language: "en"));
        var controller = new DeckController(application, store, live: false);
        SettingsWindow? window = null;
        try {
            var before = File.ReadAllBytes(path);
            using var menu = new Forms.ContextMenuStrip();
            controller.AddCardMenu(menu);
            var row = menu.Items.OfType<Forms.ToolStripMenuItem>().Single(item => item.Text == Text.L("card.title.workInFlight"));
            Require(row.Enabled && !row.Checked && row.Tag as string == "local.workInFlight",
                "Work in flight is still an unusable tray placeholder; it must be default-off and available without accounts.");
            window = new SettingsWindow(controller, live: false);
            window.Show();
            window.SelectPage("cards");
            window.UpdateLayout();
            var toggle = Descendants<CheckBox>(window.Page).Single(item => item.Tag as string == "local.workInFlight");
            Require(toggle.IsEnabled && toggle.IsChecked == false && System.Windows.Automation.AutomationProperties.GetName(toggle)==Text.L("card.title.workInFlight"),
                "Cards settings still has a disabled Work in flight placeholder.");
            Require(File.ReadAllBytes(path).SequenceEqual(before) && controller.AllLocalViews.Length == 0 && controller.AllRemoteViews.Length == 0,
                "Default-off catalog inspection materializes configuration or starts unrelated owners.");
            checks.Add(new { name = "wif.actualCatalogPresence", availableWithoutAccount = true, defaultOff = true, actualTrayAndCards = true, noWorkerOrCommand = true });
            return Task.CompletedTask;
        } finally {
            window?.Close(); controller.CloseViews();
            foreach (var file in new[] { path, path + ".bak" }) if (File.Exists(file)) File.Delete(file);
        }
    }

    private static System.Collections.Generic.IEnumerable<T> Descendants<T>(DependencyObject parent) where T : DependencyObject
    {
        for (var i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(parent); i++) {
            var child = System.Windows.Media.VisualTreeHelper.GetChild(parent, i);
            if (child is T value) yield return value;
            foreach (var nested in Descendants<T>(child)) yield return nested;
        }
    }
    private static void Require(bool condition, string message) { if (!condition) throw new IOException(message); }
}
