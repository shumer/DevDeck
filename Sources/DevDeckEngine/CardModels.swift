import DevDeckCore
import Foundation
import GitHubKit
import ProjectKit

enum CardModels {
    static func time(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func pulls(_ state: CardState<PullRequestsSnapshot>, expanded: Bool) -> JSONValue {
        var model: [String: JSONValue] = [
            "id": "github.pullRequests", "kind": "list", "mark": "github",
            "title": .string(L("card.chrome.pulls")), "timeText": .string(time(state.updatedAt)),
        ]
        guard let snapshot = state.value else {
            model["hero"] = ["number": "", "unit": .string(state.failure?.displayMessage ?? L("card.pill.loading"))]
            model["rows"] = []; model["footer"] = ["text": ""]
            return .object(model)
        }
        let badge: JSONValue
        if let failure = state.failure { badge = ["text": .string(failure.displayMessage), "tone": "bad"] }
        else if snapshot.blockedCount > 0 { badge = ["text": .string(L("card.pill.blocked", snapshot.blockedCount)), "tone": "bad"] }
        else if snapshot.reviewRequestCount > 0 { badge = ["text": .string(L("card.pill.toReview", snapshot.reviewRequestCount)), "tone": "alert"] }
        else { badge = ["text": .string(snapshot.totalCount == 0 ? L("card.pill.clear") : L("card.pill.onTrack")), "tone": "good"] }
        model["hero"] = ["number": .string(String(snapshot.totalCount)), "unit": .string(L("card.open")), "badge": badge]
        let count = CardMetrics.rowCount(total: snapshot.pullRequests.count, isExpanded: expanded)
        model["rows"] = .array(snapshot.prioritized(limit: count).map { pull in
            var chips: [JSONValue] = []
            if let key = pull.ticket.key { chips.append(["text": .string(key), "tone": "quiet"]) }
            var row: [String: JSONValue] = [
                "tone": .string(pull.health == .ready ? "good" : pull.health == .blocked ? "bad" : "alert"),
                "chips": .array(chips), "title": .string(pull.ticket.subject),
                "trailing": .string(pull.statusCode), "action": .string("pull." + pull.id),
            ]
            if pull.isReviewRequest { row["glyph"] = "eye" }
            return .object(row)
        })
        if CardMetrics.showsExpander(total: snapshot.pullRequests.count) {
            let hidden = max(0, snapshot.pullRequests.count - count)
            model["expander"] = ["hiddenCount": .number(Double(hidden)), "isExpanded": .bool(expanded),
                                  "label": .string(expanded ? L("card.showLess") : L("card.showMore", hidden))]
        }
        var footer = snapshot.failures.summary ?? L("card.footer.pair", LN("card.repos", snapshot.repositoryCount), LN("card.orgs", snapshot.organizationCount))
        let beyond = CardMetrics.hiddenWhenExpanded(total: snapshot.pullRequests.count)
        if expanded, beyond > 0 { footer += L("card.notShown", beyond) }
        model["footer"] = ["text": .string(footer)]
        return .object(model)
    }

    static func project(_ project: LocalProject, status: LocalProjectStatus, busy: Bool) -> JSONValue {
        let label: String
        switch status.state {
        case .running: label = L("card.state.running")
        case .starting: label = L("card.state.starting")
        case .working: label = status.detail ?? L("card.state.working")
        case .stopped: label = L("card.state.stopped")
        case .unavailable: label = L("card.state.notConfigured")
        }
        let action = status.isRunning || status.state == .starting ? "stop" : "start"
        var hero: [String: JSONValue] = ["tone": .string(status.isRunning ? "good" : busy ? "accent" : "quiet"), "state": .string(label)]
        if let detail = status.detail { hero["note"] = .string(detail) }
        var model: [String: JSONValue] = [
            "id": .string("project." + project.id), "kind": "project", "mark": "project",
            "title": .string(L("project.section.project") + " · " + project.displayTitle),
            "timeText": .string(time(status.checkedAt)), "hero": .object(hero),
            "meta": [["leading": .string(project.folderURL?.lastPathComponent ?? "")]],
            "chips": [["label": .string(L("card.action.openSite")), "tone": "accent",
                       "isEnabled": .bool(status.isRunning), "action": "site"]],
            "actions": [["id": .string(action), "label": .string(action == "start" ? L("card.action.start") : L("card.action.stop")),
                         "glyph": .string(action == "start" ? "play.fill" : "power"), "role": "primary",
                         "isEnabled": .bool(!busy && project.supportsCommands), "isBusy": .bool(busy)]],
        ]
        if let branch = status.branch { model["branch"] = ["name": .string(branch)] }
        return .object(model)
    }
}
