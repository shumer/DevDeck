import SwiftUI

/// The visual language of the deck: one place for every colour and text style, so a new
/// card looks like the existing ones without copying magic numbers.
///
/// The palette is fixed rather than semantic-system colours: the panels sit on a
/// translucent dark blur over the wallpaper, where `.labelColor` would flip with the
/// system appearance and become unreadable.
public enum DeckTheme {
    public static let value = Color(red: 0.949, green: 0.961, blue: 0.969)
    /// Secondary text. Kept well above the "tasteful grey" that disappears the moment the
    /// panel sits over a bright wallpaper.
    public static let label = Color(red: 0.922, green: 0.941, blue: 0.961).opacity(0.68)
    /// Card titles. They name the card, so they read first, not last.
    public static let title = Color(red: 0.949, green: 0.961, blue: 0.969).opacity(0.9)
    public static let faint = Color.white.opacity(0.1)

    public static let green = Color(red: 0.494, green: 0.886, blue: 0.690)
    public static let red = Color(red: 1.0, green: 0.541, blue: 0.541)
    public static let amber = Color(red: 0.949, green: 0.820, blue: 0.486)
    public static let violet = Color(red: 0.788, green: 0.694, blue: 1.0)
    public static let blue = Color(red: 0.561, green: 0.780, blue: 1.0)

    public static let cornerRadius: CGFloat = 20
    /// Vertical spacing between stacked panels.
    public static let panelGap: CGFloat = 12

    public static func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(title)
    }
}

/// A pill in the top-right corner of a card: the one-word verdict.
public struct StatusPill: View {
    private let text: String
    private let color: Color

    public init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .kerning(0.9)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                Capsule().strokeBorder(color.opacity(0.7), lineWidth: 1)
            )
    }
}

/// Shared card frame: title row, optional pill, then whatever the card draws.
public struct CardChrome<Content: View>: View {
    private let title: String
    private let pill: (text: String, color: Color)?
    private let content: Content

    public init(
        title: String,
        pill: (text: String, color: Color)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.pill = pill
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                DeckTheme.sectionLabel(title)
                Spacer(minLength: 8)
                if let pill {
                    StatusPill(pill.text, color: pill.color)
                }
            }
            content
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The footer every card shares: context on the left, freshness on the right.
public struct CardFooter: View {
    private let leading: String
    private let trailing: String
    private let isStale: Bool

    public init(leading: String, trailing: String, isStale: Bool = false) {
        self.leading = leading
        self.trailing = trailing
        self.isStale = isStale
    }

    public var body: some View {
        HStack {
            Text(leading)
            Spacer(minLength: 6)
            Text(trailing)
                .foregroundStyle(isStale ? DeckTheme.amber : DeckTheme.label)
        }
        .font(.system(size: 11))
        .foregroundStyle(DeckTheme.label)
        .lineLimit(1)
    }
}
