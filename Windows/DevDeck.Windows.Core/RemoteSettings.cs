using System.Security.Cryptography;
using System.Text;

namespace DevDeck.Windows.Core;

// Tokens have no representation in persisted deck settings.
[System.Text.Json.Serialization.JsonUnmappedMemberHandling(System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow)]
public sealed record RemoteAccountSettings(string Id, string Label, string Provider, string Endpoint, string[] Organizations, string[] Repositories, bool Enabled = true,
    string Browser = "system", string? BrowserProfile = null, bool NotifiesReviewRequests = true, bool NotifiesBlocked = false, bool NotifiesFailedRuns = false)
{
    public void Validate()
    {
        if (string.IsNullOrWhiteSpace(Id) || Encoding.UTF8.GetByteCount(Id) > 128 || Id.Any(char.IsControl) || string.IsNullOrWhiteSpace(Label)
            || Encoding.UTF8.GetByteCount(Label) > 256 || Label.Any(char.IsControl)
            || Provider is not ("github" or "gitlab") || Organizations is null || Repositories is null
            || !BrowserLaunch.Choices.Contains(Browser) || BrowserProfile?.Any(char.IsControl) == true || BrowserProfile?.Length > 256
            || !Uri.TryCreate(Endpoint, UriKind.Absolute, out var endpoint) || endpoint.Scheme != "https"
            || endpoint.UserInfo.Length > 0 || endpoint.Query.Length > 0 || endpoint.Fragment.Length > 0)
            throw new InvalidDataException("Account requires a stable ID, provider and HTTPS endpoint.");
    }
    // Bind credentials to endpoint and provider; changing a host never silently forwards an old token.
    public string CredentialTarget => "DevDeck/account/" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Provider + "\n" + Id + "\n" + Endpoint)));
}
public sealed record RemoteCardSettings(string Id, string Title, string Kind, string Distribution, string[] AccountIDs, bool Enabled = true, double X = 48, double Y = 80, bool Collapsed = false, bool UseAllAccounts = false)
{
    public void Validate(DeckSettings settings)
    {
        var provider = Kind == "mergeRequests" ? "gitlab" : "github";
        if (string.IsNullOrWhiteSpace(Id) || Id.Length > 128 || Id.Any(char.IsControl) || string.IsNullOrWhiteSpace(Title)
            || Kind is not ("pullRequests" or "inbox" or "actions" or "mergeRequests") || AccountIDs is null || (Enabled && AccountIDs.Length == 0 && !UseAllAccounts)
            || AccountIDs.Distinct(StringComparer.Ordinal).Count() != AccountIDs.Length
            || !AccountIDs.All(id => settings.AccountList.Any(account => account.Id == id && account.Provider == provider))
            || !settings.Workers.Any(worker => worker.Distribution == Distribution) || !double.IsFinite(X) || !double.IsFinite(Y))
            throw new InvalidDataException("Remote card has invalid accounts, distribution or placement.");
    }
}
