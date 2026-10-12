import ArcKit
import AzureKit
import DDEVKit
import DevDeckCore
import Foundation
import GitHubKit
import GitLabKit
import ProjectKit

// The settings operations as one request and one answer, for a settings window in another
// process. The Mac's forms call the same operations directly. See docs/engine-protocol.md.

/// The deck-wide settings a settings window shows and changes.
///
/// The Mac's summon key is not here: it is a Mac key code the Mac's own settings page edits. The
/// Windows shortcut is, as text the Windows shell reads and writes.
public struct DeckPreferencesModel: Sendable, Equatable, Codable {
    public var language: AppLanguage
    public var displayMode: DisplayMode
    public var isLocked: Bool
    public var packsColumns: Bool
    public var refreshIntervalSeconds: TimeInterval
    public var notificationsEnabled: Bool
    public var notifiesUpdates: Bool
    public var checksForUpdates: Bool
    public var summonEnabled: Bool
    public var summonDims: Bool
    /// `Ctrl+Shift+Space`, in Windows words; nil for the shell's default.
    public var summonShortcutWindows: String?
    public var actionsRepositories: [String]
    /// Projects whose going down is not worth a banner, by id, sorted.
    public var projectsQuietWhenDown: [String]
    /// Projects whose failed start is not worth a banner, by id, sorted.
    public var projectsQuietWhenStartFails: [String]
    /// What a coding agent may do through the deck. Optional on the way in, so a shell that does
    /// not know the field yet leaves it as it is.
    public var agentAccess: AgentAccess?
}

/// A card as the Cards page lists it: what it is, and whether it is on the deck.
public struct DeckSettingsCard: Sendable, Equatable, Codable {
    public let id: CardID
    public let title: String
    public let detail: String
    public let isEnabled: Bool
    /// A project's card rather than a built-in one: the page lists those under their own
    /// heading, after the built-in cards.
    public let isProject: Bool
}

/// Where a new token is made, for the link under a form's token row.
public enum DeckTokenPages {
    public static let github = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    /// The instance's own page, with the name and the one scope the card needs filled in.
    public static func gitlab(host: URL) -> URL {
        var components = URLComponents(url: host.appendingPathComponent("-/user_settings/personal_access_tokens"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "name", value: "DevDeck"), URLQueryItem(name: "scopes", value: "read_api")]
        return components?.url ?? host
    }

    /// The organization's token page. Azure DevOps takes no scopes in the link, so the form's
    /// help says which to tick.
    public static func azure(organization: String) -> URL {
        guard !organization.isEmpty else { return AzureAccount.host }
        return AzureAccount.host.appendingPathComponent(organization).appendingPathComponent("_usersSettings/tokens")
    }
}

/// One thing a settings window asks of the engine.
public enum DeckSettingsRequest: Sendable, Equatable, Codable {
    /// The sidebar.
    case list
    /// The Cards page: every built-in card, in deck order, with its switch.
    case cards
    /// A switch on the Cards page.
    case setCard(id: CardID, isEnabled: Bool)
    /// Every word a settings window says, in the deck's language: the keys under
    /// `DeckSettingsWords.prefixes` with their translations.
    case words
    case preferences
    case setPreferences(DeckPreferencesModel)
    case terminalSettings
    case setTerminalApplication(value: String?)
    case setTerminalProfile(value: String?)
    /// Where the deck's MCP server stands with each agent on this computer. Also sent unasked,
    /// as `settings.answered` with no id, whenever that changes.
    case agentClients

    // What a form edits, as stored.
    case localProject(id: String)
    case arcProject(id: String)
    case ddevProject(id: String)
    case githubAccount(id: String)
    case gitlabAccount(id: String)
    case azureAccount(id: String)

    case addLocalProject(folder: String)
    case saveLocalProject(LocalProject)
    case removeLocalProject(id: String)
    case detect(folder: String?)
    case checkLocalProject(LocalProject)
    case testLocalProjectLink(LocalProject)

