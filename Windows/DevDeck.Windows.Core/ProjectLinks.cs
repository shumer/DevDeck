using System.Text.RegularExpressions;

namespace DevDeck.Windows.Core;

public sealed record PresentedProjectLink(ProjectLink Link, bool RequiresRunning);

public static class ProjectLinks
{
    public static string? TestTarget(CardSettings settings, ProjectStatus? status = null)
    {
        var project=settings.Project;
        var links=settings.LinkList.Select(link => Resolve(link,project,status)).OfType<ProjectLink>().ToArray();
        var site=project.Kind == "local" ? string.IsNullOrWhiteSpace(project.OpenURL) ? project.HealthURL : project.OpenURL : status?.SiteURL;
        if (site is null || !ProjectDetection.ValidOpenURL(site) || site.Length == 0) site=null;
        if (project.Kind == "local") return site ?? links.FirstOrDefault(link => link.EffectiveKind == "site")?.Url ?? links.FirstOrDefault()?.Url;
        if (project.Kind == "ddev") return (status?.ToolLinks ?? []).FirstOrDefault(link => DeckSettings.ValidLink(link) && link.Enabled
                && !settings.HiddenToolList.Contains(link.Label,StringComparer.OrdinalIgnoreCase))?.Url
            ?? links.FirstOrDefault(link => link.EffectiveKind == "tool")?.Url ?? site ?? links.FirstOrDefault(link => link.EffectiveKind == "site")?.Url;
        return links.FirstOrDefault()?.Url;
    }

    public static ProjectLink[] Defaults(string kind) => kind == "arc" ? [
        new("PageBuilder","https://{org}.arcpublishing.com/home/"),
        new("Composer","https://{org}.arcpublishing.com/composer"),
        new("Deployer","https://{org}.arcpublishing.com/deployments/fusion/"),
        new("Site Service","https://{org}.arcpublishing.com/developer/sites",false),
        new("Delivery API","https://api.{org}.arcpublishing.com/content/v4",false),
        new("Sandbox","",false,"site"), new("Prod","",false,"site")
    ] : [new("TEST","",false,"site"),new("UAT","",false,"site"),new("PROD","",false,"site")];

    public static ProjectLink[] Editable(CardSettings? settings, string kind)
    {
        if (settings is null) return Defaults(kind);
        var existing = settings.LinkList;
        if (kind == "arc" && settings.Project.Arc is not null) return existing;
        // Legacy switches become editable rows only when the user opens and edits this form.
        return existing.Concat(Defaults(kind).Where(link => !existing.Any(item => item.Label == link.Label))
            .Select(link => settings.HiddenToolList.Contains(link.Label,StringComparer.OrdinalIgnoreCase) ? link with { Enabled = false } : link)).ToArray();
    }

    public static bool ValidTemplate(ProjectLink? link)
    {
        if (link is null || string.IsNullOrWhiteSpace(link.Label) || link.Label.Length > 80 || link.Label.Any(char.IsControl)
            || link.Url is null || link.Url.Length > 2048 || link.Url.Any(char.IsControl) || link.Kind is not (null or "tool" or "site")) return false;
        if (link.Url.Length == 0) return !link.Enabled;
        var test = link.Url.Replace("{org}","sandbox.example",StringComparison.Ordinal)
            .Replace("{site}",link.Url.StartsWith("{site}",StringComparison.Ordinal) ? "https://example.test" : "example",StringComparison.Ordinal);
        return !test.Contains('{') && !test.Contains('}') && DeckSettings.ValidLink(link with { Url = test });
    }

    public static bool ValidArc(ArcOptions? arc)
    {
        if (arc is null) return true;
        return arc.Organization is not null && arc.Organization.Length <= 253
            && (arc.Organization.Length == 0 || arc.Organization.Split('.').All(label => Regex.IsMatch(label,@"^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$")))
            && (arc.Site is null || arc.Site.Length <= 128 && Regex.IsMatch(arc.Site,@"^[a-zA-Z0-9_-]*$"))
            && arc.LocalURL is not null && (arc.LocalURL.Length == 0 || DeckSettings.ValidLink(new("Local",arc.LocalURL)))
            && arc.HealthPath is not null && arc.HealthPath.Length <= 2048 && arc.HealthPath.StartsWith('/') && !arc.HealthPath.StartsWith("//",StringComparison.Ordinal)
            && !arc.HealthPath.Any(char.IsWhiteSpace) && !arc.HealthPath.Any(char.IsControl);
    }

    public static ProjectLink MigrateArc(ProjectLink link)
    {
        var replacement = link.Url switch {
            "https://{org}.arcpublishing.com/pagebuilder" or "https://sandbox.{org}.arcpublishing.com/home/" => "https://{org}.arcpublishing.com/home/",
            "https://sandbox.{org}.arcpublishing.com/composer/" => "https://{org}.arcpublishing.com/composer",
            "https://{org}.arcpublishing.com/developer" or "https://sandbox.{org}.arcpublishing.com/developer/" or "https://sandbox.{org}.arcpublishing.com/deployments/fusion/" => "https://{org}.arcpublishing.com/deployments/fusion/",
            "https://sandbox.{org}.arcpublishing.com/developer/sites/" => "https://{org}.arcpublishing.com/developer/sites",
            "https://api.sandbox.{org}.arcpublishing.com/content/v4" => "https://api.{org}.arcpublishing.com/content/v4",
            _ => link.Url
        };
        return link with { Url = replacement, Label = link.Label == "Dev Center" && replacement == "https://{org}.arcpublishing.com/deployments/fusion/" ? "Deployer" : link.Label };
    }

    public static ProjectLink? Resolve(ProjectLink link, ProjectReference project, ProjectStatus? status)
    {
        if (!link.Enabled || !ValidTemplate(link)) return null;
        var org = project.Arc?.Organization ?? "";
        var site = project.Kind == "arc" ? project.Arc?.Site ?? "" : (status?.SiteURL ?? (project.Kind == "local" ? string.IsNullOrWhiteSpace(project.OpenURL) ? project.HealthURL : project.OpenURL : null))?.TrimEnd('/') ?? "";
        if (link.Url.Contains("{org}",StringComparison.Ordinal) && org.Length == 0 || link.Url.Contains("{site}",StringComparison.Ordinal) && site.Length == 0) return null;
        var resolved = link with { Url = link.Url.Replace("{org}",org,StringComparison.Ordinal).Replace("{site}",site,StringComparison.Ordinal) };
        return DeckSettings.ValidLink(resolved) ? resolved : null;
    }

    public static PresentedProjectLink[] Present(CardSettings settings, ProjectStatus? status)
    {
        var result = settings.LinkList.Select(link => Resolve(link,settings.Project,status)).OfType<ProjectLink>()
            .Select(link => new PresentedProjectLink(link,LocalURL(link.Url))).ToList();
        if (status?.State == "running") result.AddRange((status.ToolLinks ?? []).Where(link => link.Enabled && !settings.HiddenToolList.Contains(link.Label,StringComparer.OrdinalIgnoreCase)
            && DeckSettings.ValidLink(link) && !result.Any(item => item.Link.Label == link.Label)).Select(link => new PresentedProjectLink(link,true)));
        return result.ToArray();
    }

    public static bool LocalURL(string value) => Uri.TryCreate(value,UriKind.Absolute,out var uri)
        && (uri.IsLoopback || uri.Host.Equals("localhost",StringComparison.OrdinalIgnoreCase) || uri.Host.EndsWith(".localhost",StringComparison.OrdinalIgnoreCase)
            || uri.Host.EndsWith(".ddev.site",StringComparison.OrdinalIgnoreCase));
}
