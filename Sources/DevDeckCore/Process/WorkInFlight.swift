import Foundation

/// One checkout, as the deck sees it: what is uncommitted, what is unpushed, how far behind.
public struct CheckoutState: Sendable, Equatable, Identifiable {
    public let id: String
    /// What the card calls the project.
    public let title: String
    public let branch: String
    /// Files changed, staged or not, plus untracked ones.
    public let dirtyFiles: Int
    /// Commits on this branch that the remote does not have.
    public let ahead: Int
    /// Commits the remote has that this branch does not.
    public let behind: Int
    /// Nil when the branch has no upstream at all, which is not the same as being level with it.
    public let hasUpstream: Bool

    public init(
        id: String,
        title: String,
        branch: String,
        dirtyFiles: Int,
        ahead: Int,
        behind: Int,
        hasUpstream: Bool
    ) {
        self.id = id
        self.title = title
        self.branch = branch
        self.dirtyFiles = dirtyFiles
        self.ahead = ahead
        self.behind = behind
        self.hasUpstream = hasUpstream
    }

    /// Whether this checkout is worth a row at all.
    ///
    /// A clean checkout level with its remote is the normal state of most of them, and listing
    /// those is how a card becomes a wall of green nobody reads.
    public var isInFlight: Bool {
        dirtyFiles > 0 || ahead > 0 || behind > 0 || !hasUpstream
    }

    /// What the row says on the right, worst first, at most two facts.
    public var summary: String {
        var parts: [String] = []
        if dirtyFiles > 0 { parts.append("\(dirtyFiles) changed") }
        if ahead > 0 { parts.append("\(ahead) unpushed") }
        if !hasUpstream { parts.append("no remote") }
        if behind > 0 { parts.append("\(behind) behind") }
        return parts.prefix(2).joined(separator: " · ")
    }

    /// How loud the row is. Unpushed work is the one that can be lost with a disk, so it leads.
    public var isUrgent: Bool { ahead > 0 || !hasUpstream }
}

/// Reads what git already knows, in one command per checkout.
///
/// `git status --porcelain=v2 --branch` answers all four questions at once: the branch, its
/// upstream, how far ahead and behind, and every file that is not committed. One process per
/// project rather than four is the difference between a card that refreshes and a card that
/// makes the fans spin.
public enum WorkInFlight {
    public static let command = "git status --porcelain=v2 --branch --untracked-files=normal"

    /// Parses the porcelain v2 output. Pure, because this is the part worth being sure about.
    public static func parse(_ output: String, id: String, title: String) -> CheckoutState? {
        var branch: String?
        var hasUpstream = false
        var ahead = 0
        var behind = 0
        var dirty = 0

        for line in output.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                let value = String(line.dropFirst("# branch.head ".count))
                // A detached head reports "(detached)", which is a state, not a branch name.
                branch = value == "(detached)" ? nil : value
            } else if line.hasPrefix("# branch.upstream ") {
                hasUpstream = true
            } else if line.hasPrefix("# branch.ab ") {
                // `+2 -3`, always both, and always with signs.
                let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                if parts.count == 2 {
                    ahead = abs(Int(parts[0]) ?? 0)
                    behind = abs(Int(parts[1]) ?? 0)
                }
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") || line.hasPrefix("u ") || line.hasPrefix("? ") {
                // Changed, renamed, unmerged and untracked, which is every way a file can be
                // not-committed. Ignored files are not reported at this level.
                dirty += 1
            }
        }

        guard let branch else {
            return CheckoutState(
                id: id,
                title: title,
                branch: "detached",
                dirtyFiles: dirty,
                ahead: ahead,
                behind: behind,
                hasUpstream: hasUpstream
            )
        }
        return CheckoutState(
            id: id,
            title: title,
            branch: branch,
            dirtyFiles: dirty,
            ahead: ahead,
            behind: behind,
            hasUpstream: hasUpstream
        )
    }

    /// The rows the card shows: only what is in flight, loudest first.
    ///
    /// Unpushed commits lead because they are the only thing here that a dead disk takes with
    /// it. Then the size of the mess, then the name, so the order is stable between refreshes.
    public static func rows(from states: [CheckoutState]) -> [CheckoutState] {
        states
            .filter(\.isInFlight)
            .sorted { left, right in
                if left.isUrgent != right.isUrgent { return left.isUrgent }
                if left.dirtyFiles != right.dirtyFiles { return left.dirtyFiles > right.dirtyFiles }
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }
    }
}
