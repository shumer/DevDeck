import DDEVKit
import DevDeckCore
import Foundation
import TestHarness

/// Recorded from `ddev list -j` on a real machine, trimmed to two projects.
private let listOutput = """
{"level":"info","msg":"raw","raw":[\
{"approot":"/Users/x/Projects/whistleblower","docroot":"docroot",\
"httpsurl":"https://governance.ddev.site:9444","httpurl":"http://governance.ddev.site:9081",\
"mailpit_https_url":"https://governance.ddev.site:8026","mailpit_url":"http://governance.ddev.site:8025",\
"mutagen_enabled":true,"mutagen_status":"ok","name":"Governance","nodejs_version":"18",\
"primary_url":"https://governance.ddev.site:9444","router":"traefik","router_disabled":false,\
"shortroot":"~/Projects/whistleblower","status":"paused","status_desc":"paused","type":"drupal9",\
"xhgui_https_url":"https://governance.ddev.site:8142","xhgui_url":"http://governance.ddev.site:8143"},\
{"approot":"/Users/x/Projects/NasdaqIR","docroot":"docroot",\
"mailpit_https_url":"https://nasdaqir.ddev.site:8026","mutagen_enabled":true,"mutagen_status":"stopped",\
"name":"nasdaqir","primary_url":"https://nasdaqir.ddev.site","status":"running","status_desc":"running",\
"type":"drupal9"}\
],"time":"2026-08-02T23:00:00.000000+02:00"}
"""

private let configYAML = """
name: nasdaqir
type: drupal9
docroot: docroot
php_version: "8.4"
webserver_type: nginx-fpm
additional_hostnames:
    - automatedtests.local
database:
    type: mysql
    version: "8.0"
hooks:
    post-start:
        - exec: echo hi
nodejs_version: "18"
"""

