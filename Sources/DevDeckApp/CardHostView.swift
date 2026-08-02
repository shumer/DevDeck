import AppKit
import ArcKit
import DDEVKit
import DevDeckCore
import DevDeckUI
import GitHubKit
import SwiftUI

/// Maps a card identifier onto its view and its panel size.
///
/// The single place that knows "this identifier draws that card" — adding a card means one
/// branch here and one descriptor in `CardCatalog`.
struct CardHostView: View {
    @ObservedObject var controller: DeckController
    let card: CardID

    var body: some View {
        Group {
            if card == .githubPullRequests {
                PullRequestsCard(
                    state: controller.pullRequests,
                    accountLabels: controller.accountLabels,
                    isExpanded: controller.isExpanded(card),
                    onOpen: open,
                    onToggleExpand: { controller.toggleExpanded(card) }
                )
            } else if card == .githubInbox {
                InboxCard(
                    state: controller.inbox,
                    accountLabels: controller.accountLabels,
                    isExpanded: controller.isExpanded(card),
                    onOpen: open,
                    onToggleExpand: { controller.toggleExpanded(card) }
                )
            } else if card == .githubActions {
                ActionsCard(state: controller.actions, onOpen: open)
            } else if let project = controller.ddevProject(forCard: card) {
                DDEVProjectCard(
                    project: project,
                    status: controller.ddevStatus(for: project),
                    onOpen: { LinkOpener.open($0, using: project.browser) },
                    onAction: { controller.perform($0, for: project) },
                    onRevealFolder: { LocalFolder.reveal(project.folderURL) },
                    onOpenTerminal: { LocalFolder.openTerminal(project.folderURL) }
                )
            } else if let project = controller.project(forCard: card) {
                ArcProjectCard(
                    project: project,
                    status: controller.stackStatus(for: project),
                    onOpen: { LinkOpener.open($0, using: project.browser) },
                    onAction: { controller.perform($0, for: project) },
                    onRevealFolder: { LocalFolder.reveal(project.folderURL) },
                    onOpenTerminal: { LocalFolder.openTerminal(project.folderURL) }
                )
            } else {
                unimplemented
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard let url = CardHostView.dashboardURL(for: card) else { return }
            // The dashboard belongs to whichever account is first; there is no row to ask.
            LinkOpener.open(url, using: controller.browser(for: controller.accountLabels.keys.sorted().first ?? ""))
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

    /// Rows open in the browser of the account they belong to — one signed-in GitHub identity
    /// per browser profile is the whole reason accounts exist.
    private func open(_ url: URL, _ accountID: String) {
        LinkOpener.open(url, using: controller.browser(for: accountID))
    }

    @MainActor
    static func size(for card: CardID, controller: DeckController) -> NSSize {
        switch card {
        case .githubPullRequests:
            return PullRequestsCard.size(
                for: controller.pullRequests,
                isExpanded: controller.isExpanded(card)
            )
        case .githubInbox:
            return InboxCard.size(for: controller.inbox, isExpanded: controller.isExpanded(card))
        case .githubActions:
            return ActionsCard.size
        default:
            if let project = controller.ddevProject(forCard: card) {
                return DDEVProjectCard.size(for: project, status: controller.ddevStatus(for: project))
            }
            guard let project = controller.project(forCard: card) else {
                return NSSize(width: CardMetrics.width, height: 150)
            }
            return ArcProjectCard.size(for: project, status: controller.stackStatus(for: project))
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
