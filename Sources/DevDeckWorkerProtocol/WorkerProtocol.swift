import Foundation
import ArcKit
import DevDeckCore
import ProjectKit

/// Newline-delimited JSON. Stdout belongs exclusively to this protocol.
public enum WorkerProtocol {
    public static let version = 1
    public static let maximumFrameBytes = 1_048_576
    public static let maximumActiveProjectIDs = 1024
    public static let capabilities = ["hello", "ddev.list", "project.probe", "project.check", "project.status", "project.logs", "project.preflight", "project.start", "project.stop", "project.restart", "cancel", "remote.snapshot", "remote.verify", "remote.markRead", "remote.markRest", "remote.markAll", "attention.shared", "attention.dismiss", "attention.activeProjects", "ddev.poweroff.transaction", "checkouts.snapshot", "attention.inboxReadTarget"]
}

public struct WorkerProject: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case ddev, arc, local }
    public let id: String
    public let distribution: String
    public let kind: Kind
    public let path: String
    public let startCommand: String?
    public let stopCommand: String?
    public let holdsProcess: Bool?
    public let requiresDocker: Bool?
    public let healthURL: String?
    public let title: String?
    public let arc: WorkerArcConfiguration?
    public let subtitle: String?
    public let openURL: String?

    public init(id: String, distribution: String, kind: Kind, path: String, startCommand: String? = nil,
                stopCommand: String? = nil, holdsProcess: Bool? = nil, requiresDocker: Bool? = nil, healthURL: String? = nil, title: String? = nil, arc: WorkerArcConfiguration? = nil, subtitle: String? = nil, openURL: String? = nil) {
        self.id = id; self.distribution = distribution; self.kind = kind; self.path = path
        self.startCommand = startCommand; self.stopCommand = stopCommand; self.holdsProcess = holdsProcess
        self.requiresDocker = requiresDocker; self.healthURL = healthURL
        self.title = title
        self.arc = arc
        self.subtitle = subtitle; self.openURL = openURL
    }

    public func localModel(runtimeID: String? = nil) -> LocalProject {
        LocalProject(id: runtimeID ?? id, title: title ?? id, subtitle: subtitle ?? "", folder: path,
                     startCommand: startCommand ?? "", stopCommand: stopCommand ?? "",
                     holdsProcess: holdsProcess ?? true, requiresDocker: requiresDocker ?? false,
                     healthURL: healthURL ?? "", localSiteURL: openURL ?? "")
    }

    public var arcModel: ArcProject {
        ArcProject(id: id, title: title ?? id, organization: arc?.organization ?? "", site: arc?.site,
                   folder: path.isEmpty ? nil : path, startCommand: startCommand ?? "npx --no-install fusion daemon",
                   stopCommand: stopCommand ?? "npx --no-install fusion stop", localURL: arc?.localURL ?? "",
                   healthPath: arc?.healthPath ?? "/release")
    }
}

public struct WorkerArcConfiguration: Codable, Sendable, Equatable {
    public let organization: String
    public let site: String?
    public let localURL: String
    public let healthPath: String
    public init(organization: String = "", site: String? = nil, localURL: String = "", healthPath: String = "/release") {
        self.organization = organization; self.site = site; self.localURL = localURL; self.healthPath = healthPath
    }
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        organization = try fields.decodeIfPresent(String.self, forKey: .organization) ?? ""
        site = try fields.decodeIfPresent(String.self, forKey: .site)
        localURL = try fields.decodeIfPresent(String.self, forKey: .localURL) ?? ""
        healthPath = try fields.decodeIfPresent(String.self, forKey: .healthPath) ?? "/release"
    }
}

public struct WorkerRequest: Codable, Sendable {
    public let protocolVersion: Int
    public let id: String
    public let operation: String
    public let project: WorkerProject?
    public let targetRequestID: String?
    public let remote: WorkerRemoteRequest?
    public let refreshCycle: String?
    /// Attention presentation only. Nil preserves legacy sessions; an empty list shows no local events.
    public let activeProjectIDs: [String]?
    public let powerOff: WorkerDDEVPowerOffContext?
    public let checkout: WorkerCheckoutRequest?

