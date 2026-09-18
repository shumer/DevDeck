import AppKit
import ArcKit
import DDEVKit
import DevDeckCore
import DevDeckUI
import ProjectKit

/// The tag colour of an environment link, the same family the card's chips use.
@MainActor
private func tint(for label: String) -> NSColor {
    let name = label.lowercased()
    if name.contains("prod") { return .systemOrange }
    if name.contains("uat") || name.contains("stag") { return .systemPurple }
    if name.contains("test") || name.contains("dev") { return .systemIndigo }
    return .systemTeal
}

// MARK: - Plain project

/// A plain project, in the order it is filled in: where it is and how it starts, how the app
/// knows it is up, the links on its card, and under Advanced what is rarely touched.
@MainActor
final class LocalProjectForm: FlippedContainer, NSTextFieldDelegate {
    private(set) var project: LocalProject

    private let folderField: NSTextField
    private let startField: NSTextField
    private let holdsSwitch: NSSwitch
    private let healthField: NSTextField
    private let siteField: NSTextField
    private let nameField: NSTextField
    private let captionField: NSTextField
    private let stopField: NSTextField
    private let dockerSwitch: NSSwitch
    private let browser: BrowserPicker
    private var enabledSwitch: NSSwitch?
    private var linkChecks: [NSButton] = []
    private var linkFields: [NSTextField] = []
    private var openButtons: [NSButton] = []
    private let detectButton = SettingsForm.button(L("button.detect"), target: nil, action: nil)
    private let testButton = SettingsForm.button(L("button.test"), target: nil, action: nil)
    let health: StatusLine

    var onChange: ((LocalProjectForm) -> Void)?
    var onChooseFolder: ((LocalProjectForm) -> Void)?
    var onDetect: ((LocalProjectForm) -> Void)?
    var onCheckHealth: ((LocalProjectForm) -> Void)?
    var onOpenLink: ((LocalProjectForm, Int) -> Void)?
    var onTestLink: ((LocalProjectForm) -> Void)?
    var onToggleAdvanced: (() -> Void)?

