import ArcKit
import DDEVKit
import DevDeckCore
import Foundation
import ProjectKit

/// The Arc, DDEV and plain project cards, which are one card fed by three kinds of project.
///
/// Whether it is up, where to open it, and what to press. The three used to be three views built
/// from the same pieces; they are now three builders of one model, so a change to what a project
/// card says is made once.
public struct DeckProjectCardModel: Sendable, Equatable, Codable {
    /// A link on the card.
    public struct Chip: Sendable, Equatable, Codable, Identifiable {
        public enum Kind: String, Sendable, Equatable, Codable {
            /// Something you work in: PageBuilder, Mailpit, an admin page.
            case tool
            /// The site served on this machine.
            case local
            /// A deployed environment that is production, worth a beat of hesitation.
            case production
            /// Any other deployed environment.
            case environment
        }

        public let label: String
        public let kind: Kind
        /// A local link while nothing is serving it: it would land on a connection error that
        /// reads as a broken app rather than a stopped one.
        public let isDimmed: Bool
        public let help: String
        public let command: DeckCommand?

        public var id: String { label }
    }

    public struct Hero: Sendable, Equatable, Codable {
        public let tone: DeckTone
        public let text: String
        /// The trailing words: containers, a pid, why Stop cannot reach it.
        public let note: String?
        public let help: String
    }

    public struct Meta: Sendable, Equatable, Codable {
        /// The branch, linked to the repository when the checkout has an origin. It opens the
        /// repository rather than the branch: a branch link has to be right about whether the
        /// remote has the branch, and being wrong lands on a 404.
        public let branch: String?
        public let branchHelp: String
        public let repository: DeckCommand?
        public let leading: String?
        public let trailing: String?
        /// Where the project runs, `Windows` or `WSL · Ubuntu-24.04`, where there is more than
        /// one place it could. Information, not a link.
        public let place: String?

        init(branch: String?, repositoryURL: URL?, card: CardID, folder: String?, leading: String?, trailing: String?) {
            self.branch = branch
            branchHelp = repositoryURL.map { L("card.branch.help", $0.absoluteString, branch ?? "") } ?? L("card.branch.checkedOut")
            repository = repositoryURL.map { .openProjectLink(card, $0) }
            place = ProjectLocation(folder: folder)?.label
            self.leading = leading
            self.trailing = trailing
        }
    }

    /// The buttons in the card's header.
    public struct Header: Sendable, Equatable, Codable {
        public let logIsOn: Bool
        public let logHelp: String
        public let log: DeckCommand
        /// Only for a site actually being served: a QR code pointing at a port nothing is
        /// listening on is a worse answer than no button.
        public let phoneURL: URL?
        public let phoneHelp: String
        /// The words around the QR code.
        public let phoneTitle: String
        public let phoneNote: String
    }

    public let title: String
    public let mark: DeckMark
    public let timestamp: String
    public let header: Header
    public let hero: Hero
    public let meta: Meta
    public let tools: [Chip]
    public let environments: [Chip]
    public let actions: [DeckActionModel]
    public let collapsed: DeckCollapsedModel
    public let isCollapsed: Bool

    // MARK: The three kinds

