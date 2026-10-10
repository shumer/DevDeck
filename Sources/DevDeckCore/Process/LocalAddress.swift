import Foundation

#if os(Windows)
import WinSDK

/// Reading this machine's physical Windows adapters through IP Helper.
extension LocalAddress {
    /// The address, or nil when this machine is not on a network the phone could share.
    public static func current() -> String? {
        addresses().first
    }

    /// Every IPv4 address on a real adapter, best first.
    public static func addresses() -> [String] {
        let flags = ULONG(
            GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER)
        var byteCount: ULONG = 0
        let measured = GetAdaptersAddresses(ULONG(AF_INET), flags, nil, nil, &byteCount)
        guard measured == ERROR_BUFFER_OVERFLOW, byteCount > 0 else { return [] }

        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: Int(byteCount), alignment: MemoryLayout<IP_ADAPTER_ADDRESSES_LH>.alignment)
        defer { memory.deallocate() }
        let first = memory.bindMemory(to: IP_ADAPTER_ADDRESSES_LH.self, capacity: 1)
        guard GetAdaptersAddresses(ULONG(AF_INET), flags, nil, first, &byteCount) == NO_ERROR else {
            return []
        }

        var adapters: [Adapter] = []
        var current: UnsafeMutablePointer<IP_ADAPTER_ADDRESSES_LH>? = first
        while let adapter = current {
            let value = adapter.pointee
            let name = value.FriendlyName.map(wideString) ?? ""
            let description = value.Description.map(wideString) ?? ""
            var unicast = value.FirstUnicastAddress
            while let address = unicast {
                if let socketAddress = address.pointee.Address.lpSockaddr,
                   socketAddress.pointee.sa_family == ADDRESS_FAMILY(AF_INET),
                   let text = ipv4String(socketAddress, address.pointee.Address.iSockaddrLength) {
                    adapters.append(Adapter(
                        name: name,
                        description: description,
                        address: text,
                        isUp: value.OperStatus == IfOperStatusUp,
                        isLoopback: value.IfType == ULONG(IF_TYPE_SOFTWARE_LOOPBACK),
                        isWireless: value.IfType == ULONG(IF_TYPE_IEEE80211)
                    ))
                }
                unicast = address.pointee.Next
            }
            current = value.Next
        }
        return preferredAddresses(from: adapters)
    }

    private static func wideString(_ pointer: UnsafeMutablePointer<WCHAR>) -> String {
        String(decodingCString: pointer, as: UTF16.self)
    }

    private static func ipv4String(_ address: LPSOCKADDR, _ length: INT) -> String? {
        var buffer = [WCHAR](repeating: 0, count: 46)
        var bufferLength = DWORD(buffer.count)
        let result = buffer.withUnsafeMutableBufferPointer { output in
            WSAAddressToStringW(address, DWORD(length), nil, output.baseAddress, &bufferLength)
        }
        guard result == 0 else { return nil }
        return buffer.withUnsafeBufferPointer { output in
            guard let start = output.baseAddress else { return nil }
            return String(decodingCString: start, as: UTF16.self)
        }
    }
}
#else
/// Reading this machine's interfaces on the Mac. The shared selection rules are in
/// `LocalAddressRules.swift`.
extension LocalAddress {
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
            // Up to the terminator, decoded as bytes: `String(cString:)` on an array is
            // deprecated, and the buffer is NI_MAXHOST wide whatever the address is.
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            found.append((name, String(decoding: bytes, as: UTF8.self)))
        }

        // `en0` before `en1` before the rest: the first is wifi, which is what a phone is on.
        return found.sorted { $0.name < $1.name }.map(\.address)
    }
}
#endif
