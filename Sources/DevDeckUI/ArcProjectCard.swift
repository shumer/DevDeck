import ArcKit
import DevDeckCore
import SwiftUI

/// One Arc XP project: whether its local stack is up, and where to open it.
public struct ArcProjectCard: View {
    private let project: ArcProject
    private let status: LocalStackStatus
    private let docker: DockerStatus
    private let now: Date
    private let onOpen: (URL) -> Void
    private let onAction: (LocalStackAction) -> Void
    private let onRevealFolder: () -> Void
    private let onOpenTerminal: () -> Void
    private let onStartDocker: (() -> Void)?

    public init(
        project: ArcProject,
        status: LocalStackStatus,
        docker: DockerStatus = DockerStatus(state: .unknown),
        now: Date = Date(),
        onOpen: @escaping (URL) -> Void = { _ in },
        onAction: @escaping (LocalStackAction) -> Void = { _ in },
        onRevealFolder: @escaping () -> Void = {},
        onOpenTerminal: @escaping () -> Void = {},
        onStartDocker: (() -> Void)? = nil
    ) {
        self.project = project
        self.status = status
        self.docker = docker
        self.now = now
        self.onOpen = onOpen
        self.onAction = onAction
        self.onRevealFolder = onRevealFolder
        self.onOpenTerminal = onOpenTerminal
        self.onStartDocker = onStartDocker
    }

    nonisolated public static func size(for project: ArcProject, status: LocalStackStatus) -> CGSize {
        CGSize(
            width: CardMetrics.width,
            height: ProjectCardMetrics.height(
                tools: project.adminLinks.map(\.label),
                environments: environmentChips(project: project, status: status).map(\.label),
                hasBranch: status.branch != nil,
                hasMetaRow: true
            )
        )
    }

    public var body: some View {
        CardChrome(
            title: "Arc · \(project.title)",
            glyph: .arc,
            timestamp: ProjectCardMetrics.timestamp(status.checkedAt)
        ) {
            hero
            CardMetaBlock(branch: status.branch, leading: project.organization, trailing: status.engineVersion)
            chips
            controls
            Spacer(minLength: 0)
        }
    }

    /// Whether the card is about Docker rather than about the stack. Fusion runs in containers,
    /// so a project with a folder always needs it.
    private var isDockerBlocked: Bool {
        DockerGate.blocks(
            docker,
            isRunning: status.isRunning,
            requiresDocker: project.supportsLocalStack
        )
    }

    private var hero: some View {
        CardHeroRow(
            color: heroColor,
            text: heroText,
            note: heroNote,
            help: status.detail ?? heroText
        )
    }

    private var heroColor: Color {
        if isDockerBlocked { return DockerGate.color(docker) }
        switch status.state {
        case .running: return DeckTheme.green
        case .working: return DeckTheme.amber
        case .stopped, .unavailable: return DeckTheme.label
        }
    }

    private var heroText: String {
        // Docker first: `fusion daemon` fails at the first container without it, and "local
        // stack not running" would be a true sentence that helps nobody.
        if isDockerBlocked { return DockerGate.text(docker) }
        // One vocabulary across all three cards: running, stopped, starting…, and the rest.
        // "local stopped" here against "not running" there made two identical states look like
        // two different ones.
        switch status.state {
        case .running: return "running"
        case .working: return status.detail ?? "working…"
        case .stopped: return "stopped"
        case .unavailable: return "not configured"
        }
    }

    /// The container count earns the trailing slot only while the stack is up; otherwise the
    /// reason the last command failed is the more useful thing to carry.
    private var heroNote: String? {
        if isDockerBlocked { return nil }
        if status.isRunning, let containers = status.containers {
            return "\(containers) container\(containers == 1 ? "" : "s")"
        }
        return status.state == .stopped ? status.detail : nil
    }

    private var chips: some View {
        ProjectChipRow(
            tools: project.adminLinks.map { ProjectChip(label: $0.label, url: $0.url, kind: .tool) },
            environments: Self.environmentChips(project: project, status: status),
            isLocalReachable: status.isRunning,
            onOpen: onOpen
        )
    }

    /// Local first, then the published environments — built as one list so the order on screen
    /// is the order written here rather than wherever a conditional child lands.
    nonisolated private static func environmentChips(
        project: ArcProject,
        status: LocalStackStatus
    ) -> [ProjectChip] {
        var chips: [ProjectChip] = []
        if let local = status.siteURL ?? project.localSiteURL {
            // "Local site" rather than the port: the port is an implementation detail of this
            // checkout, and it is one hover away for anyone who wants it.
            chips.append(ProjectChip(label: ProjectChipRow.localLabel, url: local, kind: .site))
        }
        chips.append(contentsOf: project.siteLinks.map {
            ProjectChip(label: $0.label, url: $0.url, kind: .site)
        })
        return chips
    }

    private var controls: some View {
        CardActionRow(lifecycle + [
            CardAction(
                "Folder",
                systemImage: "folder",
                isEnabled: project.supportsLocalStack,
                action: onRevealFolder
            ),
            CardAction(
                "Terminal",
                systemImage: "terminal",
                isEnabled: project.supportsLocalStack,
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
                isEnabled: !status.isBusy && project.supportsLocalStack,
                isProminent: true
            ) {
                onAction(.start)
            },
            CardAction("Restart", systemImage: "arrow.clockwise", isEnabled: false),
        ]
    }
}
