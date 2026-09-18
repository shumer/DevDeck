import Foundation

/// The languages the interface is written in, and the one that says "whatever the Mac is set to".
///
/// Their names are in their own language, the way every list of languages on a Mac is: somebody
/// looking for Deutsch is not looking for German.
public enum AppLanguage: String, Sendable, Equatable, CaseIterable {
    case system
    case english = "en"
    case russian = "ru"
    case italian = "it"
    case german = "de"
    case spanish = "es"
    case french = "fr"

    /// What the picker shows. The system entry is the only one that has to be translated, since
    /// it is the only one that is not the name of a language.
    public var title: String {
        switch self {
        case .system: return L("settings.language.system")
        case .english: return "English"
        case .russian: return "Русский"
        case .italian: return "Italiano"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .french: return "Français"
        }
    }

    /// The languages that ship, in the order the picker lists them: the system first, then the
    /// rest as they are named.
    public static let choices: [AppLanguage] = [.system, .english, .german, .spanish, .french, .italian, .russian]
}

/// Where every word the interface says comes from.
///
/// The app is built without Xcode, so there is no asset catalog and no automatic string
/// extraction: the tables are `Resources/Localizations/<code>.lproj/Localizable.strings`, copied
/// into the bundle by `build.sh`, and this is the one place that reads them. Picking a language in
/// Settings swaps the table underneath, which is why nothing here caches a translated string.
///
/// The fall-back chain is the chosen language, then English, then the key itself. A key on screen
/// is ugly and unmistakable, which is what a missing translation should be.
public enum Strings {
    /// The chosen language's own bundle, and English as the floor under it. Guarded because a
    /// card can ask for a word from a background task while Settings is changing the language.
    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var chosen: Bundle?
        private var fallback: Bundle?
        private var language: AppLanguage = .system

        func set(_ language: AppLanguage, chosen: Bundle?, fallback: Bundle?) {
            lock.lock()
            defer { lock.unlock() }
            self.language = language
            self.chosen = chosen
            self.fallback = fallback
        }

        var bundles: (chosen: Bundle?, fallback: Bundle?) {
            lock.lock()
            defer { lock.unlock() }
            return (chosen, fallback)
        }

        var current: AppLanguage {
            lock.lock()
            defer { lock.unlock() }
            return language
        }
    }

    private static let store = Store()

    public static var current: AppLanguage { store.current }

    /// Points the tables at a language. `system` means the one macOS picked for the app, which is
    /// what `Bundle.main` already answers with.
    ///
    /// `root` is for the suite, which runs as a plain executable with no bundle of its own and
    /// reads the tables straight out of the repository.
    public static func use(_ language: AppLanguage, lookingIn root: URL? = nil) {
        let fallback = lproj(AppLanguage.english.rawValue, in: root)
        switch language {
        case .system where root == nil:
            store.set(language, chosen: .main, fallback: fallback)
        case .system:
            store.set(language, chosen: fallback, fallback: fallback)
        default:
            store.set(language, chosen: lproj(language.rawValue, in: root) ?? .main, fallback: fallback)
        }
    }

    private static func lproj(_ code: String, in root: URL?) -> Bundle? {
        if let root { return Bundle(url: root.appendingPathComponent("\(code).lproj")) }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// The translation for a key, or the English one, or the key.
    public static func string(_ key: String) -> String {
        let (chosen, fallback) = store.bundles
        // A missing key comes back as the key itself, which is how the next bundle gets a turn.
        if let chosen {
            let value = chosen.localizedString(forKey: key, value: key, table: nil)
            if value != key { return value }
        }
        if let fallback {
            let value = fallback.localizedString(forKey: key, value: key, table: nil)
            if value != key { return value }
        }
        return key
    }

    /// A key whose translation carries a count, from `Localizable.stringsdict`: one file per
    /// language decides how many forms there are, because Russian has three where English has two
    /// and no amount of string joining gets that right.
    public static func plural(_ key: String, _ count: Int) -> String {
        String(format: string(key), locale: locale, count)
    }

    /// The locale the numbers and the plural rules are read in.
    public static var locale: Locale {
        switch store.current {
        case .system: return .current
        default: return Locale(identifier: store.current.rawValue)
        }
    }
}

/// The short name every call site uses. Arguments are positional, so a translation may reorder
/// them with `%1$@`, which several of these languages need.
public func L(_ key: String) -> String {
    Strings.string(key)
}

public func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: Strings.string(key), locale: Strings.locale, arguments: arguments)
}

/// A count and the words that go with it, in the forms the language actually has.
public func LN(_ key: String, _ count: Int) -> String {
    Strings.plural(key, count)
}
