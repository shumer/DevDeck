using System.Text;

namespace DevDeck.Windows.Core;

/// Validates the additive DDEV transaction without touching paths, a worker or Docker.
public static class PowerOffValidation
{
    public const string Capability = "ddev.poweroff.transaction";
    public static bool IsOperation(string operation) => operation is "ddev.poweroff.prepare" or "ddev.poweroff.run" or "ddev.poweroff.finalize" or "ddev.poweroff.abort";

    public static void ValidateRequest(DDEVPowerOffContext? context, string operation, string distribution,
        ProjectReference? project = null, RemoteRequest? remote = null, string? refreshCycle = null, string[]? activeProjectIDs = null)
    {
        if (!IsOperation(operation) || context is null || !Text(context.GroupToken, 128) || !Text(distribution, 128)
            || project is not null || remote is not null || refreshCycle is not null
            || !AttentionVisibility.ValidProjectIDs(activeProjectIDs)
            || activeProjectIDs is not null && operation is not ("ddev.poweroff.finalize" or "ddev.poweroff.abort")) InvalidRequest();
        if (operation == "ddev.poweroff.prepare")
        {
            if (context!.Projects is not { Length: >= 1 and <= 1024 }) InvalidRequest();
            var identities = new HashSet<string>(StringComparer.Ordinal);
            foreach (var item in context!.Projects!)
                if (item is null || !Text(item.Id, 128) || !identities.Add(item.Id) || item.Distribution != distribution
                    || item.Kind != "ddev" || item.Path is null || !LinuxPath.IsAbsolute(item.Path)
                    || Encoding.UTF8.GetByteCount(item.Path) > 4096 || item.Title is not null && !Text(item.Title, 512)) InvalidRequest();
        }
        else if (context!.Projects is not null) InvalidRequest();
    }

    public static void ValidateResponse(DDEVPowerOffResult? result, string operation, DDEVPowerOffProject[] expectedPlan,
        string? expectedInstanceID = null, string? expectedGroupToken = null)
    {
        if (!IsOperation(operation) || result is null || !Text(result.GroupToken, 128) || !Text(result.WorkerInstanceID, 128)
            || expectedInstanceID is not null && result.WorkerInstanceID != expectedInstanceID
            || expectedGroupToken is not null && result.GroupToken != expectedGroupToken
            || result.Phase != (operation["ddev.poweroff.".Length..] switch { "prepare" => "prepared", "run" => "ran", "finalize" => "finalized", "abort" => "aborted", _ => "" })
            || result.LeaseSecondsRemaining is < 0 or > 600
            || result.CommandState is not ("notRun" or "succeeded" or "failed" or "timedOut" or "cancelled" or "unavailable")
            || result.InventoryState is not ("notChecked" or "available" or "unavailable" or "invalid")
            || result.CommandState == "succeeded" && result.CommandExitCode != 0
            || result.CommandState == "failed" && (result.CommandExitCode is null or 0)
            || result.CommandState is "notRun" or "timedOut" or "cancelled" or "unavailable" && result.CommandExitCode is not null
            || result.Diagnostic is { } diagnostic && (!Text(diagnostic.Code, 128) || !Text(diagnostic.Message, 16384, multiline: true))
            || result.Statuses is null || result.Statuses.Length > 1024) InvalidResponse();
        if (operation is "ddev.poweroff.prepare" or "ddev.poweroff.run")
        {
            if (result!.Statuses!.Length != 0 || result.InventoryState != "notChecked") InvalidResponse();
            return;
        }
        if (result!.LeaseSecondsRemaining != 0) InvalidResponse();
        if (operation == "ddev.poweroff.abort" && result.CommandState == "notRun")
        {
            if (result.Statuses!.Length != 0 || result.InventoryState != "notChecked") InvalidResponse();
            return;
        }
        if (result.InventoryState == "notChecked") InvalidResponse();
        if (expectedPlan is not { Length: >= 1 and <= 1024 } || result!.Statuses!.Length != expectedPlan.Length) InvalidResponse();
        var identities = new HashSet<string>(StringComparer.Ordinal);
        for (var index = 0; index < expectedPlan.Length; index++)
        {
            var status = result!.Statuses![index];
            if (status is null || !Text(status.ProjectID, 128) || !identities.Add(status.ProjectID)
                || status.ProjectID != expectedPlan[index].Id
                || status.State is not ("running" or "stopped" or "paused" or "unknown" or "unavailable" or "working" or "starting")
                || status.CheckedAt is null) InvalidResponse();
            ValidateStatusFields(status!);
        }
    }

    // The same limits are used for ordinary project replies and every bulk member.
    internal static void ValidateStatusFields(ProjectStatus status)
    {
        if (status.RepositoryURL is { } repository && !DeckSettings.ValidLink(new("Repository", repository))
            || status.LocalEditorURL is { } editor && !DeckSettings.ValidLink(new("PageBuilder", editor))
            || status.ToolLinks is { } links && (links.Length > 30 || links.Any(link => !DeckSettings.ValidLink(link))))
            throw new WorkerException("protocolMismatch", "Worker project links are invalid.");
        if (status.VersionsLine is { } versions && (Encoding.UTF8.GetByteCount(versions) > 512 || versions.Any(char.IsControl)))
            throw new WorkerException("protocolMismatch", "Worker project versions are invalid.");
        if (!SettingsChecks.Valid(status.CheckSummary, status.CheckedAt))
            throw new WorkerException("protocolMismatch", "Worker returned an invalid settings check.");
    }

    /// Lets injected native endpoints use the same scoped validation as real IPC.
    public static void ValidateAttention(AttentionSnapshot? snapshot, string distribution, string operation)
    {
        if (snapshot is null) return;
        if (operation is not ("ddev.poweroff.finalize" or "ddev.poweroff.abort")) InvalidResponse();
        AttentionValidation.Validate(snapshot, distribution, operation, null, null);
    }

    private static bool Text(string? value, int limit, bool multiline = false) => !string.IsNullOrWhiteSpace(value)
        && Encoding.UTF8.GetByteCount(value) <= limit && !value.Any(character => char.IsControl(character)
            && (!multiline || character is not ('\r' or '\n' or '\t')));
    [System.Diagnostics.CodeAnalysis.DoesNotReturn]
    private static void InvalidRequest() => throw new WorkerException("invalidRequest", "DDEV poweroff context is invalid.");
    [System.Diagnostics.CodeAnalysis.DoesNotReturn]
    private static void InvalidResponse() => throw new WorkerException("protocolMismatch", "DDEV poweroff result does not match its prepared plan.");
}
