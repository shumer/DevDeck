using System.Text.Json;
using DevDeck.Windows.Core;

// Pure request ownership and actual owned-store transactions; no vault/provider/native calls.
internal static class AccountProviderChecks
{
    internal static async Task RunAsync(Func<string, Func<Task>, Task> check)
    {
        await check("account provider exact applicability and GitHub credential copies preserve current identity and raw scopes", GitHubOwnership);
        await check("account provider invalid active GitHub legacy scopes stay exact fail-closed request inputs", GitHubLegacyScopes);
        await check("account provider GitLab request projection leaves legacy arrays flags and unrelated owned settings exact", GitLabStoredPreservation);
        await check("account provider malformed credentials and rejected owned writes preserve current files and backup", StrictAdmission);
    }

    private static Task GitHubOwnership()
    {
        foreach (var provider in new[] { "github", "gitlab", "GitHub", "GITHUB", "unknown", "", " github" }) {
            var expected = provider == "github";
            Require(RemoteAccountApplicability.HasGitHubScopes(provider) == expected
                && RemoteAccountApplicability.HasFailedRunPreference(provider) == expected,
                "Provider applicability was inferred from an unsupported/case-wrong provider.");
        }
        var account = Account("github") with {
            Endpoint = "https://gitlab.example.com/api/v3", Organizations = ["second", "first"], Repositories = ["second/web", "first/api"]
        };
        var before = Json(account); var target = account.CredentialTarget;
        const string token = "owned-memory-token-never-persisted";
        var credential = RemoteAccountApplicability.Credential(account, token);
        Require(credential.Id == account.Id && credential.Label == account.Label && credential.Endpoint == account.Endpoint
            && credential.Token == token && credential.Organizations.SequenceEqual(account.Organizations)
            && credential.Repositories.SequenceEqual(account.Repositories), "GitHub request lost its exact account identity/token/order.");
        Require(!ReferenceEquals(credential.Organizations, account.Organizations) && !ReferenceEquals(credential.Repositories, account.Repositories)
            && Json(account) == before && account.CredentialTarget == target
            && credential.ToString() == "Remote account credential (redacted)" && !credential.ToString().Contains(token, StringComparison.Ordinal),
            "Credential reused saved arrays, mutated the account or exposed its token representation.");
        credential.Organizations[0] = "returned-change"; credential.Repositories[0] = "returned/change";
        Require(account.Organizations[0] == "second" && account.Repositories[0] == "second/web", "Returned arrays mutate saved GitHub scopes.");
        account.Organizations[1] = "stored-change"; account.Repositories[1] = "stored/change";
        Require(credential.Organizations[1] == "first" && credential.Repositories[1] == "first/api", "Stored arrays mutate an already captured request.");
        var empty = RemoteAccountApplicability.Credential(account with { Organizations = [], Repositories = [] }, null);
        Require(empty.Token is null && empty.CacheScope is null && empty.Organizations.Length == 0 && empty.Repositories.Length == 0
            && empty.Id == account.Id && empty.Endpoint == account.Endpoint, "Null token or empty active scope was replaced by an invented fallback.");
        return Task.CompletedTask;
    }

    private static Task GitHubLegacyScopes()
    {
        using var fixture = new Fixture();
        var account = Account("github") with { Organizations = LegacyOrganizations(), Repositories = LegacyRepositories() };
        var original = RichSettings(account);
        fixture.Store.Save(original with { Accounts = original.AccountList.Select(item => item.Id == account.Id ? item with { Label = "Previous" } : item).ToArray() });
        fixture.Store.Save(original);
        var currentBytes = File.ReadAllBytes(fixture.Path); var backupBytes = File.ReadAllBytes(fixture.BackupPath);
        var loaded = fixture.Store.Load(); var saved = loaded.AccountList.Single(item => item.Id == account.Id); var before = Json(loaded);
        saved.Validate();
        var credential = RemoteAccountApplicability.Credential(saved, "owned-gh-fixture");
        Require(saved.Organizations.Length > 64 && saved.Organizations.Any(value => value is null)
            && credential.Organizations.SequenceEqual(account.Organizations) && credential.Repositories.SequenceEqual(account.Repositories)
            && credential.Organizations.Length == account.Organizations.Length
            && !ReferenceEquals(credential.Organizations, saved.Organizations) && !ReferenceEquals(credential.Repositories, saved.Repositories),
            "Settings-valid active legacy scopes were repaired, truncated, normalized or aliased.");
        Require(credential.Organizations.Count(value => value == "duplicate") == 2 && credential.Organizations.Contains(" spaced ")
            && credential.Repositories.Contains("owner/repo,other") && credential.Repositories.Any(value => value is null),
            "Raw duplicate/space/comma/null GitHub inputs were silently changed.");
        Require(Json(loaded) == before && Json(loaded) == Json(original)
            && Same(File.ReadAllBytes(fixture.Path), currentBytes) && Same(File.ReadAllBytes(fixture.BackupPath), backupBytes),
            "Pure credential projection changed stored GitHub settings or the preceding backup.");
        fixture.RequireNoTemporary();
        return Task.CompletedTask;
    }

