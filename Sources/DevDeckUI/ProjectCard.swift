import AppKit
import DevDeckCore
import DevDeckEngine
import SwiftUI

/// An Arc, DDEV or plain project: draws `DeckProjectCardModel`, which the engine has already
/// decided.
public struct ProjectCard: View {
    private let model: DeckProjectCardModel
    private let onCommand: (DeckCommand) -> Void
    // A stored `State` rather than `@State`; see `ClickableHighlight` for why. Whether the phone
    // popover is open is the view's own business: nothing else needs to know.
    private var _isShowingPhone = State(initialValue: false)
    private var isShowingPhone: Bool {
        get { _isShowingPhone.wrappedValue }
        nonmutating set { _isShowingPhone.wrappedValue = newValue }
    }

    public init(model: DeckProjectCardModel, onCommand: @escaping (DeckCommand) -> Void = { _ in }) {
        self.model = model
        self.onCommand = onCommand
    }

    public nonisolated static func size(for model: DeckProjectCardModel) -> CGSize {
        guard !model.isCollapsed else {
            return CGSize(width: CardMetrics.width, height: CollapsedCardMetrics.height)
        }
        return CGSize(
            width: CardMetrics.width,
            height: ProjectCardMetrics.height(
                tools: model.tools.map(\.label),
                environments: model.environments.map(\.label),
                hasBranch: model.meta.branch != nil,
                hasMetaRow: true
            )
        )
    }

    public var body: some View {
        if model.isCollapsed {
            CardCollapsedRow(model.collapsed, onCommand: onCommand)
        } else {
            CardChrome(title: model.title, glyph: model.mark.glyph, timestamp: model.timestamp, toggles: toggles) {
                CardHeroRow(
                    color: model.hero.tone.color,
                    tone: model.hero.tone.stateTone,
                    text: model.hero.text,
                    note: model.hero.note,
                    help: model.hero.help
                )
                CardMetaBlock(model.meta, onCommand: onCommand)
                ProjectChipRow(tools: model.tools, environments: model.environments, onCommand: onCommand)
                CardActionRow(model.actions.map { CardAction($0, onCommand: onCommand) })
                Spacer(minLength: 0)
            }
        }
    }

    /// The log window, and the phone.
    private var toggles: [CardHeaderToggle] {
        var toggles = [CardHeaderToggle(id: "log", isOn: model.header.logIsOn, help: model.header.logHelp) {
            onCommand(model.header.log)
        }]
        if let phoneURL = model.header.phoneURL {
            toggles.append(CardHeaderToggle(
                id: "phone",
                isOn: isShowingPhone,
                systemImage: "qrcode",
                help: model.header.phoneHelp,
                popover: AnyView(PhoneSheet(url: phoneURL, onCopy: copyToPasteboard)),
                dismiss: { isShowingPhone = false }
            ) { isShowingPhone.toggle() })
        }
        return toggles
    }

    /// Puts the address where a phone cannot reach: the Mac's own pasteboard, for sending it on
    /// in a message when a camera is not to hand.
    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        isShowingPhone = false
    }
}
