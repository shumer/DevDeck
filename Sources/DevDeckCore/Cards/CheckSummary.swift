import Foundation

/// What a settings form says about a check: a tone for the dot, a word for the state, and the
/// detail after it.
///
/// Kept apart from the view so the rule that matters most can be tested: an answer is only ever
/// shown next to the address it was the answer for. The old live row joined whatever address
/// was in the field to whatever the last check had said, so correcting a wrong port showed the
/// new port beside the old port's refusal.
public struct CheckSummary: Sendable, Equatable {
    public enum Tone: Sendable, Equatable {
        case good, busy, bad, idle
    }

    public let tone: Tone
    public let state: String
    public let detail: String

    public init(tone: Tone, state: String, detail: String) {
        self.tone = tone
        self.state = state
        self.detail = detail
    }

    public static let checking = CheckSummary(tone: .idle, state: "Checking…", detail: "")
    public static let notChecked = CheckSummary(tone: .idle, state: "Not checked yet", detail: "")

    /// "at 23:41:07", in the form's clock.
    public static func time(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
