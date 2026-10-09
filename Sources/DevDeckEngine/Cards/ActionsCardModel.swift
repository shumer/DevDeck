import DevDeckCore
import Foundation
import GitHubKit

/// "GitHub Actions": is the pipeline healthy, and what is broken right now.
public struct ActionsCardModel: Sendable, Equatable, Codable {
    /// Two rows, always: failures are the reason to look, and when there are none, what is
    /// running.
    public static let visibleRows = 2

    public struct Row: Sendable, Equatable, Codable, Identifiable {
        public let id: Int
        public let tone: DeckTone
        public let title: String
        public let trailing: String
        public let help: String
        /// Nil for a run with no page.
        public let command: DeckCommand?
    }

    /// Words in place of numbers, for a card with nothing to count.
    public struct Notice: Sendable, Equatable, Codable {
        public let title: String
        public let detail: String
        /// The one thing to do about it, when there is one.
        public let link: DeckLinkModel?
    }

    public enum Content: Sendable, Equatable, Codable {
        /// No repositories to watch.
        case unconfigured(Notice)
        /// Repositories, and nothing ran in them.
        case quiet(Notice, footer: DeckFooterModel)
        /// The success rate, and the runs worth a look.
        case runs(headline: String, headlineTone: DeckTone, caption: String, rows: [Row], footer: DeckFooterModel)
    }

    public let title: String
    public let pill: DeckPillModel?
    public let content: Content?
    public let placeholder: DeckPlaceholderModel
    public let collapsed: DeckCollapsedModel
    public let isCollapsed: Bool

    /// - `followsPullRequests`: the repositories come from the open pull requests, because no
    ///   list was given in Settings. It decides what an empty card says and what the footer says
    ///   it is watching.
    public static func build(
        state: CardState<ActionsSnapshot>,
        followsPullRequests: Bool,
        isCollapsed: Bool,
        now: Date
    ) -> ActionsCardModel {
        ActionsCardModel(
            title: L("card.chrome.actions"),
            pill: pill(state, followsPullRequests: followsPullRequests),
            content: state.value.map { content($0, state: state, followsPullRequests: followsPullRequests, now: now) },
            placeholder: DeckPlaceholderModel(state),
            collapsed: collapsed(state, followsPullRequests: followsPullRequests),
            isCollapsed: isCollapsed
        )
    }

    /// The repositories by their own names, `site, web and 1 more`: the owner is the same on
    /// nearly every one and would take the whole line.
    public static func watchedNames(_ repositories: [String]) -> String {
        AttentionWords.list(repositories.map { $0.split(separator: "/").last.map(String.init) ?? $0 })
    }

    /// Why an empty card is empty, for the pill and the folded row. With no list of its own the
    /// card follows the open pull requests, so an empty card means there are none: a normal,
    /// quiet state. "no repos" read as a card somebody forgot to set up.
    public static func quietReason(followsPullRequests: Bool) -> String {
        followsPullRequests ? L("card.actions.noOpenPRs") : L("card.actions.noRepos")
    }

    /// What the footer says the card is watching, and where that list came from.
    public static func watching(_ count: Int, followsPullRequests: Bool) -> String {
        followsPullRequests
            ? LN("card.actions.repos.fromPulls", count)
            : LN("card.actions.repos.fromList", count)
    }

    private static func pill(_ state: CardState<ActionsSnapshot>, followsPullRequests: Bool) -> DeckPillModel? {
        if let failure = state.failure, state.value == nil {
            return DeckPillModel(failure.displayMessage, tone: .alert)
        }
        guard let snapshot = state.value else { return nil }
        if snapshot.repositories.isEmpty { return DeckPillModel(quietReason(followsPullRequests: followsPullRequests), tone: .neutral) }
        guard let rate = snapshot.successRate else { return DeckPillModel(L("card.actions.noRuns"), tone: .neutral) }
        if rate < 0.8 || snapshot.failedCount > 0 { return DeckPillModel(L("card.actions.attention"), tone: .alert) }
        return DeckPillModel(L("card.actions.healthy"), tone: .good)
    }

