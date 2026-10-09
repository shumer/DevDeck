import Foundation

/// A mark-as-read in flight. Without this the card said nothing for the minute a few hundred
/// threads take, and a second press started the same work again.
public enum InboxProgress: Equatable, Sendable {
    /// Paging through the box for what has to be marked.
    case gathering
    /// So many of so many.
    case marking(done: Int, total: Int)
    /// One request for the whole box, nothing to count.
    case markingAll
    /// Over: how many were marked, or nil when GitHub was asked for everything at once.
    case finished(Int?)
    /// GitHub refused, with its reason.
    case failed(String)

    public var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    public var isRunning: Bool {
        switch self {
        case .gathering, .marking, .markingAll: return true
        case .finished, .failed: return false
        }
    }
}
