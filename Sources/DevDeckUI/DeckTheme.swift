import DevDeckCore
import SwiftUI

/// The card frame's own measurements.
///
/// Separate from `CardChrome` because it is generic over its content, and a generic type's
/// static members cannot be read without naming that content — while every size calculation in
/// the app needs exactly these numbers.
public enum CardChromeMetrics {
    public static let horizontalPadding: Double = 14
    public static let topPadding: Double = 12
    public static let bottomPadding: Double = 12
    public static let headerHeight: Double = 14
    /// Width left for a card's content once the padding is taken off.
    public static var contentWidth: Double { CardMetrics.width - horizontalPadding * 2 }
}

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

/// Shared card frame: the title row, then whatever the card draws.
///
/// The title row carries a mark saying what kind of thing this is, and on the right either a
/// pill or the time of the last check. The timestamp moved up here from the footer: it is the
/// least important thing on the card, and down there it took a whole row to say so.
public struct CardChrome<Content: View>: View {
    private let title: String
    private let glyph: CardGlyph?
    private let pill: (text: String, color: Color)?
    private let timestamp: String?
    private let content: Content

    public init(
        title: String,
        glyph: CardGlyph? = nil,
        pill: (text: String, color: Color)? = nil,
        timestamp: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.glyph = glyph
        self.pill = pill
        self.timestamp = timestamp
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 7) {
                if let glyph {
                    CardGlyphView(glyph)
                }
                DeckTheme.sectionLabel(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if let pill {
                    StatusPill(pill.text, color: pill.color)
                } else if let timestamp {
                    Text(timestamp)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .fixedSize()
                }
            }
            .frame(height: CardChromeMetrics.headerHeight)
            content
        }
        .padding(.horizontal, CardChromeMetrics.horizontalPadding)
        .padding(.top, CardChromeMetrics.topPadding)
        .padding(.bottom, CardChromeMetrics.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The footer every card shares: context on the left, an optional note on the right.
public struct CardFooter: View {
    private let leading: String
    private let trailing: String?
    private let isStale: Bool

    public init(leading: String, trailing: String? = nil, isStale: Bool = false) {
        self.leading = leading
        self.trailing = trailing
        self.isStale = isStale
    }

    public nonisolated static let height: Double = 14

    public var body: some View {
        HStack {
            Text(leading)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isStale ? DeckTheme.amber : DeckTheme.label)
                    .fixedSize()
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(isStale ? DeckTheme.amber : DeckTheme.label)
        .lineLimit(1)
        .frame(height: Self.height)
    }
}