    public init(protocolVersion: Int = WorkerProtocol.version, id: String, operation: String, project: WorkerProject? = nil, targetRequestID: String? = nil, remote: WorkerRemoteRequest? = nil, refreshCycle: String? = nil, activeProjectIDs: [String]? = nil, powerOff: WorkerDDEVPowerOffContext? = nil, checkout: WorkerCheckoutRequest? = nil) {
        self.protocolVersion = protocolVersion; self.id = id; self.operation = operation; self.project = project
        self.targetRequestID = targetRequestID
        self.remote = remote
        self.refreshCycle = refreshCycle
        self.activeProjectIDs = activeProjectIDs
        self.powerOff = powerOff
        self.checkout = checkout
    }
}

public struct WorkerFailure: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public init(code: String, message: String) { self.code = code; self.message = message }
}

/// The original settings answer, independent of the card's polling-settled state.
public struct WorkerCheckSummary: Codable, Sendable, Equatable {
    public let tone: String
    public let state: String
    public let detail: String

    public init(_ summary: CheckSummary) {
        switch summary.tone {
        case .good: tone = "good"
        case .busy: tone = "busy"
        case .bad: tone = "bad"
        case .idle: tone = "idle"
        }
        state = Self.bounded(summary.state, bytes: 512, multiline: false)
        detail = Self.bounded(summary.detail, bytes: 16_384, multiline: true)
    }

    private static func bounded(_ value: String, bytes limit: Int, multiline: Bool) -> String {
        var result = String.UnicodeScalarView()
        var bytes = 0
        for scalar in value.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar), !(multiline && ["\n", "\t"].contains(String(scalar))) { continue }
            let length = scalar.utf8.count
            guard bytes + length <= limit else { break }
            result.append(scalar)
            bytes += length
        }
        return String(result)
    }
}

public struct WorkerStatus: Codable, Sendable {
    public let projectID: String
    public let state: String
    public let branch: String?
    public let siteURL: String?
    public let framework: String?
    public let engineVersion: String?
    public let versionsLine: String?
    public let localEditorURL: String?
    public let notAnswering: String?
    public let syncBroken: String?
    public let repositoryURL: String?
    public let toolLinks: [WorkerLink]?
    public var checkSummary: WorkerCheckSummary?
    public var checkedAt: Double?

    public init(projectID: String, state: String, branch: String? = nil, siteURL: String? = nil,
                framework: String? = nil, engineVersion: String? = nil, notAnswering: String? = nil, syncBroken: String? = nil,
                repositoryURL: String? = nil, toolLinks: [WorkerLink]? = nil, versionsLine: String? = nil, localEditorURL: String? = nil,
                checkSummary: WorkerCheckSummary? = nil, checkedAt: Double? = nil) {
        self.projectID = projectID; self.state = state; self.branch = branch; self.siteURL = siteURL
        self.framework = framework; self.engineVersion = engineVersion
        self.notAnswering = notAnswering
        self.syncBroken = syncBroken
        self.repositoryURL = repositoryURL; self.toolLinks = toolLinks
        self.versionsLine = versionsLine
        self.localEditorURL = localEditorURL
        self.checkSummary = checkSummary
        self.checkedAt = checkedAt.flatMap { $0.isFinite && (0...253_402_300_799).contains($0) ? $0 : nil }
    }
}
public struct WorkerLink: Codable, Sendable {
    public let label: String
    public let url: String
    public init(label: String, url: String) { self.label = label; self.url = url }
}

public struct WorkerDiscoveredProject: Codable, Sendable {
    public let name: String
    public let distribution: String
    public let path: String
    public let state: String
    public init(name: String, distribution: String, path: String, state: String) {
        self.name = name; self.distribution = distribution; self.path = path; self.state = state
    }
}

