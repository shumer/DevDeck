import DevDeckCore
import Foundation
import TestHarness

private func release(
    tag: String,
    assets: [String] = ["DevDeck-0.11-120.zip"],
    draft: Bool = false,
    prerelease: Bool = false
) -> Release {
    Release(
        tagName: tag,
        htmlUrl: URL(string: "https://github.com/shumer/DevDeck/releases/tag/\(tag)")!,
        draft: draft,
        prerelease: prerelease,
        publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
        assets: assets.map {
            ReleaseAsset(name: $0, browserDownloadUrl: URL(string: "https://example.test/\($0)")!, size: 1_719_879)
        }
    )
}

/// A folder shaped like an unpacked archive, with a bundle in it carrying the given plist.
private func makeUnpacked(bundleName: String = "DevDeck.app", plist: [String: Any]?) -> URL {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("devdeck-update-\(UUID().uuidString)", isDirectory: true)
    let contents = folder.appendingPathComponent(bundleName).appendingPathComponent("Contents")
    try? FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    if let plist, let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
        try? data.write(to: contents.appendingPathComponent("Info.plist"))
    }
    return folder
}

func runUpdateTests(_ run: TestRun) async {
    run.section("Updates - versions")

    await run.test("versions compare by number, with or without the v") {
        let older = try expectNotNil(SemanticVersion("v0.9"), "0.9")
        let newer = try expectNotNil(SemanticVersion("0.10"), "0.10")
        try expect(older < newer, "0.10 is newer than 0.9, whatever a string comparison says")
        try expect(SemanticVersion("0.9.1")! > SemanticVersion("0.9")!)
        try expect(SemanticVersion("1.0")! == SemanticVersion("1.0.0")!, "a missing component is zero")
        try expectEqual(SemanticVersion("v0.10")?.description, "0.10")
        try expectNil(SemanticVersion("latest"), "a tag that is not a version is not a version")
        try expectNil(SemanticVersion(""), "empty")
    }

    run.section("Updates - which release counts")

    await run.test("a newer release with a build attached is an update") {
        let update = try expectNotNil(UpdateCheck.available(current: "0.10", release: release(tag: "v0.11")), "update")
        try expectEqual(update.version.description, "0.11")
        try expectEqual(update.asset.name, "DevDeck-0.11-120.zip")
        try expectEqual(update.pageURL.absoluteString, "https://github.com/shumer/DevDeck/releases/tag/v0.11")
    }

    await run.test("the same version, or an older one, is nothing to do") {
        try expectNil(UpdateCheck.available(current: "0.11", release: release(tag: "v0.11")),
                      "a deck built past the last tag runs the version the tag names; it must not be offered itself")
        try expectNil(UpdateCheck.available(current: "0.12", release: release(tag: "v0.11")), "older")
    }

    await run.test("a draft, a prerelease, or a release with no build is skipped") {
        try expectNil(UpdateCheck.available(current: "0.10", release: release(tag: "v0.11", draft: true)), "draft")
        try expectNil(UpdateCheck.available(current: "0.10", release: release(tag: "v0.11", prerelease: true)), "prerelease")
        try expectNil(UpdateCheck.available(current: "0.10", release: release(tag: "v0.11", assets: ["notes.txt"])),
                      "nothing to install")
        try expectNil(UpdateCheck.available(current: "0.10", release: release(tag: "nightly")), "not a version")
    }

    await run.test("the build is the zip the workflow names, whatever else is attached") {
        let mixed = release(tag: "v0.11", assets: ["DevDeck-0.11-120.zip.sha256", "DevDeck-0.11-120.zip", "Source code.zip"])
        try expectEqual(UpdateCheck.asset(in: mixed)?.name, "DevDeck-0.11-120.zip")
    }

    await run.test("GitHub's answer decodes, dates and all") {
        let json = """
        {"tag_name":"v0.11","html_url":"https://github.com/shumer/DevDeck/releases/tag/v0.11",
         "draft":false,"prerelease":false,"published_at":"2026-09-11T10:00:00Z",
         "assets":[{"name":"DevDeck-0.11-120.zip","browser_download_url":"https://github.com/x.zip","size":1719879,"content_type":"application/zip"}],
         "body":"notes"}
        """
        let decoded = try UpdateCheck.decode(Data(json.utf8))
        try expectEqual(decoded.tagName, "v0.11")
        try expectEqual(decoded.assets.first?.size, 1_719_879)
        try expectNotNil(decoded.publishedAt, "published_at")
    }

    await run.test("the request goes to the latest release, unauthenticated") {
        let request = UpdateCheck.request()
        try expectEqual(request.url.absoluteString, "https://api.github.com/repos/shumer/DevDeck/releases/latest")
        try expectNil(request.headers["Authorization"], "the repository is public; a token would tie the check to an account")
        try expectEqual(request.method, .get)
    }

    run.section("Updates - the unpacked bundle")

    let promised = SemanticVersion("0.11")!

    await run.test("the bundle inside the archive is found and checked against the release") {
        let folder = makeUnpacked(plist: [
            "CFBundleIdentifier": "com.shumer.devdeck",
            "CFBundleShortVersionString": "0.11",
        ])
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = try expectNotNil(UpdateCheck.bundle(inUnpacked: folder), "bundle")
        try expectEqual(bundle.lastPathComponent, "DevDeck.app")
        try expect(UpdateCheck.verifyBundle(at: bundle, version: promised))
    }

    await run.test("somebody else's app, an older build under a new name, or no plist is refused") {
        for (name, plist) in [
            ("another app", ["CFBundleIdentifier": "com.example.other", "CFBundleShortVersionString": "0.11"]),
            ("older build", ["CFBundleIdentifier": "com.shumer.devdeck", "CFBundleShortVersionString": "0.10"]),
            ("no plist", nil),
        ] as [(String, [String: Any]?)] {
            let folder = makeUnpacked(plist: plist)
            defer { try? FileManager.default.removeItem(at: folder) }
            let bundle = try expectNotNil(UpdateCheck.bundle(inUnpacked: folder), "bundle")
            try expect(!UpdateCheck.verifyBundle(at: bundle, version: promised), name)
        }
    }

    await run.test("an archive with no bundle in it has nothing to verify") {
        let folder = makeUnpacked(bundleName: "README.md", plist: nil)
        defer { try? FileManager.default.removeItem(at: folder) }
        try expectNil(UpdateCheck.bundle(inUnpacked: folder), "bundle")
    }

    run.section("Updates - coming back up")

    await run.test("the relaunch waits for the old process and opens the same path") {
        let script = UpdateCheck.relaunchScript(waitingFor: 4242, appPath: "/Applications/DevDeck.app")
        try expectEqual(script, "while kill -0 4242 2>/dev/null; do sleep 0.2; done; open '/Applications/DevDeck.app'")
    }

    await run.test("a path with a quote in it stays one argument") {
        let script = UpdateCheck.relaunchScript(waitingFor: 1, appPath: "/Users/o'brien/Applications/DevDeck.app")
        try expect(script.hasSuffix("open '/Users/o'\\''brien/Applications/DevDeck.app'"), script)
    }
}