    public static func arc(
        _ project: ArcProject,
        status: LocalStackStatus,
        docker: DockerStatus,
        canStartDocker: Bool,
        isShowingLogs: Bool,
        isCollapsed: Bool,
        phoneURL: URL?,
        startedBy: String? = nil,
        replacing: String? = nil
    ) -> DeckProjectCardModel {
        let card = project.cardID
        // Fusion runs in containers, so a project with a folder always needs Docker.
        let blocked = DockerGate.blocks(docker, isRunning: status.isRunning, requiresDocker: project.supportsLocalStack)
        let hero: Hero
        if blocked {
            // Docker first: `fusion daemon` fails at the first container without it, and "local
            // stack not running" would be a true sentence that helps nobody.
            hero = Hero(tone: DockerGate.tone(docker), text: DockerGate.text(docker), note: DockerGate.note(docker), help: status.detail ?? DockerGate.text(docker))
        } else {
            let tone: DeckTone
            let text: String
            switch status.state {
            // Running with something to say about it is not the same as running: a stop that did
            // not take effect leaves the stack up, and the card has to look wrong about it.
            case .running where status.detail != nil: tone = .attention; text = status.detail ?? L("card.state.running")
            case .running: tone = .good; text = L("card.state.running")
            case .working: tone = .attention; text = status.detail ?? L("card.state.working")
            case .stopped where status.readiness?.canStart == false:
                tone = .attention
                text = L("arc.readiness.notReady")
            case .stopped: tone = .neutral; text = L("card.state.stopped")
            case .unavailable: tone = .neutral; text = L("card.state.notConfigured")
            }
            // The container count earns the trailing slot only while the stack is up; otherwise
            // the reason the last command failed is the more useful thing to carry.
            let note: String?
            if status.isRunning, let containers = status.containers {
                note = LN("card.containers", containers)
            } else if status.isRunning, let startedBy {
                note = L("card.project.startedBy", startedBy)
            } else {
                note = status.state == .stopped ? status.detail : nil
            }
            hero = Hero(tone: tone, text: text, note: note, help: Self.help(status.detail ?? text, startedBy: status.isRunning ? startedBy : nil))
        }

        var environments: [Chip] = []
        if let local = status.siteURL ?? project.localSiteURL {
            // "Local site" rather than the port: the port is an implementation detail of this
            // checkout, and it is one hover away for anyone who wants it.
            environments.append(chip(L("card.localSite"), url: local, isSite: true, card: card, isRunning: status.isRunning))
        }
        if let editor = project.localPageBuilderURL {
            // Next to the local site, because it is the same stack: one is the page, the other is
            // where you edit it.
            environments.append(chip(L("card.localPageBuilder"), url: editor, isSite: true, card: card, isRunning: status.isRunning))
        }
        environments += project.siteLinks.map { chip($0.label, url: $0.url, isSite: true, card: card, isRunning: status.isRunning) }

        // Fusion runs one stack at a time: a start while another Arc card is up is also that
        // card's stop, and the button says so before it does it.
        let question = replacing.map { rival in
            DeckConfirmation(
                title: L("arc.replace.title", rival, project.title),
                detail: L("arc.replace.detail"),
                confirm: L("arc.replace.confirm", rival),
                cancel: L("button.cancel"),
                isDestructive: true
            )
        }
        let lifecycle = lifecycle(
            card: card, blocked: blocked, docker: docker, canStartDocker: canStartDocker,
            isRunning: status.isRunning,
            canStart: !status.isBusy && project.supportsLocalStack && status.readiness?.canStart != false,
            canRestart: status.readiness?.canStart != false,
            startConfirmation: question
        )
        let site = status.isRunning ? (status.siteURL ?? project.localSiteURL) : nil
        let note = status.isRunning && hero.note != nil && !blocked ? hero.note : hero.text
        return DeckProjectCardModel(
            title: "Arc · \(project.title)",
            mark: .arc,
            timestamp: DeckCardTime.checked(status.checkedAt),
            header: header(card: card, isShowingLogs: isShowingLogs, phoneURL: phoneURL),
            hero: hero,
            meta: Meta(
                branch: status.branch,
                repositoryURL: status.repositoryURL,
                card: card,
                folder: project.folder,
                // While a command runs, the line it just printed takes the meta slot: it is the
                // only thing on the card that is changing.
                leading: status.isBusy ? (status.progressLine ?? project.organization) : project.organization,
                trailing: status.isBusy ? nil : status.engineVersion
            ),
            tools: project.adminLinks.map { chip($0.label, url: $0.url, isSite: false, card: card, isRunning: status.isRunning) },
            environments: environments,
            actions: lifecycle + [
                DeckActionModel(L("card.action.terminal"), glyph: .terminal, isEnabled: project.supportsLocalStack, command: .openTerminal(card)),
                DeckActionModel(L("card.action.folder"), glyph: .folder, isEnabled: project.supportsLocalStack, command: .revealFolder(card)),
            ],
            collapsed: DeckCollapsedModel(
                mark: .arc,
                title: project.title,
                note: note,
                tone: hero.tone,
                actions: collapsedActions(lifecycle, card: card, site: site),
                help: status.detail ?? hero.text
            ),
            isCollapsed: isCollapsed
        )
    }

