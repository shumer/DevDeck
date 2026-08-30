import CoreGraphics
import Foundation
import SwiftUI

/// Turns an SVG path string into a `Path`.
///
/// The alternative was drawing the brand marks by hand out of circles and triangles, and it
/// looked like what it was. Every logo here ships as one or two `d` attributes copied from the
/// vendor's own SVG, so what appears on the card is the real mark rather than an impression of
/// it - and no asset catalog is needed, which this toolchain does not have anyway.
public enum SVGPath {
    /// Parses `d` and scales it from its viewBox into `rect`, keeping the aspect ratio and
    /// centring what is left over - the same rule `preserveAspectRatio="xMidYMid meet"` states.
    public static func path(_ commands: String, viewBox: CGSize, in rect: CGRect) -> Path {
        let raw = parse(commands)
        guard viewBox.width > 0, viewBox.height > 0 else { return raw }

        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let offset = CGPoint(
            x: rect.minX + (rect.width - viewBox.width * scale) / 2,
            y: rect.minY + (rect.height - viewBox.height * scale) / 2
        )
        return raw.applying(
            CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
        )
    }

    /// Parses a `d` attribute in its own coordinate space.
    public static func parse(_ commands: String) -> Path {
        var path = Path()
        var scanner = Scanner(commands)
        var current = CGPoint.zero
        var start = CGPoint.zero
        /// The reflected control point `S`/`T` need, and which command produced it.
        var lastControl: CGPoint?
        var lastCommand: Character = " "

        while let command = scanner.nextCommand() {
            // A command letter may be followed by several sets of arguments; SVG repeats the
            // command for each, except that a repeated `M` means `L`.
            var isFirstRun = true
            repeat {
                let effective: Character = {
                    guard !isFirstRun, command == "M" || command == "m" else { return command }
                    return command == "M" ? "L" : "l"
                }()

                switch effective {
                case "M", "m":
                    guard let point = scanner.point(relativeTo: effective == "m" ? current : .zero)
                    else { return path }
                    path.move(to: point)
                    current = point
                    start = point
                    lastControl = nil

                case "L", "l":
                    guard let point = scanner.point(relativeTo: effective == "l" ? current : .zero)
                    else { return path }
                    path.addLine(to: point)
                    current = point
                    lastControl = nil

                case "H", "h":
                    guard let x = scanner.number() else { return path }
                    current = CGPoint(x: effective == "h" ? current.x + x : x, y: current.y)
                    path.addLine(to: current)
                    lastControl = nil

                case "V", "v":
                    guard let y = scanner.number() else { return path }
                    current = CGPoint(x: current.x, y: effective == "v" ? current.y + y : y)
                    path.addLine(to: current)
                    lastControl = nil

                case "C", "c":
                    let origin = effective == "c" ? current : .zero
                    guard
                        let control1 = scanner.point(relativeTo: origin),
                        let control2 = scanner.point(relativeTo: origin),
                        let end = scanner.point(relativeTo: origin)
                    else { return path }
                    path.addCurve(to: end, control1: control1, control2: control2)
                    current = end
                    lastControl = control2

                case "S", "s":
                    let origin = effective == "s" ? current : .zero
                    guard
                        let control2 = scanner.point(relativeTo: origin),
                        let end = scanner.point(relativeTo: origin)
                    else { return path }
                    let control1 = "CcSs".contains(lastCommand)
                        ? CGPoint(x: 2 * current.x - (lastControl ?? current).x,
                                  y: 2 * current.y - (lastControl ?? current).y)
                        : current
                    path.addCurve(to: end, control1: control1, control2: control2)
                    current = end
                    lastControl = control2

                case "Q", "q":
                    let origin = effective == "q" ? current : .zero
                    guard
                        let control = scanner.point(relativeTo: origin),
                        let end = scanner.point(relativeTo: origin)
                    else { return path }
                    path.addQuadCurve(to: end, control: control)
                    current = end
                    lastControl = control

                case "T", "t":
                    let origin = effective == "t" ? current : .zero
                    guard let end = scanner.point(relativeTo: origin) else { return path }
                    let control = "QqTt".contains(lastCommand)
                        ? CGPoint(x: 2 * current.x - (lastControl ?? current).x,
                                  y: 2 * current.y - (lastControl ?? current).y)
                        : current
                    path.addQuadCurve(to: end, control: control)
                    current = end
                    lastControl = control

                case "A", "a":
                    guard
                        let rx = scanner.number(), let ry = scanner.number(),
                        let rotation = scanner.number(),
                        let largeArc = scanner.flag(), let sweep = scanner.flag(),
                        let end = scanner.point(relativeTo: effective == "a" ? current : .zero)
                    else { return path }
                    appendArc(
                        to: &path,
                        from: current,
                        to: end,
                        radii: CGSize(width: abs(rx), height: abs(ry)),
                        rotation: rotation * .pi / 180,
                        isLargeArc: largeArc,
                        isSweep: sweep
                    )
                    current = end
                    lastControl = nil

                case "Z", "z":
                    path.closeSubpath()
                    current = start
                    lastControl = nil

                default:
                    return path
                }

                lastCommand = effective
                isFirstRun = false
                // Arguments run until the next letter; `Z` takes none.
            } while effective(of: command) && scanner.hasMoreArguments()
        }

        return path
    }

