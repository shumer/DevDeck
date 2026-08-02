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

/// "My pull requests": how many are open, and the few that need something done.
public struct PullRequestsCard: View {
    /// How many rows fit before the card would have to scroll. Panels do not scroll —
    /// a widget that needs scrolling has stopped being glanceable.
    public static let visibleRows = 3
    public static let size = CGSize(width: 320, height: 208)

    private let state: CardState<PullRequestsSnapshot>
    private let now: Date
    private let onOpen: (URL) -> Void

    public init(
        state: CardState<PullRequestsSnapshot>,
        now: Date = Date(),
        onOpen: @escaping (URL) -> Void = { _ in }
    ) {
        self.state = state
        self.now = now
        self.onOpen = onOpen
    }

    public var body: some View {
        CardChrome(title: "GitHub · my pull requests", pill: pill) {
            if let snapshot = state.value {
                content(snapshot)
            } else {
                placeholder
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
                .font(.system(size: 42, weight: .bold, design: .default))
                .monospacedDigit()
                .foregroundStyle(snapshot.blockedCount > 0 ? DeckTheme.red : DeckTheme.green)
            Text("open")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DeckTheme.label)
        }
        .padding(.top, 2)

        VStack(spacing: 0) {
            ForEach(snapshot.prioritized(limit: Self.visibleRows)) { pullRequest in
                row(pullRequest)
            }
        }
        .padding(.top, 6)

        Spacer(minLength: 4)

        CardFooter(
            leading: footerLeading(snapshot),
            trailing: freshness,
            isStale: state.failure != nil || state.isStale(now: now, maxAge: 600)
        )
    }

    private func row(_ pullRequest: PullRequestSummary) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(pullRequest.health.color)
                .frame(width: 7, height: 7)
            Text(pullRequest.title)
                .font(.system(size: 12.5))
                .foregroundStyle(DeckTheme.value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(pullRequest.statusLine)
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.label)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { onOpen(pullRequest.url) }
        .help("\(pullRequest.shortLabel) — \(pullRequest.statusLine)")
    }

    @ViewBuilder
    private var placeholder: some View {
        Spacer(minLength: 8)
        Text(state.failure?.displayMessage ?? "Loading…")
            .font(.system(size: 13))
            .foregroundStyle(state.failure == nil ? DeckTheme.label : DeckTheme.red)
        if case .missingToken = state.failure {
            Text("Add a GitHub token in Settings")
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.label)
                .padding(.top, 2)
        }
        Spacer(minLength: 8)
    }

    private func footerLeading(_ snapshot: PullRequestsSnapshot) -> String {
        let repositories = snapshot.repositoryCount
        let organizations = snapshot.organizationCount
        let hidden = snapshot.pullRequests.count - Self.visibleRows
        var text = "\(repositories) repo\(repositories == 1 ? "" : "s") · \(organizations) org\(organizations == 1 ? "" : "s")"
        if hidden > 0 { text += " · +\(hidden) more" }
        return text
    }

    /// Shows the failure rather than the timestamp when the last refresh broke: a clock that
    /// keeps ticking while the data is frozen is the worst of both.
    private var freshness: String {
        if let failure = state.failure { return failure.displayMessage }
        guard let updatedAt = state.updatedAt else { return "never updated" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: updatedAt)
    }
}