    public static func ddev(
        _ project: DDEVProject,
        status: DDEVStatus,
        docker: DockerStatus,
        canStartDocker: Bool,
        isShowingLogs: Bool,
        isCollapsed: Bool,
        phoneURL: URL?,
        startedBy: String? = nil
    ) -> DeckProjectCardModel {
        let card = project.cardID
        let blocked = DockerGate.blocks(docker, isRunning: status.isRunning, requiresDocker: true)
        let hero: Hero
        if blocked {
            // Docker first: without it `ddev list` cannot answer either, and "unknown to ddev"
            // would be a true sentence that helps nobody.
            hero = Hero(tone: DockerGate.tone(docker), text: DockerGate.text(docker), note: DockerGate.note(docker), help: status.detail ?? DockerGate.text(docker))
        } else if ddevUnavailable(status) {
            hero = Hero(tone: .alert, text: L("ddev.silent.title"), note: L("ddev.silent.detail"), help: L("ddev.silent.detail"))
        } else {
            let tone: DeckTone
            let text: String
            switch status.state {
            // A broken file sync is a running project you cannot trust, so it reads as attention
            // rather than as fine.
            case .running: tone = status.mutagenWarning == nil ? .good : .attention; text = L("card.state.running")
            // Paused is DDEV's own state, not a shade of stopped: the containers are still there
            // and a start is quick.
            case .paused: tone = .attention; text = L("card.state.paused")
            case .working: tone = .attention; text = status.detail ?? L("card.state.working")
            case .stopped: tone = .neutral; text = L("card.state.stopped")
            case .unknown: tone = .alert; text = L("card.state.unknown")
            }
            let note: String?
            switch status.state {
            // "unknown" alone says nothing useful; what makes it useful is who does not know.
            case .unknown: note = L("card.ddev.notListed")
            case .running: note = status.mutagenWarning ?? startedBy.map { L("card.project.startedBy", $0) }
            // The detail is already the state text.
            case .working: note = nil
            // Why it is down, when DDEV or a failed command said: a start that failed is the
            // moment the card is most worth reading, and the reason used to reach only the
            // tooltip.
            case .stopped, .paused: note = status.detail
            }
            hero = Hero(tone: tone, text: text, note: note, help: Self.help(status.detail ?? text, startedBy: status.isRunning ? startedBy : nil))
        }

        let lifecycle = lifecycle(
            card: card, blocked: blocked, docker: docker, canStartDocker: canStartDocker,
            isRunning: status.isRunning, canStart: !status.isBusy && !ddevUnavailable(status), canRestart: !ddevUnavailable(status)
        )
        let note = status.isRunning ? (status.mutagenWarning ?? hero.text) : hero.text
        let folder = project.folderURL?.lastPathComponent
        let leading = [status.frameworkLabel, folder].compactMap { $0 }
        return DeckProjectCardModel(
            title: "DDEV · \(project.displayTitle)",
            mark: .ddev,
            timestamp: DeckCardTime.checked(status.checkedAt),
            header: header(card: card, isShowingLogs: isShowingLogs, phoneURL: phoneURL),
            hero: hero,
            meta: Meta(
                branch: status.branch,
                repositoryURL: status.repositoryURL,
                card: card,
                folder: project.folder,
                leading: leading.isEmpty ? nil : leading.joined(separator: " · "),
                trailing: status.versionsLine
            ),
            tools: project.toolLinks(status: status).map { chip($0.label, url: $0.url, isSite: false, card: card, isRunning: status.isRunning) },
            environments: project.environmentLinks(status: status).map {
                chip($0.label, url: $0.url, isSite: $0.kind == .site, card: card, isRunning: status.isRunning)
            },
            actions: lifecycle + [
                DeckActionModel(L("card.action.terminal"), glyph: .terminal, isEnabled: project.folderURL != nil, command: .openTerminal(card)),
                DeckActionModel(L("card.action.folder"), glyph: .folder, isEnabled: project.folderURL != nil, command: .revealFolder(card)),
            ],
            collapsed: DeckCollapsedModel(
                mark: .ddev,
                title: project.displayTitle,
                note: note,
                tone: hero.tone,
                actions: collapsedActions(lifecycle, card: card, site: status.isRunning ? status.entry?.primaryURL : nil),
                help: status.detail ?? hero.text
            ),
            isCollapsed: isCollapsed
        )
    }

