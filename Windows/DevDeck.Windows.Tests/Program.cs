using System.Diagnostics;
using System.Text;
using System.Text.Json;
using DevDeck.Windows.Core;

if (args.Contains("--fake-poweroff-worker")) return await PowerOffChecks.RunFakeAsync(args);
if (args.Contains("--fake-checkout-worker")) return await CheckoutChecks.RunFakeAsync(args);
if (args.Contains("--fake-attention-choice-worker")) return await AttentionChoiceChecks.RunFakeAsync(args);

if (args.Contains("--live-terminal"))
{
    var index = Array.IndexOf(args, "--live-terminal");
    return await TerminalChecks.RunAsync(args[index + 1], args[index + 2]);
}
if (args.Contains("--live-remote"))
{
    // Explicit read-only qualification of already configured accounts. Credentials stay in memory
    // and the inherited worker pipe; the report has only aggregate metadata, never titles or tokens.
    var index = Array.IndexOf(args,"--live-remote");
    var settings = new SettingsStore(args[index + 1]).Load(); var results = new List<object>();
    var vault = new WindowsTokenStore();
    await using var pool = new WorkerManager();
    var worker = await pool.GetAsync(settings.Workers.First());
    foreach (var kind in new[] { "pullRequests","inbox","actions","mergeRequests" }) {
        var provider = kind == "mergeRequests" ? "gitlab" : "github";
        var accounts = settings.AccountList.Where(account => account.Enabled && account.Provider == provider).ToArray();
        if (accounts.Length == 0) { results.Add(new { kind, configured = false }); continue; }
        try {
            var credentials = accounts.Select(account => RemoteAccountApplicability.Credential(account,vault.Read(account))).ToArray();
            var response = await worker.CallAsync("remote.snapshot",timeout:TimeSpan.FromMinutes(3),remote:new("owned.read-only."+kind,kind,credentials));
            var snapshot = response.Remote ?? throw new WorkerException("remoteMissing","Remote snapshot missing.");
            results.Add(new { kind, configured = true, success = true, accounts = accounts.Length, total = snapshot.Total, rows = snapshot.Rows.Length,
                blocked = snapshot.Blocked, review = snapshot.ReviewCount, personal = snapshot.ActionableCount, repositories = snapshot.RepositoryCount,
                namespaces = snapshot.NamespaceCount, successRate = snapshot.SuccessRate, running = snapshot.RunningCount, capped = snapshot.Capped,
                statusCodes = snapshot.Rows.Select(row => row.StatusCode).Where(code => code is not null).Distinct().ToArray(),
                failures = snapshot.Failures.Select(failure => failure.Kind).ToArray(), pollIntervalSeconds = snapshot.PollIntervalSeconds });
        } catch (WorkerException error) { results.Add(new { kind, configured = true, success = false, code = error.Code, failures = error.Remote?.Failures.Select(failure => failure.Kind).ToArray() }); }
    }
    await File.WriteAllTextAsync(args[index + 2],JsonSerializer.Serialize(new { readOnly = true, notificationsMutated = false, credentialsWritten = false, configurationChanged = false, results, releaseQualified = false },new JsonSerializerOptions { WriteIndented = true }));
    Console.WriteLine("Read-only remote qualification report saved; no notification or configuration changed.");
    return 0;
}

if (args.Contains("--fake-worker"))
{
    var mode = args.Last();
    var distributionIndex = Array.IndexOf(args, "--fake-distribution");
    var fakeDistribution = distributionIndex >= 0 ? args[distributionIndex + 1] : "Test Linux";
    while (Console.ReadLine() is { } line)
    {
        var request = JsonSerializer.Deserialize<WorkerRequest>(line, WorkerProtocol.Json)!;
        if (mode == "stall") { await Task.Delay(TimeSpan.FromMinutes(1)); continue; }
        if (mode == "remote-stall" && request.Operation == "remote.snapshot") { await Task.Delay(TimeSpan.FromMinutes(1)); continue; }
        if (mode == "malformed") { Console.WriteLine("{broken"); continue; }
        var response = new WorkerResponse(mode == "version" ? 99 : 1, mode == "id" ? "wrong" : request.Id,
            mode == "distribution" ? "wrong" : fakeDistribution, mode == "visibility-copy" ? ["hello","attention.activeProjects"] : ["hello"], null, null,
            request.Operation == "unsupported" ? new WorkerFailure("unsupportedOperation", "Unavailable.") : null);
        if (mode == "progress") Console.WriteLine(JsonSerializer.Serialize(response with { Event = new WorkerEvent("progress", "owned progress"), Capabilities = null }, WorkerProtocol.Json));
        if (request.Operation == "project.status" && mode.StartsWith("project-versions",StringComparison.Ordinal)) response = response with {
            Status = new(request.Project!.Id,"stopped",null,null,"drupal 11",null,VersionsLine: mode switch {
                "project-versions-control" => "php 8.4\nmysql 8.0", "project-versions-long" => new string('x',513),
                "project-versions-utf8" => new string('Ж',257), _ => "php 8.4 · mysql 8.0" }) };
        if (request.Operation == "project.status" && mode == "project-cycle") response = response with {
            Status = new(request.Project!.Id,"unknown",null,null,null,null,VersionsLine:request.RefreshCycle) };
        if(request.Operation=="project.status" && mode=="visibility-copy")response=response with{
            Status=new(request.Project!.Id,"stopped",null,null,null,null,VersionsLine:string.Join("|",request.ActiveProjectIDs??[]))};
        if (request.Operation is "project.status" or "project.check" && mode.StartsWith("project-check",StringComparison.Ordinal)) response = response with {
            Status = new(request.Project!.Id,"running",null,"http://localhost:3000",null,null,
                CheckSummary: mode == "project-check-legacy" ? null : new(
                    mode == "project-check-tone" ? "unexpected" : "good",
                    mode switch { "project-check-state-control" => "invalid\nstate", "project-check-state-long" => new string('Ж',257), "project-check-state-null" => null!, _ => "Fixture is running" },
                    mode switch { "project-check-detail-control" => "invalid\0detail", "project-check-detail-long" => new string('Ж',8193), "project-check-detail-null" => null!, _ => "Source: fixture\nReady\r\n\tDetails" }),
                CheckedAt: mode switch { "project-check-legacy" => null, "project-check-time-negative" => -1, "project-check-time-overflow" => 253402300800, _ => 0 }) };
        if (request.Operation == "project.probe" && mode.StartsWith("project-probe",StringComparison.Ordinal)) response = response with {
            Suggestion = mode == "project-probe-empty" ? null : new("bun · next","bun run dev","",true,false,
                mode == "project-probe-unsafe" ? "file:///tmp/secret" : "http://localhost:3000") };
        if (request.Operation == "remote.snapshot") response = response with {
            Remote = new RemoteSnapshot(mode == "remote-id" ? "wrong-card" : request.Remote!.CardID, request.Remote!.Kind, 1, 0, null,
                [new("row", "a", "Synthetic request", "example/web", "https://example.com", "ready", "approved", false)], [], false,
                PollIntervalSeconds: mode == "remote-interval" ? 0 : null) };
        if (mode == "remote-shape" && response.Remote is { } remote) response = response with { Remote = remote with { SuccessRate = 1.5, Failures = [null!] } };
        if (response.Remote is { } fixture && mode.StartsWith("remote-invalid-",StringComparison.Ordinal)) response = response with { Remote = fixture with { Rows = [fixture.Rows[0] with {
            AccountID = mode == "remote-invalid-account" ? "other" : "a", Url = mode == "remote-invalid-url" ? "file:///C:/Windows/notepad.exe" : "https://example.com",
            StatusCode = mode == "remote-invalid-status" ? "ERROR" : "CF", UpdatedAt = mode == "remote-invalid-time" ? -1 : 1000 }],
            RepositoryCount = mode == "remote-invalid-count" ? -1 : 2, AverageDurationSeconds = mode == "remote-invalid-duration" ? -1 : 60 } };
        if (request.Operation == "project.logs" && mode != "logs-missing") response = response with { Logs = new(
            Enumerable.Range(0, mode == "logs-lines" ? 401 : 400).Select(index => index.ToString()).ToArray(), "Synthetic source", null,
            mode == "logs-path" ? "/home/user/../secret" : "/home/user/project/log.txt") };
        if (mode == "logs-bytes" && response.Logs is { } large) response = response with { Logs = large with { Lines = [new string('x', 262145)] } };
        if (mode.StartsWith("attention", StringComparison.Ordinal) && request.Operation == "remote.snapshot") {
            var action = new AttentionAction("accountSettings", Service: "github", AccountID: mode == "attention-account" ? "other" : "a");
            if (mode is "attention-url" or "attention-error-invalid") action = new("open", "file:///C:/Windows/notepad.exe", "github", "a");
            response = response with { Attention = new(mode == "attention-scope" ? "wrong" : request.Remote!.CardID,
                [new("account:github:a:rejected", "github:account:a", mode == "attention-tier" ? "unknown" : "needsFixing", "token", "Replace token", "Safe detail", 1000, action, true, false)], []) };
            if (mode.Contains("error", StringComparison.Ordinal)) response = response with { Error = new("credentialsRejected", "Safe failure."),
                Remote = response.Remote! with { Rows = [], Total = 0, Failures = [new("a", "rejected")] } };
        }
        var encodedResponse = JsonSerializer.Serialize(response, WorkerProtocol.Json);
        if (mode == "project-check-time-nonfinite") encodedResponse = encodedResponse.Replace("\"checkedAt\":0", "\"checkedAt\":1e309",StringComparison.Ordinal);
        Console.WriteLine(encodedResponse);
        if (mode == "exit") return 0;
    }
    return 0;
}

var passed = 0;
var failed = 0;
async Task Check(string name, Func<Task> test)
{
    try { await test(); passed++; Console.WriteLine("ok  " + name); }
    catch (Exception error) { failed++; Console.WriteLine("FAIL " + name + ": " + error.Message); }
}
static void Expect(bool value, string message = "Expectation failed") { if (!value) throw new Exception(message); }
static async Task Throws<T>(Func<Task> test, Func<T, bool>? predicate = null) where T : Exception
{
    try { await test(); } catch (T error) { if (predicate is not null) Expect(predicate(error)); return; }
    throw new Exception("Expected " + typeof(T).Name);
}

if (args.Contains("--atomic-settings-only") || args.Contains("--atomic-settings-red")) {
    await SettingsAtomicChecks.RunAsync(Check, transientOnly: args.Contains("--atomic-settings-red"));
    Console.WriteLine($"Windows checks: {passed} passed, {failed} failed.");
    return failed == 0 ? 0 : 1;
}

if (args.Contains("--tray-core-red") || args.Contains("--tray-core-only")) {
    if (args.Contains("--tray-core-red")) await AttentionChoiceChecks.RunRedAsync(Check);
    else await AttentionChoiceChecks.RunAsync(Check);
    Console.WriteLine($"Windows checks: {passed} passed, {failed} failed.");
    return failed == 0 ? 0 : 1;
}

if (args.Contains("--sidebar-core-red") || args.Contains("--sidebar-core-only")) {
    if (args.Contains("--sidebar-core-red")) await SettingsSidebarChecks.RunRedAsync(Check);
    else await SettingsSidebarChecks.RunAsync(Check);
    Console.WriteLine($"Windows checks: {passed} passed, {failed} failed.");
    return failed == 0 ? 0 : 1;
}

if (args.Contains("--settings-geometry-core-only")) {
    await SettingsGeometryChecks.RunAsync(Check);
    Console.WriteLine($"Windows checks: {passed} passed, {failed} failed.");
    return failed == 0 ? 0 : 1;
}

if (args.Contains("--account-provider-core-only")) {
    await AccountProviderChecks.RunAsync(Check);
    Console.WriteLine($"Windows checks: {passed} passed, {failed} failed.");
    return failed == 0 ? 0 : 1;
}

if (args.Contains("--account-token-core-only")) {
    await AccountTokenChecks.RunAsync(Check);
    Console.WriteLine($"Windows checks: {passed} passed, {failed} failed.");
    return failed == 0 ? 0 : 1;
}

await Check("shared attention equal-time titles use Mac natural numbers while priority dedupe and case ties remain stable", () => {
    var previous = System.Globalization.CultureInfo.CurrentCulture;
    try {
        foreach (var (culture,title) in new[] { ("en-US","Review"),("ru-RU","Проект"),("de-DE","Aufgabe"),("es-ES","Revisión"),("fr-FR","Révision"),("it-IT","Revisione") }) {
            System.Globalization.CultureInfo.CurrentCulture = System.Globalization.CultureInfo.GetCultureInfo(culture);
            AttentionItem Item(string id,string tier,string label,double? since=1000) => new(id,id,tier,"github",label,"Original account detail",since,new("none"),false,false);
            foreach (var tier in new[] { "waiting","needsFixing","stuck","goodToKnow" }) {
                var tracker = new AttentionTracker();
                var ten = Item("ten",tier,title + "10"); var arabicTwo = Item("arabic.two",tier,title + "٢"); var two = Item("two",tier,title + "2");
                tracker.Observe(new AttentionSnapshot("original",[ten,arabicTwo,two],[]));
                tracker.Observe(new AttentionSnapshot("duplicate",[two with { Id="duplicate",Title="! duplicate must not replace original",Since=1 }],[]));
                var ordered = tracker.SignalItems;
                Expect(ordered.Select(row => row.Id).SequenceEqual(new[] { "arabic.two","two","ten" }),culture + "/" + tier + " equal-time names do not use natural numbers/source-stable numeric ties.");
                Expect(ReferenceEquals(ordered[0],arabicTwo) && ReferenceEquals(ordered[1],two) && ReferenceEquals(ordered[2],ten),"Natural comparison replaced deduped source identity, account detail or action.");
            }
            var priority = new AttentionTracker();
            priority.Observe(new AttentionSnapshot("scope",[Item("waiting.new","waiting","! newer",2000),Item("stuck","stuck","! stuck",3000),Item("waiting.old","waiting","Z old",100),
                Item("fix.old","needsFixing","! old",100),Item("fix.new","needsFixing","Z new",2000)],[]));
            Expect(priority.SignalItems.Select(row => row.Id).SequenceEqual(new[] { "waiting.old","waiting.new","fix.new","fix.old","stuck" }),"Natural title order changed tier/oldest-waiting/newest-fixing priority.");
            var ties = new AttentionTracker(); var first = Item("tie.z","waiting","Same"); var second = Item("tie.a","waiting","SAME");
            ties.Observe(new AttentionSnapshot("scope",[first,second],[]));
            Expect(ties.SignalItems.Select(row => row.Id).SequenceEqual(new[] { "tie.z","tie.a" }),"Case-equivalent attention title ties no longer retain original source order.");
        }
    } finally { System.Globalization.CultureInfo.CurrentCulture = previous; }
    return Task.CompletedTask;
});
if (args.Contains("--natural-only")) {
    Console.WriteLine($"Windows checks: {passed} passed, {failed} failed.");
    return failed == 0 ? 0 : 1;
}

await VisibilityChecks.RunAsync(Check);
await ArrangementChecks.RunAsync(Check);
await PowerOffChecks.RunAsync(Check);
await CheckoutChecks.RunAsync(Check);
await AttentionChoiceChecks.RunAsync(Check);
await SettingsAtomicChecks.RunAsync(Check);
await SettingsSidebarChecks.RunAsync(Check);
await SettingsGeometryChecks.RunAsync(Check);
await AccountProviderChecks.RunAsync(Check);
await AccountTokenChecks.RunAsync(Check);

