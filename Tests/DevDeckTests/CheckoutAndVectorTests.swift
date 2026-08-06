import CoreGraphics
import DevDeckCore
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

private let gitConfig = """
[core]
    repositoryformatversion = 0
    bare = false
[remote "upstream"]
    url = git@github.com:someone-else/fork.git
    fetch = +refs/heads/*:refs/remotes/upstream/*
[remote "origin"]
    url = git@github.com:editoria/ledwall.git
    fetch = +refs/heads/*:refs/remotes/origin/*
[branch "main"]
    remote = origin
"""

func runVectorTests(_ run: TestRun) async {
    run.section("Git — the branch is a link to the branch")

    await run.test("origin is read from its own section, not from the first url in the file") {
        // A repository with an upstream has several `url =` lines and origin's is not first.
        try expectEqual(
            GitCheckout.originURL(inConfig: gitConfig),
            "git@github.com:editoria/ledwall.git"
        )
        try expectNil(GitCheckout.originURL(inConfig: "[core]\n    bare = false\n"), "no origin")
    }

    await run.test("every way of writing the same repository leads to the same page") {
        let expected = "https://github.com/editoria/ledwall"
        for remote in [
            "git@github.com:editoria/ledwall.git",
            "git@github.com:editoria/ledwall",
            "ssh://git@github.com/editoria/ledwall.git",
            "https://github.com/editoria/ledwall.git",
            "https://shumer@github.com/editoria/ledwall",
        ] {
            try expectEqual(GitCheckout.webURL(fromRemote: remote)?.absoluteString, expected, remote)
        }
    }

    await run.test("what is not a repository produces no link at all") {
        try expectNil(GitCheckout.webURL(fromRemote: ""), "empty")
        try expectNil(GitCheckout.webURL(fromRemote: "/Users/x/some/local/path"), "a local path")
        try expectNil(GitCheckout.webURL(fromRemote: "https://github.com"), "a host with no repo")
    }

    await run.test("each host spells a branch its own way, and an unknown one is not guessed at") {
        func branch(_ remote: String, _ name: String = "feat/IW-164") throws -> String {
            let repository = try expectNotNil(GitCheckout.webURL(fromRemote: remote), remote)
            return GitCheckout.branchWebURL(repository: repository, branch: name).absoluteString
        }
        try expectEqual(
            try branch("git@github.com:editoria/ledwall.git"),
            "https://github.com/editoria/ledwall/tree/feat/IW-164"
        )
        try expectEqual(
            try branch("git@gitlab.com:editoria/ledwall.git"),
            "https://gitlab.com/editoria/ledwall/-/tree/feat/IW-164"
        )
        try expectEqual(
            try branch("git@git.internal.example:editoria/ledwall.git"),
            "https://git.internal.example/editoria/ledwall",
            "an unknown host gets the repository rather than a path that would 404"
        )
    }

    await run.test("a branch that is not on the remote links to the repository, not to a 404") {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("devdeck-refs-\(UUID().uuidString)", isDirectory: true)
        let dotGit = folder.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: true)
        try gitConfig.write(to: dotGit.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/wip/local-only\n".write(
            to: dotGit.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8
        )

        try expect(!GitCheckout.hasRemoteBranch(in: folder, branch: "wip/local-only"))
        try expectEqual(
            GitCheckout.branchWebURL(in: folder, branch: "wip/local-only")?.absoluteString,
            "https://github.com/editoria/ledwall",
            "a branch nobody has pushed is not a page"
        )

        // Pushed: git writes the ref as a file.
        let remote = dotGit.appendingPathComponent("refs/remotes/origin/wip", isDirectory: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try "deadbeef\n".write(
            to: remote.appendingPathComponent("local-only"), atomically: true, encoding: .utf8
        )
        try expect(GitCheckout.hasRemoteBranch(in: folder, branch: "wip/local-only"))
        try expectEqual(
            GitCheckout.branchWebURL(in: folder, branch: "wip/local-only")?.absoluteString,
            "https://github.com/editoria/ledwall/tree/wip/local-only"
        )

        // And a repository with many refs packs them into one file instead.
        try "# pack-refs with: peeled fully-peeled sorted \n"
            .appending("2f8a1c9 refs/remotes/origin/main\n")
            .write(to: dotGit.appendingPathComponent("packed-refs"), atomically: true, encoding: .utf8)
        try expect(GitCheckout.hasRemoteBranch(in: folder, branch: "main"), "packed refs count too")
        try expect(!GitCheckout.hasRemoteBranch(in: folder, branch: "mai"), "and are matched whole")
    }

    await run.test("a checkout with no origin has no link, and nothing breaks") {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("devdeck-git-\(UUID().uuidString)", isDirectory: true)
        let dotGit = folder.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(
            to: dotGit.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8
        )

        try expectEqual(GitCheckout.branch(in: folder), "main")
        try expectNil(GitCheckout.originWebURL(in: folder), "no config, no link")
        try expectNil(GitCheckout.branchWebURL(in: folder, branch: "main"), "branch link")

        try gitConfig.write(to: dotGit.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        try expectEqual(
            GitCheckout.branchWebURL(in: folder, branch: "main")?.absoluteString,
            "https://github.com/editoria/ledwall",
            "origin is known, the branch is not — so the repository it is"
        )
    }

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
