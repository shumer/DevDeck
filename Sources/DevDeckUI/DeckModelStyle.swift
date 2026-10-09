import DevDeckCore
import DevDeckEngine
import SwiftUI

// How the Mac draws what a card model says. The model decides the tone, the mark and what an
// icon means; these are the only places that turn them into a colour, a vector and a symbol.

public extension DeckTone {
    var color: Color {
        switch self {
        case .good: return DeckTheme.green
        case .attention: return DeckTheme.amber
        case .alert: return DeckTheme.red
        case .neutral: return DeckTheme.label
        case .personal: return DeckTheme.violet
        }
    }

    /// How a folded row's dot and note carry it: amber and red both ask to be caught.
    var stateTone: CardStateTone {
        switch self {
        case .good: return .good
        case .attention, .alert, .personal: return .alert
        case .neutral: return .neutral
        }
    }
}

public extension DeckMark {
    var glyph: CardGlyph? { CardGlyph(rawValue: rawValue) }
}

public extension DeckGlyph {
    var systemImage: String {
        switch self {
        case .review: return "eye"
        case .openExternal: return "arrow.up.forward"
        }
    }
}

public extension StatusPill {
    init(_ model: DeckPillModel) {
        self.init(model.text, color: model.tone.color)
    }
}

public extension CardFooter {
    init(_ model: DeckFooterModel) {
        self.init(leading: model.leading, trailing: model.trailing, isStale: model.isStale)
    }
}

public extension CardCollapsedRow {
    init(_ model: DeckCollapsedModel, onCommand: @escaping (DeckCommand) -> Void) {
        self.init(
            glyph: model.mark?.glyph,
            title: model.title,
            note: model.note,
            tone: model.tone.stateTone,
            color: model.tone.color,
            actions: model.actions.map { action in
                CardAction(
                    action.title,
                    systemImage: action.glyph?.systemImage,
                    isEnabled: action.isEnabled,
                    action: { onCommand(action.command) }
                )
            },
            help: model.help
        )
    }
}

/// What a card shows before its first answer, from its model.
public struct CardPlaceholderView: View {
    private let model: DeckPlaceholderModel

    public init(_ model: DeckPlaceholderModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 8)
            Text(model.message)
                .font(.system(size: 13))
                .foregroundStyle(model.isFailure ? DeckTheme.red : DeckTheme.label)
            if let hint = model.hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(DeckTheme.label)
            }
            Spacer(minLength: 8)
        }
    }
}

/// The row that grows and shrinks a list, from its model.
public struct CardExpanderView: View {
    private let model: DeckExpanderModel
    private let onCommand: (DeckCommand) -> Void

    public init(_ model: DeckExpanderModel, onCommand: @escaping (DeckCommand) -> Void) {
        self.model = model
        self.onCommand = onCommand
    }

    public var body: some View {
        Text(model.label)
            .font(.system(size: 11))
            .foregroundStyle(DeckTheme.label)
            .frame(maxWidth: .infinity)
            .padding(.top, 5)
            .padding(.bottom, 1)
            .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1) }
            .contentShape(Rectangle())
            .clickable()
            .onTapGesture { onCommand(model.command) }
    }
}
