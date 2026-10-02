using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed partial class DeckController
{
    private readonly Func<string[],bool> powerOffConfirmation;
    private readonly Func<string,Task<IDDEVPowerOffEndpoint>> powerOffEndpointFactory;
    private readonly CancellationTokenSource powerOffLifetime = new();
    private bool powerOffRequested;
    private Task? powerOffTask;
    internal bool DDEVPowerOffBusy => powerOffRequested;
    internal DDEVPowerOffOutcome? LastDDEVPowerOffOutcome { get; private set; }

    internal DDEVPowerOffRoute[] CaptureDDEVPowerOffRoutes() => Settings.Cards
        .Where(card => card.Project.Kind == "ddev")
        .GroupBy(card => card.Project.Distribution, StringComparer.Ordinal)
        .Select(group => new DDEVPowerOffRoute(group.Key, group.Select(card => new DDEVPowerOffProject(
            card.Project.Id, group.Key, "ddev", card.Project.Path, card.Title)).ToArray())).ToArray();

    internal Task PowerOffDDEVAsync()
    {
        if (powerOffRequested) return powerOffTask ?? Task.CompletedTask;
        powerOffRequested = true;
        return powerOffTask = RunDDEVPowerOffAsync();
    }

    private async Task RunDDEVPowerOffAsync()
    {
        var acquired = false;
        var began = false;
        var token = Guid.NewGuid().ToString("N");
        var routes = CaptureDDEVPowerOffRoutes();
        var owners = Array.Empty<ProjectCard>();
        DDEVPowerOffOutcome? outcome = null;
        try
        {
            if (closing || shuttingDown || routes.Length == 0
                || !powerOffConfirmation(routes.Select(route => route.Distribution).ToArray())) return;
            await actions.WaitAsync(powerOffLifetime.Token);
            acquired = true;
            if (closing || shuttingDown) return;
            // Visibility/compact changes are independent. Metadata/route changes need new confirmation.
            if (JsonSerializer.Serialize(routes,WorkerProtocol.Json)
                != JsonSerializer.Serialize(CaptureDDEVPowerOffRoutes(),WorkerProtocol.Json))
                throw new InvalidOperationException(Text.L("windows.ddevPowerOff.planChanged"));
            owners = cards.Where(card => card.Reference.Kind == "ddev").ToArray();
            foreach (var route in routes) FenceDDEVPowerOffAttention(route.Distribution);
            foreach (var owner in owners) owner.BeginDDEVPowerOff(token);
            began = true;
            var endpoints = new IDDEVPowerOffEndpoint[routes.Length];
            for (var index = 0; index < routes.Length; index++)
            {
                powerOffLifetime.Token.ThrowIfCancellationRequested();
                endpoints[index] = await powerOffEndpointFactory(routes[index].Distribution);
            }
            outcome = await DDEVPowerOffCoordinator.RunAsync(token, routes, endpoints, CaptureLocalAttention,
                (distribution,line) => application.Dispatcher.BeginInvoke(new Action(() => {
                    if (closing || shuttingDown) return;
                    foreach (var owner in owners.Where(card => card.Reference.Distribution == distribution))
                        owner.ReportDDEVPowerOffProgress(token,line);
                })), powerOffLifetime.Token);
            LastDDEVPowerOffOutcome = outcome;
            if (!closing && outcome.AnyCommandAttempted)
            {
                foreach (var route in outcome.Routes)
                {
                    var result = route.Response?.PowerOff;
                    foreach (var owner in owners.Where(card => card.Reference.Distribution == route.Route.Distribution))
                    {
                        var status = result?.Statuses?.SingleOrDefault(item => item.ProjectID == owner.Reference.Id);
                        var failure = route.Failure ?? (result?.Diagnostic is { } diagnostic
                            ? Text.Failure(new WorkerException(diagnostic.Code,diagnostic.Message)) : null);
                        if (status is null) failure ??= Text.L("windows.workerDisconnected");
                        owner.CompleteDDEVPowerOff(token,status,failure);
                    }
                    ObserveAttention(route.Response?.Attention,route.AttentionContext);
                }
            }
            if (!closing && outcome.UnconfirmedDistributions is { Length: > 0 } unconfirmed)
                throw new InvalidOperationException(Text.L("windows.ddevPowerOff.failed",string.Join(", ",unconfirmed)));
        }
        catch (OperationCanceledException) when (closing || shuttingDown || powerOffLifetime.IsCancellationRequested) { }
        finally
        {
            // Never-run cancellation/failed preparation restores the exact prior presentation.
            // Matching tokens also make completion harmless after an owner closed or changed.
            if (began)
            {
                foreach (var owner in owners) owner.CompleteDDEVPowerOff(token);
                foreach (var route in routes) FenceDDEVPowerOffAttention(route.Distribution);
            }
            if (acquired) actions.Release();
            powerOffRequested = false;
        }
    }

    private void FenceDDEVPowerOffAttention(string distribution) =>
        visibilityRevisions[distribution] = visibilityRevisions.GetValueOrDefault(distribution) + 1;

    private async Task<IDDEVPowerOffEndpoint> CaptureDDEVPowerOffEndpointAsync(string distribution) =>
        new CapturedDDEVPowerOffEndpoint(await GetWorkerAsync(distribution));

    private sealed class CapturedDDEVPowerOffEndpoint(WorkerClient worker) : IDDEVPowerOffEndpoint
    {
        public string[] Capabilities => worker.Capabilities.ToArray();
        public Task<WorkerResponse> CallAsync(string operation,DDEVPowerOffContext context,
            string[]? activeProjectIDs,CancellationToken cancellation,Action<string>? progress=null) =>
            worker.CallAsync(operation,timeout: operation == "ddev.poweroff.run" ? TimeSpan.FromSeconds(330)
                : operation is "ddev.poweroff.finalize" or "ddev.poweroff.abort" ? TimeSpan.FromSeconds(90) : TimeSpan.FromSeconds(45),
                cancellation:cancellation,onProgress:progress,activeProjectIDs:activeProjectIDs,powerOff:context);
    }
}
