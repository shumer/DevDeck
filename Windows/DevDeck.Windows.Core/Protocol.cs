using System.Text.Json;

namespace DevDeck.Windows.Core;

public static class WorkerProtocol
{
    public const int Version = 1;
    public const int MaximumFrameBytes = 1_048_576;
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
}

public sealed record ProjectReference(string Id, string Distribution, string Kind, string Path,
    string? StartCommand = null, string? StopCommand = null, bool? HoldsProcess = null, bool? RequiresDocker = null, string? HealthURL = null, string? Title = null, ArcOptions? Arc = null, string? Subtitle = null, string? OpenURL = null)
{
    [System.Text.Json.Serialization.JsonIgnore] public bool HasLocalFolder => LinuxPath.IsAbsolute(Path);
}
public sealed record ArcOptions(string Organization = "", string? Site = null, string LocalURL = "", string HealthPath = "/release");
public sealed record ProjectSuggestion(string Subtitle, string StartCommand, string StopCommand, bool HoldsProcess, bool RequiresDocker, string HealthURL);
public sealed record WorkerRequest(int ProtocolVersion, string Id, string Operation, ProjectReference? Project = null, RemoteRequest? Remote = null, string? RefreshCycle = null, string[]? ActiveProjectIDs = null, DDEVPowerOffContext? PowerOff = null, CheckoutRequest? Checkout = null);
public sealed record WorkerFailure(string Code, string Message);
public sealed record DDEVPowerOffProject(string Id, string Distribution, string Kind, string Path, string? Title = null);
public sealed record DDEVPowerOffContext(string GroupToken, DDEVPowerOffProject[]? Projects = null);
public sealed record DDEVPowerOffResult(string GroupToken, string WorkerInstanceID, string Phase,
    [property: System.Text.Json.Serialization.JsonRequired] int LeaseSecondsRemaining,
    string CommandState, int? CommandExitCode = null, WorkerFailure? Diagnostic = null,
    [property: System.Text.Json.Serialization.JsonRequired] string InventoryState = "notChecked", ProjectStatus[]? Statuses = null);
public sealed record ProjectStatus(string ProjectID, string State, string? Branch, string? SiteURL, string? Framework, string? EngineVersion, string? NotAnswering = null, string? SyncBroken = null,
    string? RepositoryURL = null, ProjectLink[]? ToolLinks = null, string? VersionsLine = null, string? LocalEditorURL = null, ProjectCheckSummary? CheckSummary = null, double? CheckedAt = null);
public sealed record ProjectCheckSummary(string Tone, string State, string Detail);
public sealed record ProjectLink(string Label, string Url, bool Enabled = true, string? Kind = null)
{
    [System.Text.Json.Serialization.JsonIgnore] public string EffectiveKind => Kind ?? (Label is "TEST" or "UAT" or "PROD" ? "site" : "tool");
}
public sealed record DiscoveredProject(string Name, string Distribution, string Path, string State);
public sealed record WorkerLogs(string[] Lines, string? Source, string? Detail, string? FilePath = null);
public sealed record WorkerEvent(string Kind, string Line);
public sealed record WorkerResponse(int ProtocolVersion, string? Id, string Distribution, string[]? Capabilities,
    ProjectStatus? Status, DiscoveredProject[]? Projects, WorkerFailure? Error, WorkerLogs? Logs = null, WorkerEvent? Event = null, RemoteSnapshot? Remote = null, AttentionSnapshot? Attention = null, ProjectSuggestion? Suggestion = null, DDEVPowerOffResult? PowerOff = null, CheckoutResult? Checkout = null);

public sealed record RemoteCredential(string Id, string Label, string Endpoint, string[] Organizations, string[] Repositories, string? Token)
{
    // Memory-only namespace. A changed credential cannot reuse an earlier credential's ETag/body.
    public string? CacheScope
    {
        get
        {
            if (Token is null) return null;
            var bytes = System.Text.Encoding.UTF8.GetBytes(Token);
            try { return Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes)); }
            finally { System.Security.Cryptography.CryptographicOperations.ZeroMemory(bytes); }
        }
    }
    public override string ToString() => "Remote account credential (redacted)";
}
public sealed record RemoteRequest(string CardID, string Kind, RemoteCredential[] Accounts, string[]? ThreadIDs = null, double? LastReadAt = null);
public sealed record RemoteRow(string Id, string AccountID, string Title, string Repository, string? Url, string Health, string Detail, bool NeedsReview,
    string? StatusCode = null, double? UpdatedAt = null, bool IsUnread = true, string? TicketKey = null, string? Subject = null);
public sealed record RemoteAccountFailure(string? AccountID, string Kind, double? ResetAt = null);
public sealed record RemoteSnapshot(string CardID, string Kind, int Total, int Blocked, double? SuccessRate, RemoteRow[] Rows, RemoteAccountFailure[] Failures, bool Capped, RemoteAttention[]? Attention = null, double? PollIntervalSeconds = null,
    int RepositoryCount = 0, int NamespaceCount = 0, int ReviewCount = 0, int ActionableCount = 0, int RunningCount = 0, int WindowDays = 7,
    double? AverageDurationSeconds = null, string[]? WatchedRepositories = null, bool FollowsPullRequests = false,
    [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] AttentionSnapshot? Signals = null);
public sealed record RemoteAttention(string Id, string Key, string AccountID, string Kind, string Title, string? Url);
public sealed record AttentionAction(string Kind, string? Url = null, string? Service = null, string? AccountID = null, string? CardID = null, string? Path = null, CheckoutTarget? Checkout = null);
[System.Text.Json.Serialization.JsonUnmappedMemberHandling(System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow)]
public sealed record InboxReadTarget(string CardID, string AccountID, string ThreadID, string Endpoint);
public sealed record AttentionItem(string Id, string Key, string Tier, string Mark, string Title, string Subtitle, double? Since, AttentionAction Action, bool Enabled, bool Dismissible,
    [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] InboxReadTarget? InboxRead = null);
public sealed record DeckAlert(string Id, string Kind, string Source, string Title, string Subtitle, string Body, string Subject, AttentionAction Target, bool Quiet);
public sealed record AttentionSnapshot(string Scope, AttentionItem[] Items, DeckAlert[] Alerts, string? DockerState = null, bool? ContainerStartAllowed = null);

public sealed class WorkerException(string code, string message, AttentionSnapshot? attention = null, RemoteSnapshot? remote = null) : IOException(message)
{
    public string Code { get; } = code;
    public AttentionSnapshot? Attention { get; } = attention;
    public RemoteSnapshot? Remote { get; } = remote;
}

public static class LinuxPath
{
    public static bool IsAbsolute(string path) => path.StartsWith('/') && !path.StartsWith("//", StringComparison.Ordinal)
        && !path.Contains('\\') && !path.Any(char.IsControl) && !path.Split('/').Contains("..");
}
