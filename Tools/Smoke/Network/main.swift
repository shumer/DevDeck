import DevDeckCore
import Foundation
import GitHubKit

actor ObservedHTTP: HTTPClient {
    private let base = URLSessionHTTPClient.makeDefault()
    private var lastResponse: HTTPResponse?
    private var lastConditional = false
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = try await base.send(request)
        lastResponse = response
        lastConditional = request.headers["If-None-Match"] != nil
        return response
    }
    func summary() -> (Int?, Bool, Int?) {
        (lastResponse?.statusCode, lastConditional, lastResponse.flatMap { RateLimit.parse($0)?.remaining })
    }
}
struct User: Decodable, Sendable { let id: Int }

do {
    // The caller supplies a credential only through redirected stdin.
    guard let line = readLine(), line.utf8.count <= 1_048_576, !line.isEmpty else { exit(1) }
    let token = try JSONDecoder().decode(String.self, from: Data(line.utf8))
    let tokens = InMemoryTokenStore()
    try tokens.setToken(token, for: .github)
    let observed = ObservedHTTP()
    let client = GitHubClient(transport: APITransport(client: observed), tokenStore: tokens)
    let snapshot = try await PullRequestsService(client: client).fetch()
    print("Authenticated PR fetch succeeded: \(snapshot.totalCount) open.")
    let _: RESTResult<User> = try await client.get(path: "user", cacheKey: "github:smoke:user")
    let second: RESTResult<User> = try await client.get(path: "user", cacheKey: "github:smoke:user")
    let summary = await observed.summary()
    guard second.wasNotModified, summary.0 == 304, summary.1 else { exit(1) }
    print("REST conditional request: ETag sent, HTTP 304 received.")
    print("REST rate-limit remaining: \(summary.2.map(String.init) ?? "unavailable").")
    try tokens.setToken("fixture", for: .github)
    do {
        _ = try await PullRequestsService(client: client).fetch()
        exit(1)
    } catch APIError.unauthorized {
        print("Invalid credential returned an unauthorized error.")
    }
    try tokens.setToken(nil, for: .github)
} catch {
    FileHandle.standardError.write(Data("Network smoke check failed. No credentials were logged.\n".utf8))
    exit(1)
}
