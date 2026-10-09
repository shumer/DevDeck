#if os(Windows)
import Foundation
import WinSDK

/// API tokens in Windows Credential Manager: one generic credential per token, named
/// `service/account`, readable only by the signed-in user. The Windows twin of
/// `KeychainTokenStore`, and like it the only place a token is persisted.
public struct WindowsCredentialTokenStore: TokenStore {
    /// `ERROR_NOT_FOUND`: there is no credential under that name, which is an answer, not a failure.
    private static let notFound: DWORD = 1168

    public init() {}

    static func target(_ key: TokenKey) -> String {
        "\(key.service)/\(key.account)"
    }

    public func token(for key: TokenKey) throws -> String? {
        var pointer: PCREDENTIALW?
        let read = Self.target(key).withCString(encodedAs: UTF16.self) { name in
            CredReadW(name, DWORD(CRED_TYPE_GENERIC), 0, &pointer)
        }
        guard read else {
            let error = GetLastError()
            if error == Self.notFound { return nil }
            throw TokenStoreError.keychain(Int32(bitPattern: error))
        }
        defer { CredFree(pointer) }
        guard let credential = pointer?.pointee, let blob = credential.CredentialBlob else { return nil }
        let data = Data(bytes: blob, count: Int(credential.CredentialBlobSize))
        guard let token = String(data: data, encoding: .utf8) else { throw TokenStoreError.invalidEncoding }
        return token
    }

    /// Nil or empty deletes the credential.
    public func setToken(_ token: String?, for key: TokenKey) throws {
        let target = Self.target(key)
        guard let token, !token.isEmpty else {
            let deleted = target.withCString(encodedAs: UTF16.self) { name in
                CredDeleteW(name, DWORD(CRED_TYPE_GENERIC), 0)
            }
            if !deleted {
                let error = GetLastError()
                if error != Self.notFound { throw TokenStoreError.keychain(Int32(bitPattern: error)) }
            }
            return
        }
        var bytes = Array(token.utf8)
        let written = target.withCString(encodedAs: UTF16.self) { name in
            key.account.withCString(encodedAs: UTF16.self) { user in
                bytes.withUnsafeMutableBytes { blob in
                    var credential = CREDENTIALW()
                    credential.`Type` = DWORD(CRED_TYPE_GENERIC)
                    credential.TargetName = UnsafeMutablePointer(mutating: name)
                    credential.UserName = UnsafeMutablePointer(mutating: user)
                    credential.CredentialBlobSize = DWORD(blob.count)
                    credential.CredentialBlob = blob.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    // Kept for this user on this machine, not roamed to other machines.
                    credential.Persist = DWORD(CRED_PERSIST_LOCAL_MACHINE)
                    return CredWriteW(&credential, 0)
                }
            }
        }
        if !written { throw TokenStoreError.keychain(Int32(bitPattern: GetLastError())) }
    }
}
#endif
