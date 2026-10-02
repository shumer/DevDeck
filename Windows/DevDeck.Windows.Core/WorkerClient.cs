using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace DevDeck.Windows.Core;

/// One transport per distribution. Queued requests never interleave frames.
public sealed class WorkerClient : IAsyncDisposable
{
    private readonly Process process;
    private readonly string distribution;
    private readonly SemaphoreSlim gate = new(1);
    private readonly Task diagnostics;
    private readonly BoundedFrameReader reader;
    private volatile bool closed;
    public bool IsConnected => !closed && !process.HasExited;
    public string[] Capabilities { get; private set; } = [];
    private Task? stopping;
    private readonly Dictionary<string, (DDEVPowerOffProject[] Plan, string Instance)> powerOffPlans = new(StringComparer.Ordinal);

    public WorkerClient(string distribution, ProcessStartInfo start)
    {
        this.distribution = distribution;
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.RedirectStandardInput = start.RedirectStandardOutput = start.RedirectStandardError = true;
        start.StandardInputEncoding = new UTF8Encoding(false, true);
        try { process = Process.Start(start) ?? throw new WorkerException("launchFailed", "Cannot start the WSL worker."); }
        catch (System.ComponentModel.Win32Exception) { throw new WorkerException("launchFailed", "Cannot start the WSL worker."); }
        reader = new BoundedFrameReader(process.StandardOutput.BaseStream);
        // Drain without retaining/logging command diagnostics or possible project secrets.
        diagnostics = DrainAsync(process.StandardError.BaseStream);
    }

    public static ProcessStartInfo WslStart(string distribution, string runtimeDirectory, string language = "en")
    {
        if (string.IsNullOrWhiteSpace(distribution) || distribution.StartsWith('-') || distribution.Any(char.IsControl))
            throw new ArgumentException("A WSL distribution name is required.", nameof(distribution));
        if (!LinuxPath.IsAbsolute(runtimeDirectory))
            throw new ArgumentException("An absolute Linux runtime directory is required.", nameof(runtimeDirectory));
        if (!Localization.Languages.Contains(language)) throw new ArgumentException("Unsupported worker language.", nameof(language));
        var start = new ProcessStartInfo("wsl.exe");
        foreach (var argument in new[] { "--distribution", distribution, "--cd", "~", "--exec",
                     runtimeDirectory.TrimEnd('/') + "/run-worker", "--distribution", distribution, "--language", language })
            start.ArgumentList.Add(argument);
        return start;
    }

