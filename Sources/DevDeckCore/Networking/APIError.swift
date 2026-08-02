import Foundation

/// Every failure the transport can surface, in terms a card can render.
public enum APIError: Error, Sendable, Equatable {
    /// The token is missing, expired or revoked.
    case unauthorized
    /// Authenticated but not allowed — most often SAML SSO authorisation is missing
    /// for the organisation, which GitHub reports as 403 rather than 401.
    case forbidden(String?)
    case rateLimited(resetAt: Date?)
    case notFound
    case server(status: Int, message: String?)
    case transport(String)
    case decoding(String)
    /// GraphQL answers 200 with an `errors` array; those are surfaced separately.
    case graphQL([String])
    case missingToken(String)

    /// Whether retrying the same request could plausibly succeed.
    public var isRetryable: Bool {
        switch self {
        case .server, .transport: return true
        case .rateLimited: return false
        case .unauthorized, .forbidden, .notFound, .decoding, .graphQL, .missingToken: return false
        }
    }

    /// Short text for the card's error line.
    public var displayMessage: String {
        switch self {
        case .unauthorized:
            return "Token rejected"
        case .forbidden(let detail):
            return detail.map { "Forbidden — \($0)" } ?? "Forbidden"
        case .rateLimited(let resetAt):
            guard let resetAt else { return "Rate limited" }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            return "Rate limited until \(formatter.string(from: resetAt))"
        case .notFound:
            return "Not found"
        case .server(let status, _):
            return "GitHub error \(status)"
        case .transport:
            return "Network unavailable"
        case .decoding:
            return "Unexpected response"
        case .graphQL(let messages):
            return messages.first ?? "GraphQL error"
        case .missingToken(let name):
            return "No \(name) token"
        }
    }
}
