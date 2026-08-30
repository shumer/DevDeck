import DevDeckCore
import GitLabKit
import SwiftUI

// Deliberately the GitHub card with the nouns changed: same layout, same order, same vocabulary
// for the three states. Two cards on one desktop that answer the same question in two different
// shapes would be two things to learn instead of one.

public extension MergeRequestHealth {
    var color: Color {
        switch self {
        case .blocked: return DeckTheme.red
        case .attention: return DeckTheme.amber
        case .ready: return DeckTheme.green
        }
    }
}

/// Pull requests: yours, plus the ones waiting on a review from you.
///
/// Both halves of "what do I owe today" on one card. A review someone is waiting on sits just
/// under the blocked ones and carries an eye rather than the two-letter code of its own state:
/// what matters about it is not whether its checks pass but that it is not yours.
public struct MergeRequestsCard: View {
    /// Everything that is not a row: chrome, the count, the distribution bar and the footer.
    public nonisolated static let baseHeight: Double = 110

    private let state: CardState<MergeRequestsSnapshot>
    private let now: Date
    /// Account id to label. More than one entry turns the per-row chips on.
    private let accountLabels: [String: String]
    private let isExpanded: Bool
    private let isCollapsed: Bool
    private let onOpen: (URL, String) -> Void
    private let onToggleExpand: () -> Void
    private let onOpenDashboard: () -> Void

    public init(
        state: CardState<MergeRequestsSnapshot>,
        now: Date = Date(),
        accountLabels: [String: String] = [:],
        isExpanded: Bool = false,
        isCollapsed: Bool = false,
        onOpen: @escaping (URL, String) -> Void = { _, _ in },
        onToggleExpand: @escaping () -> Void = {},
        onOpenDashboard: @escaping () -> Void = {}
    ) {
        self.state = state
        self.now = now
        self.accountLabels = accountLabels
        self.isExpanded = isExpanded
        self.isCollapsed = isCollapsed
        self.onOpen = onOpen
        self.onToggleExpand = onToggleExpand
        self.onOpenDashboard = onOpenDashboard
    }

    /// Panel size for the current contents. The app resizes the window with this, so the card
    /// and the panel never disagree about how much room the rows need.
    public nonisolated static func size(
        for state: CardState<MergeRequestsSnapshot>,
        isExpanded: Bool,
        isCollapsed: Bool = false
    ) -> CGSize {
        guard !isCollapsed else {
            return CGSize(width: CardMetrics.width, height: CollapsedCardMetrics.height)
        }
        let total = state.value?.mergeRequests.count ?? 0
        return CGSize(
            width: CardMetrics.width,
            height: CardMetrics.height(base: baseHeight, total: total, isExpanded: isExpanded)
        )
    }

    public var body: some View {
        if isCollapsed {
            collapsed
        } else {
            full
        }
    }

    /// One row: the mark, a dot for how loud the card is, its name and the count. A list card
    /// has no lifecycle to offer, so its single action is the one thing it can do - open the
    /// same list on the web.
    private var collapsed: some View {
        CardCollapsedRow(
            glyph: CardGlyph.gitlab,
            title: "Merge requests",
            note: collapsedNote,
            tone: collapsedTone.tone,
            color: collapsedTone.color,
            action: CardAction("Open in browser", systemImage: "arrow.up.forward", action: onOpenDashboard),
            help: collapsedNote ?? "Merge requests"
        )
    }

    /// The pill's words, which are already the shortest true sentence about the card.
    private var collapsedNote: String? {
        guard let snapshot = state.value else { return state.failure?.displayMessage ?? "loading" }
        if snapshot.blockedCount > 0 { return "\(snapshot.blockedCount) blocked · \(snapshot.totalCount) open" }
        if snapshot.reviewRequestCount > 0 { return "\(snapshot.reviewRequestCount) to review · \(snapshot.totalCount) open" }
        return snapshot.totalCount == 0 ? "clear" : "\(snapshot.totalCount) open"
    }

    private var collapsedTone: (tone: CardStateTone, color: Color) {
        guard let snapshot = state.value else { return (.neutral, DeckTheme.label) }
        if snapshot.blockedCount > 0 { return (.alert, DeckTheme.red) }
        if snapshot.reviewRequestCount > 0 { return (.alert, DeckTheme.amber) }
        return (.good, DeckTheme.green)
    }