    private static func content(
        _ snapshot: ActionsSnapshot,
        state: CardState<ActionsSnapshot>,
        followsPullRequests: Bool,
        now: Date
    ) -> Content {
        if snapshot.repositories.isEmpty {
            // What the card does, why there is nothing in it, and the one thing to do about it,
            // which opens the field rather than pointing vaguely at Settings.
            let choose = L("card.actions.empty.choose")
            return .unconfigured(Notice(
                title: L("card.actions.empty.title"),
                detail: L("card.actions.empty.detail"),
                link: DeckLinkModel(title: choose, help: choose, command: .openSetting(.actionsRepositories))
            ))
        }
        let footer = DeckFooterModel(
            leading: snapshot.failures.summary ?? activity(snapshot, followsPullRequests: followsPullRequests),
            trailing: DeckCardTime.header(for: state),
            isStale: state.failure != nil || !snapshot.failures.isEmpty || state.isStale(now: now, maxAge: 900)
        )
        if snapshot.runs.isEmpty {
            // Repositories to watch and nothing ran in them. It used to be "n/a" at 42 points
            // beside "no runs", which read as a card that had broken rather than one with nothing
            // to report.
            return .quiet(Notice(
                title: LN("card.actions.quiet.title", snapshot.windowDays),
                detail: L("card.actions.quiet.detail", watchedNames(snapshot.repositories)),
                link: nil
            ), footer: footer)
        }
        let failures = snapshot.recentFailures(limit: visibleRows)
        let runs = failures.isEmpty ? snapshot.active(limit: visibleRows) : failures
        return .runs(
            headline: snapshot.successRate.map { "\(Int(($0 * 100).rounded()))" } ?? L("card.na"),
            headlineTone: headlineTone(snapshot.successRate),
            caption: snapshot.successRate == nil ? L("card.actions.noRuns") : L("card.actions.successWindow", snapshot.windowDays),
            rows: runs.map { run in
                Row(
                    id: run.id,
                    tone: run.status.isActive ? .attention : .alert,
                    title: "\(run.shortRepository) · \(run.name)",
                    trailing: run.status.isActive ? L("card.state.running") : DeckCardTime.age(from: run.updatedAt, to: now),
                    help: L("card.actions.run.help", run.repository, run.name, run.branch),
                    command: run.url.map { .openLink($0, account: run.accountID, service: .github) }
                )
            },
            footer: footer
        )
    }

    private static func headlineTone(_ rate: Double?) -> DeckTone {
        guard let rate else { return .neutral }
        if rate < 0.8 { return .alert }
        if rate < 0.95 { return .attention }
        return .good
    }

    private static func activity(_ snapshot: ActionsSnapshot, followsPullRequests: Bool) -> String {
        var parts: [String] = []
        if snapshot.runningCount > 0 { parts.append(L("card.actions.running", snapshot.runningCount)) }
        if snapshot.failedCount > 0 { parts.append(L("card.actions.failed", snapshot.failedCount)) }
        // Where the repositories came from, so the card says what it is watching and why: the
        // choice it makes by itself is the one nobody could see until it came up empty.
        if parts.isEmpty {
            parts.append(watching(snapshot.repositories.count, followsPullRequests: followsPullRequests))
        }
        if let average = snapshot.averageDurationSeconds {
            parts.append(L("card.actions.avg", DeckCardTime.duration(average)))
        }
        return parts.joined(separator: " · ")
    }

    /// One row. The success rate is the whole card in a number, and the one action a list card
    /// can offer is opening the same thing on the web.
    private static func collapsed(_ state: CardState<ActionsSnapshot>, followsPullRequests: Bool) -> DeckCollapsedModel {
        let note: String
        let tone: DeckTone
        if let snapshot = state.value {
            if snapshot.repositories.isEmpty {
                note = quietReason(followsPullRequests: followsPullRequests)
            } else if snapshot.failedCount > 0 {
                note = L("card.actions.failing", snapshot.failedCount)
            } else if let rate = snapshot.successRate {
                note = L("card.actions.green", Int((rate * 100).rounded()))
            } else {
                note = L("card.actions.noRuns")
            }
            if snapshot.failedCount > 0 {
                tone = .alert
            } else {
                tone = snapshot.successRate == nil ? .neutral : .good
            }
        } else {
            note = state.failure?.displayMessage ?? L("card.pill.loading")
            tone = .neutral
        }
        return DeckCollapsedModel(
            mark: .github,
            title: L("card.title.actions"),
            note: note,
            tone: tone,
            actions: [DeckActionModel(L("card.action.openInBrowser"), glyph: .openExternal, command: .openDashboard(.githubActions))],
            help: note
        )
    }
}