    case addArcProject
    case saveArcProject(ArcProject)
    case restructureArcProject(ArcProject)
    case removeArcProject(id: String)
    case checkArcStack(ArcProject)
    case testArcProjectLink(ArcProject)

    case ddevCandidates
    case addDDEVProject(DDEVListEntry)
    case saveDDEVProject(DDEVProject)
    case removeDDEVProject(id: String)
    case ddevFolderNote(folder: String)
    case testDDEVProjectLink(DDEVProject)

    case addGitHubAccount
    case addGitLabAccount
    case addAzureAccount
    case saveGitHubAccount(GitHubAccount)
    case saveGitLabAccount(GitLabAccount)
    case saveAzureAccount(AzureAccount)
    case removeGitHubAccount(id: String)
    case removeGitLabAccount(id: String)
    case removeAzureAccount(id: String)
    case testGitHubAccountLink(GitHubAccount)
    case testGitLabAccountLink(GitLabAccount)
    case testAzureAccountLink(AzureAccount)
    /// The token typed into the form, or an empty one to check the stored token. A token that
    /// works is stored; it is never sent back.
    case checkGitHubToken(GitHubAccount, typed: String)
    case checkGitLabToken(GitLabAccount, typed: String)
    case checkAzureToken(AzureAccount, typed: String)
    /// The page where a token is made, opened in the default browser.
    case openGitHubTokenPage
    case openGitLabTokenPage(GitLabAccount)
    case openAzureTokenPage(AzureAccount)

    /// Whether the answer means the deck itself changed: cards came or went, or a deck-wide
    /// setting moved.
    var changesDeck: Bool {
        switch self {
        case .setPreferences, .setCard, .addLocalProject, .saveLocalProject, .removeLocalProject,
             .addArcProject, .saveArcProject, .restructureArcProject, .removeArcProject,
             .addDDEVProject, .saveDDEVProject, .removeDDEVProject,
             .addGitHubAccount, .addGitLabAccount, .addAzureAccount,
             .saveGitHubAccount, .saveGitLabAccount, .saveAzureAccount,
             .removeGitHubAccount, .removeGitLabAccount, .removeAzureAccount,
             .checkGitHubToken, .checkGitLabToken, .checkAzureToken:
            return true
        default:
            return false
        }
    }
}

/// What the engine answers.
public enum DeckSettingsAnswer: Sendable, Equatable, Codable {
    case list(DeckSettingsList)
    case cards([DeckSettingsCard])
    case words([String: String])
    case preferences(DeckPreferencesModel)
    case terminalSettings(DeckTerminalSettings)
    case agentClients([DeckAgentClient])
    case localProject(LocalProject?)
    case arcProject(ArcProject?)
    case ddevProject(DDEVProject?)
    case githubAccount(GitHubAccount?)
    case gitlabAccount(GitLabAccount?)
    case azureAccount(AzureAccount?)
    /// Something was added under this id.
    case added(id: String)
    /// Saved. `checkAgain` when the form's status line has a new question to answer.
    case saved(checkAgain: Bool)
    case done
    case detection(DeckDetection)
    /// A form's status line.
    case check(CheckSummary)
    /// Words for the form, or nothing to say.
    case note(String?)
    case ddevCandidates(DeckDDEVCandidates)
    case token(DeckTokenCheck)
}

/// Which keys a settings window needs: its pages, its forms, the token and check rows, the
/// buttons, the update row and the notification toggles.
public enum DeckSettingsWords {
    public static let prefixes = [
        "settings.", "account.", "project.", "token.", "ddev.", "check.", "button.", "update.", "notify.toggle.",
    ]
}

