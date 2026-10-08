import DevDeckCore
import Foundation
import GitHubKit
import ProjectKit

public struct CardBadge: Codable, Sendable {
    public let text: String
    public let tone: String
}

public enum CardIcon: String, Codable, Sendable {
    case start
    case stop
    case restart
    case folder
    case terminal
    case log
    case phone
    case open
    case review
    case expand
    case collapse
    case branch
}

public struct ListCardHero: Codable, Sendable {
    public let number: String
    public let unit: String
    public let badge: CardBadge?
}

public struct ListCardRow: Codable, Sendable {
    public let tone: String
    public let chips: [CardBadge]
    public let title: String
    public let trailing: String
    public let action: String
    public let glyph: CardIcon?
}

public struct CardFooter: Codable, Sendable {
    public let text: String
}

public struct CardExpander: Codable, Sendable {
    public let hiddenCount: Int
    public let isExpanded: Bool
    public let label: String
}

public struct ListCardModel: Codable, Sendable {
    public let id: String
    public let kind: String
    public let mark: String
    public let title: String
    public let timeText: String
    public let hero: ListCardHero
    public let rows: [ListCardRow]
    public let footer: CardFooter
    public let expander: CardExpander?
}

public struct ProjectCardHero: Codable, Sendable {
    public let tone: String
    public let state: String
    public let note: String?
}

public struct ProjectCardMeta: Codable, Sendable {
    public let leading: String
}

public struct ProjectCardChip: Codable, Sendable {
    public let label: String
    public let tone: String
    public let isEnabled: Bool
    public let action: String
}

public struct ProjectCardAction: Codable, Sendable {
    public let id: String
    public let label: String
    public let glyph: CardIcon
    public let role: String
    public let isEnabled: Bool
    public let isBusy: Bool
}

public struct ProjectCardBranch: Codable, Sendable {
    public let name: String
}

public struct ProjectCardModel: Codable, Sendable {
    public let id: String
    public let kind: String
    public let mark: String
    public let title: String
    public let timeText: String
    public let hero: ProjectCardHero
    public let meta: [ProjectCardMeta]
    public let chips: [ProjectCardChip]
    public let actions: [ProjectCardAction]
    public let branch: ProjectCardBranch?
}

public enum CardModel: Codable, Sendable {
    case list(ListCardModel)
    case project(ProjectCardModel)

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "list":
            self = .list(try ListCardModel(from: decoder))
        case "project":
            self = .project(try ProjectCardModel(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "Unknown card kind.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .list(let model):
            try model.encode(to: encoder)
        case .project(let model):
            try model.encode(to: encoder)
        }
    }
}

