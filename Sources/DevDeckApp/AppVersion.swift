import Foundation

/// Which build is running.
///
/// The build number is the commit count, written into the bundle by `build.sh`, so it moves
/// on every rebuild — which makes it the quickest way to answer "am I looking at the change
/// I just made, or at the copy that was already running?".
enum AppVersion {
    static var summary: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        guard let short, let build else {
            // `swift run` has no bundle to read, and neither does an unpackaged binary.
            return "DevDeck, development build"
        }
        return "DevDeck \(short) (build \(build))"
    }

    /// The bundle actually running. There are usually two copies — the one in the repository
    /// and the installed one — and knowing which is in front saves a puzzled minute.
    static var location: String {
        let path = Bundle.main.bundleURL.path
        return path.hasSuffix(".app") ? path : "not running from a bundle"
    }
}
