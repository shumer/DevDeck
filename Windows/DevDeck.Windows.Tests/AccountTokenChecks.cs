using System.Text;
using System.Text.Json;
using DevDeck.Windows.Core;

// Four pure link/identity groups. No browser, vault, provider, worker or native process is used.
internal static class AccountTokenChecks
{
    internal static async Task RunAsync(Func<string, Func<Task>, Task> check)
    {
        await check("account token hosted GitHub classification is lexical narrow and provider-explicit", HostedMapping);
        await check("account token GitLab creation keeps current prefix and exact fixed prefill", GitLabPrefix);
        await check("account token explicit Enterprise destination leaves saved identity and raw arrays untouched", EnterpriseIdentity);
        await check("account token strict HTTPS lexical and UTF8 budgets fail closed without exposing inputs", AdmissionBounds);
    }

    private static Task HostedMapping()
    {
        const string expected = "https://github.com/settings/personal-access-tokens/new";
        foreach (var endpoint in new[] { "https://api.github.com", "https://api.github.com/", "HTTPS://API.GITHUB.COM/", "https://api.github.com:443/" }) {
            var result = AccountTokenActions.Creation("github", endpoint);
            Require(result.Address == expected && !result.NeedsEnterpriseAddress, "Hosted root/default-port input did not use the original fixed destination.");
        }
        foreach (var endpoint in new[] { "https://api.github.com:8443", "https://api.github.com/api/v3", "https://api.github.com.evil/",
            "https://api.github.com./", "https://api.gіthub.com/", "https://github.company.example/api/v3", "https://api.example.ghe.com/",
            "https://api.github.com/.", "https://api.github.com/path/..", "https://api.github.com/%2e", "https://api.github.com/%2e/",
            "https://api.github.com//", "https://api.github.com/%2F", "https://api.github.com:0443/" }) {
            var result = AccountTokenActions.Creation("github", endpoint);
            Require(result.Address is null && result.NeedsEnterpriseAddress, "A non-hosted or normalized nonroot endpoint silently guessed a token host.");
        }
        var gitlab = AccountTokenActions.Creation("gitlab", "https://api.github.com/");
        Require(gitlab.Address == "https://api.github.com/-/user_settings/personal_access_tokens?name=DevDeck&scopes=read_api"
            && !gitlab.NeedsEnterpriseAddress, "Provider was inferred from endpoint instead of the explicit field.");
        return Task.CompletedTask;
    }

    private static Task GitLabPrefix()
    {
        var cases = new[] {
            ("https://gitlab.example.com", "https://gitlab.example.com/-/user_settings/personal_access_tokens?name=DevDeck&scopes=read_api"),
            ("https://edited.example.com/", "https://edited.example.com/-/user_settings/personal_access_tokens?name=DevDeck&scopes=read_api"),
            ("https://gitlab.example.com/customer/GitLab/", "https://gitlab.example.com/customer/GitLab/-/user_settings/personal_access_tokens?name=DevDeck&scopes=read_api"),
            ("https://gitlab.example.com:8443/mount", "https://gitlab.example.com:8443/mount/-/user_settings/personal_access_tokens?name=DevDeck&scopes=read_api"),
            ("https://gitlab.example.com/customer%2Ftenant/", "https://gitlab.example.com/customer%2Ftenant/-/user_settings/personal_access_tokens?name=DevDeck&scopes=read_api"),
            ("https://gitlab.example.com/équipe/", "https://gitlab.example.com/%C3%A9quipe/-/user_settings/personal_access_tokens?name=DevDeck&scopes=read_api")
        };
        foreach (var (endpoint, expected) in cases) {
            var original = endpoint;
            var result = AccountTokenActions.Creation("gitlab", endpoint);
            Require(result.Address == expected && !result.NeedsEnterpriseAddress && endpoint == original,
                "Creation discarded/rewrote the current instance prefix or added a draft field to the query.");
            var uri = new Uri(result.Address!);
            Require(uri.Query == "?name=DevDeck&scopes=read_api" && uri.Fragment.Length == 0,
                "Derived query was not exactly the original two fixed prefill values.");
            var args = BrowserLaunch.Arguments("chrome", "Profile 2", result.Address!);
            Require(args.SequenceEqual(new[] { "--profile-directory=Profile 2", expected }), "Derived link is not admissible through existing browser/profile arguments.");
        }
        return Task.CompletedTask;
    }

