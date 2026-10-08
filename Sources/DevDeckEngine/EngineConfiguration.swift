import Foundation
import ProjectKit

public struct EngineConfiguration: Codable, Sendable {
    public struct GitHub: Codable, Sendable {
        public let account: String
        public let label: String
    }
    public struct Project: Codable, Sendable {
        public let id: String
        public let title: String
        public let distribution: String
        public let path: String
        public let startCommand: String
        public let healthURL: String

        public var model: LocalProject {
            LocalProject(id: id, title: title, folder: path, startCommand: startCommand,
                         holdsProcess: true, healthURL: healthURL)
        }
    }
    public let language: String
    public let github: GitHub
    public let project: Project

    public static func load(from file: URL) throws -> Self {
        let config = try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
        guard ["en", "ru"].contains(config.language), !config.github.account.isEmpty,
              !config.project.distribution.isEmpty, config.project.path.hasPrefix("/"),
              !config.project.id.isEmpty, config.project.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              !config.project.startCommand.isEmpty,
              let url = URL(string: config.project.healthURL), ["http", "https"].contains(url.scheme ?? "") else {
            throw EngineProtocolError.invalidConfiguration
        }
        return config
    }
}
