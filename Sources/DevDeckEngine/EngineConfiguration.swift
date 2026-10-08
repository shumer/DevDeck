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
        public let distribution: String?
        public let path: String
        public let startCommand: String
        public let healthURL: String
        public let siteURL: String?

        public enum ExecutionLocation: Sendable, Equatable {
            case windows(path: String)
            case wsl(distribution: String, path: String)
        }

        public var executionLocation: ExecutionLocation? {
            let normalized = path.replacingOccurrences(of: "\\", with: "/")
            if normalized.count >= 3 {
                let letters = Array(normalized)
                if letters[0].isASCII, letters[0].isLetter, letters[1] == ":", letters[2] == "/" {
                    return .windows(path: path)
                }
            }
            for prefix in ["//wsl.localhost/", "//wsl$/"] {
                if normalized.lowercased().hasPrefix(prefix) {
                    let components = normalized.dropFirst(prefix.count).split(
                        separator: "/", omittingEmptySubsequences: true)
                    guard let name = components.first else { return nil }
                    return .wsl(
                        distribution: String(name), path: "/" + components.dropFirst().joined(separator: "/"))
                }
            }
            if path.hasPrefix("/"), !path.hasPrefix("//"), let distribution, !distribution.isEmpty {
                return .wsl(distribution: distribution, path: path)
            }
            return nil
        }

        public var model: LocalProject {
            LocalProject(
                id: id, title: title, folder: resolvedPath, startCommand: startCommand,
                holdsProcess: true, healthURL: healthURL, localSiteURL: siteURL ?? "")
        }

        private var resolvedPath: String {
            if case .wsl(_, let path) = executionLocation { return path }
            return path
        }
    }
    public let language: String
    public let github: GitHub
    public let projects: [Project]

    public var project: Project { projects[0] }

    private enum CodingKeys: String, CodingKey { case language, github, projects, project }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        language = try values.decode(String.self, forKey: .language)
        github = try values.decode(GitHub.self, forKey: .github)
        if let list = try values.decodeIfPresent([Project].self, forKey: .projects) {
            projects = list
        } else {
            projects = [try values.decode(Project.self, forKey: .project)]
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(language, forKey: .language)
        try values.encode(github, forKey: .github)
        try values.encode(projects, forKey: .projects)
    }

    public static func load(from file: URL) throws -> Self {
        let config = try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
        guard ["en", "ru"].contains(config.language), !config.github.account.isEmpty,
            !config.projects.isEmpty, Set(config.projects.map(\.id)).count == config.projects.count
        else {
            throw EngineProtocolError.invalidConfiguration
        }
        for project in config.projects {
            guard project.executionLocation != nil, !project.id.isEmpty,
                project.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                !project.startCommand.isEmpty,
                let url = URL(string: project.healthURL), ["http", "https"].contains(url.scheme ?? "")
            else {
                throw EngineProtocolError.invalidConfiguration
            }
            if let site = project.siteURL {
                guard let url = URL(string: site), ["http", "https"].contains(url.scheme ?? "") else {
                    throw EngineProtocolError.invalidConfiguration
                }
            }
        }
        return config
    }
}