    init(project: LocalProject, health: StatusLine, isAdvancedOpen: Bool, width: CGFloat) {
        self.project = project
        self.health = health
        folderField = SettingsForm.field(project.folder ?? "", placeholder: "~/Projects/…", code: true)
        startField = SettingsForm.field(project.startCommand, placeholder: L("project.start.placeholder"), code: true)
        holdsSwitch = SettingsForm.makeSwitch(isOn: project.holdsProcess, title: L("project.longRunning"), target: nil, action: nil)
        healthField = SettingsForm.field(project.healthURL, placeholder: "http://localhost:3000", code: true)
        siteField = SettingsForm.field(project.localSiteURL, placeholder: L("project.openURL.placeholder"), code: true)
        nameField = SettingsForm.field(project.title, placeholder: project.folderURL?.lastPathComponent ?? L("project.name.placeholder"))
        captionField = SettingsForm.field(project.subtitle, placeholder: L("project.caption.placeholder"))
        stopField = SettingsForm.field(project.stopCommand, placeholder: L("project.stop.placeholder"), code: true)
        dockerSwitch = SettingsForm.makeSwitch(isOn: project.requiresDocker, title: L("project.needsDocker"), target: nil, action: nil)
        browser = BrowserPicker(choice: project.browser)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        for control in [holdsSwitch, dockerSwitch] {
            control.target = self
            control.action = #selector(changed)
        }
        for field in [folderField, startField, healthField, siteField, nameField, captionField, stopField] {
            field.delegate = self
        }
        browser.onChange = { [weak self] in self?.changed() }

        let form = SettingsForm(in: self)
        enabledSwitch = form.pageHeader(
            icon: SettingsIcons.mark(Self.glyph(for: project), size: 32),
            title: project.displayTitle,
            subtitle: project.folder,
            toggleTitle: L("account.showOnDeck"),
            isOn: project.isEnabled,
            target: self,
            action: #selector(changed)
        )

        form.section(L("project.section.project"))
        form.beginGroup()
        form.fieldRow(L("account.name"), [(nameField, nil)])
        form.fieldRow(L("project.folder"), [(folderField, nil)], trailing: SettingsForm.button(L("button.choose"), target: self, action: #selector(chooseFolder)))
        form.endGroup()

        form.section(L("project.section.start"))
        form.beginGroup()
        detectButton.target = self
        detectButton.action = #selector(detect)
        form.fieldRow(L("project.startCommand"), [(startField, nil)], trailing: detectButton)
        form.fieldRow(L("project.stopCommand"), [(stopField, nil)])
        form.settingRow(
            L("project.longRunning"),
            subtitle: L("project.longRunning.detail"),
            control: holdsSwitch
        )
        // The switch that decides whether Start can work at all belongs beside the command, not
        // behind a fold.
        form.settingRow(L("project.needsDocker"), subtitle: L("project.needsDocker.detail"), control: dockerSwitch)
        form.endGroup()

        form.section(L("project.section.health"), help: L("project.health.help"))
        form.beginGroup()
        form.fieldRow(L("project.checkURL"), [(healthField, nil)])
        form.fieldRow(L("project.openURL"), [(siteField, nil)])
        form.statusRow(health, button: SettingsForm.button(L("button.checkNow"), target: self, action: #selector(checkHealth)))
        form.endGroup()

        if !project.links.isEmpty {
            form.section(L("project.section.links"))
            form.beginGroup()
            let chipWidth = SettingsForm.chipWidth(for: project.links.map(\.label))
            for (index, link) in project.links.enumerated() {
                let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(changed))
                check.state = link.isEnabled ? .on : .off
                let field = SettingsForm.field(link.urlTemplate, placeholder: "https://…", code: true)
                field.delegate = self
                let open = SettingsForm.openButton(target: self, action: #selector(openLink(_:)))
                open.tag = index
                open.isHidden = link.urlTemplate.isEmpty
                linkChecks.append(check)
                linkFields.append(field)
                openButtons.append(open)
                form.linkRow(toggle: check, tag: link.label, tint: tint(for: link.label), field: field, open: open, chipWidth: chipWidth)
            }
            form.endGroup()
        }

        form.disclosure(L("account.advanced"), summary: L("project.advanced.summary.local"), isOpen: isAdvancedOpen, target: self, action: #selector(toggleAdvanced))
        if isAdvancedOpen {
            form.beginGroup()
            form.fieldRow(L("project.caption"), [(captionField, nil)])
            testButton.target = self
            testButton.action = #selector(testLink)
            form.fieldRow(L("account.openLinksIn"), [(browser.browserPopUp, 150), (browser.profilePopUp, nil)], trailing: testButton)
            form.endGroup()
        }

        frame.size.height = form.usedHeight
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    /// The mark its card wears.
    static func glyph(for project: LocalProject) -> CardGlyph {
        switch project.kind {
        case .node: return .node
        case .next: return .next
        case .nest: return .nest
        case .bun: return .bun
        case .docker: return .docker
        case .make: return .make
        case .other: return .project
        }
    }

    var editedProject: LocalProject {
        var edited = project
        edited.title = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.subtitle = captionField.stringValue.trimmingCharacters(in: .whitespaces)
        let folder = folderField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.folder = folder.isEmpty ? nil : folder
        edited.isEnabled = enabledSwitch?.state != .off
        edited.startCommand = startField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.stopCommand = stopField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.holdsProcess = holdsSwitch.state == .on
        edited.requiresDocker = dockerSwitch.state == .on
        edited.healthURL = healthField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.localSiteURL = siteField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.browser = browser.choice
        edited.links = zip(project.links.indices, project.links).map { index, link in
            var updated = link
            if index < linkChecks.count { updated.isEnabled = linkChecks[index].state == .on }
            if index < linkFields.count {
                // Taken as typed, including empty: clearing a field has to mean something.
                updated.urlTemplate = linkFields[index].stringValue.trimmingCharacters(in: .whitespaces)
            }
            return updated
        }
        return edited
    }

    func apply(_ project: LocalProject) {
        self.project = project
    }

    func setFolder(_ path: String) {
        folderField.stringValue = path
        onChange?(self)
    }

    /// Fills the command in from what the folder looks like. Only from the Detect button, so a
    /// guess never overwrites something typed.
    func applySuggestion(_ suggestion: ProjectSuggestion) {
        startField.stringValue = suggestion.startCommand
        stopField.stringValue = suggestion.stopCommand
        holdsSwitch.state = suggestion.holdsProcess ? .on : .off
        dockerSwitch.state = suggestion.requiresDocker ? .on : .off
        if captionField.stringValue.isEmpty { captionField.stringValue = suggestion.subtitle }
        if healthField.stringValue.isEmpty { healthField.stringValue = suggestion.healthURL }
        onChange?(self)
    }

    func setDetectNote(_ text: String, isError: Bool) {
        ButtonAnswer.show(text, isError: isError, at: detectButton)
    }

    func setLinkNote(_ text: String, isError: Bool) {
        guard !text.isEmpty else { return }
        ButtonAnswer.show(text, isError: isError, at: testButton.window == nil ? detectButton : testButton)
    }

    func linkURL(at index: Int) -> URL? {
        guard linkFields.indices.contains(index) else { return nil }
        return URL(string: linkFields[index].stringValue.trimmingCharacters(in: .whitespaces))
    }

    @objc private func changed() { onChange?(self) }
    @objc private func chooseFolder() { onChooseFolder?(self) }
    @objc private func detect() { onDetect?(self) }
    @objc private func checkHealth() { onCheckHealth?(self) }
    @objc private func testLink() { onTestLink?(self) }
    @objc private func toggleAdvanced() { onToggleAdvanced?() }
    @objc private func openLink(_ sender: NSButton) { onOpenLink?(self, sender.tag) }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let index = linkFields.firstIndex(of: field) else { return }
        openButtons[index].isHidden = field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        onChange?(self)
    }
}

// MARK: - Arc

/// An Arc XP project: its local stack first, since that is what the card starts and stops, then
/// its organisation, its links, and under Advanced what is rarely touched.
@MainActor
final class ArcProjectForm: FlippedContainer, NSTextFieldDelegate {
    private(set) var project: ArcProject

    private let folderField: NSTextField
    private let startField: NSTextField
    private let localURLField: NSTextField
    private let healthField: NSTextField
    private let organizationField: NSTextField
    private let siteField: NSTextField
    private let nameField: NSTextField
    private let stopField: NSTextField
    private let browser: BrowserPicker
    private var enabledSwitch: NSSwitch?
    private var linkChecks: [NSButton] = []
    private var linkFields: [NSTextField] = []
    /// One per link, nil where the name is not editable.
    private var labelFields: [NSTextField?] = []
    private let testButton = SettingsForm.button(L("button.test"), target: nil, action: nil)
    let stack: StatusLine

    var onChange: ((ArcProjectForm) -> Void)?
    var onChooseFolder: ((ArcProjectForm) -> Void)?
    var onCheckStack: ((ArcProjectForm) -> Void)?
    var onTestLink: ((ArcProjectForm) -> Void)?
    var onToggleAdvanced: (() -> Void)?
    /// A link added or removed changes the shape of the form, so it is built again.
    var onStructureChange: ((ArcProjectForm, ArcProject) -> Void)?

    init(project: ArcProject, stack: StatusLine, isAdvancedOpen: Bool, width: CGFloat) {
        self.project = project
        self.stack = stack
        folderField = SettingsForm.field(project.folder ?? "", placeholder: "~/Projects/…", code: true)
        startField = SettingsForm.field(project.startCommand, placeholder: "npx fusion daemon", code: true)
        let envURL = EnvFile.localURL(in: project.folderURL)
        localURLField = SettingsForm.field(project.localURL, placeholder: L("project.arc.localURL.placeholder", "\(envURL)"), code: true)
        healthField = SettingsForm.field(project.healthPath, placeholder: "/release", code: true)
        organizationField = SettingsForm.field(project.organization, placeholder: "sandbox.acme")
        siteField = SettingsForm.field(project.site ?? "", placeholder: L("project.arc.site.placeholder"))
        nameField = SettingsForm.field(project.title, placeholder: L("project.name.placeholder"))
        stopField = SettingsForm.field(project.stopCommand, placeholder: "npx fusion stop", code: true)
        browser = BrowserPicker(choice: project.browser)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        for field in [folderField, startField, localURLField, healthField, organizationField, siteField, nameField, stopField] {
            field.delegate = self
        }
        browser.onChange = { [weak self] in self?.changed() }

        let form = SettingsForm(in: self)
        enabledSwitch = form.pageHeader(
            icon: SettingsIcons.mark(.arc, size: 32),
            title: project.title,
            subtitle: project.organization.isEmpty ? "Arc XP" : "Arc XP · \(project.organization)",
            toggleTitle: L("account.showOnDeck"),
            isOn: project.isEnabled,
            target: self,
            action: #selector(changed)
        )

        form.section(L("project.section.project"))
        form.beginGroup()
        form.fieldRow(L("account.name"), [(nameField, nil)])
        form.fieldRow(L("project.folder"), [(folderField, nil)], trailing: SettingsForm.button(L("button.choose"), target: self, action: #selector(chooseFolder)))
        form.endGroup()

        form.section(L("project.section.stack"))
        form.beginGroup()
        form.fieldRow(L("project.startCommand"), [(startField, nil)])
        form.fieldRow(L("project.stopCommand"), [(stopField, nil)])
        // The same two words as every other project's form: what is asked, and where the site is.
        form.fieldRow(L("project.checkURL"), [(healthField, nil)])
        form.fieldRow(L("project.openURL"), [(localURLField, nil)])
        form.statusRow(stack, button: SettingsForm.button(L("button.checkNow"), target: self, action: #selector(checkStack)))
        form.endGroup()

        form.section("Arc XP")
        form.beginGroup()
        form.fieldRow(L("project.arc.organisation"), [(organizationField, nil)])
        form.fieldRow(L("project.arc.site"), [(siteField, nil)])
        form.endGroup()
        form.footnote(L("project.arc.footnote"))

        form.section(L("project.section.links"), help: L("project.arc.links.help"))
        form.beginGroup()
        let shipped = Set(ArcLink.defaults().map(\.label))
        let chipWidth = SettingsForm.chipWidth(for: project.links.map(\.label))
        for (index, link) in project.links.enumerated() {
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(changed))
            check.state = link.isEnabled ? .on : .off
            check.setAccessibilityLabel(link.label)
            let template = SettingsForm.field(link.urlTemplate, placeholder: "https://…", code: true)
            template.delegate = self
            linkChecks.append(check)
            linkFields.append(template)

            // A shipped link keeps its name: renaming one would orphan it at the next migration,
            // which matches links by label. It gets the same chipped row as every other project's
            // links, so one thing looks like one thing across the three forms.
            guard !shipped.contains(link.label) else {
                labelFields.append(nil)
                form.linkRow(
                    toggle: check,
                    tag: link.label,
                    tint: tint(for: link.label),
                    field: template,
                    open: nil,
                    chipWidth: chipWidth
                )
                continue
            }
            let name = SettingsForm.field(link.label, placeholder: L("account.name"))
            name.delegate = self
            labelFields.append(name)
            let remove = NSButton(image: NSImage(systemSymbolName: "minus.circle", accessibilityDescription: L("project.link.remove")) ?? NSImage(), target: self, action: #selector(removeLink(_:)))
            remove.isBordered = false
            remove.tag = index
            form.fieldRow("", [(name, 96), (check, 18), (template, nil)], trailing: remove)
        }
        form.endGroup()
        form.textButton(L("project.arc.addLink"), target: self, action: #selector(addLink))

        form.disclosure(L("account.advanced"), summary: L("project.advanced.summary.browser"), isOpen: isAdvancedOpen, target: self, action: #selector(toggleAdvanced))
        if isAdvancedOpen {
            form.beginGroup()
            testButton.target = self
            testButton.action = #selector(testLink)
            form.fieldRow(L("account.openLinksIn"), [(browser.browserPopUp, 150), (browser.profilePopUp, nil)], trailing: testButton)
            form.endGroup()
        }

        frame.size.height = form.usedHeight
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    var editedProject: ArcProject {
        var edited = project
        let title = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.title = title.isEmpty ? project.title : title
        edited.organization = organizationField.stringValue.trimmingCharacters(in: .whitespaces)
        let site = siteField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.site = site.isEmpty ? nil : site
        edited.isEnabled = enabledSwitch?.state != .off
        edited.browser = browser.choice
        edited.links = zip(project.links.indices, project.links).map { index, link in
            var updated = link
            if index < linkChecks.count { updated.isEnabled = linkChecks[index].state == .on }
            if index < linkFields.count {
                updated.urlTemplate = linkFields[index].stringValue.trimmingCharacters(in: .whitespaces)
            }
            if index < labelFields.count, let field = labelFields[index] {
                let name = field.stringValue.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { updated.label = name }
            }
            return updated
        }
        let folder = folderField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.folder = folder.isEmpty ? nil : folder
        edited.startCommand = startField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.stopCommand = stopField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.localURL = localURLField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.healthPath = healthField.stringValue.trimmingCharacters(in: .whitespaces)
        return edited
    }

    func apply(_ project: ArcProject) {
        self.project = project
    }

    func setFolder(_ path: String) {
        folderField.stringValue = path
        onChange?(self)
    }

    func setLinkNote(_ text: String, isError: Bool) {
        guard !text.isEmpty else { return }
        ButtonAnswer.show(text, isError: isError, at: testButton)
    }

    @objc private func changed() { onChange?(self) }
    @objc private func chooseFolder() { onChooseFolder?(self) }
    @objc private func checkStack() { onCheckStack?(self) }
    @objc private func testLink() { onTestLink?(self) }
    @objc private func toggleAdvanced() { onToggleAdvanced?() }

    /// Adds a link of your own. A project with a fourth environment has somewhere to put it.
    @objc private func addLink() {
        var edited = editedProject
        let existing = Set(edited.links.map(\.label))
        var name = L("project.link.new")
        var index = 2
        while existing.contains(name) {
            name = L("project.link.new.numbered", index)
            index += 1
        }
        edited.links.append(ArcLink(label: name, urlTemplate: "", isEnabled: true, kind: .admin))
        onStructureChange?(self, edited)
    }

    @objc private func removeLink(_ sender: NSButton) {
        var edited = editedProject
        guard edited.links.indices.contains(sender.tag) else { return }
        edited.links.remove(at: sender.tag)
        onStructureChange?(self, edited)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        onChange?(self)
    }
}

// MARK: - DDEV

/// A DDEV project. Short on purpose: DDEV knows the name, the type, the URLs and the state, so
/// what is left to ask is the folder, what to call it, which tools and links the card offers,
/// and where they open.
@MainActor
final class DDEVProjectForm: FlippedContainer, NSTextFieldDelegate {
    private(set) var project: DDEVProject

    private let folderField: NSTextField
    private let nameField: NSTextField
    private let mailpitSwitch: NSSwitch
    private let xhguiSwitch: NSSwitch
    private let browser: BrowserPicker
    private var enabledSwitch: NSSwitch?
    private var linkChecks: [NSButton] = []
    private var linkFields: [NSTextField] = []
    private let chooseButton = SettingsForm.button(L("button.choose"), target: nil, action: nil)
    private let testButton = SettingsForm.button(L("button.test"), target: nil, action: nil)

    var onChange: ((DDEVProjectForm) -> Void)?
    var onChooseFolder: ((DDEVProjectForm) -> Void)?
    var onTestLink: ((DDEVProjectForm) -> Void)?

    init(project: DDEVProject, width: CGFloat) {
        self.project = project
        folderField = SettingsForm.field(project.folder ?? "", placeholder: "~/Projects/…", code: true)
        nameField = SettingsForm.field(project.title, placeholder: project.name)
        mailpitSwitch = SettingsForm.makeSwitch(isOn: project.showsMailpit, title: "Mailpit", target: nil, action: nil)
        xhguiSwitch = SettingsForm.makeSwitch(isOn: project.showsXhgui, title: "xhgui", target: nil, action: nil)
        browser = BrowserPicker(choice: project.browser)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        for control in [mailpitSwitch, xhguiSwitch] {
            control.target = self
            control.action = #selector(changed)
        }
        folderField.delegate = self
        nameField.delegate = self
        browser.onChange = { [weak self] in self?.changed() }

        let form = SettingsForm(in: self)
        enabledSwitch = form.pageHeader(
            icon: SettingsIcons.mark(.ddev, size: 32),
            title: project.displayTitle,
            subtitle: "DDEV · \(project.name)",
            toggleTitle: L("account.showOnDeck"),
            isOn: project.isEnabled,
            target: self,
            action: #selector(changed)
        )

        form.section(L("project.section.project"))
        form.beginGroup()
        chooseButton.target = self
        chooseButton.action = #selector(chooseFolder)
        form.fieldRow(L("account.name"), [(nameField, nil)])
        form.fieldRow(L("project.folder"), [(folderField, nil)], trailing: chooseButton)
        form.endGroup()

        form.section(L("project.ddev.tools"))
        form.beginGroup()
        form.settingRow("Mailpit", control: mailpitSwitch)
        form.settingRow("xhgui", control: xhguiSwitch)
        form.endGroup()

        if !project.customLinks.isEmpty {
            form.section(L("project.section.links"))
            form.beginGroup()
            let chipWidth = SettingsForm.chipWidth(for: project.customLinks.map(\.label))
            for link in project.customLinks {
                let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(changed))
                check.state = link.isEnabled ? .on : .off
                let field = SettingsForm.field(link.urlTemplate, placeholder: "https://…", code: true)
                field.delegate = self
                linkChecks.append(check)
                linkFields.append(field)
                form.linkRow(toggle: check, tag: link.label, tint: tint(for: link.label), field: field, open: nil, chipWidth: chipWidth)
            }
            form.endGroup()
        }

        // One row called the same thing as in every other form, rather than a section whose
        // title and whose row said the same word twice.
        form.beginGroup()
        testButton.target = self
        testButton.action = #selector(testLink)
        form.fieldRow(L("account.openLinksIn"), [(browser.browserPopUp, 150), (browser.profilePopUp, nil)], trailing: testButton)
        form.endGroup()

        frame.size.height = form.usedHeight
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    var editedProject: DDEVProject {
        var edited = project
        edited.title = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let folder = folderField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.folder = folder.isEmpty ? nil : folder
        edited.isEnabled = enabledSwitch?.state != .off
        edited.showsMailpit = mailpitSwitch.state == .on
        edited.showsXhgui = xhguiSwitch.state == .on
        edited.browser = browser.choice
        edited.customLinks = zip(project.customLinks.indices, project.customLinks).map { index, link in
            var updated = link
            if index < linkChecks.count { updated.isEnabled = linkChecks[index].state == .on }
            if index < linkFields.count {
                updated.urlTemplate = linkFields[index].stringValue.trimmingCharacters(in: .whitespaces)
            }
            return updated
        }
        return edited
    }

    func apply(_ project: DDEVProject) {
        self.project = project
    }

    func setFolder(_ path: String) {
        folderField.stringValue = path
        onChange?(self)
    }

    func setFolderNote(_ text: String, isError: Bool) {
        guard !text.isEmpty else { return }
        ButtonAnswer.show(text, isError: isError, at: chooseButton)
    }

    func setLinkNote(_ text: String, isError: Bool) {
        guard !text.isEmpty else { return }
        ButtonAnswer.show(text, isError: isError, at: testButton)
    }

    @objc private func changed() { onChange?(self) }
    @objc private func chooseFolder() { onChooseFolder?(self) }
    @objc private func testLink() { onTestLink?(self) }

    func controlTextDidEndEditing(_ notification: Notification) {
        onChange?(self)
    }
}