func runDDEVTests(_ run: TestRun) async {
    run.section("DDEV - reading ddev list")

    let entries = DDEVEnvironment.parseList(listOutput)

    await run.test("every project comes back from one call") {
        try expectEqual(entries.count, 2, "one command answers for the whole deck")
        try expectEqual(entries.map(\.name), ["Governance", "nasdaqir"])
    }

    await run.test("paused is its own state, not a shade of stopped") {
        try expectEqual(entries.first?.state, .paused)
        try expectEqual(entries.last?.state, .running)
        try expectEqual(DDEVState(apiValue: "stopped"), .stopped)
        try expectEqual(DDEVState(apiValue: "something new"), .unknown)
    }

    await run.test("the URLs a card links to are read, https first") {
        let governance = try expectNotNil(entries.first, "entry")
        try expectEqual(governance.primaryURL?.absoluteString, "https://governance.ddev.site:9444")
        try expectEqual(governance.mailpitURL?.absoluteString, "https://governance.ddev.site:8026")
        try expectEqual(governance.xhguiURL?.absoluteString, "https://governance.ddev.site:8142")
        try expectEqual(governance.approot, "/Users/x/Projects/whistleblower")
        try expectEqual(governance.type, "drupal9")
    }

    await run.test("output that is not a project list yields nothing rather than a guess") {
        try expect(DDEVEnvironment.parseList("").isEmpty)
        try expect(DDEVEnvironment.parseList("ddev: command not found").isEmpty)
        try expect(DDEVEnvironment.parseList("{\"level\":\"info\"}").isEmpty)
    }

    run.section("DDEV - reading .ddev/config.yaml")

    await run.test("php and database come from the checkout") {
        let config = DDEVConfig.parse(configYAML)
        try expectEqual(config.name, "nasdaqir")
        try expectEqual(config.type, "drupal9")
        try expectEqual(config.phpVersion, "8.4", "quotes are stripped")
        try expectEqual(config.databaseType, "mysql")
        try expectEqual(config.databaseVersion, "8.0")
        try expectEqual(config.databaseLabel, "mysql 8.0")
    }

    await run.test("the nested database block does not shadow the top-level type") {
        // Both blocks have a `type:` key; only indentation tells them apart.
        let config = DDEVConfig.parse(configYAML)
        try expectEqual(config.type, "drupal9", "the project type, not the database's")
    }

    await run.test("a file without a database says so instead of inventing one") {
        let config = DDEVConfig.parse("name: plain\ntype: php\nphp_version: \"8.2\"\n")
        try expectNil(config.databaseLabel)
        try expectEqual(config.phpVersion, "8.2")
    }

    run.section("DDEV - status")

    await run.test("a project is matched by name, and by folder when it was renamed") {
        let environment = DDEVEnvironment(runner: StubCommandRunner([]))
        let byName = DDEVProject(id: "n", name: "nasdaqir", folder: "/tmp")
        try expectEqual(environment.status(for: byName, entries: entries).state, .running)

        let renamed = DDEVProject(id: "g", name: "renamed-since", folder: "/Users/x/Projects/whistleblower")
        try expectEqual(environment.status(for: renamed, entries: entries).state, .paused,
                        "the folder is what the user actually chose")
    }

    await run.test("a project ddev has never heard of says so") {
        let environment = DDEVEnvironment(runner: StubCommandRunner([]))
        let status = environment.status(for: DDEVProject(id: "x", name: "gone"), entries: entries)
        try expectEqual(status.state, .unknown)
        try expectEqual(status.detail, "ddev does not know this project")
    }

    await run.test("ddev not answering is different from having no projects") {
        let environment = DDEVEnvironment(runner: StubCommandRunner([]))
        let status = environment.status(for: DDEVProject(id: "x", name: "any"), entries: nil)
        try expectEqual(status.state, .unknown)
        try expectEqual(status.detail, "ddev did not answer")
    }

    await run.test("a broken file sync is called out, a working one is not") {
        let ok = DDEVStatus(state: .running, entry: entries.first)
        try expectNil(ok.mutagenWarning, "mutagen is only worth mentioning when it is not fine")

        let broken = DDEVStatus(state: .running, entry: entries.last)
        try expectEqual(broken.mutagenWarning, "mutagen stopped",
                        "edits stop reaching the container and nothing else would hint at it")
    }

    await run.test("the versions line is the one that answers works-on-mine") {
        let status = DDEVStatus(state: .running, config: DDEVConfig.parse(configYAML))
        try expectEqual(status.versionsLine, "php 8.4 · mysql 8.0")
        try expectNil(DDEVStatus(state: .running).versionsLine)
    }

    run.section("DDEV - what the project is built on")

    await run.test("the version comes from composer.lock, not from ddev's type") {
        // Real numbers from this machine: both projects say `type: drupal9` in their DDEV
        // config while running Drupal 11 and 10. The lock file cannot drift that way.
        let lock = """
        {"packages":[
          {"name":"drupal/core-recommended","version":"11.4.4"},
          {"name":"drupal/core","version":"11.4.4"},
          {"name":"symfony/framework-bundle","version":"v7.1.0"}
        ]}
        """
        try expectEqual(ProjectFramework.parse(composerLock: Data(lock.utf8)), "drupal 11.4.4")
    }

    await run.test("a leading v on the tag is dropped") {
        let lock = """
        {"packages":[{"name":"laravel/framework","version":"v11.9.2"}]}
        """
        try expectEqual(ProjectFramework.parse(composerLock: Data(lock.utf8)), "laravel 11.9.2")
    }

    await run.test("no lock file, or nothing recognised, says nothing") {
        try expectNil(ProjectFramework.parse(composerLock: Data("{}".utf8)))
        try expectNil(ProjectFramework.parse(composerLock: Data("not json".utf8)))
        let unknown = """
        {"packages":[{"name":"vendor/thing","version":"1.0"}]}
        """
        try expectNil(ProjectFramework.parse(composerLock: Data(unknown.utf8)))
        try expectNil(ProjectFramework.label(in: nil))
    }

    await run.test("the footer falls back to ddev's type when there is no lock file") {
        let fromLock = DDEVStatus(state: .running, entry: entries.first, framework: "drupal 11.4.4")
        try expectEqual(fromLock.frameworkLabel, "drupal 11.4.4")

        let withoutLock = DDEVStatus(state: .running, entry: entries.first)
        try expectEqual(withoutLock.frameworkLabel, "drupal9", "stale, but better than nothing")
    }

    run.section("DDEV - projects and links")

    await run.test("the title falls back to the ddev name") {
        try expectEqual(DDEVProject(id: "p", name: "nasdaqir").displayTitle, "nasdaqir")
        try expectEqual(DDEVProject(id: "p", name: "nasdaqir", title: "IR site").displayTitle, "IR site")
        try expectEqual(DDEVProject(id: "p", name: "nasdaqir", title: "  ").displayTitle, "nasdaqir")
    }

    await run.test("tooling and environments are separate rows") {
        let status = DDEVStatus(state: .running, entry: entries.first)

        let plain = DDEVProject(id: "g", name: "Governance")
        try expectEqual(plain.toolLinks(status: status).map(\.label), ["Mailpit"],
                        "xhgui is off until someone wants it")
        try expectEqual(plain.environmentLinks(status: status).map(\.label), ["Local site"],
                        "the deployed ones ship empty")

        let everything = DDEVProject(id: "g", name: "Governance", showsXhgui: true)
        try expectEqual(everything.toolLinks(status: status).map(\.label), ["Mailpit", "xhgui"])

        let quiet = DDEVProject(id: "g", name: "Governance", showsMailpit: false)
        try expect(quiet.toolLinks(status: status).isEmpty)
    }

    await run.test("test, uat and prod appear once their addresses are typed in") {
        let status = DDEVStatus(state: .running, entry: entries.first)
        var project = DDEVProject(id: "g", name: "Governance")

        try expectEqual(project.customLinks.map(\.label), ["Test", "UAT", "Prod"],
                        "the three environments are offered, empty and off")

        project.customLinks[0].urlTemplate = "https://test.example.com"
        project.customLinks[0].isEnabled = true
        project.customLinks[2].urlTemplate = "https://example.com"
        project.customLinks[2].isEnabled = true

        try expectEqual(
            project.environmentLinks(status: status).map(\.label),
            ["Local site", "Test", "Prod"],
            "local first, then whatever has an address"
        )
        try expect(project.toolLinks(status: status).allSatisfy { $0.kind == .tool })
    }

    await run.test("an environment added since the project was created is picked up") {
        let json = """
        { "id": "g", "name": "Governance",
          "customLinks": [{ "label": "Test", "urlTemplate": "https://test.example.com", "isEnabled": true }] }
        """
        let project = try JSONDecoder().decode(DDEVProject.self, from: Data(json.utf8))
        try expectEqual(project.customLinks.map(\.label), ["Test", "UAT", "Prod"])
        try expectEqual(project.customLinks.first?.kind, .tool,
                        "a link stored before kinds existed keeps being what it was")
    }

    await run.test("a link can point at a path on the local site") {
        let status = DDEVStatus(state: .running, entry: entries.last)
        let project = DDEVProject(
            id: "n",
            name: "nasdaqir",
            showsMailpit: false,
            customLinks: [DDEVCustomLink(label: "Admin", urlTemplate: "{site}/user/login")]
        )
        try expectEqual(
            project.toolLinks(status: status).first?.url.absoluteString,
            "https://nasdaqir.ddev.site/user/login"
        )
    }

    await run.test("only the local link waits on ddev; a typed address does not") {
        var project = DDEVProject(id: "n", name: "nasdaqir")
        try expect(project.links(status: DDEVStatus(state: .unknown)).isEmpty)

        project.customLinks[2].urlTemplate = "https://example.com"
        project.customLinks[2].isEnabled = true
        try expectEqual(
            project.environmentLinks(status: DDEVStatus(state: .unknown)).map(\.label),
            ["Prod"],
            "production is reachable whether or not the container is up"
        )
    }

    await run.test("actions map onto the ddev commands") {
        try expectEqual(DDEVAction.start.command, "ddev start")
        try expectEqual(DDEVAction.stop.command, "ddev stop")
        try expectEqual(DDEVAction.restart.command, "ddev restart")
    }

    await run.test("a project with no folder runs nothing") {
        let environment = DDEVEnvironment(runner: StubCommandRunner([]))
        let result = await environment.perform(.start, for: DDEVProject(id: "p", name: "p"))
        try expectNil(result)
    }

    await run.test("identifiers are slugged and never collide") {
        try expectEqual(DDEVProject.makeID(from: "Governance", existing: []), "governance")
        try expectEqual(DDEVProject.makeID(from: "Governance", existing: ["governance"]), "governance-2")
        try expectEqual(DDEVProject(id: "governance", name: "Governance").cardID.rawValue,
                        "ddev.project.governance")
    }

    run.section("DDEV - storage")

    await run.test("projects round trip and can be disabled") {
        let store = DDEVProjectsStore(backend: InMemoryPreferences())
        try expect(store.projects().isEmpty, "there is no sensible project to invent")

        store.save([
            DDEVProject(id: "g", name: "Governance"),
            DDEVProject(id: "n", name: "nasdaqir", isEnabled: false),
        ])
        try expectEqual(store.projects().count, 2)
        try expectEqual(store.enabledProjects().map(\.id), ["g"])
        try expectEqual(store.project(forCard: CardID(rawValue: "ddev.project.n"))?.name, "nasdaqir")
    }
}
