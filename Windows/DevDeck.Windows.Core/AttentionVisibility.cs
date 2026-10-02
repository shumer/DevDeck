using System.Text;

namespace DevDeck.Windows.Core;

public sealed record LocalAttentionContext(string Distribution, long Revision, string[] ActiveProjectIDs);

/// Visibility changes delivery, while workers keep the state of already running jobs.
public static class AttentionVisibility
{
    public static string[] ProjectIDs(DeckSettings settings, string distribution) => settings.Cards
        .Where(card => card.Enabled && card.Project.HasLocalFolder && card.Project.Distribution == distribution)
        .Select(card => card.Project.Id).Order(StringComparer.Ordinal).ToArray();

    public static bool ValidProjectIDs(string[]? ids) => ids is null || ids.Length <= 1024
        && ids.All(id => !string.IsNullOrWhiteSpace(id) && Encoding.UTF8.GetByteCount(id) <= 128 && !id.Any(char.IsControl))
        && ids.Distinct(StringComparer.Ordinal).Count() == ids.Length;

    public static AttentionSnapshot? Filter(AttentionSnapshot snapshot, DeckSettings settings)
    {
        if (snapshot.Scope == CheckoutCatalog.CardID && settings.WorkInFlight is not null) {
            if (!settings.WorkInFlight.Enabled) return null;
            return snapshot with { Items = snapshot.Items.Where(item => CheckoutCatalog.CurrentTarget(settings, item.Action.Checkout)).ToArray(), Alerts = [] };
        }
        if (!snapshot.Scope.StartsWith("local:", StringComparison.Ordinal)) {
            var remote = settings.RemoteCardList.FirstOrDefault(card => card.Id == snapshot.Scope);
            return remote is not null && RemoteCardCatalog.Active(settings, remote) ? snapshot : null;
        }
        var distribution = snapshot.Scope[6..];
        var active = ProjectIDs(settings, distribution).ToHashSet(StringComparer.Ordinal);
        if (active.Count == 0) return snapshot with { Items = [], Alerts = [] };
        bool Visible(AttentionAction action) => action.CardID is { } id ? active.Contains(id)
            : action.Kind != "openTerminal" || settings.Cards.Any(card => active.Contains(card.Project.Id) && card.Project.Path == action.Path);
        return snapshot with {
            Items = snapshot.Items.Where(item => Visible(item.Action)).ToArray(),
            Alerts = snapshot.Alerts.Where(alert => Visible(alert.Target)).ToArray()
        };
    }

    public static bool RemoveAfterHide(string scope, DeckAlert alert, string id, string? distribution) => distribution is null
        ? scope == id : scope == "local:" + distribution && (alert.Target.CardID == id || alert.Source == "docker");
}
