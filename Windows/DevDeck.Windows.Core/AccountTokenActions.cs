using System.Text;

namespace DevDeck.Windows.Core;

public sealed record TokenCreationDestination(string? Address, bool NeedsEnterpriseAddress);

// Pure link projection. It does not authorize credentials, validate an account draft or save metadata.
public static class AccountTokenActions
{
    private const int MaximumURLBytes = 2048;
    private const string HostedGitHubPage = "https://github.com/settings/personal-access-tokens/new";
    private const string GitLabPage = "/-/user_settings/personal_access_tokens?name=DevDeck&scopes=read_api";
    private const string InvalidMessage = "Choose a valid bounded HTTPS token page or provider endpoint.";
    private static readonly UTF8Encoding StrictUTF8 = new(false, true);

    public static TokenCreationDestination Creation(string provider, string endpoint)
    {
        if (provider is not ("github" or "gitlab")) throw Invalid();
        var admitted = Admit(endpoint);
        if (provider == "github") {
            // URI parsing resolves dot segments and may normalize authority spellings. Hosted mapping
            // additionally requires the exact original host spelling and a genuinely lexical root.
            var pathStart = endpoint.IndexOf('/', "https://".Length);
            var authority = pathStart < 0 ? endpoint["https://".Length..] : endpoint["https://".Length..pathStart];
            var root = pathStart < 0 || pathStart == endpoint.Length - 1;
            var hostedAuthority = authority.Equals("api.github.com", StringComparison.OrdinalIgnoreCase)
                || authority.Equals("api.github.com:443", StringComparison.OrdinalIgnoreCase);
            return hostedAuthority && root && admitted.IsDefaultPort
                && admitted.Host.Equals("api.github.com", StringComparison.OrdinalIgnoreCase)
                ? new(HostedGitHubPage, false) : new(null, true);
        }
        // Append to the complete admitted prefix rather than resolving an origin-relative URI.
        var address = admitted.AbsoluteUri.TrimEnd('/') + GitLabPage;
        _ = Admit(address, fixedGitLabQuery: true);
        return new(address, false);
    }

    public static string EnterpriseCreationAddress(string enteredAddress) => Admit(enteredAddress).AbsoluteUri;

    private static Uri Admit(string? value, bool fixedGitLabQuery = false)
    {
        if (string.IsNullOrEmpty(value) || value.Any(char.IsControl)
            || char.IsWhiteSpace(value[0]) || char.IsWhiteSpace(value[^1])
            || value.Contains('\\') || !value.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
            || !WithinBudget(value) || !EscapesValid(value)
            || !Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != "https"
            || uri.Host.Length == 0 || uri.Port <= 0 || uri.UserInfo.Length != 0 || value.Contains('#')
            || (!fixedGitLabQuery && value.Contains('?'))
            || fixedGitLabQuery && uri.Query != "?name=DevDeck&scopes=read_api"
            || !WithinBudget(uri.AbsoluteUri)) throw Invalid();
        var authorityEnd = value.IndexOf('/', "https://".Length);
        var authority = authorityEnd < 0 ? value["https://".Length..] : value["https://".Length..authorityEnd];
        if (authority.Length == 0 || authority.Contains('@')) throw Invalid();
        // Accepted local-action strictness: do not accept an encoded control which becomes a
        // control when decoded. This does not change old account/settings URL admission.
        if (Uri.UnescapeDataString(value).Any(char.IsControl)) throw Invalid();
        return uri;
    }

    private static bool WithinBudget(string value)
    {
        try { return StrictUTF8.GetByteCount(value) <= MaximumURLBytes; }
        catch (EncoderFallbackException) { return false; }
    }

    private static bool EscapesValid(string value)
    {
        for (var index = 0; index < value.Length; index++) {
            if (value[index] != '%') continue;
            if (index + 2 >= value.Length || !char.IsAsciiHexDigit(value[index + 1])
                || !char.IsAsciiHexDigit(value[index + 2])) return false;
            index += 2;
        }
        return true;
    }

    private static InvalidDataException Invalid() => new(InvalidMessage);
}
