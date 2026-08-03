import DevDeckCore
import ProjectKit
import SwiftUI

/// One plain project: where to open it, whether it is up, and the command that starts it.
///
/// The same shape as the Arc and DDEV cards and built from the same pieces. What differs is
/// that nothing here can describe itself — there is no `ddev list` to ask — so the card shows
/// exactly what was configured, and the health URL is the only thing that decides "running".
public struct LocalProjectCard: View {
    private nonisolated static let baseHeight: Double = 150
    private nonisolated static let chipRowHeight: Double = 25

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
        var rows = 0
        if !project.toolLinks().isEmpty { rows += 1 }
        if !project.environmentLinks().isEmpty { rows += 1 }

        return CGSize(
            width: CardMetrics.width,
            height: baseHeight
                + Double(rows) * chipRowHeight
                + (status.branch != nil ? CardBranchRow.height : 0)
        )
    }

    public var body: some View {
        CardChrome(title: "Project · \(project.displayTitle)", pill: pill) {
            links
            CardSeparator()
            stateRow
            branchRow
            controls
            Spacer(minLength: 12)
            CardFooter(leading: footerLeading, trailing: freshness, isStale: false)
        }
    }

    /// Whether the card is currently about Docker rather than about the project.
    private var isDockerBlocked: Bool {
        DockerGate.blocks(docker, isRunning: status.isRunning, requiresDocker: project.requiresDocker)
    }

    private var pill: (text: String, color: Color)? {
        if isDockerBlocked { return DockerGate.pill(docker) }
        switch status.state {
        case .running: return ("running", DeckTheme.green)
        case .starting: return ("starting…", DeckTheme.amber)
        case .stopped: return ("stopped", DeckTheme.label)
        case .working: return (status.detail ?? "working…", DeckTheme.amber)
        case .unavailable: return ("not configured", DeckTheme.label)
        }
    }

    /// Two rows, as on the other project cards: tooling on top, the environments below.
    private var links: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(project.toolLinks())
            row(project.environmentLinks())
        }
        .padding(.top, 11)
    }

    private func row(_ links: [LocalProjectResolvedLink]) -> some View {
        HStack(spacing: 6) {
            ForEach(links) { link in
                let isLocal = link.kind == .site && link.label == "Local site"
                // A deployed environment is reachable whether or not anything is running here;
                // only the local one goes nowhere, and a link into a stopped project lands on a
                // connection error that reads as a broken app.
                let isDimmed = isLocal && !status.isRunning
                CardChip(
                    link.label,
                    color: colour(for: link, isLocal: isLocal),
                    isDimmed: isDimmed,
                    help: isDimmed
                        ? "\(link.url.absoluteString) — the project is not running"
                        : link.url.absoluteString
                ) {
                    guard !isDimmed else { return }
                    onOpen(link.url)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func colour(for link: LocalProjectResolvedLink, isLocal: Bool) -> Color {
        guard link.kind == .site else { return DeckTheme.blue }
        if isLocal { return DeckTheme.green }
        // Production is the one worth a beat of hesitation, so it is the one that is not calm.
        return link.label.lowercased().contains("prod") ? DeckTheme.amber : DeckTheme.violet
    }

    private var stateRow: some View {
        CardStateRow(
            color: stateColor,
            text: stateText,
            isProminent: status.isRunning || isDockerBlocked,
            trailing: status.pid.map { "pid \($0)" },
            help: status.detail ?? stateText
        )
    }

    private var stateColor: Color {
        if isDockerBlocked { return DockerGate.color(docker) }
        switch status.state {
        case .running: return DeckTheme.green
        case .starting, .working: return DeckTheme.amber
        case .stopped, .unavailable: return DeckTheme.label
        }
    }

    private var stateText: String {
        if isDockerBlocked { return DockerGate.text(docker) }
        switch status.state {
        case .running: return status.detail ?? project.startCommand
        case .starting, .working: return status.detail ?? "working…"
        case .stopped: return status.detail ?? "not running"
        case .unavailable: return status.detail ?? "not configured"
        }
    }

    @ViewBuilder
    private var branchRow: some View {
        if let branch = status.branch {
            CardBranchRow(branch)
        }
    }

    /// Logs rather than Terminal, unlike the Arc and DDEV cards: a command started from here
    /// writes to a file nobody else knows about, and a card that can start something it cannot
    /// show the output of is a card that hides its own failures.
    private var controls: some View {
        HStack(spacing: 6) {
            if isDockerBlocked {
                DockerGate.startButton(docker, onStart: onStartDocker)
                CardActionButton("↻ Restart", isEnabled: false) {}
            } else if status.isRunning || status.state == .starting {
                CardActionButton("⏻ Stop", tint: DeckTheme.red) { onAction(.stop) }
                CardActionButton("↻ Restart") { onAction(.restart) }
            } else {
                CardActionButton(
                    "▶ Start",
                    tint: DeckTheme.green,
                    isEnabled: !status.isBusy && project.supportsCommands
                ) {
                    onAction(.start)
                }
                CardActionButton("↻ Restart", isEnabled: false) {}
            }
            CardActionButton("Logs", isEnabled: status.hasLog, action: onOpenLog)
            CardActionButton("Folder", isEnabled: project.folderURL != nil, action: onRevealFolder)
        }
        .padding(.top, 12)
    }

    private var footerLeading: String {
        let subtitle = project.subtitle.trimmingCharacters(in: .whitespaces)
        let folder = project.folderURL?.lastPathComponent
        let parts = [subtitle.isEmpty ? nil : subtitle, folder].compactMap { $0 }
        return parts.isEmpty ? project.startCommand : parts.joined(separator: " · ")
    }

    private var freshness: String {
        guard let checkedAt = status.checkedAt else { return "not checked" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: checkedAt)
    }
}
