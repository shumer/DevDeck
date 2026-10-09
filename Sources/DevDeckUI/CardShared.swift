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
    // Written out rather than as `@State`. In the macOS 27 SDK that attribute resolves to a
    // macro whose plugin only Xcode ships, and this project builds with the Command Line
    // Tools; the `State` struct itself is still there, and a stored one is exactly what the
    // attribute expands to. SwiftUI finds it by its type, not by the attribute.
    private var _isHovering = State(initialValue: false)
    private var isHovering: Bool {
        get { _isHovering.wrappedValue }
        nonmutating set { _isHovering.wrappedValue = newValue }
    }

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
