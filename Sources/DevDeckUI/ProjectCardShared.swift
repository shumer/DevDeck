import DevDeckCore
import SwiftUI

/// A link on a project card, whatever kind of project it is.
public struct ProjectChip: Identifiable, Equatable {
    public enum Kind: Equatable {
        /// Something you work in: PageBuilder, Mailpit, an admin page.
        case tool
        /// The site itself, in some environment.
        case site
    }

    public let label: String
    public let url: URL
    public let kind: Kind

    public init(label: String, url: URL, kind: Kind) {
        self.label = label
        self.url = url
        self.kind = kind
    }

    public var id: String { label }
}

/// The chip block: tooling, a divider, then the environments.
public struct ProjectChipRow: View {
    private let tools: [ProjectChip]
    private let environments: [ProjectChip]
    private let isLocalReachable: Bool
    private let onOpen: (URL) -> Void

    public init(
        tools: [ProjectChip],
        environments: [ProjectChip],
        isLocalReachable: Bool,
        onOpen: @escaping (URL) -> Void
    ) {
        self.tools = tools
        self.environments = environments
        self.isLocalReachable = isLocalReachable
        self.onOpen = onOpen
    }

    /// The label DDEV, Arc and plain projects all give the local environment.
    public nonisolated static let localLabel = "Local site"
    /// PageBuilder's editor as this stack serves it.
    ///
    /// Named to match its neighbour rather than shortened. "PB editor" beside a "PageBuilder"
    /// chip three places to the left is two names for one product and no clue which of them is
    /// the one you are running; "Local site" and "Local PageBuilder" say what they are and that
    /// they are the same stack.
    public nonisolated static let localPageBuilderLabel = "Local PageBuilder"

    public var body: some View {
        // The divider is a subview like any other, so the layout is told which index it sits at
        // rather than being asked to work out what the chips mean.
        CardChipLayout(breakBefore: CardChipFlow.breakIndex(
            tools: tools.map(\.label),
            environments: environments.map(\.label)
        )) {
            ForEach(tools) { chip in
                view(for: chip)
            }
            if !tools.isEmpty, !environments.isEmpty {
                CardChipDivider()
            }
            ForEach(environments) { chip in
                view(for: chip)
            }
        }
        .padding(.top, CardChipFlow.topPadding)
    }

    @ViewBuilder
    private func view(for chip: ProjectChip) -> some View {
        // By where it points rather than by what it is called: the local site is not the only
        // local thing on the card any more, and a link into a stopped stack lands on a connection
        // error that reads as a broken app rather than a stopped one.
        let isLocal = chip.kind == .site && LocalAddress.isLoopback(chip.url)
        // A deployed environment is reachable whether or not anything is running here; only the
        // local one goes nowhere, and a link into a stopped project lands on a connection error
        // that reads as a broken app rather than a stopped one.
        let isDimmed = isLocal && !isLocalReachable

        CardChip(
            chip.label,
            color: Self.colour(for: chip, isLocal: isLocal),
            isDimmed: isDimmed,
            help: isDimmed
                ? "\(chip.url.absoluteString), the project is not running"
                : chip.url.absoluteString
        ) {
            guard !isDimmed else { return }
            onOpen(chip.url)
        }
    }

    public nonisolated static func colour(for chip: ProjectChip, isLocal: Bool) -> Color {
        guard chip.kind == .site else { return DeckTheme.blue }
        if isLocal { return DeckTheme.green }
        // Production is the one worth a beat of hesitation, so it is the one that is not calm.
        return chip.label.lowercased().contains("prod") ? DeckTheme.amber : DeckTheme.violet
    }
}

/// The height arithmetic every project card shares.
///
/// One place, because three cards and the panel that hosts them have to agree on it exactly: a
/// disagreement shows up as a clipped control row or a strip of empty glass.
public enum ProjectCardMetrics {
    public nonisolated static func height(
        tools: [String],
        environments: [String],
        hasBranch: Bool,
        hasMetaRow: Bool,
        logs: LogLines? = nil
    ) -> Double {
        CardChromeMetrics.topPadding
            + CardChromeMetrics.headerHeight
            + CardHeroRow.topPadding + CardHeroRow.height
            + CardMetaBlock.height(hasBranch: hasBranch, hasRow: hasMetaRow)
            + CardChipFlow.height(tools: tools, environments: environments)
            + CardLogTray.height(for: logs)
            + CardActionRow.height
            + CardChromeMetrics.bottomPadding
    }

    /// The time of the last check, as the card header shows it.
    public nonisolated static func timestamp(_ date: Date?) -> String {
        guard let date else { return "n/a" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
