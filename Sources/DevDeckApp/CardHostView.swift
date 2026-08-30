import AppKit
import ArcKit
import DDEVKit
import DevDeckCore
import DevDeckUI
import GitHubKit
import GitLabKit
import ProjectKit
import SwiftUI

/// Maps a card identifier onto its view and its panel size.
///
/// The single place that knows "this identifier draws that card" - adding a card means one
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
                    isCollapsed: controller.isCollapsed(card),
                    onOpen: open,
                    onToggleExpand: { controller.toggleExpanded(card) },
                    onOpenDashboard: { openDashboard(for: card) }
                )
            } else if card == .githubInbox {
                InboxCard(
                    state: controller.inbox,
                    accountLabels: controller.accountLabels,
                    isExpanded: controller.isExpanded(card),
                    isCollapsed: controller.isCollapsed(card),
                    onOpen: open,
                    onToggleExpand: { controller.toggleExpanded(card) },
                    onOpenDashboard: { openDashboard(for: card) },
                    onMarkRead: { controller.markRead($0) }
                )
            } else if card == .gitlabMergeRequests {
                MergeRequestsCard(
                    state: controller.mergeRequests,
                    accountLabels: controller.gitlabAccountLabels,
                    isExpanded: controller.isExpanded(card),
                    isCollapsed: controller.isCollapsed(card),
                    onOpen: openGitLab,
                    onToggleExpand: { controller.toggleExpanded(card) },
                    onOpenDashboard: { openDashboard(for: card) }
                )
            } else if card == .githubActions {
                ActionsCard(
                    state: controller.actions,
                    isCollapsed: controller.isCollapsed(card),
                    onOpen: open,
                    onOpenDashboard: { openDashboard(for: card) }
                )
            } else if let project = controller.ddevProject(forCard: card) {
                DDEVProjectCard(
                    project: project,
                    status: controller.ddevStatus(for: project),
                    docker: controller.docker,
                    logs: controller.logs(for: card),
                    isCollapsed: controller.isCollapsed(card),
                    phoneURL: phoneURL(for: project),
                    onOpen: { LinkOpener.open($0, using: project.browser) },
                    onAction: { controller.perform($0, for: project) },
                    onRevealFolder: { LocalFolder.reveal(project.folderURL) },
                    onOpenTerminal: { LocalFolder.openTerminal(project.folderURL) },
                    onStartDocker: startDocker,
                    onToggleLogs: { controller.toggleLogs(for: card) },
                    onOpenLogFile: { LocalFolder.open($0) }
                )
            } else if let project = controller.project(forCard: card) {
                ArcProjectCard(
                    project: project,
                    status: controller.stackStatus(for: project),
                    docker: controller.docker,
                    logs: controller.logs(for: card),
                    isCollapsed: controller.isCollapsed(card),
                    phoneURL: phoneURL(for: project),
                    onOpen: { LinkOpener.open($0, using: project.browser) },
                    onAction: { controller.perform($0, for: project) },
                    onRevealFolder: { LocalFolder.reveal(project.folderURL) },
                    onOpenTerminal: { LocalFolder.openTerminal(project.folderURL) },
                    onStartDocker: startDocker,
                    onToggleLogs: { controller.toggleLogs(for: card) },
                    onOpenLogFile: { LocalFolder.open($0) }
                )
            } else if let project = controller.localProject(forCard: card) {
                LocalProjectCard(
                    project: project,
                    status: controller.localStatus(for: project),
                    docker: controller.docker,
                    logs: controller.logs(for: card),
                    isCollapsed: controller.isCollapsed(card),
                    phoneURL: phoneURL(for: project),
                    onOpen: { LinkOpener.open($0, using: project.browser) },
                    onAction: { controller.perform($0, for: project) },
                    onOpenTerminal: { LocalFolder.openTerminal(project.folderURL) },
                    onRevealFolder: { LocalFolder.reveal(project.folderURL) },
                    onStartDocker: startDocker,
                    onToggleLogs: { controller.toggleLogs(for: card) },
                    onOpenLogFile: { LocalFolder.open($0) }
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

    /// Nil on a machine whose runtime has no application to open, which is how the cards know
    /// to show a disabled Start rather than a button that would do nothing.
    private var startDocker: (() -> Void)? {
        controller.canStartDocker ? { controller.startDockerRuntime() } : nil
    }

    /// Rows open in the browser of the account they belong to - one signed-in GitHub identity
    /// per browser profile is the whole reason accounts exist.
    /// GitLab rows open in the browser of the instance they came from, for the same reason
    /// GitHub rows do: one signed-in identity per browser profile.
    private func openGitLab(_ url: URL, _ accountID: String) {
        LinkOpener.open(url, using: controller.gitlabBrowser(for: accountID))
    }

    /// The site as another device on this network would ask for it, per kind of project.
    ///
    /// Three overloads rather than one, because "where does this project serve" is answered from
    /// a different place for each: DDEV knows, Arc reads the checkout's `.env`, and a plain
    /// project was told.
    private func phoneURL(for project: DDEVProject) -> URL? {
        let status = controller.ddevStatus(for: project)
        return controller.phoneURL(for: status.entry?.primaryURL, isRunning: status.isRunning)
    }

    private func phoneURL(for project: ArcProject) -> URL? {
        let status = controller.stackStatus(for: project)
        return controller.phoneURL(for: status.siteURL ?? project.localSiteURL, isRunning: status.isRunning)
    }

    private func phoneURL(for project: LocalProject) -> URL? {
        let status = controller.localStatus(for: project)
        return controller.phoneURL(for: project.siteURL ?? project.healthCheckURL, isRunning: status.isRunning)
    }

    /// The same place a double-click on the panel goes. A collapsed list card has no lifecycle
    /// to offer, so this is its one action.
    private func openDashboard(for card: CardID) {
        guard let url = CardHostView.dashboardURL(for: card) else { return }
        let account = card == .gitlabMergeRequests
            ? controller.gitlabAccountLabels.keys.sorted().first ?? ""
            : controller.accountLabels.keys.sorted().first ?? ""
        let browser = card == .gitlabMergeRequests
            ? controller.gitlabBrowser(for: account)
            : controller.browser(for: account)
        LinkOpener.open(url, using: browser)
    }

    private func open(_ url: URL, _ accountID: String) {
        LinkOpener.open(url, using: controller.browser(for: accountID))
    }

    @MainActor
    static func size(for card: CardID, controller: DeckController) -> NSSize {
        switch card {
        case .githubPullRequests:
            return PullRequestsCard.size(
                for: controller.pullRequests,
                isExpanded: controller.isExpanded(card),
                isCollapsed: controller.isCollapsed(card)
            )
        case .githubInbox:
            return InboxCard.size(
                for: controller.inbox,
                isExpanded: controller.isExpanded(card),
                isCollapsed: controller.isCollapsed(card)
            )
        case .githubActions:
            return ActionsCard.size(isCollapsed: controller.isCollapsed(card))
        case .gitlabMergeRequests:
            return MergeRequestsCard.size(
                for: controller.mergeRequests,
                isExpanded: controller.isExpanded(card),
                isCollapsed: controller.isCollapsed(card)
            )
        default:
            if let project = controller.ddevProject(forCard: card) {
                return DDEVProjectCard.size(
                    for: project,
                    status: controller.ddevStatus(for: project),
                    logs: controller.logs(for: card),
                    isCollapsed: controller.isCollapsed(card)
                )
            }
            if let project = controller.localProject(forCard: card) {
                return LocalProjectCard.size(
                    for: project,
                    status: controller.localStatus(for: project),
                    logs: controller.logs(for: card),
                    isCollapsed: controller.isCollapsed(card)
                )
            }
            guard let project = controller.project(forCard: card) else {
                return NSSize(width: CardMetrics.width, height: 150)
            }
            return ArcProjectCard.size(
                for: project,
                status: controller.stackStatus(for: project),
                logs: controller.logs(for: card),
                isCollapsed: controller.isCollapsed(card)
            )
        }
    }

    /// Where a double-click on the panel background goes: the same data, on the web.
    static func dashboardURL(for card: CardID) -> URL? {
        switch card {
        case .githubPullRequests:
            return URL(string: "https://github.com/pulls")
        case .githubInbox:
            return URL(string: "https://github.com/notifications")
        case .gitlabMergeRequests:
            // The instance is per account, so the dashboard cannot be a constant. The card's
            // own rows carry absolute URLs; this is only the double-click on the background.
            return URL(string: "https://gitlab.com/dashboard/merge_requests")
        case .githubActions:
            // Actions has no cross-repository page; the closest thing is the dashboard.
            return URL(string: "https://github.com")
        default:
            return nil
        }
    }
}
