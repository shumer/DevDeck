import DDEVKit
import DevDeckCore
import SwiftUI

/// One DDEV project: where to open it, what it is built on, and whether it is up.
///
/// Same shape as the Arc card and built from the same pieces; what differs is that DDEV can
/// describe itself, so nothing here has to be configured to be shown.
public struct DDEVProjectCard: View {
    private static let baseHeight: Double = 150
    private static let chipRowHeight: Double = 25

    private let project: DDEVProject
    private let status: DDEVStatus
    private let onOpen: (URL) -> Void
    private let onAction: (DDEVAction) -> Void
    private let onRevealFolder: () -> Void
    private let onOpenTerminal: () -> Void

    public init(
        project: DDEVProject,
        status: DDEVStatus,
        onOpen: @escaping (URL) -> Void = { _ in },
        onAction: @escaping (DDEVAction) -> Void = { _ in },
        onRevealFolder: @escaping () -> Void = {},
        onOpenTerminal: @escaping () -> Void = {}
    ) {
        self.project = project
        self.status = status
        self.onOpen = onOpen
        self.onAction = onAction
        self.onRevealFolder = onRevealFolder
        self.onOpenTerminal = onOpenTerminal
    }

    nonisolated public static func size(for project: DDEVProject, status: DDEVStatus) -> CGSize {
        CGSize(
            width: CardMetrics.width,
            height: baseHeight
                + (project.links(status: status).isEmpty ? 0 : chipRowHeight)
                + (status.branch != nil ? CardBranchRow.height : 0)
        )
    }

    public var body: some View {
        CardChrome(title: "DDEV · \(project.displayTitle)", pill: pill) {
            links
            CardSeparator()
            stateRow
            branchRow
            controls
            Spacer(minLength: 12)
            CardFooter(leading: footerLeading, trailing: freshness, isStale: status.mutagenWarning != nil)
        }
    }

    private var pill: (text: String, color: Color)? {
        switch status.state {
        case .running: return ("running", DeckTheme.green)
        // Paused is DDEV's own state, not a shade of stopped: the containers are still there
        // and a start is quick, so the card says which it is.
        case .paused: return ("paused", DeckTheme.amber)
        case .stopped: return ("stopped", DeckTheme.label)
        case .working: return (status.detail ?? "working…", DeckTheme.amber)
        case .unknown: return ("unknown to ddev", DeckTheme.red)
        }
    }

    private var links: some View {
        HStack(spacing: 6) {
            ForEach(project.links(status: status)) { link in
                CardChip(
                    link.label,
                    color: link.kind == .site ? DeckTheme.green : DeckTheme.blue,
                    isDimmed: !status.isRunning,
                    help: status.isRunning
                        ? link.url.absoluteString
                        : "\(link.url.absoluteString) — the project is not running"
                ) {
                    // A link into a stopped project lands on a connection error, which reads
                    // as a broken app rather than a stopped one.
                    guard status.isRunning else { return }
                    onOpen(link.url)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 11)
    }

    private var stateRow: some View {
        CardStateRow(
            color: stateColor,
            text: stateText,
            isProminent: status.isRunning,
            trailing: status.entry.map { _ in status.mutagenWarning } ?? nil,
            help: status.detail ?? stateText
        )
    }

    private var stateColor: Color {
        switch status.state {
        case .running: return status.mutagenWarning == nil ? DeckTheme.green : DeckTheme.amber
        case .paused, .working: return DeckTheme.amber
        case .stopped: return DeckTheme.label
        case .unknown: return DeckTheme.red
        }
    }

    /// The versions first: they answer most of what anyone asks a local environment, and the
    /// pill above has already said whether it is running.
    private var stateText: String {
        if status.state == .working { return status.detail ?? "working…" }
        if let versions = status.versionsLine { return versions }
        if status.state == .unknown { return status.detail ?? "not known to ddev" }
        return status.state.rawValue
    }

    @ViewBuilder
    private var branchRow: some View {
        if let branch = status.branch {
            CardBranchRow(branch)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if status.isRunning {
                CardActionButton("⏻ Stop", tint: DeckTheme.red) { onAction(.stop) }
                CardActionButton("↻ Restart") { onAction(.restart) }
            } else {
                CardActionButton("▶ Start", tint: DeckTheme.green, isEnabled: !status.isBusy) {
                    onAction(.start)
                }
                CardActionButton("↻ Restart", isEnabled: false) {}
            }
            CardActionButton("Folder", isEnabled: project.folderURL != nil, action: onRevealFolder)
            CardActionButton("Terminal", isEnabled: project.folderURL != nil, action: onOpenTerminal)
        }
        .padding(.top, 12)
    }

    private var footerLeading: String {
        let type = status.entry?.type ?? status.config.type
        let folder = project.folderURL?.lastPathComponent
        return [type, folder].compactMap { $0 }.joined(separator: " · ")
    }

    private var freshness: String {
        if let warning = status.mutagenWarning { return warning }
        guard let checkedAt = status.checkedAt else { return "not checked" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: checkedAt)
    }
}
