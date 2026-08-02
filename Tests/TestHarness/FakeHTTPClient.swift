import DevDeckCore
import Foundation

/// Replays scripted responses and records what was asked of it.
///
/// Two modes, because two shapes of test need them: a queue for a single endpoint called
/// repeatedly, and routes for code that fans out over several URLs concurrently — there the
/// arrival order is not deterministic and a queue would make the test flaky.
public actor FakeHTTPClient: HTTPClient {
    private var pending: [Result<HTTPResponse, Error>]
    private let routes: [(match: String, result: Result<HTTPResponse, Error>)]
    public private(set) var requests: [HTTPRequest] = []

    public init(_ responses: [Result<HTTPResponse, Error>]) {
        self.pending = responses
        self.routes = []
    }

    public init(routes: [(String, Result<HTTPResponse, Error>)]) {
        self.pending = []
        self.routes = routes.map { (match: $0.0, result: $0.1) }
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)

        if !routes.isEmpty {
            let url = request.url.absoluteString
            guard let route = routes.first(where: { url.contains($0.match) }) else {
                throw APIError.notFound
            }
            switch route.result {
            case .success(let response): return response
            case .failure(let error): throw error
            }
        }

        guard !pending.isEmpty else {
            throw APIError.transport("FakeHTTPClient ran out of scripted responses")
        }
        switch pending.removeFirst() {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    public var requestCount: Int { requests.count }

    public func request(at index: Int) -> HTTPRequest? {
        index < requests.count ? requests[index] : nil
    }

    /// The first recorded request whose URL contains `fragment`.
    public func request(matching fragment: String) -> HTTPRequest? {
        requests.first { $0.url.absoluteString.contains(fragment) }
    }
}

public extension HTTPResponse {
    static func json(
        _ body: String,
        status: Int = 200,
        headers: [String: String] = [:]
    ) -> HTTPResponse {
        HTTPResponse(
            statusCode: status,
            headers: headers.merging(["Content-Type": "application/json"]) { current, _ in current },
            body: Data(body.utf8)
        )
    }

    static func status(_ status: Int, headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: headers, body: Data())
    }
}
