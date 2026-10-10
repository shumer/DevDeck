import ArcKit
import DDEVKit
import DevDeckCore
import DevDeckEngine
import DevDeckLocalization
import Foundation
import GitHubKit
import GitLabKit
import ProjectKit

// The engine for a shell in another process: a deck session over standard input and output,
// one JSON object per line each way. See docs/engine-protocol.md.
//
// Everything the deck remembers is the engine's: preferences, accounts and projects in one file
// under %LOCALAPPDATA%\DevDeck, tokens in Credential Manager. The shell keeps nothing.

func diagnostic(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

#if os(Windows)
let backend = FilePreferencesBackend.standard()
let tokenStore: any TokenStore = WindowsCredentialTokenStore()
// Native projects run through the process host, so they outlive this process; a project in a
// WSL distribution runs through that distribution's own client. See ADR 0023.
let runner: any CommandRunning = NativeWindowsCommandRunner()
let folderRunner: @Sendable (String?) -> any CommandRunning = { folder in
    if case .wsl(let distribution, _)? = ProjectLocation(folder: folder) {
        return WSLCommandRunner(distribution: distribution)
    }
    return NativeWindowsCommandRunner()
}
// Docker Desktop, where its installer puts it. The shell launches it on the engine's say-so.
let programFiles = ProcessInfo.processInfo.environment["ProgramFiles"] ?? "C:\\Program Files"
let canStartDocker = FileManager.default.fileExists(atPath: programFiles + "\\Docker\\Docker\\Docker Desktop.exe")
#else
// On the Mac the host is for development: it keeps its own preferences, apart from the app's,
// and never opens the app's Keychain items. A token for it is typed into a check and forgotten
// when it exits.
let backend: any PreferencesBackend = UserDefaults(suiteName: "com.shumer.devdeck.host") ?? .standard
let tokenStore: any TokenStore = InMemoryTokenStore()
let runner: any CommandRunning = ShellCommandRunner()
let folderRunner: (@Sendable (String?) -> any CommandRunning)? = nil
let canStartDocker = false
#endif

let runtime = DeckRuntime(
    preferences: Preferences(backend: backend),
    tokenStore: tokenStore,
    accountsStore: GitHubAccountsStore(backend: backend),
    gitlabAccountsStore: GitLabAccountsStore(backend: backend),
    projectsStore: ArcProjectsStore(backend: backend),
    ddevProjectsStore: DDEVProjectsStore(backend: backend),
    localProjectsStore: LocalProjectsStore(backend: backend),
    commandRunner: runner,
    canStartDocker: canStartDocker,
    localAddress: { LocalAddress.current() },
    folderRunner: folderRunner
)
let session = DeckSession(runtime: runtime, localizationRoot: LocalizationResources.root) { data in
    FileHandle.standardOutput.write(data)
}
// Nothing to replace yet: the Windows installer is W-17. The row says so.
session.watchForUpdates(currentVersion: nil, canInstall: false, http: URLSessionHTTPClient.makeDefault())

let input = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(32)) { continuation in
    DispatchQueue.global().async {
        var pending = Data()
        var oversized = false
        while true {
            let chunk = FileHandle.standardInput.availableData
            if chunk.isEmpty { break }
            for byte in chunk {
                if byte == 10 {
                    if pending.last == 13 { pending.removeLast() }
                    if !oversized, !pending.isEmpty {
                        if case .dropped = continuation.yield(pending) {
                            diagnostic("Input queue is full.")
                        }
                    }
                    pending.removeAll(keepingCapacity: true)
                    oversized = false
                } else if !oversized {
                    if pending.count >= DeckIntent.maximumSize {
                        diagnostic("Input message exceeds 1 MiB.")
                        pending.removeAll(keepingCapacity: true)
                        oversized = true
                    } else {
                        pending.append(byte)
                    }
                }
            }
        }
        if !pending.isEmpty { diagnostic("Incomplete input message.") }
        continuation.finish()
    }
}

for await line in input {
    session.handle(line: line)
}
// The shell closed the pipe: stop the loops. The projects keep running.
session.stop()
