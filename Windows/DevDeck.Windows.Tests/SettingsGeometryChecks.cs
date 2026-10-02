using System.Text;
using System.Text.Json;
using DevDeck.Windows.Core;

// Pure projections and actual owned SettingsStore transactions; no native UI or user settings.
internal static class SettingsGeometryChecks
{
    private static readonly Encoding Utf8WithoutBom = new UTF8Encoding(false);
    internal static async Task RunAsync(Func<string, Func<Task>, Task> check)
    {
        await check("settings geometry old JSON stays absent and rich size roundtrips preserve all other configuration", Compatibility);
        await check("settings geometry malformed stored field falls back alone while invalid writes preserve owned files", StoredFallbackAndWriteBounds);
        await check("settings geometry restore clamps supported work areas without changing remembered size", Restore);
        await check("settings geometry current-model merge preserves committed resize and atomic failure keeps prior bytes", MergeAndAtomicFailure);
    }

    private static Task Compatibility()
    {
        using var fixture = new Fixture();
        var original = RichSettings();
        var oldJson = Json(original);
        Require(!oldJson.Contains("\"settingsWindow\"", StringComparison.Ordinal), "Null optional geometry changed the legacy JSON shape.");
        fixture.Write(oldJson);
        var loaded = fixture.Store.Load();
        Require(loaded.SettingsWindow is null && Json(loaded) == oldJson, "Loading complete old settings materialized geometry or changed unrelated fields.");
        Require(SettingsGeometry.Valid(null) && DeckSettings.Empty.SettingsWindow is null && DeckSettings.Empty.RefreshSeconds == 120,
            "Default geometry or the explicit new-deck cadence was materialized or changed.");
        fixture.Store.Save(loaded);
        Require(fixture.Store.Load().SettingsWindow is null && !File.ReadAllText(fixture.Path).Contains("\"settingsWindow\"", StringComparison.Ordinal),
            "An unrelated save created a geometry preference.");
        fixture.Write("{\"schemaVersion\":1,\"workers\":[],\"cards\":[]}");
        var omitted = fixture.Store.Load();
        Require(omitted.SettingsWindow is null && omitted.RefreshSeconds == 60, "Legacy omitted refresh/geometry defaults changed.");

        var remembered = new SettingsWindowGeometry(940.25, 560.5);
        var chosen = original with { SettingsWindow = remembered };
        fixture.Store.Save(chosen);
        var roundtrip = fixture.Store.Load();
        Require(roundtrip.SettingsWindow == remembered && Json(roundtrip with { SettingsWindow = null }) == oldJson,
            "Size roundtrip changed card IDs, positions, compact flags, accounts, scopes, arrangements, history or preferences.");
        Require(Json(remembered) == "{\"width\":940.25,\"height\":560.5}", "Geometry wire spelling or numeric precision changed.");
        Require(Json(original) == oldJson && original.SettingsWindow is null, "Serialization/save modified its input.");
        fixture.RequireNoTemporary();
        return Task.CompletedTask;
    }

