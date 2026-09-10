import Foundation
import Security

/// Who signed a piece of code, as far as the Keychain and the updater care.
///
/// Three answers. Unsigned, which macOS on Apple silicon does not really allow any more.
/// Ad-hoc, which is what `codesign --sign -` and the linker produce: a signature with nobody
/// behind it, different for every build. And signed, with an identity that survives a rebuild:
/// a Developer ID, named by its team, or a certificate somebody made by hand, named by its
/// subject.
public enum CodeIdentity {
    public enum Kind: Sendable, Equatable {
        case unsigned
        case adHoc
        case signed(identity: String)

        /// Whether two builds signed like this are the same application to macOS.
        public var survivesRebuild: Bool {
            if case .signed = self { return true }
            return false
        }
    }

    /// The running process.
    public static func current() -> Kind {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return .unsigned }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return .unsigned
        }
        return kind(of: staticCode)
    }

    /// A bundle on disk, for the updater to ask about a build before it replaces itself with it.
    public static func kind(ofBundleAt url: URL) -> Kind {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            return .unsigned
        }
        return kind(of: staticCode)
    }

    private static func kind(of code: SecStaticCode) -> Kind {
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
              let info = information as? [String: Any],
              info[kSecCodeInfoIdentifier as String] != nil
        else { return .unsigned }

        let signatureFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if signatureFlags & SecCodeSignatureFlags.adhoc.rawValue != 0 { return .adHoc }

        if let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return .signed(identity: team)
        }
        // A certificate with no team behind it, made by hand. Its subject is the identity.
        if let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let leaf = certificates.first,
           let subject = SecCertificateCopySubjectSummary(leaf) as String?,
           !subject.isEmpty {
            return .signed(identity: subject)
        }
        return .adHoc
    }
}

/// How the stored tokens are protected, which follows from how the app is signed.
///
/// Signed with an identity that survives a rebuild, the Keychain can do what it does by
/// default: bind each item to this application, and nobody else reads it without a prompt.
/// Ad-hoc, that binding breaks on every build, and the alternative to an open access list is
/// one password prompt per token per update, which is how tokens stop being stored at all.
public enum KeychainAccessPolicy {
    /// The mode the items should be written in for this identity, as the string the
    /// preferences remember, so a change of signature is noticed at the next launch.
    public static func mode(for identity: CodeIdentity.Kind) -> String {
        switch identity {
        case .signed(let name): return "app:\(name)"
        case .adHoc, .unsigned: return "open"
        }
    }

    /// Whether items are written with the access list that names no application.
    public static func opensAccess(for identity: CodeIdentity.Kind) -> Bool {
        !identity.survivesRebuild
    }
}