await Check("catalog project presentation uses Arc DDEV plain kind order and natural title numbers", () => {
    var cards = new[] {
        new CardSettings(new("plain.10","Test Linux","local","/tmp/plain10"),"site10"),
        new CardSettings(new("ddev.10","Test Linux","ddev","/tmp/ddev10"),"site10"),
        new CardSettings(new("arc.10","Test Linux","arc","/tmp/arc10"),"site10",Enabled:false),
        new CardSettings(new("plain.2","Test Linux","local","/tmp/plain2"),"site2"),
        new CardSettings(new("arc.2","Test Linux","arc","/tmp/arc2"),"site2"),
        new CardSettings(new("ddev.2","Test Linux","ddev","/tmp/ddev2"),"site2")
    };
    var ordered = CardOrdering.Projects(cards,System.Globalization.CultureInfo.GetCultureInfo("en-US"));
    Expect(ordered.Select(card => card.Project.Id).SequenceEqual(new[] { "arc.2","arc.10","ddev.2","ddev.10","plain.2","plain.10" }));
    Expect(ordered.Length == cards.Length && !ordered[1].Enabled,"Catalog order must retain hidden projects.");
    return Task.CompletedTask;
});
await Check("catalog case-equivalent project titles use permanent ID ties independent of insertion order", () => {
    var cards = new[] {
        new CardSettings(new("project.z","Test Linux","local","/tmp/z"),"Same title"),
        new CardSettings(new("project.b","Test Linux","local","/tmp/b"),"SAME TITLE"),
        new CardSettings(new("project.a","Test Linux","local","/tmp/a"),"same title")
    };
    var culture = System.Globalization.CultureInfo.GetCultureInfo("en-US");
    var expected = new[] { "project.a","project.b","project.z" };
    Expect(CardOrdering.Projects(cards,culture).Select(card => card.Project.Id).SequenceEqual(expected));
    Expect(CardOrdering.Projects(cards.Reverse(),culture).Select(card => card.Project.Id).SequenceEqual(expected));
    return Task.CompletedTask;
});
await Check("catalog natural titles follow explicit locale collation for Unicode and number sequences", () => {
    var titles = new[] { "örebro","älg","zebra","alfa10","åland","alfa2" };
    var cards = titles.Select((title,index) => new CardSettings(new("fixture."+index,"Test Linux","local","/tmp/fixture"+index),title)).ToArray();
    Expect(CardOrdering.Projects(cards,System.Globalization.CultureInfo.GetCultureInfo("sv-SE")).Select(card => card.Title)
        .SequenceEqual(new[] { "alfa2","alfa10","zebra","åland","älg","örebro" }));
    var cyrillic = new[] {
        new CardSettings(new("fixture.z","Test Linux","local","/tmp/z"),"Проект10"),
        new CardSettings(new("fixture.b","Test Linux","local","/tmp/b"),"Проект2"),
        new CardSettings(new("fixture.a","Test Linux","local","/tmp/a"),"Проект٢")
    };
    Expect(CardOrdering.Projects(cyrillic,System.Globalization.CultureInfo.GetCultureInfo("ru-RU")).Select(card => card.Project.Id)
        .SequenceEqual(new[] { "fixture.a","fixture.b","fixture.z" }));
    return Task.CompletedTask;
});
await Check("remote catalog keeps original builtin roles first and naturally sorts custom legacy titles", () => {
    var cards = new[] {
        new RemoteCardSettings("gitlab.mergeRequests","First alphabetically","mergeRequests","Test Linux",["gitlab"]),
        new RemoteCardSettings("github.actions","Builds","actions","Test Linux",["work"]),
        new RemoteCardSettings("github.pullRequests","Zulu","pullRequests","Test Linux",["work"]),
        new RemoteCardSettings("custom.beta10","Beta10","pullRequests","Test Linux",["work"]),
        new RemoteCardSettings("legacy.alpha10","Alpha10","pullRequests","Test Linux",["private"]),
        new RemoteCardSettings("github.inbox","Inbox","inbox","Test Linux",["work"]),
        new RemoteCardSettings("legacy.alpha2","Alpha2","pullRequests","Test Linux",["private"],Enabled:false),
        new RemoteCardSettings("custom.beta2","Beta2","actions","Test Linux",["work"])
    };
    var expected = new[] { "github.pullRequests","github.inbox","github.actions","gitlab.mergeRequests","legacy.alpha2","legacy.alpha10","custom.beta2","custom.beta10" };
    var ordered = CardOrdering.Remote(cards,System.Globalization.CultureInfo.GetCultureInfo("en-US"));
    Expect(ordered.Select(card => card.Id).SequenceEqual(expected));
    Expect(ordered[4].Kind == "pullRequests" && !ordered[4].Enabled && ordered[4].AccountIDs.SequenceEqual(new[] { "private" }),"Legacy remote identity and scope must survive presentation order.");
    return Task.CompletedTask;
});
await Check("custom remote case-equivalent title ties use permanent IDs and preserve input records", () => {
    var cards = new[] {
        new RemoteCardSettings("primary.pulls","Primary","pullRequests","Test Linux",["primary"]),
        new RemoteCardSettings("legacy.z","Work2","pullRequests","Test Linux",["z"]),
        new RemoteCardSettings("custom.a","WORK2","pullRequests","Other Linux",["a"],Enabled:false),
        new RemoteCardSettings("legacy.b","work2","pullRequests","Test Linux",["b"])
    };
    var ordered = CardOrdering.Remote(cards,System.Globalization.CultureInfo.GetCultureInfo("en-US"));
    Expect(ordered.Select(card => card.Id).SequenceEqual(new[] { "primary.pulls","custom.a","legacy.b","legacy.z" }));
    Expect(ordered.All(card => cards.Any(original => ReferenceEquals(original,card))),"Presentation ordering must not rewrite custom metadata.");
    return Task.CompletedTask;
});
await Check("legacy first-per-kind aliases own builtin slots even when canonical IDs appear later", () => {
    var cards = new[] {
        new RemoteCardSettings("legacy.merges","Zulu merges","mergeRequests","Test Linux",["lab"],Enabled:false),
        new RemoteCardSettings("legacy.pulls","Zulu pulls","pullRequests","Other Linux",["private"],Collapsed:true),
        new RemoteCardSettings("github.actions","Builds","actions","Test Linux",["work"]),
        new RemoteCardSettings("github.pullRequests","Alpha10","pullRequests","Test Linux",["work"]),
        new RemoteCardSettings("custom.alpha2","Alpha2","pullRequests","Test Linux",["work"]),
        new RemoteCardSettings("github.inbox","Inbox","inbox","Test Linux",["work"]),
        new RemoteCardSettings("gitlab.mergeRequests","Alpha2","mergeRequests","Test Linux",["lab"])
    };
    var settings = DeckSettings.Empty with { RemoteCards=cards };
    var selected = RemoteCardCatalog.All.Select(descriptor => RemoteCardCatalog.Resolve(settings,descriptor.Kind)!.Id).ToArray();
    var before = JsonSerializer.Serialize(settings,WorkerProtocol.Json);
    var ordered = CardOrdering.Remote(cards,System.Globalization.CultureInfo.GetCultureInfo("en-US"));
    Expect(ordered.Select(card => card.Id).SequenceEqual(new[] { "legacy.pulls","github.inbox","github.actions","legacy.merges","custom.alpha2","gitlab.mergeRequests","github.pullRequests" }));
    Expect(ordered.Take(4).Select(card => card.Id).SequenceEqual(selected),"Presentation changed the legacy card selected by the builtin menu role.");
    Expect(ordered[0].Distribution == "Other Linux" && ordered[0].AccountIDs.SequenceEqual(new[] { "private" }) && ordered[0].Collapsed && !ordered[3].Enabled);
    Expect(ReferenceEquals(cards,settings.RemoteCards) && JsonSerializer.Serialize(settings,WorkerProtocol.Json) == before,"Alias ordering rewrote saved roles or scopes.");
    return Task.CompletedTask;
});
await Check("full catalog IDs order remote before grouped projects without rewriting saved arrays or state", () => {
    var settings = DeckSettings.Empty with {
        Cards = [
            new(new("project.plain","Test Linux","local","/tmp/plain","custom command"),"Plain",X:881,Y:377,Collapsed:true,Browser:"firefox",BrowserProfile:"Old profile"),
            new(new("arc.project.fixture","Test Linux","arc","/tmp/arc"),"Arc",Enabled:false,X:91,Y:82,Links:[new("TEST","https://example.test/",false)])
        ],
        RemoteCards = [
            new("legacy.pulls","Work10","pullRequests","Other Linux",["private"],X:221,Y:190,Collapsed:true),
            new("github.pullRequests","Pulls","pullRequests","Test Linux",["work"],Enabled:false,X:48,Y:80)
        ]
    };
    var before = JsonSerializer.Serialize(settings,WorkerProtocol.Json);
    var originalLocals = settings.Cards; var originalRemote = settings.RemoteCards;
    var ids = CardOrdering.IDs(settings,System.Globalization.CultureInfo.GetCultureInfo("en-US"));
    Expect(ids.SequenceEqual(new[] { "legacy.pulls","github.pullRequests","arc.project.fixture","project.plain" }));
    Expect(ReferenceEquals(originalLocals,settings.Cards) && ReferenceEquals(originalRemote,settings.RemoteCards)
        && JsonSerializer.Serialize(settings,WorkerProtocol.Json) == before,"Catalog ordering rewrote persisted arrays or preferences.");
    Expect(settings.Cards[0].Project.StartCommand == "custom command" && settings.Cards[0].Collapsed && settings.Cards[0].BrowserProfile == "Old profile");
    return Task.CompletedTask;
});
await Check("empty and partial catalogs retain only their actual records without adding defaults", () => {
    Expect(CardOrdering.Projects([]).Length == 0 && CardOrdering.Remote([]).Length == 0 && CardOrdering.IDs(DeckSettings.Empty).Length == 0);
    var card = new RemoteCardSettings("github.actions","Builds","actions","Test Linux",["fixture"]);
    Expect(CardOrdering.Remote([card]).Single() == card);
    var local = new CardSettings(new("project.only","Test Linux","local","/tmp/only"),"Only",Enabled:false);
    Expect(CardOrdering.Projects([local]).Single() == local);
    return Task.CompletedTask;
});

await Check("Detect fills commands and modes while preserving chosen name caption health open URL and identity", () => {
    var project = new ProjectReference("project.stable","Test Linux","local","/tmp/project","old","stop",false,false,"http://localhost:8111/health","Chosen",Subtitle:"Custom",OpenURL:"http://localhost:4111/front");
    var next = ProjectDetection.Apply(project,new("bun · next + nest","bun run dev","",true,true,"http://localhost:3000"));
    Expect(next.Id == project.Id && next.Title == "Chosen" && next.Subtitle == "Custom" && next.HealthURL == project.HealthURL && next.OpenURL == project.OpenURL);
    Expect(next.StartCommand == "bun run dev" && next.StopCommand == "" && next.HoldsProcess == true && next.RequiresDocker == true);
    var empty = ProjectDetection.Apply(project with { Subtitle=null,HealthURL="" },new("vite","npm run dev","",true,false,"http://localhost:5173"));
    Expect(empty.Subtitle == "vite" && empty.HealthURL == "http://localhost:5173"); return Task.CompletedTask;
});
await Check("generic legacy optional fields round-trip and site templates use the opening URL", () => {
    var legacy = JsonSerializer.Deserialize<ProjectReference>("""{"id":"project.old","distribution":"Test Linux","kind":"local","path":"/tmp/project","healthURL":"http://localhost:3000/health"}""",WorkerProtocol.Json)!;
    Expect(legacy.Subtitle is null && legacy.OpenURL is null);
    Expect(ProjectLinks.Resolve(new("Admin","{site}/admin"),legacy,null)!.Url == "http://localhost:3000/health/admin");
    var distinct = legacy with { Subtitle="bun · next",OpenURL="http://localhost:4111/front" };
    Expect(ProjectLinks.Resolve(new("Admin","{site}/admin"),distinct,null)!.Url == "http://localhost:4111/front/admin");
    Expect(JsonSerializer.Deserialize<ProjectReference>(JsonSerializer.Serialize(distinct,WorkerProtocol.Json),WorkerProtocol.Json) == distinct);
    Expect(!ProjectDetection.ValidSubtitle("invalid\ncaption") && !ProjectDetection.ValidSubtitle(new string('Ж',257)) && !ProjectDetection.ValidOpenURL("https://user:password@example.com"));
    Expect(!ProjectDetection.ValidOpenURL("http://localhost:3000/invalid\npath") && !ProjectDetection.ValidOpenURL("http://localhost/" + new string('Ж',1024)));
    return Task.CompletedTask;
});
await Check("generic glyph mirrors frozen whole-word framework and runtime precedence", () => {
    foreach (var (command,caption,expected) in new[] { ("bun run dev","bun · next + nest","next"), ("docker compose up -d","next","docker"),
        ("npm run dev","nest","nest"), ("bunx vite","","bun"), ("npm run bundle","","node"), ("make dev","","make"), ("python makemigrations","","other") })
        Expect(ProjectDetection.Glyph(command,caption) == expected);
    return Task.CompletedTask;
});
await Check("worker Detect accepts bounded suggestion no-match and rejects unsafe URLs", async () => {
    var project = new ProjectReference("project.probe","Test Linux","local","/tmp/project");
    await using (var worker = new WorkerClient("Test Linux",Fake("project-probe"))) Expect((await worker.CallAsync("project.probe",project)).Suggestion is { Subtitle:"bun · next" });
    await using (var worker = new WorkerClient("Test Linux",Fake("project-probe-empty"))) Expect((await worker.CallAsync("project.probe",project)).Suggestion is null);
    await using (var worker = new WorkerClient("Test Linux",Fake("project-probe-unsafe"))) await Throws<WorkerException>(() => worker.CallAsync("project.probe",project),error => error.Code == "protocolMismatch");
});

await Check("project checks preserve shared multiline detail and optional legacy protocol status", async () => {
    var project = new ProjectReference("project.check.fixture","Test Linux","local","/tmp/project");
    foreach(var operation in new[]{"project.status","project.check"}) await using (var worker = new WorkerClient("Test Linux",Fake("project-check"))) {
        var status = (await worker.CallAsync(operation,project)).Status!;
        Expect(status.CheckSummary is { Tone:"good",State:"Fixture is running" } && status.CheckSummary.Detail.Contains("\r\n\tDetails") && status.CheckedAt == 0);
    }
    foreach(var operation in new[]{"project.status","project.check"}) await using (var worker = new WorkerClient("Test Linux",Fake("project-check-legacy"))) {
        var status = (await worker.CallAsync(operation,project)).Status!;
        Expect(status.CheckSummary is null && status.CheckedAt is null);
    }
});
await Check("project check transport rejects invalid tones oversized text controls and timestamps", async () => {
    var project = new ProjectReference("project.check.fixture","Test Linux","local","/tmp/project");
    foreach (var mode in new[] { "project-check-tone","project-check-state-control","project-check-state-long","project-check-state-null","project-check-detail-control",
        "project-check-detail-long","project-check-detail-null","project-check-time-negative","project-check-time-overflow","project-check-time-nonfinite" }) {
        foreach(var operation in new[]{"project.status","project.check"}) { await using var worker = new WorkerClient("Test Linux",Fake(mode));
        await Throws<WorkerException>(() => worker.CallAsync(operation,project),error => error.Code == "protocolMismatch"); }
    }
});
await Check("project check validation permits shared tones Unicode detail and finite date boundaries", () => {
    foreach (var tone in new[] { "good","busy","bad","idle" }) {
        Expect(SettingsChecks.Valid(new(tone,"Состояние",new string('Ж',8192) + ""),0));
        Expect(SettingsChecks.Valid(new(tone,new string('Ж',256),"Source\r\n\tDetail"),253402300799));
    }
    Expect(SettingsChecks.Valid(null,null) && SettingsChecks.Valid(null,0));
    foreach (var date in new[] { double.NaN,double.PositiveInfinity,double.NegativeInfinity,-1,253402300800 }) Expect(!SettingsChecks.Valid(null,date));
    Expect(!SettingsChecks.Valid(new("good","state\tvalue","detail"),0));
    return Task.CompletedTask;
});

