import DevDeckCore
import Foundation

/// Replays a scripted list of responses and records what was asked of it.
public actor FakeHTTPClient: HTTPClient {
    private var pending: [Result<HTTPResponse, Error>]
    public private(set) var requests: [HTTPRequest] = []

    public init(_ responses: [Result<HTTPResponse, Error>]) {
        self.pending = responses
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
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
