import Foundation

/// What a plain project is built on, as far as the card is concerned.
///
/// Only ever used to pick a glyph. Arc and DDEV projects know what they are from their own card
/// type; a plain project has nothing but a command and a caption, and between them that is a
/// reliable enough tell.
public enum ProjectKind: String, Sendable, Equatable, Codable {
    case node
    case next
    case nest
    case bun
    case docker
    case make
    case other

    /// The words that name each kind, most specific first.
    ///
    /// A framework beats the runtime that happens to run it: `bun run dev` on a Next app is a
    /// Next app, and "bun" says the least interesting true thing about it. Docker stays ahead of
    /// all of them, because a stack you start and stop through compose is a compose stack
    /// whatever it runs inside.
    private static let vocabulary: [(kind: ProjectKind, words: Set<String>)] = [
        (.docker, ["docker", "compose"]),
        (.next, ["next", "nextjs"]),
        (.nest, ["nest", "nestjs"]),
        (.bun, ["bun", "bunx"]),
        (.node, ["npm", "pnpm", "yarn", "node", "vite", "nuxt", "astro", "turbo", "turborepo"]),
        (.make, ["make"]),
    ]

    /// Read from the command first and the footer caption second, because the caption is free
    /// text the user may have rewritten into something poetic. Which is also the escape hatch:
    /// a project whose mark comes out wrong gets the right one by having its caption say so.
    public static func detect(startCommand: String, subtitle: String = "") -> ProjectKind {
        let words = self.words(in: startCommand + " " + subtitle)
        for entry in vocabulary where !entry.words.isDisjoint(with: words) {
            return entry.kind
        }
        return .other
    }

    /// Whole words rather than substrings.
    ///
    /// `bun` is three letters that also begin `bundle`, and `make` sits inside `makemigrations`.
    /// Matching on a substring gave `npm run bundle` the bun mark, which is the kind of wrong
    /// nobody reports and everybody notices.
    private static func words(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
        )
    }
}

public extension LocalProject {
    var kind: ProjectKind {
        ProjectKind.detect(startCommand: startCommand, subtitle: subtitle)
    }
}
