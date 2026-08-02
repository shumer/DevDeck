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

    public init(
        transport: APITransport,
        tokenStore: any TokenStore,
        settings: GitHubSettings = .default,
        userAgent: String = "DevDeck"
    ) {
        self.transport = transport
        self.tokenStore = tokenStore
        self.settings = settings
        self.userAgent = userAgent
    }

    public static func makeDefault(
        tokenStore: any TokenStore = CompositeTokenStore.standard(),
        settings: GitHubSettings = .default
    ) -> GitHubClient {
        GitHubClient(
            transport: APITransport(client: URLSessionHTTPClient.makeDefault()),
            tokenStore: tokenStore,
            settings: settings
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

    private func resolveToken() throws -> String {
        do {
            guard let token = try tokenStore.token(for: .github), !token.isEmpty else {
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