    private var full: some View {
        CardChrome(
            title: "GitLab · merge requests",
            glyph: .gitlab,
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
        // Someone waiting on you outranks anything of yours that is merely in progress.
        if snapshot.reviewRequestCount > 0 {
            return ("\(snapshot.reviewRequestCount) to review", DeckTheme.amber)
        }
        if snapshot.totalCount == 0 {
            return ("clear", DeckTheme.green)
        }
        return ("on track", DeckTheme.green)
    }

    @ViewBuilder
    private func content(_ snapshot: MergeRequestsSnapshot) -> some View {
        // The count is the hero, but 26 rather than the 42 it used to be: it was the largest
        // thing on the deck and it is not the most important one. It is also plain now. A number
        // that turns red when something is blocked says the same thing twice, since the words
        // beside it already say which and how many.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(snapshot.totalCount)")
                .font(.system(size: 26, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(DeckTheme.value.opacity(0.85))
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

        let total = snapshot.mergeRequests.count
        let rows = CardMetrics.rowCount(total: total, isExpanded: isExpanded)

        VStack(spacing: 0) {
            ForEach(snapshot.prioritized(limit: rows)) { mergeRequest in
                row(mergeRequest)
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
    /// Three points of height for the shape of the whole list, which the three visible rows
    /// cannot give: two blocked out of eight reads differently from two out of two.
    @ViewBuilder
    private func healthBar(_ snapshot: MergeRequestsSnapshot) -> some View {
        let counts = [MergeRequestHealth.blocked, .attention, .ready]
            .map { health in snapshot.mergeRequests.filter { $0.health == health }.count }

        if counts.reduce(0, +) > 0 {
            HStack(spacing: 2) {
                ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
                    if count > 0 {
                        Capsule()
                            .fill([DeckTheme.red, DeckTheme.amber, DeckTheme.green][index].opacity(0.62))
                            .frame(maxWidth: .infinity)
                            .layoutPriority(Double(count))
                    }
                }
            }
            .frame(height: 3)
            .padding(.top, 8)
        }
    }

    private func row(_ mergeRequest: MergeRequestSummary) -> some View {
        let ticket = mergeRequest.ticket

        return HStack(spacing: 7) {
            Circle()
                .fill(mergeRequest.health.color)
                .frame(width: 6, height: 6)
            if accountLabels.count > 1, let label = accountLabels[mergeRequest.accountID] {
                AccountChip(label)
            }
            // The ticket key gets its own monospaced column: left in the sentence it eats the
            // width the subject needs, which is how a row reads `IR-6257 - Dr…r the core flip.`
            // Not mine: the row is here because somebody is waiting, and the eye needs to know
            // that before it reads the title.
            if mergeRequest.isReviewRequest {
                Image(systemName: "eye")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(DeckTheme.amber)
                    .help("waiting for your review")
            }
            if let key = ticket.key {
                Text(key)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeckTheme.value.opacity(0.55))
                    .fixedSize()
            }
            Text(ticket.subject)
                .font(.system(size: 11.5))
                .foregroundStyle(DeckTheme.value.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(mergeRequest.statusCode)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(DeckTheme.value.opacity(0.58))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: CardMetrics.rowHeight - 1)
        .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1) }
        .contentShape(Rectangle())
        .clickable()
        .onTapGesture { onOpen(mergeRequest.url, mergeRequest.accountID) }
        .help("\(mergeRequest.shortLabel): \(mergeRequest.statusLine)")
    }

    private func footerLeading(_ snapshot: MergeRequestsSnapshot) -> String {
        let projects = snapshot.projectCount
        let groups = snapshot.groupCount
        var text = "\(projects) project\(projects == 1 ? "" : "s") · \(groups) group\(groups == 1 ? "" : "s")"
        // Only the rows beyond the expanded ceiling are worth mentioning here; the ones the
        // expander would reveal are its own business.
        let beyondCeiling = CardMetrics.hiddenWhenExpanded(total: snapshot.mergeRequests.count)
        if isExpanded, beyondCeiling > 0 { text += " · +\(beyondCeiling) not shown" }
        return text
    }
}