    public async Task<WorkerResponse> CallAsync(string operation, ProjectReference? project = null,
        TimeSpan? timeout = null, CancellationToken cancellation = default, Action<string>? onProgress = null, RemoteRequest? remote = null, string? refreshCycle = null, string[]? activeProjectIDs = null, DDEVPowerOffContext? powerOff = null, CheckoutRequest? checkout = null)
    {
        // Own mutable arrays before waiting; later edits cannot change the captured account/origin.
        remote = remote is null ? null : remote with { Accounts = remote.Accounts?.Select(account => account is null ? null! : account with {
            Organizations = account.Organizations?.ToArray()!, Repositories = account.Repositories?.ToArray()!
        }).ToArray()!, ThreadIDs = remote.ThreadIDs?.ToArray() };
        var active = activeProjectIDs?.ToArray();
        var group = powerOff is null ? null : powerOff with { Projects = powerOff.Projects?.ToArray() };
        var checkoutContext = checkout is null ? null : checkout with { Reference = checkout.Reference is null ? null! : checkout.Reference with { } };
        var checkoutOperation = operation == CheckoutValidation.Capability;
        if (checkoutOperation) CheckoutValidation.ValidateRequest(checkoutContext, operation, distribution, project, remote, refreshCycle, active, group);
        else if (checkoutContext is not null) throw new WorkerException("invalidRequest", "Checkout context cannot be used for this operation.");
        var powerOffOperation = PowerOffValidation.IsOperation(operation);
        if (powerOffOperation) PowerOffValidation.ValidateRequest(group, operation, distribution, project, remote, refreshCycle, active);
        else if (group is not null) throw new WorkerException("invalidRequest", "DDEV poweroff context cannot be used for this operation.");
        if (!AttentionVisibility.ValidProjectIDs(active) || !powerOffOperation && active is not null && (project is null || remote is not null || operation == "project.check"))
            throw new WorkerException("invalidRequest", "Active project attention context is invalid.");
        await gate.WaitAsync(cancellation).ConfigureAwait(false);
        try
        {
            if (closed || process.HasExited) throw new WorkerException("disconnected", "The WSL worker has stopped. Refresh to reconnect.");
            if (project is not null && project.Distribution != distribution)
                throw new WorkerException("wrongDistribution", "Project belongs to another WSL distribution.");
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            deadline.CancelAfter(timeout ?? TimeSpan.FromSeconds(checkoutOperation ? 75 : 45));
            if (refreshCycle is { } cycle && (cycle.Length == 0 || Encoding.UTF8.GetByteCount(cycle) > 128 || cycle.Any(char.IsControl)))
                throw new WorkerException("invalidRequest", "Refresh cycle is invalid.");
            if (active is not null && !Capabilities.Contains("attention.activeProjects", StringComparer.Ordinal))
                throw new WorkerException("protocolMismatch", "The WSL worker does not support active project attention.");
            if (checkoutOperation && !Capabilities.Contains(CheckoutValidation.Capability, StringComparer.Ordinal))
                throw new WorkerException("protocolMismatch", "The WSL worker does not support checkout reads.");
            DDEVPowerOffProject[]? expectedPlan = null;
            string? expectedInstance = null;
            if (powerOffOperation)
            {
                if (!Capabilities.Contains(PowerOffValidation.Capability, StringComparer.Ordinal))
                    throw new WorkerException("protocolMismatch", "The WSL worker does not support DDEV poweroff transactions.");
                if (powerOffPlans.TryGetValue(group!.GroupToken, out var staged))
                {
                    expectedPlan = staged.Plan;
                    expectedInstance = staged.Instance;
                    if (operation == "ddev.poweroff.prepare" && !expectedPlan.SequenceEqual(group.Projects!))
                        throw new WorkerException("invalidRequest", "DDEV poweroff renewal changed its prepared plan.");
                }
                else if (operation == "ddev.poweroff.prepare") expectedPlan = group!.Projects!;
                else throw new WorkerException("invalidRequest", "DDEV poweroff requires a preparation on this worker instance.");
            }
            var request = new WorkerRequest(WorkerProtocol.Version, Guid.NewGuid().ToString("N"), operation, project, remote, refreshCycle, active, group, checkoutContext);
            var json = JsonSerializer.Serialize(request, WorkerProtocol.Json);
            if (Encoding.UTF8.GetByteCount(json) > WorkerProtocol.MaximumFrameBytes)
                throw new WorkerException("frameTooLarge", "Request exceeds the protocol frame limit.");
            try
            {
                await process.StandardInput.WriteLineAsync(json.AsMemory(), deadline.Token).ConfigureAwait(false);
                await process.StandardInput.FlushAsync(deadline.Token).ConfigureAwait(false);
                WorkerResponse response;
                while (true)
                {
                var data = await reader.ReadAsync(deadline.Token).ConfigureAwait(false)
                    ?? throw new WorkerException("disconnected", "The WSL worker closed its output.");
                response = JsonSerializer.Deserialize<WorkerResponse>(data, WorkerProtocol.Json)
                    ?? throw new WorkerException("invalidResponse", "Worker returned an empty response.");
                InboxReadValidation.ValidateWirePlacement(data, operation, response.Event is not null);
                if (response.ProtocolVersion != WorkerProtocol.Version || response.Distribution != distribution || response.Id != request.Id)
                    throw new WorkerException("protocolMismatch", "Worker version, distribution or request ID does not match.");
                if (response.Event is not { } progress) break;
                if (checkoutOperation || response.Checkout is not null)
                    throw new WorkerException("protocolMismatch", "Checkout reads cannot return progress or an unrelated result.");
                if (progress.Kind != "progress" || progress.Line is null || progress.Line.Length > 8192)
                    throw new WorkerException("protocolMismatch", "Worker progress event is invalid.");
                if (powerOffOperation && (response.PowerOff is not null || response.Status is not null || response.Remote is not null || response.Attention is not null))
                    throw new WorkerException("protocolMismatch", "DDEV poweroff progress contains an unrelated result.");
                onProgress?.Invoke(progress.Line);
                }
                if (response.Error is { } error)
                {
                    if (string.IsNullOrWhiteSpace(error.Code) || string.IsNullOrWhiteSpace(error.Message))
                        throw new WorkerException("protocolMismatch", "Worker error omitted its code or message.");
                }
                if (response.Error is null && operation == "hello" && response.Capabilities is null)
                    throw new WorkerException("protocolMismatch", "Worker hello omitted its capabilities.");
                if (response.Error is null && operation == "hello") Capabilities = response.Capabilities!.ToArray();
                if (checkoutOperation)
                {
                    if (response.Status is not null || response.Projects is not null || response.Remote is not null || response.Logs is not null
                        || response.Suggestion is not null || response.PowerOff is not null || response.Attention is not null || response.Capabilities is not null
                        || response.Error is not null && response.Checkout is not null)
                        throw new WorkerException("protocolMismatch", "Checkout reply contains an unrelated result.");
                    if (response.Error is null) CheckoutValidation.ValidateResponse(response.Checkout, checkoutContext!);
                }
                else if (response.Checkout is not null)
                    throw new WorkerException("protocolMismatch", "Worker returned an unexpected checkout result.");
                if (powerOffOperation)
                {
                    if (response.Status is not null || response.Remote is not null || response.Projects is not null || response.Logs is not null
                        || response.Suggestion is not null || response.Capabilities is not null || response.Error is not null && (response.PowerOff is not null || response.Attention is not null)
                        || (operation is "ddev.poweroff.prepare" or "ddev.poweroff.run") && response.Attention is not null)
                        throw new WorkerException("protocolMismatch", "DDEV poweroff reply contains an unrelated result.");
                    if (response.Error is null || response.PowerOff is not null)
                        PowerOffValidation.ValidateResponse(response.PowerOff, operation, expectedPlan!, expectedInstance, group!.GroupToken);
                    if (response.Error is null && operation == "ddev.poweroff.prepare")
                    {
                        // Retain a bounded number of terminal receipts for idempotent follow-up validation.
                        if (!powerOffPlans.ContainsKey(group!.GroupToken) && powerOffPlans.Count >= 16)
                            powerOffPlans.Remove(powerOffPlans.Keys.First());
                        powerOffPlans[group!.GroupToken] = (expectedPlan!.ToArray(), response.PowerOff!.WorkerInstanceID);
                    }
                }
                else if (response.PowerOff is not null)
                    throw new WorkerException("protocolMismatch", "Worker returned an unexpected DDEV poweroff result.");
                if (response.Suggestion is { } suggestion && (operation != "project.probe" || !ProjectDetection.ValidSuggestion(suggestion)))
                    throw new WorkerException("protocolMismatch", "Worker returned an invalid project suggestion.");
                if (response.Error is null && operation is ("project.status" or "project.check" or "project.start" or "project.stop" or "project.restart"))
                {
                    if (response.Status?.ProjectID != project?.Id || response.Status?.State is not ("running" or "stopped" or "paused" or "unknown" or "unavailable" or "working" or "starting"))
                        throw new WorkerException("protocolMismatch", "Worker status does not match the requested project.");
                }
                if (response.Status is { } status) PowerOffValidation.ValidateStatusFields(status);
                if (operation == "remote.snapshot" && (response.Error is null || response.Remote is not null) && (response.Remote?.CardID != remote?.CardID || response.Remote?.Kind != remote?.Kind
                    || response.Remote?.Rows is null || response.Remote?.Failures is null || response.Remote.Total < 0))
                    throw new WorkerException("protocolMismatch", "Remote snapshot does not match the requested card.");
                if (response.Remote is { } snapshot && (operation != "remote.snapshot" || snapshot.Rows is null || snapshot.Failures is null
                    || snapshot.Rows.Any(row => row is null || row.Id is null || row.AccountID is null || row.Title is null
                    || row.Repository is null || row.Detail is null || row.Health is not ("ready" or "attention" or "blocked")
                    || remote?.Accounts.Any(account => account.Id == row.AccountID) != true
                    || row.Url is { } address && !DeckSettings.ValidLink(new("Remote", address))
                    || row.StatusCode is { } code && !System.Text.RegularExpressions.Regex.IsMatch(code, "^(RV|MC|CF|CR|DR|CP|AP|WR|[TA][1-9])$")
                    || row.UpdatedAt is { } time && (!double.IsFinite(time) || time < 0 || time > 253402300799))
                    || snapshot.Failures.Any(item => item is null || item.Kind is not ("rejected" or "forbidden" or "rateLimited" or "unreachable" or "other")
                        || item.AccountID is { } accountID && remote?.Accounts.Any(account => account.Id == accountID) != true
                        || item.ResetAt is { } reset && (!double.IsFinite(reset) || reset < 0 || reset > 253402300799))
                    || snapshot.Attention?.Any(item => item is null || item.Id is null || item.Key is null || item.AccountID is null || item.Title is null
                        || item.Kind is not ("review" or "blocked" or "run" or "inbox")) == true
                    || snapshot.SuccessRate is { } rate && (!double.IsFinite(rate) || rate < 0 || rate > 1)
                    || snapshot.Blocked < 0 || snapshot.Blocked > snapshot.Total || snapshot.RepositoryCount < 0 || snapshot.NamespaceCount < 0
                    || snapshot.ReviewCount < 0 || snapshot.ActionableCount < 0 || snapshot.RunningCount < 0 || snapshot.WindowDays is < 1 or > 365
                    || snapshot.AverageDurationSeconds is { } duration && (!double.IsFinite(duration) || duration < 0 || duration > 31536000)
                    || snapshot.WatchedRepositories?.Any(repository => repository is null || repository.Length > 512) == true))
                    throw new WorkerException("protocolMismatch", "Remote snapshot contains an invalid item.");
                if (response.Remote?.PollIntervalSeconds is { } interval && (!double.IsFinite(interval) || interval < 60 || interval > 86400))
                    throw new WorkerException("protocolMismatch", "Remote polling interval is invalid.");
                if (response.Error is null && operation == "project.logs" && response.Logs is null)
                    throw new WorkerException("protocolMismatch", "Worker omitted the project log.");
                if (response.Logs is { } logs && (operation != "project.logs" || logs.Lines is null || logs.Lines.Length > 400
                    || logs.Lines.Any(line => line is null) || logs.Lines.Sum(line => (long)Encoding.UTF8.GetByteCount(line)) > 262144
                    || logs.Source?.Length > 8192 || logs.Detail?.Length > 8192 || logs.FilePath is { } logPath && !LinuxPath.IsAbsolute(logPath)))
                    throw new WorkerException("protocolMismatch", "Worker log contains an invalid line, size or file path.");
                if(operation=="project.check"&&response.Attention is not null)throw new WorkerException("protocolMismatch","A settings check must not change deck attention.");
                if (response.Remote?.Signals is { } nestedSignals) AttentionValidation.Validate(nestedSignals, distribution, operation, project, remote, response.Remote);
                if (response.Attention is { } signals) AttentionValidation.Validate(signals, distribution, operation, project, remote, response.Remote);
                InboxReadValidation.ValidateConsistency(response.Attention, response.Remote?.Signals);
                if (response.Error is { } failure) throw new WorkerException(failure.Code, failure.Message, response.Attention, response.Remote);
                return response;
            }
            catch (OperationCanceledException)
            {
                Abort(); // An interrupted read cannot consume the next request's response.
                if (cancellation.IsCancellationRequested) throw;
                throw new WorkerException("timedOut", "The WSL worker did not respond in time. Refresh to reconnect.");
            }
            catch (JsonException) { Abort(); throw new WorkerException("invalidResponse", "Worker returned invalid JSON."); }
            catch (WorkerException error) when (error.Code is "protocolMismatch" or "disconnected" or "frameTooLarge")
            { Abort(); throw; }
            catch (IOException error) when (error is not WorkerException)
            { Abort(); throw new WorkerException("disconnected", "WSL transport failed. Refresh to reconnect."); }
        }
        finally { gate.Release(); }
    }