await Check("project browser Test selects the actual opening address before a deployed environment", () => {
    var project = new ProjectReference("project.browser","Test Linux","local","/tmp/project","npm run dev",HealthURL:"http://localhost:8111/health",OpenURL:"http://localhost:4112/front");
    var settings = new CardSettings(project,"Fixture",Links:[new("PROD","https://example.test",true,"site")]);
    Expect(ProjectLinks.TestTarget(settings) == "http://localhost:4112/front");
    Expect(ProjectLinks.TestTarget(settings with { Project=project with { OpenURL=null } }) == "http://localhost:8111/health");
    var deployed=settings with { Project=project with { OpenURL=null,HealthURL=null }, Links=[new("Admin","https://admin.example.test",true,"tool"),new("PROD","https://example.test",true,"site")] };
    Expect(ProjectLinks.TestTarget(deployed) == "https://example.test");
    var ddev=settings with { Project=project with { Kind="ddev",OpenURL=null,HealthURL=null } };
    var status=new ProjectStatus(project.Id,"stopped",null,"https://fixture.ddev.site",null,null,ToolLinks:[new("Mailpit","https://fixture.ddev.site:8026"),new("xhgui","https://fixture.ddev.site:8143")]);
    Expect(ProjectLinks.TestTarget(ddev,status) == "https://fixture.ddev.site:8026");
    Expect(ProjectLinks.TestTarget(ddev with { HiddenTools=["Mailpit","xhgui"] },status) == "https://fixture.ddev.site");
    var arc=settings with { Project=project with { Kind="arc",Arc=new("sandbox.example") },Links=ProjectLinks.Defaults("arc") };
    Expect(ProjectLinks.TestTarget(arc) == "https://sandbox.example.arcpublishing.com/home/");
    return Task.CompletedTask;
});

await Check("Arc template defaults match hosted tooling and retain a single sandbox prefix", () => {
    var project = new ProjectReference("arc.project.links","","arc","",Arc:new("sandbox.example","news"));
    var links = ProjectLinks.Defaults("arc");
    Expect(links.Take(3).All(link => link.Enabled) && links.Skip(3).All(link => !link.Enabled));
    var resolved = ProjectLinks.Resolve(links[0],project,null)!;
    Expect(resolved.Url == "https://sandbox.example.arcpublishing.com/home/");
    Expect(ProjectLinks.Resolve(new("Custom","https://{org}.example/{site}"),project,null)!.Url == "https://sandbox.example.example/news");
    Expect(ProjectLinks.Resolve(links[0],project with { Arc = new() },null) is null);
    return Task.CompletedTask;
});
await Check("DDEV templates retain tool or site kinds and local runtime gating while hosted sites stay usable", () => {
    var reference = new ProjectReference("ddev.project.example","Ubuntu","ddev","/tmp/example");
    var settings = new CardSettings(reference,"Example",Links:[new("Admin","{site}/user/login",Kind:"tool"),new("PROD","https://example.com",Kind:"site"),new("Disabled","https://example.com/retained",false,"site")]);
    var links = ProjectLinks.Present(settings,new(reference.Id,"stopped",null,"https://example.ddev.site/",null,null));
    Expect(links.Length == 2 && links[0].RequiresRunning && !links[1].RequiresRunning);
    Expect(links[0].Link.Url == "https://example.ddev.site/user/login" && links[0].Link.EffectiveKind == "tool" && links[1].Link.EffectiveKind == "site");
    Expect(ProjectLinks.Resolve(settings.LinkList[0],reference,null) is null);
    return Task.CompletedTask;
});
await Check("legacy Arc template correction is exact and preserves custom edits and disabled state", () => {
    var exact = new ProjectLink("Dev Center","https://sandbox.{org}.arcpublishing.com/developer/",false);
    Expect(ProjectLinks.MigrateArc(exact) is { Label:"Deployer",Url:"https://{org}.arcpublishing.com/deployments/fusion/",Enabled:false });
    var custom = exact with { Url = exact.Url+"?custom=1" };
    Expect(ProjectLinks.MigrateArc(custom) == custom);
    return Task.CompletedTask;
});
await Check("links-only Arc settings round-trip without worker and attaching a checkout preserves identity and placement", () => {
    var card = new CardSettings(new("arc.project.hosted","","arc","",Arc:new("sandbox.example","news")),"Hosted",X:91,Y:123,Collapsed:true,Links:ProjectLinks.Defaults("arc"));
    var settings = new DeckSettings(1,[],[card]); settings.Validate();
    var implicitLinks = card with { Links = null };
    Expect(implicitLinks.LinkList.Length == 7 && implicitLinks.LinkList.Take(3).All(link => link.Enabled));
    var decoded = JsonSerializer.Deserialize<DeckSettings>(JsonSerializer.Serialize(settings,WorkerProtocol.Json),WorkerProtocol.Json)!; decoded.Validate();
    var attached = decoded with { Workers = [new("Ubuntu","/tmp/worker")],Cards=[decoded.Cards[0] with { Project=decoded.Cards[0].Project with { Distribution="Ubuntu",Path="/tmp/checkout" } }] }; attached.Validate();
    Expect(attached.Cards[0].Project.Id == card.Project.Id && attached.Cards[0].Collapsed && attached.Cards[0].X == card.X && attached.Cards[0].Y == card.Y);
    return Task.CompletedTask;
});
await Check("typed templates reject unknown placeholders unsafe schemes empty enabled links and invalid Arc options", () => {
    foreach (var link in new[] { new ProjectLink("Bad","https://{unknown}.example"),new("Bad","file:///tmp/path",false),new("Bad","",true),new("Bad","https://example.com",Kind:"invalid") }) Expect(!DeckSettings.ValidConfiguredLink(link));
    Expect(DeckSettings.ValidConfiguredLink(new("Draft","",false,"tool")));
    foreach (var arc in new[] { new ArcOptions("bad..host"),new(Site:"a/b"),new(LocalURL:"file:///tmp/path"),new(HealthPath:"//other"),new(HealthPath:"/health\n") }) Expect(!ProjectLinks.ValidArc(arc));
    return Task.CompletedTask;
});
static ProcessStartInfo Fake(string mode = "normal", string distribution = "Test Linux")
{
    var start = new ProcessStartInfo(Environment.ProcessPath!);
    start.ArgumentList.Add("--fake-worker"); start.ArgumentList.Add("--fake-distribution"); start.ArgumentList.Add(distribution); start.ArgumentList.Add(mode);
    return start;
}

