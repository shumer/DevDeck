import DevDeckCore
import Foundation

/// Authenticated access to one GitHub instance.
///
/// GraphQL is the default on purpose: a pull request card needs the review decision, the
/// check rollup and the unresolved thread count, which is three REST round trips per PR
/// against a 5000/hour budget, or one query here.
public struct GitHubClient: Sendable {
    private let transport: APITransport
    private let tokenStore: any TokenStore
    private let settings: GitHubSettings
    private let userAgent: String
    /// Which stored token this client authenticates with. One per configured account.
    private let tokenKey: TokenKey

    public init(
        transport: APITransport,
        tokenStore: any TokenStore,
        settings: GitHubSettings = .default,
        userAgent: String = "DevDeck",
        tokenKey: TokenKey = .github
    ) {
        self.transport = transport
        self.tokenStore = tokenStore
        self.settings = settings
        self.userAgent = userAgent
        self.tokenKey = tokenKey
    }

    public static func makeDefault(
        tokenStore: any TokenStore = CompositeTokenStore.standard(),
        settings: GitHubSettings = .default,
        tokenKey: TokenKey = .github
    ) -> GitHubClient {
        GitHubClient(
            transport: APITransport(client: URLSessionHTTPClient.makeDefault()),
            tokenStore: tokenStore,
            settings: settings,
            tokenKey: tokenKey
        )
    }

    /// Runs a GraphQL document and decodes the `data` payload.
    ///
    /// GraphQL answers 200 even when the query failed, so an `errors` array is mapped to a
    /// thrown `APIError.graphQL` rather than a half-empty payload reaching the UI.
    public func graphQL<Variables: Encodable & Sendable, Payload: Decodable & Sendable>(
        query: String,
        variables: Variables,
        as payloadType: Payload.Type = Payload.self
    ) async throws -> Payload {
        let token = try resolveToken()
        let body = try JSONEncoder().encode(GraphQLRequestBody(query: query, variables: variables))

        let request = HTTPRequest(
            method: .post,
            url: settings.apiBaseURL.appendingPathComponent("graphql"),
            headers: [
                "Authorization": "bearer \(token)",
                "Accept": "application/vnd.github+json",
                "Content-Type": "application/json",
                "User-Agent": userAgent,
            ],
            body: body
        )

        let response = try await transport.perform(request)

        let envelope: GraphQLEnvelope<Payload>
        do {
            envelope = try Self.decoder.decode(GraphQLEnvelope<Payload>.self, from: response.body)
        } catch {
            throw APIError.decoding(String(describing: error))
        }

        if let errors = envelope.errors, !errors.isEmpty {
            throw APIError.graphQL(errors.map(\.message))
        }
        guard let payload = envelope.data else {
            throw APIError.decoding("GraphQL response carried neither data nor errors")
        }
        return payload
    }

    /// A REST GET, decoded, with conditional-request support.
    ///
    /// `cacheKey` is what makes polling affordable: with an `ETag` in hand the server answers
    /// 304, which costs nothing against the hourly budget.
    public func get<Payload: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem] = [],
        cacheKey: String? = nil,
        as payloadType: Payload.Type = Payload.self
    ) async throws -> RESTResult<Payload> {
        var components = URLComponents(
            url: settings.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else {
            throw APIError.decoding("Could not build a URL for \(path)")
        }

        let request = HTTPRequest(
            method: .get,
            url: url,
            headers: [
                "Authorization": "bearer \(try resolveToken())",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": userAgent,
            ],
            cacheKey: cacheKey
        )

        let response = try await transport.perform(request)
        do {
            let value = try Self.decoder.decode(Payload.self, from: response.body)
            return RESTResult(
                value: value,
                wasNotModified: response.wasNotModified,
                pollIntervalSeconds: response.pollIntervalSeconds
            )
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// A REST call that changes something and answers with nothing worth decoding.
    ///
    /// Marking a notification read is the first of these: the endpoint answers 205, and a 404
    /// means the thread is already gone, which is the same outcome from where the card sits.
    public func send(method: HTTPMethod, path: String) async throws {
        let request = HTTPRequest(
            method: method,
            url: settings.apiBaseURL.appendingPathComponent(path),
            headers: [
                "Authorization": "bearer \(try resolveToken())",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": userAgent,
            ]
        )
        _ = try await transport.perform(request)
    }

    private func resolveToken() throws -> String {
        do {
            guard let token = try tokenStore.token(for: tokenKey), !token.isEmpty else {
                throw APIError.missingToken("GitHub")
            }
            return token
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.missingToken("GitHub")
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
