import CoreGraphics
import DevDeckUI
import Foundation
import TestHarness

/// Rounded comparison: bezier arithmetic lands a hair off round numbers.
private func expectClose(
    _ actual: CGFloat,
    _ expected: CGFloat,
    _ label: String = "",
    tolerance: CGFloat = 0.01,
    file: String = #filePath,
    line: UInt = #line
) throws {
    try expect(
        abs(actual - expected) <= tolerance,
        "\(label.isEmpty ? "" : label + ": ")expected \(expected), got \(actual)",
        file: file,
        line: line
    )
}

func runVectorTests(_ run: TestRun) async {
    run.section("SVG paths — the logos are real, so the parser has to be")

    await run.test("absolute and relative moves and lines") {
        // (10,10) → (20,10) → (20,20) → (5,20) → (5,15), closed.
        let path = SVGPath.parse("M10,10 L20,10 l0,10 H5 v-5 Z")
        let box = path.boundingRect
        try expectClose(box.minX, 5, "H is absolute")
        try expectClose(box.minY, 10)
        try expectClose(box.maxX, 20)
        try expectClose(box.maxY, 20, "v is relative")
        try expect(!path.isEmpty)
    }

    await run.test("a repeated moveto argument becomes a lineto") {
        // The specification's oddest corner, and every real logo relies on it.
        let repeated = SVGPath.parse("M0,0 10,0 10,10").boundingRect
        try expectClose(repeated.maxX, 10)
        try expectClose(repeated.maxY, 10)
    }

    await run.test("numbers run together the way real path data writes them") {
        // `.186.186` is two numbers, and `12-4` is two more: the separators are optional
        // wherever they cannot be ambiguous, and every vendor's exporter uses that.
        let path = SVGPath.parse("M.186.186L12-4")
        let box = path.boundingRect
        try expectClose(box.minY, -4)
        try expectClose(box.maxX, 12)
    }

    await run.test("an arc curves rather than cutting the corner") {
        // A quarter circle from (0,10) to (10,0): the corner point (10,10) must stay outside it.
        let path = SVGPath.parse("M0,10 A10,10 0 0 1 10,0")
        let box = path.boundingRect
        try expectClose(box.minX, 0, tolerance: 0.2)
        try expectClose(box.maxX, 10, tolerance: 0.2)
        try expect(!path.contains(CGPoint(x: 9.9, y: 9.9)), "the arc bulges away from the corner")
    }

    await run.test("a curve keeps its control points inside the box") {
        let path = SVGPath.parse("M0,0 C0,10 10,10 10,0")
        try expect(path.boundingRect.height <= 10)
        try expect(path.boundingRect.height > 4, "and it does bulge")
    }

    await run.test("junk stops the parse instead of crashing it") {
        try expect(SVGPath.parse("").isEmpty)
        try expect(SVGPath.parse("hello").isEmpty)
        try expect(!SVGPath.parse("M0,0 L10,10 QQQ").isEmpty, "what parsed is kept")
    }

    run.section("SVG paths — the marks themselves")

    await run.test("every brand mark parses and fills its box") {
        let box = CGRect(x: 0, y: 0, width: 15, height: 15)
        for glyph in CardGlyph.allCases {
            guard let mark = CardGlyphView.mark(for: glyph) else { continue }
            for data in mark.paths {
                let path = SVGPath.path(data, viewBox: mark.viewBox, in: box)
                try expect(!path.isEmpty, "\(glyph.rawValue) produced nothing")

                let bounds = path.boundingRect
                // Inside the box it was given, and not a speck in the corner of it.
                try expect(bounds.minX >= -0.5 && bounds.minY >= -0.5, "\(glyph.rawValue) starts outside")
                try expect(bounds.maxX <= 15.5 && bounds.maxY <= 15.5, "\(glyph.rawValue) overflows")
                try expect(bounds.width > 3 || bounds.height > 3, "\(glyph.rawValue) is a speck")
            }
        }
    }

    await run.test("a mark keeps its proportions when the box is not square") {
        // DDEV's is the wide one, so it is the one that would stretch.
        let mark = try expectNotNil(CardGlyphView.mark(for: .ddev), "ddev")
        // The whole mark, not one of its three strokes: a single stroke has its own shape.
        var union = CGRect.null
        for data in mark.paths {
            union = union.union(
                SVGPath.path(data, viewBox: mark.viewBox, in: CGRect(x: 0, y: 0, width: 40, height: 20))
                    .boundingRect
            )
        }
        let bounds = union
        let sourceRatio = mark.viewBox.width / mark.viewBox.height
        try expectClose(bounds.width / bounds.height, sourceRatio, "aspect ratio", tolerance: 0.35)
    }
}
