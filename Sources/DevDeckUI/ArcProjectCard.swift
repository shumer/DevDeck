import ArcKit
import DevDeckCore
import SwiftUI

/// One Arc XP project: where to open it, and whether its local stack is up.
public struct ArcProjectCard: View {
    /// Everything except the chip rows and the branch line.
    private static let baseHeight: Double = 158
    private static let chipRowHeight: Double = 25
    private static let branchRowHeight: Double = 18

    /// Height from what the card will actually contain.
    ///
    /// The chip rows never wrap — each is a plain stack whose membership is fixed — so the
    /// count is simply how many of the two rows have anything in them, plus the branch line.
    nonisolated public static func size(for project: ArcProject, status: LocalStackStatus) -> CGSize {
        var rows = 0
        if !project.adminLinks.isEmpty { rows += 1 }
        if !project.siteLinks.isEmpty || (status.siteURL ?? project.localSiteURL) != nil { rows += 1 }

        return CGSize(
            width: CardMetrics.width,
            height: baseHeight
                + Double(rows) * chipRowHeight
                + (status.branch != nil ? branchRowHeight : 0)
        )
    }

    private let project: ArcProject
    private let status: LocalStackStatus
    private let now: Date
    private let onOpen: (URL) -> Void
    private let onAction: (LocalStackAction) -> Void
    private let onRevealFolder: () -> Void
    private let onOpenTerminal: () -> Void

    public init(
        project: ArcProject,
        status: LocalStackStatus,
        now: Date = Date(),
        onOpen: @escaping (URL) -> Void = { _ in },
        onAction: @escaping (LocalStackAction) -> Void = { _ in },
        onRevealFolder: @escaping () -> Void = {},
        onOpenTerminal: @escaping () -> Void = {}
    ) {
        self.project = project
        self.status = status
        self.now = now
        self.onOpen = onOpen
        self.onAction = onAction
        self.onRevealFolder = onRevealFolder
        self.onOpenTerminal = onOpenTerminal
    }

    public var body: some View {
        CardChrome(title: "Arc · \(project.title)", pill: pill) {
            links
            separator
            stackRow
            branchRow
            controls
            // The footer is a different kind of thing from the buttons above it — reading
            // material, not controls — so it gets air rather than sitting against them.
            Spacer(minLength: 12)
            CardFooter(leading: project.organization, trailing: freshness, isStale: false)
        }
    }

    private var pill: (text: String, color: Color)? {
        switch status.state {
        case .running: return ("local running", DeckTheme.green)
        case .stopped: return ("local stopped", DeckTheme.label)
        case .working: return (status.detail ?? "working…", DeckTheme.amber)
        case .unavailable: return ("no folder", DeckTheme.label)
        }
    }

