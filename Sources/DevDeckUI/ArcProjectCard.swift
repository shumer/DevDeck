import ArcKit
import DevDeckCore
import AppKit
import SwiftUI

/// One Arc XP project: whether its local stack is up, and where to open it.
public struct ArcProjectCard: View {
    private let project: ArcProject
    private let status: LocalStackStatus
    private let docker: DockerStatus
    private let logs: LogLines?
    private let isCollapsed: Bool
    /// The same site, addressed for another device on this network. Nil unless it is running.
    private let phoneURL: URL?
    @State private var isShowingPhone = false
    private let now: Date
    private let onOpen: (URL) -> Void
    private let onAction: (LocalStackAction) -> Void
    private let onRevealFolder: () -> Void
    private let onOpenTerminal: () -> Void
    private let onStartDocker: (() -> Void)?
    private let onToggleLogs: (() -> Void)?
    private let onOpenLogFile: ((URL) -> Void)?

    public init(
        project: ArcProject,
        status: LocalStackStatus,
        docker: DockerStatus = DockerStatus(state: .unknown),
        logs: LogLines? = nil,
        isCollapsed: Bool = false,
        phoneURL: URL? = nil,
        now: Date = Date(),
        onOpen: @escaping (URL) -> Void = { _ in },
        onAction: @escaping (LocalStackAction) -> Void = { _ in },
        onRevealFolder: @escaping () -> Void = {},
        onOpenTerminal: @escaping () -> Void = {},
        onStartDocker: (() -> Void)? = nil,
        onToggleLogs: (() -> Void)? = nil,
        onOpenLogFile: ((URL) -> Void)? = nil
    ) {
        self.project = project
        self.status = status
        self.docker = docker
        self.logs = logs
        self.isCollapsed = isCollapsed
        self.phoneURL = phoneURL
        self.now = now
        self.onOpen = onOpen
        self.onAction = onAction
        self.onRevealFolder = onRevealFolder
        self.onOpenTerminal = onOpenTerminal
        self.onStartDocker = onStartDocker
        self.onToggleLogs = onToggleLogs
        self.onOpenLogFile = onOpenLogFile
    }

    nonisolated public static func size(for project: ArcProject, status: LocalStackStatus, logs: LogLines? = nil, isCollapsed: Bool = false) -> CGSize {
        guard !isCollapsed else {
            return CGSize(width: CardMetrics.width, height: CollapsedCardMetrics.height)
        }
        return CGSize(
            width: CardMetrics.width,
            height: ProjectCardMetrics.height(
                tools: project.adminLinks.map(\.label),
                environments: environmentChips(project: project, status: status).map(\.label),
                hasBranch: status.branch != nil,
                hasMetaRow: true,
                logs: logs
            )
        )
    }

    public var body: some View {
        if isCollapsed {
            collapsed
        } else {
            full
        }
    }

    /// One row: the mark, the state dot, the name and the action the state implies.
    private var collapsed: some View {
        CardCollapsedRow(
            glyph: CardGlyph.arc,
            title: project.title,
            note: collapsedNote,
            tone: heroState.tone,
            color: heroState.color,
            action: lifecycle.first,
            help: status.detail ?? heroText
        )
    }

    /// Running says how many containers; anything else says what it is. The dot has already
    /// said which of the two this is, so the words do not repeat it.
    private var collapsedNote: String? {
        if status.isRunning, let note = heroNote { return note }
        return heroText
    }

    private var full: some View {
        CardChrome(
            title: "Arc · \(project.title)",
            glyph: .arc,
            timestamp: ProjectCardMetrics.timestamp(status.checkedAt),
            toggles: headerToggles
        ) {
            hero
            CardMetaBlock(
                branch: status.branch,
                repositoryURL: status.repositoryURL,
                // While a command runs, the line it just printed takes the meta slot: it is the
                // only thing on the card that is changing, and it answers "is anything
                // happening" without the card having to grow a log window.
                leading: status.isBusy ? (status.progressLine ?? project.organization) : project.organization,
                trailing: status.isBusy ? nil : status.engineVersion,
                onOpenRepository: onOpen
            )
            chips
            if let logs {
                CardLogTray(logs: logs, onOpenFile: onOpenLogFile)
            }
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
            color: heroState.color,
            tone: heroState.tone,
            text: heroText,
            note: heroNote,
            help: status.detail ?? heroText
        )
    }

    private var heroState: (color: Color, tone: CardStateTone) {
        if isDockerBlocked { return (DockerGate.color(docker), .alert) }
        switch status.state {
        // Running with something to say about it is not the same as running: a stop that did
        // not take effect leaves the stack up, and the card has to look wrong about it.
        case .running where status.detail != nil: return (DeckTheme.amber, .alert)
        case .running: return (DeckTheme.green, .good)
        case .working: return (DeckTheme.amber, .alert)
        case .stopped, .unavailable: return (DeckTheme.label, .neutral)
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
        case .running: return status.detail ?? "running"
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

    /// Local first, then the published environments - built as one list so the order on screen
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
        if let editor = project.localPageBuilderURL {
            // Next to the local site, because it is the same stack: one is the page, the other is
            // where you edit it. The hosted PageBuilder link a few chips to the left edits
            // something else entirely.
            chips.append(ProjectChip(label: "PB editor", url: editor, kind: .site))
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

    /// The buttons in the header. The log tray, and the phone, which is only ever offered for a
    /// site that is actually being served: a QR code pointing at a port nothing is listening on
    /// is a worse answer than no button.
    private var headerToggles: [CardHeaderToggle] {
        var toggles: [CardHeaderToggle] = []
        if let onToggleLogs {
            toggles.append(CardHeaderToggle(
                id: "log",
                isOn: logs != nil,
                help: logs == nil ? "show the last log lines" : "hide the log"
            ) { onToggleLogs() })
        }
        if let phoneURL {
            toggles.append(CardHeaderToggle(
                id: "phone",
                isOn: isShowingPhone,
                systemImage: "qrcode",
                help: "open this on your phone",
                popover: AnyView(PhoneSheet(url: phoneURL, onCopy: copyToPasteboard))
            ) { isShowingPhone.toggle() })
        }
        return toggles
    }

    /// Puts the address where a phone cannot reach: the Mac's own pasteboard, for sending it on
    /// in a message when a camera is not to hand.
    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        isShowingPhone = false
    }
}
