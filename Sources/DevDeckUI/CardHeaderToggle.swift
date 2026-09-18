import DevDeckCore
import SwiftUI

/// One of the small switches in a card's header: the log, and the QR code for a phone.
///
/// In the header rather than in the control row on purpose. Four buttons already need 311
/// points and the row has 303, so a fifth would shrink every one of them and undo the reason
/// the card is 352 points wide in the first place.
public struct CardHeaderToggle: Identifiable {
    public let id: String
    public let isOn: Bool
    public let isEnabled: Bool
    public let systemImage: String
    public let help: String
    public let action: () -> Void
    /// Shown hanging off the button while it is on. The log tray has none: it lives in the card.
    public let popover: AnyView?
    /// What closes the popover, rather than what toggles it: a dismissal can arrive twice
    /// before the card is drawn again, and a toggle run twice puts the popover back.
    public let dismiss: () -> Void

    public init(
        id: String = "log",
        isOn: Bool,
        isEnabled: Bool = true,
        systemImage: String = "text.alignleft",
        help: String,
        popover: AnyView? = nil,
        dismiss: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.systemImage = systemImage
        self.help = help
        self.popover = popover
        self.action = action
        self.dismiss = dismiss ?? action
    }

    public nonisolated static let width: Double = 20

    /// What the popover is bound to.
    ///
    /// A constant binding cannot be written back, so a popover closed by a click somewhere else
    /// left the card still believing it was open, and the next redraw - the click's own, if it
    /// landed on another button - opened it again. The dismissal has to reach the card, and the
    /// only thing that changes the card's mind is the toggle's own action.
    public func presentation() -> Binding<Bool> {
        Binding(
            get: { isOn && popover != nil },
            set: { isPresented in
                guard !isPresented, isOn, popover != nil else { return }
                dismiss()
            }
        )
    }
}

/// The last few lines the project is writing, on the card itself.
///
/// A card that can start something has to be able to show what that something said. The Logs
/// button used to open a file in Console, which answers the question and costs a context
/// switch; six lines in place answer it without one. It is not a terminal: no following, no
/// scrolling, no colour. The arrow opens the real log when six lines are not enough.
