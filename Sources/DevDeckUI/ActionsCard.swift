import DevDeckCore
import GitHubKit
import SwiftUI

/// "GitHub Actions": is the pipeline healthy, and what is broken right now.
public struct ActionsCard: View {
    public nonisolated static let visibleRows = 2
    public nonisolated static let size = CGSize(width: CardMetrics.width, height: 190)

    private let state: CardState<ActionsSnapshot>
    private let now: Date
    private let onOpen: (URL, String) -> Void
    private let isCollapsed: Bool
    /// Whether the repositories come from the open pull requests, because no list was given in
    /// Settings. It decides what an empty card says and what the footer says it is watching.
    private let followsPullRequests: Bool
    private let onOpenDashboard: () -> Void
    /// Opens Settings on the field that names the repositories, for the empty card's link.
    private let onChooseRepositories: (() -> Void)?

    public init(
        state: CardState<ActionsSnapshot>,
        now: Date = Date(),
        isCollapsed: Bool = false,
        followsPullRequests: Bool = true,
        onOpen: @escaping (URL, String) -> Void = { _, _ in },
        onOpenDashboard: @escaping () -> Void = {},
        onChooseRepositories: (() -> Void)? = nil
    ) {
        self.state = state
        self.now = now
        self.isCollapsed = isCollapsed
        self.followsPullRequests = followsPullRequests
        self.onOpen = onOpen
        self.onOpenDashboard = onOpenDashboard
        self.onChooseRepositories = onChooseRepositories
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
            title: L("card.title.actions"),
            note: collapsedNote,
            tone: collapsedTone.tone,
            color: collapsedTone.color,
            actions: [CardAction(L("card.action.openInBrowser"), systemImage: "arrow.up.forward", action: onOpenDashboard)],
            help: collapsedNote ?? L("card.title.actions")
        )
    }

    private var collapsedNote: String? {
        guard let snapshot = state.value else { return state.failure?.displayMessage ?? L("card.pill.loading") }
        if snapshot.repositories.isEmpty { return quietReason }
        if snapshot.failedCount > 0 { return L("card.actions.failing", snapshot.failedCount) }
        guard let rate = snapshot.successRate else { return L("card.actions.noRuns") }
        return L("card.actions.green", Int((rate * 100).rounded()))
    }

    private var collapsedTone: (tone: CardStateTone, color: Color) {
        guard let snapshot = state.value else { return (.neutral, DeckTheme.label) }
        if snapshot.failedCount > 0 { return (.alert, DeckTheme.red) }
        return snapshot.successRate == nil ? (.neutral, DeckTheme.label) : (.good, DeckTheme.green)
    }

    private var full: some View {
        CardChrome(title: L("card.chrome.actions"), pill: pill) {
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
        if snapshot.repositories.isEmpty { return (quietReason, DeckTheme.label) }
        guard let rate = snapshot.successRate else { return (L("card.actions.noRuns"), DeckTheme.label) }
        if rate < 0.8 || snapshot.failedCount > 0 { return (L("card.actions.attention"), DeckTheme.red) }
        return (L("card.actions.healthy"), DeckTheme.green)
    }

    @ViewBuilder
    private func content(_ snapshot: ActionsSnapshot) -> some View {
        if snapshot.repositories.isEmpty {
            emptyConfiguration
        } else if snapshot.runs.isEmpty {
            quietWindow(snapshot)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(headline(snapshot))
                    .font(.system(size: 42, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(headlineColor(snapshot))
                Text(snapshot.successRate == nil ? L("card.actions.noRuns") : L("card.actions.successWindow", snapshot.windowDays))
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
        guard let rate = snapshot.successRate else { return L("card.na") }
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
            Text(run.status.isActive ? L("card.state.running") : RelativeTime.short(from: run.updatedAt, to: now))
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.label)
                .fixedSize()
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1) }
        .contentShape(Rectangle())
        .clickable(isEnabled: run.url != nil)
        .onTapGesture { if let url = run.url { onOpen(url, run.accountID) } }
        .help(L("card.actions.run.help", run.repository, run.name, run.branch))
    }

    private func activity(_ snapshot: ActionsSnapshot) -> String {
        var parts: [String] = []
        if snapshot.runningCount > 0 { parts.append(L("card.actions.running", snapshot.runningCount)) }
        if snapshot.failedCount > 0 { parts.append(L("card.actions.failed", snapshot.failedCount)) }
        // Where the repositories came from, so the card says what it is watching and why: the
        // choice it makes by itself is the one nobody could see until it came up empty.
        if parts.isEmpty {
            parts.append(Self.watching(snapshot.repositories.count, followsPullRequests: followsPullRequests))
        }
        if let average = snapshot.averageDurationSeconds {
            parts.append(L("card.actions.avg", RelativeTime.duration(average)))
        }
        return parts.joined(separator: " · ")
    }

    /// Repositories to watch and nothing ran in them. It used to be "n/a" at 42 points beside
    /// "no runs", which read as a card that had broken rather than one with nothing to report:
    /// the same quiet shape as the empty card instead, saying what was looked at and for how long.
    @ViewBuilder
    private func quietWindow(_ snapshot: ActionsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 8)
            Text(LN("card.actions.quiet.title", snapshot.windowDays))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DeckTheme.value)
            Text(L("card.actions.quiet.detail", Self.watchedNames(snapshot.repositories)))
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.label)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Spacer(minLength: 8)
        }
        CardFooter(
            leading: snapshot.failures.summary ?? activity(snapshot),
            trailing: CardFreshness.text(for: state),
            isStale: state.failure != nil
                || !snapshot.failures.isEmpty
                || state.isStale(now: now, maxAge: 900)
        )
    }

    /// The repositories by their own names, `site, web and 1 more`: the owner is the same on
    /// nearly every one and would take the whole line.
    public nonisolated static func watchedNames(_ repositories: [String]) -> String {
        AttentionWords.list(repositories.map { $0.split(separator: "/").last.map(String.init) ?? $0 })
    }

    /// Why an empty card is empty, for the pill and the folded row. With no list of its own the
    /// card follows the open pull requests, so an empty card means there are none: a normal,
    /// quiet state. "no repos" read as a card somebody forgot to set up.
    private var quietReason: String {
        Self.quietReason(followsPullRequests: followsPullRequests)
    }

    public nonisolated static func quietReason(followsPullRequests: Bool) -> String {
        followsPullRequests ? L("card.actions.noOpenPRs") : L("card.actions.noRepos")
    }

    /// What the footer says the card is watching, and where that list came from.
    public nonisolated static func watching(_ count: Int, followsPullRequests: Bool) -> String {
        followsPullRequests
            ? LN("card.actions.repos.fromPulls", count)
            : LN("card.actions.repos.fromList", count)
    }

    /// The quiet state: what the card does, why there is nothing in it, and the one thing to do
    /// about it, which opens the field rather than pointing vaguely at Settings.
    private var emptyConfiguration: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 8)
            Text(L("card.actions.empty.title"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DeckTheme.value)
            Text(L("card.actions.empty.detail"))
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.label)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let onChooseRepositories {
                Text(L("card.actions.empty.choose"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DeckTheme.blue)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .clickable(cornerRadius: 5)
                    .onTapGesture { onChooseRepositories() }
                    .padding(.top, 6)
            }
            Spacer(minLength: 8)
        }
    }
}
