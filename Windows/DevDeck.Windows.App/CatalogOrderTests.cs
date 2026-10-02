using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;
using Forms = System.Windows.Forms;

namespace DevDeck.Windows.App;

/// Synthetic native menus and widgets only; no worker, credential, browser or lifecycle action.
internal static class CatalogOrderTests
{
    internal static async Task RunAsync(Application application, List<object> checks)
    {
        var path = Path.Combine(Path.GetTempPath(), "devdeck-catalog-order-" + Guid.NewGuid().ToString("N") + ".json");
        var store = new SettingsStore(path);
        store.Save(Fixture());
        var controller = new DeckController(application, store, live:false);
        try {
            Text.Use("en");
            CheckMenu(controller, store, "en", checks);
            await CheckMenuChangesAsync(controller, checks);
            await controller.SaveSettingsAsync(Fixture());
            await CheckArrangeAsync(controller, store, checks);
        } finally {
            controller.CloseViews();
            foreach (var file in new[] { path, path + ".bak" }) if (File.Exists(file)) File.Delete(file);
            Text.Use("en");
        }
    }

    private static DeckSettings Fixture()
    {
        CardSettings Project(string id, string kind, string title, bool enabled=true, bool compact=false) =>
            new(new(id,"Test Linux",kind,"/tmp/catalog-" + id),title,enabled,X:330,Y:180,Collapsed:compact);
        RemoteCardSettings Remote(string id, string kind, string title, bool enabled=true, bool compact=false) =>
            new(id,title,kind,"Test Linux",kind == "mergeRequests" ? ["lab"] : ["sample","second"],enabled,X:470,Y:240,Collapsed:compact);
        return new(1,[new("Test Linux","/tmp/devdeck-catalog-runtime")],[
            Project("local.10","local","App10",compact:true),
            Project("ddev.10","ddev","App10",compact:true),
            Project("arc.10","arc","App10",enabled:false) with { X=3400,Y=3100 },
            Project("local.tie.b","local","CASE2",compact:true),
            Project("local.2","local","App2"),
            Project("arc.2","arc","App2"),
            Project("ddev.2","ddev","App2"),
            Project("local.tie.a","local","Case2",compact:true)
        ], Accounts:[
            new("sample","Synthetic work","github","https://api.github.com",[],[]),
            new("second","Synthetic personal","github","https://api.github.com",[],[]),
            new("lab","Synthetic GitLab","gitlab","https://git.example.test",[],[])
        ], RemoteCards:[
            Remote("legacy.merges","mergeRequests","Zulu merges",compact:true),
            Remote("legacy.pulls","pullRequests","Zulu pulls"),
            Remote("github.actions","actions","Actions",compact:true),
            Remote("custom.beta10","pullRequests","Beta10"),
            Remote("github.pullRequests","pullRequests","Alpha10",compact:true),
            Remote("github.inbox","inbox","Inbox"),
            Remote("legacy.alpha2.b","pullRequests","ALPHA2",enabled:false) with { X=3500,Y=3200 },
            Remote("custom.alpha2.a","pullRequests","Alpha2",compact:true),
            Remote("gitlab.mergeRequests","mergeRequests","Beta2",enabled:false) with { X=3600,Y=3300 }
        ], Language:"en",Notifications:false);
    }

    private static readonly string[] ProjectIDs = ["arc.2","arc.10","ddev.2","ddev.10","local.2","local.10","local.tie.a","local.tie.b"];
    private static readonly string[] RemoteIDs = ["legacy.pulls","github.inbox","github.actions","legacy.merges","custom.alpha2.a","legacy.alpha2.b","github.pullRequests","gitlab.mergeRequests","custom.beta10"];

