namespace DevDeck.Windows.Core;

// Applicable request fields are projected without changing the saved account or its scope.
public static class RemoteAccountApplicability
{
    public static bool HasGitHubScopes(string provider) => provider == "github";
    public static bool HasFailedRunPreference(string provider) => provider == "github";

    public static RemoteCredential Credential(RemoteAccountSettings account, string? token)
    {
        ArgumentNullException.ThrowIfNull(account);
        account.Validate();
        return new(account.Id, account.Label, account.Endpoint,
            HasGitHubScopes(account.Provider) ? account.Organizations.ToArray() : [],
            HasGitHubScopes(account.Provider) ? account.Repositories.ToArray() : [], token);
    }
}
