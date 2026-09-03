import DevDeckCore
import ProjectKit
import AppKit
import SwiftUI

/// One plain project: whether it is up, where to open it, and the command that starts it.
///
/// The same shape as the Arc and DDEV cards and built from the same pieces. What differs is
/// that nothing here can describe itself - there is no `ddev list` to ask - so the card shows
/// exactly what was configured, and the health URL is the only thing that decides "running".
public struct LocalProjectCard: View {
    private let project: LocalProject
    private let status: LocalProjectStatus
    private let docker: DockerStatus
    private let logs: LogLines?
    private let isCollapsed: Bool
    /// The same site, addressed for another device on this network. Nil unless it is running.
    private let phoneURL: URL?
    @State private var isShowingPhone = false
    private let onOpen: (URL) -> Void
    private let onAction: (LocalProjectAction) -> Void
    private let onOpenTerminal: () -> Void
    private let onRevealFolder: () -> Void
    private let onStartDocker: (() -> Void)?
    private let onToggleLogs: (() -> Void)?
    private let onOpenLogFile: ((URL) -> Void)?

    public init(
        project: LocalProject,
        status: LocalProjectStatus,
        docker: DockerStatus = DockerStatus(state: .unknown),
        logs: LogLines? = nil,
        isCollapsed: Bool = false,
        phoneURL: URL? = nil,
        onOpen: @escaping (URL) -> Void = { _ in },
        onAction: @escaping (LocalProjectAction) -> Void = { _ in },
        onOpenTerminal: @escaping () -> Void = {},
        onRevealFolder: @escaping () -> Void = {},
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
        self.onOpen = onOpen
        self.onAction = onAction
        self.onOpenTerminal = onOpenTerminal
        self.onRevealFolder = onRevealFolder
        self.onStartDocker = onStartDocker
        self.onToggleLogs = onToggleLogs
        self.onOpenLogFile = onOpenLogFile
    }

    nonisolated public static func size(for project: LocalProject, status: LocalProjectStatus, logs: LogLines? = nil, isCollapsed: Bool = false) -> CGSize {
        guard !isCollapsed else {
            return CGSize(width: CardMetrics.width, height: CollapsedCardMetrics.height)
        }
        return CGSize(
            width: CardMetrics.width,
            height: ProjectCardMetrics.height(
                tools: project.toolLinks().map(\.label),
                environments: project.environmentLinks().map(\.label),
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
            glyph: glyph,
            title: project.displayTitle,
            note: collapsedNote,
            tone: heroState.tone,
            color: heroState.color,
            actions: collapsedActions,
            help: status.detail ?? heroText
        )
    }

    /// What a folded card keeps: the action the state implies, a restart when it can be done,
    /// a terminal, and the site while there is one to open.
    ///
    /// Folder is left out although the full card has it, because a terminal opens in the folder
    /// anyway and a row this size cannot spend 24 points saying the same thing twice. A disabled
    /// control is left out too, apart from the lifecycle one: four squares of which two cannot be
    /// pressed reads as a broken row rather than an idle project.
    private var collapsedActions: [CardAction] {
        var actions: [CardAction] = []
        if let first = lifecycle.first { actions.append(first) }
        actions.append(contentsOf: lifecycle.dropFirst().filter(\.isEnabled))
        actions.append(CardAction("Terminal", systemImage: "terminal", action: onOpenTerminal))
        if let site = status.isRunning ? (project.siteURL ?? project.healthCheckURL) : nil {
            actions.append(CardAction("Open the site", systemImage: "arrow.up.forward") { onOpen(site) })
        }
        return actions
    }

    /// Running says how many containers; anything else says what it is. The dot has already
    /// said which of the two this is, so the words do not repeat it.
    private var collapsedNote: String? {
        if status.isRunning, let pid = status.pid { return "pid \(pid)" }
        return heroText
    }

    private var full: some View {
        CardChrome(
            title: "Project · \(project.displayTitle)",
            glyph: glyph,
            timestamp: ProjectCardMetrics.timestamp(status.checkedAt),
            toggles: headerToggles
        ) {
            hero
            CardMetaBlock(
                branch: status.branch,
                repositoryURL: status.repositoryURL,
                leading: metaLeading,
                trailing: project.startCommand,
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

    /// What this project is built on. Nothing declares it, so it is read from the command -
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
            color: heroState.color,
            tone: heroState.tone,
            text: heroText,
            note: status.pid.map { "pid \($0)" },
            help: status.detail ?? heroText
        )
    }

    private var heroState: (color: Color, tone: CardStateTone) {
        if isDockerBlocked { return (DockerGate.color(docker), .alert) }
        switch status.state {
        case .running: return (DeckTheme.green, .good)
        case .starting, .working: return (DeckTheme.amber, .alert)
        case .stopped, .unavailable: return (DeckTheme.label, .neutral)
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

    /// The same four as the Arc and DDEV cards now. Logs used to have a button here, back when
    /// reading them meant opening a file in Console; the tray shows them in place, and the whole
    /// file is one click away inside it.
    private var controls: some View {
        CardActionRow(lifecycle + [
            CardAction("Terminal", systemImage: "terminal", action: onOpenTerminal),
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
