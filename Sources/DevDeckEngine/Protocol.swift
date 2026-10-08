import Foundation

public enum EngineProtocolError: Error { case invalidConfiguration, invalidIntent, oversizedMessage }

public struct EngineIntent: Decodable, Sendable {
    public struct Display: Decodable, Sendable {
        public let id: String
        public let visibleFrame: [Double]
        public let scale: Double
    }
    public let protocolVersion: Int
    public let id: String
    public let intent: String
    public let language: String?
    public let displays: [Display]?
    public let account: String?
    public let token: String?
    public let card: String?
    public let size: [Double]?
    public let action: String?
    public let isExpanded: Bool?

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576 else { throw EngineProtocolError.oversizedMessage }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.protocolVersion == 2, !value.id.isEmpty else { throw EngineProtocolError.invalidIntent }
        return value
    }
}

public struct CardPlacement: Codable, Sendable {
    public let card: String
    public let display: String
    public let topLeft: [Double]
}

public struct OpenURLEffect: Codable, Sendable {
    public let kind: String
    public let url: String
    public let browser: String
}

public struct ShellPresentation: Codable, Sendable {
    public let toolTip: String
    public let quitLabel: String
    public let credentialAccounts: [String]
    public let failureCards: [CardModel]
}

public struct EngineEvent: Codable, Sendable {
    public let protocolVersion: Int
    public let revision: Int
    public let event: String
    public let id: String?
    public let card: CardModel?
    public let cards: [CardPlacement]?
    public let effect: OpenURLEffect?
    public let shell: ShellPresentation?
    public let reason: String?
}
