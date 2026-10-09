import Foundation

/// Where a project's folder is, read from the folder itself: a Windows folder, a folder inside a
/// WSL distribution, or an ordinary POSIX folder.
///
/// The same text means the same place on every platform, so the label a card wears and the
/// golden transcripts that pin it do not depend on which machine reads them. Which runner a
/// project gets on Windows follows from it. See docs/adr/0023-project-process-lifetime.md.
public enum ProjectLocation: Sendable, Equatable {
    /// `C:\Users\demo\site`.
    case windows(path: String)
    /// `\\wsl.localhost\Ubuntu-24.04\home\demo\site`, as `Ubuntu-24.04` and `/home/demo/site`.
    case wsl(distribution: String, path: String)
    /// `/Users/demo/site`: the Mac, or a folder whose distribution is not named.
    case posix(path: String)

    public init?(folder: String?) {
        guard let folder, !folder.isEmpty else { return nil }
        let normalized = folder.replacingOccurrences(of: "\\", with: "/")
        let letters = Array(normalized)
        if letters.count >= 3, letters[0].isASCII, letters[0].isLetter, letters[1] == ":", letters[2] == "/" {
            self = .windows(path: folder)
            return
        }
        for prefix in ["//wsl.localhost/", "//wsl$/"] where normalized.lowercased().hasPrefix(prefix) {
            let parts = normalized.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: true)
            guard let name = parts.first else { return nil }
            self = .wsl(distribution: String(name), path: "/" + parts.dropFirst().joined(separator: "/"))
            return
        }
        self = .posix(path: folder)
    }

    /// What a card says about it, or nil where there is only one place a project can be.
    public var label: String? {
        switch self {
        case .windows: return L("project.place.windows")
        case .wsl(let distribution, _): return L("project.place.wsl", distribution)
        case .posix: return nil
        }
    }
}
