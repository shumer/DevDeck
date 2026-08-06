import SwiftUI

/// Pieces shared by every card that fronts a local project.
///
/// Arc, DDEV and plain project cards are the same shape — a state, some meta, links, controls —
/// and differ only in what fills them. Keeping the pieces here is what stops the three drifting
/// apart every time a padding is adjusted.

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

    public nonisolated static let height: Double = 20

    public var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(isDimmed ? color.opacity(0.45) : color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .background(color.opacity(isDimmed ? 0.07 : 0.14), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .clickable(cornerRadius: 6, isEnabled: !isDimmed)
            .onTapGesture(perform: action)
            .help(help)
    }
}

/// The upright rule between the tooling chips and the environment chips.
///
/// The two used to be rows of their own, which spent a row of height saying what a 12-point
/// line says: to the left is what you work in, to the right is the site itself.
public struct CardChipDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 12)
            .padding(.horizontal, 3)
    }
}

/// One of the controls along the bottom of a project card.
///
/// Not four equal slabs any more: the action that matters right now is wider, tinted and
/// bolder, and the rest recede to a hairline. They keep a resting fill regardless, because the
/// panels sit behind other windows where hover cannot be relied on to say "pressable".
public struct CardActionButton: View {
    private let title: String
    private let systemImage: String?
    private let tint: Color
    private let isEnabled: Bool
    private let isProminent: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        tint: Color = DeckTheme.value,
        isEnabled: Bool = true,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isEnabled = isEnabled
        self.isProminent = isProminent
        self.action = action
    }

    public nonisolated static let height: Double = 26

    private var isTinted: Bool { isProminent && tint != DeckTheme.value }

    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: isProminent ? 10 : 9.5, weight: .semibold))
            }
            Text(title)
                .font(.system(size: isProminent ? 11.5 : 10.5, weight: isProminent ? .semibold : .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isEnabled ? tint : tint.opacity(0.3))
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTinted
                    ? tint.opacity(isEnabled ? 0.16 : 0.04)
                    : Color.white.opacity(isEnabled ? 0.1 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .clickable(cornerRadius: 8, isEnabled: isEnabled)
        .onTapGesture { if isEnabled { action() } }
    }

    private var borderColor: Color {
        guard isEnabled else { return Color.white.opacity(0.08) }
        // The bright border belongs to the one action the card is offering; everything else
        // steps back so it stops competing.
        return isTinted ? tint.opacity(0.45) : Color.white.opacity(0.22)
    }
}

/// One entry in a card's control row.
public struct CardAction: Identifiable {
    public let title: String
    public let systemImage: String?
    public let tint: Color
    public let isEnabled: Bool
    public let isProminent: Bool
    public let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        tint: Color = DeckTheme.value,
        isEnabled: Bool = true,
        isProminent: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isEnabled = isEnabled
        self.isProminent = isProminent
        self.action = action
    }

    public var id: String { title }
}

/// The control row: the action that matters is half again as wide as the others.
///
/// The widths are computed rather than left to an equal division, because the ratio is the
/// whole point and the card's width is fixed and known.
public struct CardActionRow: View {
    private let actions: [CardAction]

    public init(_ actions: [CardAction]) {
        self.actions = actions
    }

    public nonisolated static let spacing: Double = 6
    public nonisolated static let topPadding: Double = 10
    public nonisolated static var height: Double { CardActionButton.height + topPadding }
    /// How much wider the prominent action is than a quiet one.
    public nonisolated static let prominentShare: Double = 1.5

    public var body: some View {
        let widths = Self.widths(for: actions)

        return HStack(spacing: Self.spacing) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                CardActionButton(
                    action.title,
                    systemImage: action.systemImage,
                    tint: action.tint,
                    isEnabled: action.isEnabled,
                    isProminent: action.isProminent,
                    action: action.action
                )
                .frame(width: widths[index])
            }
        }
        .padding(.top, Self.topPadding)
    }

    /// The row fills the card exactly, so its edges line up with the chips and the meta above.
    public nonisolated static func widths(for actions: [CardAction]) -> [Double] {
        guard !actions.isEmpty else { return [] }
        let units = actions.reduce(0.0) { $0 + ($1.isProminent ? prominentShare : 1) }
        let available = CardChromeMetrics.contentWidth - spacing * Double(actions.count - 1)
        return actions.map { (available / units) * ($0.isProminent ? prominentShare : 1) }
    }
}

/// The state of the thing the card is about, said as loudly as the card says anything.
///
/// This is the focal point: one glance answers "is it up", and everything else is detail for
/// after that question is settled. It replaced a 12.5-point line that looked exactly like the
/// three lines around it.
public struct CardHeroRow: View {
    private let color: Color
    private let text: String
    private let note: String?
    private let help: String

    public init(color: Color, text: String, note: String? = nil, help: String) {
        self.color = color
        self.text = text
        self.note = note
        self.help = help
    }

    public nonisolated static let height: Double = 24
    public nonisolated static let topPadding: Double = 9

    public var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(text)
                .font(.system(size: 20, weight: .semibold))
                .kerning(-0.35)
                .foregroundStyle(isQuiet ? DeckTheme.value.opacity(0.72) : DeckTheme.value)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if let note {
                Text(note)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(DeckTheme.value.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: Self.height)
        .padding(.top, Self.topPadding)
        .help(help)
    }

    /// A card that is simply off should not shout it; one that is broken or busy should.
    private var isQuiet: Bool { color == DeckTheme.label }
}

/// The quiet block under the hero: the branch, then whatever names this checkout.
///
/// The branch keeps a line of its own — branch names are routinely longer than anything beside
/// them, and "which branch is this" must not be the thing that gets truncated.
public struct CardMetaBlock: View {
    private let branch: String?
    private let leading: String?
    private let trailing: String?

    public init(branch: String?, leading: String?, trailing: String? = nil) {
        self.branch = branch
        self.leading = leading
        self.trailing = trailing
    }

    public nonisolated static let branchHeight: Double = 15
    public nonisolated static let rowHeight: Double = 16
    public nonisolated static let topPadding: Double = 6

    /// How tall the block is for what it was given, so the panel and the card cannot disagree.
    public nonisolated static func height(hasBranch: Bool, hasRow: Bool) -> Double {
        guard hasBranch || hasRow else { return 0 }
        return topPadding + (hasBranch ? branchHeight : 0) + (hasRow ? rowHeight : 0)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let branch {
                Text("⎇ \(branch)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(DeckTheme.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: Self.branchHeight, alignment: .leading)
                    .help("checked out branch")
            }
            if leading != nil || trailing != nil {
                HStack(spacing: 12) {
                    if let leading {
                        Text(leading)
                            .font(.system(size: 10.5))
                            .foregroundStyle(DeckTheme.label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if let trailing {
                        Text(trailing)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DeckTheme.value.opacity(0.55))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(height: Self.rowHeight)
            }
        }
        .padding(.top, Self.topPadding)
    }
}
