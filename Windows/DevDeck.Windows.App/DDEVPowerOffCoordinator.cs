using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed record DDEVPowerOffRoute(string Distribution, DDEVPowerOffProject[] Projects);

/// Captured once per route: a disconnected participant must never become a replacement worker.
internal interface IDDEVPowerOffEndpoint
{
    string[] Capabilities { get; }
    Task<WorkerResponse> CallAsync(string operation, DDEVPowerOffContext context,
        string[]? activeProjectIDs, CancellationToken cancellation, Action<string>? progress = null);
}

internal sealed record DDEVPowerOffRouteOutcome(DDEVPowerOffRoute Route, WorkerResponse? Response,
    LocalAttentionContext? AttentionContext, string? Failure, bool CommandAttempted);

internal sealed record DDEVPowerOffOutcome(string GroupToken, bool AnyCommandAttempted,
    DDEVPowerOffRouteOutcome[] Routes)
{
    internal string[] UnconfirmedDistributions => Routes.Where(route => route.Failure is not null
        || route.Response?.PowerOff?.Diagnostic is not null
        || AnyCommandAttempted && (route.Response?.PowerOff is not { InventoryState: "available", Statuses: { } statuses }
            || statuses.Any(status => status.State != "stopped")))
        .Select(route => route.Route.Distribution).ToArray();
}

/// An all-participant intent barrier precedes every serial, Docker-wide command.
/// Only owned endpoints and typed results are used; no project-stop loop or transport retry.
internal static class DDEVPowerOffCoordinator
{
    private sealed class Participant(DDEVPowerOffRoute route, IDDEVPowerOffEndpoint endpoint)
    {
        internal readonly DDEVPowerOffRoute Route = route;
        internal readonly IDDEVPowerOffEndpoint Endpoint = endpoint;
        internal bool Prepared;
        internal bool PreparationAttempted;
        internal bool Attempted;
        internal string? Instance;
        internal string? Failure;
        internal WorkerResponse? Response;
        internal LocalAttentionContext? AttentionContext;
    }

    internal static async Task<DDEVPowerOffOutcome> RunAsync(string token, DDEVPowerOffRoute[] routes,
        IDDEVPowerOffEndpoint[] endpoints, Func<string, LocalAttentionContext> attentionContext,
        Action<string, string> progress, CancellationToken cancellation)
    {
        if (routes.Length == 0 || routes.Length != endpoints.Length)
            throw new ArgumentException("Poweroff requires one captured endpoint per distribution.");
        var participants = routes.Select((route, index) => new Participant(route, endpoints[index])).ToArray();
        var anyAttempted = false;
        try
        {
            // Reject an old worker before preparing even the first participant.
            foreach (var participant in participants)
            {
                if (!participant.Endpoint.Capabilities.Contains("ddev.poweroff.transaction", StringComparer.Ordinal))
                    throw new WorkerException("unsupportedOperation", "DDEV poweroff requires an updated worker.");
                PowerOffValidation.ValidateRequest(new(token, participant.Route.Projects),
                    "ddev.poweroff.prepare", participant.Route.Distribution);
            }
            foreach (var participant in participants)
            {
                cancellation.ThrowIfCancellationRequested();
                await PrepareAsync(participant, token, cancellation);
            }
            foreach (var participant in participants)
            {
                // The shared server may also stop routes whose own CLI has not run yet.
                // Renew every intent, including already-run workers, before another command.
                foreach (var staged in participants)
                {
                    cancellation.ThrowIfCancellationRequested();
                    await PrepareAsync(staged, token, cancellation);
                }
                cancellation.ThrowIfCancellationRequested();
                participant.Attempted = anyAttempted = true;
                try
                {
                    var response = await participant.Endpoint.CallAsync("ddev.poweroff.run", new(token),
                        null, cancellation, line => progress(participant.Route.Distribution, line));
                    Validate(participant, response, "ddev.poweroff.run", token);
                    participant.Response = response;
                }
                catch (Exception error) when (Expected(error))
                {
                    participant.Failure = Text.Failure(error);
                    if (error is OperationCanceledException) throw;
                    // A valid staged group still reconciles/tries its other confirmed routes.
                    // The failed route will be required to acknowledge the next renewal barrier.
                }
            }
        }
        catch (Exception error) when (Expected(error))
        {
            var detail = Text.Failure(error);
            foreach (var participant in participants)
                participant.Failure ??= detail;
        }
        finally
        {
            foreach (var participant in participants.Where(item => item.PreparationAttempted))
            {
                // A lost run response may have followed a real stop. Never retry/undo it.
                // Finalize every prepared actor after any attempted CLI, even a notRun route.
                var operation = anyAttempted ? "ddev.poweroff.finalize" : "ddev.poweroff.abort";
                try
                {
                    var context = attentionContext(participant.Route.Distribution);
                    var response = await participant.Endpoint.CallAsync(operation, new(token),
                        context.ActiveProjectIDs, CancellationToken.None);
                    Validate(participant, response, operation, token);
                    participant.Response = response;
                    participant.AttentionContext = context;
                }
                catch (Exception error) when (Expected(error))
                {
                    participant.Response = null;
                    participant.Failure ??= Text.Failure(error);
                }
            }
        }
        return new(token, anyAttempted, participants.Select(item => new DDEVPowerOffRouteOutcome(
            item.Route, item.Response, item.AttentionContext, item.Failure, item.Attempted)).ToArray());
    }

    private static async Task PrepareAsync(Participant participant, string token, CancellationToken cancellation)
    {
        participant.PreparationAttempted = true;
        var response = await participant.Endpoint.CallAsync("ddev.poweroff.prepare",
            new(token, participant.Route.Projects), null, cancellation);
        Validate(participant, response, "ddev.poweroff.prepare", token);
        participant.Prepared = true;
        participant.Instance ??= response.PowerOff!.WorkerInstanceID;
    }

    private static void Validate(Participant participant, WorkerResponse response, string operation, string token)
    {
        if (response.ProtocolVersion != WorkerProtocol.Version || string.IsNullOrWhiteSpace(response.Id)
            || response.Distribution != participant.Route.Distribution || response.Error is not null
            || response.Status is not null || response.Remote is not null || response.Projects is not null
            || response.Logs is not null || response.Suggestion is not null || response.Capabilities is not null
            || response.Event is not null
            || response.PowerOff is null)
            throw new WorkerException("protocolMismatch", "Poweroff response does not match its participant.");
        PowerOffValidation.ValidateResponse(response.PowerOff, operation, participant.Route.Projects,
            participant.Instance, token);
        PowerOffValidation.ValidateAttention(response.Attention, participant.Route.Distribution, operation);
    }

    private static bool Expected(Exception error) => error is IOException or InvalidOperationException or OperationCanceledException;
}
