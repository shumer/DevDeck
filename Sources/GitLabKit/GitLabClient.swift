import DevDeckCore
import Foundation

/// Authenticated access to one GitLab instance.
///
/// GraphQL rather than REST v4, for the same reason the GitHub client uses it: the card needs
/// the pipeline verdict, the approval state and the unresolved discussion count per merge
/// request, and REST answers those from three different places. GitLab's `currentUser` also
/// carries both halves of the question - what you wrote and what you have been asked to review -
/// so the whole card is one request rather than two searches and a fan-out.
public struct GitLabClient: Sendable {
    private let transport: APITransport
    private let tokenStore: any TokenStore
    private let account: GitLabAccount
    private let userAgent: String

    public init(
        transport: APITransport,
        tokenStore: any TokenStore,
        account: GitLabAccount,
        userAgent: String = "DevDeck"
    ) {
        self.transport = transport
        self.tokenStore = tokenStore
        self.account = account
        self.userAgent = userAgent
    }

    public static func makeDefault(
        account: GitLabAccount,
        tokenStore: any TokenStore = CompositeTokenStore.standard()
    ) -> GitLabClient {
        GitLabClient(
            transport: APITransport(client: URLSessionHTTPClient.makeDefault()),
            tokenStore: tokenStore,
            account: account
        )
    }

    /// Runs a GraphQL document and decodes the `data` payload.
    ///
    /// GraphQL answers 200 even when the query failed, so an `errors` array becomes a thrown
    /// `APIError.graphQL` rather than a half-empty payload reaching the card.
    public func graphQL<Variables: Encodable & Sendable, Payload: Decodable & Sendable>(
        query: String,
        variables: Variables,
        as payloadType: Payload.Type = Payload.self
    ) async throws -> Payload {
        let token = try resolveToken()
        let body = try JSONEncoder().encode(GitLabRequestBody(query: query, variables: variables))

        let request = HTTPRequest(
            method: .post,
            url: account.graphQLURL,
            headers: [
                // A personal access token goes in as a bearer token here, the same as an OAuth
                // one. GitLab also accepts `Private-Token`, but only for PATs, and one header
                // that works for both is one thing fewer to get wrong.
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json",
                "User-Agent": userAgent,
            ],
            body: body
        )

        let response = try await transport.perform(request)

        let envelope: GitLabEnvelope<Payload>
        do {
            envelope = try Self.decoder.decode(GitLabEnvelope<Payload>.self, from: response.body)
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
            guard let token = try tokenStore.token(for: account.tokenKey), !token.isEmpty else {
                throw APIError.missingToken("GitLab")
            }
            return token
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.missingToken("GitLab")
        }
    }

    /// GitLab timestamps are ISO 8601 with fractional seconds, which the plain `.iso8601`
    /// strategy refuses. Both shapes appear across versions, so both are accepted.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw APIError.decoding("Not a date GitLab was expected to send: \(text)")
        }
        return decoder
    }()

    /// Made per call rather than shared: `ISO8601DateFormatter` is not `Sendable`, and a
    /// formatter is cheap next to the request that just came back over the network.
    static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

struct GitLabRequestBody<Variables: Encodable & Sendable>: Encodable, Sendable {
    let query: String
    let variables: Variables
}

struct GitLabEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let data: Payload?
    let errors: [GitLabErrorEntry]?
}

struct GitLabErrorEntry: Decodable, Sendable {
    let message: String
}
