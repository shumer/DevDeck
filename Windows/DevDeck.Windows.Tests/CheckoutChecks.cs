using System.Diagnostics;
using System.Globalization;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using DevDeck.Windows.Core;

// Pure configured values and owned synthetic IPC only. No Git, WSL, provider or user files.
internal static class CheckoutChecks
{
    private const string Distribution = "Test Linux";
    private const double Now = 1_800_000_000;
    private static CheckoutReference Reference => new("hidden", Distribution, "/missing/project 🧩", "Review 2");
    private static CheckoutRequest Request => new(CheckoutCatalog.CardID, "owned-pass", Reference);
    internal static async Task RunAsync(Func<string, Func<Task>, Task> check)
    {
        await check("checkout optional settings preserve legacy omission interval and old arrangement match", () => {
            var old = JsonSerializer.Deserialize<DeckSettings>("{\"schemaVersion\":1,\"workers\":[],\"cards\":[]}", WorkerProtocol.Json)!;
            old.Validate(); old = old.SaveArrangement("Before");
            Require(old.WorkInFlight is null && old.RefreshSeconds == 60 && old.ArrangementMatches("Before"), "Legacy settings acquired a card, changed interval or stopped matching.");
            Require(!JsonSerializer.Serialize(old, WorkerProtocol.Json).Contains("workInFlight", StringComparison.Ordinal), "Saving a legacy deck materialized the preference.");
            Require(DeckSettings.Empty.RefreshSeconds == 120 && new DeckSettings(1, [], []).RefreshSeconds == 60, "New-install and omitted legacy defaults were conflated.");
            return Task.CompletedTask;
        });
        await check("checkout explicit enable placement hide and reload leave source arrays and unrelated settings intact", () => {
            var source = Settings() with { Locked = true, SeenAlerts = ["already-seen"], RefreshSeconds = 300 };
            var enabled = CheckoutCatalog.SetEnabled(source, true, _ => (64, 80)); enabled.Validate();
            Require(enabled.WorkInFlight == new WorkInFlightSettings(true, 64, 80) && ReferenceEquals(enabled.Cards, source.Cards)
                && ReferenceEquals(enabled.Workers, source.Workers) && enabled.SeenAlerts == source.SeenAlerts && enabled.Locked && enabled.RefreshSeconds == 300,
                "Enable rewrote the configuration beyond its preference.");
            var hidden = CheckoutCatalog.SetEnabled(enabled with { WorkInFlight = enabled.WorkInFlight! with { Collapsed = true } }, false);
            var loaded = JsonSerializer.Deserialize<DeckSettings>(JsonSerializer.Serialize(hidden, WorkerProtocol.Json), WorkerProtocol.Json)!;
            loaded.Validate(); Require(loaded.WorkInFlight == new WorkInFlightSettings(false, 64, 80, true), "Hide/reload lost explicit placement or compact state.");
            Require(ReferenceEquals(CheckoutCatalog.SetEnabled(source, false), source), "Default-off disable materialized settings.");
            return Task.CompletedTask;
        });
        await check("checkout fixed ID conflict preserves legacy loads and rejects only explicit activation", () => {
            var legacy = Settings() with { Cards = [Card(CheckoutCatalog.CardID, "arc", "/legacy")] };
            legacy.Validate(); Require(CheckoutCatalog.HasIdentityConflict(legacy), "A project-owned permanent ID collision was missed.");
            Invalid(() => CheckoutCatalog.SetEnabled(legacy, true));
            foreach (var placement in new[] { new WorkInFlightSettings(X: double.NaN), new WorkInFlightSettings(Y: double.PositiveInfinity) })
                Invalid(() => (Settings() with { WorkInFlight = placement }).Validate());
            Invalid(() => (legacy with { WorkInFlight = new() }).Validate());
            Require(legacy.WorkInFlight is null && legacy.Cards.Single().Project.Id == CheckoutCatalog.CardID, "Collision handling renamed or rewrote an old card.");
            return Task.CompletedTask;
        });
        await check("checkout arrangements include only explicit preferences and apply only existing owners", () => {
            var legacy = Settings().SaveArrangement("Old");
            var added = CheckoutCatalog.SetEnabled(legacy, true) with { WorkInFlight = new(true, 90, 120, true) };
            Require(!added.ArrangementMatches("Old") && added.ApplyArrangement("Old").WorkInFlight == added.WorkInFlight, "An old arrangement reset a new aggregate owner.");
            var saved = added.SaveArrangement("With WIF");
            Require(saved.ArrangementList.Last().Cards.Last() == new CardPlacement(CheckoutCatalog.CardID, 90, 120, true, true), "Explicit aggregate placement was absent.");
            var changed = saved with { WorkInFlight = new(false, 300, 400, false) };
            Require(changed.ApplyArrangement("With WIF").WorkInFlight == saved.WorkInFlight && changed.ApplyArrangement("With WIF").ArrangementMatches("With WIF"), "Apply lost aggregate geometry/flags.");
            var removed = saved with { WorkInFlight = null };
            Require(removed.ApplyArrangement("With WIF").WorkInFlight is null, "An arrangement recreated a missing preference.");
            Require((saved with { WorkInFlight = saved.WorkInFlight! with { Enabled = false } }).SaveArrangement("Hidden").ArrangementList.Last().Cards.Any(card => card.Id == CheckoutCatalog.CardID && !card.Enabled), "Disabled explicit owner was omitted.");
            return Task.CompletedTask;
        });
        await check("checkout authoritative selection uses saved kind order hidden folders lexical tuples and owned references", () => {
            var source = Settings() with { Cards = [Card("plain", "local", "/same/./path/"), Card("ddev-10", "ddev", "/ddev"),
                Card("arc-first", "arc", "/same//path", false), Card("arc-alias", "arc", "/same/path"), Card("arc-second", "arc", "/second"),
                Card("hosted", "arc", ""), Card("debian", "local", "/same/path", distribution: "Other Linux")] };
            var refs = CheckoutCatalog.Select(source);
            Require(refs.Select(value => value.ProjectID).SequenceEqual(new[] { "arc-first", "arc-second", "ddev-10", "debian" })
                && refs[0].Path == "/same/path", "Selection used title/visibility order or collapsed independent distribution paths.");
            refs[0] = refs[0] with { ProjectID = "mutated" };
            Require(CheckoutCatalog.Select(source)[0].ProjectID == "arc-first" && source.Cards[0].Project.Id == "plain", "Caller mutation changed the authoritative configuration.");
            Require(CheckoutCatalog.Standardize("/./") == "/" && CheckoutCatalog.Standardize("/tmp/space 🧩///.") == "/tmp/space 🧩", "Lexical standardization changed Unicode or root.");
            return Task.CompletedTask;
        });
        await check("checkout selection fails closed on missing runtime unsafe paths and excess without silently truncating", () => {
            foreach (var path in new[] { "relative", "//host/path", "/tmp/../secret", "/tmp\\secret", "/tmp/\n" })
                Invalid(() => CheckoutCatalog.Select(Settings() with { Cards = [Card("bad", "local", path)] }));
            Invalid(() => CheckoutCatalog.Select(Settings() with { Workers = [] }));
            var bounded = Settings() with { Cards = Enumerable.Range(0, 1024).Select(index => Card("id-" + index, "local", "/tmp/" + index)).ToArray() };
            Require(CheckoutCatalog.Select(bounded).Length == 1024, "The supported bound was rejected.");
            Invalid(() => CheckoutCatalog.Select(bounded with { Cards = bounded.Cards.Append(Card("extra", "local", "/tmp/extra")).ToArray() }));
            return Task.CompletedTask;
        });
        await check("checkout terminal target requires exact current tuple while hidden source remains eligible", () => {
            var settings = CheckoutCatalog.SetEnabled(Settings(), true);
            var target = new CheckoutTarget(Distribution, "hidden", Reference.Path);
            Require(CheckoutCatalog.CurrentTarget(settings, target), "Hidden configured checkout could not be reached.");
            foreach (var foreign in new[] { target with { Distribution = "Other Linux" }, target with { ProjectID = "other" }, target with { Path = "/changed" }, target with { Path = "//bad" } })
                Require(!CheckoutCatalog.CurrentTarget(settings, foreign), "A foreign target borrowed another checkout.");
            Require(!CheckoutCatalog.CurrentTarget(settings with { WorkInFlight = new(false) }, target)
                && !CheckoutCatalog.CurrentTarget(settings with { Cards = [] }, target)
                && !CheckoutCatalog.CurrentTarget(settings with { Cards = [Card("hidden", "local", "/moved")] }, target), "Disabled/removed/moved checkout stayed actionable.");
            return Task.CompletedTask;
        });
        await check("checkout catalog order inserts aggregate after resolved roles and before saved custom extras", () => {
            var remotes = new[] { Remote("custom-10", "actions"), Remote("legacy-pulls", "pullRequests"), Remote("mr", "mergeRequests"),
                Remote("inbox", "inbox"), Remote("github.pullRequests", "pullRequests"), Remote("custom-2", "actions") };
            var settings = Settings() with { RemoteCards = remotes, WorkInFlight = new(false) };
            Require(CardOrdering.IDs(settings).SequenceEqual(new[] { "legacy-pulls", "inbox", "custom-10", "mr", CheckoutCatalog.CardID, "custom-2", "github.pullRequests", "hidden" }), "Aggregate displaced a resolved alias or followed custom extras.");
            Require(CardOrdering.IDs(settings with { WorkInFlight = null }).SequenceEqual(new[] { "legacy-pulls", "inbox", "custom-10", "mr", "custom-2", "github.pullRequests", "hidden" })
                && settings.RemoteCardList.SequenceEqual(remotes), "Null preference changed old ordering or wrote sorted arrays.");
            return Task.CompletedTask;
        });
        await check("checkout global projection preserves urgency dirty natural multilingual stable ties and counts", () => {
            var entries = new[] { Entry("clean", "Clean", State()), Entry("dirty", "Dirty", State(dirty: 40)),
                Entry("ten", "Review 10", State(ahead: 3)), Entry("two", "Review 2", State(ahead: 1)),
                Entry("unicode-ten", "Проект 10", State(ahead: 1)), Entry("unicode-two", "Проект 2", State(ahead: 1)),
                Entry("case-first", "same", State(ahead: 1)), Entry("case-last", "SAME", State(ahead: 1)),
                Entry("most-dirty", "Z", State(dirty: 2, upstream: false)), Entry("failed", "Failed", null, new("status", "missingFolder")) };
            var projected = CheckoutPresentation.Project(entries, CultureInfo.GetCultureInfo("en-US"));
            Require(projected.Rows.Select(row => row.Reference.ProjectID).SequenceEqual(new[] { "most-dirty", "two", "ten", "case-first", "case-last", "unicode-two", "unicode-ten", "dirty" }), "Global order used route concatenation, lexical numbers, ID ties or wrong urgency.");
            Require(projected.Watched == 9 && projected.InFlight == 8 && projected.Unpushed == 6 && projected.Failures == 1 && projected.Urgent,
                "Watched, checkout count and commit count were conflated.");
            var snapshot = new WorkInFlightSnapshot(entries, 10, Now);
            Require(snapshot.SuccessfulCount == 9 && snapshot.FailureCount == 1 && snapshot.Partial && snapshot.Rows.Length == 8, "Snapshot discarded clean/failure facts.");
            return Task.CompletedTask;
        });
        await check("checkout card rows cap three twelve and retain complete clean log-failure and stale facts", () => {
            var entries = Enumerable.Range(0, 13).Select(index => Entry("row-" + index, "Row " + index, State(dirty: 1))).ToArray();
            var projected = CheckoutPresentation.Project(entries);
            Require(CheckoutPresentation.CardRows(projected, false).Length == 3 && CheckoutPresentation.CardRows(projected, true).Length == 12 && projected.Rows.Length == 13, "Expansion altered underlying rows or original caps.");
            var logFailure = Entry("log", "Log", State(upstream: false), new("localCommits", "timedOut"));
            CheckoutValidation.ValidateResponse(logFailure.Result, new(CheckoutCatalog.CardID, "owned-pass", logFailure.Reference));
            var mixed = new WorkInFlightSnapshot([logFailure, Entry("clean", "Clean", State())], 2, Now);
            Require(mixed.SuccessfulCount == 2 && mixed.FailureCount == 1 && mixed.Partial && mixed.InFlightCount == 1, "Valid status was lost on local-commits failure.");
            Require(new WorkInFlightSnapshot([], 0, Now).Partial == false && new WorkInFlightSnapshot([], 1, Now, Stale: true).Partial, "Empty/stale completion was dishonest.");
            return Task.CompletedTask;
        });
        await check("checkout structured words adapt all six languages without altering original signal identity or policy", () => {
            foreach (var language in Localization.Languages) {
                var words = new Localization(language); var state = State(dirty: 2, ahead: 3, commits: 4, oldest: Now - 4 * 86400);
                var signal = Signal(Reference, state);
                Require(!CheckoutWords.Summary(state, words).Contains("windows.wif", StringComparison.Ordinal)
                    && !CheckoutWords.Footer(CheckoutPresentation.Project([Entry("x", "X", state)]), words).Contains("card.wif", StringComparison.Ordinal), "WIF display leaked a missing translation.");
                var adapted = CheckoutWords.Signal(signal, Reference, state, words, Now);
                Require(adapted.Title == words.Get("windows.wif.localCommitsTitle", words.Plural("attention.local.commits", 4), Reference.Title)
                    && (adapted with { Title = signal.Title, Subtitle = signal.Subtitle }) == signal, "Platform wording modified worker-produced attention facts.");
                foreach (var count in new[] { 1, 2, 5 }) {
                    var aged = State(upstream: false, commits: count, oldest: Now - count * 86400);
                    var native = CheckoutWords.Signal(Signal(Reference, aged), Reference, aged, words, Now);
                    Require(native.Subtitle == words.Get("attention.local.noRemote.subtitle", "develop", words.Plural("attention.local.commits", count), words.Plural("attention.local.days", count))
                        && !native.Subtitle.Contains("attention.local", StringComparison.Ordinal), "Native commit/day plurals borrowed the worker fallback grammar.");
                }
                Require(CheckoutWords.Collapsed(new([], 0, 0, 0, 2, false), words) == words.Get("windows.wif.readFailed", 2)
                    && CheckoutWords.Collapsed(new([], 2, 0, 0, 1, false), words) == words.Get("windows.wif.partial", 2, 1), "Failures claimed all-clean.");
            }
            return Task.CompletedTask;
        });
        await check("checkout shared refresh policy matches original hint backoff rate reset and source roles", () => {
            Require(SharedRefreshPolicy.NextDelay(120, 0) == 120 && SharedRefreshPolicy.NextDelay(10, 0) == 60
                && SharedRefreshPolicy.NextDelay(120, 0, 300) == 300 && SharedRefreshPolicy.NextDelay(120, 1, 300) == 600
                && SharedRefreshPolicy.NextDelay(120, 8) == 900 && SharedRefreshPolicy.NextDelay(600, 99) == 900,
                "Base/hint/backoff differs from original policy.");
            Require(SharedRefreshPolicy.AfterError(120, 2, "rateLimited", Now + 100, Now) == 105
                && SharedRefreshPolicy.AfterError(120, 2, "rateLimited", Now - 4, Now) == 60
                && SharedRefreshPolicy.AfterError(120, 2, "rateLimited", Now - 5, Now) == 480
                && SharedRefreshPolicy.AfterError(120, 2, "unreachable", Now + 100, Now) == 480
                && SharedRefreshPolicy.AfterError(120, 2, "rateLimited", Now + 2000, Now) == 900, "First rate-reset+5 did not control failed-pass delay.");
            var source = Settings() with { RemoteCards = [Remote("actions", "actions"), Remote("mr", "mergeRequests"), Remote("legacy", "pullRequests"), Remote("extra", "pullRequests"), Remote("inbox", "inbox")] };
            Require(SharedRefreshPolicy.SourceOrder(source).Select(card => card.Id).SequenceEqual(new[] { "legacy", "inbox", "mr", "actions", "extra" })
                && SharedRefreshPolicy.SourceOrder(DeckSettings.Empty).Length == 0, "Shared cadence used catalog order or dropped legacy extras.");
            return Task.CompletedTask;
        });
        await check("checkout request admission enforces UTF8 bounds exact distribution and isolated envelope", () => {
            CheckoutValidation.ValidateRequest(Request, CheckoutValidation.Capability, Distribution);
            CheckoutValidation.ValidateRequest(Request with { PassToken = new string('Ж', 64), Reference = Reference with { ProjectID = new string('Ж', 64), Title = new string('Ж', 256), Path = "/" + new string('x', 4095) } }, CheckoutValidation.Capability, Distribution);
            foreach (var request in new[] { Request with { CardID = "foreign" }, Request with { PassToken = "" }, Request with { PassToken = new string('Ж', 65) },
                Request with { Reference = Reference with { Distribution = "Other Linux" } }, Request with { Reference = Reference with { Title = "bad\n" } },
                Request with { Reference = Reference with { Path = "/tmp/../secret" } }, Request with { Reference = null! } })
                Reject(() => CheckoutValidation.ValidateRequest(request, CheckoutValidation.Capability, Distribution), "invalidRequest");
            Reject(() => CheckoutValidation.ValidateRequest(Request, "project.status", Distribution), "invalidRequest");
            Reject(() => CheckoutValidation.ValidateRequest(Request, CheckoutValidation.Capability, Distribution, project: new("x", Distribution, "local", "/x")), "invalidRequest");
            Reject(() => CheckoutValidation.ValidateRequest(Request, CheckoutValidation.Capability, Distribution, remote: new("x", "inbox", [])), "invalidRequest");
            Reject(() => CheckoutValidation.ValidateRequest(Request, CheckoutValidation.Capability, Distribution, refreshCycle: "cycle"), "invalidRequest");
            Reject(() => CheckoutValidation.ValidateRequest(Request, CheckoutValidation.Capability, Distribution, activeProjectIDs: []), "invalidRequest");
            Reject(() => CheckoutValidation.ValidateRequest(Request, CheckoutValidation.Capability, Distribution, powerOff: new("group")), "invalidRequest");
            return Task.CompletedTask;
        });
        await check("checkout replies require matching identity finite clocks exact flags facts and typed failures", () => {
            var valid = Result(State(dirty: 1, ahead: 2, behind: 3)); CheckoutValidation.ValidateResponse(valid, Request);
            foreach (var result in new[] { valid with { CardID = "foreign" }, valid with { PassToken = "old" }, valid with { ProjectID = "other" }, valid with { Path = "/other" },
                valid with { CheckedAt = -1 }, valid with { CheckedAt = double.NaN }, valid with { CheckedAt = 253402300800 }, valid with { State = null }, valid with { Signals = null! },
                valid with { Failure = new("status", "statusFailed") }, valid with { Failure = new("other", "timedOut") }, valid with { Failure = new("localCommits", "secret diagnostic") } })
                Reject(() => CheckoutValidation.ValidateResponse(result, Request), "protocolMismatch");
            foreach (var state in new[] { valid.State! with { DirtyFiles = -1 }, valid.State! with { Branch = "bad\t" }, valid.State! with { InFlight = false }, valid.State! with { Urgent = false },
                valid.State! with { SummaryFacts = [new("unpushed", 2), new("changed", 1)] }, valid.State! with { SummaryFacts = [new("changed"), new("unpushed", 2)] },
                valid.State! with { LocalCommits = 1 }, valid.State! with { OldestLocalCommitAt = 0 }, valid.State! with { SummaryFacts = null! },
                valid.State! with { LocalCommits = 1, OldestLocalCommitAt = double.PositiveInfinity } })
                Reject(() => CheckoutValidation.ValidateResponse(valid with { State = state }, Request), "protocolMismatch");
            CheckoutValidation.ValidateResponse(Result(null, new("status", "missingFolder")), Request);
            CheckoutValidation.ValidateResponse(Result(State(upstream: false), new("localCommits", "localCommitsFailed")), Request);
            return Task.CompletedTask;
        });
        await check("checkout informational signal preserves age boundary collision-free tuple and exact terminal action", () => {
            var state = State(ahead: 1, commits: 2, oldest: Now - 3 * 86400); var signal = Signal(Reference, state);
            var valid = Result(state) with { Signals = [signal] }; CheckoutValidation.ValidateResponse(valid, Request);
            foreach (var item in new[] { signal with { Key = "foreign" }, signal with { Tier = "waiting" }, signal with { Mark = "github" }, signal with { Dismissible = true },
                signal with { Enabled = false }, signal with { Since = 0 }, signal with { Action = signal.Action with { Checkout = signal.Action.Checkout! with { Distribution = "Other Linux" } } },
                signal with { Action = signal.Action with { Path = "/other" } }, signal with { Action = signal.Action with { Url = "https://example.invalid" } } })
                Reject(() => CheckoutValidation.ValidateResponse(valid with { Signals = [item] }, Request), "protocolMismatch");
            Reject(() => CheckoutValidation.ValidateResponse(valid with { Signals = [signal, signal] }, Request), "protocolMismatch");
            Reject(() => CheckoutValidation.ValidateResponse(valid with { CheckedAt = Now - 1 }, Request), "protocolMismatch");
            Reject(() => CheckoutValidation.ValidateResponse(valid with { Failure = new("localCommits", "timedOut") }, Request), "protocolMismatch");
            var first = new CheckoutReference("b:c", "a", "/x", "X"); var second = new CheckoutReference("c", "a:b", "/x", "X");
            Require(CheckoutValidation.SignalIdentity(first, true) != CheckoutValidation.SignalIdentity(second, true)
                && CheckoutValidation.SignalIdentity(new("Ж", "🧩", "/x", "X"), false) == "checkout:4:🧩:2:Ж:noremote", "Tuple delimiter or UTF8 length collision.");
            return Task.CompletedTask;
        });
        await check("checkout attention visibility owns aggregate scope independently of hidden project cards and legacy collisions", () => {
            var settings = CheckoutCatalog.SetEnabled(Settings(), true); var state = State(ahead: 1, commits: 1, oldest: Now - 4 * 86400);
            var item = Signal(Reference, state); var scope = new AttentionSnapshot(CheckoutCatalog.CardID, [item], []);
            Require(AttentionVisibility.Filter(scope, settings)!.Items.Single() == item, "Hidden source project suppressed aggregate attention.");
            Require(AttentionVisibility.Filter(scope, settings with { WorkInFlight = new(false) }) is null
                && AttentionVisibility.Filter(scope, settings with { Cards = [] })!.Items.Length == 0, "Hidden aggregate or removed checkout reinserted attention.");
            var legacy = Settings() with { RemoteCards = [Remote(CheckoutCatalog.CardID, "pullRequests")], Accounts = [new("account", "Account", "github", "https://github.com", [], [])] };
            var old = new AttentionSnapshot(CheckoutCatalog.CardID, [], []);
            Require(AttentionVisibility.Filter(old, legacy) == old, "New reserved scope made an old remote card unloadable/invisible.");
            return Task.CompletedTask;
        });
        await check("checkout actual IPC capability rejection preserves the legacy session and pure admission precedes its gate", async () => {
            await using var worker = new WorkerClient(Distribution, Fake("legacy")); await worker.CallAsync("hello");
            await Fails(() => worker.CallAsync(CheckoutValidation.Capability, checkout: Request), "protocolMismatch");
            Require(worker.IsConnected, "Missing optional capability killed a reusable worker.");
            await worker.CallAsync("hello");
            var gate = (SemaphoreSlim)typeof(WorkerClient).GetField("gate", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(worker)!;
            await gate.WaitAsync();
            try {
                var rejected = worker.CallAsync(CheckoutValidation.Capability, checkout: Request, activeProjectIDs: []);
                Require(rejected.IsCompleted, "Invalid context waited on an unrelated request gate."); await Fails(() => rejected, "invalidRequest");
            } finally { gate.Release(); }
        });
        await check("checkout actual IPC copies its immutable reference before waiting for serialization", async () => {
            await using var worker = new WorkerClient(Distribution, Fake("normal")); await worker.CallAsync("hello");
            var gate = (SemaphoreSlim)typeof(WorkerClient).GetField("gate", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(worker)!;
            await gate.WaitAsync(); var context = Request; var capturedPath = context.Reference.Path;
            var pending = worker.CallAsync(CheckoutValidation.Capability, checkout: context);
            Require(!pending.IsCompleted, "Owned request did not wait for serialization.");
            // Records expose no public mutation. Deliberately alter the original private backing
            // field to verify the stronger transport ownership guarantee under a held gate.
            typeof(CheckoutReference).GetField("<Path>k__BackingField", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(context.Reference, "/mutated");
            gate.Release(); var response = await pending;
            Require(response.Checkout!.Path == capturedPath, "Queued serialization borrowed the original DTO instance.");
        });
        await check("checkout actual IPC accepts complete dirty clean no-upstream and partial read receipts without aggregate attention", async () => {
            foreach (var mode in new[] { "normal", "clean", "no-upstream", "log-failed", "status-failed" }) {
                await using var worker = new WorkerClient(Distribution, Fake(mode)); await worker.CallAsync("hello");
                var response = await worker.CallAsync(CheckoutValidation.Capability, checkout: Request);
                Require(response.Checkout is not null && response.Attention is null, "A per-checkout reply overwrote aggregate attention.");
                if (mode == "no-upstream") Require(response.Checkout!.Signals.Single().Mark == "noRemote", "Original no-upstream informational signal was lost.");
                if (mode == "log-failed") Require(response.Checkout!.State is not null && response.Checkout.Failure?.Stage == "localCommits", "Partial status was discarded.");
                if (mode == "status-failed") Require(response.Checkout!.State is null && response.Checkout.Failure?.Stage == "status", "Primary failure fabricated a clean state.");
            }
        });
        await check("checkout untrusted IPC rejects foreign identities malformed states targets and unrelated envelopes before consumers", async () => {
            foreach (var mode in new[] { "foreign-pass", "foreign-id", "foreign-path", "bad-count", "bad-date", "bad-facts", "bad-flags", "foreign-target", "extra-status", "top-attention", "missing-result", "progress" }) {
                await using var worker = new WorkerClient(Distribution, Fake(mode)); await worker.CallAsync("hello");
                await Fails(() => worker.CallAsync(CheckoutValidation.Capability, checkout: Request), "protocolMismatch");
                Require(!worker.IsConnected, "Untrusted " + mode + " reply left its transport connected.");
            }
        });
        await check("checkout wire requires explicit counters flags dates facts signals and rejects targets on old attention routes", async () => {
            foreach (var mode in new[] { "omit-date", "omit-signals", "omit-counter", "omit-upstream", "omit-flag", "omit-facts" }) {
                await using var worker = new WorkerClient(Distribution, Fake(mode)); await worker.CallAsync("hello");
                await Fails(() => worker.CallAsync(CheckoutValidation.Capability, checkout: Request), "invalidResponse");
                Require(!worker.IsConnected, "Missing required values defaulted to clean.");
            }
            foreach (var mode in new[] { "unexpected-checkout", "legacy-target", "remote-target" }) {
                await using var worker = new WorkerClient(Distribution, Fake(mode));
                if (mode == "unexpected-checkout") await Fails(() => worker.CallAsync("hello"), "protocolMismatch");
                else {
                    await worker.CallAsync("hello");
                    await Fails(() => mode == "legacy-target" ? worker.CallAsync("project.status", new("hidden", Distribution, "local", Reference.Path))
                        : worker.CallAsync("remote.snapshot", remote: new("legacy-remote", "pullRequests", [])), "protocolMismatch");
                }
                Require(!worker.IsConnected, "An old route introduced a new terminal target.");
            }
        });
    }

    internal static async Task<int> RunFakeAsync(string[] args)
    {
        var mode = args.Last();
        while (await Console.In.ReadLineAsync() is { } line) {
            var request = JsonSerializer.Deserialize<WorkerRequest>(line, WorkerProtocol.Json)!;
            var response = new WorkerResponse(1, request.Id, Distribution, null, null, null, null);
            if (request.Operation == "hello") response = response with { Capabilities = mode == "legacy" ? ["hello"] : ["hello", CheckoutValidation.Capability] };
            else if (request.Operation == CheckoutValidation.Capability) {
                var reference = request.Checkout!.Reference;
                var state = mode switch { "clean" => State(), "no-upstream" => State(upstream: false, commits: 2, oldest: Now - 4 * 86400),
                    "log-failed" => State(upstream: false), "status-failed" => null, _ => State(ahead: 2, commits: 3, oldest: Now - 4 * 86400) };
                var failure = mode == "log-failed" ? new CheckoutFailure("localCommits", "timedOut") : mode == "status-failed" ? new("status", "missingFolder") : null;
                var result = new CheckoutResult(request.Checkout.CardID, request.Checkout.PassToken, reference.ProjectID, reference.Path, Now, state, failure,
                    state?.LocalCommits > 0 ? [Signal(reference, state)] : []);
                response = response with { Checkout = result };
                response = mode switch {
                    "foreign-pass" => response with { Checkout = result with { PassToken = "foreign" } },
                    "foreign-id" => response with { Checkout = result with { ProjectID = "foreign" } },
                    "foreign-path" => response with { Checkout = result with { Path = "/foreign" } },
                    "bad-count" => response with { Checkout = result with { State = state! with { Ahead = -1 } } },
                    "bad-date" => response with { Checkout = result with { CheckedAt = -1 } },
                    "bad-facts" => response with { Checkout = result with { State = state! with { SummaryFacts = [new("changed", 999)] } } },
                    "bad-flags" => response with { Checkout = result with { State = state! with { InFlight = false } } },
                    "foreign-target" => response with { Checkout = result with { Signals = [result.Signals[0] with { Action = result.Signals[0].Action with { Checkout = new("Other Linux", reference.ProjectID, reference.Path) } }] } },
                    "extra-status" => response with { Status = new(reference.ProjectID, "stopped", null, null, null, null) },
                    "top-attention" => response with { Attention = new(CheckoutCatalog.CardID, result.Signals, []) },
                    "missing-result" => response with { Checkout = null },
                    "progress" => response with { Event = new("progress", "Unexpected progress") }, _ => response
                };
            } else if (request.Operation == "project.status") response = response with { Status = new("hidden", "stopped", null, null, null, null),
                Attention = new("local:" + Distribution, [Signal(Reference, State(ahead: 1, commits: 1, oldest: Now - 4 * 86400))], []) };
            else if (request.Operation == "remote.snapshot") response = response with { Remote = new("legacy-remote", "pullRequests", 0, 0, null, [], [], false),
                Attention = new("legacy-remote", [Signal(Reference, State(ahead: 1, commits: 1, oldest: Now - 4 * 86400))], []) };
            if (mode == "unexpected-checkout" && request.Operation == "hello") response = response with { Checkout = Result(State()) };
            var node = JsonSerializer.SerializeToNode(response, WorkerProtocol.Json)!;
            if (request.Operation == CheckoutValidation.Capability && mode.StartsWith("omit-", StringComparison.Ordinal)) {
                var checkout = node["checkout"]!.AsObject();
                switch (mode) {
                    case "omit-date": checkout.Remove("checkedAt"); break;
                    case "omit-signals": checkout.Remove("signals"); break;
                    case "omit-counter": checkout["state"]!.AsObject().Remove("dirtyFiles"); break;
                    case "omit-upstream": checkout["state"]!.AsObject().Remove("hasUpstream"); break;
                    case "omit-flag": checkout["state"]!.AsObject().Remove("urgent"); break;
                    case "omit-facts": checkout["state"]!.AsObject().Remove("summaryFacts"); break;
                }
            }
            Console.WriteLine(node.ToJsonString(WorkerProtocol.Json));
        }
        return 0;
    }
    private static DeckSettings Settings() => new(1, [new(Distribution, "/owned/runtime"), new("Other Linux", "/owned/runtime")], [Card("hidden", "local", Reference.Path, false)]);
    private static CardSettings Card(string id, string kind, string path, bool enabled = true, string distribution = Distribution) => new(new(id, distribution, kind, path), id, enabled);
    private static RemoteCardSettings Remote(string id, string kind) => new(id, id, kind, Distribution, ["account"]);
    private static CheckoutState State(int dirty = 0, int ahead = 0, int behind = 0, bool upstream = true, int commits = 0, double? oldest = null)
    {
        var facts = new List<CheckoutSummaryFact>();
        if (dirty > 0) facts.Add(new("changed", dirty)); if (ahead > 0) facts.Add(new("unpushed", ahead));
        if (!upstream) facts.Add(new("noRemote")); if (behind > 0) facts.Add(new("behind", behind));
        return new("develop", dirty, ahead, behind, upstream, commits, oldest, dirty > 0 || ahead > 0 || behind > 0 || !upstream, ahead > 0 || !upstream, facts.Take(2).ToArray());
    }
    private static CheckoutResult Result(CheckoutState? state, CheckoutFailure? failure = null) => new(CheckoutCatalog.CardID, "owned-pass", Reference.ProjectID, Reference.Path, Now, state, failure, []);
    private static CheckoutEntry Entry(string id, string title, CheckoutState? state, CheckoutFailure? failure = null)
    {
        var reference = new CheckoutReference(id, Distribution, "/missing/" + id, title);
        return new(reference, Result(state, failure) with { ProjectID = id, Path = reference.Path });
    }
    private static AttentionItem Signal(CheckoutReference reference, CheckoutState state) => new(CheckoutValidation.SignalIdentity(reference, state.HasUpstream),
        CheckoutValidation.SignalIdentity(reference, state.HasUpstream), "goodToKnow", state.HasUpstream ? "unpushed" : "noRemote", "Original title", "develop · oldest 4 days ago",
        state.OldestLocalCommitAt, new("openTerminal", Path: reference.Path, Checkout: new(reference.Distribution, reference.ProjectID, reference.Path)), true, false);
    private static ProcessStartInfo Fake(string mode) { var start = new ProcessStartInfo(Environment.ProcessPath!); start.ArgumentList.Add("--fake-checkout-worker"); start.ArgumentList.Add(mode); return start; }
    private static void Reject(Action action, string code) { try { action(); } catch (WorkerException error) when (error.Code == code) { return; } throw new IOException("Expected pure rejection: " + code); }
    private static void Invalid(Action action) { try { action(); } catch (Exception error) when (error is InvalidDataException or InvalidOperationException or WorkerException) { return; } throw new IOException("Expected invalid configuration rejection."); }
    private static async Task Fails(Func<Task> action, string code) { try { await action(); } catch (WorkerException error) when (error.Code == code) { return; } throw new IOException("Expected transport rejection: " + code); }
    private static void Require(bool condition, string message) { if (!condition) throw new IOException(message); }
}