    private static Task EnterpriseIdentity()
    {
        var account = new RemoteAccountSettings("owned", "", "gitlab", "https://gitlab.example.com/customer/", ["duplicate", "duplicate", " raw ", null!],
            ["owner/repo,other", null!], Enabled:false, Browser:"chrome", BrowserProfile:"Profile 2", NotifiesFailedRuns:true);
        var settings = DeckSettings.Empty with { Accounts = [account], SettingsWindow = new(940, 560), WorkInFlight = new(false, 321, 654, true) };
        var before = Json(settings); var target = account.CredentialTarget;
        var organizations = account.Organizations; var repositories = account.Repositories;
        var cases = new[] {
            ("https://server.example.com/settings/tokens", "https://server.example.com/settings/tokens"),
            ("https://cloud.example.ghe.com/settings/personal-access-tokens/new", "https://cloud.example.ghe.com/settings/personal-access-tokens/new"),
            ("HTTPS://SERVER.EXAMPLE.COM:8443/mounted/TokenPage/", "https://server.example.com:8443/mounted/TokenPage/"),
            ("https://server.example.com/%C3%A9quipe/token%2Fpage", "https://server.example.com/%C3%A9quipe/token%2Fpage")
        };
        foreach (var (entered, expected) in cases) {
            Require(AccountTokenActions.EnterpriseCreationAddress(entered) == expected, "Explicit Enterprise page was guessed, rebased or double-escaped.");
            _ = AccountTokenActions.Creation(account.Provider, account.Endpoint);
            Require(Json(settings) == before && account.CredentialTarget == target && account.Endpoint == "https://gitlab.example.com/customer/"
                && ReferenceEquals(account.Organizations, organizations) && ReferenceEquals(account.Repositories, repositories)
                && account.Organizations.SequenceEqual(new[] { "duplicate", "duplicate", " raw ", null! })
                && account.Repositories.SequenceEqual(new[] { "owner/repo,other", null! }),
                "Pure creation needed a valid label or changed credential identity/raw arrays/optional settings.");
        }
        Require(account.Label.Length == 0, "The fixture no longer proves creation works independently of full account validation.");
        return Task.CompletedTask;
    }

    private static Task AdmissionBounds()
    {
        var invalid = new string?[] { null, "", " ", "http://sentinel.example.com", "/token-page", "file:///tmp/token", "javascript:alert(1)",
            "https://user@sentinel.example.com", "https://user:secret@sentinel.example.com", "https://@sentinel.example.com", "https://sentinel.example.com?", "https://sentinel.example.com#",
            "https://sentinel.example.com?token=must-never-echo", "https://sentinel.example.com#fragment", " https://sentinel.example.com",
            "https://sentinel.example.com ", "https://sentinel.example.com/\npage", "https://sentinel.example.com/\u007Fpage", "https://sentinel.example.com/\u0085page",
            "https://sentinel.example.com/\uD800", "https://sentinel.example.com/\uDC00", "https://sentinel.example.com:0/", "https://sentinel.example.com:65536/",
            "https:\\sentinel.example.com\\page", "https://sentinel.example.com/%", "https://sentinel.example.com/%GG",
            "https://sentinel.example.com/%00", "https://sentinel.example.com/%0A", "https://sentinel.example.com/%C2%85" };
        foreach (var input in invalid) {
            Rejected(() => AccountTokenActions.EnterpriseCreationAddress(input!));
            foreach (var provider in new[] { "github", "gitlab" }) Rejected(() => AccountTokenActions.Creation(provider, input!));
        }
        foreach (var provider in new string?[] { null, "", "GitHub", "GITLAB", " github", "unknown" })
            Rejected(() => AccountTokenActions.Creation(provider!, "https://api.github.com"));

        const string prefix = "https://server.example.com/";
        var exact = prefix + new string('a', 2048 - prefix.Length);
        Require(Encoding.UTF8.GetByteCount(exact) == 2048 && AccountTokenActions.EnterpriseCreationAddress(exact) == exact,
            "An exact2048-byte complete page was rejected or rewritten.");
        Rejected(() => AccountTokenActions.EnterpriseCreationAddress(exact + "a"));
        Rejected(() => AccountTokenActions.Creation("github", exact + "a"));
        const string glPrefix = "https://gitlab.example.com/";
        const string suffix = "/-/user_settings/personal_access_tokens?name=DevDeck&scopes=read_api";
        var finalExactBase = glPrefix + new string('b', 2048 - glPrefix.Length - suffix.Length);
        var independentlyExpected = finalExactBase + suffix;
        Require(Encoding.UTF8.GetByteCount(independentlyExpected) == 2048
            && AccountTokenActions.Creation("gitlab", finalExactBase).Address == independentlyExpected,
            "A final derived2048-byte GitLab link was rejected or lost its prefix.");
        Rejected(() => AccountTokenActions.Creation("gitlab", finalExactBase + "b"));
        var expanded = glPrefix + string.Concat(Enumerable.Repeat("中", 230));
        Require(Encoding.UTF8.GetByteCount(expanded) < 2048, "The Unicode fixture must have a bounded raw input.");
        Rejected(() => AccountTokenActions.Creation("gitlab", expanded));
        Require(AccountTokenActions.EnterpriseCreationAddress("https://server.example.com/token%3Fpart%23part%2Fnext")
            == "https://server.example.com/token%3Fpart%23part%2Fnext", "Escaped reserved path data was mistaken for an input query/fragment.");
        return Task.CompletedTask;
    }

    private static string Json<T>(T value) => JsonSerializer.Serialize(value, WorkerProtocol.Json);
    private static void Rejected(Action action)
    {
        try { action(); }
        catch (InvalidDataException error) {
            Require(error.Message == "Choose a valid bounded HTTPS token page or provider endpoint."
                && !error.Message.Contains("sentinel", StringComparison.Ordinal) && !error.Message.Contains("secret", StringComparison.Ordinal),
                "Rejected URL leaked input or failed at a nongeneric boundary.");
            return;
        }
        throw new Exception("Unsafe or oversized token page was accepted.");
    }
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
}
