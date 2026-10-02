using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using DevDeck.Windows.Core;

// Owned fake-process frames and pure settings only; no provider, vault or browser.
internal static class AttentionChoiceChecks
{
    private const string Distribution = "Test Linux";
    private const string Endpoint = "https://api.example.test";
    private const string URL = "https://example.test/repo/issues/42";
    private const double Now = 1_800_000_000;
    private static RemoteRequest Request => new("owned.inbox", "inbox", [new("account", "Owned account", Endpoint, [], [], "synthetic")]);
    private static InboxReadTarget Target => new("owned.inbox", "account", "42", Endpoint);
    private static AttentionItem Item(bool url = true) => new(InboxReadValidation.Identity("account", "42"), InboxReadValidation.Identity("account", "42"),
        "waiting", "github", "Original personal thread", "Original detail", 1000, url ? new("open", URL, "github", "account") : new("none"), url, false, Target);
    private static RemoteSnapshot Snapshot(bool url = true) => new("owned.inbox", "inbox", 1, 0, null,
        [new("42", "account", "Original personal thread", "example/repo", url ? URL : null, "attention", "mention", false)], [], false);
    private static AttentionSnapshot Signals(AttentionItem? item = null) => new("owned.inbox", [item ?? Item()], []);

    internal static async Task RunRedAsync(Func<string, Func<Task>, Task> check)
    {
        await check("inbox action untrusted API origin is rejected before any attention observer", async () => {
            await using var worker = new WorkerClient(Distribution, Fake("foreign-endpoint"));
            await worker.CallAsync("hello");
            var observed = false;
            try { var response = await worker.CallAsync("remote.snapshot", remote: Request); observed = response.Attention is not null; }
            catch (WorkerException error) when (error.Code == "protocolMismatch") {
                Require(error.Attention is null && error.Remote is null && !worker.IsConnected, "Malformed action escaped in an attached error or remained connected.");
                return;
            }
            throw new IOException("Malformed Inbox read target was accepted; observer would receive attention=" + observed + ".");
        });
    }