await Check("columns use measured compact/expanded heights with exactly twelve DIP gaps", () => {
    var cards = new MeasuredCard[] { new("remote",410,240),new("compact",410,64),new("local",410,160) };
    var places = ColumnLayout.Tidy(cards,24,40,new(0,0,1200,900));
    Expect(places.Select(point => point.Id).SequenceEqual(cards.Select(card => card.Id)));
    Expect(places[0].X == 24 && places[0].Y == 40 && places[1].Y == 292 && places[2].Y == 368);
    Expect(places.All(point => point.X == 24)); return Task.CompletedTask;
});
await Check("columns wrap by actual bottom edge and grow to the side with free space", () => {
    var cards = new MeasuredCard[] { new("a",410,200),new("b",410,250),new("c",410,300),new("d",410,64) };
    var places = ColumnLayout.Tidy(cards,30,20,new(0,0,1280,640));
    Expect(places[1].Y == 232 && places[2].X == 452 && places[2].Y == 20 && places[3].Y == 332);
    Expect(places.All(point => point.Y + cards.Single(card => card.Id == point.Id).Height <= 640));
    var left = ColumnLayout.Tidy(cards,860,20,new(0,0,1280,640));
    Expect(left[2].X == 438 && left[2].Y == 20); return Task.CompletedTask;
});
await Check("columns preserve negative-monitor anchors and allow an exact fit without wrapping", () => {
    var places = ColumnLayout.Tidy([new("a",410,100),new("b",410,100)],-1800,30,new(-1920,0,1920,242));
    Expect(places[0].X == -1800 && places[0].Y == 30 && places[1].X == -1800 && places[1].Y == 142);
    return Task.CompletedTask;
});
await Check("crowded or oversized columns keep headers reachable and empty decks have no placements", () => {
    var places = ColumnLayout.Tidy([new("oversize",410,1200),new("b",410,400),new("c",410,400)],2000,2000,new(0,0,820,600));
    Expect(places.Length == 3 && places.All(point => point.X >= 0 && point.X <= 410 && point.Y >= 0 && point.Y < 600));
    Expect(places[0].Y == 0 && places[1].Y == 0 && ColumnLayout.Tidy([],0,0,new(0,0,100,100)).Length == 0);
    return Task.CompletedTask;
});
await Check("column geometry rejects non-finite dimensions and duplicate identities", async () => {
    await Throws<ArgumentException>(() => Task.Run(() => ColumnLayout.Tidy([new("a",410,double.NaN)],0,0,new(0,0,1000,900))));
    await Throws<ArgumentException>(() => Task.Run(() => ColumnLayout.Tidy([new("a",410,60),new("a",410,60)],0,0,new(0,0,1000,900))));
});
await Check("WSL launch keeps distribution and spaced Unicode Linux paths as individual arguments", () =>
{
    var start = WorkerClient.WslStart("Test Linux", "/home/user/проект с пробелами/worker");
    Expect(!start.UseShellExecute);
    Expect(start.ArgumentList[1] == "Test Linux");
    Expect(start.ArgumentList[5] == "/home/user/проект с пробелами/worker/run-worker");
    return Task.CompletedTask;
});
await Check("phone links preserve port, path and query and reject unsafe or routed domains", () => {
    var value = PhoneLink.Rewrite("http://localhost:8080/путь?a=1&b=two#part", true, "192.168.1.8");
    Expect(value?.Host == "192.168.1.8" && value.Port == 8080 && value.Query == "?a=1&b=two" && value.Fragment == "#part");
    Expect(PhoneLink.Rewrite("http://[::1]:3000/", true, "192.168.1.8")?.Port == 3000);
    foreach (var url in new[] { "http://shop.ddev.site", "https://example.com", "file:///tmp/x", "http://user:secret@localhost:8080", "http://localhost:0" }) Expect(PhoneLink.Rewrite(url, true, "192.168.1.8") is null);
    Expect(PhoneLink.Rewrite("http://localhost", false, "192.168.1.8") is null && PhoneLink.Rewrite("http://localhost", true, "127.0.0.1") is null);
    return Task.CompletedTask;
});
await Check("phone links already using this PC LAN address remain usable", () => {
    var value = PhoneLink.Rewrite("http://192.168.1.8:8080/front?q=a#section",true,"192.168.1.8");
    Expect(value?.Port == 8080 && value.Query == "?q=a" && value.Fragment == "#section");
    Expect(PhoneLink.Rewrite("http://192.168.1.9:8080",true,"192.168.1.8") is null);
    return Task.CompletedTask;
});
await Check("phone LAN discovery excludes WSL Docker VPN and prefers physical Wi-Fi", () => {
    LanInterface Item(string name, string ip, System.Net.NetworkInformation.NetworkInterfaceType type = System.Net.NetworkInformation.NetworkInterfaceType.Ethernet, bool up = true) => new(name, name, type, up, true, [ip]);
    Expect(PhoneLink.Address([Item("vEthernet WSL", "172.20.1.1"), Item("Docker virtual", "172.18.0.1"), Item("VPN", "10.0.0.2"), Item("Ethernet", "192.168.1.3"), Item("Wi-Fi", "192.168.1.8", System.Net.NetworkInformation.NetworkInterfaceType.Wireless80211)]) == "192.168.1.8");
    Expect(PhoneLink.Address([Item("Ethernet", "169.254.1.2"), Item("Wi-Fi", "192.168.1.8", up: false)]) is null);
    return Task.CompletedTask;
});
await Check("phone availability explains routed stopped invalid and missing LAN targets", () => {
    Expect(PhoneLink.Resolve("https://shop.ddev.site",true,"192.168.1.8").Issue == PhoneLinkIssue.RoutedHost);
    Expect(PhoneLink.Resolve("http://localhost:8080",true,null).Issue == PhoneLinkIssue.NoLAN);
    Expect(PhoneLink.Resolve(null,true,"192.168.1.8").Issue == PhoneLinkIssue.NoSite);
    Expect(PhoneLink.Resolve("file:///tmp/x",true,"192.168.1.8").Issue == PhoneLinkIssue.InvalidURL);
    Expect(PhoneLink.Resolve("http://localhost:8080",false,null).Issue == PhoneLinkIssue.NotRunning);
    Expect(PhoneLink.Resolve("http://localhost:8080/\nsecret",true,"192.168.1.8").Issue == PhoneLinkIssue.InvalidURL);
    var prefix = "http://localhost:8080/";
    Expect(PhoneLink.Resolve(prefix+new string('a',2048-prefix.Length),true,"192.168.100.100").Issue == PhoneLinkIssue.InvalidURL);
    return Task.CompletedTask;
});
await Check("explicit phone URL is bounded credential-free and never uses self-addressing domains", () => {
    foreach (var bad in new[] { "http://localhost:8080", "http://LOCALHOST./", "http://shop.localhost", "https://shop.ddev.site", "https://shop.ddev.site./", "http://127.0.0.1:8080", "http://[::1]", "http://0.0.0.0", "http://[::]", "http://169.254.1.2", "http://224.0.0.1", "http://[::ffff:0.0.0.0]", "http://[::ffff:169.254.1.2]", "http://[::ffff:224.0.0.1]", "http://[::ffff:127.0.0.1]", "file:///tmp/x", "https://user:secret@example.com", "http://example.com:0", "http://example.com/\nsecret", "https://example.com/?data="+new string('a',2048) }) {
        Expect(!PhoneLink.ValidPhoneURL(bad),"Unsafe phone URL accepted: "+bad);
        Expect(PhoneLink.Resolve("https://shop.ddev.site",true,null,bad).Issue == PhoneLinkIssue.InvalidURL);
    }
    foreach(var good in new[] { "http://192.168.1.8:8080/front?q=a#section", "https://phone.example.com/front?preview=1" }) {
        Expect(PhoneLink.ValidPhoneURL(good));
        Expect(PhoneLink.Resolve("https://shop.ddev.site",true,null,good).Address?.AbsoluteUri == good);
        Expect(PhoneLink.Resolve("https://shop.ddev.site",false,null,good).Issue == PhoneLinkIssue.NotRunning);
    }
    return Task.CompletedTask;
});
await Check("phone setting roundtrip preserves legacy defaults and unrelated project fields", () => {
    var legacy = new DeckSettings(1,[new("Test Linux","/tmp/worker")],[new(new("p","Test Linux","ddev","/tmp/project"),"Project",X:41,Y:73,Collapsed:true)]);
    var restored = JsonSerializer.Deserialize<DeckSettings>(JsonSerializer.Serialize(legacy,WorkerProtocol.Json),WorkerProtocol.Json)!;
    restored.Validate(); Expect(restored.Cards[0].PhoneURL is null);
    var configured = restored with { Cards = [restored.Cards[0] with { PhoneURL="http://192.168.1.8:8080/front" }] };
    configured.Validate(); var saved = JsonSerializer.Deserialize<DeckSettings>(JsonSerializer.Serialize(configured,WorkerProtocol.Json),WorkerProtocol.Json)!;
    Expect(saved.Cards[0] == configured.Cards[0] && saved.Cards[0].Project == legacy.Cards[0].Project && saved.Cards[0].Collapsed && saved.Cards[0].X == 41 && saved.Cards[0].Y == 73);
    try { (saved with { Cards=[saved.Cards[0] with { PhoneURL="http://localhost" }] }).Validate(); throw new Exception("Invalid phone setting accepted"); } catch(InvalidDataException) { }
    return Task.CompletedTask;
});
await Check("independent ZXing decoder reads short Unicode and long QR phone URLs", () => {
    foreach (var uri in new[] { new Uri("http://192.168.1.8:8080/"), new Uri("https://192.168.1.8:4443/путь?foo=bar%20baz"), new Uri("http://192.168.1.8:3000/?data=" + new string('a', 1500)) }) {
        var matrix = PhoneCode.Encode(uri); const int scale = 4; var width = matrix.Length * scale; var rgb = new byte[width * width * 3];
        for (var y = 0; y < width; y++) for (var x = 0; x < width; x++) for (var channel = 0; channel < 3; channel++) rgb[(y * width + x) * 3 + channel] = matrix[y / scale][x / scale] ? (byte)0 : (byte)255;
        var reader = new ZXing.BarcodeReaderGeneric { Options = new ZXing.Common.DecodingOptions { PossibleFormats = [ZXing.BarcodeFormat.QR_CODE], TryHarder = true } };
        Expect(reader.Decode(rgb, width, width, ZXing.RGBLuminanceSource.BitmapFormat.RGB24)?.Text == uri.AbsoluteUri, "Independent QR decode mismatch");
    } return Task.CompletedTask;
});
await Check("log terminal commands preserve literal quotes and delimiters without Windows Terminal parsing", () => {
    var project = new ProjectReference("p", "Test Linux", "local", "/home/user/a'; echo injected");
    var command = TerminalLaunch.CreateLogs(project, "/home/user/log'; touch injected");
    Expect(command.FileName == "wsl.exe" && command.ArgumentList[3] == project.Path && command.ArgumentList[^1].Contains("tail -n 400 -F --"));
    Expect(TerminalLaunch.CreateLogs(project with { Kind = "ddev", Path = "/tmp" }).ArgumentList[^1].Contains("ddev logs -s web -f"));
    return Task.CompletedTask;
});
await Check("Fusion terminal follows the resolved shared engine and rejects injected container targets", async () => {
    var project = new ProjectReference("p", "Test Linux", "arc", "/home/user/project");
    Expect(TerminalLaunch.ContainerFromSource("docker logs fusion-engine") == "fusion-engine");
    var launch = TerminalLaunch.CreateLogs(project, containerName: "fusion-engine");
    Expect(launch.ArgumentList[^1].Contains("docker logs --tail 400 --follow") && !launch.ArgumentList[^1].Contains("compose"));
    foreach (var source in new[] { "docker logs", "docker logs engine; touch /tmp/x", "docker logs --help", "docker logs engine\n" }) Expect(TerminalLaunch.ContainerFromSource(source) is null);
    foreach (var target in new string?[] { null, "engine; touch /tmp/x", "--help" }) await Throws<HostFailure>(() => Task.FromResult(TerminalLaunch.CreateLogs(project, containerName: target)), error => error.Code == "logFileUnavailable");
});
await Check("bounded log payload and full-file path cross the worker boundary", async () => {
    var project = new ProjectReference("p", "Test Linux", "local", "/home/user/project");
    await using (var worker = new WorkerClient("Test Linux", Fake())) {
        var logs = (await worker.CallAsync("project.logs", project)).Logs;
        Expect(logs?.Lines.Length == 400 && logs.FilePath == "/home/user/project/log.txt");
    }
    foreach (var mode in new[] { "logs-missing", "logs-lines", "logs-path", "logs-bytes" }) {
        await using var worker = new WorkerClient("Test Linux", Fake(mode));
        await Throws<WorkerException>(() => worker.CallAsync("project.logs", project), error => error.Code == "protocolMismatch");
        Expect(!worker.IsConnected);
    }
});
await Check("additive project browser links refresh and log geometry preserve legacy settings", async () => {
    var legacy = new DeckSettings(1, [new("Test Linux", "/tmp/worker")], [new(new("p", "Test Linux", "local", "/tmp/project"), "Project")]);
    legacy.Validate(); Expect(legacy.RefreshSeconds == 60 && legacy.LogWindowList.Length == 0 && legacy.Cards[0].LinkList.Length == 0);
    var updated = legacy with { RefreshSeconds = 300, LogWindows = [new("p", 100, 200, 900, 560)], Cards = [legacy.Cards[0] with { Browser = "chrome", BrowserProfile = "Profile 1", Links = [new("UAT", "https://example.com/uat")] }] };
    var value = JsonSerializer.Deserialize<DeckSettings>(JsonSerializer.Serialize(updated, WorkerProtocol.Json), WorkerProtocol.Json)!; value.Validate();
    Expect(value.Cards[0].Project.Id == "p" && value.Cards[0].BrowserProfile == "Profile 1" && value.RefreshSeconds == 300 && value.LogWindowList[0].Width == 900);
    foreach (var bad in new[] { updated with { RefreshSeconds = 2 }, updated with { LogWindows = [null!] }, updated with { LogWindows = [new("p", 0, 0, 10, 10)] },
        updated with { Cards = [legacy.Cards[0] with { Links = [new("Bad", "file:///tmp/x")] }] } }) await Throws<InvalidDataException>(() => { bad.Validate(); return Task.CompletedTask; });
});
await Check("invalid Linux paths and control characters are rejected before launch", async () =>
{
    foreach (var path in new[] { "C:\\worker", "//server/path", "~/worker", "/home/../worker", "/home/worker\n" })
        await Throws<ArgumentException>(() => Task.FromResult(WorkerClient.WslStart("Ubuntu", path)));
});
await Check("folder picker accepts only the selected WSL distribution and preserves Unicode paths", () => {
    Expect(LinuxFolder.FromWindows("Ubuntu-24.04", @"\\wsl.localhost\Ubuntu-24.04\home\user\проект с пробелами") == "/home/user/проект с пробелами");
    Expect(LinuxFolder.FromWindows("Debian", @"\\wsl$\Debian") == "/");
    foreach (var path in new[] { @"C:\Users\user", @"\\wsl.localhost\Debian\home\user", @"\\wsl.localhost\Ubuntu-24.04-extra\tmp", @"\\wsl.localhost\Ubuntu-24.04\home\..\etc" })
        Expect(LinuxFolder.FromWindows("Ubuntu-24.04",path) is null);
    return Task.CompletedTask;
});
await Check("tool visibility and disabled environment drafts preserve legacy links without weakening worker URLs", async () => {
    var legacy = new DeckSettings(1,[new("Ubuntu","/tmp/worker")],[new(new("p","Ubuntu","ddev","/tmp/project"),"Example",Links:[new("TEST","https://example.com")])]);
    legacy.Validate(); Expect(legacy.Cards[0].LinkList[0].Enabled && legacy.Cards[0].HiddenToolList.Length == 0);
    var edited = legacy with { Cards = [legacy.Cards[0] with { HiddenTools = ["xhgui"], Links = [new("TEST","https://example.com",false),new("UAT","",false)] }] };
    var roundtrip = JsonSerializer.Deserialize<DeckSettings>(JsonSerializer.Serialize(edited,WorkerProtocol.Json),WorkerProtocol.Json)!; roundtrip.Validate();
    Expect(!roundtrip.Cards[0].LinkList[0].Enabled && roundtrip.Cards[0].LinkList[0].Url == "https://example.com" && roundtrip.Cards[0].HiddenToolList.SequenceEqual(new[] { "xhgui" }));
    Expect(!DeckSettings.ValidLink(new("UAT","",false)),"Worker accepted an empty URL");
    foreach (var invalid in new[] { edited.Cards[0] with { HiddenTools = ["unexpected"] }, edited.Cards[0] with { HiddenTools = ["xhgui","XHGUI"] }, edited.Cards[0] with { Links = [new("UAT","",true)] }, edited.Cards[0] with { Links = [new("UAT","file:///tmp/x",false)] } })
        await Throws<InvalidDataException>(() => { (edited with { Cards = [invalid] }).Validate(); return Task.CompletedTask; });
});
await Check("an unavailable worker executable becomes a handled launch failure", async () =>
{
    var missing = Path.Combine(Path.GetTempPath(), "devdeck-missing-executable-" + Guid.NewGuid().ToString("N") + ".exe");
    await Throws<WorkerException>(() => { _ = new WorkerClient("Test Linux", new ProcessStartInfo(missing)); return Task.CompletedTask; }, error => error.Code == "launchFailed");
});
await Check("terminal launch keeps Unicode and delimiters literal with direct WSL fallback", () =>
{
    var regular = TerminalLaunch.Create("Test Linux", "/home/user/проект с пробелами");
    Expect(regular.FileName == "wt.exe" && regular.ArgumentList.Last() == "/home/user/проект с пробелами");
    foreach (var path in new[] { "/home/user/a;new-tab", "/home/user/a\"b" })
    {
        var literal = TerminalLaunch.Create("Test Linux", path);
        Expect(literal.FileName == "wsl.exe" && literal.ArgumentList.Last() == path && literal.ArgumentList.Count == 4);
    }
    Expect(TerminalLaunch.Create("Test Linux", "/tmp", false).FileName == "wsl.exe");
    return Task.CompletedTask;
});
await Check("folder and log terminals explicitly select a stable Windows directory before entering WSL", () =>
{
    var previousDirectory = Environment.CurrentDirectory;
    var previewDirectory = Path.Combine(Path.GetTempPath(), "devdeck-terminal-cwd-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(previewDirectory);
    try
    {
        Environment.CurrentDirectory = previewDirectory;
        var project = new ProjectReference("p", "Test Linux", "ddev", "/home/user/проект с пробелами");
        foreach (var launch in new[] { TerminalLaunch.Create(project.Distribution, project.Path), TerminalLaunch.CreateLogs(project),
            TerminalLaunch.Create(project.Distribution, project.Path, false), TerminalLaunch.CreateLogs(project, preferWindowsTerminal: false) })
        {
            Expect(Path.IsPathFullyQualified(launch.WorkingDirectory) && Directory.Exists(launch.WorkingDirectory), "Missing Windows working directory");
            Expect(launch.WorkingDirectory != previewDirectory, "Inherited mutable Preview directory");
            if (launch.FileName == "wt.exe")
                Expect(launch.ArgumentList.Take(4).SequenceEqual(new[] { "new-tab", "--startingDirectory", launch.WorkingDirectory, "wsl.exe" }), "Missing explicit Terminal tab directory");
            var cd = launch.ArgumentList.IndexOf("--cd");
            Expect(cd >= 0 && launch.ArgumentList[cd + 1] == project.Path, "Changed Linux project directory");
        }
    }
    finally { Environment.CurrentDirectory = previousDirectory; Directory.Delete(previewDirectory); }
    return Task.CompletedTask;
});
await Check("WSL UTF16 inventory parses names and excludes Docker internal distributions", () =>
{
    var names = WslDistributions.Parse(Encoding.Unicode.GetBytes("\uFEFFUbuntu-24.04\r\nDebian\r\ndocker-desktop\r\n"));
    Expect(names.SequenceEqual(new[] { "Ubuntu-24.04", "Debian" })); return Task.CompletedTask;
});
await Check("Swift status field spelling round-trips into Windows DTOs", () =>
{
    var response = JsonSerializer.Deserialize<WorkerResponse>("""{"protocolVersion":1,"id":"x","distribution":"Debian","status":{"projectID":"arc.project.a","state":"stopped","siteURL":"http://localhost:3000"}}""", WorkerProtocol.Json)!;
    Expect(response.Status?.ProjectID == "arc.project.a" && response.Status.SiteURL == "http://localhost:3000");
    return Task.CompletedTask;
});
await Check("DDEV version metadata round-trips without conflating engine version and accepts legacy omission", () => {
    foreach (var versions in new string?[] { null,"php 8.4 · mysql 8.0","php 8.3 · mariadb 10.11","postgres 16" }) {
        var status = new ProjectStatus("ddev.project.metadata","stopped",null,null,"drupal 11",null,VersionsLine:versions);
        var decoded = JsonSerializer.Deserialize<ProjectStatus>(JsonSerializer.Serialize(status,WorkerProtocol.Json),WorkerProtocol.Json)!;
        Expect(decoded.VersionsLine == versions && decoded.EngineVersion is null && decoded.Framework == "drupal 11");
    }
    var legacy = JsonSerializer.Deserialize<ProjectStatus>("""{"projectID":"legacy","state":"unknown"}""",WorkerProtocol.Json)!;
    Expect(legacy.VersionsLine is null); return Task.CompletedTask;
});
await Check("worker client accepts version lines and rejects controls or more than 512 UTF8 bytes", async () => {
    var project = new ProjectReference("ddev.project.metadata","Test Linux","ddev","/tmp");
    await using (var worker = new WorkerClient("Test Linux",Fake("project-versions")))
        Expect((await worker.CallAsync("project.status",project)).Status?.VersionsLine == "php 8.4 · mysql 8.0");
    foreach (var mode in new[] { "project-versions-control","project-versions-long","project-versions-utf8" }) {
        await using var worker = new WorkerClient("Test Linux",Fake(mode));
        await Throws<WorkerException>(() => worker.CallAsync("project.status",project), error => error.Code == "protocolMismatch");
    }
});
await Check("local batch shares a cycle starts independent reads and coalesces a slow previous poll", async () => {
    var batch = new LocalRefreshBatch(); var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
    var cycles = new List<string>(); var independentRead = false;
    var first = batch.RunAsync([cycle => { cycles.Add(cycle); return release.Task; },cycle => { cycles.Add(cycle); independentRead = true; return Task.CompletedTask; }]);
    Expect(independentRead && cycles.Count == 2 && cycles[0] == cycles[1] && cycles[0].Length == 32 && LocalRefreshBatch.Interval.TotalSeconds == 10);
    var overlap = batch.RunAsync([_ => throw new Exception("Overlapping poll started another batch.")]);
    Expect(ReferenceEquals(first,overlap)); release.SetResult(); await first;
    await batch.RunAsync([cycle => { cycles.Add(cycle); return Task.CompletedTask; }]);
    Expect(cycles[2] != cycles[0]);
});
await Check("local cycle survives native transport and invalid cycle never contaminates a worker session", async () => {
    await using var worker = new WorkerClient("Test Linux",Fake("project-cycle"));
    var project = new ProjectReference("ddev.project.poll","Test Linux","ddev","/tmp");
    foreach (var cycle in new[] { "", "bad\ncycle", new string('Ж',65) })
        await Throws<WorkerException>(() => worker.CallAsync("project.status",project,refreshCycle:cycle), error => error.Code == "invalidRequest");
    Expect((await worker.CallAsync("project.status",project,refreshCycle:"fixture-cycle")).Status?.VersionsLine == "fixture-cycle");
    Expect((await worker.CallAsync("project.status",project)).Status?.VersionsLine is null);
});
await Check("frame reader preserves buffered next frame and unterminated EOF frame", async () =>
{
    var reader = new BoundedFrameReader(new MemoryStream(Encoding.UTF8.GetBytes("one\ntwo\nlast")), 4);
    foreach (var expected in new[] { "one", "two", "last" }) Expect(Encoding.UTF8.GetString((await reader.ReadAsync())!) == expected);
    Expect(await reader.ReadAsync() is null);
});
await Check("frame reader rejects a response before unbounded allocation", async () =>
{
    var reader = new BoundedFrameReader(new MemoryStream(new byte[100_000]), 32);
    await Throws<WorkerException>(() => reader.ReadAsync(), error => error.Code == "frameTooLarge");
});
await Check("ten simultaneous calls serialize request-response correlation", async () =>
{
    await using var worker = new WorkerClient("Test Linux", Fake());
    var responses = await Task.WhenAll(Enumerable.Range(0, 10).Select(_ => worker.CallAsync("hello")));
    Expect(responses.Select(response => response.Id).Distinct().Count() == 10);
});
await Check("a normal worker rejection leaves the transport reusable", async () =>
{
    await using var worker = new WorkerClient("Test Linux", Fake());
    await Throws<WorkerException>(() => worker.CallAsync("unsupported"), error => error.Code == "unsupportedOperation");
    Expect((await worker.CallAsync("hello")).Capabilities?.Contains("hello") == true);
});
await Check("worker reconnect replaces only a dead distro and never replays an interrupted operation", async () =>
{
    var launches = 0;
    await using var manager = new WorkerManager(settings => new WorkerClient("Test Linux", Fake(++launches == 1 ? "exit" : "normal")));
    var configuration = new WorkerSettings("Test Linux", "/home/user/worker");
    var first = await manager.GetAsync(configuration);
    var deadline = Stopwatch.StartNew();
    while (first.IsConnected && deadline.Elapsed < TimeSpan.FromSeconds(5)) await Task.Delay(20);
    Expect(!first.IsConnected);
    var replacements = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => manager.GetAsync(configuration)));
    Expect(launches == 2 && replacements.All(worker => ReferenceEquals(worker, replacements[0])));
    Expect(!ReferenceEquals(first, replacements[0]));
    Expect((await replacements[0].CallAsync("hello")).Capabilities?.Contains("hello") == true);
});
await Check("a lost distro worker reconnects without replacing the healthy distro session", async () =>
{
    var launches = new Dictionary<string, int>(StringComparer.Ordinal);
    await using var manager = new WorkerManager(settings => {
        var count = launches.GetValueOrDefault(settings.Distribution) + 1;
        launches[settings.Distribution] = count;
        return new WorkerClient(settings.Distribution, Fake(settings.Distribution == "Owned A" && count == 1 ? "exit" : "normal", settings.Distribution));
    });
    var firstSettings = new WorkerSettings("Owned A", "/home/user/runtime-a");
    var secondSettings = new WorkerSettings("Owned B", "/home/user/runtime-b");
    var first = await manager.GetAsync(firstSettings);
    var healthy = await manager.GetAsync(secondSettings);
    var deadline = Stopwatch.StartNew();
    while (first.IsConnected && deadline.Elapsed < TimeSpan.FromSeconds(5)) await Task.Delay(20);
    Expect(!first.IsConnected && healthy.IsConnected);
    var sessions = await Task.WhenAll(manager.GetAsync(firstSettings), manager.GetAsync(secondSettings), manager.GetAsync(firstSettings));
    Expect(!ReferenceEquals(sessions[0], first) && ReferenceEquals(sessions[0], sessions[2]) && ReferenceEquals(sessions[1], healthy));
    Expect(launches["Owned A"] == 2 && launches["Owned B"] == 1);
    Expect((await healthy.CallAsync("hello")).Distribution == "Owned B");
});
await Check("slow remote API cannot hold the local distribution transport and reconnect preserves local session", async () => {
    var launches = 0;
    await using var manager = new WorkerManager(settings => new WorkerClient(settings.Distribution,Fake(++launches == 1 ? "remote-stall" : "normal",settings.Distribution)));
    var configuration = new WorkerSettings("Test Linux","/home/user/worker");
    var remote = await manager.GetAsync(configuration,remote:true);
    using var cancellation = new CancellationTokenSource();
    var pending = remote.CallAsync("remote.snapshot",cancellation:cancellation.Token,remote:new("github.pullRequests","pullRequests",[]));
    WorkerClient? local = null;
    try {
        local = await manager.GetAsync(configuration).WaitAsync(TimeSpan.FromSeconds(10));
        Expect(!ReferenceEquals(remote,local) && !pending.IsCompleted && (await local.CallAsync("hello")).Distribution == configuration.Distribution);
    } finally {
        cancellation.Cancel();
        try { await pending; } catch (OperationCanceledException) { }
    }
    var replacement = await manager.GetAsync(configuration,remote:true);
    Expect(!ReferenceEquals(remote,replacement) && ReferenceEquals(local,await manager.GetAsync(configuration)) && launches == 3);
    await manager.ResetAsync(configuration.Distribution);
    Expect(local is not null && !local.IsConnected && !replacement.IsConnected);
});
await Check("correlated progress is delivered before the final response", async () =>
{
    await using var worker = new WorkerClient("Test Linux", Fake("progress"));
    var lines = new List<string>();
    var response = await worker.CallAsync("hello", onProgress: lines.Add);
    Expect(lines.SequenceEqual(new[] { "owned progress" }) && response.Capabilities?.Contains("hello") == true);
});
foreach (var mode in new[] { "version", "distribution", "id", "malformed" })
    await Check("untrusted worker " + mode + " response closes transport", async () =>
    {
        await using var worker = new WorkerClient("Test Linux", Fake(mode));
        await Throws<WorkerException>(() => worker.CallAsync("hello"));
        await Throws<WorkerException>(() => worker.CallAsync("hello"), error => error.Code == "disconnected");
    });
