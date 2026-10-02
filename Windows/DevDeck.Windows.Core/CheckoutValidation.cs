using System.Diagnostics.CodeAnalysis;
using System.Text;

namespace DevDeck.Windows.Core;

/// Bounds and identity checks for the isolated, read-only checkout route.
public static class CheckoutValidation
{
    public const string Capability = "checkouts.snapshot";
    private static readonly string[] FailureCodes = ["missingFolder", "gitUnavailable", "runnerUnavailable", "timedOut", "cancelled", "statusFailed", "localCommitsFailed", "outputTooLarge", "invalidState"];
    public static void ValidateReference(CheckoutReference? reference, string distribution)
    {
        if (reference is null || !Text(reference.ProjectID, 128) || !Text(reference.Distribution, 128)
            || reference.Distribution != distribution || !Text(reference.Title, 512) || !Path(reference.Path)) InvalidRequest();
    }
    public static void ValidateRequest(CheckoutRequest? checkout, string operation, string distribution,
        ProjectReference? project = null, RemoteRequest? remote = null, string? refreshCycle = null,
        string[]? activeProjectIDs = null, DDEVPowerOffContext? powerOff = null)
    {
        if (operation != Capability || checkout is null || checkout.CardID != CheckoutCatalog.CardID || !Text(checkout.PassToken, 128)
            || project is not null || remote is not null || refreshCycle is not null || activeProjectIDs is not null || powerOff is not null) InvalidRequest();
        ValidateReference(checkout!.Reference, distribution);
    }
    public static bool ValidTarget(CheckoutTarget? target) => target is not null && Text(target.Distribution, 128) && Text(target.ProjectID, 128) && Path(target.Path);
    public static string SignalIdentity(CheckoutReference reference, bool hasUpstream) =>
        $"checkout:{Encoding.UTF8.GetByteCount(reference.Distribution)}:{reference.Distribution}:{Encoding.UTF8.GetByteCount(reference.ProjectID)}:{reference.ProjectID}:{(hasUpstream ? "unpushed" : "noremote")}";
    public static void ValidateResponse(CheckoutResult? result, CheckoutRequest request)
    {
        ValidateRequest(request, Capability, request.Reference.Distribution);
        if (result is null || result.CardID != request.CardID || result.PassToken != request.PassToken
            || result.ProjectID != request.Reference.ProjectID || result.Path != request.Reference.Path || !Time(result.CheckedAt)
            || result.Signals is null || result.Signals.Length > 1) InvalidResponse();
        if (result!.Failure is { } failure && (failure.Stage is not ("status" or "localCommits") || !FailureCodes.Contains(failure.Code, StringComparer.Ordinal))) InvalidResponse();
        if (result.State is null) {
            if (result.Failure?.Stage != "status" || result.Signals.Length != 0) InvalidResponse();
            return;
        }
        if (result.Failure?.Stage == "status") InvalidResponse();
        var state = result.State;
        if (!Text(state.Branch, 512) || state.DirtyFiles < 0 || state.Ahead < 0 || state.Behind < 0 || state.LocalCommits < 0
            || state.LocalCommits > 0 && (!state.Urgent || state.OldestLocalCommitAt is not { } oldest || !Time(oldest))
            || state.LocalCommits == 0 && state.OldestLocalCommitAt is not null
            || state.InFlight != (state.DirtyFiles > 0 || state.Ahead > 0 || state.Behind > 0 || !state.HasUpstream)
            || state.Urgent != (state.Ahead > 0 || !state.HasUpstream)
            || state.SummaryFacts is null || state.SummaryFacts.Length > 2) InvalidResponse();
        var facts = new List<CheckoutSummaryFact>();
        if (state.DirtyFiles > 0) facts.Add(new("changed", state.DirtyFiles));
        if (state.Ahead > 0) facts.Add(new("unpushed", state.Ahead));
        if (!state.HasUpstream) facts.Add(new("noRemote"));
        if (state.Behind > 0) facts.Add(new("behind", state.Behind));
        if (!state.SummaryFacts!.SequenceEqual(facts.Take(2))) InvalidResponse();
        if (result.Failure is not null && (state.LocalCommits != 0 || state.OldestLocalCommitAt is not null || result.Signals.Length != 0)) InvalidResponse();
        foreach (var signal in result.Signals) {
            if (signal is null || state.LocalCommits <= 0 || state.OldestLocalCommitAt is not { } since
                || result.CheckedAt - since < 3 * 86400 || signal.Since != since
                || signal.Id != SignalIdentity(request.Reference, state.HasUpstream) || signal.Key != signal.Id
                || signal.Tier != "goodToKnow" || signal.Mark != (state.HasUpstream ? "unpushed" : "noRemote")
                || !Text(signal.Title, 2048) || !Text(signal.Subtitle, 4096) || !signal.Enabled || signal.Dismissible || signal.InboxRead is not null
                || signal.Action is not { } action || action.Kind != "openTerminal" || action.Path != request.Reference.Path
                || action.Url is not null || action.Service is not null || action.AccountID is not null || action.CardID is not null
                || action.Checkout != new CheckoutTarget(request.Reference.Distribution, request.Reference.ProjectID, request.Reference.Path)) InvalidResponse();
        }
    }
    private static bool Text(string? value, int limit) => !string.IsNullOrWhiteSpace(value) && Encoding.UTF8.GetByteCount(value) <= limit && !value.Any(char.IsControl);
    private static bool Path(string? value) => value is not null && LinuxPath.IsAbsolute(value) && Encoding.UTF8.GetByteCount(value) <= 4096;
    private static bool Time(double value) => double.IsFinite(value) && value is >= 0 and <= 253402300799;
    [DoesNotReturn] private static void InvalidRequest() => throw new WorkerException("invalidRequest", "Checkout reads require one bounded typed reference for this distribution.");
    [DoesNotReturn] private static void InvalidResponse() => throw new WorkerException("protocolMismatch", "Checkout reply contains an invalid identity, state or signal.");
}
