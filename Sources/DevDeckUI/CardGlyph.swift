import SwiftUI

/// The mark in front of a card's title, saying what kind of thing the card is about.
///
/// Drawn rather than shipped as images: the app has no asset catalog, and at 15 points a
/// faithful logo is mush anyway — what survives is the silhouette. They are deliberately
/// monochrome. Colour on these cards means state, and six tinted logos would compete with the
/// one thing that has to read first.
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
    private let color: Color

    public init(_ glyph: CardGlyph, size: CGFloat = 14, color: Color = DeckTheme.title) {
        self.glyph = glyph
        self.size = size
        self.color = color
    }

    public var body: some View {
        shape
            .foregroundStyle(color)
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var shape: some View {
        switch glyph {
        case .github: OctocatMark()
        case .arc: ArcMark()
        case .ddev: MonogramMark("D")
        case .node: HexagonMark()
        case .docker: ContainerMark()
        case .make: Image(systemName: "hammer.fill").resizable().scaledToFit().padding(0.5)
        case .project: Image(systemName: "shippingbox.fill").resizable().scaledToFit()
        }
    }
}

// MARK: The marks

/// GitHub, reduced to what is left of the octocat at 14 points: a round head, two ears, two
/// knocked-out eyes and the tail.
private struct OctocatMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let unit = side / 16

            ZStack {
                // Head and ears in one silhouette, so the ears read as part of the shape rather
                // than as two triangles parked on top of a circle.
                Path { path in
                    path.move(to: CGPoint(x: 3 * unit, y: 5 * unit))
                    path.addLine(to: CGPoint(x: 2.2 * unit, y: 1.4 * unit))
                    path.addLine(to: CGPoint(x: 5.6 * unit, y: 3.4 * unit))
                    path.addLine(to: CGPoint(x: 10.4 * unit, y: 3.4 * unit))
                    path.addLine(to: CGPoint(x: 13.8 * unit, y: 1.4 * unit))
                    path.addLine(to: CGPoint(x: 13 * unit, y: 5 * unit))
                    path.addCurve(
                        to: CGPoint(x: 8 * unit, y: 14.6 * unit),
                        control1: CGPoint(x: 15.6 * unit, y: 8.6 * unit),
                        control2: CGPoint(x: 12.6 * unit, y: 14.6 * unit)
                    )
                    path.addCurve(
                        to: CGPoint(x: 3 * unit, y: 5 * unit),
                        control1: CGPoint(x: 3.4 * unit, y: 14.6 * unit),
                        control2: CGPoint(x: 0.4 * unit, y: 8.6 * unit)
                    )
                    path.closeSubpath()
                }
                .fill(.foreground)

                // Knocked out rather than drawn in the background colour, which is glass and
                // has no colour to match.
                Path { path in
                    path.addEllipse(in: CGRect(x: 4.6 * unit, y: 7.2 * unit, width: 2.6 * unit, height: 3 * unit))
                    path.addEllipse(in: CGRect(x: 8.8 * unit, y: 7.2 * unit, width: 2.6 * unit, height: 3 * unit))
                }
                .fill(.foreground)
                .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: side, height: side)
        }
    }
}

/// Arc XP: an arc, open at the top right, with the dot the brand sets at its end.
private struct ArcMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let inset = side * 0.16
            let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)

            ZStack {
                Circle()
                    .trim(from: 0.08, to: 0.72)
                    .stroke(style: StrokeStyle(lineWidth: side * 0.17, lineCap: .round))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: side / 2, y: side / 2)
                Circle()
                    .frame(width: side * 0.2, height: side * 0.2)
                    .position(x: side * 0.78, y: side * 0.26)
            }
            .frame(width: side, height: side)
        }
    }
}

/// DDEV and anything else that has a wordmark rather than a shape: a rounded tile with the
/// initial knocked out of it, the same trick the app's own menu-bar icon uses.
private struct MonogramMark: View {
    private let letter: String

    init(_ letter: String) {
        self.letter = letter
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                    .fill(.foreground)
                Text(letter)
                    .font(.system(size: side * 0.72, weight: .heavy, design: .rounded))
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: side, height: side)
        }
    }
}

/// Node: the hexagon, which is the whole of its mark that survives this size.
private struct HexagonMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let width = side * 0.86
            let center = CGPoint(x: side / 2, y: side / 2)

            Path { path in
                for corner in 0..<6 {
                    // Flat-topped, rotated the way Node draws it: a point at the top.
                    let angle = Double(corner) * .pi / 3 - .pi / 2
                    let point = CGPoint(
                        x: center.x + cos(angle) * width / 2,
                        y: center.y + sin(angle) * width / 2
                    )
                    corner == 0 ? path.move(to: point) : path.addLine(to: point)
                }
                path.closeSubpath()
            }
            .stroke(style: StrokeStyle(lineWidth: side * 0.13, lineJoin: .round))
            .frame(width: side, height: side)
        }
    }
}

/// Docker, as containers on a deck rather than as a whale: three boxes and the waterline.
private struct ContainerMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let unit = side / 16
            let box = CGSize(width: 3.6 * unit, height: 3.2 * unit)

            ZStack(alignment: .topLeading) {
                ForEach(Array(boxes.enumerated()), id: \.offset) { _, origin in
                    RoundedRectangle(cornerRadius: unit * 0.6, style: .continuous)
                        .fill(.foreground)
                        .frame(width: box.width, height: box.height)
                        .offset(x: origin.x * unit, y: origin.y * unit)
                }
                Capsule()
                    .fill(.foreground)
                    .frame(width: 14 * unit, height: 1.6 * unit)
                    .offset(x: unit, y: 12.4 * unit)
            }
            .frame(width: side, height: side, alignment: .topLeading)
        }
    }
}

private let boxes: [CGPoint] = [
    CGPoint(x: 2.4, y: 8.4), CGPoint(x: 6.4, y: 8.4), CGPoint(x: 10.4, y: 8.4),
    CGPoint(x: 6.4, y: 4.8),
]
