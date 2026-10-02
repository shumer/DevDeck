using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace DevDeck.Windows.Core;

public sealed record WorkerSettings(string Distribution, string RuntimeDirectory, string Language = "en");
public sealed record CardSettings(ProjectReference Project, string Title, bool Enabled = true, double X = 48, double Y = 80, bool Collapsed = false, bool NotifiesWhenDown = true, bool NotifiesStartFailed = true,
    string Browser = "system", string? BrowserProfile = null, ProjectLink[]? Links = null, string[]? HiddenTools = null, string? PhoneURL = null)
{
    [System.Text.Json.Serialization.JsonIgnore] public ProjectLink[] LinkList => Links ?? (Project.Kind == "arc" && Project.Arc is not null ? ProjectLinks.Defaults("arc") : []);
    [System.Text.Json.Serialization.JsonIgnore] public string[] HiddenToolList => HiddenTools ?? [];
    public static string[] Tools(string kind) => kind switch { "ddev" => ["Mailpit", "xhgui"], "arc" => ["PageBuilder", "Composer", "Deployer", "Site Service", "Delivery API"], _ => [] };
}
public sealed record DeckSettings(int SchemaVersion, WorkerSettings[] Workers, CardSettings[] Cards, bool Floating = false, bool Locked = false,
    RemoteAccountSettings[]? Accounts = null, RemoteCardSettings[]? RemoteCards = null, string Language = "system", Arrangement[]? Arrangements = null, bool Notifications = false,
    string[]? SeenAlerts = null, bool NotifiesUpdates = true, LogWindowPlacement[]? LogWindows = null, int RefreshSeconds = 60,
    [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] WorkInFlightSettings? WorkInFlight = null,
    [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] SettingsWindowGeometry? SettingsWindow = null)
{
    [System.Text.Json.Serialization.JsonIgnore] public RemoteAccountSettings[] AccountList => Accounts ?? [];
    [System.Text.Json.Serialization.JsonIgnore] public RemoteCardSettings[] RemoteCardList => RemoteCards ?? [];
    [System.Text.Json.Serialization.JsonIgnore] public Arrangement[] ArrangementList => Arrangements ?? [];
    [System.Text.Json.Serialization.JsonIgnore] public string[] AnnouncedAlerts => SeenAlerts ?? [];
    [System.Text.Json.Serialization.JsonIgnore] public LogWindowPlacement[] LogWindowList => LogWindows ?? [];
    public static DeckSettings Empty => new(1, [], [], RefreshSeconds: 120);
    public const int ArrangementLimit = 8;
    public void Validate()
    {
        if (SchemaVersion != 1) throw new InvalidDataException("This settings version is not supported.");
        if (RefreshSeconds is not (60 or 120 or 300 or 600)) throw new InvalidDataException("Invalid refresh interval.");
        if (!SettingsGeometry.Valid(SettingsWindow)) throw new InvalidDataException("Settings window size is invalid.");
        if (Language != "system" && !Localization.Languages.Contains(Language)) throw new InvalidDataException("Unsupported interface language.");
        if (Workers is null || Cards is null) throw new InvalidDataException("Settings require worker and card lists.");
        if (Workers.Any(worker => worker is null) || Cards.Any(card => card is null || card.Project is null))
            throw new InvalidDataException("Settings contain an empty worker or card.");
        if (Workers.Select(worker => worker.Distribution).Distinct(StringComparer.Ordinal).Count() != Workers.Length)
            throw new InvalidDataException("Each distribution may have only one worker.");
        foreach (var worker in Workers) _ = WorkerClient.WslStart(worker.Distribution, worker.RuntimeDirectory, worker.Language);
        if (AnnouncedAlerts.Length > NotificationLedger.Memory || AnnouncedAlerts.Any(id => string.IsNullOrWhiteSpace(id) || id.Length > 1024 || id.Any(char.IsControl)))
            throw new InvalidDataException("Notification history is invalid.");
        if (Cards.Select(card => card.Project.Id).Distinct(StringComparer.Ordinal).Count() != Cards.Length)
            throw new InvalidDataException("Card IDs must be unique.");
        foreach (var card in Cards)
        {
            if (card is null || card.Project is null || string.IsNullOrWhiteSpace(card.Title)
                || Encoding.UTF8.GetByteCount(card.Title) > 512 || card.Title.Any(char.IsControl)
                || string.IsNullOrWhiteSpace(card.Project.Id) || Encoding.UTF8.GetByteCount(card.Project.Id) > 128 || card.Project.Id.Any(char.IsControl)
                || !(card.Project.HasLocalFolder || card.Project.Kind == "arc" && card.Project.Path == "") || card.Project.Kind is not ("ddev" or "arc" or "local")
                || card.Project.HasLocalFolder && !Workers.Any(worker => worker.Distribution == card.Project.Distribution)
                || !ProjectLinks.ValidArc(card.Project.Arc) || card.Project.Kind != "arc" && card.Project.Arc is not null
                || !ProjectDetection.ValidSubtitle(card.Project.Subtitle) || !ProjectDetection.ValidOpenURL(card.Project.OpenURL)
                || !PhoneLink.ValidPhoneURL(card.PhoneURL)
                || new[] { card.Project.StartCommand,card.Project.StopCommand }.Any(command => command?.Contains('\0') == true || command is not null && Encoding.UTF8.GetByteCount(command) > 65536)
                || !double.IsFinite(card.X) || !double.IsFinite(card.Y) || !BrowserLaunch.Choices.Contains(card.Browser)
                || card.BrowserProfile?.Any(char.IsControl) == true || card.BrowserProfile?.Length > 256
                || card.LinkList.Length > 30 || card.LinkList.Any(link => !ValidConfiguredLink(link))
                || card.HiddenToolList.Any(tool => tool is null || !CardSettings.Tools(card.Project.Kind).Contains(tool, StringComparer.OrdinalIgnoreCase))
                || card.HiddenToolList.Distinct(StringComparer.OrdinalIgnoreCase).Count() != card.HiddenToolList.Length)
                throw new InvalidDataException("Card has an invalid project reference or placement.");
        }
        foreach (var account in AccountList) account.Validate();
        if (AccountList.Select(account => account.Id).Distinct(StringComparer.Ordinal).Count() != AccountList.Length)
            throw new InvalidDataException("Account IDs must be unique.");
        foreach (var card in RemoteCardList) card.Validate(this);
        if (Cards.Select(card => card.Project.Id).Concat(RemoteCardList.Select(card => card.Id)).Distinct(StringComparer.Ordinal).Count() != Cards.Length + RemoteCardList.Length)
            throw new InvalidDataException("Card IDs must be unique.");
        if (WorkInFlight is { } work && (!double.IsFinite(work.X) || !double.IsFinite(work.Y) || CheckoutCatalog.HasIdentityConflict(this)))
            throw new InvalidDataException("Work in flight placement or card identity is invalid.");
        foreach (var arrangement in ArrangementList) arrangement.Validate();
        if (LogWindowList.Length > 200 || LogWindowList.Any(item => item is null) || LogWindowList.Select(item => item.CardID).Distinct(StringComparer.Ordinal).Count() != LogWindowList.Length)
            throw new InvalidDataException("Log window placements are invalid.");
        foreach (var placement in LogWindowList) placement.Validate();
        if (ArrangementList.Select(item => item.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count() != ArrangementList.Length)
            throw new InvalidDataException("Arrangement names must be unique.");
    }
    public static bool ValidConfiguredLink(ProjectLink? link) => ProjectLinks.ValidTemplate(link);
    public static bool ValidLink(ProjectLink? link) => link is not null && !string.IsNullOrWhiteSpace(link.Label) && link.Label.Length <= 80
        && !link.Label.Any(char.IsControl) && link.Url is not null && link.Url.Length <= 2048 && Uri.TryCreate(link.Url, UriKind.Absolute, out var uri)
        && uri.Scheme is "http" or "https" && uri.UserInfo.Length == 0 && link.Kind is null or "tool" or "site";
    public DeckSettings SaveArrangement(string name)
    {
        var arrangement = new Arrangement(name.Trim(), ArrangementPlacements());
        arrangement.Validate();
        var saved = ArrangementList.ToArray();
        var index = Array.FindIndex(saved, item => string.Equals(item.Name, arrangement.Name, StringComparison.OrdinalIgnoreCase));
        if (index >= 0) {
            // The saved name owns its spelling and its place in the menu, including legacy lists.
            saved[index] = arrangement with { Name = saved[index].Name };
        } else {
            // Bound an explicit new save; loading or replacing a legacy name never truncates it.
            saved = saved.Append(arrangement).TakeLast(ArrangementLimit).ToArray();
        }
        return this with { Arrangements = saved };
    }
    public DeckSettings ForgetArrangement(string name)
    {
        var saved = ArrangementList.Where(item => !string.Equals(item.Name, name, StringComparison.OrdinalIgnoreCase)).ToArray();
        return saved.Length == ArrangementList.Length ? this : this with { Arrangements = saved };
    }
    public bool ArrangementMatches(string name)
    {
        var saved = ArrangementList.FirstOrDefault(item => string.Equals(item.Name, name, StringComparison.OrdinalIgnoreCase));
        if (saved is null) return false;
        var current = ArrangementPlacements();
        if (current.Length != saved.Cards.Length) return false;
        var expected = saved.Cards.ToDictionary(card => card.Id, StringComparer.Ordinal);
        return current.All(card => expected.TryGetValue(card.Id, out var placed) && card == placed);
    }
    private CardPlacement[] ArrangementPlacements() => Cards.Select(card => new CardPlacement(card.Project.Id, card.X, card.Y, card.Enabled, card.Collapsed))
        .Concat(RemoteCardList.Select(card => new CardPlacement(card.Id, card.X, card.Y, card.Enabled, card.Collapsed)))
        .Concat(WorkInFlight is { } work ? new[] { new CardPlacement(CheckoutCatalog.CardID, work.X, work.Y, work.Enabled, work.Collapsed) } : []).ToArray();
    public DeckSettings ApplyArrangement(string name)
    {
        var saved = ArrangementList.Single(item => string.Equals(item.Name, name, StringComparison.OrdinalIgnoreCase)).Cards.ToDictionary(card => card.Id, StringComparer.Ordinal);
        return this with {
            Cards = Cards.Select(card => saved.TryGetValue(card.Project.Id, out var place) ? card with { X = place.X, Y = place.Y, Enabled = place.Enabled, Collapsed = place.Collapsed } : card).ToArray(),
            RemoteCards = RemoteCardList.Select(card => saved.TryGetValue(card.Id, out var place) ? card with { X = place.X, Y = place.Y, Enabled = place.Enabled, Collapsed = place.Collapsed } : card).ToArray(),
            WorkInFlight = WorkInFlight is { } work && saved.TryGetValue(CheckoutCatalog.CardID, out var workPlace)
                ? work with { X = workPlace.X, Y = workPlace.Y, Enabled = workPlace.Enabled, Collapsed = workPlace.Collapsed } : WorkInFlight
        };
    }
}

public sealed record LogWindowPlacement(string CardID, double X, double Y, double Width, double Height)
{
    public void Validate()
    {
        if (string.IsNullOrWhiteSpace(CardID) || CardID.Length > 128 || CardID.Any(char.IsControl) || !double.IsFinite(X) || !double.IsFinite(Y)
            || !double.IsFinite(Width) || !double.IsFinite(Height) || Width is < 640 or > 10000 || Height is < 320 or > 10000)
            throw new InvalidDataException("Log window placement is invalid.");
    }
}

public sealed record CardPlacement(string Id, double X, double Y, bool Enabled, bool Collapsed);
public sealed record Arrangement(string Name, CardPlacement[] Cards)
{
    public void Validate()
    {
        if (string.IsNullOrWhiteSpace(Name) || Name.Length > 128 || Name.Any(char.IsControl) || Cards is null
            || Cards.Any(card => card is null || string.IsNullOrWhiteSpace(card.Id) || !double.IsFinite(card.X) || !double.IsFinite(card.Y))
            || Cards.Select(card => card.Id).Distinct(StringComparer.Ordinal).Count() != Cards.Length)
            throw new InvalidDataException("Arrangement name or card positions are invalid.");
    }
}

public sealed class SettingsStore(string path)
{
    private readonly AtomicSettingsCommit atomic = new();
    internal SettingsStore(string path, AtomicSettingsCommit atomic) : this(path) => this.atomic = atomic;
    public string Path { get; } = System.IO.Path.GetFullPath(path);
    public DeckSettings Load()
    {
        if (OperatingSystem.IsWindows() && Path.StartsWith("\\\\", StringComparison.Ordinal))
            throw new InvalidDataException("Store Windows settings on a local Windows disk so atomic saves and backups are supported.");
        if (!File.Exists(Path)) return DeckSettings.Empty;
        var settings = JsonSerializer.Deserialize<DeckSettings>(File.ReadAllBytes(Path), WorkerProtocol.Json)
            ?? throw new InvalidDataException("Settings are empty.");
        settings.Validate();
        return settings with { Cards = settings.Cards.Select(card => card.Project.Arc is null ? card : card with { Links = card.LinkList.Select(ProjectLinks.MigrateArc).ToArray() }).ToArray() };
    }
    public void Save(DeckSettings settings)
    {
        if (OperatingSystem.IsWindows() && Path.StartsWith("\\\\", StringComparison.Ordinal))
            throw new InvalidDataException("Store Windows settings on a local Windows disk so atomic saves and backups are supported.");
        settings.Validate();
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
        var temporary = Path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                JsonSerializer.Serialize(output, settings, new JsonSerializerOptions(WorkerProtocol.Json) { WriteIndented = true });
                output.Flush(flushToDisk: true);
            }
            if (File.Exists(Path)) atomic.Replace(temporary, Path, Path + ".bak");
            else File.Move(temporary, Path);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}

public static class WslDistributions
{
    public static string[] Parse(ReadOnlySpan<byte> bytes)
    {
        var text = bytes.Contains((byte)0) ? Encoding.Unicode.GetString(bytes) : Encoding.UTF8.GetString(bytes);
        return text.Trim('\uFEFF').Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(name => !name.StartsWith("docker-desktop", StringComparison.OrdinalIgnoreCase)).Distinct(StringComparer.Ordinal).ToArray();
    }
    public static async Task<string[]> DiscoverAsync(CancellationToken cancellation = default)
    {
        var start = new ProcessStartInfo("wsl.exe") { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true };
        start.ArgumentList.Add("--list"); start.ArgumentList.Add("--quiet");
        Process process;
        try { process = Process.Start(start) ?? throw new HostFailure("wslUnavailable", "Cannot enumerate WSL distributions."); }
        catch (System.ComponentModel.Win32Exception) { throw new HostFailure("wslUnavailable", "WSL could not be launched."); }
        using var owned = process;
        using var output = new MemoryStream();
        var errors = process.StandardError.ReadToEndAsync(cancellation);
        await process.StandardOutput.BaseStream.CopyToAsync(output, cancellation).ConfigureAwait(false);
        await process.WaitForExitAsync(cancellation).ConfigureAwait(false);
        await errors.ConfigureAwait(false);
        if (process.ExitCode != 0) throw new HostFailure("wslUnavailable", "WSL is unavailable. Install WSL2 to connect local projects.");
        return Parse(output.ToArray());
    }
}

public sealed class WorkerManager : IAsyncDisposable
{
    private readonly Func<WorkerSettings, WorkerClient> create;
    private readonly Dictionary<(string Distribution, bool Remote), WorkerClient> workers = new();
    private readonly SemaphoreSlim gate = new(1);
    public WorkerManager(Func<WorkerSettings, WorkerClient>? create = null) => this.create = create
        ?? (settings => new WorkerClient(settings.Distribution, WorkerClient.WslStart(settings.Distribution, settings.RuntimeDirectory, settings.Language)));
    public async Task<WorkerClient> GetAsync(WorkerSettings settings, bool remote = false)
    {
        await gate.WaitAsync().ConfigureAwait(false);
        try
        {
            var key = (settings.Distribution, remote);
            if (workers.TryGetValue(key, out var worker))
            {
                if (worker.IsConnected) return worker;
                workers.Remove(key);
                await worker.DisposeAsync().ConfigureAwait(false);
            }
            worker = create(settings);
            try { await worker.CallAsync("hello").ConfigureAwait(false); }
            catch { await worker.DisposeAsync().ConfigureAwait(false); throw; }
            workers.Add(key, worker);
            return worker;
        }
        finally { gate.Release(); }
    }
    public async Task ResetAsync(string distribution)
    {
        await gate.WaitAsync().ConfigureAwait(false);
        try {
            foreach (var key in workers.Keys.Where(key => key.Distribution == distribution).ToArray())
                if (workers.Remove(key, out var worker)) await worker.DisposeAsync().ConfigureAwait(false);
        }
        finally { gate.Release(); }
    }
    public async ValueTask DisposeAsync()
    {
        await gate.WaitAsync().ConfigureAwait(false);
        try { foreach (var worker in workers.Values) await worker.DisposeAsync().ConfigureAwait(false); workers.Clear(); }
        finally { gate.Release(); }
    }
}
