using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal interface IWorkInFlightEndpoint
{
    string[] Capabilities { get; }
    Task<CheckoutResult> ReadAsync(CheckoutRequest request, CancellationToken cancellation);
}

internal sealed record WorkInFlightScanResult(CheckoutEntry[] Entries, bool Completed);

/// A pass sequences each distro's Git reads, while independent routes may progress together.
/// Visibility supersession stops admission, never the already admitted reader.
internal sealed class WorkInFlightScanCoordinator(Func<string, Task<IWorkInFlightEndpoint>> endpoints)
{
    internal async Task<WorkInFlightScanResult> RunAsync(CheckoutReference[] references, string passToken,
        Func<bool> current, CancellationToken cancellation, Action<CheckoutEntry[]>? completedRoute = null)
    {
        if (references.Length > 1024) throw new IOException("Too many configured checkouts.");
        var captured = references.ToArray();
        var routes = captured.GroupBy(item => item.Distribution, StringComparer.Ordinal).Select(group => group.ToArray()).ToArray();
        var results = await Task.WhenAll(routes.Select(ReadRouteAsync));
        var entries = results.SelectMany(result => result.Entries).ToDictionary(entry => entry.Reference.ProjectID, StringComparer.Ordinal);
        return new(captured.Where(reference => entries.ContainsKey(reference.ProjectID)).Select(reference => entries[reference.ProjectID]).ToArray(),
            results.All(result => result.Completed));

        async Task<WorkInFlightScanResult> ReadRouteAsync(CheckoutReference[] route)
        {
            var read = new List<CheckoutEntry>();
            if (!current()) return new([], false);
            IWorkInFlightEndpoint endpoint;
            try {
                endpoint = await endpoints(route[0].Distribution);
                if (!endpoint.Capabilities.Contains(CheckoutValidation.Capability, StringComparer.Ordinal))
                    throw new IOException("Checkout scanner capability is missing.");
            } catch (Exception error) when (error is IOException or InvalidOperationException or System.ComponentModel.Win32Exception) {
                if (!current()) return new([], false);
                var failures = route.Select(reference => Failure(reference, "runnerUnavailable")).ToArray();
                completedRoute?.Invoke(failures);
                return new(failures, true);
            }
            foreach (var reference in route) {
                cancellation.ThrowIfCancellationRequested();
                if (!current()) return new(read.ToArray(), false);
                var request = new CheckoutRequest(CheckoutCatalog.CardID, passToken, reference);
                CheckoutResult value;
                try {
                    value = await endpoint.ReadAsync(request, cancellation);
                    CheckoutValidation.ValidateResponse(value, request);
                } catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { throw; }
                catch (Exception error) when (error is IOException or InvalidOperationException or OperationCanceledException or System.ComponentModel.Win32Exception) {
                    // No qualified receipt means this pass is incomplete. Preserve earlier
                    // physical reads, never replay the lost read or invent later outcomes.
                    return new(read.ToArray(), false);
                }
                read.Add(new(reference, value));
            }
            var completed = read.ToArray(); completedRoute?.Invoke(completed);
            return new(completed, true);
        }

        CheckoutEntry Failure(CheckoutReference reference, string code) => new(reference,
            new(CheckoutCatalog.CardID, passToken, reference.ProjectID, reference.Path, DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                null, new("status", code), []));
    }
}
