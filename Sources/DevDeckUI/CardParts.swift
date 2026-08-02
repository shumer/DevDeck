import SwiftUI

/// Pieces shared by every card that fronts a local project.
///
/// Arc and DDEV cards are the same shape — links, a state line, the checked out branch, a row
/// of controls — and differ only in what fills them. Keeping the pieces here is what stops the
/// two drifting apart every time a padding is adjusted.

/// A link chip.
public struct CardChip: View {
    private let label: String
    private let color: Color
    private let isDimmed: Bool
    private let help: String
    private let action: () -> Void

    public init(
        _ label: String,
        color: Color,
        isDimmed: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.color = color
        self.isDimmed = isDimmed
        self.help = help
        self.action = action
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isDimmed ? color.opacity(0.45) : color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(isDimmed ? 0.07 : 0.15), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .clickable(cornerRadius: 7, isEnabled: !isDimmed)
            .onTapGesture(perform: action)
            .help(help)
    }
}

/// One of the controls along the bottom of a project card. They share the row's width, so the
/// row lines up with the footer beneath it.
public struct CardActionButton: View {
    private let title: String
    private let tint: Color
    private let isEnabled: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        tint: Color = DeckTheme.value,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.tint = tint
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(isEnabled ? tint : tint.opacity(0.3))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            // A resting fill, not just a hairline border: on glass a bare outline reads as a
            // label rather than as something to press.
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(isEnabled ? 0.1 : 0.03)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isEnabled ? tint.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .clickable(cornerRadius: 8, isEnabled: isEnabled)
            .onTapGesture { if isEnabled { action() } }
    }
}

/// The rule between the links and the state below them.
///
/// A real element with its own padding rather than an overlay: as an overlay it was anchored
/// to the row beneath and every attempt to give it room pushed it further into the chips.
public struct CardSeparator: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(DeckTheme.faint)
            .frame(height: 1)
            .padding(.top, 12)
    }
}

/// The state line: a coloured dot, what is going on, and an optional note on the right.
public struct CardStateRow: View {
    private let color: Color
    private let text: String
    private let isProminent: Bool
    private let trailing: String?
    private let help: String

    public init(color: Color, text: String, isProminent: Bool, trailing: String? = nil, help: String) {
        self.color = color
        self.text = text
        self.isProminent = isProminent
        self.trailing = trailing
        self.help = help
    }

    public var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(isProminent ? DeckTheme.value : DeckTheme.label)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DeckTheme.label)
                    .fixedSize()
            }
        }
        .padding(.top, 10)
        .help(help)
    }
}

/// The checked out branch, on its own line.
///
/// It gets a line to itself because branch names are routinely longer than the state text
/// beside them, and "is it running" must not be the thing that gets truncated.
public struct CardBranchRow: View {
    private let branch: String

    public init(_ branch: String) {
        self.branch = branch
    }

    public static let height: Double = 18

    public var body: some View {
        HStack(spacing: 8) {
            Text("⎇")
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.label)
            Text(branch)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(DeckTheme.blue)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .help("checked out branch")
    }
}
