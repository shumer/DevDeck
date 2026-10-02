using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Actual choice dispatcher with owned settings and injected launch/credential seams only.
internal static class AttentionPrimaryDispatchTests
{
    internal static async Task RunAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        try {
            using var fixture = new Fixture(application);
            await CapturedBrowserAsync(fixture, checks);
            await OpenAdmissionAsync(fixture, checks);
            await AccountSettingsAsync(fixture, checks);
            await DockerAsync(fixture, checks);
            await LegacyTerminalAsync(fixture, checks);
            await CheckoutTerminalAsync(fixture, checks);
            await ChoiceGuardsAsync(fixture, checks);
            await ClosingGuardsAsync(fixture, checks);
        } finally { Text.Use(language); }
    }

    private static async Task CapturedBrowserAsync(Fixture fixture, List<object> checks)
    {
        fixture.Reset(); fixture.ClearCalls();
        var github = Item("captured-github", new("open", Url: "https://example.test/review/41", Service: "github", AccountID: "second.github"));
        var changed = fixture.Baseline.AccountList.Select(account => account.Id == "second.github"
            ? account with { Browser = "brave", BrowserProfile = "Profile 9" } : account).ToArray();
        fixture.Set(fixture.Baseline with { Accounts = changed });
        Require(await fixture.ChooseAsync(github) && fixture.Browsers.SequenceEqual(new[] { ("brave", (string?)"Profile 9", github.Action.Url!) }),
            "Attention primary uses the first account or captured old browser/profile instead of the exact account's current choice.");
        var gitlab = Item("captured-gitlab", new("open", Url: "https://gitlab.example.test/team/review/9", Service: "gitlab", AccountID: "owned.gitlab"));
        Require(await fixture.ChooseAsync(gitlab) && fixture.Browsers.Last() == ("firefox", null, gitlab.Action.Url!)
            && fixture.Browsers.Count == 2, "GitLab attention primary loses its exact provider account or captured URL.");
        checks.Add(new { name = "attention.primary.capturedCurrentBrowser", nonFirstAccount = true, currentBrowserAndProfile = true,
            githubAndGitlabRoutes = true, exactCapturedUrl = true, fakeLaunchesOnly = true });
    }

    private static async Task OpenAdmissionAsync(Fixture fixture, List<object> checks)
    {
        fixture.Reset(); fixture.ClearCalls();
        var item = Item("stale-open", new("open", Url: "https://example.test/review/41", Service: "github", AccountID: "second.github"));
        var variants = new[] {
            fixture.Baseline with { Accounts = fixture.Baseline.AccountList.Select(account => account.Id == "second.github" ? account with { Enabled = false } : account).ToArray() },
            RemoteCardCatalog.RemoveAccount(fixture.Baseline, "second.github"),
            fixture.Baseline with { Accounts = fixture.Baseline.AccountList.Select(account => account.Id == "second.github" ? account with { Provider = "gitlab" } : account).ToArray() }
        };
        foreach (var settings in variants) {
            fixture.Set(settings);
            Require(!await fixture.ChooseAsync(item), "Disabled/removed/provider-changed captured account remains admitted.");
        }
        fixture.Reset();
        Require(!await fixture.ChooseAsync(item with { Action = item.Action with { Service = "gitlab" } })
            && !await fixture.ChooseAsync(item with { Action = item.Action with { AccountID = "missing" } })
            && !await fixture.ChooseAsync(item with { Action = item.Action with { Url = null } })
            && fixture.Browsers.Count == 0, "Wrong provider, missing account or URL launches an unrelated browser.");
        checks.Add(new { name = "attention.primary.openAdmission", disabledRemovedAndChangedProvider = true,
            wrongProviderAndMissingAccountOrUrlRefused = true, noFallbackToFirstAccount = true });
    }

    private static async Task AccountSettingsAsync(Fixture fixture, List<object> checks)
    {
        fixture.Reset(); fixture.ClearCalls();
        var item = Item("edit-disabled", new("accountSettings", Service: "github", AccountID: "second.github"));
        fixture.Set(fixture.Baseline with { Accounts = fixture.Baseline.AccountList.Select(account => account.Id == "second.github"
            ? account with { Enabled = false } : account).ToArray() });
        Require(await fixture.ChooseAsync(item) && fixture.Pages.SequenceEqual(new[] { "account:second.github" }),
            "Disabled account cannot be edited, or attention settings opens the wrong account.");
        Require(!await fixture.ChooseAsync(item with { Action = item.Action with { Service = "gitlab" } }),
            "Account settings admits a wrong provider with the same captured ID.");
        fixture.Set(RemoteCardCatalog.RemoveAccount(fixture.Baseline, "second.github"));
        Require(!await fixture.ChooseAsync(item) && fixture.Pages.Count == 1,
            "Removed account attention creates settings or redirects to another account.");
        checks.Add(new { name = "attention.primary.accountSettings", exactAccountPage = true, disabledAccountRemainsEditable = true,
            wrongProviderAndRemovedAccountRefused = true, noActualSettingsWindow = true });
    }

    private static async Task DockerAsync(Fixture fixture, List<object> checks)
    {
        fixture.Reset(); fixture.ClearCalls();
        var item = Item("docker", new("startDocker"));
        Require(await fixture.ChooseAsync(item) && fixture.DockerCalls == 1 && !await fixture.ChooseAsync(item with { Enabled = false })
            && fixture.DockerCalls == 1, "Docker primary does not route once through the fake launcher or admits a disabled signal.");
        checks.Add(new { name = "attention.primary.docker", actualDispatcherRoutesOnce = true, disabledSignalRefused = true, fakeLauncherOnly = true });
    }

    private static async Task LegacyTerminalAsync(Fixture fixture, List<object> checks)
    {
        fixture.Reset(); fixture.ClearCalls();
        var project = fixture.Baseline.Cards.Single(card => card.Project.Id == "enabled.legacy");
        var item = Item("legacy-terminal", new("openTerminal", Path: project.Project.Path));
        Require(await fixture.ChooseAsync(item) && fixture.LegacyTerminals.SequenceEqual(new[] { project.Project }),
            "Legacy path primary chooses an earlier hidden card or loses exact configured project/distribution/path.");
        fixture.Set(fixture.Baseline with { Cards = fixture.Baseline.Cards.Select(card => card.Project.Id == project.Project.Id ? card with { Enabled = false } : card).ToArray() });
        Require(!await fixture.ChooseAsync(item), "Disabled legacy project remains a terminal target.");
        fixture.Set(fixture.Baseline with { Cards = fixture.Baseline.Cards.Where(card => card.Project.Id != project.Project.Id).ToArray() });
        Require(!await fixture.ChooseAsync(item), "Removed legacy project falls back to an earlier hidden card.");
        fixture.Reset();
        Require(!await fixture.ChooseAsync(item with { Action = item.Action with { Path = "/owned/unconfigured" } })
            && fixture.LegacyTerminals.Count == 1 && fixture.CheckoutTerminals.Count == 0,
            "Unconfigured legacy folder starts a terminal or crosses into typed checkout routing.");
        checks.Add(new { name = "attention.primary.legacyTerminal", exactConfiguredProjectDistributionPath = true,
            earlierHiddenSamePathSkipped = true, disabledRemovedAndUnknownFolderRefused = true, fakeTerminalOnly = true });
    }

    private static async Task CheckoutTerminalAsync(Fixture fixture, List<object> checks)
    {
        fixture.Reset(); fixture.ClearCalls();
        var project = fixture.Baseline.Cards.Single(card => card.Project.Id == "hidden.checkout");
        var target = new CheckoutTarget(project.Project.Distribution, project.Project.Id, project.Project.Path);
        var item = Item("typed-terminal", new("openTerminal", Path: target.Path, Checkout: target));
        Require(!project.Enabled && await fixture.ChooseAsync(item) && fixture.CheckoutTerminals.SequenceEqual(new[] { target })
            && !fixture.Controller.Settings.Cards.Single(card => card.Project.Id == target.ProjectID).Enabled,
            "Typed checkout attention refuses the hidden configured source, loses exact tuple, or reveals its card.");
        fixture.Set(fixture.Baseline with { Cards = fixture.Baseline.Cards.Select(card => card.Project.Id == target.ProjectID ? card with { Title = "Renamed current source" } : card).ToArray() });
        Require(await fixture.ChooseAsync(item) && fixture.CheckoutTerminals.Count == 2,
            "Renaming a project invalidates an unchanged physical checkout target.");
        var variants = new[] {
            fixture.Baseline with { WorkInFlight = new(false) },
            fixture.Baseline with { WorkInFlight = null },
            fixture.Baseline with { Cards = fixture.Baseline.Cards.Where(card => card.Project.Id != target.ProjectID).ToArray() },
            fixture.Baseline with { Cards = fixture.Baseline.Cards.Select(card => card.Project.Id == target.ProjectID ? card with { Project = card.Project with { Path = "/owned/changed-checkout" } } : card).ToArray() },
            fixture.Baseline with { Cards = fixture.Baseline.Cards.Select(card => card.Project.Id == target.ProjectID ? card with { Project = card.Project with { Distribution = "Test Two" } } : card).ToArray() }
        };
        foreach (var settings in variants) {
            fixture.Set(settings);
            Require(!await fixture.ChooseAsync(item), "Disabled/removed WIF or removed/path/distribution-changed checkout is admitted.");
        }
        fixture.Reset();
        foreach (var wrong in new[] { target with { Distribution = "Test Two" }, target with { ProjectID = "removed.checkout" }, target with { Path = "/owned/other" } })
            Require(!await fixture.ChooseAsync(item with { Action = item.Action with { Checkout = wrong } }), "Foreign typed checkout tuple is admitted.");
        Require(fixture.CheckoutTerminals.Count == 2 && fixture.LegacyTerminals.Count == 0,
            "Rejected typed terminal falls back to the legacy path route or launches another checkout.");
        checks.Add(new { name = "attention.primary.checkoutTerminal", hiddenSourceExactTuple = true, cardStaysHidden = true,
            titleRenamePreservesPhysicalIdentity = true, currentWifRequired = true, removedAndChangedTupleRefused = true,
            noLegacyFallback = true, fakeTerminalOnly = true });
    }

    private static async Task ChoiceGuardsAsync(Fixture fixture, List<object> checks)
    {
        fixture.Reset(); fixture.ClearCalls();
        var none = Item("status-only", new("none"));
        var docker = Item("enabled-docker", new("startDocker"));
        var open = Item("enabled-open", new("open", Url: "https://example.test/review/41", Service: "github", AccountID: "second.github"));
        Require(!await fixture.ChooseAsync(none) && !await fixture.ChooseAsync(docker with { Enabled = false })
            && !await fixture.ChooseAsync(none, new("primary", true, docker.Action))
            && !await fixture.ChooseAsync(open, new("primary", true, open.Action with { AccountID = "first.github" }))
            && !await fixture.ChooseAsync(open, new("primary", true, open.Action with { Url = "https://foreign.example.test" }))
            && !await fixture.ChooseAsync(open, new("read", true, InboxRead: new("github.inbox", "second.github", "0041", "https://api.example.test")))
            && !await fixture.ChooseAsync(docker, new("dismiss", true, docker.Action))
            && !await fixture.ChooseAsync(docker, new("unexpected", true)) && fixture.TotalCalls == 0,
            "Status-only/disabled signal or forged action choice performs a launch, credential read, alternate or unsupported action.");
        checks.Add(new { name = "attention.primary.choiceGuards", noneAndDisabledNeverExecute = true,
            forgedAccountUrlReadDismissAndKindRefused = true, noCredentialOrProviderAccess = true });
    }

    private static async Task ClosingGuardsAsync(Fixture fixture, List<object> checks)
    {
        fixture.Reset(); fixture.ClearCalls();
        var items = new[] {
            Item("closing-docker", new("startDocker")),
            Item("closing-settings", new("accountSettings", Service: "github", AccountID: "second.github")),
            Item("closing-open", new("open", Url: "https://example.test/review/41", Service: "github", AccountID: "second.github"))
        };
        foreach (var field in new[] { "closing", "shuttingDown" }) {
            SetField(fixture.Controller, field, true);
            try { foreach (var item in items) Require(!await fixture.ChooseAsync(item), "Closing/shutting down controller admits captured primary action."); }
            finally { SetField(fixture.Controller, field, false); }
        }
        Require(fixture.TotalCalls == 0, "Closing primary routing invokes a launcher or settings.");
        checks.Add(new { name = "attention.primary.closingGuards", closingAndShuttingDownNoOp = true,
            noActualApplicationShutdown = true, canonicalSettingsClockSignalsAndSeenPreserved = true });
    }

    private sealed class Fixture : IDisposable
    {
        private readonly string path = Path.Combine(Path.GetTempPath(), "devdeck-attention-primary-" + Guid.NewGuid().ToString("N") + ".json");
        private readonly byte[] persisted;
        private readonly DateTimeOffset? checkedAt;
        private readonly AttentionItem[] signals;
        private readonly Application application;
        private readonly int windows;
        internal DeckController Controller { get; }
        internal DeckSettings Baseline { get; }
        internal List<(string Browser, string? Profile, string Url)> Browsers { get; } = [];
        internal List<string> Pages { get; } = [];
        internal List<ProjectReference> LegacyTerminals { get; } = [];
        internal List<CheckoutTarget> CheckoutTerminals { get; } = [];
        internal int DockerCalls, CredentialReads, ProviderWrites;
        internal int TotalCalls => Browsers.Count + Pages.Count + LegacyTerminals.Count + CheckoutTerminals.Count + DockerCalls + CredentialReads + ProviderWrites;
        internal Fixture(Application application)
        {
            this.application = application; windows = application.Windows.Count;
            var accounts = new[] {
                new RemoteAccountSettings("first.github", "First Github", "github", "https://api.first.example.test", [], [], Browser: "edge", BrowserProfile: "Profile 1"),
                new RemoteAccountSettings("owned.gitlab", "Owned GitLab", "gitlab", "https://gitlab.example.test", [], [], Browser: "firefox"),
                new RemoteAccountSettings("second.github", "Second Github", "github", "https://api.example.test", [], [], Browser: "chrome", BrowserProfile: "Profile 2")
            };
            var cards = new[] {
                new CardSettings(new("hidden.legacy", "Test One", "local", "/owned/shared-legacy"), "Hidden earlier legacy", Enabled: false),
                new CardSettings(new("enabled.legacy", "Test Two", "ddev", "/owned/shared-legacy"), "Enabled legacy"),
                new CardSettings(new("hidden.checkout", "Test One", "local", "/owned/hidden-checkout"), "Hidden checkout", Enabled: false)
            };
            var store = new SettingsStore(path);
            store.Save(new(1, [new("Test One", "/tmp/devdeck-primary-fixture"), new("Test Two", "/tmp/devdeck-primary-fixture")], cards,
                Accounts: accounts, Language: "en", SeenAlerts: ["owned-previous-alert"], WorkInFlight: new(true)));
            Controller = new(application, store, live: false,
                dashboardOpener: (browser, profile, url) => Browsers.Add((browser, profile, url)),
                checkoutTerminalOpener: target => CheckoutTerminals.Add(target),
                checkoutEndpointFactory: _ => throw new IOException("Unexpected primary fixture checkout worker."));
            Controller.AttentionSettingsOpener = page => Pages.Add(page);
            Controller.AttentionDockerOpener = () => DockerCalls++;
            Controller.AttentionTerminalOpener = project => LegacyTerminals.Add(project);
            Controller.InboxTokenReader = _ => { CredentialReads++; throw new IOException("Unexpected primary fixture credential read."); };
            Controller.InboxWriteSender = (_, _, _, _) => { ProviderWrites++; throw new IOException("Unexpected primary fixture provider write."); };
            Controller.ObserveAttention(new("synthetic:primary-dispatch", [Item("retained-status", new("none"))], []));
            Baseline = Controller.Settings; persisted = File.ReadAllBytes(path); checkedAt = Controller.LastCheckedAt;
            signals = Tracker(Controller).SignalItems.ToArray();
            Require(checkedAt is not null && signals.Length == 1 && Baseline.AnnouncedAlerts.SequenceEqual(new[] { "owned-previous-alert" }),
                "Primary fixture did not seed meaningful clock/attention/seen state.");
        }
        internal void Set(DeckSettings value)
        {
            value = RemoteCardCatalog.Synchronize(value, key => Text.L(key)); value.Validate();
            typeof(DeckController).GetProperty("Settings", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(Controller, value);
        }
        internal void Reset() => Set(Baseline);
        internal void ClearCalls() { Browsers.Clear(); Pages.Clear(); LegacyTerminals.Clear(); CheckoutTerminals.Clear(); DockerCalls = CredentialReads = ProviderWrites = 0; }
        internal async Task<bool> ChooseAsync(AttentionItem item, AttentionChoice? choice = null)
        {
            var before = JsonSerializer.Serialize(Controller.Settings, WorkerProtocol.Json);
            var result = await Controller.ExecuteAttentionChoiceAsync(item, choice ?? AttentionChoices.Primary(item));
            Require(before == JsonSerializer.Serialize(Controller.Settings, WorkerProtocol.Json), "Primary routing rewrites current settings.");
            Guard(); return result;
        }
        private void Guard()
        {
            var workerCount = typeof(DeckController).GetFields(BindingFlags.Instance | BindingFlags.NonPublic)
                .Where(field => field.FieldType == typeof(WorkerManager)).Select(field => field.GetValue(Controller))
                .Sum(manager => ((IDictionary)typeof(WorkerManager).GetField("workers", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(manager)!).Count);
            Require(workerCount == 0 && !Controller.LocalPollEnabled && !Controller.SharedPollEnabled
                && File.ReadAllBytes(path).SequenceEqual(persisted) && Controller.LastCheckedAt == checkedAt
                && Tracker(Controller).SignalItems.SequenceEqual(signals)
                && Controller.Settings.AnnouncedAlerts.SequenceEqual(Baseline.AnnouncedAlerts)
                && CredentialReads == 0 && ProviderWrites == 0 && application.Windows.Count == windows,
                "Primary routing starts a worker/poll/window, accesses credentials/provider, or alters canonical bytes/clock/attention/seen history.");
        }
        public void Dispose()
        {
            try { Guard(); }
            finally {
                Controller.CloseViews();
                foreach (var file in new[] { path, path + ".bak" }) if (File.Exists(file)) File.Delete(file);
            }
        }
    }
    private static AttentionTracker Tracker(DeckController controller) => (AttentionTracker)typeof(DeckController).GetField("attention", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(controller)!;
    private static void SetField(DeckController controller, string name, bool value) => typeof(DeckController).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(controller, value);
    private static AttentionItem Item(string id, AttentionAction action) => new(id, id, "goodToKnow", "network", "Owned " + id, "Owned fake primary route", null, action, true, false);
    private static void Require(bool value, string message) { if (!value) throw new IOException(message); }
}