extension DeckRuntime {
    public var preferencesModel: DeckPreferencesModel {
        DeckPreferencesModel(
            language: preferences.language,
            displayMode: preferences.displayMode,
            isLocked: preferences.isLocked,
            packsColumns: preferences.packsColumns,
            refreshIntervalSeconds: preferences.refreshIntervalSeconds,
            notificationsEnabled: preferences.notificationsEnabled,
            notifiesUpdates: preferences.notifiesUpdates,
            checksForUpdates: preferences.checksForUpdates,
            summonEnabled: preferences.summonEnabled,
            summonDims: preferences.summonDims,
            summonShortcutWindows: preferences.summonShortcutWindows,
            actionsRepositories: preferences.actionsRepositories,
            projectsQuietWhenDown: preferences.projectsQuietWhenDown.sorted(),
            projectsQuietWhenStartFails: preferences.projectsQuietWhenStartFails.sorted(),
            agentAccess: preferences.agentAccess
        )
    }

    func apply(_ model: DeckPreferencesModel) {
        preferences.language = model.language
        preferences.displayMode = model.displayMode
        preferences.isLocked = model.isLocked
        preferences.packsColumns = model.packsColumns
        preferences.refreshIntervalSeconds = model.refreshIntervalSeconds
        preferences.notificationsEnabled = model.notificationsEnabled
        preferences.notifiesUpdates = model.notifiesUpdates
        preferences.checksForUpdates = model.checksForUpdates
        preferences.summonEnabled = model.summonEnabled
        preferences.summonDims = model.summonDims
        preferences.summonShortcutWindows = model.summonShortcutWindows
        preferences.actionsRepositories = model.actionsRepositories
        preferences.projectsQuietWhenDown = Set(model.projectsQuietWhenDown)
        preferences.projectsQuietWhenStartFails = Set(model.projectsQuietWhenStartFails)
        if let access = model.agentAccess {
            preferences.agentAccess = access
            agents?.applyPreferences()
        }
    }

