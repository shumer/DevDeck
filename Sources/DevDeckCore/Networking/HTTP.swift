import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

public struct HTTPRequest: Sendable, Equatable {
    public var method: HTTPMethod
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    /// Identity used for conditional requests. Nil means "never send If-None-Match for this
    /// call" — correct for POST bodies such as GraphQL, where an ETag would be meaningless.
    public var cacheKey: String?

    public init(
        method: HTTPMethod = .get,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        cacheKey: String? = nil
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.cacheKey = cacheKey
    }

    public mutating func setHeader(_ value: String?, for name: String) {
        headers[name] = value
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    /// HTTP header names are case-insensitive and servers do not agree on casing;
    /// URLSession preserves whatever the server sent, so every lookup must fold case.
    public func header(_ name: String) -> String? {
        let wanted = name.lowercased()
        for (key, value) in headers where key.lowercased() == wanted {
            return value
        }
        return nil
    }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }
}
