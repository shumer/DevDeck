using System;
using System.Linq;
using System.Text.Json;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal enum SidebarProjectActivity { None, Running, Busy }

internal sealed partial class DeckController
{
    internal void NotifySidebarProjectPresentation(ProjectCard owner)
    {
        // A queued callback is only a hint. Revalidate the current physical owner
        // and full configured reference at the UI dispatch boundary.
        if (!application.Dispatcher.CheckAccess()) {
            application.Dispatcher.BeginInvoke(new Action(() => NotifySidebarProjectPresentation(owner)));
            return;
        }
        if (closing || shuttingDown || owner.SidebarOwnerClosed || settingsWindow?.IsVisible != true
            || !cards.Any(current => ReferenceEquals(current, owner))) return;
        var configured = Settings.Cards.FirstOrDefault(card => card.Project.Id == owner.Reference.Id);
        if (configured is null || owner.Latest is { } snapshot && snapshot.ProjectID != configured.Project.Id) return;
        var expected = configured.Project with { Title = configured.Title };
        var actual = owner.Reference with { Title = configured.Title };
        if (JsonSerializer.Serialize(actual, WorkerProtocol.Json) != JsonSerializer.Serialize(expected, WorkerProtocol.Json)) return;
        settingsWindow.ReconcileProjectSidebar(configured.Project.Id);
    }
}