    private static void CheckMenu(DeckController controller, SettingsStore store, string language, List<object> checks)
    {
        var persisted = File.ReadAllBytes(store.Path);
        using var menu = new Forms.ContextMenuStrip();
        controller.AddCardMenu(menu);
        var groups = Groups(menu);
        // This is deliberately the first assertion: the old menu preserves App10 before App2.
        Require(groups.Length == 3 && groups.SelectMany(group => Rows(group).Select(row => (string)row.Tag!)).SequenceEqual(ProjectIDs),
            "Tray projects do not follow Arc/DDEV/plain, natural App2/App10 and stable case-equivalent title order.");
        foreach (var (group,kind) in groups.Zip(new[] { "arc","ddev","local" })) {
            var saved = controller.Settings.Cards.Where(card => card.Project.Kind == kind).ToArray();
            Require(group.Text == Text.L(kind == "local" ? "menu.group.projects" : "menu.group." + kind) + $" ({saved.Count(card => card.Enabled)}/{saved.Length})",
                "Tray project group loses its localized title or visible/total count.");
            foreach (var row in Rows(group)) {
                var card = saved.Single(card => card.Project.Id == (string)row.Tag!);
                Require(row.Checked == card.Enabled && row.Text == card.Title.Replace("&","&&",StringComparison.Ordinal),"Tray project visibility or caption is stale.");
            }
        }
        Require(!Rows(groups[0]).Single(row => (string)row.Tag! == "arc.10").Checked,"Hidden project disappeared from the tray instead of remaining unchecked.");
        Require(File.ReadAllBytes(store.Path).SequenceEqual(persisted),"Building the tray menu changed saved settings.");
        checks.Add(new { name=language+".catalog.tray.projects", kindOrder=true, natural2Before10=true, stableCaseTies=true, hiddenRetained=true, localizedCounts=true, noPersistence=true });

        var tagged = menu.Items.OfType<Forms.ToolStripMenuItem>().Where(row => row.Tag is string).ToArray();
        Require(tagged.Take(4).Select(row => (string)row.Tag!).SequenceEqual(new[] { "pullRequests","inbox","actions","mergeRequests" }),"Tray builtin roles no longer follow the original catalog.");
        var selected = RemoteCardCatalog.All.Select(descriptor => RemoteCardCatalog.Resolve(controller.Settings,descriptor.Kind)!.Id).ToArray();
        Require(selected.SequenceEqual(RemoteIDs.Take(4)),"Tray changed the first saved legacy card selected by a builtin role.");
        Require(tagged[4].Tag as string == CheckoutCatalog.CardID && tagged[4].Enabled && !tagged[4].Checked,
            "Tray fixed work-in-flight entry is missing, disabled, enabled by default or misplaced after builtin roles.");
        Require(tagged.Skip(5).Select(row => (string)row.Tag!).SequenceEqual(RemoteIDs.Skip(4)),"Tray custom/legacy remote cards do not use natural title and stable ID order after builtin roles and work-in-flight.");
        foreach (var (row,descriptor) in tagged.Take(4).Zip(RemoteCardCatalog.All))
            Require(row.Checked == RemoteCardCatalog.Resolve(controller.Settings,descriptor.Kind)!.Enabled && row.Text == Text.L(descriptor.TitleKey),"Builtin menu visibility/caption no longer reflects its resolved legacy card.");
        foreach (var row in tagged.Skip(5)) {
            var saved = controller.Settings.RemoteCardList.Single(card => card.Id == (string)row.Tag!);
            Require(row.Checked == saved.Enabled && row.Text == saved.Title.Replace("&","&&",StringComparison.Ordinal),"Custom remote visibility/caption is stale.");
        }
        checks.Add(new { name=language+".catalog.tray.remote", originalRoleOrder=true, selectedLegacyIDsRetained=true, extraCanonicalIndependent=true, naturalCustomTitles=true, hiddenRetained=true });
    }

