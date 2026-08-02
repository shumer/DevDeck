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

    /// Known cards in display order, with unknown identifiers dropped and new cards appended.
    public func resolved(catalog: [CardDescriptor] = CardCatalog.all) -> [ResolvedCard] {
        var seen = Set<CardID>()
        var result: [ResolvedCard] = []

        for setting in settings {
            guard let descriptor = catalog.first(where: { $0.id == setting.id }) else { continue }
            guard seen.insert(setting.id).inserted else { continue }
            result.append(ResolvedCard(descriptor: descriptor, isEnabled: setting.isEnabled))
        }

        for descriptor in catalog where !seen.contains(descriptor.id) {
            result.append(ResolvedCard(descriptor: descriptor, isEnabled: descriptor.isEnabledByDefault))
        }

        return result
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

    public mutating func move(_ id: CardID, to index: Int) {
        guard let current = settings.firstIndex(where: { $0.id == id }) else { return }
        let setting = settings.remove(at: current)
        settings.insert(setting, at: min(max(index, 0), settings.count))
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
