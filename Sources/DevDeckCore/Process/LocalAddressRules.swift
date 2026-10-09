import Foundation

/// This machine's address on the network the phone is also on.
///
/// The cheapest possible answer to "let me look at this on my phone": no account, no tunnel, no
/// third party, nothing published to the internet. The site is already being served; it is only
/// being asked for by the wrong name, because `localhost` on a phone means the phone.
public enum LocalAddress {
    /// Whether the site behind this URL is served by this machine, whatever name it goes by.
    ///
    /// Wider than `isLoopback`: DDEV serves `*.ddev.site`, which public DNS points back at
    /// 127.0.0.1, and `*.localhost` never leaves the machine either. Such a link goes nowhere
    /// while the project is down, which is what the card needs to know. It is not the question
    /// the phone asks, since a router that picks the project by name cannot be reached by an
    /// address instead.
    public static func isServedHere(_ url: URL?) -> Bool {
        if isLoopback(url) { return true }
        guard let host = url?.host?.lowercased() else { return false }
        return host.hasSuffix(".localhost") || host == "ddev.site" || host.hasSuffix(".ddev.site")
    }

    /// Whether this URL is this machine talking to itself.
    public static func isLoopback(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0" || host == "::1"
    }

    /// The same URL, addressed so another device on this network can ask for it.
    ///
    /// Returns nil for anything that is not this machine by another name: a link to a staging
    /// site does not need rewriting, and rewriting it would send the phone somewhere wrong.
    public static func rewrite(_ url: URL, to address: String) -> URL? {
        guard isLoopback(url) else { return nil }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = address
        return components?.url
    }
}
