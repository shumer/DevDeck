import Foundation

/// What a coding agent on this computer may do through the deck.
///
/// Three steps rather than a switch, because reading and acting are different promises. An
/// agent that reads sees what the cards and the menu show. One that may act can also start,
/// stop and restart projects and mark notifications read, under the rules the buttons follow.
/// See docs/adr/0036-agent-access.md.
public enum AgentAccess: String, Sendable, Equatable, Codable, CaseIterable {
    /// No agent sees the deck: the endpoint is closed.
    case off
    /// An agent sees the deck and changes nothing.
    case read
    /// An agent sees the deck and may run the commands a card's buttons run.
    case control
}