    /// `ddev list` did not answer at all, which is a different card from a project it does not
    /// know: nothing can be started until ddev is back, on either platform.
    private static func ddevUnavailable(_ status: DDEVStatus) -> Bool {
        status.listUnavailable
    }

    public static func local(
        _ project: LocalProject,
        status: LocalProjectStatus,
        docker: DockerStatus,
        canStartDocker: Bool,
        isShowingLogs: Bool,
        isCollapsed: Bool,
        phoneURL: URL?,
        startedBy: String? = nil
    ) -> DeckProjectCardModel {
        let card = project.cardID
        let blocked = DockerGate.blocks(docker, isRunning: status.isRunning, requiresDocker: project.requiresDocker)
        // Why Stop cannot reach it, in the slot the pid takes when it can. The runtime decides
        // which; the card only words it.
        let stopNote: String?
        let stopHelp: String?
        switch status.stopBlock {
        case .startedElsewhere:
            stopNote = L("card.project.startedElsewhere")
            stopHelp = L("card.project.startedElsewhere.help")
        case .noStopCommand:
            stopNote = L("card.project.noStopCommand")
            stopHelp = L("card.project.noStopCommand.help")
        case nil:
            stopNote = nil
            stopHelp = nil
        }

        let tone: DeckTone
        let text: String
        if blocked {
            tone = DockerGate.tone(docker)
            text = DockerGate.text(docker)
        } else {
            switch status.state {
            case .running: tone = .good; text = L("card.state.running")
            case .starting: tone = .attention; text = L("card.state.starting")
            case .working: tone = .attention; text = status.detail ?? L("card.state.working")
            case .stopped: tone = .neutral; text = L("card.state.stopped")
            case .unavailable: tone = .neutral; text = L("card.state.notConfigured")
            }
        }
        let help = stopHelp ?? status.detail ?? text
        // Behind the Docker gate the note is the gate's; otherwise why Stop cannot reach it, or
        // the pid.
        let heroNote = blocked ? DockerGate.note(docker) : (stopNote ?? startedBy.flatMap { status.isRunning ? L("card.project.startedBy", $0) : nil } ?? status.pid.map { "pid \($0)" })
        let hero = Hero(tone: tone, text: text, note: heroNote, help: Self.help(help, startedBy: status.isRunning ? startedBy : nil))

        let lifecycle: [DeckActionModel]
        if !blocked, status.isRunning || status.state == .starting {
            // Stop stays pressable when it cannot reach the project: pressing it is how the
            // person finds out, and the menu then says why. Restart does not, because it would
            // start a second copy onto a port that is taken.
            lifecycle = [
                DeckActionModel(L("card.action.stop"), glyph: .stop, tone: .alert, isProminent: true, command: .project(card, .stop)),
                DeckActionModel(L("card.action.restart"), glyph: .restart, isEnabled: status.stopBlock == nil, command: .project(card, .restart)),
            ]
        } else {
            lifecycle = Self.lifecycle(
                card: card, blocked: blocked, docker: docker, canStartDocker: canStartDocker,
                isRunning: false, canStart: !status.isBusy && project.supportsCommands, canRestart: true
            )
        }

        let note: String
        if let stopNote {
            note = stopNote
        } else if status.isRunning, let pid = status.pid {
            note = "pid \(pid)"
        } else {
            note = text
        }
        let subtitle = project.subtitle.trimmingCharacters(in: .whitespaces)
        let leading = [subtitle.isEmpty ? nil : subtitle, project.folderURL?.lastPathComponent].compactMap { $0 }
        return DeckProjectCardModel(
            title: "\(L("project.section.project")) · \(project.displayTitle)",
            // What this project is built on. Nothing declares it, so it is read from the command,
            // which is the one thing every plain project definitely has.
            mark: brand(of: project.kind),
            timestamp: DeckCardTime.checked(status.checkedAt),
            header: header(card: card, isShowingLogs: isShowingLogs, phoneURL: phoneURL),
            hero: hero,
            meta: Meta(
                branch: status.branch,
                repositoryURL: status.repositoryURL,
                card: card,
                folder: project.folder,
                leading: leading.isEmpty ? nil : leading.joined(separator: " · "),
                trailing: project.startCommandSummary
            ),
            tools: project.toolLinks().map { chip($0.label, url: $0.url, isSite: false, card: card, isRunning: status.isRunning) },
            environments: project.environmentLinks().map {
                chip($0.label, url: $0.url, isSite: $0.kind == .site, card: card, isRunning: status.isRunning)
            },
            // The same four as the Arc and DDEV cards, in the plain card's own order.
            actions: lifecycle + [
                // Terminal, then folder, the same order on every kind of project card.
                DeckActionModel(L("card.action.terminal"), glyph: .terminal, command: .openTerminal(card)),
                DeckActionModel(L("card.action.folder"), glyph: .folder, isEnabled: project.folderURL != nil, command: .revealFolder(card)),
            ],
            collapsed: DeckCollapsedModel(
                mark: brand(of: project.kind),
                title: project.displayTitle,
                note: note,
                tone: tone,
                actions: collapsedActions(lifecycle, card: card, site: status.isRunning ? (project.siteURL ?? project.healthCheckURL) : nil),
                help: help
            ),
            isCollapsed: isCollapsed
        )
    }