    private var links: some View {
        // Two rows, and plain stacks rather than a wrapping layout: the membership of each row
        // is decided here, not by where a line happens to break.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(project.adminLinks) { link in
                    chip(link.label, color: DeckTheme.blue, help: link.url.absoluteString) {
                        onOpen(link.url)
                    }
                }
                Spacer(minLength: 0)
            }
            environmentRow
        }
        .padding(.top, 11)
    }

    /// One chip on the environment row.
    private struct EnvironmentChip: Identifiable {
        let id: String
        let label: String
        let color: Color
        let isDimmed: Bool
        let help: String
        let url: URL?
    }

    /// Built as one list rather than a conditional followed by a `ForEach`, so the order on
    /// screen is the order written here — local first, then the published environments.
    private var environmentChips: [EnvironmentChip] {
        var chips: [EnvironmentChip] = []

        if let local = status.siteURL ?? project.localSiteURL {
            chips.append(
                EnvironmentChip(
                    id: "local",
                    // "Local site" rather than the port: the port is an implementation detail
                    // of this checkout, and it is one hover away for anyone who wants it.
                    label: "Local site",
                    color: status.isRunning ? DeckTheme.green : DeckTheme.label,
                    isDimmed: !status.isRunning,
                    help: status.isRunning
                        ? local.absoluteString
                        : "\(local.absoluteString) — the local stack is not running",
                    // Opening a stopped stack lands on a connection error, which reads as a
                    // broken app rather than a stopped one.
                    url: status.isRunning ? local : nil
                )
            )
        }

        for link in project.siteLinks {
            chips.append(
                EnvironmentChip(
                    id: link.label,
                    label: link.label,
                    color: colour(for: link),
                    isDimmed: false,
                    help: link.url.absoluteString,
                    url: link.url
                )
            )
        }

        return chips
    }

    private var environmentRow: some View {
        HStack(spacing: 6) {
            ForEach(environmentChips) { item in
                chip(item.label, color: item.color, isDimmed: item.isDimmed, help: item.help) {
                    guard let url = item.url else { return }
                    onOpen(url)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func colour(for link: ResolvedLink) -> Color {
        // Production is the one worth a beat of hesitation, so it is the one that is not
        // calm — the same amber the other cards use for "someone should look at this".
        link.label.lowercased().contains("prod") ? DeckTheme.amber : DeckTheme.violet
    }

    private func chip(
        _ label: String,
        color: Color,
        isDimmed: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isDimmed ? color.opacity(0.45) : color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(isDimmed ? 0.07 : 0.15), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .clickable(cornerRadius: 7, isEnabled: !isDimmed)
            .onTapGesture(perform: action)
            .help(help)
    }

    /// A real element between the two halves of the card rather than an overlay nudged into
    /// place. The overlay was anchored to the top of the row below it, so every attempt to
    /// give it room moved the text down and the line further up into the chips.
    private var separator: some View {
        Rectangle()
            .fill(DeckTheme.faint)
            .frame(height: 1)
            .padding(.top, 12)
    }

    private var stackRow: some View {
        HStack(spacing: 8) {
            Circle().fill(stackColor).frame(width: 7, height: 7)
            Text(stackText)
                .font(.system(size: 12.5))
                .foregroundStyle(status.state == .running ? DeckTheme.value : DeckTheme.label)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if let version = status.engineVersion {
                Text(version)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DeckTheme.label)
                    .fixedSize()
            }
        }
        .padding(.top, 10)
        .help(status.detail ?? stackText)
    }

    /// What the stack is serving. It changes under you when you switch branches in a
    /// terminal, which is exactly when it is worth seeing.
    @ViewBuilder
    private var branchRow: some View {
        if let branch = status.branch {
            HStack(spacing: 8) {
                Text("⎇")
                    .font(.system(size: 11))
                    .foregroundStyle(DeckTheme.label)
                Text(branch)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(DeckTheme.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
            .help("checked out branch")
        }
    }

    private var stackColor: Color {
        switch status.state {
        case .running: return DeckTheme.green
        case .working: return DeckTheme.amber
        case .stopped, .unavailable: return DeckTheme.label
        }
    }

    private var stackText: String {
        switch status.state {
        case .running:
            guard let containers = status.containers else { return "local stack up" }
            return "docker · \(containers) container\(containers == 1 ? "" : "s")"
        case .working:
            return status.detail ?? "working…"
        case .stopped:
            return status.detail ?? "local stack not running"
        case .unavailable:
            return "set a project folder in settings"
        }
    }

    /// The four buttons share the full width, so the row lines up with the footer beneath it
    /// and with the card's own edges instead of trailing off mid-card.
    private var controls: some View {
        HStack(spacing: 6) {
            if status.isRunning {
                button("⏻ Stop", tint: DeckTheme.red) { onAction(.stop) }
                button("↻ Restart") { onAction(.restart) }
            } else {
                button("▶ Start", tint: DeckTheme.green, isEnabled: !status.isBusy && project.supportsLocalStack) {
                    onAction(.start)
                }
                button("↻ Restart", isEnabled: false) {}
            }
            button("Folder", isEnabled: project.supportsLocalStack, action: onRevealFolder)
            button("Terminal", isEnabled: project.supportsLocalStack, action: onOpenTerminal)
        }
        .padding(.top, 12)
    }

    private func button(
        _ title: String,
        tint: Color = DeckTheme.value,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(isEnabled ? tint : tint.opacity(0.3))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            // A resting fill, not just a hairline border: on glass a bare outline reads as a
            // label rather than as something to press.
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isEnabled ? 0.1 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isEnabled ? tint.opacity(0.45) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
            .clickable(cornerRadius: 8, isEnabled: isEnabled)
            .onTapGesture { if isEnabled { action() } }
    }

    private var freshness: String {
        guard let checkedAt = status.checkedAt else { return "not checked" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: checkedAt)
    }
}
