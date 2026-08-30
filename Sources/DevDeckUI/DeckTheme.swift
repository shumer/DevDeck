import AppKit
import DevDeckCore
import SwiftUI

/// The card frame's own measurements.
///
/// Separate from `CardChrome` because it is generic over its content, and a generic type's
/// static members cannot be read without naming that content - while every size calculation in
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
    public static let label = Color(red: 0.922, green: 0.941, blue: 0.961).opacity(0.78)
    /// Card titles. Quiet on purpose: the title is the line you already know by heart, and in
    /// bold caps at 90% white it was the loudest thing on a card whose point is the state.
    public static let title = Color(red: 0.949, green: 0.961, blue: 0.969).opacity(0.62)
    /// Row rules. A separator only has to be found, not seen: at 10% it drew a ladder down
    /// every list card.
    public static let faint = Color.white.opacity(0.06)

    /// The state colours, pulled down about 20% in saturation from the fully saturated set they
    /// started as. Six cards of pure hue on dark glass is what made the deck tiring to sit next
    /// to for a working day: nothing was wrong with any one card, and the wall of them hummed.
    /// Muted, they still separate at a glance and stop competing with the wallpaper.
    public static let green = Color(red: 0.439, green: 0.780, blue: 0.600)
    public static let red = Color(red: 0.910, green: 0.518, blue: 0.518)
    public static let amber = Color(red: 0.941, green: 0.761, blue: 0.420)
    public static let violet = Color(red: 0.663, green: 0.608, blue: 0.878)
    public static let blue = Color(red: 0.498, green: 0.682, blue: 0.867)

    /// A hue as a chip wears it: mostly the hue, mixed back towards the text colour.
    ///
    /// Chips used to be filled with their own colour and lettered in it at full strength, which
    /// put five saturated pills in one row on every card. The fill is neutral now and only the
    /// lettering keeps the hue, so the row still says what kind of link each one is without the
    /// card reading as a paint chart.
    public static func chipInk(_ color: Color) -> Color {
        blend(color, with: value, amount: 0.55)
    }

    /// Two colours mixed in sRGB. `SwiftUI.Color.mix(with:by:)` needs macOS 15, and this app
    /// runs further back than that.
    public static func blend(_ first: Color, with second: Color, amount: Double) -> Color {
        guard
            let one = NSColor(first).usingColorSpace(.sRGB),
            let two = NSColor(second).usingColorSpace(.sRGB)
        else { return first }
        let mix = { (a: CGFloat, b: CGFloat) in Double(a) * amount + Double(b) * (1 - amount) }
        return Color(
            .sRGB,
            red: mix(one.redComponent, two.redComponent),
            green: mix(one.greenComponent, two.greenComponent),
            blue: mix(one.blueComponent, two.blueComponent),
            opacity: 1
        )
    }

    public static let cornerRadius: CGFloat = 20
    /// Vertical spacing between stacked panels.
    public static let panelGap: CGFloat = 12

    public static func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(title)
    }
}

/// The one-word verdict beside a card's headline number.
///
/// It was a bordered capsule in small caps, which is three pieces of decoration for two words.
/// Plain tinted text says the same thing and leaves the card one outline quieter.
public struct StatusPill: View {
    private let text: String
    private let color: Color

    public init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.2)
            .foregroundStyle(color)
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
    private let toggle: CardHeaderToggle?
    private let content: Content

    public init(
        title: String,
        glyph: CardGlyph? = nil,
        pill: (text: String, color: Color)? = nil,
        timestamp: String? = nil,
        toggle: CardHeaderToggle? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.glyph = glyph
        self.pill = pill
        self.timestamp = timestamp
        self.toggle = toggle
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
                if let toggle {
                    Image(systemName: toggle.systemImage)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(DeckTheme.value.opacity(toggle.isOn ? 0.8 : 0.45))
                        .frame(width: CardHeaderToggle.width, height: 14)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(toggle.isOn ? 0.12 : 0.06))
                        )
                        .contentShape(Rectangle())
                        .clickable(cornerRadius: 5)
                        .onTapGesture(perform: toggle.action)
                        .help(toggle.help)
                }
                if let pill {
                    StatusPill(pill.text, color: pill.color)
                } else if let timestamp {
                    Text(timestamp)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.50))
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
