import AppKit
import DevDeckCore
import SwiftUI

/// Makes something look and feel clickable: it lights up under the cursor and the cursor
/// itself turns into a hand.
///
/// Panels sit behind other windows, so hover tracking only starts once the deck has been
/// clicked and the app is active. That is why the controls also carry a resting fill - the
/// affordance cannot depend on hover alone.
public struct ClickableHighlight: ViewModifier {
    private let cornerRadius: CGFloat
    private let isEnabled: Bool
    @State private var isHovering = false

    public init(cornerRadius: CGFloat, isEnabled: Bool) {
        self.cornerRadius = cornerRadius
        self.isEnabled = isEnabled
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(isHovering && isEnabled ? 0.09 : 0))
            )
            .onHover { hovering in
                guard isEnabled else { return }
                isHovering = hovering
                // push/pop rather than set: a card can have several of these, and set() would
                // leave the arrow behind whenever the pointer left one for another.
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                // A panel resized or hidden while the pointer is inside it would otherwise
                // leave the hand cursor stuck over the desktop.
                if isHovering {
                    isHovering = false
                    NSCursor.pop()
                }
            }
    }
}

public extension View {
    func clickable(cornerRadius: CGFloat = 6, isEnabled: Bool = true) -> some View {
        modifier(ClickableHighlight(cornerRadius: cornerRadius, isEnabled: isEnabled))
    }
}

/// What a card shows before its first successful load, or when it has nothing to show.
public struct CardPlaceholder<Value: Sendable & Equatable>: View {
    private let state: CardState<Value>

    public init(state: CardState<Value>) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 8)
            Text(state.failure?.displayMessage ?? "Loading…")
                .font(.system(size: 13))
                .foregroundStyle(state.failure == nil ? DeckTheme.label : DeckTheme.red)
            if case .missingToken = state.failure {
                Text("Add a GitHub token in Settings")
                    .font(.system(size: 11))
                    .foregroundStyle(DeckTheme.label)
            }
            Spacer(minLength: 8)
        }
    }
}

/// Which account a row came from. Only drawn when more than one is configured - with a single
/// account the chip would be noise on every row.
public struct AccountChip: View {
    private let label: String

    public init(_ label: String) {
        self.label = label
    }

    public var body: some View {
        Text(label.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(DeckTheme.blue)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(DeckTheme.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// The row that grows and shrinks the card.
public struct CardExpander: View {
    private let hidden: Int
    private let isExpanded: Bool
    private let onToggle: () -> Void

    public init(hidden: Int, isExpanded: Bool, onToggle: @escaping () -> Void) {
        self.hidden = hidden
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    public var body: some View {
        Text(isExpanded ? "show less ⌃" : "show \(hidden) more ⌄")
            .font(.system(size: 11))
            .foregroundStyle(DeckTheme.label)
            .frame(maxWidth: .infinity)
            .padding(.top, 5)
            .padding(.bottom, 1)
            .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1) }
            .contentShape(Rectangle())
            .clickable()
            .onTapGesture(perform: onToggle)
    }
}

public enum CardFreshness {
    /// Shows the failure rather than a timestamp when the last refresh broke: a clock that
    /// keeps ticking while the data is frozen is the worst of both.
    public static func text<Value: Sendable & Equatable>(for state: CardState<Value>) -> String {
        if let failure = state.failure { return failure.displayMessage }
        guard let updatedAt = state.updatedAt else { return "never updated" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: updatedAt)
    }
}

public enum RelativeTime {
    /// Compact age for a row: `14m`, `3h`, `2d`. Rows are narrow, and "14 minutes ago" costs
    /// more width than it adds meaning.
    public static func short(from date: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 90 { return "now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    /// Compact duration for a footer: `6m 12s`, `48s`.
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        return "\(total / 60)m \(total % 60)s"
    }
}
