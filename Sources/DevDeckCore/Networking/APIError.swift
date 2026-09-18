import Foundation

/// Every failure the transport can surface, in terms a card can render.
public enum APIError: Error, Sendable, Equatable {
    /// The token is missing, expired or revoked.
    case unauthorized
    /// Authenticated but not allowed - most often SAML SSO authorisation is missing
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
    /// Every account behind a card failed. Carried whole, so the card and the menu can say which
    /// account and why rather than a class of HTTP error.
    case accounts([AccountFailure])

    /// Whether retrying the same request could plausibly succeed.
    public var isRetryable: Bool {
        switch self {
        case .server, .transport: return true
        case .accounts(let failures): return failures.contains { $0.kind == .unreachable }
        case .rateLimited: return false
        case .unauthorized, .forbidden, .notFound, .decoding, .graphQL, .missingToken: return false
        }
    }

    /// Short text for the card's error line.
    public var displayMessage: String {
        switch self {
        case .unauthorized:
            return L("error.unauthorized")
        case .forbidden(let detail):
            return detail ?? L("error.forbidden")
        case .rateLimited(let resetAt):
            guard let resetAt else { return L("error.rateLimited") }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            return L("error.rateLimited.back", formatter.string(from: resetAt))
        case .notFound:
            return L("error.notFound")
        case .server(let status, _):
            return L("error.server", status)
        case .transport:
            return L("error.offline")
        case .decoding:
            return L("error.decoding")
        case .graphQL(let messages):
            return messages.first ?? L("error.graphQL")
        case .missingToken(let name):
            return L("card.noToken", name)
        case .accounts(let failures):
            return failures.summary ?? L("error.everyAccount")
        }
    }
}
