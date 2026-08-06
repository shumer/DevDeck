import AppKit
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

    /// Space either side of a button's label. The same on every button, which is the point.
    public nonisolated static let labelPadding: Double = 10
    /// How much wider the prominent action is than its own contents need.
    public nonisolated static let prominentPadding: Double = 24
    private nonisolated static let iconWidth: Double = 12
    private nonisolated static let iconSpacing: Double = 4

    /// Widths from what each button actually contains, plus the same padding on every one.
    ///
    /// Four equal shares looked tidy in a mockup and wrong on screen: `Terminal` all but touched
    /// its own border while `Logs` sat in a field of space. Measuring the labels is what makes
    /// the padding uniform, which is the thing the eye actually reads as "these are the same
    /// kind of button". Whatever is left over is shared out equally, so the row still fills the
    /// card and lines up with the chips above it.
    public nonisolated static func widths(for actions: [CardAction]) -> [Double] {
        guard !actions.isEmpty else { return [] }
        let gaps = spacing * Double(actions.count - 1)
        let available = CardChromeMetrics.contentWidth - gaps
        let intrinsic = actions.map(intrinsicWidth(of:))
        let total = intrinsic.reduce(0, +)

        guard total < available else {
            // Not enough room for everything: shrink in proportion rather than let one label
            // truncate while another keeps its air.
            return intrinsic.map { $0 * (available / total) }
        }
        let surplus = (available - total) / Double(actions.count)
        return intrinsic.map { $0 + surplus }
    }

    /// What a button actually holds — icon, gap and label — with no padding at all.
    public nonisolated static func contentWidth(of action: CardAction) -> Double {
        intrinsicWidth(of: action) - labelPadding * 2 - (action.isProminent ? prominentPadding : 0)
    }

    private nonisolated static func intrinsicWidth(of action: CardAction) -> Double {
        let font = NSFont.systemFont(
            ofSize: action.isProminent ? 11.5 : 10.5,
            weight: action.isProminent ? .semibold : .medium
        )
        let label = ceil(NSAttributedString(string: action.title, attributes: [.font: font]).size().width)
        let icon = action.systemImage == nil ? 0 : iconWidth + iconSpacing
        return label + icon + labelPadding * 2 + (action.isProminent ? prominentPadding : 0)
    }
}

/// How much a state wants to be noticed.
public enum CardStateTone: Sendable, Equatable {
    /// Working as it should.
    case good
    /// Off, and that is nobody's problem — a stopped project is a normal thing.
    case neutral
    /// Busy, blocked or broken: the one a sweep down the column should catch.
    case alert
}

/// The state of the thing the card is about — the card's focal point.
///
/// It replaced a 12.5-point line that looked exactly like the three lines around it, and then
/// overshot: at 20 points in near-white it was the loudest thing on the desktop. What made it
/// shout was not the size on its own but near-white at weight 600 on dark glass, so all three
/// knobs move a little instead of one moving a lot — 17 points, 80% white, and the colour moves
/// out of the word and into the dot.
public struct CardHeroRow: View {
    private let color: Color
    private let tone: CardStateTone
    private let text: String
    private let note: String?
    private let help: String

    public init(
        color: Color,
        tone: CardStateTone = .neutral,
        text: String,
        note: String? = nil,
        help: String
    ) {
        self.color = color
        self.tone = tone
        self.text = text
        self.note = note
        self.help = help
    }

    public nonisolated static let height: Double = 22
    public nonisolated static let topPadding: Double = 9

    public var body: some View {
        HStack(spacing: 9) {
            dot
            Text(text)
                // Colour returns to the word only when something wants attention. That is the
                // whole asymmetry: five calm cards read as texture, the sixth reads as a state.
                .font(.system(size: 17, weight: .semibold))
                .kerning(-0.3)
                .foregroundStyle(tone == .alert ? color : DeckTheme.value.opacity(0.8))
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

    /// The halo is reserved for states that mean something: a stopped project gets a plain grey
    /// dot, so the ones that glow are worth looking at.
    @ViewBuilder
    private var dot: some View {
        switch tone {
        case .neutral:
            Circle()
                .fill(DeckTheme.label.opacity(0.66))
                .frame(width: 9, height: 9)
                .padding(1.5)
        case .good, .alert:
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .background(
                    Circle()
                        .fill(color.opacity(tone == .alert ? 0.3 : 0.2))
                        .frame(width: 16, height: 16)
                )
                .frame(width: 12, height: 12)
        }
    }
}

/// The quiet block under the hero: the branch, then whatever names this checkout.
///
/// The branch keeps a line of its own — branch names are routinely longer than anything beside
/// them, and "which branch is this" must not be the thing that gets truncated.
public struct CardMetaBlock: View {
    private let branch: String?
    private let branchURL: URL?
    private let leading: String?
    private let trailing: String?
    private let onOpenBranch: ((URL) -> Void)?

    public init(
        branch: String?,
        branchURL: URL? = nil,
        leading: String?,
        trailing: String? = nil,
        onOpenBranch: ((URL) -> Void)? = nil
    ) {
        self.branch = branch
        self.branchURL = branchURL
        self.leading = leading
        self.trailing = trailing
        self.onOpenBranch = onOpenBranch
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
                branchRow(branch)
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

    /// The branch, and — when the checkout has an origin — the way to that branch on the web.
    ///
    /// The line was already blue and monospaced, which is what a link looks like; all it was
    /// missing was being one. The arrow is what says so at rest, since these panels sit behind
    /// other windows and hover cannot be relied on to announce anything.
    @ViewBuilder
    private func branchRow(_ branch: String) -> some View {
        let isLink = branchURL != nil && onOpenBranch != nil

        HStack(spacing: 5) {
            Text("⎇ \(branch)")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(DeckTheme.blue)
                .lineLimit(1)
                .truncationMode(.middle)
            if isLink {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(DeckTheme.blue.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .frame(height: Self.branchHeight, alignment: .leading)
        .contentShape(Rectangle())
        .clickable(cornerRadius: 5, isEnabled: isLink)
        .onTapGesture {
            guard let branchURL, let onOpenBranch else { return }
            onOpenBranch(branchURL)
        }
        .help(branchURL.map { "\($0.absoluteString)" } ?? "checked out branch")
    }
}
