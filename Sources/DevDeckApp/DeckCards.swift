import ArcKit
import DDEVKit
import DevDeckCore
import ProjectKit

/// The cards this deck can show, and which of them it is showing.
///
/// The built-in cards plus one per configured project, in the order the deck is laid out: Arc,
/// then DDEV, then the plain ones, each group alphabetical. See `CardCatalog.projectOrder`. Read
/// fresh every time, so a project added in settings is in the list the moment it is asked for.
@MainActor
final class DeckCards {
    private let preferences: Preferences
    private let projectsStore: ArcProjectsStore
    private let ddevProjectsStore: DDEVProjectsStore
    private let localProjectsStore: LocalProjectsStore

    init(
        preferences: Preferences,
        projectsStore: ArcProjectsStore,
        ddevProjectsStore: DDEVProjectsStore,
        localProjectsStore: LocalProjectsStore
    ) {
        self.preferences = preferences
        self.projectsStore = projectsStore
        self.ddevProjectsStore = ddevProjectsStore
        self.localProjectsStore = localProjectsStore
    }

    var catalog: [CardDescriptor] {
        let arc = projectsStore.projects().map { project in
            CardDescriptor(
                id: project.cardID,
                title: project.title,
                subtitle: "Arc · \(project.organization)",
                isImplemented: true,
                isEnabledByDefault: true
            )
        }
        let ddev = ddevProjectsStore.projects().map { project in
            CardDescriptor(
                id: project.cardID,
                title: project.displayTitle,
                subtitle: "DDEV · \(project.name)",
                isImplemented: true,
                isEnabledByDefault: true
            )
        }
        let plain = localProjectsStore.projects().map { project in
            CardDescriptor(
                id: project.cardID,
                title: project.displayTitle,
                subtitle: project.startCommand.isEmpty ? "Project" : "Project · \(project.startCommand)",
                isImplemented: true,
                isEnabledByDefault: true
            )
        }
        return CardCatalog.all(
            including: CardCatalog.projectOrder(arc: arc, ddev: ddev, plain: plain)
        )
    }

    /// Every card with its switch, in deck order.
    var resolved: [ResolvedCard] {
        preferences.cardLayout.resolved(catalog: catalog)
    }

    /// The cards that should be on screen, in deck order.
    var visible: [CardID] {
        preferences.cardLayout.visibleCards(catalog: catalog).map(\.id)
    }

    /// Which kind of project a card is for, so a menu can group them. Nil for a built-in card.
    enum ProjectKind {
        case arc, ddev, plain
    }

    func projectKind(of card: CardID) -> ProjectKind? {
        if projectsStore.project(forCard: card) != nil { return .arc }
        if ddevProjectsStore.project(forCard: card) != nil { return .ddev }
        if localProjectsStore.project(forCard: card) != nil { return .plain }
        return nil
    }

    func setEnabled(_ isEnabled: Bool, for card: CardID) {
        var layout = preferences.cardLayout
        layout.setEnabled(isEnabled, for: card)
        preferences.cardLayout = layout
    }

    func isEnabled(_ card: CardID) -> Bool {
        preferences.cardLayout.isEnabled(card, catalog: catalog)
    }
}
