using System;
using System.IO;
using System.Linq;
using System.Windows;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Synthetic configuration only. No worker is started and no credential is read.
internal static class SampleDeck
{
    internal static DeckController Controller(Application application, string? path = null)
    {
        var store = new SettingsStore(path ?? Path.Combine(Path.GetTempPath(), "devdeck-synthetic-" + Guid.NewGuid().ToString("N") + ".json"));
        var settings = new DeckSettings(1, [new("Ubuntu-24.04", "/home/user/.local/share/devdeck/example-worker")],
            Enumerable.Range(0, 7).Select(index => new CardSettings(new("sample.project." + index, "Ubuntu-24.04", "ddev", "/home/user/example-" + index),
                index == 0 ? "Example shop" : "Example project " + (index + 1))).ToArray(), Notifications: true,
            RemoteCards: new[] { "pullRequests","mergeRequests","inbox","actions" }.Select(kind => RemoteSettings(kind) with { Enabled = false }).ToArray(),
            Accounts: [new("sample", "Example work account", "github", "https://api.github.com", [], []),
                new("second", "Personal", "github", "https://api.github.com", [], []), new("lab", "Example GitLab", "gitlab", "https://git.example.com", [], [])]);
        try { store.Save(settings); return new DeckController(application, store, live: false); }
        finally { if (File.Exists(store.Path)) File.Delete(store.Path); }
    }
    internal static RemoteCardSettings RemoteSettings(string kind, bool collapsed = false) => new("sample."+kind, kind switch { "mergeRequests" => "GitLab · merge requests", "inbox" => "GitHub · inbox", "actions" => "GitHub · Actions", _ => "GitHub · pull requests" }, kind,"Ubuntu-24.04",kind == "mergeRequests" ? ["lab"] : ["sample","second"],Collapsed:collapsed);
    internal static RemoteSnapshot Remote(string kind, int count = 5) {
        var id = "sample." + kind; var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var rows = Enumerable.Range(1,count).Select(index => new RemoteRow(index.ToString(),kind == "mergeRequests" ? "lab" : index % 2 == 0 ? "second" : "sample",
            index == 1 ? "IR-6258 - Update checkout validation" : index == 2 ? "Review search results" : "Update dependencies " + index,"example/shop", index == 3 ? null : "https://example.com/items/"+index,
            index == 1 ? "blocked" : index == 2 ? "attention" : "ready",kind == "inbox" ? index == 2 ? "reviewRequested" : "ciActivity" : kind == "actions" ? "main · failure" : "checks failed",index == 2,
            kind is "pullRequests" or "mergeRequests" ? index == 1 ? "CF" : index == 2 ? "RV" : "AP" : null, now - index * 120, index != 5,
            kind is "pullRequests" or "mergeRequests" && index == 1 ? "IR-6258" : null,kind is "pullRequests" or "mergeRequests" && index == 1 ? "Update checkout validation" : null)).ToArray();
        return new(id,kind,kind == "inbox" ? rows.Count(row => row.IsUnread) : count,kind == "inbox" ? 0 : 1,kind == "actions" ? .75 : null,rows,[],false,
            RepositoryCount:2,NamespaceCount:1,ReviewCount:1,ActionableCount:1,RunningCount:1,AverageDurationSeconds:372,WatchedRepositories:["example/shop","example/tools"]);
    }
}
