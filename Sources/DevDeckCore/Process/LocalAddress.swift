import Foundation

/// This machine's address on the network the phone is also on.
///
/// The cheapest possible answer to "let me look at this on my phone": no account, no tunnel, no
/// third party, nothing published to the internet. The site is already being served; it is only
/// being asked for by the wrong name, because `localhost` on a phone means the phone.
public enum LocalAddress {
    /// Interfaces worth offering, in the order they are worth offering.
    ///
    /// `en0` is wifi on every Mac and the one the phone is almost certainly on. `en1` and up are
    /// Thunderbolt Ethernet and docks, which are right when the laptop is wired. Everything else
    /// - `utun` for VPNs, `bridge` for Docker and virtual machines, `awdl` for AirDrop - is an
    /// address the phone cannot reach, and offering one would produce a QR code that fails
    /// silently, which is worse than none.
    static let interfacePrefixes = ["en"]

    /// The address, or nil when this machine is not on a network the phone could share.
    public static func current() -> String? {
        addresses().first
    }

    /// Every IPv4 address on a real interface, best first.
    public static func addresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var found: [(name: String, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0 else { continue }
            guard let sockaddr = current.pointee.ifa_addr, sockaddr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let name = String(cString: current.pointee.ifa_name)
            guard interfacePrefixes.contains(where: { name.hasPrefix($0) }) else { continue }

            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sockaddr,
                socklen_t(sockaddr.pointee.sa_len),
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            found.append((name, String(cString: buffer)))
        }

        // `en0` before `en1` before the rest: the first is wifi, which is what a phone is on.
        return found.sorted { $0.name < $1.name }.map(\.address)
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