    private static async Task CheckMenuChangesAsync(DeckController controller, List<object> checks)
    {
        var projectOrder = controller.Settings.Cards.Select(card => card.Project.Id).ToArray();
        var remoteOrder = controller.Settings.RemoteCardList.Select(card => card.Id).ToArray();
        await controller.SaveSettingsAsync(current => current with {
            Cards=current.Cards.Select(card => card.Project.Id switch {
                "local.10" => card with { Title="App1 & tools" }, "ddev.2" => card with { Enabled=false }, _ => card }).ToArray(),
            RemoteCards=current.RemoteCardList.Select(card => card.Id switch {
                "custom.beta10" => card with { Title="Alpha1 & tools" }, "github.pullRequests" => card with { Enabled=false }, _ => card }).ToArray()
        });
        using var menu = new Forms.ContextMenuStrip(); controller.AddCardMenu(menu);
        var groups = Groups(menu);
        Require(Rows(groups[2]).Select(row => (string)row.Tag!).SequenceEqual(new[] { "local.10","local.2","local.tie.a","local.tie.b" })
            && Rows(groups[2])[0].Text == "App1 && tools", "Reopened tray does not reorder/escape a renamed project.");
        Require(groups[1].Text!.EndsWith(" (1/2)",StringComparison.Ordinal) && !Rows(groups[1]).Single(row => (string)row.Tag! == "ddev.2").Checked,
            "Reopened tray does not refresh project show/hide state or group count.");
        var tagged=menu.Items.OfType<Forms.ToolStripMenuItem>().Where(row => row.Tag is string).ToArray();
        Require(tagged[4].Tag as string == CheckoutCatalog.CardID && tagged[4].Enabled && !tagged[4].Checked
            && tagged.Skip(5).Select(row => (string)row.Tag!).SequenceEqual(new[] { "custom.beta10","custom.alpha2.a","legacy.alpha2.b","github.pullRequests","gitlab.mergeRequests" })
            && tagged[5].Text == "Alpha1 && tools", "Reopened tray does not preserve work-in-flight placement or naturally reorder/escape renamed custom remote cards.");
        Require(tagged[0].Checked && !tagged.Single(row => (string)row.Tag! == "github.pullRequests").Checked
            && RemoteCardCatalog.Resolve(controller.Settings,"pullRequests")!.Id == "legacy.pulls", "Hiding the extra canonical card changes the builtin legacy role selection.");
        Require(controller.Settings.Cards.Select(card => card.Project.Id).SequenceEqual(projectOrder)
            && controller.Settings.RemoteCardList.Select(card => card.Id).SequenceEqual(remoteOrder),"Menu refresh rewrote persisted card array order.");
        checks.Add(new { name="catalog.tray.rebuild", renamedTitlesReordered=true, ampersandsEscaped=true, showHideAndCountsCurrent=true, legacyRoleIndependent=true, savedArrayOrderPreserved=true });
    }

