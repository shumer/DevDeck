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
    /// Everything above the rows: title, count and footer.
    public static let baseHeight: Double = 127

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
        CardChrome(title: "GitHub · my pull requests", pill: pill) {
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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(snapshot.totalCount)")
                .font(.system(size: 42, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(snapshot.blockedCount > 0 ? DeckTheme.red : DeckTheme.green)
            Text("open")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DeckTheme.label)
        }
        .padding(.top, 2)

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

        CardFooter(
            leading: snapshot.failures.summary ?? footerLeading(snapshot),
            trailing: CardFreshness.text(for: state),
            isStale: state.failure != nil
                || !snapshot.failures.isEmpty
                || state.isStale(now: now, maxAge: 600)
        )
    }

    private func row(_ pullRequest: PullRequestSummary) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(pullRequest.health.color)
                .frame(width: 7, height: 7)
            if accountLabels.count > 1, let label = accountLabels[pullRequest.accountID] {
                AccountChip(label)
            }
            Text(pullRequest.title)
                .font(.system(size: 12.5))
                .foregroundStyle(DeckTheme.value)
                .lineLimit(1)
                .truncationMode(.middle)
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
