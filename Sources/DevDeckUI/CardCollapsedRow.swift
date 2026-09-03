import DevDeckCore
import SwiftUI

/// A whole card in one row.
///
/// What survives is what a glance is actually asking: the mark, the name, the state dot and one
/// action. What goes is the branch, the meta row, every chip, three of the four buttons and the
/// clock. That is the honest trade, and it is worth saying plainly: a collapsed card can tell
/// you something is wrong, it cannot tell you what. Opening it is one item in the panel's own
/// menu away.
///
/// The name is larger here than the title on a full card, at 12.5 points against 10.5 in caps.
/// With no hero line under it, the name *is* the card.
public struct CardCollapsedRow: View {
    private let glyph: CardGlyph?
    private let title: String
    private let note: String?
    private let tone: CardStateTone
    private let color: Color
    private let actions: [CardAction]
    private let help: String

    public init(
        glyph: CardGlyph?,
        title: String,
        note: String?,
        tone: CardStateTone,
        color: Color,
        actions: [CardAction] = [],
        help: String
    ) {
        self.glyph = glyph
        self.title = title
        self.note = note
        self.tone = tone
        self.color = color
        self.actions = actions
        self.help = help
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let glyph {
                CardGlyphView(glyph)
            }
            dot
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DeckTheme.value.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            // The note goes as soon as the row is carrying controls. It is detail rather than
            // state - `10 containers`, `pid 48213` - and the dot has already said good, busy or
            // off by colour. Keeping both leaves the name 91 points and truncates it.
            if let note, actions.count < 2 {
                Text(note)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tone == .alert ? color : DeckTheme.value.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize()
            }
            if !actions.isEmpty {
                HStack(spacing: Self.buttonSpacing) {
                    ForEach(actions) { action in
                        button(action)
                    }
                }
            }
        }
        .frame(height: CollapsedCardMetrics.rowHeight)
        .padding(.horizontal, CardChromeMetrics.horizontalPadding)
        .padding(.vertical, CollapsedCardMetrics.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .help(help)
    }

    /// The same dot as a full card, at the same size. It is the only thing in this row that is
    /// not smaller than it was, because it is the thing the row exists for.
    @ViewBuilder
    private var dot: some View {
        switch tone {
        case .neutral:
            Circle()
                .fill(DeckTheme.label.opacity(0.66))
                .frame(width: 9, height: 9)
        case .good, .alert:
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .background(
                    Circle()
                        .fill(color.opacity(tone == .alert ? 0.20 : 0.14))
                        .frame(width: 16, height: 16)
                )
        }
    }

    public nonisolated static let buttonSize: Double = 24
    public nonisolated static let buttonSpacing: Double = 4

    /// Icons, no labels. Which lifecycle action leads has already been decided by the state, the
    /// same way the full card's control row decides it. Four of them take 108 points of the 324
    /// a row has, which is what dropping the note pays for.
    private func button(_ action: CardAction) -> some View {
        Image(systemName: action.systemImage ?? "play.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(action.isEnabled ? action.tint : action.tint.opacity(0.28))
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(action.tint == DeckTheme.value
                        ? Color.white.opacity(action.isEnabled ? 0.07 : 0.03)
                        : action.tint.opacity(action.isEnabled ? 0.14 : 0.05))
            )
            .contentShape(Rectangle())
            .clickable(cornerRadius: 7, isEnabled: action.isEnabled)
            .onTapGesture { if action.isEnabled { action.action() } }
            .help(action.title)
    }
}