    private static Task GitLabStoredPreservation()
    {
        using var fixture = new Fixture();
        var account = Account("gitlab") with { Organizations = LegacyOrganizations(), Repositories = LegacyRepositories(),
            NotifiesFailedRuns = true, Browser = "chrome", BrowserProfile = "Profile 2" };
        var original = RichSettings(account);
        fixture.Store.Save(original with { Accounts = original.AccountList.Select(item => item.Id == account.Id ? item with { Label = "Previous" } : item).ToArray() });
        fixture.Store.Save(original);
        var currentBytes = File.ReadAllBytes(fixture.Path); var backupBytes = File.ReadAllBytes(fixture.BackupPath);
        var loaded = fixture.Store.Load(); var saved = loaded.AccountList.Single(item => item.Id == account.Id); var before = Json(loaded);
        Require(Json(loaded) == Json(original) && saved.NotifiesFailedRuns && saved.Organizations.Length > 64
            && saved.Repositories.Any(value => value is null), "The owned store changed valid inactive legacy GitLab data on load.");
        const string token = "owned-gl-fixture-never-in-settings";
        foreach (var value in new string?[] { null, token }) {
            var credential = RemoteAccountApplicability.Credential(saved, value);
            Require(credential.Id == saved.Id && credential.Label == saved.Label && credential.Endpoint == saved.Endpoint && credential.Token == value
                && credential.Organizations.Length == 0 && credential.Repositories.Length == 0,
                "GitLab projection retained unused worker filters or lost the admitted account/token identity.");
        }
        Require(Json(loaded) == before && Same(File.ReadAllBytes(fixture.Path), currentBytes)
            && Same(File.ReadAllBytes(fixture.BackupPath), backupBytes), "A pure GitLab projection changed saved data or backup.");
        var edited = saved with { Label = "Renamed GitLab", Browser = "edge", BrowserProfile = "Default" };
        var proposed = loaded with { Accounts = loaded.AccountList.Select(item => item.Id == saved.Id ? edited : item).ToArray() };
        fixture.Store.Save(proposed);
        var after = fixture.Store.Load(); var updated = after.AccountList.Single(item => item.Id == saved.Id);
        Require(updated.Label == edited.Label && updated.Browser == edited.Browser && updated.BrowserProfile == edited.BrowserProfile
            && Json(updated with { Label = saved.Label, Browser = saved.Browser, BrowserProfile = saved.BrowserProfile }) == Json(saved)
            && updated.Organizations.SequenceEqual(account.Organizations) && updated.Repositories.SequenceEqual(account.Repositories)
            && updated.NotifiesFailedRuns && updated.CredentialTarget == saved.CredentialTarget,
            "Authorized GitLab metadata save changed inactive arrays/flag or credential identity.");
        Require(Json(after with { Accounts = loaded.Accounts }) == before && Json(after) == Json(proposed)
            && Same(File.ReadAllBytes(fixture.BackupPath), currentBytes),
            "GitLab metadata save changed unrelated settings or failed to preserve the exact preceding configuration.");
        var backup = JsonSerializer.Deserialize<DeckSettings>(File.ReadAllBytes(fixture.BackupPath), WorkerProtocol.Json)!;
        backup.Validate();
        Require(Json(backup) == before && !File.ReadAllText(fixture.Path).Contains(token, StringComparison.Ordinal), "Backup was invalid or a token leaked into persisted settings.");
        using var persisted = JsonDocument.Parse(File.ReadAllBytes(fixture.Path));
        Require(persisted.RootElement.GetProperty("accounts").EnumerateArray().All(item => !item.TryGetProperty("token", out _)),
            "Persisted account schema acquired a token field.");
        fixture.RequireNoTemporary();
        return Task.CompletedTask;
    }

