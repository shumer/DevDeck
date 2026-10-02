using System.Text;
using System.Text.RegularExpressions;

namespace DevDeck.Windows.Core;

public static class ProjectDetection
{
    public static bool ValidSubtitle(string? value) => value is null || Encoding.UTF8.GetByteCount(value) <= 512 && !value.Any(char.IsControl);
    public static bool ValidOpenURL(string? value) => value is null or "" || Encoding.UTF8.GetByteCount(value) <= 2048 && !value.Any(char.IsControl) && DeckSettings.ValidLink(new("Site",value));
    public static bool ValidSuggestion(ProjectSuggestion? value) => value is not null && value.Subtitle is not null && ValidSubtitle(value.Subtitle)
        && !string.IsNullOrWhiteSpace(value.StartCommand) && Encoding.UTF8.GetByteCount(value.StartCommand) <= 65536 && !value.StartCommand.Contains('\0')
        && value.StopCommand is not null && Encoding.UTF8.GetByteCount(value.StopCommand) <= 65536 && !value.StopCommand.Contains('\0')
        && value.HealthURL is not null && ValidOpenURL(value.HealthURL);

    public static ProjectReference Apply(ProjectReference project, ProjectSuggestion suggestion)
    {
        if (project.Kind != "local" || !ValidSuggestion(suggestion)) throw new InvalidDataException("Invalid local project suggestion.");
        return project with { StartCommand = suggestion.StartCommand, StopCommand = suggestion.StopCommand,
            HoldsProcess = suggestion.HoldsProcess, RequiresDocker = suggestion.RequiresDocker,
            Subtitle = string.IsNullOrEmpty(project.Subtitle) ? suggestion.Subtitle : project.Subtitle,
            HealthURL = string.IsNullOrEmpty(project.HealthURL) ? suggestion.HealthURL : project.HealthURL };
    }

    // Mirror the frozen ProjectKit.ProjectKind whole-word vocabulary and precedence.
    public static string Glyph(string? startCommand, string? subtitle)
    {
        var words = Regex.Matches((startCommand ?? "") + " " + (subtitle ?? ""),@"[\p{L}\p{N}]+")
            .Select(match => match.Value.ToLowerInvariant()).ToHashSet(StringComparer.Ordinal);
        foreach (var (kind,vocabulary) in new (string,string[])[] {
            ("docker",["docker","compose"]), ("next",["next","nextjs"]), ("nest",["nest","nestjs"]),
            ("bun",["bun","bunx"]), ("node",["npm","pnpm","yarn","node","vite","nuxt","astro","turbo","turborepo"]), ("make",["make"]) })
            if (vocabulary.Any(words.Contains)) return kind;
        return "other";
    }
}
