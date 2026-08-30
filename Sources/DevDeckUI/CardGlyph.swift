import SwiftUI

/// The mark in front of a card's title, saying what kind of thing the card is about.
///
/// Real logos, drawn from the vendors' own path data rather than approximated out of circles
/// and triangles - see `BrandMark`. Each keeps its brand colour, which is why they are the one
/// exception to the rule that colour on these cards means state: nobody reads a logo as a
/// status, and a grey octocat reads as a worse octocat.
public enum CardGlyph: String, Sendable, Equatable, CaseIterable {
    case github
    case arc
    case ddev
    case node
    case docker
    case make
    case project
}

public struct CardGlyphView: View {
    private let glyph: CardGlyph
    private let size: CGFloat

    public init(_ glyph: CardGlyph, size: CGFloat = 15) {
        self.glyph = glyph
        self.size = size
    }

    public var body: some View {
        content
            .frame(width: size, height: size)
    }

    /// The vector behind a glyph, or nil where the glyph is a system symbol. Public so the
    /// suite can check that every logo actually parses - a mark that silently comes out empty
    /// looks, on a card, exactly like a mark that was never added.
    public nonisolated static func mark(for glyph: CardGlyph) -> BrandMark.Vector? {
        switch glyph {
        case .github: return BrandMark.github
        case .node: return BrandMark.node
        case .docker: return BrandMark.docker
        case .ddev: return BrandMark.ddev
        case .arc, .make, .project: return nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch glyph {
        case .github: VectorMark(BrandMark.github)
        case .node: VectorMark(BrandMark.node)
        case .docker: VectorMark(BrandMark.docker)
        case .ddev: VectorMark(BrandMark.ddev)
        case .arc: ArcMark()
        // No brand behind these two, so the system's own symbols are the honest choice.
        case .make:
            Image(systemName: "hammer.fill")
                .resizable().scaledToFit().padding(0.5)
                .foregroundStyle(DeckTheme.label)
        case .project:
            Image(systemName: "shippingbox.fill")
                .resizable().scaledToFit()
                .foregroundStyle(DeckTheme.label)
        }
    }
}

/// Draws one of the vendor marks at whatever size it is given.
private struct VectorMark: View {
    private let mark: BrandMark.Vector

    init(_ mark: BrandMark.Vector) {
        self.mark = mark
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            for data in mark.paths {
                let path = SVGPath.path(data, viewBox: mark.viewBox, in: rect)
                context.fill(path, with: .color(mark.color), style: FillStyle(eoFill: mark.isEvenOdd))
            }
        }
    }
}

/// Arc XP: the wordmark's "A" - a white left stroke and a right one that runs from Arc's blue
/// into its green. The navy disc it usually sits on is left out; on dark glass it would be a
/// dark hole rather than a logo.
private struct ArcMark: View {
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 100

            func shape(_ points: [(CGFloat, CGFloat)]) -> Path {
                var path = Path()
                for (index, point) in points.enumerated() {
                    let scaled = CGPoint(x: point.0 * unit, y: point.1 * unit)
                    index == 0 ? path.move(to: scaled) : path.addLine(to: scaled)
                }
                path.closeSubpath()
                return path
            }

            context.fill(
                shape([(44, 14), (64, 14), (34, 86), (8, 86)]),
                with: .color(.white)
            )
            context.fill(
                shape([(64, 14), (92, 86), (62, 86), (48, 50)]),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.20, green: 0.66, blue: 0.87),
                        Color(red: 0.31, green: 0.76, blue: 0.63),
                    ]),
                    startPoint: CGPoint(x: 64 * unit, y: 14 * unit),
                    endPoint: CGPoint(x: 92 * unit, y: 86 * unit)
                )
            )
        }
    }
}
