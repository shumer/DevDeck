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

public enum JSONValue: Codable, Sendable, Equatable, ExpressibleByStringLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