    private static Task StoredFallbackAndWriteBounds()
    {
        using var fixture = new Fixture();
        var original = RichSettings();
        var oldJson = Json(original);
        var invalidFields = new[] {
            "null", "false", "true", "42", "1e309", "\"940x560\"", "[]", "[{},[1,2]]", "{}",
            "{\"width\":940}", "{\"height\":560}", "{\"width\":\"940\",\"height\":560}",
            "{\"width\":940,\"height\":null}", "{\"width\":[],\"height\":560}", "{\"width\":940,\"height\":{\"nested\":1}}",
            "{\"width\":940,\"height\":560,\"width\":960}", "{\"width\":940,\"height\":560,\"HEIGHT\":600}",
            "{\"width\":879.999,\"height\":560}", "{\"width\":940,\"height\":439.999}",
            "{\"width\":10000.001,\"height\":560}", "{\"width\":940,\"height\":10000.001}",
            "{\"width\":1e309,\"height\":560}", "{\"width\":940,\"height\":-1e309}",
            "{\"" + new string('x', 65) + "\":0,\"width\":940,\"height\":560}",
            "{\"width\":940,\"height\":560,\"a\":0,\"b\":0,\"c\":0,\"d\":0,\"e\":0,\"f\":0,\"g\":0}"
        };
        foreach (var field in invalidFields) {
            fixture.Write(WithGeometry(oldJson, field));
            var before = File.ReadAllBytes(fixture.Path);
            var backup = File.ReadAllBytes(fixture.BackupPath);
            var loaded = fixture.Store.Load();
            Require(loaded.SettingsWindow is null && Json(loaded) == oldJson, "Malformed optional size discarded or changed a valid sibling: " + field);
            Require(Same(File.ReadAllBytes(fixture.Path), before) && Same(File.ReadAllBytes(fixture.BackupPath), backup), "Read fallback rewrote settings or backup.");
            fixture.RequireNoTemporary();
        }
        var validFields = new[] {
            ("{\"width\":880,\"height\":440}", new SettingsWindowGeometry(880,440)),
            ("{\"width\":10000,\"height\":10000}", new SettingsWindowGeometry(10000,10000)),
            ("{\"WiDtH\":940.25,\"HEIGHT\":560.5}", new SettingsWindowGeometry(940.25,560.5)),
            ("{\"\\u0077idth\":940,\"height\":560}", new SettingsWindowGeometry(940,560)),
            ("{\"width\":940,\"height\":560,\"future\":{\"text\":\"" + new string('x',32768) + "\",\"items\":[[1],{}]}}", new SettingsWindowGeometry(940,560)),
            ("{\"width\":940,\"height\":560,\"a\":0,\"b\":false,\"c\":null,\"d\":[],\"e\":{},\"f\":\"unknown\"}", new SettingsWindowGeometry(940,560))
        };
        foreach (var (field, expected) in validFields) {
            fixture.Write(WithGeometry(oldJson, field));
            var loaded = fixture.Store.Load();
            Require(loaded.SettingsWindow == expected && Json(loaded with { SettingsWindow = null }) == oldJson,
                "Valid bounded/forward-compatible optional size failed or changed siblings.");
            loaded.Validate();
        }
        foreach (var broken in new[] {
            WithGeometry(oldJson, "{\"width\":NaN,\"height\":560}"),
            WithGeometry(oldJson, "{\"width\":940,\"height\":560"),
            WithGeometry(oldJson.Replace("\"cards\":[", "\"cards\":false,\"ignoredCards\":[", StringComparison.Ordinal), "false"),
            WithGeometry(oldJson.Replace("\"schemaVersion\":1", "\"schemaVersion\":2", StringComparison.Ordinal), "false"),
            WithGeometry(oldJson.Replace("\"refreshSeconds\":300", "\"refreshSeconds\":42", StringComparison.Ordinal), "false"),
            WithGeometry(oldJson.Replace("\"x\":-12.25", "\"x\":\"invalid sibling\"", StringComparison.Ordinal), "false")
        }) {
            fixture.Write(broken);
            Require(Capture(() => fixture.Store.Load()) is JsonException or InvalidDataException,
                "Optional fallback swallowed broken JSON or unrelated invalid configuration.");
        }
        fixture.Write(oldJson);
        var prior = File.ReadAllBytes(fixture.Path); var priorBackup = File.ReadAllBytes(fixture.BackupPath);
        var invalidSizes = new[] {
            new SettingsWindowGeometry(879.999,560), new SettingsWindowGeometry(940,439.999),
            new SettingsWindowGeometry(10000.001,560), new SettingsWindowGeometry(940,10000.001),
            new SettingsWindowGeometry(double.NaN,560), new SettingsWindowGeometry(940,double.NaN),
            new SettingsWindowGeometry(double.PositiveInfinity,560), new SettingsWindowGeometry(940,double.NegativeInfinity),
            new SettingsWindowGeometry(0,0)
        };
        var replacements = 0;
        var rejecting = new SettingsStore(fixture.Path, new AtomicSettingsCommit((_,_,_) => replacements++, _ => throw new Exception("Unexpected retry."), () => TimeSpan.Zero));
        foreach (var size in invalidSizes) {
            Require(!SettingsGeometry.Valid(size) && Capture(() => rejecting.Save(original with { SettingsWindow = size })) is InvalidDataException,
                "Invalid new geometry was normalized or reached serialization.");
            Require(Capture(() => Json(size)) is JsonException, "Direct invalid geometry serialization bypassed the type-local write guard.");
            Require(replacements == 0 && Same(File.ReadAllBytes(fixture.Path), prior) && Same(File.ReadAllBytes(fixture.BackupPath), priorBackup),
                "Rejected new size changed original or backup.");
            fixture.RequireNoTemporary();
        }
        return Task.CompletedTask;
    }