    internal static async Task RunAsync(Func<string, Func<Task>, Task> check)
    {
        await RunRedAsync(check);
        await check("attention optional Inbox target retains protocol1 old JSON and constructor semantics", () => {
            const string old = "{\"id\":\"legacy\",\"key\":\"legacy\",\"tier\":\"waiting\",\"mark\":\"github\",\"title\":\"Original\",\"subtitle\":\"Detail\",\"since\":null,\"action\":{\"kind\":\"none\"},\"enabled\":false,\"dismissible\":false}";
            var item = JsonSerializer.Deserialize<AttentionItem>(old, WorkerProtocol.Json)!;
            Require(item.InboxRead is null && !AttentionChoices.Primary(item).Enabled && AttentionChoices.Alternate(item).Kind == "none" && WorkerProtocol.Version == 1,
                "Old JSON acquired a write target or changed protocol.");
            Require(!JsonSerializer.Serialize(item, WorkerProtocol.Json).Contains("inboxRead", StringComparison.Ordinal), "Reserializing old attention added a null target field.");
            var roundtrip = JsonSerializer.Deserialize<AttentionItem>(JsonSerializer.Serialize(Item(), WorkerProtocol.Json), WorkerProtocol.Json)!;
            Require(roundtrip == Item() && roundtrip.InboxRead == Target, "Optional typed target did not roundtrip.");
            var oldSnapshot = JsonSerializer.Deserialize<RemoteSnapshot>(JsonSerializer.Serialize(Snapshot(), WorkerProtocol.Json), WorkerProtocol.Json)!;
            Require(oldSnapshot.Signals is null && !JsonSerializer.Serialize(oldSnapshot, WorkerProtocol.Json).Contains("signals", StringComparison.Ordinal), "Absent nested attention became an invented baseline or null field.");
            return Task.CompletedTask;
        });
        await check("attention selection keeps URLless primary disabled and read precedence without executing", () => {
            var none = Item(false);
            Require(AttentionChoices.Primary(none) is { Kind: "primary", Enabled: false, IsAlternate: false }
                && AttentionChoices.Alternate(none) is { Kind: "read", Enabled: true, IsAlternate: true, InboxRead: { ThreadID: "42" } }
                && AttentionChoices.Select(none, true).Kind == "read", "URLless read inherited disabled primary.");
            Require(AttentionChoices.Alternate(none with { Dismissible = true, Action = new("showCard", CardID: "project") }).Kind == "read", "Dismiss displaced an exact Inbox target.");
            var dismiss = none with { InboxRead = null, Dismissible = true, Action = new("showCard", CardID: "project") };
            Require(AttentionChoices.Alternate(dismiss) is { Kind: "dismiss", Enabled: true } && AttentionChoices.Select(dismiss, false).Action == dismiss.Action,
                "Permitted project dismissal or primary identity was lost.");
            foreach (var unsupported in new[] { none with { InboxRead = null }, none with { InboxRead = null, Action = new("update"), Enabled = true },
                dismiss with { Action = new("open", URL), Enabled = true }, dismiss with { Action = new("showCard", CardID: "") } })
                Require(AttentionChoices.Alternate(unsupported).Kind == "none" && AttentionChoices.Select(unsupported, true) == AttentionChoices.Primary(unsupported), "No-alternate row gained a write action or lost primary.");
            return Task.CompletedTask;
        });
        await check("inbox provenance preserves original personal reasons URLless rows review dedupe and Unicode tuple identity", () => {
            foreach (var reason in new[] { "securityAlert", "reviewRequested", "mention", "teamMention", "assigned" }) {
                var row = Snapshot().Rows[0] with { Detail = reason, NeedsReview = reason == "reviewRequested" };
                var item = reason == "reviewRequested" ? Item() with { Key = "github:review:" + URL } : Item();
                InboxReadValidation.ValidateSnapshot(Signals(item), Request, Snapshot() with { Rows = [row] });
                if (reason == "reviewRequested") {
                    Reject(() => InboxReadValidation.ValidateSnapshot(Signals(Item()), Request, Snapshot() with { Rows = [row] }));
                    Reject(() => InboxReadValidation.ValidateSnapshot(Signals(item with { Key = "github:review:https://wrong.test" }), Request, Snapshot() with { Rows = [row] }));
                    InboxReadValidation.ValidateSnapshot(Signals(Item(false)), Request, Snapshot(false) with { Rows = [row with { Url = null }] });
                }
            }
            InboxReadValidation.ValidateSnapshot(Signals(Item(false)), Request, Snapshot(false));
            Require(InboxReadValidation.Identity("Ж:2", "42") == "inbox:4:Ж:2:2:42"
                && InboxReadValidation.Identity("a:1", "23") != InboxReadValidation.Identity("a", "123"), "Identity counts UTF16 or collapses delimiter tuples.");
            return Task.CompletedTask;
        });
        await check("inbox pure target rejects invalid scope account host thread unread duplicate and nonpersonal rows", () => {
            foreach (var target in new[] { Target with { CardID = "other" }, Target with { AccountID = "other" }, Target with { AccountID = new string('Ж', 65) },
                Target with { ThreadID = "" }, Target with { ThreadID = new string('1', 33) }, Target with { ThreadID = "٤٢" }, Target with { ThreadID = "42/1" },
                Target with { Endpoint = "https://other.test" }, Target with { Endpoint = "http://api.example.test" }, Target with { Endpoint = "https://name:secret@api.example.test" },
                Target with { Endpoint = Endpoint + "?secret=x" }, Target with { Endpoint = Endpoint + "#fragment" }, Target with { Endpoint = Endpoint + "/\n" } })
                Reject(() => InboxReadValidation.Validate(target, Request, Snapshot()));
            foreach (var snapshot in new[] { Snapshot() with { Kind = "pullRequests" }, Snapshot() with { CardID = "other" }, Snapshot() with { Rows = [] },
                Snapshot() with { Rows = [Snapshot().Rows[0] with { IsUnread = false }] }, Snapshot() with { Rows = [Snapshot().Rows[0], Snapshot().Rows[0]] },
                Snapshot() with { Rows = [Snapshot().Rows[0] with { Detail = "comment" }] } }) Reject(() => InboxReadValidation.Validate(Target, Request, snapshot));
            Reject(() => InboxReadValidation.Validate(Target, Request with { Accounts = [Request.Accounts[0], Request.Accounts[0]] }, Snapshot()));
            return Task.CompletedTask;
        });
        await check("inbox pure signal rejects PR identity graft account error actions and altered original policy", () => {
            foreach (var item in new[] { Item() with { Id = "review:42" }, Item() with { Key = "github:review:" + URL }, Item() with { Tier = "stuck" },
                Item() with { Mark = "token" }, Item() with { Dismissible = true }, Item() with { Action = new("accountSettings", Service: "github", AccountID: "account") },
                Item() with { Action = new("open", URL, "github", "other") }, Item() with { Action = new("open", "https://different.test", "github", "account") },
                Item() with { Action = new("none") } })
                Reject(() => InboxReadValidation.ValidateSnapshot(Signals(item), Request, Snapshot()));
            Reject(() => InboxReadValidation.ValidateSnapshot(Signals(Item(false) with { Action = new("none", AccountID: "account") }), Request, Snapshot(false)));
            return Task.CompletedTask;
        });
        await check("inbox current admission ignores layout title and captured enablement while refusing stale owner scope", () => {
            var settings = Settings(); var owner = settings.RemoteCardList[0];
            Require(InboxReadValidation.IsCurrent(settings, owner with { Enabled = false, Title = "Old title", X = 999, Y = 777, Collapsed = true }, Snapshot(), Target), "Metadata retained owner could not act.");
            var changes = new[] { settings with { RemoteCards = [] }, settings with { RemoteCards = [owner with { Enabled = false }] },
                settings with { RemoteCards = [owner with { Distribution = "Other Linux" }] }, settings with { RemoteCards = [owner with { Kind = "pullRequests" }] },
                settings with { RemoteCards = [owner with { AccountIDs = ["other"] }] }, settings with { RemoteCards = [owner with { UseAllAccounts = true }] },
                settings with { Accounts = [settings.AccountList[0] with { Enabled = false }] }, settings with { Accounts = [settings.AccountList[0] with { Provider = "gitlab" }] },
                settings with { Accounts = [settings.AccountList[0] with { Endpoint = "https://other.test" }] }, settings with { Workers = [] } };
            foreach (var changed in changes) Require(!InboxReadValidation.IsCurrent(changed, owner, Snapshot(), Target), "Changed current owner borrowed captured write permission.");
            Require(!InboxReadValidation.IsCurrent(settings, owner, Snapshot() with { Rows = [] }, Target)
                && !InboxReadValidation.IsCurrent(settings, owner, Snapshot() with { Rows = [Snapshot().Rows[0] with { IsUnread = false }] }, Target), "Removed/read current row stayed actionable.");
            return Task.CompletedTask;
        });
        await check("inbox actual IPC accepts exact URL URLless nested-only and same-thread independent-account receipts", async () => {
            foreach (var mode in new[] { "normal", "none", "nested-only", "multi-account" }) {
                await using var worker = new WorkerClient(Distribution, Fake(mode)); await worker.CallAsync("hello");
                var request = mode == "multi-account" ? Request with { Accounts = [Request.Accounts[0], new("other", "Other account", "https://other.test", [], [], "owned-other")] } : Request;
                var response = await worker.CallAsync("remote.snapshot", remote: request);
                var signals = response.Attention ?? response.Remote!.Signals!;
                Require(signals.Items[0].InboxRead == Target && response.Remote!.Signals is not null, "Typed original target or nested source was lost.");
                if (mode == "none") Require(!AttentionChoices.Primary(signals.Items[0]).Enabled && AttentionChoices.Alternate(signals.Items[0]).Enabled, "URLless receipt lost read alternate.");
                if (mode == "multi-account") Require(signals.Items.Length == 2 && signals.Items.Select(item => item.Id).Distinct().Count() == 2
                    && signals.Items[1].InboxRead?.AccountID == "other", "Raw same-thread identity collapsed accounts.");
            }
        });
        await check("inbox actual IPC legacy optional target absence remains usable without invented capabilities", async () => {
            await using var worker = new WorkerClient(Distribution, Fake("legacy")); await worker.CallAsync("hello");
            var response = await worker.CallAsync("remote.snapshot", remote: Request);
            Require(!worker.Capabilities.Contains(InboxReadValidation.Capability) && response.Attention!.Items[0].InboxRead is null
                && AttentionChoices.Primary(response.Attention.Items[0]).Enabled && AttentionChoices.Alternate(response.Attention.Items[0]).Kind == "none", "Legacy producer acquired a fabricated alternate.");
        });
        await check("inbox actual IPC rejects wrong target identifiers endpoint bytes and decimal bounds", async () => {
            foreach (var mode in new[] { "foreign-card", "foreign-account", "foreign-thread", "bad-thread", "long-thread", "unicode-thread", "bad-endpoint", "long-account" })
                await InvalidFrame(mode);
        });
        await check("inbox actual IPC rejects missing read duplicate and nonpersonal owning rows", async () => {
            foreach (var mode in new[] { "missing-row", "read-row", "duplicate-row", "nonpersonal-row", "foreign-row-account" }) await InvalidFrame(mode);
        });
        await check("inbox actual IPC rejects changed policy primary service account URL and review-key graft", async () => {
            foreach (var mode in new[] { "account-error-target", "foreign-primary-account", "foreign-primary-service", "foreign-primary-url", "bad-tier", "bad-mark", "bad-key", "bad-id", "dismissible" }) await InvalidFrame(mode);
        });
        await check("inbox actual IPC refuses targets on PR MR Actions local poweroff checkout and hello routes", async () => {
            foreach (var kind in new[] { "pullRequests", "mergeRequests", "actions" }) await InvalidFrame("normal", request: Request with { Kind = kind });
            foreach (var mode in new[] { "local-target", "checkout-target", "hello-target", "poweroff-target" }) {
                await using var worker = new WorkerClient(Distribution, Fake(mode));
                if (mode == "hello-target") await Fails(() => worker.CallAsync("hello"));
                else {
                    await worker.CallAsync("hello");
                    if (mode == "local-target") await Fails(() => worker.CallAsync("project.status", new("project", Distribution, "local", "/owned/project")));
                    else if (mode == "checkout-target") await Fails(() => worker.CallAsync(CheckoutValidation.Capability,
                        checkout: new(CheckoutCatalog.CardID, "owned-pass", new("project", Distribution, "/owned/project", "Project"))));
                    else {
                        await worker.CallAsync("ddev.poweroff.prepare", powerOff: new("owned-group", [new("project", Distribution, "ddev", "/owned/project")]));
                        await Fails(() => worker.CallAsync("ddev.poweroff.finalize", powerOff: new("owned-group")));
                    }
                }
                Require(!worker.IsConnected, "Forbidden route retained transport.");
            }
        });
        await check("inbox actual IPC rejects silently discardable read-target placements on alerts actions and rows", async () => {
            foreach (var mode in new[] { "alert-target", "action-target", "row-target", "remote-attention-target", "progress-target" }) await InvalidFrame(mode);
        });
        await check("inbox actual IPC validates nested source independently and cross-checks target presence", async () => {
            foreach (var mode in new[] { "top-missing-target", "nested-missing-target", "top-missing-item", "nested-missing-item", "duplicate-signal", "nested-scope", "nested-bad-action" }) await InvalidFrame(mode);
        });
        await check("inbox actual IPC validates errors before exposing attached attention or remote snapshots", async () => {
            await InvalidFrame("malformed-error");
            await using var worker = new WorkerClient(Distribution, Fake("valid-error")); await worker.CallAsync("hello");
            try { await worker.CallAsync("remote.snapshot", remote: Request); }
            catch (WorkerException error) when (error.Code == "remoteUnavailable") {
                Require(error.Attention?.Items[0].InboxRead == Target && error.Remote?.Signals?.Items[0].InboxRead == Target && worker.IsConnected, "Validated partial error lost original attention or broke transport.");
                return;
            }
            throw new IOException("Expected owned partial failure.");
        });
        await check("inbox actual IPC freezes accounts origins and mutable request arrays before a held serialization gate", async () => {
            await using var worker = new WorkerClient(Distribution, Fake("copy")); await worker.CallAsync("hello");
            var gate = (SemaphoreSlim)typeof(WorkerClient).GetField("gate", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(worker)!;
            var account = new RemoteCredential("account", "Owned", Endpoint, ["org"], ["repo"], "synthetic");
            var request = new RemoteRequest("owned.inbox", "inbox", [account], ["42"]);
            await gate.WaitAsync(); Task<WorkerResponse>? pending = null;
            try {
                pending = worker.CallAsync("remote.snapshot", remote: request);
                Require(!pending.IsCompleted, "Owned request did not wait for gate.");
                account.Organizations[0] = "mutated-org"; account.Repositories[0] = "mutated-repo"; request.ThreadIDs![0] = "99";
                typeof(RemoteCredential).GetField("<Endpoint>k__BackingField", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(account, "https://mutated.test");
                request.Accounts[0] = new("other", "Other", "https://other.test", [], [], "owned-other");
            } finally { gate.Release(); }
            var response = await pending!;
            Require(response.Remote!.Rows[0].Title == "org|repo|42|" + Endpoint && response.Attention!.Items[0].InboxRead == Target, "Queued request borrowed changed credential origin or arrays.");
        });
        await check("inbox actual IPC rejects missing malformed and unmapped target fields without banning unrelated extensions", async () => {
            foreach (var mode in new[] { "missing-target-field", "null-target-field" }) await InvalidFrame(mode);
            foreach (var mode in new[] { "numeric-thread", "target-array", "target-extra" }) await InvalidFrame(mode, "invalidResponse");
            await using var worker = new WorkerClient(Distribution, Fake("extension")); await worker.CallAsync("hello");
            Require((await worker.CallAsync("remote.snapshot", remote: Request)).Attention!.Items[0].InboxRead == Target, "An unrelated future field broke protocol1 compatibility.");
        });
        await check("inbox direct checkout validator refuses a target on otherwise valid original informational signal", () => {
            var reference = new CheckoutReference("project", Distribution, "/owned/project", "Project");
            var request = new CheckoutRequest(CheckoutCatalog.CardID, "owned-pass", reference);
            var state = new CheckoutState("develop", 0, 1, 0, true, 1, Now - 4 * 86400, true, true, [new("unpushed", 1)]);
            var signal = new AttentionItem(CheckoutValidation.SignalIdentity(reference, true), CheckoutValidation.SignalIdentity(reference, true), "goodToKnow", "unpushed", "Local commit", "develop", state.OldestLocalCommitAt,
                new("openTerminal", Path: reference.Path, Checkout: new(Distribution, reference.ProjectID, reference.Path)), true, false);
            var result = new CheckoutResult(CheckoutCatalog.CardID, "owned-pass", reference.ProjectID, reference.Path, Now, state, null, [signal]);
            CheckoutValidation.ValidateResponse(result, request);
            Reject(() => CheckoutValidation.ValidateResponse(result with { Signals = [signal with { InboxRead = Target }] }, request));
            return Task.CompletedTask;
        });
    }

    internal static async Task<int> RunFakeAsync(string[] args)
    {
        var mode = args.Last();
        while (await Console.In.ReadLineAsync() is { } line) {
            var request = JsonSerializer.Deserialize<WorkerRequest>(line, WorkerProtocol.Json)!;
            var response = new WorkerResponse(1, request.Id, Distribution, null, null, null, null);
            if (request.Operation == "hello") response = response with { Capabilities = mode == "legacy" ? ["hello"] : ["hello", "remote.snapshot", InboxReadValidation.Capability, CheckoutValidation.Capability, PowerOffValidation.Capability] };
            else if (request.Operation == "remote.snapshot") {
                var context = request.Remote!;
                var account = context.Accounts[0]; var url = mode is "none" or "foreign-endpoint" ? null : URL;
                var target = new InboxReadTarget(context.CardID, account.Id, "42", account.Endpoint);
                var item = Item(url is not null) with { InboxRead = target };
                if (mode == "legacy") item = item with { Id = "inbox:42", Key = "inbox:42", InboxRead = null };
                var rows = new List<RemoteRow> { new("42", account.Id, mode == "copy" ? string.Join("|", account.Organizations[0], account.Repositories[0], context.ThreadIDs![0], account.Endpoint) : "Original personal thread", "example/repo", url, "attention", "mention", false) };
                var items = new List<AttentionItem> { item };
                if (mode == "multi-account") {
                    var other = context.Accounts[1]; rows.Add(rows[0] with { AccountID = other.Id });
                    items.Add(item with { Id = InboxReadValidation.Identity(other.Id, "42"), Key = InboxReadValidation.Identity(other.Id, "42"),
                        Action = item.Action with { AccountID = other.Id }, InboxRead = target with { AccountID = other.Id, Endpoint = other.Endpoint } });
                }
                var signals = new AttentionSnapshot(context.CardID, items.ToArray(), []);
                response = response with {
                    Remote = new(context.CardID, context.Kind, rows.Count, 0, null, rows.ToArray(), [], false, Signals: signals), Attention = signals
                };
                if (mode == "nested-only") response = response with { Attention = null };
                if (mode is "valid-error" or "malformed-error") response = response with { Error = new("remoteUnavailable", "Owned partial failure.") };
            } else if (request.Operation == "project.status") response = response with { Status = new("project", "stopped", null, null, null, null),
                Attention = new("local:" + Distribution, [Item(false) with { Action = new("showCard", CardID: "project") }], []) };
            else if (request.Operation == CheckoutValidation.Capability) response = response with { Checkout = new(CheckoutCatalog.CardID, "owned-pass", "project", "/owned/project", Now,
                new("develop", 0, 0, 0, true, 0, null, false, false, []), null, [Item(false)]) };
            else if (request.Operation == "ddev.poweroff.prepare") response = response with { PowerOff = new("owned-group", "owned-instance", "prepared", 10, "notRun", Statuses: []) };
            else if (request.Operation == "ddev.poweroff.finalize") response = response with { PowerOff = new("owned-group", "owned-instance", "finalized", 0, "notRun", InventoryState: "available",
                Statuses: [new("project", "stopped", null, null, null, null, CheckedAt: 0)]), Attention = new("local:" + Distribution, [Item(false) with { Action = new("showCard", CardID: "project") }], []) };
            if (mode == "hello-target" && request.Operation == "hello") response = response with { Attention = Signals() };
            var node = JsonSerializer.SerializeToNode(response, WorkerProtocol.Json)!;
            if (request.Operation == "remote.snapshot") {
                var top = node["attention"]?["items"]?[0]; var nested = node["remote"]!["signals"]!["items"]![0]!;
                var target = top?["inboxRead"];
                foreach (var value in new[] { top, nested }.OfType<JsonNode>()) {
                    var read = value["inboxRead"];
                    switch (mode) {
                        case "foreign-endpoint": case "malformed-error": read!["endpoint"] = "https://foreign.example.test"; break;
                        case "foreign-card": read!["cardID"] = "other"; break;
                        case "foreign-account": read!["accountID"] = "other"; break;
                        case "foreign-thread": read!["threadID"] = "99"; break;
                        case "bad-thread": read!["threadID"] = "42/1"; break;
                        case "long-thread": read!["threadID"] = new string('1', 33); break;
                        case "unicode-thread": read!["threadID"] = "٤٢"; break;
                        case "bad-endpoint": read!["endpoint"] = "http://api.example.test"; break;
                        case "long-account": read!["accountID"] = new string('Ж', 65); break;
                        case "account-error-target": value["action"] = JsonSerializer.SerializeToNode(new AttentionAction("accountSettings", Service: "github", AccountID: "account"), WorkerProtocol.Json); break;
                        case "foreign-primary-account": value["action"]!["accountID"] = "other"; break;
                        case "foreign-primary-service": value["action"]!["service"] = "gitlab"; break;
                        case "foreign-primary-url": value["action"]!["url"] = "https://different.test"; break;
                        case "bad-tier": value["tier"] = "stuck"; break;
                        case "bad-mark": value["mark"] = "token"; break;
                        case "bad-key": value["key"] = "github:review:" + URL; break;
                        case "bad-id": value["id"] = "review:42"; break;
                        case "dismissible": value["dismissible"] = true; break;
                        case "missing-target-field": read!.AsObject().Remove("endpoint"); break;
                        case "null-target-field": read!["endpoint"] = null; break;
                        case "numeric-thread": read!["threadID"] = 42; break;
                        case "target-array": value["inboxRead"] = new JsonArray(); break;
                        case "target-extra": read!["token"] = "synthetic-extra"; break;
                    }
                }
                var rows = node["remote"]!["rows"]!.AsArray();
                switch (mode) {
                    case "missing-row": rows.Clear(); break;
                    case "read-row": rows[0]!["isUnread"] = false; break;
                    case "duplicate-row": rows.Add(rows[0]!.DeepClone()); break;
                    case "nonpersonal-row": rows[0]!["detail"] = "comment"; break;
                    case "foreign-row-account": rows[0]!["accountID"] = "other"; break;
                    case "top-missing-target": top!.AsObject().Remove("inboxRead"); break;
                    case "nested-missing-target": nested.AsObject().Remove("inboxRead"); break;
                    case "top-missing-item": node["attention"]!["items"]!.AsArray().Clear(); break;
                    case "nested-missing-item": node["remote"]!["signals"]!["items"]!.AsArray().Clear(); break;
                    case "duplicate-signal": node["attention"]!["items"]!.AsArray().Add(top!.DeepClone()); break;
                    case "nested-scope": node["remote"]!["signals"]!["scope"] = "other"; break;
                    case "nested-bad-action": nested["action"]!["url"] = "file:///secret"; break;
                    case "alert-target":
                        var alert = JsonSerializer.SerializeToNode(new DeckAlert("owned", "reviewRequest", "github", "Original", "Detail", "Body", "Subject", new("open", URL, "github", "account"), false), WorkerProtocol.Json)!;
                        alert["inboxRead"] = target!.DeepClone(); node["attention"]!["alerts"]!.AsArray().Add(alert); break;
                    case "action-target": top!["action"]!["inboxRead"] = target!.DeepClone(); break;
                    case "row-target": rows[0]!["inboxRead"] = target!.DeepClone(); break;
                    case "remote-attention-target":
                        var legacyAttention = JsonSerializer.SerializeToNode(new RemoteAttention("owned", "owned", "account", "inbox", "Original", URL), WorkerProtocol.Json)!;
                        legacyAttention["inboxRead"] = target!.DeepClone(); node["remote"]!["attention"] = new JsonArray(legacyAttention); break;
                    case "extension": node["compatibleFutureField"] = true; top!["compatibleFutureField"] = "ignored"; break;
                }
                if (mode == "progress-target") {
                    var progress = node.DeepClone(); progress["event"] = JsonSerializer.SerializeToNode(new WorkerEvent("progress", "Owned progress"), WorkerProtocol.Json);
                    Console.WriteLine(progress.ToJsonString(WorkerProtocol.Json));
                }
            }
            Console.WriteLine(node.ToJsonString(WorkerProtocol.Json));
        }
        return 0;
    }

    private static ProcessStartInfo Fake(string mode) { var start = new ProcessStartInfo(Environment.ProcessPath!); start.ArgumentList.Add("--fake-attention-choice-worker"); start.ArgumentList.Add(mode); return start; }
    private static DeckSettings Settings() => new(1, [new(Distribution, "/owned/runtime")], [], Accounts: [new("account", "Owned", "github", Endpoint, [], [])],
        RemoteCards: [new("owned.inbox", "Inbox", "inbox", Distribution, ["account"])]);
    private static void Reject(Action action) { try { action(); } catch (WorkerException error) when (error.Code == "protocolMismatch") { return; } throw new IOException("Expected pure provenance rejection."); }
    private static async Task Fails(Func<Task> action, string code = "protocolMismatch") { try { await action(); } catch (WorkerException error) when (error.Code == code) {
        Require(error.Attention is null && error.Remote is null, "Untrusted values escaped in error fields."); return; } throw new IOException("Expected transport rejection: " + code); }
    private static async Task InvalidFrame(string mode, string code = "protocolMismatch", RemoteRequest? request = null) {
        await using var worker = new WorkerClient(Distribution, Fake(mode)); await worker.CallAsync("hello");
        await Fails(() => worker.CallAsync("remote.snapshot", remote: request ?? Request), code);
        Require(!worker.IsConnected, "Malformed " + mode + " frame left transport connected.");
    }
    private static void Require(bool value, string message) { if (!value) throw new IOException(message); }
}
