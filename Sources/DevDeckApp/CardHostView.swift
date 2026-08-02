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
                PullRequestsCard(state: controller.pullRequests) { url in
                    NSWorkspace.shared.open(url)
                }
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

    static func size(for card: CardID) -> NSSize {
        switch card {
        case .githubPullRequests: return PullRequestsCard.size
        default: return NSSize(width: 320, height: 150)
        }
    }

    /// Where a double-click on the panel background goes: the same data, on the web.
    static func dashboardURL(for card: CardID) -> URL? {
        switch card {
        case .githubPullRequests:
            return URL(string: "https://github.com/pulls")
        default:
            return nil
        }
    }
}