    private static Task Restore()
    {
        Require(SettingsGeometry.Restore(null,null,null) == new SettingsWindowGeometry(1020,720), "Absent preference changed the current Windows default.");
        var saved = new SettingsWindowGeometry(1500,900);
        Require(SettingsGeometry.Restore(saved,1200,700) == new SettingsWindowGeometry(1200,700) && saved == new SettingsWindowGeometry(1500,900),
            "Supported work-area clamp changed remembered geometry or failed exact arithmetic.");
        Require(SettingsGeometry.Restore(saved,880,440) == new SettingsWindowGeometry(880,440), "Inclusive supported floor was rejected.");
        Require(SettingsGeometry.Restore(saved,2000,1200) == saved, "Larger work area enlarged the chosen size.");
        Require(SettingsGeometry.Restore(null,940,560) == new SettingsWindowGeometry(940,560), "Default size did not clamp to a supported work area.");
        foreach (var area in new (double? Width,double? Height)[] {
            (null,700),(1200,null),(879.999,700),(1200,439.999),(double.NaN,700),(1200,double.NaN),
            (double.PositiveInfinity,700),(1200,double.NegativeInfinity),(0,0)
        }) {
            Require(SettingsGeometry.Restore(saved,area.Width,area.Height) == saved
                && SettingsGeometry.Restore(null,area.Width,area.Height) == new SettingsWindowGeometry(1020,720),
                "Incomplete, nonfinite or unsupported work area partially clamped a window.");
        }
        Require(SettingsGeometry.Restore(new(879,440),1200,700) == new SettingsWindowGeometry(1020,700)
            && SettingsGeometry.Restore(new(940,double.NaN),null,null) == new SettingsWindowGeometry(1020,720),
            "Defensive invalid-size restore did not use the default before optional clamp.");
        return Task.CompletedTask;
    }

    private static Task MergeAndAtomicFailure()
    {
        using var fixture = new Fixture();
        var original = RichSettings();
        var current = original with { SettingsWindow = new(1300,810) };
        var stale = original with { Floating = false, Locked = false, Language = "de", RefreshSeconds = 600,
            Cards = original.Cards.Select(card => card with { Title = "Edited " + card.Title }).ToArray() };
        foreach (var oldGeometry in new SettingsWindowGeometry?[] { null,new(940,560) }) {
            var draft = stale with { SettingsWindow = oldGeometry };
            var currentBefore = Json(current); var draftBefore = Json(draft);
            var merged = SettingsGeometry.PreserveCurrent(current,draft);
            Require(ReferenceEquals(merged.SettingsWindow,current.SettingsWindow) && Json(merged with { SettingsWindow = oldGeometry }) == draftBefore,
                "Stale metadata erased the current resize or lost its intended edits.");
            Require(ReferenceEquals(merged.Cards,draft.Cards) && ReferenceEquals(merged.Workers,draft.Workers)
                && ReferenceEquals(merged.Accounts,draft.Accounts) && ReferenceEquals(merged.Arrangements,draft.Arrangements)
                && Json(current) == currentBefore && Json(draft) == draftBefore, "Pure geometry merge cloned/mutated other model data.");
        }
        Require(SettingsGeometry.PreserveCurrent(original,stale with { SettingsWindow = new(940,560) }).SettingsWindow is null,
            "Current null geometry was replaced by a stale captured preference.");
        fixture.Store.Save(original);
        fixture.Store.Save(current);
        var prior = File.ReadAllBytes(fixture.Path); var priorBackup = File.ReadAllBytes(fixture.BackupPath);
        Require(Json(JsonSerializer.Deserialize<DeckSettings>(priorBackup,WorkerProtocol.Json)!) == Json(original),
            "Owned fixture did not retain an exact preceding valid configuration backup.");
        var proposed = SettingsGeometry.PreserveCurrent(current,stale);
        var failure = new IOException("Owned geometry replacement fault.");
        var attempts = 0;
        var failing = new SettingsStore(fixture.Path, new AtomicSettingsCommit((source,target,backup) => {
            attempts++;
            var prepared = JsonSerializer.Deserialize<DeckSettings>(File.ReadAllBytes(source),WorkerProtocol.Json)!;
            Require(prepared.SettingsWindow == current.SettingsWindow && Json(prepared) == Json(proposed)
                && target == fixture.Path && backup == fixture.BackupPath, "Failed transaction prepared a stale geometry or lost metadata.");
            throw failure;
        }, _ => throw new Exception("Unexpected retry."), () => TimeSpan.Zero));
        Require(ReferenceEquals(Capture(() => failing.Save(proposed)),failure) && attempts == 1
            && Same(File.ReadAllBytes(fixture.Path),prior) && Same(File.ReadAllBytes(fixture.BackupPath),priorBackup),
            "Rejected atomic merge overwrote committed geometry, prior settings or backup.");
        Require(fixture.Store.Load().SettingsWindow == current.SettingsWindow && original.SettingsWindow is null,
            "Failed geometry save changed committed model or original input.");
        fixture.RequireNoTemporary();
        return Task.CompletedTask;
    }