    private static async Task CheckArrangeAsync(DeckController controller, SettingsStore store, List<object> checks)
    {
        foreach (var card in controller.LocalViews)
            card.ApplySnapshot(new(card.Reference.Id,"running","feature/catalog","http://localhost:3112","Fixture framework",null,RepositoryURL:"https://example.test/repository",VersionsLine:card.Reference.Kind == "ddev" ? "php 8.4 · mysql 8.0" : null));
        foreach (var card in controller.RemoteViews) {
            var settings=controller.Settings.RemoteCardList.Single(saved => saved.Id == card.CardID);
            card.ApplySnapshot(SampleDeck.Remote(settings.Kind,settings.Collapsed ? 1 : 4) with { CardID=card.CardID });
        }
        var busy=controller.LocalViews.Single(card => card.Reference.Id == "local.10"); busy.ShowOperation("start");
        var mutating=controller.RemoteViews.Single(card => card.CardID == "github.actions"); mutating.SetMutationPresentation(true);
        await Dispatcher.Yield(DispatcherPriority.Background);
        var before=Windows(controller);
        foreach (var (pair,index) in before.Select((pair,index) => (pair,index))) { pair.Value.UpdateLayout(); pair.Value.Left=150; pair.Value.Top=180+index*7; }
        busy.Left=64; busy.Top=80;
        var anchorX=busy.Left; var anchorY=busy.Top;
        var handles=before.ToDictionary(pair => pair.Key,pair => new WindowInteropHelper(pair.Value).Handle,StringComparer.Ordinal);
        Require(handles.Values.All(handle => handle != 0) && before.Values.All(WidgetWindow.IsExcluded),"Synthetic catalog fixture lacks native tool-window handles.");
        var localSnapshots=controller.LocalViews.ToDictionary(card => card.Reference.Id,card => card.Latest,StringComparer.Ordinal);
        var remoteSnapshots=controller.RemoteViews.ToDictionary(card => card.CardID,card => card.Latest,StringComparer.Ordinal);
        var original=controller.Settings;
        var expected=RemoteIDs.Concat(ProjectIDs).Where(before.ContainsKey).ToArray();
        var area=new Rect(0,0,2400,900);
        await controller.ArrangeAsync(area);
        await Dispatcher.Yield(DispatcherPriority.Background);
        var after=Windows(controller);
        var flow=after.OrderBy(pair => pair.Value.Left).ThenBy(pair => pair.Value.Top).Select(pair => pair.Key).ToArray();
        Require(flow.SequenceEqual(expected),"Measured tidy does not use resolved builtin/legacy roles then natural Arc/DDEV/plain catalog order.");
        Require(after[expected[0]].Left == anchorX && after[expected[0]].Top == anchorY,"Catalog tidy lost the existing topmost window's anchor.");
        checks.Add(new { name="catalog.tidy.order", shuffledSavedArrays=true, resolvedLegacyRoleFirst=true, remoteBeforeProjects=true, naturalKindTitleOrder=true, topmostAnchorPreserved=true });

        Require(after.Count == before.Count && before.All(pair => ReferenceEquals(pair.Value,after[pair.Key]) && handles[pair.Key] == new WindowInteropHelper(after[pair.Key]).Handle)
            && after.Values.All(WidgetWindow.IsExcluded),"Catalog tidy rebuilds widgets or changes native identity/switcher exclusion.");
        Require(controller.LocalViews.All(card => ReferenceEquals(localSnapshots[card.Reference.Id],card.Latest))
            && controller.RemoteViews.All(card => ReferenceEquals(remoteSnapshots[card.CardID],card.Latest))
            && !busy.CanRefresh && mutating.IsMutating && !controller.LocalPollEnabled,"Catalog tidy loses snapshots, synthetic operation presentation or the no-worker guard.");
        checks.Add(new { name="catalog.tidy.identity", hwndsAndWindowsPreserved=true, allSnapshotsPreserved=true, compactBusyAndMutationRetained=true, altTabExcluded=true, noWorkerStarted=true });

        var columns=after.Values.GroupBy(window => window.Left).OrderBy(column => column.Key).ToArray();
        Require(columns.Length >= 2 && after.Values.Select(window => ReadBounds(window).Bottom-ReadBounds(window).Top).Distinct().Count() >= 3,"Catalog tidy fixture did not exercise wrapping and mixed actual card heights.");
        foreach (var column in columns) {
            var stack=column.OrderBy(window => window.Top).ToArray();
            for (var index=1;index<stack.Length;index++) {
                var previous=ReadBounds(stack[index-1]); var current=ReadBounds(stack[index]);
                Require(Math.Abs(current.Top-previous.Bottom-12*VisualTreeHelper.GetDpi(stack[index]).DpiScaleY) <= 1,"Catalog tidy gaps differ from twelve DIPs measured in native pixels.");
            }
            Require(stack.All(window => ReadBounds(window).Bottom/VisualTreeHelper.GetDpi(window).DpiScaleY <= area.Bottom+1),"Catalog tidy failed to wrap before the work-area bottom.");
        }
        for (var index=1;index<columns.Length;index++) {
            var previous=columns[index-1].First(); var current=columns[index].First();
            Require(Math.Abs(ReadBounds(current).Left-ReadBounds(previous).Right-12*VisualTreeHelper.GetDpi(current).DpiScaleX) <= 1,"Catalog tidy column gap differs from twelve DIPs.");
        }
        checks.Add(new { name="catalog.tidy.geometry", actualMixedHeights=true, wrapsAtWorkArea=true, nativeVerticalAndHorizontalGaps=12, pixelTolerance=1 });

        var saved=store.Load();
        Require(saved.Cards.Select(card => card.Project.Id).SequenceEqual(original.Cards.Select(card => card.Project.Id))
            && saved.RemoteCardList.Select(card => card.Id).SequenceEqual(original.RemoteCardList.Select(card => card.Id)),"Catalog tidy rewrote saved card array order.");
        var preserved=saved with {
            Cards=saved.Cards.Select(card => { var old=original.Cards.Single(item => item.Project.Id == card.Project.Id); return card with { X=old.X,Y=old.Y }; }).ToArray(),
            RemoteCards=saved.RemoteCardList.Select(card => { var old=original.RemoteCardList.Single(item => item.Id == card.Id); return card with { X=old.X,Y=old.Y }; }).ToArray()
        };
        Require(JsonSerializer.Serialize(preserved,WorkerProtocol.Json) == JsonSerializer.Serialize(original,WorkerProtocol.Json),"Catalog tidy changed a caption, scope, compact state, preference or identity.");
        foreach (var card in original.Cards.Where(card => !before.ContainsKey(card.Project.Id)))
            Require(saved.Cards.Single(item => item.Project.Id == card.Project.Id).X == card.X && saved.Cards.Single(item => item.Project.Id == card.Project.Id).Y == card.Y,"Catalog tidy moved a hidden local card.");
        foreach (var card in original.RemoteCardList.Where(card => !before.ContainsKey(card.Id)))
            Require(saved.RemoteCardList.Single(item => item.Id == card.Id).X == card.X && saved.RemoteCardList.Single(item => item.Id == card.Id).Y == card.Y,"Catalog tidy moved a hidden remote card.");
        foreach (var pair in after) {
            var local=saved.Cards.FirstOrDefault(card => card.Project.Id == pair.Key);
            var remote=saved.RemoteCardList.FirstOrDefault(card => card.Id == pair.Key);
            var bounds=ReadBounds(pair.Value);var dpi=VisualTreeHelper.GetDpi(pair.Value);
            Require(Math.Abs((local?.X ?? remote!.X)*dpi.DpiScaleX-bounds.Left)<=1 && Math.Abs((local?.Y ?? remote!.Y)*dpi.DpiScaleY-bounds.Top)<=1,
                "Catalog tidy did not persist native placements by stable ID within one device pixel.");
        }
        checks.Add(new { name="catalog.tidy.persistence", savedArrayOrderPreserved=true, hiddenLocalAndRemotePositionsPreserved=true, scopesPreferencesCompactAndIDsPreserved=true, visiblePlacementsSavedByID=true });
    }

    private static Forms.ToolStripMenuItem[] Groups(Forms.ContextMenuStrip menu) => menu.Items.OfType<Forms.ToolStripMenuItem>().Where(row => row.DropDownItems.Count > 0).ToArray();
    private static Forms.ToolStripMenuItem[] Rows(Forms.ToolStripMenuItem group) => group.DropDownItems.OfType<Forms.ToolStripMenuItem>().ToArray();
    private static Dictionary<string,Window> Windows(DeckController controller) => controller.RemoteViews.Select(card => (ID:card.CardID,Window:(Window)card))
        .Concat(controller.LocalViews.Select(card => (ID:card.Reference.Id,Window:(Window)card))).ToDictionary(pair => pair.ID,pair => pair.Window,StringComparer.Ordinal);
    private static void Require(bool condition, string message) { if (!condition) throw new IOException(message); }
    [StructLayout(LayoutKind.Sequential)] private struct NativeBounds { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetWindowRect(nint window,out NativeBounds bounds);
    private static NativeBounds ReadBounds(Window window) => GetWindowRect(new WindowInteropHelper(window).Handle,out var bounds) ? bounds : throw new IOException("Cannot measure synthetic catalog widget bounds.");
}
