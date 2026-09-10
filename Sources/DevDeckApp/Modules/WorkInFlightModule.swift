import AppKit
import DevDeckCore
import DevDeckUI
import SwiftUI

/// Every checkout at once: what is uncommitted, unpushed, behind, or has no remote.
@MainActor
final class WorkInFlightModule: CardModule {
    private let context: ModuleContext
    private var controller: DeckController { context.controller }

    init(context: ModuleContext) {
        self.context = context
    }

    func owns(_ card: CardID) -> Bool { card == .workInFlight }

    func view(for card: CardID) -> AnyView {
        AnyView(WorkInFlightCard(
            states: controller.checkouts,
            checkedAt: controller.checkoutsCheckedAt,
            isExpanded: controller.isExpanded(card),
            isCollapsed: controller.isCollapsed(card),
            onOpen: { [controller] in LocalFolder.openTerminal(controller.folder(forCheckout: $0)) },
            onToggleExpand: { [controller] in controller.toggleExpanded(card) }
        ))
    }

    func size(for card: CardID) -> NSSize {
        WorkInFlightCard.size(
            for: controller.checkouts,
            isExpanded: controller.isExpanded(card),
            isCollapsed: controller.isCollapsed(card)
        )
    }
}
