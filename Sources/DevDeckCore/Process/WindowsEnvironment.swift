#if os(Windows)
import Foundation
import WinSDK

enum WindowsEnvironment {
    static func current() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.filter { $0.key.lowercased() != "path" }
        let machine = registryString(
            root: HKEY_LOCAL_MACHINE, key: "SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment")
        let user = registryString(root: HKEY_CURRENT_USER, key: "Environment")
        environment["Path"] = [machine, user].compactMap { $0 }.joined(separator: ";")
        return environment
    }

    static var localAppData: String? {
        registryString(
            root: HKEY_CURRENT_USER,
            key: "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders",
            field: "Local AppData")
    }

    private static func registryString(root: HKEY?, key: String, field: String = "Path") -> String? {
        let name = Array((field + "\0").utf16)
        let subkey = Array((key + "\0").utf16)
        var size: DWORD = 0
        return subkey.withUnsafeBufferPointer { keyBuffer in
            name.withUnsafeBufferPointer { nameBuffer in
                let flags = DWORD(RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ)
                guard
                    RegGetValueW(root, keyBuffer.baseAddress, nameBuffer.baseAddress, flags, nil, nil, &size)
                        == ERROR_SUCCESS
                else { return nil }
                var value = [WCHAR](repeating: 0, count: Int(size) / 2)
                let result = value.withUnsafeMutableBytes {
                    RegGetValueW(
                        root, keyBuffer.baseAddress, nameBuffer.baseAddress, flags, nil, $0.baseAddress, &size
                    )
                }
                guard result == ERROR_SUCCESS else { return nil }
                return String(decoding: value.prefix { $0 != 0 }, as: UTF16.self)
            }
        }
    }
}
#endif
