import DevDeckCore
import ProjectKit
import SwiftUI

/// One plain project: whether it is up, where to open it, and the command that starts it.
///
/// The same shape as the Arc and DDEV cards and built from the same pieces. What differs is
/// that nothing here can describe itself — there is no `ddev list` to ask — so the card shows
/// exactly what was configured, and the health URL is the only thing that decides "running".
public struct LocalProjectCard: View {
    private let project: LocalProject
    private let status: LocalProjectStatus
    private let docker: DockerStatus
    private let onOpen: (URL) -> Void
    private let onAction: (LocalProjectAction) -> Void
    private let onOpenLog: () -> Void
    private let onRevealFolder: () -> Void
    private let onStartDocker: (() -> Void)?

    public init(
        project: LocalProject,
        status: LocalProjectStatus,
        docker: DockerStatus = DockerStatus(state: .unknown),
        onOpen: @escaping (URL) -> Void = { _ in },
        onAction: @escaping (LocalProjectAction) -> Void = { _ in },
        onOpenLog: @escaping () -> Void = {},
        onRevealFolder: @escaping () -> Void = {},
        onStartDocker: (() -> Void)? = nil
    ) {
        self.project = project
        self.status = status
        self.docker = docker
        self.onOpen = onOpen
        self.onAction = onAction
        self.onOpenLog = onOpenLog
        self.onRevealFolder = onRevealFolder
        self.onStartDocker = onStartDocker
    }

    nonisolated public static func size(for project: LocalProject, status: LocalProjectStatus) -> CGSize {
        CGSize(
            width: CardMetrics.width,
            height: ProjectCardMetrics.height(
                tools: project.toolLinks().map(\.label),
                environments: project.environmentLinks().map(\.label),
                hasBranch: status.branch != nil,
                hasMetaRow: true
            )
        )
    }

    public var body: some View {
        CardChrome(
            title: "Project · \(project.displayTitle)",
            glyph: glyph,
            timestamp: ProjectCardMetrics.timestamp(status.checkedAt)
        ) {
            hero
            CardMetaBlock(branch: status.branch, leading: metaLeading, trailing: project.startCommand)
            chips
            controls
            Spacer(minLength: 0)
        }
    }

    /// What this project is built on. Nothing declares it, so it is read from the command —
    /// which is the one thing every plain project definitely has.
    private var glyph: CardGlyph {
        switch project.kind {
        case .node: return .node
        case .docker: return .docker
        case .make: return .make
        case .other: return .project
        }
    }

    private var isDockerBlocked: Bool {
        DockerGate.blocks(docker, isRunning: status.isRunning, requiresDocker: project.requiresDocker)
    }

    private var hero: some View {
        CardHeroRow(
            color: heroColor,
            text: heroText,
            note: status.pid.map { "pid \($0)" },
            help: status.detail ?? heroText
        )
    }

    private var heroColor: Color {
        if isDockerBlocked { return DockerGate.color(docker) }
        switch status.state {
        case .running: return DeckTheme.green
        case .starting, .working: return DeckTheme.amber
        case .stopped, .unavailable: return DeckTheme.label
        }
    }

    private var heroText: String {
        if isDockerBlocked { return DockerGate.text(docker) }
        switch status.state {
        case .running: return "running"
        case .starting: return "starting…"
        case .working: return status.detail ?? "working…"
        case .stopped: return "stopped"
        case .unavailable: return "not configured"
        }
    }

    private var metaLeading: String? {
        let subtitle = project.subtitle.trimmingCharacters(in: .whitespaces)
        let folder = project.folderURL?.lastPathComponent
        let parts = [subtitle.isEmpty ? nil : subtitle, folder].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var chips: some View {
        ProjectChipRow(
            tools: project.toolLinks().map { ProjectChip(label: $0.label, url: $0.url, kind: .tool) },
            environments: project.environmentLinks().map {
                ProjectChip(label: $0.label, url: $0.url, kind: $0.kind == .site ? .site : .tool)
            },
            isLocalReachable: status.isRunning,
            onOpen: onOpen
        )
    }

    /// Logs rather than Terminal, unlike the Arc and DDEV cards: a command started from here
    /// writes to a file nobody else knows about, and a card that can start something it cannot
    /// show the output of is a card that hides its own failures.
    private var controls: some View {
        CardActionRow(lifecycle + [
            CardAction("Logs", systemImage: "doc.text", isEnabled: status.hasLog, action: onOpenLog),
            CardAction(
                "Folder",
                systemImage: "folder",
                isEnabled: project.folderURL != nil,
                action: onRevealFolder
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
        if status.isRunning || status.state == .starting {
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
                isEnabled: !status.isBusy && project.supportsCommands,
                isProminent: true
            ) {
                onAction(.start)
            },
            CardAction("Restart", systemImage: "arrow.clockwise", isEnabled: false),
        ]
    }
}
