import ArcKit
import DevDeckCore
import SwiftUI

/// One Arc XP project: where to open it, and whether its local stack is up.
public struct ArcProjectCard: View {
    public static let size = CGSize(width: CardMetrics.width, height: 184)

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
            stackRow
            controls
            Spacer(minLength: 2)
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
        // A wrapping row: five links at a readable size do not fit on one line at 320 points.
        FlowRow(spacing: 6) {
            ForEach(project.resolvedLinks, id: \.label) { link in
                chip(link.label, color: DeckTheme.blue, help: link.url.absoluteString) {
                    onOpen(link.url)
                }
            }
            if let local = status.siteURL ?? project.localSiteURL {
                // "Local site" rather than the port: the port is an implementation detail of
                // this checkout, and it is one hover away for anyone who wants it.
                chip(
                    "Local site",
                    color: status.isRunning ? DeckTheme.green : DeckTheme.label,
                    isDimmed: !status.isRunning,
                    help: status.isRunning
                        ? local.absoluteString
                        : "\(local.absoluteString) — the local stack is not running"
                ) {
                    // Opening a stopped stack lands on a connection error, which reads as a
                    // broken app rather than a stopped one.
                    guard status.isRunning else { return }
                    onOpen(local)
                }
            }
        }
        .padding(.top, 11)
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
        .padding(.top, 11)
        .padding(.bottom, 1)
        .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1).offset(y: -5) }
        .help(status.detail ?? stackText)
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
        .padding(.top, 10)
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
            .padding(.horizontal, 9)
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

/// A row that wraps onto the next line when it runs out of width.
///
/// `HStack` would clip the last chips, and the number of links is a per-project setting rather
/// than something the layout can assume.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? CardMetrics.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
