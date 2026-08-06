import DDEVKit
import DevDeckCore
import SwiftUI

/// One DDEV project: whether it is up, where to open it, and what it is built on.
///
/// Same shape as the Arc and plain project cards and built from the same pieces; what differs
/// is that DDEV can describe itself, so nothing here has to be configured to be shown.
public struct DDEVProjectCard: View {
    private let project: DDEVProject
    private let status: DDEVStatus
    private let docker: DockerStatus
    private let onOpen: (URL) -> Void
    private let onAction: (DDEVAction) -> Void
    private let onRevealFolder: () -> Void
    private let onOpenTerminal: () -> Void
    private let onStartDocker: (() -> Void)?

    public init(
        project: DDEVProject,
        status: DDEVStatus,
        docker: DockerStatus = DockerStatus(state: .unknown),
        onOpen: @escaping (URL) -> Void = { _ in },
        onAction: @escaping (DDEVAction) -> Void = { _ in },
        onRevealFolder: @escaping () -> Void = {},
        onOpenTerminal: @escaping () -> Void = {},
        onStartDocker: (() -> Void)? = nil
    ) {
        self.project = project
        self.status = status
        self.docker = docker
        self.onOpen = onOpen
        self.onAction = onAction
        self.onRevealFolder = onRevealFolder
        self.onOpenTerminal = onOpenTerminal
        self.onStartDocker = onStartDocker
    }

    nonisolated public static func size(for project: DDEVProject, status: DDEVStatus) -> CGSize {
        CGSize(
            width: CardMetrics.width,
            height: ProjectCardMetrics.height(
                tools: project.toolLinks(status: status).map(\.label),
                environments: project.environmentLinks(status: status).map(\.label),
                hasBranch: status.branch != nil,
                hasMetaRow: true
            )
        )
    }

    public var body: some View {
        CardChrome(
            title: "DDEV · \(project.displayTitle)",
            glyph: .ddev,
            timestamp: ProjectCardMetrics.timestamp(status.checkedAt)
        ) {
            hero
            CardMetaBlock(
                branch: status.branch,
                repositoryURL: status.repositoryURL,
                leading: metaLeading,
                trailing: status.versionsLine,
                onOpenRepository: onOpen
            )
            chips
            controls
            Spacer(minLength: 0)
        }
    }

    /// Whether the card is about Docker rather than about the project. DDEV is containers all
    /// the way down, so this is every project here.
    private var isDockerBlocked: Bool {
        DockerGate.blocks(docker, isRunning: status.isRunning, requiresDocker: true)
    }

    private var hero: some View {
        CardHeroRow(
            color: heroState.color,
            tone: heroState.tone,
            text: heroText,
            // "unknown" alone says nothing useful; what makes it useful is who does not know.
            note: isDockerBlocked
                ? nil
                : (status.state == .unknown ? "not in ddev list" : status.mutagenWarning),
            help: status.detail ?? heroText
        )
    }

    private var heroState: (color: Color, tone: CardStateTone) {
        if isDockerBlocked { return (DockerGate.color(docker), .alert) }
        switch status.state {
        // A broken file sync is a running project you cannot trust, so it reads as attention
        // rather than as fine.
        case .running:
            return status.mutagenWarning == nil ? (DeckTheme.green, .good) : (DeckTheme.amber, .alert)
        case .paused, .working: return (DeckTheme.amber, .alert)
        case .stopped: return (DeckTheme.label, .neutral)
        case .unknown: return (DeckTheme.red, .alert)
        }
    }

    private var heroText: String {
        // Docker first: without it `ddev list` cannot answer either, and "unknown to ddev" would
        // be a true sentence that helps nobody.
        if isDockerBlocked { return DockerGate.text(docker) }
        switch status.state {
        case .running: return "running"
        // Paused is DDEV's own state, not a shade of stopped: the containers are still there
        // and a start is quick, so the card says which it is.
        case .paused: return "paused"
        case .stopped: return "stopped"
        case .working: return status.detail ?? "working…"
        case .unknown: return "unknown"
        }
    }

    private var metaLeading: String? {
        let folder = project.folderURL?.lastPathComponent
        let parts = [status.frameworkLabel, folder].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Tooling on the left, the environments after the divider. Only the local one depends on
    /// the project being up.
    private var chips: some View {
        ProjectChipRow(
            tools: project.toolLinks(status: status).map {
                ProjectChip(label: $0.label, url: $0.url, kind: .tool)
            },
            environments: project.environmentLinks(status: status).map {
                ProjectChip(label: $0.label, url: $0.url, kind: $0.kind == .site ? .site : .tool)
            },
            isLocalReachable: status.isRunning,
            onOpen: onOpen
        )
    }

    private var controls: some View {
        CardActionRow(lifecycle + [
            CardAction(
                "Folder",
                systemImage: "folder",
                isEnabled: project.folderURL != nil,
                action: onRevealFolder
            ),
            CardAction(
                "Terminal",
                systemImage: "terminal",
                isEnabled: project.folderURL != nil,
                action: onOpenTerminal
            ),
        ])
    }

    private var lifecycle: [CardAction] {
        if isDockerBlocked {
            return [
                DockerGate.startAction(docker, onStart: onStartDocker),
                CardAction("Restart", systemImage: "arrow.clockwise", isEnabled: false),
            ]
        }
        if status.isRunning {
            return [
                CardAction("Stop", systemImage: "power", tint: DeckTheme.red, isProminent: true) {
                    onAction(.stop)
                },
                CardAction("Restart", systemImage: "arrow.clockwise") { onAction(.restart) },
            ]
        }
        return [
            CardAction(
                "Start",
                systemImage: "play.fill",
                tint: DeckTheme.green,
                isEnabled: !status.isBusy,
                isProminent: true
            ) {
                onAction(.start)
            },
            CardAction("Restart", systemImage: "arrow.clockwise", isEnabled: false),
        ]
    }
}
