import AppKit
import DevDeckCore
import DevDeckUI
import GitHubKit
import SwiftUI

/// Maps a card identifier onto its view and its panel size.
///
/// The single place that knows "this identifier draws that card" — adding a card means one
/// case here and one descriptor in `CardCatalog`.
struct CardHostView: View {
    @ObservedObject var controller: DeckController
    let card: CardID

    var body: some View {
        Group {
            if card == .githubPullRequests {
                PullRequestsCard(state: controller.pullRequests, onOpen: open)
            } else if card == .githubInbox {
                InboxCard(state: controller.inbox, onOpen: open)
            } else if card == .githubActions {
                ActionsCard(state: controller.actions, onOpen: open)
            } else {
                unimplemented
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if let url = CardHostView.dashboardURL(for: card) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var unimplemented: some View {
        CardChrome(title: CardCatalog.descriptor(for: card)?.title ?? card.rawValue) {
            Spacer()
            Text("Not built yet")
                .font(.system(size: 13))
                .foregroundStyle(DeckTheme.label)
            Spacer()
        }
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func size(for card: CardID) -> NSSize {
        switch card {
        case .githubPullRequests: return PullRequestsCard.size
        case .githubInbox: return InboxCard.size
        case .githubActions: return ActionsCard.size
        default: return NSSize(width: 320, height: 150)
        }
    }

    /// Where a double-click on the panel background goes: the same data, on the web.
    static func dashboardURL(for card: CardID) -> URL? {
        switch card {
        case .githubPullRequests:
            return URL(string: "https://github.com/pulls")
        case .githubInbox:
            return URL(string: "https://github.com/notifications")
        case .githubActions:
            // Actions has no cross-repository page; the closest thing is the dashboard.
            return URL(string: "https://github.com")
        default:
            return nil
        }
    }
}