await Check("timeout disconnects an owned process rather than reusing stale output", async () =>
{
    await using var worker = new WorkerClient("Test Linux", Fake("stall"));
    await Throws<WorkerException>(() => worker.CallAsync("hello", timeout: TimeSpan.FromMilliseconds(200)), error => error.Code == "timedOut");
    await Throws<WorkerException>(() => worker.CallAsync("hello"), error => error.Code == "disconnected");
});
await Check("caller cancellation disconnects the interrupted transport", async () =>
{
    await using var worker = new WorkerClient("Test Linux", Fake("stall"));
    using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(200));
    await Throws<OperationCanceledException>(() => worker.CallAsync("hello", cancellation: cancellation.Token));
    await Throws<WorkerException>(() => worker.CallAsync("hello"), error => error.Code == "disconnected");
});
await Check("cross-distribution reference is rejected without damaging its worker", async () =>
{
    await using var worker = new WorkerClient("Test Linux", Fake());
    await Throws<WorkerException>(() => worker.CallAsync("project.status", new("card", "Other", "arc", "/tmp")), error => error.Code == "wrongDistribution");
    await worker.CallAsync("hello");
});
await Check("settings save atomically, preserve IDs and retain previous valid backup", () =>
{
    var directory = Path.Combine(Path.GetTempPath(), "devdeck-settings-test-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(directory);
    var store = new SettingsStore(Path.Combine(directory, "settings.json"));
    try
    {
        var original = new DeckSettings(1, [new("Ubuntu", "/home/user/worker")],
            [new(new("ddev.project.shop", "Ubuntu", "ddev", "/home/user/shop"), "Shop")]);
        store.Save(original);
        store.Save(original with { Floating = true });
        Expect(store.Load().Cards[0].Project.Id == "ddev.project.shop" && store.Load().Floating);
        Expect(!new SettingsStore(store.Path + ".bak").Load().Floating);
        var duplicate = original with { Cards = [original.Cards[0], original.Cards[0]] };
        try { store.Save(duplicate); throw new Exception("duplicate accepted"); } catch (InvalidDataException) { }
        Expect(store.Load().Floating);
        File.WriteAllText(store.Path, "{broken");
        try { store.Load(); throw new Exception("corruption accepted"); } catch (JsonException) { }
        Expect(File.ReadAllText(store.Path) == "{broken");
    }
    finally { foreach (var file in Directory.GetFiles(directory)) File.Delete(file); Directory.Delete(directory); }
    return Task.CompletedTask;
});

await Check("remote transport correlates card identity and rejects a mismatched snapshot", async () =>
{
    var request = new RemoteRequest("card", "pullRequests", [new("a", "A", "https://api.github.com", [], [], "synthetic-test-token")]);
    await using (var worker = new WorkerClient("Test Linux", Fake()))
        Expect((await worker.CallAsync("remote.snapshot", remote: request)).Remote?.CardID == "card");
    await using var invalid = new WorkerClient("Test Linux", Fake("remote-id"));
    await Throws<WorkerException>(() => invalid.CallAsync("remote.snapshot", remote: request), error => error.Code == "protocolMismatch");
});
await Check("credential cache namespace rotates with tokens and cannot appear in stored account settings", () =>
{
    var credential = new RemoteCredential("a", "A", "https://api.github.com", [], [], "offline-secret");
    Expect(credential.CacheScope?.Length == 64);
    Expect((credential with { Token = "different-offline-secret" }).CacheScope != credential.CacheScope);
    Expect((credential with { Token = null }).CacheScope is null);
    Expect(!credential.ToString().Contains("offline-secret"));
    var metadata = new RemoteAccountSettings("a", "A", "github", "https://api.github.com", [], []);
    var stored = JsonSerializer.Serialize(metadata, WorkerProtocol.Json);
    Expect(!stored.Contains("cacheScope") && !stored.Contains("offline-secret"));
    return Task.CompletedTask;
});
await Check("remote cards preserve three/twelve row limits and Actions failures outrank newer successful or active runs", () => {
    var rows = Enumerable.Range(1,20).Select(index => new RemoteRow(index.ToString(),"a","Run "+index,"example/web","https://example.com","ready","main",false,UpdatedAt:index)).ToArray();
    var snapshot = new RemoteSnapshot("card","pullRequests",20,0,null,rows,[],false);
    Expect(RemotePresentation.CardRows(snapshot,false).Length == 3 && RemotePresentation.CardRows(snapshot,true).Length == 12);
    rows[0] = rows[0] with { Health = "blocked" }; rows[1] = rows[1] with { Health = "attention" };
    snapshot = snapshot with { Kind = "actions",Rows = rows };
    Expect(RemotePresentation.CardRows(snapshot,false).Single().Id == "1");
    snapshot = snapshot with { Rows = rows.Skip(1).ToArray() };
    Expect(RemotePresentation.CardRows(snapshot,false).Single().Id == "2");
    Expect(RemotePresentation.CardRows(snapshot with { Rows = rows.Skip(2).ToArray() },false).Length == 0);
    return Task.CompletedTask;
});
await Check("notification clearing takes each account's displayed newest timestamp, including read rows", () => {
    var snapshot = new RemoteSnapshot("inbox","inbox",2,0,null,[new("1","a","A","org/web",null,"attention","mention",false,UpdatedAt:100),
        new("2","b","B","org/web",null,"ready","ciActivity",false,UpdatedAt:200),new("3","a","Read","org/web",null,"ready","other",false,UpdatedAt:300,IsUnread:false)],[],false);
    var cutoffs = RemotePresentation.ReadCutoffs(snapshot); Expect(cutoffs["a"] == 300 && cutoffs["b"] == 200);
    Expect(RemotePresentation.ReadCutoffs(snapshot with { Kind = "pullRequests" }).Count == 0);
    return Task.CompletedTask;
});
await Check("dashboard shortcuts route GitHub public/enterprise and hosted GitLab through account browser profiles", () => {
    var account = new RemoteAccountSettings("a","A","github","https://api.github.com",[],[],Browser:"chrome",BrowserProfile:"Profile 2");
    Expect(RemotePresentation.Dashboard(account,"pullRequests") == "https://github.com/pulls");
    Expect(RemotePresentation.Dashboard(account,"inbox") == "https://github.com/notifications");
    Expect(RemotePresentation.Dashboard(account with { Endpoint = "https://git.example.com/api/v3" },"actions") == "https://git.example.com");
    var url = RemotePresentation.Dashboard(account with { Provider = "gitlab",Endpoint = "https://git.example.com/team" },"mergeRequests");
    Expect(url == "https://git.example.com/team/dashboard/merge_requests");
    Expect(BrowserLaunch.Create(account.Browser,account.BrowserProfile,url).ArgumentList.Contains("--profile-directory=Profile 2"));
    return Task.CompletedTask;
});
await Check("remote metadata rejects foreign accounts executable URLs invalid status codes timestamps counts and duration", async () => {
    var request = new RemoteRequest("card","pullRequests",[new("a","A","https://api.github.com",[],[],"synthetic-test-token")]);
    foreach (var kind in new[] { "account","url","status","time","count","duration" }) {
        await using var worker = new WorkerClient("Test Linux",Fake("remote-invalid-"+kind));
        await Throws<WorkerException>(() => worker.CallAsync("remote.snapshot",remote:request),error => error.Code == "protocolMismatch");
    }
});
await Check("an invalid remote polling interval closes the worker transport", async () =>
{
    await using var worker = new WorkerClient("Test Linux", Fake("remote-interval"));
    await Throws<WorkerException>(() => worker.CallAsync("remote.snapshot", remote: new("card", "inbox", [])), error => error.Code == "protocolMismatch");
    Expect(!worker.IsConnected);
});
await Check("malformed remote failure rows and rates are rejected before rendering", async () =>
{
    await using var worker = new WorkerClient("Test Linux", Fake("remote-shape"));
    await Throws<WorkerException>(() => worker.CallAsync("remote.snapshot", remote: new("card", "inbox", [])), error => error.Code == "protocolMismatch");
    Expect(!worker.IsConnected);
});
await Check("account settings exclude tokens, reject embedded secrets and bind credential targets to provider and host", () =>
{
    var account = new RemoteAccountSettings("a", "A", "github", "https://api.github.com", [], []);
    account.Validate();
    Expect(account.CredentialTarget != (account with { Endpoint = "https://git.example.com" }).CredentialTarget);
    Expect(account.CredentialTarget != (account with { Id = "A" }).CredentialTarget);
    Expect(!new RemoteCredential("a", "A", account.Endpoint, [], [], "synthetic-test-token").ToString().Contains("synthetic-test-token"));
    try { JsonSerializer.Deserialize<RemoteAccountSettings>("""{"id":"a","label":"A","provider":"github","endpoint":"https://api.github.com","organizations":[],"repositories":[],"token":"forbidden"}""", WorkerProtocol.Json); throw new Exception("token accepted in settings"); }
    catch (JsonException) { }
    var settings = new DeckSettings(1, [new("Test Linux", "/home/user/runtime")], [], Accounts: [account],
        RemoteCards: [new("github.pr", "Requests", "pullRequests", "Test Linux", ["a"])]);
    settings.Validate();
    Expect(!JsonSerializer.Serialize(settings, WorkerProtocol.Json).Contains("token", StringComparison.OrdinalIgnoreCase));
    try { (settings with { RemoteCards = [settings.RemoteCardList[0] with { Kind = "mergeRequests" }] }).Validate(); throw new Exception("provider mismatch accepted"); }
    catch (InvalidDataException) { }
    return Task.CompletedTask;
});
await Check("account-only GitHub settings bootstrap PR and Inbox with both accounts, Actions stays hidden", () => {
    var settings = new DeckSettings(1, [new("Test Linux", "/home/user/runtime")], [], Accounts: [
        new("a", "A", "github", "https://api.github.com", [], []), new("b", "B", "github", "https://api.github.com", [], [])]);
    var result = RemoteCardCatalog.Synchronize(settings, key => new Localization("en").Get(key)); result.Validate();
    Expect(settings.RemoteCardList.Length == 0 && result.RemoteCardList.Length == 3);
    Expect(result.RemoteCardList.Count(card => card.Enabled) == 2);
    Expect(result.RemoteCardList.All(card => card.UseAllAccounts && card.AccountIDs.SequenceEqual(new[] { "a", "b" })));
    Expect(result.RemoteCardList.Select(card => card.Id).SequenceEqual(new[] { "github.pullRequests", "github.inbox", "github.actions" }));
    Expect(!RemoteCardCatalog.Resolve(result,"actions")!.Enabled);
    return Task.CompletedTask;
});
await Check("catalog is discoverable before setup and only creates GitLab MR when a provider exists", () => {
    Expect(RemoteCardCatalog.All.Length == 4 && !RemoteCardCatalog.Available(DeckSettings.Empty,"pullRequests"));
    var empty = DeckSettings.Empty; Expect(ReferenceEquals(RemoteCardCatalog.Synchronize(empty,key => key),empty));
    var settings = new DeckSettings(1,[new("Test Linux","/home/user/runtime")],[],Accounts:[new("lab","Lab","gitlab","https://git.example.com",[],[])]);
    var result = RemoteCardCatalog.Synchronize(settings,key => key); result.Validate();
    Expect(result.RemoteCardList is [{ Id: "gitlab.mergeRequests", Enabled: true }]);
    return Task.CompletedTask;
});
await Check("hidden legacy cards retain their IDs, explicit scope, placement and collapsed preference", () => {
    var old = new RemoteCardSettings("legacy.pr", "Custom pulls", "pullRequests", "Test Linux", ["a"],false,370,215,true);
    var settings = new DeckSettings(1,[new("Test Linux","/home/user/runtime")],[],Accounts:[
        new("a","A","github","https://api.github.com",[],[]),new("b","B","github","https://api.github.com",[],[])],RemoteCards:[old]);
    var result = RemoteCardCatalog.Synchronize(settings,key => key);
    Expect(ReferenceEquals(RemoteCardCatalog.Resolve(result,"pullRequests"),old));
    Expect(result.RemoteCardList.Count(card => card.Kind == "pullRequests") == 1);
    var shown = RemoteCardCatalog.SetEnabled(result,"pullRequests",true,key => key); shown.Validate();
    Expect(RemoteCardCatalog.Resolve(shown,"pullRequests") == (old with { Enabled = true }));
    var hidden = RemoteCardCatalog.SetEnabled(shown,"pullRequests",false,key => key);
    var repeated = RemoteCardCatalog.Synchronize(hidden,key => key);
    Expect(RemoteCardCatalog.Resolve(repeated,"pullRequests") == old && ReferenceEquals(repeated,RemoteCardCatalog.Synchronize(repeated,key => key)));
    return Task.CompletedTask;
});
await Check("new accounts join automatic scopes while manual scopes and hidden state remain unchanged", () => {
    var settings = new DeckSettings(1,[new("Test Linux","/home/user/runtime")],[],Accounts:[new("a","A","github","https://api.github.com",[],[])]);
    var result = RemoteCardCatalog.Synchronize(settings,key => key);
    var original = RemoteCardCatalog.Resolve(result,"pullRequests")!;
    result = result with { RemoteCards = result.RemoteCardList.Select(card => card.Kind == "inbox" ? card with { UseAllAccounts = false, Enabled = false } : card).ToArray(),
        Accounts = result.AccountList.Append(new("b","B","github","https://api.github.com",[],[])).ToArray() };
    var updated = RemoteCardCatalog.Synchronize(result,key => key); updated.Validate();
    Expect(RemoteCardCatalog.Resolve(updated,"pullRequests")!.AccountIDs.SequenceEqual(new[] { "a","b" }));
    Expect(RemoteCardCatalog.Resolve(updated,"pullRequests")!.Id == original.Id && RemoteCardCatalog.Resolve(updated,"pullRequests")!.X == original.X);
    Expect(RemoteCardCatalog.Resolve(updated,"inbox") is { Enabled: false, UseAllAccounts: false, AccountIDs: ["a"] });
    return Task.CompletedTask;
});
await Check("catalog visibility round trips through settings without regenerating IDs or enabling hidden polling", () => {
    var settings = new DeckSettings(1,[new("Test Linux","/home/user/runtime")],[],Accounts:[new("a","A","github","https://api.github.com",[],[])]);
    var result = RemoteCardCatalog.SetEnabled(RemoteCardCatalog.Synchronize(settings,key => key),"actions",true,key => key);
    result = RemoteCardCatalog.SetEnabled(result,"inbox",false,key => key);
    var loaded = JsonSerializer.Deserialize<DeckSettings>(JsonSerializer.Serialize(result,WorkerProtocol.Json),WorkerProtocol.Json)!;
    loaded = RemoteCardCatalog.Synchronize(loaded,key => key); loaded.Validate();
    Expect(RemoteCardCatalog.Resolve(loaded,"actions") is { Id: "github.actions", Enabled: true, UseAllAccounts: true });
    Expect(!RemoteCardCatalog.Resolve(loaded,"inbox")!.Enabled && loaded.RemoteCardList.Length == 3);
    return Task.CompletedTask;
});
await Check("account removal detaches scopes, keeps card identity and suspends automatic cards until setup returns", () => {
    var settings = new DeckSettings(1,[new("Test Linux","/home/user/runtime")],[],Accounts:[
        new("a","A","github","https://api.github.com",[],[]),new("b","B","github","https://api.github.com",[],[])]);
    settings = RemoteCardCatalog.Synchronize(settings,key => key);
    var original = RemoteCardCatalog.Resolve(settings,"pullRequests")!;
    settings = settings with { RemoteCards = settings.RemoteCardList.Append(new("manual","Custom","inbox","Test Linux",["a"],X:250,Y:400)).ToArray() };
    var removed = RemoteCardCatalog.RemoveAccount(settings,"a"); removed.Validate();
    Expect(removed.RemoteCardList.Single(card => card.Id == "manual") is { Enabled: false, AccountIDs: [] });
    Expect(RemoteCardCatalog.Resolve(removed,"pullRequests")!.AccountIDs.SequenceEqual(new[] { "b" }));
    removed = RemoteCardCatalog.Synchronize(RemoteCardCatalog.RemoveAccount(removed,"b"),key => key); removed.Validate();
    var suspended = RemoteCardCatalog.Resolve(removed,"pullRequests")!;
    Expect(suspended.Enabled && !RemoteCardCatalog.Active(removed,suspended) && suspended.Id == original.Id && suspended.X == original.X);
    var restored = RemoteCardCatalog.Synchronize(removed with { Accounts = [new("c","C","github","https://api.github.com",[],[])] },key => key); restored.Validate();
    Expect(RemoteCardCatalog.Active(restored,RemoteCardCatalog.Resolve(restored,"pullRequests")!) && restored.RemoteCardList.Length == 4);
    var selected = RemoteCardCatalog.SetEnabled(restored,"inbox",true,key => key); selected.Validate();
    Expect(!selected.RemoteCardList.Single(card => card.Id == "manual").Enabled);
    return Task.CompletedTask;
});
if (OperatingSystem.IsWindows()) await Check("Windows Credential Manager stores, replaces and deletes only an owned synthetic credential", () =>
{
    var account = new RemoteAccountSettings("test-" + Guid.NewGuid().ToString("N"), "Owned test", "github", "https://api.example.invalid", [], []);
    var tokens = new WindowsTokenStore();
    try
    {
        Expect(tokens.Read(account) is null);
        tokens.Write(account, "synthetic-credential-one"); Expect(tokens.Read(account) == "synthetic-credential-one");
        tokens.Write(account, "synthetic-credential-two"); Expect(tokens.Read(account) == "synthetic-credential-two");
        Expect(tokens.Read(account with { Endpoint = "https://other.example.invalid" }) is null);
        tokens.Write(account, null); Expect(tokens.Read(account) is null);
    }
    finally { tokens.Write(account, null); }
    return Task.CompletedTask;
});

await Check("six original language tables load and printf placeholders retain their order", () =>
{
    var english = new Localization("en"); Expect(english.Count > 400);
    foreach (var language in Localization.Languages)
    {
        var locale = new Localization(language); Expect(locale.Count == english.Count, "language key count mismatch");
        Expect(locale.Get("button.cancel") != "button.cancel");
        Expect(locale.Get("arc.portHeldBy", 27017, "owned fixture").Contains("27017"));
        Expect(locale.Get("arc.portHeldBy", 27017, "owned fixture").Contains("owned fixture"));
    }
    Expect(english.Get("card.actions.green", 50) == "50% green");
    return Task.CompletedTask;
});
await Check("worker and platform failures have safe actionable wording in all six languages", () =>
{
    string[] workerCodes = ["credentialsRejected", "forbidden", "unreachable", "rateLimited", "disconnected", "launchFailed", "invalidResponse", "protocolMismatch", "frameTooLarge",
        "invalidRequest", "invalidRequestID", "unsupportedVersion", "timedOut", "commandFailed", "outcomeNotConfirmed", "cancelled", "unsupportedOperation", "ddevUnavailable",
        "dockerUnavailable", "linuxNodeUnavailable", "fusionUnavailable", "composeUnavailable", "preflightUnavailable", "portConflict", "missingFolder", "invalidProject", "missingProject",
        "wrongDistribution", "remoteUnavailable", "remoteActionFailed", "invalidRemote", "missingRemote", "futureOperationFailure"];
    string[] hostCodes = ["wslUnavailable", "workerArchitectureUnsupported", "workerSetupFailed", "workerHomeInvalid", "workerSetupInvalid", "credentialReadFailed",
        "credentialTooLarge", "credentialWriteFailed", "credentialDeleteFailed", "tokenInvalid", "browserUnavailable"];
    const string diagnostic = "Upstream diagnostic stays outside UI.";
    foreach (var language in Localization.Languages) {
        var locale = new Localization(language);
        foreach (var error in workerCodes.Select(code => (Exception)new WorkerException(code, diagnostic)).Concat(hostCodes.Select(code => new HostFailure(code, diagnostic)))) {
            var wording = FailureText.For(error, locale);
            Expect(!string.IsNullOrWhiteSpace(wording) && !wording.Contains(diagnostic) && !wording.StartsWith("windows.") && !wording.StartsWith("error.") && !wording.Contains('%'));
            // Offline is an intentional shared term in some frozen original language tables.
            if (language != "en" && error is not WorkerException { Code: "unreachable" })
                Expect(wording != FailureText.For(error, new Localization("en")), "failure wording was not translated: " + language + "." + CodeOf(error));
        }
    }
    Expect(FailureText.For(new WorkerException("portConflict", diagnostic), new("ru")).Contains("порт"));
    Expect(FailureText.For(new IOException("Already localized."), new("ru")) == "Already localized.");
    return Task.CompletedTask;
    static string CodeOf(Exception error) => error is WorkerException worker ? worker.Code : ((HostFailure)error).Code;
});
await Check("invalid synthetic token input is rejected before any credential vault operation", async () =>
{
    var account = new RemoteAccountSettings("invalid-input-only", "Owned input check", "github", "https://api.example.invalid", [], []);
    var store = new WindowsTokenStore();
    foreach (var invalid in new[] { "", "synthetic\ninput", new string('a', 2561), new string('я', 1281) })
        await Throws<HostFailure>(() => { store.Write(account, invalid); return Task.CompletedTask; }, error => error.Code == "tokenInvalid");
});
await Check("original plural resources handle Russian forms, French zero and summary wording", () =>
{
    var russian = new Localization("ru");
    Expect(russian.Plural("alert.summary.cantCheck", 1) == "1 аккаунт не проверить");
    Expect(russian.Plural("alert.summary.cantCheck", 2) == "2 аккаунта не проверить");
    Expect(russian.Plural("alert.summary.cantCheck", 11) == "11 аккаунтов не проверить");
    Expect(russian.Plural("alert.summary.cantCheck", 21) == "21 аккаунт не проверить");
    foreach (var language in Localization.Languages)
        foreach (var key in new[] { "attention.summary.waiting", "attention.summary.toFix", "attention.summary.stuck", "alert.summary.reviews", "alert.summary.startFailed" })
            Expect(!new Localization(language).Plural(key, 3).Contains(key));
    Expect(new Localization("en").Plural("alert.summary.reviews", 2) == "2 reviews waiting");
    Expect(!new Localization("fr").Plural("alert.summary.reviews", 0).Contains("%"));
    return Task.CompletedTask;
});
await Check("shared attention survives a failed fetch and malformed error payloads fail closed", async () =>
{
    var request = new RemoteRequest("card", "pullRequests", [new("a", "A", "https://api.github.com", [], [], null)]);
    await using (var worker = new WorkerClient("Test Linux", Fake("attention-error"))) {
        await Throws<WorkerException>(() => worker.CallAsync("remote.snapshot", remote: request), error => error.Code == "credentialsRejected"
            && error.Attention?.Items[0].Action.AccountID == "a" && error.Remote?.Failures[0].Kind == "rejected");
        Expect(worker.IsConnected);
    }
    foreach (var mode in new[] { "attention-url", "attention-scope", "attention-account", "attention-tier", "attention-error-invalid" }) {
        await using var worker = new WorkerClient("Test Linux", Fake(mode));
        await Throws<WorkerException>(() => worker.CallAsync("remote.snapshot", remote: request), error => error.Code == "protocolMismatch");
        Expect(!worker.IsConnected);
    }
});
await Check("shared digest merges card scopes and account errors and excludes informational rows from the badge", () =>
{
    var tracker = new AttentionTracker();
    var review = new AttentionItem("review", "github:review:url", "waiting", "github", "Review", "", 1000, new("open", "https://example.com", "github", "a"), true, false);
    var token = new AttentionItem("rejected", "github:account:a", "needsFixing", "token", "Token", "", 2000, new("accountSettings", Service: "github", AccountID: "a"), true, false);
    tracker.Observe(new AttentionSnapshot("pr", [review, token], []));
    tracker.Observe(new AttentionSnapshot("inbox", [review with { Id = "thread" }, token with { Id = "forbidden" }, token with { Key = "rate:b", Tier = "goodToKnow", Enabled = false }], []));
    Expect(tracker.SignalItems.Length == 3 && tracker.BadgeCount == 2 && tracker.SignalItems[0].Tier == "waiting");
    tracker.Retain(["pr"]); Expect(tracker.BadgeCount == 2 && tracker.SignalItems.Length == 2);
    tracker.Reset(); Expect(tracker.BadgeCount == 0);
    return Task.CompletedTask;
});
await Check("attention menu digest omits empty tiers and preserves each existing signal slice without mutation", () => {
    Expect(AttentionDigest.Sections([]).Length == 0);
    AttentionItem Item(string id,string tier) => new(id,id,tier,"github","Title " + id,"Owned fixture account",1000,new("none"),false,false);
    var rows = new[] { Item("stuck.z","stuck"),Item("waiting.z","waiting"),Item("info","goodToKnow"),Item("waiting.a","waiting"),Item("fix","needsFixing"),Item("stuck.a","stuck") };
    var before = JsonSerializer.Serialize(rows,WorkerProtocol.Json);
    var sections = AttentionDigest.Sections(rows);
    Expect(sections.Select(section => section.Tier).SequenceEqual(new[] { "waiting","needsFixing","stuck","goodToKnow" }));
    Expect(sections[0].Visible.Select(row => row.Id).SequenceEqual(new[] { "waiting.z","waiting.a" })
        && sections[2].Visible.Select(row => row.Id).SequenceEqual(new[] { "stuck.z","stuck.a" }),"Menu digest reordered authoritative worker signals by its own title/age policy.");
    Expect(sections.SelectMany(section => section.Visible).All(row => rows.Any(original => ReferenceEquals(row,original)))
        && JsonSerializer.Serialize(rows,WorkerProtocol.Json) == before,"Menu digest rewrote an action, account detail or original signal array.");
    return Task.CompletedTask;
});
await Check("urgent attention menu sections show a single leftover and fold only five or more rows", () => {
    foreach (var tier in new[] { "waiting","needsFixing","stuck" })
        foreach (var (count,visible,overflow) in new[] { (1,1,0),(3,3,0),(4,4,0),(5,3,2),(8,3,5) }) {
            var rows = Enumerable.Range(1,count).Select(index => new AttentionItem(index.ToString(),index.ToString(),tier,"github","Fixture " + index,"",null,new("none"),false,false)).ToArray();
            var section = AttentionDigest.Sections(rows).Single();
            Expect(section.Visible.Length == visible && section.Overflow.Length == overflow,tier + " menu cap/leftover differs from frozen Mac.");
            Expect(section.Visible.Concat(section.Overflow).SequenceEqual(rows),"Overflow loses or reorders a signal/action.");
            Expect((section.OverflowTitle(new("en")) is null) == (overflow == 0));
        }
    return Task.CompletedTask;
});
await Check("informational attention menu sections cap at two but keep a third row visible", () => {
    foreach (var (count,visible,overflow) in new[] { (1,1,0),(2,2,0),(3,3,0),(4,2,2),(7,2,5) }) {
        var rows = Enumerable.Range(1,count).Select(index => new AttentionItem(index.ToString(),index.ToString(),"goodToKnow","update","Fixture " + index,"",null,new("none"),false,false)).ToArray();
        var section = AttentionDigest.Sections(rows).Single();
        Expect(section.Visible.Length == visible && section.Overflow.Length == overflow,"Informational menu hides one leftover or uses the urgent cap.");
        Expect(section.Visible.Concat(section.Overflow).SequenceEqual(rows));
    }
    return Task.CompletedTask;
});
await Check("attention overflow names use original six-language tier-specific plurals", () => {
    foreach (var language in Localization.Languages) {
        var strings = new Localization(language);
        foreach (var (tier,key) in new[] { ("waiting","waiting"),("needsFixing","toFix"),("stuck","stuck"),("goodToKnow","other") }) {
            var section = new AttentionDigestSection(tier,[],Enumerable.Range(1,21).Select(index => new AttentionItem(index.ToString(),index.ToString(),tier,"github","Fixture","",null,new("none"),false,false)).ToArray());
            var title = section.OverflowTitle(strings)!;
            Expect(title == strings.Plural("attention.more." + key,21) && !title.Contains("attention.more",StringComparison.Ordinal) && title.Contains("21",StringComparison.Ordinal));
        }
    }
    return Task.CompletedTask;
});
await Check("attention age uses exact minute hour day boundaries future clamp and no unknown timestamp label", () => {
    var now = DateTimeOffset.FromUnixTimeSeconds(1790000000);
    var strings = new Localization("en");
    foreach (var (seconds,expected) in new[] { (-3600d,"now"),(0d,"now"),(59.999,"now"),(60d,"1m"),(3599.999,"59m"),(3600d,"1h"),(86399.999,"23h"),(86400d,"1d"),(259200d,"3d") })
        Expect(AttentionDigest.Age(now.ToUnixTimeSeconds()-seconds,now,strings) == expected,"Wrong menu age at " + seconds + " seconds.");
    foreach (var since in new double?[] { null,-1,double.NaN,double.PositiveInfinity,253402300800 }) Expect(AttentionDigest.Age(since,now,strings) is null);
    foreach (var language in Localization.Languages) {
        strings = new(language);
        foreach (var (seconds,key,count) in new[] { (60,"minutes",1),(3600,"hours",1),(86400,"days",1) })
            Expect(AttentionDigest.Age(now.ToUnixTimeSeconds()-seconds,now,strings) == strings.Get("attention.age." + key,count));
        Expect(AttentionDigest.Age(now.ToUnixTimeSeconds()+1,now,strings) == strings.Get("attention.age.now"));
    }
    return Task.CompletedTask;
});
await Check("attention subtitles use Mac late-word truncation at seventy-two complete Unicode characters", () => {
    var shortText = new string('a',72); Expect(AttentionDigest.TrimSubtitle(shortText) == shortText);
    Expect(AttentionDigest.TrimSubtitle(new string('a',73)) == new string('a',71) + "…");
    Expect(AttentionDigest.TrimSubtitle(new string('a',40) + " " + new string('b',40)) == new string('a',40) + "…");
    Expect(AttentionDigest.TrimSubtitle(new string('a',30) + " " + new string('b',42)) == new string('a',30) + " " + new string('b',40) + "…");
    Expect(AttentionDigest.TrimSubtitle(new string('a',36) + " " + new string('b',42)) == new string('a',36) + " " + new string('b',34) + "…","Space exactly at half limit should not use the late-word cut.");
    foreach (var character in new[] { "e\u0301","👩‍👩‍👧‍👦","🇺🇦" }) {
        var text = string.Concat(Enumerable.Repeat(character,73));
        Expect(AttentionDigest.TrimSubtitle(text) == string.Concat(Enumerable.Repeat(character,71)) + "…","Subtitle split a combining/emoji text element.");
        Expect(AttentionDigest.TrimSubtitle(character,1) == character && AttentionDigest.TrimSubtitle(character + character,1) == "…");
    }
    return Task.CompletedTask;
});
await Check("attention last-check clock is local twenty-four-hour HH:mm independent of UI culture", () => {
    var date = new DateTimeOffset(2026,10,2,23,7,19,TimeSpan.FromHours(-8));
    var local = TimeZoneInfo.ConvertTime(date,TimeZoneInfo.Local);
    var expected = local.Hour.ToString("D2",System.Globalization.CultureInfo.InvariantCulture) + ":" + local.Minute.ToString("D2",System.Globalization.CultureInfo.InvariantCulture);
    var prior = System.Globalization.CultureInfo.CurrentCulture;
    try {
        foreach (var culture in new[] { "en-US","ru-RU","ar-SA" }) {
            System.Globalization.CultureInfo.CurrentCulture = System.Globalization.CultureInfo.GetCultureInfo(culture);
            Expect(AttentionDigest.Clock(date) == expected && AttentionDigest.Clock(date).Length == 5,"Last-check clock uses UTC/12-hour/current-culture digits.");
        }
    } finally { System.Globalization.CultureInfo.CurrentCulture = prior; }
    return Task.CompletedTask;
});
await Check("notification history is quiet on first observation, bounded, persisted and respects project switches", () =>
{
    var card = new CardSettings(new("local.a", "Test Linux", "local", "/tmp/a"), "A");
    var settings = new DeckSettings(1, [new("Test Linux", "/home/user/runtime")], [card], Notifications: true);
    DeckAlert Alert(string id, string kind = "wentDown") => new(id, kind, "project", "Project stopped", "", "Safe body", "A", new("showCard", CardID: "local.a"), true);
    var ledger = new NotificationLedger();
    Expect(ledger.Observe(new("local:Test Linux", [], [Alert("baseline")]), settings).Length == 0);
    Expect(ledger.Observe(new("local:Test Linux", [], [Alert("baseline"), Alert("new"), Alert("new")]), settings).Single().Id == "new");
    var restarted = new NotificationLedger(ledger.Seen);
    Expect(restarted.Observe(new("local:Test Linux", [], [Alert("new")]), settings).Length == 0);
    Expect(restarted.Observe(new("local:Test Linux", [], [Alert("new")]), settings).Length == 0);
    Expect(ledger.Observe(new("local:Test Linux", [], [Alert("disabled")]), settings with { Cards = [card with { NotifiesWhenDown = false }] }).Length == 0);
    Expect(ledger.Observe(new("local:Test Linux", [], [Alert("start", "startFailed")]), settings with { Cards = [card with { NotifiesWhenDown = false }] }).Length == 1);
    ledger.Observe(new("local:Test Linux", [], Enumerable.Range(0, 250).Select(index => Alert("id:" + index)).ToArray()), settings);
    Expect(ledger.Seen.Length == 200 && ledger.Seen[0] == "id:50");
    (settings with { SeenAlerts = ledger.Seen }).Validate();
    Expect(ledger.Observe(new("other", [], [Alert("off")]), settings with { Notifications = false }).Length == 0 && !ledger.Seen.Contains("off"));
    ledger.ResetScope("local:Test Linux");
    Expect(ledger.Observe(new("local:Test Linux", [], [Alert("new episode")]), settings).Length == 0);
    return Task.CompletedTask;
});
await Check("remote notification switches remain provider/account scoped and inbox mention attention has no banner", () =>
{
    var account = new RemoteAccountSettings("a", "A", "github", "https://api.github.com", [], [], NotifiesReviewRequests: true, NotifiesBlocked: false, NotifiesFailedRuns: false);
    var settings = DeckSettings.Empty with { Accounts = [account], Notifications = true };
    var alert = new DeckAlert("review", "reviewRequest", "github", "Review", "", "", "", new("open", "https://example.com", "github", "a"), false);
    Expect(NotificationLedger.Enabled(alert, settings));
    Expect(!NotificationLedger.Enabled(alert with { Kind = "blocked" }, settings));
    Expect(!NotificationLedger.Enabled(alert with { Kind = "failedRun" }, settings));
    Expect(!NotificationLedger.Enabled(alert with { Target = alert.Target with { Service = "gitlab" } }, settings));
    Expect(!NotificationLedger.Enabled(alert, settings with { Accounts = [account with { Enabled = false }] }));
    return Task.CompletedTask;
});

await Check("arrangements preserve stable IDs and restore placement without recreating deleted projects or credentials", () =>
{
    var original = new DeckSettings(1, [new("Ubuntu", "/home/user/runtime")],
        [new(new("a", "Ubuntu", "local", "/home/user/a", "npm run dev"), "A", X: 123, Y: 456, Collapsed: true)]);
    var saved = original.SaveArrangement("Work");
    var changed = saved with { Cards = [original.Cards[0] with { X = 900, Collapsed = false }, new(new("new", "Ubuntu", "arc", "/home/user/new"), "New")] };
    var restored = changed.ApplyArrangement("work");
    Expect(restored.Cards[0].X == 123 && restored.Cards[0].Collapsed && restored.Cards[0].Project.StartCommand == "npm run dev");
    Expect(restored.Cards[1].Project.Id == "new");
    Expect((saved with { Cards = [] }).ApplyArrangement("Work").Cards.Length == 0);
    Expect(saved.SaveArrangement("WORK").ArrangementList.Length == 1);
    return Task.CompletedTask;
});

await Check("browser profiles and WSL architecture selection keep explicit argument boundaries", () =>
{
    var chrome = BrowserLaunch.Arguments("chrome", "Profile with spaces", "https://example.com/pull/1?q=a%20b");
    Expect(chrome.Length == 2 && chrome[0] == "--profile-directory=Profile with spaces");
    var firefox = BrowserLaunch.Arguments("firefox", "Work profile", "https://example.com");
    Expect(firefox.Length == 1 && firefox[0] == "https://example.com/", "Firefox must ignore preserved profiles, matching the Mac external-opening policy.");
    try { BrowserLaunch.Arguments("system", null, "file:///C:/Windows/notepad.exe"); throw new Exception("file URI accepted"); } catch (ArgumentException) { }
    Expect(RuntimeInstaller.PackageName("aarch64") == "worker-linux-arm64.tar" && RuntimeInstaller.PackageName("x86_64") == "worker-linux-x64.tar");
    return Task.CompletedTask;
});

await Check("Chromium browser catalog includes Brave Vivaldi and Chromium without losing legacy choices", () => {
    foreach (var id in new[] { "system", "edge", "chrome", "firefox", "brave", "vivaldi", "chromium" })
        Expect(BrowserLaunch.Choices.Contains(id), "Missing supported browser: " + id);
    return Task.CompletedTask;
});

await Check("installed browser discovery honors registered custom locations and ignores unrelated launch commands", () => {
    var custom = @"C:\Users\Fixture\Apps\Vivaldi\vivaldi.exe";
    var chrome = @"C:\Program Files\Google\Chrome\Application\chrome.exe";
    var chromium = @"C:\Program Files\Chromium\Application\chrome.exe";
    var files = new HashSet<string>([custom,chrome,chromium],StringComparer.OrdinalIgnoreCase);
    var browsers = BrowserCatalog.Discover([
        new("vivaldi",'"' + custom + "\" --registered-argument=ignored"),
        new("edge",@"C:\Windows\notepad.exe"), new("firefox","relative/firefox.exe"),
        new("brave",@"C:\Absent\brave.exe"), new("vivaldi",custom)
    ], [@"C:\Program Files"],files.Contains);
    Expect(browsers.Select(browser => browser.ID).SequenceEqual(new[] { "chromium","chrome","vivaldi" }));
    Expect(browsers.Single(browser => browser.ID == "vivaldi").Executable == custom && browsers.All(browser => browser.SupportsProfiles));
    Expect(BrowserCatalog.ExecutableFromCommand('"' + custom + "\" --anything") == custom);
    Expect(BrowserCatalog.ExecutableFromCommand(@"C:\Program Files\Google\Chrome\Application\chrome.exe --anything") == chrome);
    Expect(BrowserCatalog.ExecutableFromCommand("\"unterminated.exe") is null && BrowserCatalog.ExecutableFromCommand("chrome.exe") is null);
    return Task.CompletedTask;
});
await Check("Chromium friendly profiles retain directory identities and natural stable order", () => {
    var profiles = BrowserCatalog.ParseProfiles(Encoding.UTF8.GetBytes("""{"profile":{"info_cache":{"Profile 10":{"name":"Personal"},"Profile 2":{"name":"Work"},"Default":{"name":"Primary"},"Profile 3":{"name":""},"Profile 4":{},"../escape":{"name":"Ignored"},"Profile 5":{"name":"unsafe\nname"}}}}"""));
    Expect(profiles.Select(profile => profile.Directory).SequenceEqual(new[] { "Default","Profile 2","Profile 3","Profile 4","Profile 5","Profile 10" }));
    Expect(profiles[0].Name == "Primary" && profiles[1].Name == "Work" && profiles[2].Name == "Profile 3" && profiles[3].Name == "Profile 4" && profiles[4].Name == "Profile 5");
    foreach (var malformed in new[] { "broken", "[]", "{\"profile\":null}", "{\"profile\":{\"info_cache\":[]}}" })
        Expect(BrowserCatalog.ParseProfiles(Encoding.UTF8.GetBytes(malformed)).Length == 0);
    Expect(BrowserCatalog.ParseProfiles(new byte[BrowserCatalog.MaximumLocalStateBytes + 1]).Length == 0);
    var tooMany = new { profile = new { info_cache = Enumerable.Range(0,257).ToDictionary(index => "Profile " + index,index => new { name="Friendly" }) } };
    Expect(BrowserCatalog.ParseProfiles(JsonSerializer.SerializeToUtf8Bytes(tooMany)).Length == 0);
    return Task.CompletedTask;
});
await Check("browser profile catalog tolerates absent changed and oversized metadata files without writes", async () => {
    var directory = Path.Combine(Path.GetTempPath(),"DevDeck-owned-browser-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(directory);
    try {
        var file = Path.Combine(directory,"Local State");
        Expect(BrowserCatalog.ReadProfiles(file).Length == 0);
        await File.WriteAllTextAsync(file,"""{"profile":{"info_cache":{"Default":{"name":"Fixture friendly name"}}}}""");
        var before = await File.ReadAllBytesAsync(file);
        Expect(BrowserCatalog.ReadProfiles(file).Single() == new BrowserProfile("Default","Fixture friendly name"));
        var after = await File.ReadAllBytesAsync(file);
        Expect(before.SequenceEqual(after),"Reading profiles changed the metadata file.");
        await File.WriteAllTextAsync(file,"{being rewritten"); Expect(BrowserCatalog.ReadProfiles(file).Length == 0);
        using (var large = new FileStream(file,FileMode.Create,FileAccess.Write)) large.SetLength(BrowserCatalog.MaximumLocalStateBytes + 1L);
        Expect(BrowserCatalog.ReadProfiles(file).Length == 0);
    } finally { File.Delete(Path.Combine(directory,"Local State")); Directory.Delete(directory); }
});
await Check("missing chosen browser uses the OS default and retains the original HTTP link", () => {
    var launches = new List<ProcessStartInfo>();
    const string address = "https://example.test/pull/4?q=two%20words";
    var start = BrowserLaunch.Create("brave","Profile 2",address,_ => null);
    Expect(start.UseShellExecute && start.FileName == address && start.ArgumentList.Count == 0);
    BrowserLaunch.Open("brave","Profile 2",address,_ => null,launches.Add);
    Expect(launches.Count == 1 && launches[0].UseShellExecute && launches[0].FileName == address);
    return Task.CompletedTask;
});
await Check("chosen browser opening failure falls back once and exposes a failed default open", () => {
    var launches = new List<ProcessStartInfo>();
    BrowserLaunch.Open("chrome","Work profile","https://example.test/",_ => @"C:\Fixture\chrome.exe",start => {
        launches.Add(start); if (!start.UseShellExecute) throw new System.ComponentModel.Win32Exception(2);
    });
    Expect(launches.Count == 2 && !launches[0].UseShellExecute && launches[0].ArgumentList[0] == "--profile-directory=Work profile");
    Expect(launches[1].UseShellExecute && launches[1].FileName == "https://example.test/");
    var attempts = 0;
    try {
        BrowserLaunch.Open("chrome",null,"https://example.test/",_ => @"C:\Fixture\chrome.exe",_ => { attempts++; throw new System.ComponentModel.Win32Exception(2); });
        throw new Exception("A default-opening failure disappeared.");
    } catch (System.ComponentModel.Win32Exception) { Expect(attempts == 2); }
    return Task.CompletedTask;
});
await Check("successful chosen browser keeps Chromium profile boundaries and Firefox never receives -P", () => {
    foreach (var id in new[] { "edge","chrome","brave","vivaldi","chromium" }) {
        ProcessStartInfo? launched = null;
        BrowserLaunch.Open(id,"Profile with spaces","https://example.test/",_ => @"C:\Fixture\browser.exe",start => launched=start);
        Expect(launched is { UseShellExecute:false } && launched.ArgumentList.SequenceEqual(new[] { "--profile-directory=Profile with spaces","https://example.test/" }));
    }
    var firefox = BrowserLaunch.Create("firefox","Old saved profile","https://example.test/",_ => @"C:\Fixture\firefox.exe");
    Expect(!firefox.UseShellExecute && firefox.ArgumentList.SequenceEqual(new[] { "https://example.test/" }));
    Expect(!BrowserCatalog.SupportsProfiles("firefox") && !BrowserCatalog.SupportsProfiles("system"));
    return Task.CompletedTask;
});
await Check("browser fallback never starts invalid or credential-bearing addresses", () => {
    var attempts = 0;
    foreach (var address in new[] { "file:///C:/Windows/notepad.exe","https://user:password@example.test/","https://example.test/\n" }) {
        try { BrowserLaunch.Open("chrome",null,address,_ => null,_ => attempts++); throw new Exception("Invalid address opened."); }
        catch (ArgumentException) { }
    }
    Expect(attempts == 0);
    return Task.CompletedTask;
});
await Check("expanded browser choices and legacy Firefox profiles survive settings round-trip", () => {
    foreach (var id in new[] { "brave","vivaldi","chromium","firefox" }) {
        var account = new RemoteAccountSettings("account.fixture","Fixture","github","https://api.github.com",[],[],Browser:id,BrowserProfile:"Saved profile");
        var card = new CardSettings(new("arc.project.fixture","","arc","",Arc:new("sandbox.fixture")),"Fixture",Browser:id,BrowserProfile:"Saved profile");
        var settings = DeckSettings.Empty with { Accounts=[account],Cards=[card] };
        settings.Validate();
        var restored = JsonSerializer.Deserialize<DeckSettings>(JsonSerializer.Serialize(settings,WorkerProtocol.Json),WorkerProtocol.Json)!;
        restored.Validate();
        Expect(restored.Cards[0].Browser == id && restored.Cards[0].BrowserProfile == "Saved profile" && restored.AccountList[0].Id == account.Id
            && restored.AccountList[0].Browser == id && restored.AccountList[0].BrowserProfile == "Saved profile");
    }
    return Task.CompletedTask;
});

await Check("attention starts quietly, deduplicates PR/inbox reviews and announces only newly appearing work", () =>
{
    var tracker = new AttentionTracker();
    var review = new RemoteAttention("review:a", "github:review:https://example.com/a", "a", "review", "Synthetic review", "https://example.com/a");
    var snapshot = new RemoteSnapshot("pr", "pullRequests", 1, 0, null, [], [], false, [review]);
    Expect(tracker.Observe(snapshot).Length == 0 && tracker.Items.Length == 1);
    Expect(tracker.Observe(snapshot with { CardID = "inbox", Kind = "inbox" }).Length == 0 && tracker.Items.Length == 1);
    var blocked = review with { Id = "blocked:b", Key = "github:blocked:b", Kind = "blocked" };
    Expect(tracker.Observe(snapshot with { Attention = [review, blocked] }).Length == 1);
    Expect(tracker.Observe(snapshot with { Attention = [review, blocked] }).Length == 0);
    tracker.Retain([]); Expect(tracker.Items.Length == 0);
    return Task.CompletedTask;
});

await Check("Windows update selection cannot pick a Mac zip or a package for another architecture", () =>
{
    using var document = JsonDocument.Parse("""{"tag_name":"v0.12.0","draft":false,"prerelease":false,"html_url":"https://github.com/shumer/DevDeck/releases/tag/v0.12.0","assets":[{"name":"DevDeck-0.12.0.zip","browser_download_url":"https://github.com/shumer/DevDeck/releases/download/v0.12.0/DevDeck-0.12.0.zip"},{"name":"Windows-DevDeck-0.12.0-win-x64.zip","browser_download_url":"https://github.com/shumer/DevDeck/releases/download/v0.12.0/Windows-DevDeck-0.12.0-win-x64.zip"}]}""");
    Expect(WindowsUpdateCheck.Select(document.RootElement, "0.11.0", "win-arm64") is null);
    Expect(WindowsUpdateCheck.Select(document.RootElement, "0.11.0", "win-x64")?.Version == "0.12.0");
    Expect(WindowsUpdateCheck.Select(document.RootElement, "0.12.0", "win-x64") is null);
    Expect(WindowsUpdateCheck.Select(document.RootElement, "0.12", "win-x64") is null);
    using var foreign = JsonDocument.Parse(document.RootElement.GetRawText().Replace("/releases/tag/v0.12.0", "/other/tag/v0.12.0"));
    Expect(WindowsUpdateCheck.Select(foreign.RootElement, "0.11.0", "win-x64") is null);
    return Task.CompletedTask;
});
if (OperatingSystem.IsWindows()) await Check("startup shortcut uses literal spaced settings, is opt-in and refuses an unrelated shortcut", () =>
{
    var directory = Path.Combine(Path.GetTempPath(), "devdeck-startup-" + Guid.NewGuid().ToString("N"));
    var settings = Path.Combine(directory, "settings with spaces.json");
    // The test runner may live on the WSL UNC checkout. This local executable is never launched.
    var executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
    Directory.CreateDirectory(directory);
    var shortcutPath = Path.Combine(directory, StartupShortcut.Name(settings));
    try
    {
        Expect(!StartupShortcut.IsEnabled(directory, settings));
        StartupShortcut.Set(directory, executable, settings, true);
        Expect(StartupShortcut.IsEnabled(directory, settings));
        StartupShortcut.Set(directory, executable, settings, false);
        Expect(!File.Exists(shortcutPath));
        File.WriteAllText(shortcutPath, "unrelated fixture");
        try { StartupShortcut.Set(directory, executable, settings, true); throw new Exception("unrelated shortcut accepted"); }
        catch (IOException) { }
        Expect(File.ReadAllText(shortcutPath) == "unrelated fixture");
    }
    finally
    {
        // Only explicit files under the UUID-owned directory are removed.
        if (File.Exists(shortcutPath)) File.Delete(shortcutPath);
        Directory.Delete(directory);
    }
    return Task.CompletedTask;
});

if (args.Contains("--install-runtime"))
{
    var index = Array.IndexOf(args, "--install-runtime");
    var archive = args[index + 1];
    var path = args[index + 2];
    var store = new SettingsStore(path);
    var settings = store.Load();
    var installed = new List<WorkerSettings>();
    foreach (var distribution in args.Skip(index + 3).TakeWhile(value => !value.StartsWith("--", StringComparison.Ordinal)))
    {
        var runtime = await RuntimeInstaller.InstallAsync(distribution, archive);
        await using var worker = new WorkerClient(distribution, WorkerClient.WslStart(distribution, runtime.RuntimeDirectory));
        await worker.CallAsync("hello");
        installed.Add(runtime);
    }
    store.Save(settings with { Workers = installed.ToArray() });
    Console.WriteLine("Native Windows installed and negotiated " + installed.Count + " WSL runtimes.");
}
if (args.Contains("--live"))
{
    var path = args[Array.IndexOf(args, "--live") + 1];
    var settings = new SettingsStore(path).Load();
    await using var manager = new WorkerManager();
    foreach (var entry in settings.Workers)
        await Check("native Windows -> " + entry.Distribution + " -> Swift hello", async () =>
        {
            var worker = await manager.GetAsync(entry);
            Expect((await worker.CallAsync("hello")).Capabilities?.Contains("project.status") == true);
        });
    foreach (var entry in settings.Workers)
        foreach (var language in Localization.Languages)
            await Check("packaged shared attention language " + entry.Distribution + " / " + language, async () =>
            {
                await using var worker = new WorkerClient(entry.Distribution, WorkerClient.WslStart(entry.Distribution, entry.RuntimeDirectory, language));
                Expect((await worker.CallAsync("hello")).Capabilities?.Contains("attention.shared") == true);
                var remote = new RemoteRequest("owned.missing-token", "pullRequests", [new("owned-missing-token", "Owned offline account", "https://api.github.com", [], [], null)]);
                await Throws<WorkerException>(() => worker.CallAsync("remote.snapshot", remote: remote), error => error.Code == "credentialsRejected"
                    && error.Attention?.Items.Single().Title == new Localization(language).Get("attention.account.rejected.title", "GitHub", "Owned offline account"));
            });
    foreach (var card in settings.Cards.Where(card => card.Enabled))
        await Check("typed status " + card.Title, async () =>
        {
            var worker = await manager.GetAsync(settings.Workers.Single(worker => worker.Distribution == card.Project.Distribution));
            var response = await worker.CallAsync("project.status", card.Project);
            Expect(response.Status?.ProjectID == card.Project.Id);
            Expect(response.Status?.State is "running" or "paused" or "stopped" or "unknown" or "unavailable");
        });
    if (args.Contains("--live-logs")) foreach (var card in settings.Cards.Where(card => card.Enabled))
        await Check("read-only bounded logs " + card.Title, async () => {
            var worker = await manager.GetAsync(settings.Workers.Single(worker => worker.Distribution == card.Project.Distribution));
            var logs = (await worker.CallAsync("project.logs", card.Project, timeout: TimeSpan.FromSeconds(40))).Logs;
            Expect(logs is not null && logs.Lines.Length <= 400 && (logs.FilePath is null || LinuxPath.IsAbsolute(logs.FilePath)));
        });
}
if (args.Contains("--live-preflight"))
{
    var index = Array.IndexOf(args, "--live-preflight");
    var settings = new SettingsStore(args[index + 1]).Load();
    var results = new List<object>();
    await using var manager = new WorkerManager();
    foreach (var card in settings.Cards.Where(card => card.Project.Kind == "arc"))
        await Check("read-only actual Fusion preflight " + card.Title, async () =>
        {
            var worker = await manager.GetAsync(settings.Workers.Single(worker => worker.Distribution == card.Project.Distribution));
            var result = "ready";
            try { await worker.CallAsync("project.preflight", card.Project, timeout: TimeSpan.FromSeconds(90)); }
            catch (WorkerException error) when (error.Code is "portConflict" or "linuxNodeUnavailable" or "fusionUnavailable" or "composeUnavailable" or "preflightUnavailable" or "dockerUnavailable") { result = error.Code; }
            results.Add(new { cardID = card.Project.Id, distribution = card.Project.Distribution, preflight = result });
        });
    await File.WriteAllTextAsync(args[index + 2], JsonSerializer.Serialize(new { readOnly = true, projects = results, releaseQualified = false }, new JsonSerializerOptions { WriteIndented = true }));
}
if (args.Contains("--live-ddev"))
{
    var index = Array.IndexOf(args, "--live-ddev");
    var settings = new SettingsStore(args[index + 1]).Load();
    using var fixtureDocument = JsonDocument.Parse(File.ReadAllBytes(args[index + 2]));
    var fixture = fixtureDocument.RootElement;
    var distribution = fixture.GetProperty("distribution").GetString()!;
    var path = fixture.GetProperty("path").GetString()!;
    var name = fixture.GetProperty("name").GetString()!;
    var xdg = fixture.GetProperty("xdg").GetString()!;
    var port = fixture.GetProperty("port").GetInt32();
    var marker = fixture.GetProperty("marker").GetString()!;
    var root = fixture.GetProperty("root").GetString()!;
    if (!name.StartsWith("devdeck-", StringComparison.Ordinal) || path != root + "/project with spaces" || xdg != root + "/config")
        throw new IOException("The supplied DDEV fixture is not owned.");
    var entry = settings.Workers.Single(worker => worker.Distribution == distribution);
    var start = new ProcessStartInfo("wsl.exe");
    foreach (var argument in new[] { "--distribution", distribution, "--cd", "~", "--exec", "env", "XDG_CONFIG_HOME=" + xdg,
        "CI=true", "CAROOT=" + root + "/certificates", entry.RuntimeDirectory + "/run-worker", "--distribution", distribution }) start.ArgumentList.Add(argument);
    await using var worker = new WorkerClient(distribution, start);
    var project = new ProjectReference("ddev.owned." + name, distribution, "ddev", path);
    await Check("real owned DDEV start/status/HTTP/log/restart/stop through native Windows and Swift worker", async () =>
    {
        var progress = 0;
        var states = new List<string>();
        async Task Act(string action, string expected)
        {
            var response = await worker.CallAsync("project." + action, project, timeout: TimeSpan.FromMinutes(10), onProgress: _ => progress++);
            Expect(response.Status?.State == expected, "Unconfirmed DDEV " + action); states.Add(response.Status!.State);
        }
        try
        {
            await worker.CallAsync("hello");
            await Act("start", "running");
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
            Expect(await http.GetStringAsync("http://127.0.0.1:" + port) == marker, "Windows cannot reach the owned web endpoint");
            Expect((await worker.CallAsync("project.status", project)).Status?.State == "running");
            Expect((await worker.CallAsync("project.logs", project)).Logs is not null);
            await Act("restart", "running");
            Expect(await http.GetStringAsync("http://127.0.0.1:" + port) == marker, "Restart did not restore endpoint");
            await Act("stop", "stopped");
            Expect((await worker.CallAsync("project.status", project)).Status?.State == "stopped");
            var report = new { nativeWindows = true, project = name, states, progressLines = progress,
                windowsHTTP = true, logs = true, sharedRouterOmitted = true, releaseQualified = false };
            await File.WriteAllTextAsync(args[index + 3], JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
        }
        finally
        {
            try { await worker.CallAsync("project.stop", project, timeout: TimeSpan.FromMinutes(3)); } catch (IOException) { }
        }
    });
}
Console.WriteLine($"Windows checks: {passed} passed, {failed} failed.");
return failed == 0 ? 0 : 1;
