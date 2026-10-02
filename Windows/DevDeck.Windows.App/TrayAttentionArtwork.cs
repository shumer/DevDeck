using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows;
using DevDeck.Windows.Core;
using Forms = System.Windows.Forms;

namespace DevDeck.Windows.App;

/// Draws only an owned synthetic menu through the production item renderer.
internal static class TrayAttentionArtwork
{
    internal static void Write(Application application, string output, string variant)
    {
        var path = Path.Combine(Path.GetTempPath(), "devdeck-tray-artwork-" + Guid.NewGuid().ToString("N") + ".json");
        var commandScene = variant is "deck" or "arrangements" or "forget";
        var alternateScene = variant is "alternate-main" or "alternate-overflow" or "alternate-primary";
        var store = new SettingsStore(path);
        var settings = commandScene ? new DeckSettings(1,[new("Test Linux","/tmp/synthetic-runtime")],
            [new(new("synthetic.ddev","Test Linux","ddev","/tmp/synthetic-project"),"Example shop",X:48,Y:80)],
            Accounts:[new("synthetic","Example account","github","https://api.github.com",[],[])],
            RemoteCards:[new("github.pulls","GitHub pull requests","pullRequests","Test Linux",["synthetic"])],
            Notifications:false,Language:Text.Language) : new DeckSettings(1,[],[],Notifications:false,Language:Text.Language);
        store.Save(settings);
        var controller = new DeckController(application, store, live: false);
        try {
            if(commandScene) {
                // Discovery adds supported catalog cards; capture the same complete set
                // that the real Save command sees, so current-state checkmarks are honest.
                controller.SaveArrangement("Work & reviews");
                controller.SetCardCollapsed("synthetic.ddev",true);
                controller.SavePosition("synthetic.ddev",520,80);
                controller.SaveArrangement("Focus · PHP 8.4");
            }
            var now = DateTimeOffset.UtcNow;
            if (alternateScene) controller.ObserveAttention(new("synthetic:artwork",AttentionActionSamples.Items(),[]));
            else if (variant != "calm" && !commandScene) {
                var items = Enumerable.Range(0, 5).Select(index => new AttentionItem("sample.wait." + index, "sample.wait." + index, "waiting", index == 0 ? "gitlab" : "github",
                    Text.L("attention.inbox.review.prefix") + ": Example shop " + (index + 1),
                    "example/shop #" + (101 + index) + " · Example work account", now.AddMinutes(-12 - index * 60).ToUnixTimeSeconds(),
                    new("open", Url: "https://example.test/review/" + index), true, false))
                    .Concat(new[] { new AttentionItem("sample.token", "sample.token", "needsFixing", "token", Text.L("attention.account.rejected.title", "GitHub", "Example account"),
                        Text.L("attention.account.rejected.subtitle", "HTTP 401"), now.AddDays(-2).ToUnixTimeSeconds(), new("none"), true, false) }).ToArray();
                controller.ObserveAttention(new("synthetic:artwork", items, []));
            } else controller.ObserveAttention(new("synthetic:artwork", [], []));
            using var menu = new Forms.ContextMenuStrip();
            typeof(DeckController).GetMethod("BuildMenu", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(controller, [menu]);
            // Keep the attention section; other settings and real account data never enter this fixture.
            if(!commandScene) {
                var keep = menu.Items.Cast<Forms.ToolStripItem>().TakeWhile(item => item is not Forms.ToolStripSeparator).Count();
                while (menu.Items.Count > keep) { var item = menu.Items[keep]; menu.Items.RemoveAt(keep); item.Dispose(); }
            }
            var arrangements = commandScene ? menu.Items.OfType<Forms.ToolStripMenuItem>().Single(item=>item.Tag as string=="tray.arrangements") : null;
            if(alternateScene && variant!="alternate-primary") {
                foreach(var row in menu.Items.OfType<TrayAttentionRow>())row.SetAlternate(true);
                foreach(var child in menu.Items.OfType<Forms.ToolStripDropDownItem>())
                    foreach(var row in child.DropDownItems.OfType<TrayAttentionRow>())row.SetAlternate(true);
            }
            Forms.ToolStrip surface = variant is "overflow" or "alternate-overflow" ? menu.Items.OfType<Forms.ToolStripMenuItem>().Single(item => item.DropDownItems.Count > 0).DropDown
                : variant == "arrangements" ? arrangements!.DropDown
                : variant == "forget" ? arrangements!.DropDownItems.OfType<Forms.ToolStripMenuItem>().Single(item=>item.Tag as string=="arrangement.forgetMenu").DropDown : menu;
            // Establish the hidden native surface before measuring the owned bitmap.
            _ = surface.Handle;
            surface.PerformLayout(); surface.Size = surface.GetPreferredSize(System.Drawing.Size.Empty); surface.PerformLayout();
            using var bitmap = new Bitmap(surface.Width, surface.Height);
            surface.DrawToBitmap(bitmap, new(0, 0, bitmap.Width, bitmap.Height));
            bitmap.Save(output, ImageFormat.Png);
        } finally {
            controller.CloseViews();
            foreach (var file in new[] { path, path + ".bak" }) if (File.Exists(file)) File.Delete(file);
        }
    }
}
