using System.Diagnostics.CodeAnalysis;
using System.Text;
using System.Text.Json;

namespace DevDeck.Windows.Core;

/// A read target is captured provenance, never permission to access a credential.
public static class InboxReadValidation
{
    public const string Capability = "attention.inboxReadTarget";
    private static readonly string[] PersonalReasons = ["securityAlert", "reviewRequested", "mention", "teamMention", "assigned"];

    public static string Identity(string accountID, string threadID) =>
        $"inbox:{Encoding.UTF8.GetByteCount(accountID)}:{accountID}:{Encoding.UTF8.GetByteCount(threadID)}:{threadID}";

    public static void Validate(InboxReadTarget? target, RemoteRequest? request, RemoteSnapshot? snapshot)
    {
        if (target is null || request is null || snapshot is null || request.Kind != "inbox" || snapshot.Kind != "inbox"
            || !Text(target.CardID, 128) || !Text(target.AccountID, 128) || !Thread(target.ThreadID) || !Endpoint(target.Endpoint)
            || target.CardID != request.CardID || target.CardID != snapshot.CardID || request.Accounts is null || snapshot.Rows is null) Invalid();
        var accounts = request!.Accounts.Where(account => account is not null && account.Id == target!.AccountID).ToArray();
        if (accounts.Length != 1 || accounts[0].Endpoint != target!.Endpoint || !Endpoint(accounts[0].Endpoint)) Invalid();
        var rows = snapshot!.Rows.Where(row => row is not null && row.AccountID == target!.AccountID && row.Id == target.ThreadID).ToArray();
        if (rows.Length != 1 || !rows[0].IsUnread || !PersonalReasons.Contains(rows[0].Detail, StringComparer.Ordinal)) Invalid();
    }

    public static void ValidateSnapshot(AttentionSnapshot snapshot, RemoteRequest request, RemoteSnapshot remote) =>
        AttentionValidation.Validate(snapshot, "", "remote.snapshot", null, request, remote);

    internal static void ValidateItem(AttentionItem item, RemoteRequest? request, RemoteSnapshot? snapshot)
    {
        if (item.InboxRead is not { } target) return;
        Validate(target, request, snapshot);
        var row = snapshot!.Rows.Single(row => row.AccountID == target.AccountID && row.Id == target.ThreadID);
        var expectedKey = row.Detail == "reviewRequested" && row.Url is not null ? "github:review:" + row.Url : item.Id;
        if (item.Tier != "waiting" || item.Mark != "github" || item.Dismissible || item.Id != Identity(target.AccountID, target.ThreadID)
            || item.Key != expectedKey
            || item.Action is not { } action || action.Kind is not ("open" or "none")
            || action.CardID is not null || action.Path is not null || action.Checkout is not null
            || action.Kind == "open" && (action.Service != "github" || action.AccountID != target.AccountID || action.Url != row.Url || row.Url is null)
            || action.Kind == "none" && (row.Url is not null || action.Url is not null || action.Service is not null || action.AccountID is not null)) Invalid();
    }

    public static void ValidateConsistency(AttentionSnapshot? top, AttentionSnapshot? nested)
    {
        if (top is null || nested is null) return;
        if (top.Items is null || nested.Items is null || top.Items.Any(item => item is null) || nested.Items.Any(item => item is null)) Invalid();
        foreach (var (source, other) in new[] { (top, nested), (nested, top) }) {
            foreach (var item in source.Items) {
                var matches = other.Items.Where(candidate => candidate.Id == item.Id).ToArray();
                if (item.InboxRead is not null && (source.Items.Count(candidate => candidate.Id == item.Id) != 1
                    || matches.Length != 1 || matches[0].InboxRead != item.InboxRead)
                    || matches.Any(candidate => candidate.InboxRead != item.InboxRead)) Invalid();
            }
        }
    }

    public static bool IsCurrent(DeckSettings settings, RemoteCardSettings capturedCard, RemoteSnapshot? snapshot, InboxReadTarget? target)
    {
        if (target is null || snapshot is null || capturedCard.Kind != "inbox" || capturedCard.Id != target.CardID || capturedCard.AccountIDs is null) return false;
        var matches = settings.RemoteCardList.Where(card => card.Id == capturedCard.Id).ToArray();
        if (matches.Length != 1) return false;
        var card = matches[0];
        if (!card.Enabled || card.Kind != "inbox" || card.AccountIDs is null || card.Distribution != capturedCard.Distribution
            || card.UseAllAccounts != capturedCard.UseAllAccounts || !card.AccountIDs.SequenceEqual(capturedCard.AccountIDs)
            || !settings.Workers.Any(worker => worker.Distribution == card.Distribution) || !card.AccountIDs.Contains(target.AccountID, StringComparer.Ordinal)) return false;
        var accounts = settings.AccountList.Where(account => account.Id == target.AccountID).ToArray();
        if (accounts.Length != 1 || !accounts[0].Enabled || accounts[0].Provider != "github" || accounts[0].Endpoint != target.Endpoint) return false;
        var account = accounts[0];
        try {
            Validate(target, new(card.Id, card.Kind, [new(account.Id, account.Label, account.Endpoint, account.Organizations, account.Repositories, null)]), snapshot);
            return true;
        } catch (WorkerException) { return false; }
    }

    // Preserve unrelated unknown JSON fields, while refusing a misplaced write target that
    // an ordinary DTO deserializer would silently discard (alerts, actions or checkout data).
    internal static void ValidateWirePlacement(ReadOnlyMemory<byte> frame, string operation, bool progress)
    {
        using var document = JsonDocument.Parse(frame);
        void Visit(JsonElement element, string path) {
            if (element.ValueKind == JsonValueKind.Object) {
                foreach (var property in element.EnumerateObject()) {
                    var name = property.Name.ToLowerInvariant();
                    if (name == "inboxread" && property.Value.ValueKind != JsonValueKind.Null
                        && (operation != "remote.snapshot" || progress || path is not ("attention.items[]" or "remote.signals.items[]"))) Invalid();
                    Visit(property.Value, path.Length == 0 ? name : path + "." + name);
                }
            } else if (element.ValueKind == JsonValueKind.Array) foreach (var value in element.EnumerateArray()) Visit(value, path + "[]");
        }
        Visit(document.RootElement, "");
    }

    private static bool Text(string? value, int limit) => !string.IsNullOrWhiteSpace(value) && Encoding.UTF8.GetByteCount(value) <= limit && !value.Any(char.IsControl);
    private static bool Thread(string? value) => value is { Length: >= 1 and <= 32 } && value.All(character => character is >= '0' and <= '9');
    private static bool Endpoint(string? value) => Text(value, 2048) && Uri.TryCreate(value, UriKind.Absolute, out var endpoint)
        && endpoint.Scheme == "https" && endpoint.Host.Length > 0 && endpoint.UserInfo.Length == 0 && endpoint.Query.Length == 0 && endpoint.Fragment.Length == 0;
    [DoesNotReturn] private static void Invalid() => throw new WorkerException("protocolMismatch", "Worker Inbox read target does not match its captured card, account or unread thread.");
}
