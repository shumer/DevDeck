using System;
using System.Threading;
using System.Threading.Tasks;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed partial class DeckController
{
    // Owned native checks can capture the real request without a vault or provider.
    // Normal controllers leave both dependencies absent.
    internal Func<RemoteAccountSettings,string?>? RemoteTokenReader { get; set; }
    internal Func<string,string,RemoteRequest,CancellationToken,Task<WorkerResponse>>? RemoteRequestSender { get; set; }
}