enum CardModels {
    static func time(_ date: Date?, timeZone: TimeZone) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func pulls(_ state: CardState<PullRequestsSnapshot>, expanded: Bool, timeZone: TimeZone)
        -> ListCardModel
    {
        guard let snapshot = state.value else {
            return ListCardModel(
                id: "github.pullRequests", kind: "list", mark: "github",
                title: L("card.chrome.pulls"), timeText: time(state.updatedAt, timeZone: timeZone),
                hero: ListCardHero(
                    number: "", unit: state.failure?.displayMessage ?? L("card.pill.loading"), badge: nil),
                rows: [], footer: CardFooter(text: ""), expander: nil
            )
        }
        let badge: CardBadge
        if let failure = state.failure {
            badge = CardBadge(text: failure.displayMessage, tone: "bad")
        } else if snapshot.blockedCount > 0 {
            badge = CardBadge(text: L("card.pill.blocked", snapshot.blockedCount), tone: "bad")
        } else if snapshot.reviewRequestCount > 0 {
            badge = CardBadge(text: L("card.pill.toReview", snapshot.reviewRequestCount), tone: "alert")
        } else {
            badge = CardBadge(
                text: snapshot.totalCount == 0 ? L("card.pill.clear") : L("card.pill.onTrack"), tone: "good")
        }
        let rowCount = CardMetrics.rowCount(total: snapshot.pullRequests.count, isExpanded: expanded)
        let rows = snapshot.prioritized(limit: rowCount).map { pull in
            let chips = pull.ticket.key.map { [CardBadge(text: $0, tone: "quiet")] } ?? []
            return ListCardRow(
                tone: pull.health == .ready ? "good" : pull.health == .blocked ? "bad" : "alert",
                chips: chips, title: pull.ticket.subject, trailing: pull.statusCode,
                action: "pull." + pull.id, glyph: pull.isReviewRequest ? .review : nil
            )
        }
        let expander: CardExpander?
        if CardMetrics.showsExpander(total: snapshot.pullRequests.count) {
            let hiddenCount = max(0, snapshot.pullRequests.count - rowCount)
            expander = CardExpander(
                hiddenCount: hiddenCount, isExpanded: expanded,
                label: expanded ? L("card.showLess") : L("card.showMore", hiddenCount))
        } else {
            expander = nil
        }
        var footer =
            snapshot.failures.summary
            ?? L(
                "card.footer.pair", LN("card.repos", snapshot.repositoryCount),
                LN("card.orgs", snapshot.organizationCount))
        let hiddenWhenExpanded = CardMetrics.hiddenWhenExpanded(total: snapshot.pullRequests.count)
        if expanded, hiddenWhenExpanded > 0 {
            footer += L("card.notShown", hiddenWhenExpanded)
        }
        return ListCardModel(
            id: "github.pullRequests", kind: "list", mark: "github",
            title: L("card.chrome.pulls"), timeText: time(state.updatedAt, timeZone: timeZone),
            hero: ListCardHero(number: String(snapshot.totalCount), unit: L("card.open"), badge: badge),
            rows: rows, footer: CardFooter(text: footer), expander: expander
        )
    }

    static func project(_ project: LocalProject, status: LocalProjectStatus, busy: Bool, timeZone: TimeZone)
        -> ProjectCardModel
    {
        let stateLabel: String
        switch status.state {
        case .running: stateLabel = L("card.state.running")
        case .starting: stateLabel = L("card.state.starting")
        case .working: stateLabel = status.detail ?? L("card.state.working")
        case .stopped: stateLabel = L("card.state.stopped")
        case .unavailable: stateLabel = L("card.state.notConfigured")
        }
        let action = status.isRunning || status.state == .starting ? "stop" : "start"
        return ProjectCardModel(
            id: "project." + project.id, kind: "project", mark: "project",
            title: L("project.section.project") + " · " + project.displayTitle,
            timeText: time(status.checkedAt, timeZone: timeZone),
            hero: ProjectCardHero(
                tone: status.isRunning ? "good" : busy ? "accent" : "quiet", state: stateLabel,
                note: status.detail),
            meta: [ProjectCardMeta(leading: project.folderURL?.lastPathComponent ?? "")],
            chips: [
                ProjectCardChip(
                    label: L("card.action.openSite"), tone: "accent",
                    isEnabled: status.isRunning && project.siteURL != nil, action: "site")
            ],
            actions: [
                ProjectCardAction(
                    id: action, label: action == "start" ? L("card.action.start") : L("card.action.stop"),
                    glyph: action == "start" ? .start : .stop, role: "primary",
                    isEnabled: !busy && project.supportsCommands, isBusy: busy)
            ],
            branch: status.branch.map { ProjectCardBranch(name: $0) }
        )
    }

    static func transportFailure(_ configuration: EngineConfiguration) -> [CardModel] {
        let message = L("engine.unavailable")
        let pulls = ListCardModel(
            id: "github.pullRequests", kind: "list", mark: "github",
            title: L("card.chrome.pulls"), timeText: "",
            hero: ListCardHero(
                number: "", unit: "", badge: CardBadge(text: message, tone: "bad")),
            rows: [], footer: CardFooter(text: ""), expander: nil)
        let projects = configuration.projects.map { project in
            CardModel.project(
                ProjectCardModel(
                    id: "project." + project.id, kind: "project", mark: "project",
                    title: L("project.section.project") + " · " + project.title, timeText: "",
                    hero: ProjectCardHero(tone: "bad", state: message, note: nil),
                    meta: [ProjectCardMeta(leading: project.model.folderURL?.lastPathComponent ?? "")],
                    chips: [], actions: [], branch: nil))
        }
        return [.list(pulls)] + projects
    }
}
