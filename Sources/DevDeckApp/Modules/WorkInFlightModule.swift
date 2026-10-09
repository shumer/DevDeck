import AppKit
import DevDeckCore
import DevDeckEngine
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
        guard case .workInFlight(let model)? = controller.model(for: card) else { return AnyView(EmptyView()) }
        return AnyView(WorkInFlightCard(model: model, onCommand: context.perform))
    }

    func size(for card: CardID) -> NSSize {
        guard case .workInFlight(let model)? = controller.model(for: card) else { return .zero }
        return WorkInFlightCard.size(for: model)
    }
}