    // MARK: Shared by all three

    /// Start or Stop, then Restart. While Docker is in the way, the action that fixes it takes
    /// Start's place, or a disabled Start on a machine with no runtime app to open.
    private static func lifecycle(
        card: CardID,
        blocked: Bool,
        docker: DockerStatus,
        canStartDocker: Bool,
        isRunning: Bool,
        canStart: Bool,
        canRestart: Bool,
        startConfirmation: DeckConfirmation? = nil
    ) -> [DeckActionModel] {
        let restartOff = DeckActionModel(L("card.action.restart"), glyph: .restart, isEnabled: false, command: .project(card, .restart))
        if blocked {
            let start = canStartDocker
                ? DeckActionModel(
                    L("attention.docker.start"), glyph: .docker, tone: .attention,
                    isEnabled: docker.state == .notRunning, isProminent: true, command: .startDocker
                )
                : DeckActionModel(L("card.action.start"), glyph: .start, tone: .good, isEnabled: false, command: .project(card, .start))
            return [start, restartOff]
        }
        if isRunning {
            return [
                DeckActionModel(L("card.action.stop"), glyph: .stop, tone: .alert, isProminent: true, command: .project(card, .stop)),
                DeckActionModel(L("card.action.restart"), glyph: .restart, isEnabled: canRestart, command: .project(card, .restart), confirmation: startConfirmation),
            ]
        }
        return [
            DeckActionModel(L("card.action.start"), glyph: .start, tone: .good, isEnabled: canStart, isProminent: true, command: .project(card, .start), confirmation: startConfirmation),
            restartOff,
        ]
    }

