import ArcKit
import DDEVKit
import DevDeckCore
import Foundation
import ProjectKit

/// The cards this deck can show, and which of them it is showing.
///
/// The built-in cards plus one per configured project, Arc first, then DDEV, then plain projects,
/// which is the order the deck is laid out in. Read fresh every time, so a project added in
/// settings is in the list the moment it is asked for.
public struct DeckCardList: Sendable {
    /// A menu group: one kind of project.
    public struct Group: Sendable, Equatable {
        public let title: String
        public let cards: [CardID]
    }

    private let preferences: Preferences
    private let arc: [CardDescriptor]
    private let ddev: [CardDescriptor]
    private let local: [CardDescriptor]

    public init(
        preferences: Preferences,
        arcProjects: [ArcProject],
        ddevProjects: [DDEVProject],
        localProjects: [LocalProject]
    ) {
        self.preferences = preferences
        arc = CardCatalog.sortedByTitle(arcProjects.map {
            CardDescriptor(id: $0.cardID, title: $0.title, subtitle: "Arc · \($0.organization)", isImplemented: true, isEnabledByDefault: true)
        })
        ddev = CardCatalog.sortedByTitle(ddevProjects.map {
            CardDescriptor(id: $0.cardID, title: $0.displayTitle, subtitle: "DDEV · \($0.name)", isImplemented: true, isEnabledByDefault: true)
        })
        local = CardCatalog.sortedByTitle(localProjects.map {
            CardDescriptor(
                id: $0.cardID,
                title: $0.displayTitle,
                subtitle: $0.startCommand.isEmpty ? L("project.section.project") : "\(L("project.section.project")) · \($0.startCommand)",
                isImplemented: true,
                isEnabledByDefault: true
            )
        })
    }

    public var catalog: [CardDescriptor] {
        CardCatalog.all(including: arc + ddev + local)
    }

    /// Every card with its switch, in deck order.
    public var resolved: [ResolvedCard] {
        preferences.cardLayout.resolved(catalog: catalog)
    }

    /// The cards that should be on screen, in deck order.
    public var visible: [CardID] {
        preferences.cardLayout.visibleCards(catalog: catalog).map(\.id)
    }

    /// The project groups, in deck order, so a menu keeps project kinds apart. A built-in card
    /// belongs to none.
    public var groups: [Group] {
        [
            Group(title: L("menu.group.arc"), cards: arc.map(\.id)),
            Group(title: L("menu.group.ddev"), cards: ddev.map(\.id)),
            Group(title: L("menu.group.projects"), cards: local.map(\.id)),
        ]
    }

    /// Whether the card is a DDEV project's, for the one menu item that is about the kind.
    public func isDDEV(_ card: CardID) -> Bool {
        ddev.contains { $0.id == card }
    }

    public func setEnabled(_ isEnabled: Bool, for card: CardID) {
        var layout = preferences.cardLayout
        layout.setEnabled(isEnabled, for: card)
        preferences.cardLayout = layout
    }

    public func isEnabled(_ card: CardID) -> Bool {
        preferences.cardLayout.isEnabled(card, catalog: catalog)
    }
}
