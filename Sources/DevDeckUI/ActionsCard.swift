import DevDeckCore
import GitHubKit
import SwiftUI

/// "GitHub Actions": is the pipeline healthy, and what is broken right now.
public struct ActionsCard: View {
    public static let visibleRows = 2
    public static let size = CGSize(width: CardMetrics.width, height: 190)

    private let state: CardState<ActionsSnapshot>
    private let now: Date
    private let onOpen: (URL, String) -> Void
    private let isCollapsed: Bool
    private let onOpenDashboard: () -> Void

    public init(
        state: CardState<ActionsSnapshot>,
        now: Date = Date(),
        isCollapsed: Bool = false,
        onOpen: @escaping (URL, String) -> Void = { _, _ in },
        onOpenDashboard: @escaping () -> Void = {}
    ) {
        self.state = state
        self.now = now
        self.isCollapsed = isCollapsed
        self.onOpen = onOpen
        self.onOpenDashboard = onOpenDashboard
    }

    /// A fixed height, unlike the other list cards: this one always draws two rows.
    public nonisolated static func size(isCollapsed: Bool) -> CGSize {
        isCollapsed ? CGSize(width: CardMetrics.width, height: CollapsedCardMetrics.height) : size
    }

    public var body: some View {
        if isCollapsed {
            collapsed
        } else {
            full
        }
    }

    /// One row. The success rate is the whole card in a number, and the one action a list card
    /// can offer is opening the same thing on the web.
    private var collapsed: some View {
        CardCollapsedRow(
            glyph: CardGlyph.github,
            title: "GitHub Actions",
            note: collapsedNote,
            tone: collapsedTone.tone,
            color: collapsedTone.color,
            action: CardAction("Open in browser", systemImage: "arrow.up.forward", action: onOpenDashboard),
            help: collapsedNote ?? "GitHub Actions"
        )
    }

    private var collapsedNote: String? {
        guard let snapshot = state.value else { return state.failure?.displayMessage ?? "loading" }
        if snapshot.failedCount > 0 { return "\(snapshot.failedCount) failing" }
        guard let rate = snapshot.successRate else { return "idle" }
        return "\(Int((rate * 100).rounded()))% green"
    }

    private var collapsedTone: (tone: CardStateTone, color: Color) {
        guard let snapshot = state.value else { return (.neutral, DeckTheme.label) }
        if snapshot.failedCount > 0 { return (.alert, DeckTheme.red) }
        return snapshot.successRate == nil ? (.neutral, DeckTheme.label) : (.good, DeckTheme.green)
    }

    private var full: some View {
        CardChrome(title: "GitHub · actions", pill: pill) {
            if let snapshot = state.value {
                content(snapshot)
            } else {
                CardPlaceholder(state: state)
            }
        }
    }

    private var pill: (text: String, color: Color)? {
        if let failure = state.failure, state.value == nil {
            return (failure.displayMessage, DeckTheme.red)
        }
        guard let snapshot = state.value else { return nil }
        if snapshot.repositories.isEmpty { return ("no repos", DeckTheme.label) }
        guard let rate = snapshot.successRate else { return ("idle", DeckTheme.label) }
        if rate < 0.8 || snapshot.failedCount > 0 { return ("attention", DeckTheme.red) }
        return ("healthy", DeckTheme.green)
    }

    @ViewBuilder
    private func content(_ snapshot: ActionsSnapshot) -> some View {
        if snapshot.repositories.isEmpty {
            emptyConfiguration
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(headline(snapshot))
                    .font(.system(size: 42, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(headlineColor(snapshot))
                Text(snapshot.successRate == nil ? "no runs" : "% success · \(snapshot.windowDays)d")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DeckTheme.label)
            }
            .padding(.top, 2)

            VStack(spacing: 0) {
                ForEach(rows(snapshot)) { run in
                    row(run)
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 4)

            CardFooter(
                leading: snapshot.failures.summary ?? activity(snapshot),
                trailing: CardFreshness.text(for: state),
                isStale: state.failure != nil
                    || !snapshot.failures.isEmpty
                    || state.isStale(now: now, maxAge: 900)
            )
        }
    }

    /// Failures are the reason to look; when there are none, show what is currently running.
    private func rows(_ snapshot: ActionsSnapshot) -> [WorkflowRun] {
        let failures = snapshot.recentFailures(limit: Self.visibleRows)
        guard failures.isEmpty else { return failures }
        return snapshot.active(limit: Self.visibleRows)
    }

    private func headline(_ snapshot: ActionsSnapshot) -> String {
        guard let rate = snapshot.successRate else { return "n/a" }
        return "\(Int((rate * 100).rounded()))"
    }

    private func headlineColor(_ snapshot: ActionsSnapshot) -> Color {
        guard let rate = snapshot.successRate else { return DeckTheme.label }
        if rate < 0.8 { return DeckTheme.red }
        if rate < 0.95 { return DeckTheme.amber }
        return DeckTheme.green
    }

    private func row(_ run: WorkflowRun) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(run.status.isActive ? DeckTheme.amber : DeckTheme.red)
                .frame(width: 7, height: 7)
            Text("\(run.shortRepository) · \(run.name)")
                .font(.system(size: 12.5))
                .foregroundStyle(DeckTheme.value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(run.status.isActive ? "running" : RelativeTime.short(from: run.updatedAt, to: now))
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.label)
                .fixedSize()
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1) }
        .contentShape(Rectangle())
        .clickable(isEnabled: run.url != nil)
        .onTapGesture { if let url = run.url { onOpen(url, run.accountID) } }
        .help("\(run.repository) · \(run.name) on \(run.branch)")
    }

    private func activity(_ snapshot: ActionsSnapshot) -> String {
        var parts: [String] = []
        if snapshot.runningCount > 0 { parts.append("\(snapshot.runningCount) running") }
        if snapshot.failedCount > 0 { parts.append("\(snapshot.failedCount) failed") }
        if parts.isEmpty { parts.append("\(snapshot.repositories.count) repos") }
        if let average = snapshot.averageDurationSeconds {
            parts.append("avg \(RelativeTime.duration(average))")
        }
        return parts.joined(separator: " · ")
    }

    private var emptyConfiguration: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 8)
            Text("No repositories to watch")
                .font(.system(size: 13))
                .foregroundStyle(DeckTheme.label)
            Text("Open a pull request, or list repositories in settings")
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.label)
            Spacer(minLength: 8)
        }
    }
}
