import Foundation

/// What a plain project is built on, as far as the card is concerned.
///
/// Only ever used to pick a glyph. Arc and DDEV projects know what they are from their own card
/// type; a plain project has nothing but a command, and the command is a reliable enough tell.
public enum ProjectKind: String, Sendable, Equatable, Codable {
    case node
    case docker
    case make
    case other

    /// Read from the command first and the footer caption second, because the caption is free
    /// text the user may have rewritten into something poetic.
    public static func detect(startCommand: String, subtitle: String = "") -> ProjectKind {
        let haystack = (startCommand + " " + subtitle).lowercased()

        // Docker before Node: a compose file that happens to run a Node image is still a thing
        // you start and stop through Docker.
        if haystack.contains("docker") || haystack.contains("compose") { return .docker }
        for token in ["npm", "pnpm", "yarn", "bun", "node", "vite", "next", "nuxt", "astro"]
        where haystack.contains(token) {
            return .node
        }
        if haystack.contains("make") { return .make }
        return .other
    }
}

public extension LocalProject {
    var kind: ProjectKind {
        ProjectKind.detect(startCommand: startCommand, subtitle: subtitle)
    }
}