    /// Carries out one request. A link to test is opened as an effect, like any other link.
    public func answer(_ request: DeckSettingsRequest) async -> DeckSettingsAnswer {
        switch request {
        case .list: return .list(settingsList())
        case .cards: return .cards(settingsCards())
        case .setCard(let id, let isEnabled):
            cards.setEnabled(isEnabled, for: id)
            effect(.cardsChanged)
            return .cards(settingsCards())
        case .words:
            var words = Strings.words(withPrefixes: DeckSettingsWords.prefixes)
            // The one line that names the platform: how banners are kept. The window asks for
            // the same key on both, and the engine says the right thing for the machine it is on.
            #if os(Windows)
            words["settings.notifications.allow.detail"] = L("settings.notifications.allow.detail.windows")
            words["settings.deck.lock.detail"] = L("settings.deck.lock.detail.windows")
            #endif
            return .words(words)
        case .preferences: return .preferences(preferencesModel)
        case .terminalSettings: return .terminalSettings(terminalSettings())
        case .agentClients: return .agentClients(agents?.clients ?? [])
        case .setTerminalApplication(let value):
            setTerminalApplication(value)
            return .terminalSettings(terminalSettings())
        case .setTerminalProfile(let value):
            setTerminalProfile(value)
            return .terminalSettings(terminalSettings())
        case .setPreferences(let model):
            apply(model)
            return .preferences(preferencesModel)

        case .localProject(let id): return .localProject(localProjectsStore.projects().first { $0.id == id })
        case .arcProject(let id): return .arcProject(projectsStore.projects().first { $0.id == id })
        case .ddevProject(let id): return .ddevProject(ddevProjectsStore.projects().first { $0.id == id })
        case .githubAccount(let id): return .githubAccount(accountsStore.accounts().first { $0.id == id })
        case .gitlabAccount(let id): return .gitlabAccount(gitlabAccountsStore.accounts().first { $0.id == id })
        case .azureAccount(let id): return .azureAccount(azureAccountsStore.accounts().first { $0.id == id })

        case .addLocalProject(let folder): return .added(id: addLocalProject(folder: URL(fileURLWithPath: folder)))
        case .saveLocalProject(let project): return .saved(checkAgain: saveLocalProject(project))
        case .removeLocalProject(let id):
            removeLocalProject(id)
            return .done
        case .detect(let folder):
            return .detection(detect(folder: folder.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }))
        case .checkLocalProject(let project):
            let status = await checkLocalProject(project)
            return .check(status.summary(checkedURL: project.healthURL, currentURL: project.healthURL))
        case .testLocalProjectLink(let project): return open(testLink(project))

        case .addArcProject: return .added(id: addArcProject())
        case .saveArcProject(let project): return .saved(checkAgain: saveArcProject(project))
        case .restructureArcProject(let project):
            restructureArcProject(project)
            return .done
        case .removeArcProject(let id):
            removeArcProject(id)
            return .done
        case .checkArcStack(let project):
            guard let status = await checkArcStack(project) else { return .check(Self.stackNotConfigured) }
            let address = Self.stackAddress(of: project)
            return .check(status.summary(checkedAddress: address, currentAddress: address))
        case .testArcProjectLink(let project): return open(testLink(project))

        case .ddevCandidates: return .ddevCandidates(await ddevCandidates())
        case .addDDEVProject(let entry): return .added(id: addDDEVProject(entry))
        case .saveDDEVProject(let project):
            saveDDEVProject(project)
            return .saved(checkAgain: false)
        case .removeDDEVProject(let id):
            removeDDEVProject(id)
            return .done
        case .ddevFolderNote(let folder): return .note(ddevFolderNote(URL(fileURLWithPath: folder)))
        case .testDDEVProjectLink(let project): return open(await testLink(project))

        case .addGitHubAccount: return .added(id: addGitHubAccount())
        case .addGitLabAccount: return .added(id: addGitLabAccount())
        case .addAzureAccount: return .added(id: addAzureAccount())
        case .saveGitHubAccount(let account):
            saveGitHubAccount(account)
            return .saved(checkAgain: false)
        case .saveGitLabAccount(let account):
            saveGitLabAccount(account)
            return .saved(checkAgain: false)
        case .saveAzureAccount(let account):
            saveAzureAccount(account)
            return .saved(checkAgain: false)
        case .removeGitHubAccount(let id):
            removeGitHubAccount(id)
            return .done
        case .removeGitLabAccount(let id):
            removeGitLabAccount(id)
            return .done
        case .removeAzureAccount(let id):
            removeAzureAccount(id)
            return .done
        case .testGitHubAccountLink(let account): return open(testLink(account))
        case .testGitLabAccountLink(let account): return open(testLink(account))
        case .testAzureAccountLink(let account): return open(testLink(account))
        case .checkGitHubToken(let account, let typed): return .token(await checkGitHubToken(for: account, typed: typed))
        case .checkGitLabToken(let account, let typed): return .token(await checkGitLabToken(for: account, typed: typed))
        case .checkAzureToken(let account, let typed): return .token(await checkAzureToken(for: account, typed: typed))
        case .openGitHubTokenPage:
            effect(.openURL(DeckTokenPages.github, .systemDefault))
            return .done
        case .openGitLabTokenPage(let account):
            effect(.openURL(DeckTokenPages.gitlab(host: account.host), .systemDefault))
            return .done
        case .openAzureTokenPage(let account):
            effect(.openURL(DeckTokenPages.azure(organization: account.organization), .systemDefault))
            return .done
        }
    }

    /// The built-in cards the Cards page switches, as the Mac's page lists them: the ones that
    /// are implemented, in catalog order, projects and accounts left to their own pages.
    /// Every card with a switch: the built-in ones, then every project's. A project's card is
    /// what the menu's "take off the deck" hides, and this is the one page that shows it again.
    func settingsCards() -> [DeckSettingsCard] {
        let builtIn = Set(CardCatalog.all.map(\.id))
        return cards.catalog.filter(\.isImplemented).map { descriptor in
            DeckSettingsCard(
                id: descriptor.id, title: descriptor.title, detail: descriptor.subtitle,
                isEnabled: cards.isEnabled(descriptor.id), isProject: !builtIn.contains(descriptor.id)
            )
        }
    }

    private func open(_ test: DeckLinkTest) -> DeckSettingsAnswer {
        switch test {
        case .open(let url, let browser):
            effect(.openURL(url, browser))
            return .note(nil)
        case .note(let words):
            return .note(words)
        }
    }
}
