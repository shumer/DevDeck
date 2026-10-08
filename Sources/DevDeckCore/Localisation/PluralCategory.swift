import Foundation

/// The plural category a count falls into, for the languages DevDeck ships.
///
/// Apple's Foundation reads this from the stringsdict by itself. Foundation on Windows cannot
/// expand the stringsdict format marker, so the Windows build picks the form itself, and this is
/// the rule it picks by. It lives outside the Windows branch so the Mac suite checks it too: a
/// rule only one platform can test is a rule that drifts.
///
/// Whole numbers only, which is all the deck ever counts. The categories are the CLDR ones the
/// tables use: Russian needs three, French counts zero as singular, the rest need two.
public enum PluralCategory: String, Sendable, Equatable {
    case one
    case few
    case many
    case other

    public static func of(_ count: Int, language: String) -> PluralCategory {
        let number = count.magnitude
        switch language {
        case "ru":
            let lastDigit = number % 10
            let lastTwoDigits = number % 100
            if lastDigit == 1, lastTwoDigits != 11 {
                return .one
            }
            if (2...4).contains(lastDigit), !(12...14).contains(lastTwoDigits) {
                return .few
            }
            return .many
        case "fr":
            return number <= 1 ? .one : .other
        default:
            return number == 1 ? .one : .other
        }
    }
}
