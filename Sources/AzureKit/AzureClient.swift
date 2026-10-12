import DevDeckCore
import Foundation

/// Authenticated access to one Azure DevOps organization.
///
/// REST rather than anything else, because that is what Azure DevOps has: there is no GraphQL,
/// and the pull request list already carries the reviewers and their votes, which is most of
/// what the card asks. A personal access token goes in as HTTP Basic with an empty user name,
/// which is the one form the service documents for a PAT.
public struct AzureClient: Sendable {
    private let transport: APITransport
    private let tokenStore: any TokenStore
    private let account: AzureAccount
    private let userAgent: String

    /// The REST version every request names. One version for the whole client, so a response
    /// shape that changes is a change made here on purpose.
    public static let apiVersion = "7.1"

    public init(
        transport: APITransport,
        tokenStore: any TokenStore,
        account: AzureAccount,
        userAgent: String = "DevDeck"
    ) {
        self.transport = transport
        self.tokenStore = tokenStore
        self.account = account
        self.userAgent = userAgent
    }

    public static func makeDefault(
        account: AzureAccount,
        tokenStore: any TokenStore = CompositeTokenStore.standard()
    ) -> AzureClient {
        AzureClient(
            transport: APITransport(client: URLSessionHTTPClient.makeDefault()),
            tokenStore: tokenStore,
            account: account
        )
    }

    /// Runs a GET under the organization and decodes the payload.
    ///
    /// `path` is relative to `https://dev.azure.com/{organization}`. The API version is added
    /// unless the caller passes its own, because a handful of endpoints only exist as previews.
    public func get<Payload: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem] = [],
        apiVersion: String? = AzureClient.apiVersion,
        as payloadType: Payload.Type = Payload.self
    ) async throws -> Payload {
        let token = try resolveToken()
        var components = URLComponents(
            url: account.organizationURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        var items = query
        if let apiVersion { items.append(URLQueryItem(name: "api-version", value: apiVersion)) }
        // Nil rather than empty, or the URL ends in a bare question mark.
        components?.queryItems = items.isEmpty ? nil : items
        guard let url = components?.url else {
            throw APIError.decoding("Could not build a URL for \(path)")
        }

        let request = HTTPRequest(
            method: .get,
            url: url,
            headers: [
                "Authorization": "Basic \(Self.basicCredential(token: token))",
                "Accept": "application/json",
                "User-Agent": userAgent,
            ],
            // A GET with the same query every refresh: an ETag in hand turns a repeat into a 304.
            cacheKey: url.absoluteString
        )

        let response = try await transport.perform(request)
        do {
            return try Self.decoder.decode(Payload.self, from: response.body)
        } catch {
            // A token the service does not accept is not refused with a 401: the answer is a
            // sign-in page with a success status. HTML where JSON was expected is that page.
            if Self.looksLikeSignInPage(response.body) { throw APIError.unauthorized }
            throw APIError.decoding(String(describing: error))
        }
    }

    /// `:{token}`, base64: a PAT is the password of a Basic credential with no user name.
    static func basicCredential(token: String) -> String {
        Data(":\(token)".utf8).base64EncodedString()
    }

    static func looksLikeSignInPage(_ body: Data) -> Bool {
        let head = String(decoding: body.prefix(256), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return head.hasPrefix("<!doctype html") || head.hasPrefix("<html")
    }

    private func resolveToken() throws -> String {
        do {
            guard let token = try tokenStore.token(for: account.tokenKey), !token.isEmpty else {
                throw APIError.missingToken("Azure DevOps")
            }
            return token
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.missingToken("Azure DevOps")
        }
    }

    /// Azure DevOps writes timestamps with seven fractional digits, which no ISO 8601 formatter
    /// on the platform accepts as they are. The fraction is cut to three before parsing, and a
    /// timestamp without one is taken as it is.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw APIError.decoding("Not a date Azure DevOps was expected to send: \(text)")
        }
        return decoder
    }()

    /// Made per call rather than shared: `ISO8601DateFormatter` is not `Sendable`, and a
    /// formatter is cheap next to the request that just came back over the network.
    public static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: trimmedFraction(text))
    }

    /// `12:34:56.1234567Z` to `12:34:56.123Z`.
    static func trimmedFraction(_ text: String) -> String {
        guard let dot = text.lastIndex(of: "."), let end = text[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) else {
            return text
        }
        let digits = text[text.index(after: dot)..<end]
        guard digits.count > 3 else { return text }
        return String(text[..<dot]) + "." + String(digits.prefix(3)) + String(text[end...])
    }
}
