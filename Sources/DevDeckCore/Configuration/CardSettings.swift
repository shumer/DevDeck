import Foundation

/// User preference for a single card: shown or hidden, and where it sits in the deck.
public struct CardSetting: Codable, Sendable, Equatable {
    public var id: CardID
    public var isEnabled: Bool

    public init(id: CardID, isEnabled: Bool) {
        self.id = id
        self.isEnabled = isEnabled
    }
}

/// Ordered list of card preferences. Array order is display order.
///
/// The list is merged with `CardCatalog` on every read, so cards added in a newer build appear
/// with their default visibility instead of silently disappearing for existing users.
public struct CardLayout: Codable, Sendable, Equatable {
    public var settings: [CardSetting]

    public init(settings: [CardSetting] = []) {
        self.settings = settings
    }

    public static var `default`: CardLayout {
        CardLayout(settings: CardCatalog.all.map { CardSetting(id: $0.id, isEnabled: $0.isEnabledByDefault) })
    }

    /// Known cards in display order, which is the catalog's order.
    ///
    /// The stored settings say only whether a card is shown, never where it sits. They used to
    /// carry the order as well, and that order was an accident: a card was appended the first
    /// time it was switched on, so the deck ended up in the sequence the projects happened to be
    /// added in, and "Tidy panels" laid them out that way - which is why tidying read as
    /// scrambling. Order belongs to the catalog, where it can be a rule someone chose.
    public func resolved(catalog: [CardDescriptor] = CardCatalog.all) -> [ResolvedCard] {
        let stored = Dictionary(
            settings.map { ($0.id, $0.isEnabled) },
            uniquingKeysWith: { first, _ in first }
        )
        return catalog.map { descriptor in
            ResolvedCard(
                descriptor: descriptor,
                isEnabled: stored[descriptor.id] ?? descriptor.isEnabledByDefault
            )
        }
    }

    /// Cards that should actually be rendered and refreshed.
    public func visibleCards(catalog: [CardDescriptor] = CardCatalog.all) -> [ResolvedCard] {
        resolved(catalog: catalog).filter { $0.isEnabled && $0.descriptor.isImplemented }
    }

    public func isEnabled(_ id: CardID, catalog: [CardDescriptor] = CardCatalog.all) -> Bool {
        resolved(catalog: catalog).first { $0.id == id }?.isEnabled ?? false
    }

    public mutating func setEnabled(_ isEnabled: Bool, for id: CardID) {
        if let index = settings.firstIndex(where: { $0.id == id }) {
            settings[index].isEnabled = isEnabled
        } else {
            settings.append(CardSetting(id: id, isEnabled: isEnabled))
        }
    }

}

/// A catalog entry combined with the user's preference for it.
public struct ResolvedCard: Sendable, Equatable {
    public let descriptor: CardDescriptor
    public let isEnabled: Bool

    public init(descriptor: CardDescriptor, isEnabled: Bool) {
        self.descriptor = descriptor
        self.isEnabled = isEnabled
    }

    public var id: CardID { descriptor.id }
}
