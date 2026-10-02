using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal static class AttentionActivationTests
{
    internal static async Task ShowCardAsync(Application application, List<object> checks)
    {
        var path = Path.Combine(Path.GetTempPath(), "devdeck-attention-activation-" + Guid.NewGuid().ToString("N") + ".json");
        var store = new SettingsStore(path);
        var saved = new CardSettings(new("owned.hidden", "Ubuntu-24.04", "local", "/home/owned/example"), "Owned hidden", Enabled:false);
        store.Save(DeckSettings.Empty with { Workers=[new("Ubuntu-24.04","/tmp/devdeck-owned-fixture")], Cards=[saved] });
        var controller = new DeckController(application, store, live:false);
        try {
            typeof(DeckController).GetMethod("RebuildCards", BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(controller,null);
            var owner = controller.AllLocalViews.Single();
            owner.SetDeckVisible(true); owner.SetDeckVisible(false);
            var hwnd = new WindowInteropHelper(owner).Handle;
            await controller.ExecuteAttentionAsync(new("showCard", CardID:saved.Project.Id));
            if (!controller.Settings.Cards.Single().Enabled || !store.Load().Cards.Single().Enabled
                || !owner.DeckVisible || !owner.IsVisible || hwnd==0
                || !ReferenceEquals(controller.AllLocalViews.Single(),owner)
                || new WindowInteropHelper(owner).Handle!=hwnd || !controller.IsShowingLogs(saved.Project.Id))
                throw new IOException("Attention showCard does not enable and present the same hidden owner with its log.");
            var windows = application.Windows.Count;
            await controller.ExecuteAttentionAsync(new("showCard", CardID:saved.Project.Id));
            if (application.Windows.Count!=windows) throw new IOException("Repeated showCard duplicates the owned log.");
            await controller.ExecuteAttentionAsync(new("showCard", CardID:"removed.card"));
            if (application.Windows.Count!=windows || controller.Settings.Cards.Length!=1)
                throw new IOException("A removed attention target creates a new card or log.");
            checks.Add(new {name="attention.showCard.retainedHiddenOwner", sameHwnd=true, enabledPersisted=true, oneLog=true, missingTargetNoOp=true});
        } finally {
            controller.CloseViews();
            foreach (var file in new[]{path,path+".bak"}) if (File.Exists(file)) File.Delete(file);
        }
    }
}