    private static Task StrictAdmission()
    {
        Require(Capture(() => RemoteAccountApplicability.Credential(null!, "owned")) is ArgumentNullException,
            "Null account was accepted or failed with the wrong boundary.");
        using var fixture = new Fixture();
        var valid = Account("gitlab"); var original = RichSettings(valid);
        fixture.Store.Save(original with { Locked = false }); fixture.Store.Save(original);
        var currentBytes = File.ReadAllBytes(fixture.Path); var backupBytes = File.ReadAllBytes(fixture.BackupPath);
        var replacements = 0;
        var guarded = new SettingsStore(fixture.Path, new AtomicSettingsCommit((_, _, _) => {
            replacements++; throw new Exception("Invalid settings reached replacement.");
        }, _ => throw new Exception("Invalid settings reached retry."), () => TimeSpan.Zero));
        var invalid = new List<RemoteAccountSettings>();
        foreach (var provider in new[] { "github", "gitlab" }) {
            invalid.Add(valid with { Provider = provider, Organizations = null! });
            invalid.Add(valid with { Provider = provider, Repositories = null! });
            invalid.Add(valid with { Provider = provider, Organizations = null!, Repositories = null! });
        }
        invalid.AddRange(new[] { "unknown", "GitHub", "GITLAB" }.Select(provider => valid with { Provider = provider }));
        invalid.AddRange(new[] { "http://gitlab.example.com", "https://user@gitlab.example.com", "https://gitlab.example.com?scope=x",
            "https://gitlab.example.com#fragment", "not-an-endpoint" }.Select(endpoint => valid with { Endpoint = endpoint }));
        invalid.Add(valid with { Label = "invalid\nlabel" });
        invalid.Add(valid with { Browser = "unsupported" });
        foreach (var account in invalid) {
            Require(Capture(() => RemoteAccountApplicability.Credential(account, "owned")) is InvalidDataException,
                "Malformed credential was coerced instead of rejected by existing account validation.");
            var proposed = original with { Accounts = original.AccountList.Select(item => item.Id == valid.Id ? account : item).ToArray() };
            Require(Capture(() => guarded.Save(proposed)) is InvalidDataException && replacements == 0
                && Same(File.ReadAllBytes(fixture.Path), currentBytes) && Same(File.ReadAllBytes(fixture.BackupPath), backupBytes),
                "Rejected account save reached replacement or changed the owned current/backup bytes.");
            fixture.RequireNoTemporary();
        }
        var legacyElement = valid with { Organizations = [null!], Repositories = [null!] };
        legacyElement.Validate();
        var allowed = RemoteAccountApplicability.Credential(legacyElement, null);
        Require(allowed.Organizations.Length == 0 && allowed.Repositories.Length == 0
            && legacyElement.Organizations[0] is null && legacyElement.Repositories[0] is null,
            "Valid inactive null elements became a whole-array rejection or were changed at rest.");
        Require(Json(fixture.Store.Load()) == Json(original), "Rejected credentials changed the last accepted model.");
        return Task.CompletedTask;
    }

    private static RemoteAccountSettings Account(string provider) => new("owned", "Owned account", provider,
        provider == "github" ? "https://api.github.example.com" : "https://gitlab.example.com", ["example"], ["example/web"]);
    private static string[] LegacyOrganizations() => Enumerable.Range(0, 65).Select(index => "legacy" + index)
        .Concat(new[] { "duplicate", "duplicate", " spaced ", "with,comma", null! }).ToArray();
    private static string[] LegacyRepositories() => ["owner/repo", "owner/repo", "owner/repo,other", null!];
    private static DeckSettings RichSettings(RemoteAccountSettings account) => new(1,
        [new("Owned Linux", "/missing/worker", "en")],
        [new(new("local.ddev", "Owned Linux", "ddev", "/missing/ddev"), "DDEV2", X:321.125, Y:123.75, Collapsed:true, HiddenTools:["xhgui"]),
         new(new("local.plain", "Owned Linux", "local", "/missing/plain"), "Local10", Enabled:false, X:-12.25, Y:77.5, NotifiesWhenDown:false)],
        Floating:true, Locked:true,
        Accounts:[account, new("sibling", "Unrelated GitHub", "github", "https://api.github.com", ["sibling"], ["sibling/web"],
            Browser:"firefox", BrowserProfile:"Legacy profile", NotifiesBlocked:true)],
        RemoteCards:[new("legacy.owned", "Owned card", account.Provider == "gitlab" ? "mergeRequests" : "pullRequests", "Owned Linux", [account.Id],
            X:700.25, Y:92.5, Collapsed:true), new("legacy.sibling", "Unrelated Inbox", "inbox", "Owned Linux", ["sibling"], Enabled:false, X:900, Y:200)],
        Language:"ru", Arrangements:[new("Original", [new("local.ddev",321.125,123.75,true,true), new("legacy.owned",700.25,92.5,true,true)])],
        Notifications:true, SeenAlerts:["original:seen"], NotifiesUpdates:false, LogWindows:[new("local.ddev",10,20,800,500)],
        RefreshSeconds:300, WorkInFlight:new(false,600,400,true), SettingsWindow:new(940,560));
    private static string Json<T>(T value) => JsonSerializer.Serialize(value, WorkerProtocol.Json);
    private static Exception Capture(Action action) { try { action(); } catch (Exception error) { return error; } throw new Exception("Expected rejected account/configuration."); }
    private static bool Same(byte[] left, byte[] right) => left.AsSpan().SequenceEqual(right);
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }

    private sealed class Fixture : IDisposable
    {
        private readonly string directory = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "devdeck-account-provider-" + Guid.NewGuid().ToString("N"));
        internal string Path { get; }
        internal string BackupPath => Path + ".bak";
        internal SettingsStore Store { get; }
        internal Fixture()
        {
            Directory.CreateDirectory(directory);
            Path = System.IO.Path.Combine(directory, "settings.json");
            Store = new SettingsStore(Path);
        }
        internal void RequireNoTemporary() => Require(!Directory.EnumerateFiles(directory, "*.tmp").Any(), "Owned account transaction leaked a temporary file.");
        public void Dispose()
        {
            foreach (var file in Directory.EnumerateFiles(directory)) File.Delete(file);
            Directory.Delete(directory);
        }
    }
}