public struct WorkerLogs: Codable, Sendable {
    public let lines: [String]
    public let source: String?
    public let detail: String?
    public let filePath: String?
    public init(lines: [String], source: String?, detail: String?, filePath: String? = nil) {
        var bytes = 0
        self.lines = Array(lines.suffix(LogWindowLimit.lines).reversed().prefix { line in
            bytes += line.utf8.count
            return bytes <= LogWindowLimit.bytes
        }.reversed())
        self.source = source; self.detail = detail; self.filePath = filePath
    }
}
public enum LogWindowLimit {
    public static let lines = 400
    public static let bytes = 262_144
}
public struct WorkerEvent: Codable, Sendable {
    public let kind: String
    public let line: String
    public init(line: String) { kind = "progress"; self.line = line }
}

public struct WorkerResponse: Codable, Sendable {
    public let protocolVersion: Int
    public let id: String?
    public let distribution: String
    public let capabilities: [String]?
    public let status: WorkerStatus?
    public let projects: [WorkerDiscoveredProject]?
    public let error: WorkerFailure?
    public let logs: WorkerLogs?
    public let event: WorkerEvent?
    public let remote: WorkerRemoteSnapshot?
    public let attention: WorkerAttentionSnapshot?
    public let powerOff: WorkerDDEVPowerOffResult?
    public let suggestion: WorkerProjectSuggestion?
    public let checkout: WorkerCheckoutResult?
    public init(id: String?, distribution: String, capabilities: [String]? = nil,
                status: WorkerStatus? = nil, projects: [WorkerDiscoveredProject]? = nil, error: WorkerFailure? = nil, logs: WorkerLogs? = nil, event: WorkerEvent? = nil, remote: WorkerRemoteSnapshot? = nil, attention: WorkerAttentionSnapshot? = nil, suggestion: WorkerProjectSuggestion? = nil, powerOff: WorkerDDEVPowerOffResult? = nil, checkout: WorkerCheckoutResult? = nil) {
        protocolVersion = WorkerProtocol.version
        self.id = id; self.distribution = distribution; self.capabilities = capabilities
        self.status = status; self.projects = projects; self.error = error
        self.logs = logs
        self.event = event
        self.remote = remote
        self.attention = attention
        self.powerOff = powerOff
        self.suggestion = suggestion
        self.checkout = checkout
    }
}

public struct WorkerProjectSuggestion: Codable, Sendable, Equatable {
    public let subtitle: String
    public let startCommand: String
    public let stopCommand: String
    public let holdsProcess: Bool
    public let requiresDocker: Bool
    public let healthURL: String
    public init(_ suggestion: ProjectSuggestion) {
        subtitle = suggestion.subtitle; startCommand = suggestion.startCommand; stopCommand = suggestion.stopCommand
        holdsProcess = suggestion.holdsProcess; requiresDocker = suggestion.requiresDocker; healthURL = suggestion.healthURL
    }
}

/// A large or malformed frame cannot grow memory without bound or swallow the next request.
public struct WorkerFramer: Sendable {
    public enum Frame: Sendable, Equatable { case data(Data), oversized }
    private var buffer = Data()
    private var discarding = false
    private let limit: Int
    public init(limit: Int = WorkerProtocol.maximumFrameBytes) { self.limit = max(1, limit) }
    public mutating func feed(_ chunk: Data) -> [Frame] {
        var frames: [Frame] = []
        for byte in chunk {
            if byte == 10 {
                if discarding { frames.append(.oversized) }
                else if !buffer.isEmpty { frames.append(.data(buffer)) }
                buffer.removeAll(keepingCapacity: true); discarding = false
            } else if !discarding {
                if buffer.count >= limit { buffer.removeAll(keepingCapacity: true); discarding = true }
                else { buffer.append(byte) }
            }
        }
        return frames
    }
    public mutating func finish() -> [Frame] {
        defer { buffer.removeAll(); discarding = false }
        if discarding { return [.oversized] }
        return buffer.isEmpty ? [] : [.data(buffer)]
    }
}
