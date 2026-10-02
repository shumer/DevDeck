using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Owned synthetic sidebar data. No worker, provider or credential access.
internal static class SettingsSidebarSamples
{
    internal static async Task<SettingsWindow> WindowAsync(Application application, string variant)
    {
        if (variant is not ("projects" or "accounts" or "filtered" or "empty")) throw new ArgumentException("Unknown synthetic settings sidebar variant.");
        var path = Path.Combine(Path.GetTempPath(), "devdeck-sidebar-render-" + Guid.NewGuid().ToString("N") + ".json");
        var cards = variant == "empty" ? Array.Empty<CardSettings>() : Enumerable.Range(1, 14).Reverse().Select(index =>
            new CardSettings(new("render.project." + index, index % 2 == 0 ? "Ubuntu-24.04" : "Debian",
                index % 3 == 0 ? "arc" : index % 3 == 1 ? "ddev" : "local", "/owned/render/project-" + index,
                StartCommand: index % 3 == 2 ? "bun run dev" : null),
                index == 12 ? "Shared12 · Équipe · Проект · 長いプロジェクト" : "Shared" + index, Enabled: index != 1 && index != 2)).ToArray();
        var accounts = variant == "empty" ? Array.Empty<RemoteAccountSettings>() : new[] {
            new RemoteAccountSettings("render.account.10", "Account10", "github", "https://api.github.com", [], []),
            new RemoteAccountSettings("render.account.2", "Account2", "gitlab", "https://gitlab.example.invalid", [], [], Enabled: false),
            new RemoteAccountSettings("render.account.1", "Account1", "github", "https://api.github.com", [], [])
        };
        var store = new SettingsStore(path);
        store.Save(new(1, [new("Ubuntu-24.04", "/owned/render/ubuntu"), new("Debian", "/owned/render/debian")], cards,
            Accounts: accounts, Notifications: false, Language: Text.Language));
        var controller = new DeckController(application, store, live: false);
        var owners = (List<ProjectCard>)typeof(DeckController).GetField("cards", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(controller)!;
        var configurations = (Dictionary<string,CardSettings>)typeof(DeckController).GetField("localConfigurations", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(controller)!;
        foreach (var configured in cards.TakeLast(4)) {
            var owner = new ProjectCard(controller, configured, live: false); owner.SetDeckVisible(false); owners.Add(owner);
            configurations[configured.Project.Id] = configured;
            owner.ApplySnapshot(new(owner.Reference.Id, configured.Project.Id.EndsWith(".1", StringComparison.Ordinal) ? "working" : "running",
                "feature/settings-sidebar", null, null, null));
        }
        var window = new SettingsWindow(controller, live: false, tokenAvailable: account => account.Id == "render.account.1");
        window.Closed += (_, _) => {
            controller.CloseViews();
            foreach (var file in new[] { path, path + ".bak" }) if (File.Exists(file)) File.Delete(file);
        };
        await window.SelectPageAsync(variant == "accounts" ? "account:render.account.2"
            : variant == "empty" ? "general" : "project:render.project.2");
        if (variant == "filtered") window.Search.Text = "Shared12";
        return window;
    }
}
