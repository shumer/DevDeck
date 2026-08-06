import DevDeckCore
import GitHubKit
import SwiftUI

public extension PullRequestHealth {
    var color: Color {
        switch self {
        case .blocked: return DeckTheme.red
        case .attention: return DeckTheme.amber
        case .ready: return DeckTheme.green
        }
    }
}

/// "My pull requests": how many are open, and the ones that need something done.
public struct PullRequestsCard: View {
    /// Everything that is not a row: chrome, the count, the distribution bar and the footer.
    public nonisolated static let baseHeight: Double = 110

    private let state: CardState<PullRequestsSnapshot>
    private let now: Date
    /// Account id to label. More than one entry turns the per-row chips on.
    private let accountLabels: [String: String]
    private let isExpanded: Bool
    private let onOpen: (URL, String) -> Void
    private let onToggleExpand: () -> Void

    public init(
        state: CardState<PullRequestsSnapshot>,
        now: Date = Date(),
        accountLabels: [String: String] = [:],
        isExpanded: Bool = false,
        onOpen: @escaping (URL, String) -> Void = { _, _ in },
        onToggleExpand: @escaping () -> Void = {}
    ) {
        self.state = state
        self.now = now
        self.accountLabels = accountLabels
        self.isExpanded = isExpanded
        self.onOpen = onOpen
        self.onToggleExpand = onToggleExpand
    }

    /// Panel size for the current contents. The app resizes the window with this, so the card
    /// and the panel never disagree about how much room the rows need.
    public static func size(
        for state: CardState<PullRequestsSnapshot>,
        isExpanded: Bool
    ) -> CGSize {
        let total = state.value?.pullRequests.count ?? 0
        return CGSize(
            width: CardMetrics.width,
            height: CardMetrics.height(base: baseHeight, total: total, isExpanded: isExpanded)
        )
    }

    public var body: some View {
        CardChrome(
            title: "GitHub · my pull requests",
            glyph: .github,
            timestamp: CardFreshness.text(for: state)
        ) {
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
        if snapshot.blockedCount > 0 {
            return ("\(snapshot.blockedCount) blocked", DeckTheme.red)
        }
        if snapshot.totalCount == 0 {
            return ("clear", DeckTheme.green)
        }
        return ("on track", DeckTheme.green)
    }

    @ViewBuilder
    private func content(_ snapshot: PullRequestsSnapshot) -> some View {
        // The count is the hero, but 28 rather than the 42 it used to be: it was the largest
        // thing on the deck and it is not the most important one.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(snapshot.totalCount)")
                .font(.system(size: 28, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(snapshot.blockedCount > 0 ? DeckTheme.red : DeckTheme.green)
            Text("open")
                .font(.system(size: 12))
                .foregroundStyle(DeckTheme.label)
            Spacer(minLength: 6)
            if let pill {
                StatusPill(pill.text, color: pill.color)
            }
        }
        .frame(height: 30)
        .padding(.top, 6)

        healthBar(snapshot)

        let total = snapshot.pullRequests.count
        let rows = CardMetrics.rowCount(total: total, isExpanded: isExpanded)

        VStack(spacing: 0) {
            ForEach(snapshot.prioritized(limit: rows)) { pullRequest in
                row(pullRequest)
            }
        }
        .padding(.top, 6)

        if CardMetrics.showsExpander(total: total) {
            CardExpander(
                hidden: total - CardMetrics.collapsedRows,
                isExpanded: isExpanded,
                onToggle: onToggleExpand
            )
        }

        Spacer(minLength: 4)

        // The clock moved into the header, so the footer says what the header cannot: which
        // accounts came back empty, and whether what is on screen is still fresh.
        CardFooter(
            leading: snapshot.failures.summary ?? footerLeading(snapshot),
            trailing: state.isStale(now: now, maxAge: 600) ? "stale" : nil,
            isStale: state.failure != nil || !snapshot.failures.isEmpty
        )
    }

    /// How the open pull requests are spread across blocked, needs-attention and ready.
    ///
    /// Four points of height for the shape of the whole list, which the three visible rows
    /// cannot give: two blocked out of eight reads differently from two out of two.
    @ViewBuilder
    private func healthBar(_ snapshot: PullRequestsSnapshot) -> some View {
        let counts = [PullRequestHealth.blocked, .attention, .ready]
            .map { health in snapshot.pullRequests.filter { $0.health == health }.count }

        if counts.reduce(0, +) > 0 {
            HStack(spacing: 2) {
                ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
                    if count > 0 {
                        Capsule()
                            .fill([DeckTheme.red, DeckTheme.amber, DeckTheme.green][index].opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .layoutPriority(Double(count))
                    }
                }
            }
            .frame(height: 4)
            .padding(.top, 8)
        }
    }

    private func row(_ pullRequest: PullRequestSummary) -> some View {
        let ticket = pullRequest.ticket

        return HStack(spacing: 7) {
            Circle()
                .fill(pullRequest.health.color)
                .frame(width: 6, height: 6)
            if accountLabels.count > 1, let label = accountLabels[pullRequest.accountID] {
                AccountChip(label)
            }
            // The ticket key gets its own monospaced column: left in the sentence it eats the
            // width the subject needs, which is how a row reads `IR-6257 - Dr…r the core flip.`
            if let key = ticket.key {
                Text(key)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeckTheme.value.opacity(0.62))
                    .fixedSize()
            }
            Text(ticket.subject)
                .font(.system(size: 11.5))
                .foregroundStyle(DeckTheme.value)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(pullRequest.statusCode)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(DeckTheme.label)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: CardMetrics.rowHeight - 1)
        .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1) }
        .contentShape(Rectangle())
        .clickable()
        .onTapGesture { onOpen(pullRequest.url, pullRequest.accountID) }
        .help("\(pullRequest.shortLabel) — \(pullRequest.statusLine)")
    }

    private func footerLeading(_ snapshot: PullRequestsSnapshot) -> String {
        let repositories = snapshot.repositoryCount
        let organizations = snapshot.organizationCount
        var text = "\(repositories) repo\(repositories == 1 ? "" : "s") · \(organizations) org\(organizations == 1 ? "" : "s")"
        // Only the rows beyond the expanded ceiling are worth mentioning here; the ones the
        // expander would reveal are its own business.
        let beyondCeiling = CardMetrics.hiddenWhenExpanded(total: snapshot.pullRequests.count)
        if isExpanded, beyondCeiling > 0 { text += " · +\(beyondCeiling) not shown" }
        return text
    }
}
