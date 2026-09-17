import AppKit
import DevDeckCore
import GitHubKit
import GitLabKit

/// What the menu-bar item is saying, and why: the attention digest, with the icon and the
/// tooltip that follow from it.
///
/// The menu used to open on one greyed-out line, `1 waiting on you`, which named nothing and could
/// not be clicked. The icon now says which tier is lit, and the menu lists the things themselves.
public struct DeckStatusSummary: Sendable, Equatable {
    public let digest: AttentionDigest

    public init(digest: AttentionDigest) {
        self.digest = digest
    }

    public var state: DeckIconState { DeckIconState(tier: digest.iconTier) }

    /// One line. The list belongs in the menu; the tooltip only has to say whether opening it is
    /// worth it.
    public var tooltip: String { "DevDeck: \(digest.summary)" }
}

/// Everything the deck knows, turned into one digest.
///
/// Pure and in one place, so the suite can check what lights the icon: GitLab used to be left out
/// of the count, a review was counted twice and a rejected token looked calm.
public enum DeckAttention {
    public struct Input: Sendable {
        public var activeCards: Set<CardID>
        public var pullRequests: CardState<PullRequestsSnapshot>
        public var inbox: CardState<InboxSnapshot>
        public var actions: CardState<ActionsSnapshot>
        public var mergeRequests: CardState<MergeRequestsSnapshot>
        /// Labels by account id, only when there is more than one account of that service.
        public var githubLabels: [String: String]
        public var gitlabLabels: [String: String]
        /// When each account started failing, keyed `service:id`.
        public var accountFailingSince: [String: Date]
        public var projects: [WatchedProject]
        public var watch: ProjectWatch
        public var docker: DockerStatus
        public var dockerDownSince: Date?
        public var checkouts: [CheckoutState]
        public var checkoutFolders: [String: URL]
        public var update: AttentionItem?

        public init(
            activeCards: Set<CardID>,
            pullRequests: CardState<PullRequestsSnapshot> = CardState(),
            inbox: CardState<InboxSnapshot> = CardState(),
            actions: CardState<ActionsSnapshot> = CardState(),
            mergeRequests: CardState<MergeRequestsSnapshot> = CardState(),
            githubLabels: [String: String] = [:],
            gitlabLabels: [String: String] = [:],
            accountFailingSince: [String: Date] = [:],
            projects: [WatchedProject] = [],
            watch: ProjectWatch = ProjectWatch(),
            docker: DockerStatus = DockerStatus(state: .unknown),
            dockerDownSince: Date? = nil,
            checkouts: [CheckoutState] = [],
            checkoutFolders: [String: URL] = [:],
            update: AttentionItem? = nil
        ) {
            self.activeCards = activeCards
            self.pullRequests = pullRequests
            self.inbox = inbox
            self.actions = actions
            self.mergeRequests = mergeRequests
            self.githubLabels = githubLabels
            self.gitlabLabels = gitlabLabels
            self.accountFailingSince = accountFailingSince
            self.projects = projects
            self.watch = watch
            self.docker = docker
            self.dockerDownSince = dockerDownSince
            self.checkouts = checkouts
            self.checkoutFolders = checkoutFolders
            self.update = update
        }
    }

    public static func digest(_ input: Input, now: Date) -> AttentionDigest {
        let active = input.activeCards
        var items: [AttentionItem] = []

        // A hidden card fetches nothing, and what it fetched before it was hidden is not news.
        items += GitHubAttention.items(
            pullRequests: active.contains(.githubPullRequests) ? input.pullRequests.value : nil,
            inbox: active.contains(.githubInbox) ? input.inbox.value : nil,
            actions: active.contains(.githubActions) ? input.actions.value : nil,
            labels: input.githubLabels
        )
        if active.contains(.gitlabMergeRequests) {
            items += GitLabAttention.items(mergeRequests: input.mergeRequests.value, labels: input.gitlabLabels)
        }

        items += AccountAttention.items(
            failures: githubFailures(input),
            service: .github,
            now: now,
            failingSince: since(input.accountFailingSince, service: .github)
        )
        if active.contains(.gitlabMergeRequests) {
            items += AccountAttention.items(
                failures: failures(of: input.mergeRequests, snapshot: input.mergeRequests.value?.failures),
                service: .gitlab,
                now: now,
                failingSince: since(input.accountFailingSince, service: .gitlab)
            )
        }

        items += ProjectAttention.items(
            projects: input.projects,
            watch: input.watch,
            docker: input.docker,
            dockerDownSince: input.dockerDownSince,
            now: now
        )
        if active.contains(.workInFlight) {
            items += CheckoutAttention.items(checkouts: input.checkouts, folders: input.checkoutFolders, now: now)
        }
        if let update = input.update { items.append(update) }
        return AttentionDigest(items: items)
    }

    /// Every GitHub account that failed on any active card, once.
    public static func githubFailures(_ input: Input) -> [AccountFailure] {
        let active = input.activeCards
        var all: [AccountFailure] = []
        if active.contains(.githubPullRequests) {
            all += failures(of: input.pullRequests, snapshot: input.pullRequests.value?.failures)
        }
        if active.contains(.githubInbox) {
            all += failures(of: input.inbox, snapshot: input.inbox.value?.failures)
        }
        if active.contains(.githubActions) {
            all += failures(of: input.actions, snapshot: input.actions.value?.failures)
        }
        return all
    }

    /// The failures a card is carrying: every account when the whole fetch failed, otherwise the
    /// ones the last good snapshot lists. A missing token is a failure too, with no account to
    /// name.
    public static func failures<Value>(of state: CardState<Value>, snapshot: [AccountFailure]?) -> [AccountFailure] {
        switch state.failure {
        case .accounts(let failures): return failures
        case .missingToken(let service):
            return [AccountFailure(account: service, message: "No \(service) token yet", kind: .rejected)]
        case .some(let error):
            return [AccountFailure(account: "all accounts", message: error.displayMessage, kind: error.isRetryable ? .unreachable : .other)]
        case .none:
            return snapshot ?? []
        }
    }

    static func since(_ all: [String: Date], service: AttentionService) -> [String: Date] {
        let prefix = "\(service.rawValue):"
        return Dictionary(
            all.compactMap { key, value in key.hasPrefix(prefix) ? (String(key.dropFirst(prefix.count)), value) : nil },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
