using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed partial class DeckController
{
    // Internal seams keep qualification inside owned fake providers and credentials.
    internal Func<RemoteAccountSettings,string?>? InboxTokenReader { get; set; }
    internal Func<RemoteCardSettings,RemoteRequest,CancellationToken,Action<string>?,Task>? InboxWriteSender { get; set; }
    internal Action<string>? AttentionSettingsOpener { get; set; }
    internal Action? AttentionDockerOpener { get; set; }
    internal Action<ProjectReference>? AttentionTerminalOpener { get; set; }
    internal Func<string,Task>? AttentionDismissReady { get; set; }
    internal Func<ProjectReference,string[],Task<WorkerResponse>>? AttentionDismissSender { get; set; }

    internal bool CanReadInboxAttention(RemoteCard owner, InboxReadTarget target) =>
        CanRefreshInboxOwner(owner,target)
        && InboxReadValidation.IsCurrent(Settings,owner.Configuration,owner.AuthorizationSnapshot,target);

    internal bool CanRefreshInboxOwner(RemoteCard owner,InboxReadTarget target)
    {
        if(closing || shuttingDown || owner.IsClosed || !owner.DeckVisible || !remoteCards.Contains(owner))return false;
        var captured=owner.Configuration;
        var current=Settings.RemoteCardList.FirstOrDefault(card=>card.Id==captured.Id);
        return current is{} && current.Id==target.CardID && current.Kind=="inbox" && captured.Kind=="inbox"
            && current.Distribution==captured.Distribution && current.UseAllAccounts==captured.UseAllAccounts
            && current.AccountIDs.SequenceEqual(captured.AccountIDs) && current.AccountIDs.Contains(target.AccountID)
            && RemoteCardCatalog.Active(Settings,current)
            && Settings.AccountList.Any(account=>account.Id==target.AccountID && account.Enabled && account.Provider=="github" && account.Endpoint==target.Endpoint);
    }

    internal async Task<bool> ExecuteAttentionChoiceAsync(AttentionItem item, AttentionChoice choice)
    {
        var expected = choice.Kind == "primary" ? AttentionChoices.Primary(item) : AttentionChoices.Alternate(item);
        if (!choice.Enabled || choice != expected) return false;
        switch (choice.Kind) {
            case "read":
                var owner = remoteCards.FirstOrDefault(card => card.CardID == choice.InboxRead!.CardID);
                return owner is not null && await owner.ReadAttentionAsync(choice.InboxRead!);
            case "dismiss":
                return await DismissAttentionAsync(item);
            case "primary":
                if (!CurrentAttentionPrimary(item.Action)) return false;
                await ExecuteAttentionAsync(item.Action); return true;
            default: return false;
        }
    }

    private bool CurrentAttentionPrimary(AttentionAction action) => !closing && !shuttingDown && (action.Kind switch {
        "open" => action.Url is not null && Settings.AccountList.Any(account => account.Enabled && account.Id==action.AccountID && account.Provider==action.Service),
        "accountSettings" => Settings.AccountList.Any(account => account.Id==action.AccountID && account.Provider==action.Service),
        "showCard" => Settings.Cards.Any(card => card.Project.Id==action.CardID),
        "openTerminal" => action.Checkout is{} target ? CheckoutCatalog.CurrentTarget(Settings,target)
            : Settings.Cards.Any(card => card.Enabled && card.Project.Path==action.Path),
        "startDocker" or "menu" or "update" => true,
        _ => false
    });

    internal void RemoveReadAttention(InboxReadTarget target)
    {
        attention.PruneScope(target.CardID,item => item.InboxRead!=target);
        UpdateAttentionIcon();
    }

    private AttentionSnapshot MaskPendingInboxRead(AttentionSnapshot snapshot)
    {
        var target = remoteCards.FirstOrDefault(card => card.CardID==snapshot.Scope)?.PendingInboxRead;
        return target is null ? snapshot : snapshot with { Items=snapshot.Items.Where(item => item.InboxRead!=target).ToArray() };
    }

    internal async Task<bool> SendInboxAttentionReadAsync(RemoteCard owner,InboxReadTarget target,CancellationToken cancellation,Action<string>? onProgress)
    {
        await actions.WaitAsync(cancellation);
        try {
            cancellation.ThrowIfCancellationRequested();
            if (!CanReadInboxAttention(owner,target)) return false;
            var account = Settings.AccountList.Single(account=>account.Id==target.AccountID);
            var credential = RemoteAccountApplicability.Credential(account,
                InboxTokenReader is{} read ? read(account) : Tokens.Read(account));
            var request = new RemoteRequest(target.CardID,"inbox",[credential],[target.ThreadID]);
            if (InboxWriteSender is{} sender) {
                if (!CanReadInboxAttention(owner,target)) return false;
                await sender(owner.Configuration,request,cancellation,onProgress);
            } else {
                var worker = await GetWorkerAsync(owner.Configuration.Distribution,remote:true);
                cancellation.ThrowIfCancellationRequested();
                if (!CanReadInboxAttention(owner,target)) return false;
                _ = await worker.CallAsync("remote.markRead",timeout:TimeSpan.FromMinutes(10),cancellation:cancellation,onProgress:onProgress,remote:request);
            }
            return true;
        } finally { actions.Release(); }
    }
}