    private static func effective(of command: Character) -> Bool {
        command != "Z" && command != "z"
    }

    /// Endpoint-to-centre parameterisation, straight out of the SVG specification's appendix,
    /// then split into cubic segments of at most 90°.
    private static func appendArc(
        to path: inout Path,
        from start: CGPoint,
        to end: CGPoint,
        radii: CGSize,
        rotation: CGFloat,
        isLargeArc: Bool,
        isSweep: Bool
    ) {
        guard radii.width > 0, radii.height > 0 else {
            path.addLine(to: end)
            return
        }

        let cosPhi = cos(rotation)
        let sinPhi = sin(rotation)
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy

        var rx = radii.width
        var ry = radii.height
        // Radii too small to span the two points are scaled up, as the specification requires.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }

        let sign: CGFloat = isLargeArc == isSweep ? -1 : 1
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
        let cx1 = coefficient * rx * y1 / ry
        let cy1 = -coefficient * ry * x1 / rx

        let centre = CGPoint(
            x: cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2,
            y: sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2
        )

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            guard length > 0 else { return 0 }
            let value = acos(min(1, max(-1, dot / length)))
            return (ux * vy - uy * vx) < 0 ? -value : value
        }

        let startAngle = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var sweepAngle = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !isSweep, sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if isSweep, sweepAngle < 0 { sweepAngle += 2 * .pi }

        // A cubic cannot hold more than a quarter turn without visible error.
        let segments = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let delta = sweepAngle / CGFloat(segments)
        let alpha = 4.0 / 3.0 * tan(delta / 4)

        var theta = startAngle
        for _ in 0..<segments {
            let next = theta + delta
            let cosTheta = cos(theta), sinTheta = sin(theta)
            let cosNext = cos(next), sinNext = sin(next)

            func point(_ c: CGFloat, _ s: CGFloat) -> CGPoint {
                CGPoint(
                    x: centre.x + cosPhi * rx * c - sinPhi * ry * s,
                    y: centre.y + sinPhi * rx * c + cosPhi * ry * s
                )
            }

            let from = point(cosTheta, sinTheta)
            let to = point(cosNext, sinNext)
            let control1 = CGPoint(
                x: from.x + alpha * (-cosPhi * rx * sinTheta - sinPhi * ry * cosTheta),
                y: from.y + alpha * (-sinPhi * rx * sinTheta + cosPhi * ry * cosTheta)
            )
            let control2 = CGPoint(
                x: to.x - alpha * (-cosPhi * rx * sinNext - sinPhi * ry * cosNext),
                y: to.y - alpha * (-sinPhi * rx * sinNext + cosPhi * ry * cosNext)
            )
            path.addCurve(to: to, control1: control1, control2: control2)
            theta = next
        }
    }
}

/// Reads numbers, flags and command letters out of a `d` attribute.
///
/// SVG's number syntax is looser than it looks: `.186.186` is two numbers, `12-4` is two
/// numbers, and separators are optional wherever they are unambiguous.
private struct Scanner {
    private let characters: [Character]
    private var index: Int = 0

    init(_ text: String) {
        characters = Array(text)
    }

    mutating func nextCommand() -> Character? {
        skipSeparators()
        guard index < characters.count, characters[index].isLetter else { return nil }
        defer { index += 1 }
        return characters[index]
    }

    /// Whether another argument follows, as opposed to the next command or the end.
    mutating func hasMoreArguments() -> Bool {
        skipSeparators()
        guard index < characters.count else { return false }
        let character = characters[index]
        return character.isNumber || character == "-" || character == "+" || character == "."
    }

    mutating func number() -> CGFloat? {
        skipSeparators()
        var text = ""
        var hasDot = false

        if index < characters.count, characters[index] == "-" || characters[index] == "+" {
            text.append(characters[index])
            index += 1
        }
        while index < characters.count {
            let character = characters[index]
            if character.isNumber {
                text.append(character)
            } else if character == "." {
                // A second dot starts the next number: `.186.186` is two of them.
                if hasDot { break }
                hasDot = true
                text.append(character)
            } else if character == "e" || character == "E" {
                text.append(character)
                index += 1
                if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                    text.append(characters[index])
                    index += 1
                }
                continue
            } else {
                break
            }
            index += 1
        }

        guard let value = Double(text) else { return nil }
        return CGFloat(value)
    }

    /// Arc flags are a single character, and may be run together with what follows.
    mutating func flag() -> Bool? {
        skipSeparators()
        guard index < characters.count, characters[index] == "0" || characters[index] == "1"
        else { return nil }
        defer { index += 1 }
        return characters[index] == "1"
    }

    mutating func point(relativeTo origin: CGPoint) -> CGPoint? {
        guard let x = number(), let y = number() else { return nil }
        return CGPoint(x: origin.x + x, y: origin.y + y)
    }

    private mutating func skipSeparators() {
        while index < characters.count, characters[index] == " " || characters[index] == ","
            || characters[index] == "\n" || characters[index] == "\t" || characters[index] == "\r" {
            index += 1
        }
    }
}
