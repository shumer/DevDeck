using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

// Endpoint binding for explicit stored-token verification, separate from card sessions.
internal sealed record StoredTokenVerifier(
    WorkerSettings Route,
    Func<RemoteAccountSettings, string, CancellationToken, Task> VerifyAsync);

internal sealed partial class DeckController
{
    internal bool IsSettingsOwnerCurrent(SettingsWindow owner) =>
        !closing && !shuttingDown && ReferenceEquals(settingsWindow, owner);

    internal async Task<StoredTokenVerifier> AcquireStoredTokenVerifierAsync(
        WorkerSettings capturedRoute, CancellationToken cancellation)
    {
        void AdmitRoute()
        {
            cancellation.ThrowIfCancellationRequested();
            if (closing || shuttingDown || !Settings.Workers.Contains(capturedRoute))
                throw new OperationCanceledException(cancellation);
        }
        AdmitRoute();
        // GetExactAsync's hello is bounded by WorkerClient. No configuration discovery,
        // persistence, card-session adoption or refresh is performed here.
        var worker = await settingsChecks.GetExactAsync(capturedRoute, remote: true);
        AdmitRoute();
        return new(capturedRoute, async (account, value, token) => {
            token.ThrowIfCancellationRequested(); AdmitRoute();
            if (!Settings.AccountList.Any(current => current.Id == account.Id
                && current.Provider == account.Provider && current.Endpoint == account.Endpoint
                && current.CredentialTarget == account.CredentialTarget))
                throw new OperationCanceledException(token);
            var credential = RemoteAccountApplicability.Credential(account, value);
            _ = await worker.CallAsync("remote.verify", timeout: TimeSpan.FromMinutes(3), cancellation: token,
                remote: new("verify", account.Provider == "gitlab" ? "mergeRequests" : "pullRequests", [credential]));
            token.ThrowIfCancellationRequested(); AdmitRoute();
        });
    }
}