    private static async Task DrainAsync(Stream stream)
    {
        var buffer = new byte[4096];
        try { while (await stream.ReadAsync(buffer).ConfigureAwait(false) > 0) { } }
        catch (IOException) { }
        catch (ObjectDisposedException) { }
    }

    private void Abort()
    {
        closed = true;
        try { process.StandardInput.Close(); } catch (IOException) { }
        stopping ??= StopProcessAsync();
    }

    private async Task StopProcessAsync()
    {
        // EOF lets the Linux worker cancel and reap its process sessions before WSL is terminated.
        try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5)).ConfigureAwait(false); }
        catch (TimeoutException)
        {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
            await process.WaitForExitAsync().ConfigureAwait(false);
        }
    }

    public async ValueTask DisposeAsync()
    {
        await gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (!closed)
            {
                closed = true;
                process.StandardInput.Close();
                try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5)).ConfigureAwait(false); }
                catch (TimeoutException) { Abort(); }
            }
            if (stopping is not null) await stopping.ConfigureAwait(false);
            await diagnostics.WaitAsync(TimeSpan.FromSeconds(5)).ConfigureAwait(false);
            process.Dispose();
        }
        catch (TimeoutException) { Abort(); process.Dispose(); }
        finally { gate.Release(); }
    }
}

/// Limits bytes before JSON parsing and keeps any bytes after the newline for the next frame.
public sealed class BoundedFrameReader(Stream stream, int limit = WorkerProtocol.MaximumFrameBytes)
{
    private readonly byte[] buffer = new byte[4096];
    private int offset;
    private int count;
    public async Task<byte[]?> ReadAsync(CancellationToken cancellation = default)
    {
        using var frame = new MemoryStream();
        while (true)
        {
            if (offset == count)
            {
                count = await stream.ReadAsync(buffer, cancellation).ConfigureAwait(false);
                offset = 0;
                if (count == 0) return frame.Length == 0 ? null : frame.ToArray();
            }
            var newline = Array.IndexOf(buffer, (byte)10, offset, count - offset);
            var end = newline < 0 ? count : newline;
            if (frame.Length + end - offset > limit) throw new WorkerException("frameTooLarge", "Worker response exceeds the frame limit.");
            frame.Write(buffer, offset, end - offset);
            offset = end;
            if (newline >= 0) { offset++; return frame.ToArray(); }
        }
    }
}