    private static DeckSettings RichSettings() => new(1,
        [new("Owned Linux","/missing/worker","en")],
        [new(new("project.arc","Owned Linux","arc","/missing/arc"),"Arc 🧩",Enabled:false,X:-12.25,Y:77.5,Collapsed:true,
            Browser:"chrome",BrowserProfile:"Profile 2",Links:[new("TEST","https://example.com/test")]),
         new(new("project.ddev","Owned Linux","ddev","/missing/ddev"),"DDEV2",X:321.125,Y:123.75,HiddenTools:["xhgui"]),
         new(new("project.local","Owned Linux","local","/missing/plain"),"Local10",X:500,Y:250,NotifiesWhenDown:false)],
        Floating:true,Locked:true,
        Accounts:[new("work","Work GitHub","github","https://api.github.com",["example"],["example/web"],Browser:"edge",BrowserProfile:"Default"),
                  new("lab","Lab","gitlab","https://gitlab.example.com",[],[],Enabled:false)],
        RemoteCards:[new("legacy.inbox","Inbox","inbox","Owned Linux",["work"],X:900,Y:80,Collapsed:true),
                     new("legacy.merge","Merge","mergeRequests","Owned Linux",["lab"],Enabled:false,X:900,Y:200)],
        Language:"ru",Arrangements:[new("Work",[new("project.arc",-12.25,77.5,false,true),new("legacy.inbox",900,80,true,true)])],
        Notifications:true,SeenAlerts:["original:seen"],NotifiesUpdates:false,LogWindows:[new("project.ddev",10,20,800,500)],
        RefreshSeconds:300,WorkInFlight:new(false,600,400,true));

    private static string Json<T>(T value) => JsonSerializer.Serialize(value,WorkerProtocol.Json);
    private static string WithGeometry(string original, string field) => original[..^1] + ",\"settingsWindow\":" + field + "}";
    private static Exception Capture(Action action) { try { action(); } catch (Exception error) { return error; } throw new Exception("Expected rejected geometry/configuration."); }
    private static bool Same(byte[] left, byte[] right) => left.AsSpan().SequenceEqual(right);
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }

    private sealed class Fixture : IDisposable
    {
        private readonly string directory = System.IO.Path.Combine(System.IO.Path.GetTempPath(),"devdeck-settings-geometry-" + Guid.NewGuid().ToString("N"));
        internal string Path { get; }
        internal string BackupPath => Path + ".bak";
        internal SettingsStore Store { get; }
        internal Fixture()
        {
            Directory.CreateDirectory(directory);
            Path = System.IO.Path.Combine(directory,"settings.json");
            Store = new SettingsStore(Path);
            File.WriteAllText(BackupPath,"owned preceding backup",Utf8WithoutBom);
        }
        internal void Write(string json) => File.WriteAllText(Path,json,Utf8WithoutBom);
        internal void RequireNoTemporary() => Require(!Directory.EnumerateFiles(directory,"*.tmp").Any(), "Owned geometry transaction leaked a temporary file.");
        public void Dispose()
        {
            foreach (var file in Directory.EnumerateFiles(directory)) File.Delete(file);
            Directory.Delete(directory);
        }
    }
}