    /// What a folded card keeps: the action the state implies, a restart when it can be done,
    /// a terminal, and the site while there is one to open.
    ///
    /// Folder is left out although the full card has it, because a terminal opens in the folder
    /// anyway and a row this size cannot spend 24 points saying the same thing twice. A disabled
    /// control is left out too, apart from the lifecycle one: four squares of which two cannot be
    /// pressed reads as a broken row rather than an idle project.
    private static func collapsedActions(_ lifecycle: [DeckActionModel], card: CardID, site: URL?) -> [DeckActionModel] {
        var actions: [DeckActionModel] = []
        if let first = lifecycle.first { actions.append(first) }
        actions += lifecycle.dropFirst().filter(\.isEnabled)
        actions.append(DeckActionModel(L("card.action.terminal"), glyph: .terminal, command: .openTerminal(card)))
        if let site {
            actions.append(DeckActionModel(L("card.action.openSite"), glyph: .openExternal, command: .openProjectLink(card, site)))
        }
        return actions
    }

    private static func header(card: CardID, isShowingLogs: Bool, phoneURL: URL?) -> Header {
        Header(
            logIsOn: isShowingLogs,
            logHelp: isShowingLogs ? L("card.log.window.close") : L("card.log.window.open"),
            log: .toggleLogs(card),
            phoneURL: phoneURL,
            phoneHelp: L("card.phone.help"),
            phoneTitle: L("card.phone.title"),
            phoneNote: L("card.phone.note")
        )
    }

    /// A link, sorted by where it points rather than by what it is called: the local site is not
    /// the only local thing on a card, and a link into a stopped stack lands on a connection
    /// error that reads as a broken app rather than a stopped one. A deployed environment is
    /// reachable whether or not anything runs here.
    private static func chip(_ label: String, url: URL, isSite: Bool, card: CardID, isRunning: Bool) -> Chip {
        let isLocal = isSite && LocalAddress.isServedHere(url)
        let isDimmed = isLocal && !isRunning
        let kind: Chip.Kind
        if !isSite {
            kind = .tool
        } else if isLocal {
            kind = .local
        } else {
            kind = label.lowercased().contains("prod") ? .production : .environment
        }
        return Chip(
            label: label,
            kind: kind,
            isDimmed: isDimmed,
            help: isDimmed ? L("card.chip.notRunning", url.absoluteString) : url.absoluteString,
            command: isDimmed ? nil : .openProjectLink(card, url)
        )
    }

    /// The hero's tooltip, with who started the project when it was an agent.
    static func help(_ text: String, startedBy: String?) -> String {
        guard let startedBy else { return text }
        return "\(text) · \(L("card.project.startedBy", startedBy))"
    }

    public static func brand(of kind: ProjectKind) -> DeckMark {
        switch kind {
        case .node: return .node
        case .next: return .next
        case .nest: return .nest
        case .bun: return .bun
        case .docker: return .docker
        case .make: return .make
        case .other: return .project
        }
    }
}

/// The Docker precondition, said the same way on every card that has one.
///
/// A card whose project cannot start without Docker has to answer a different question when
/// Docker is down: not "is this project running", obviously not, but "why is the button there
/// at all". Pressing Start with no daemon produces a wall of shell output the card has nowhere to
/// put, so the card says what is wrong instead and offers the thing that fixes it.
public enum DockerGate {
    /// Whether the card should talk about Docker rather than about the project. A running
    /// project is never gated: something is clearly serving it, and no amount of probing beats
    /// that.
    public static func blocks(_ status: DockerStatus, isRunning: Bool, requiresDocker: Bool) -> Bool {
        guard requiresDocker, !isRunning else { return false }
        return !status.allowsStart
    }

    /// What goes on the state line: short, since the line is 22 points tall and a sentence on
    /// it ends in an ellipsis. The rest of the sentence is the note.
    public static func text(_ status: DockerStatus) -> String {
        switch status.state {
        case .notInstalled: return L("card.docker.notInstalled")
        case .starting: return L("card.docker.starting")
        default: return L("card.docker.off")
        }
    }

    /// The rest of the sentence: what the state means for the card.
    public static func note(_ status: DockerStatus) -> String? {
        switch status.state {
        case .notInstalled: return L("card.docker.notInstalled.note")
        case .starting: return nil
        default: return L("card.docker.off.note")
        }
    }

    public static func tone(_ status: DockerStatus) -> DeckTone {
        status.state == .notInstalled ? .alert : .attention
    }
}
