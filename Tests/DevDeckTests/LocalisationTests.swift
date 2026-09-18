import DevDeckCore
import Foundation
import TestHarness

/// Where the tables live in the repository. The suite is a plain executable with no bundle of its
/// own, so it reads them from here rather than from `Bundle.main`.
let localisationRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/Localizations")

/// Every key of one language's table, as the file has them.
private func keys(of language: String) throws -> Set<String> {
    let url = localisationRoot.appendingPathComponent("\(language).lproj/Localizable.strings")
    let text = try String(contentsOf: url, encoding: .utf8)
    var found: Set<String> = []
    for line in text.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\""), let end = trimmed.dropFirst().firstIndex(of: "\"") else { continue }
        found.insert(String(trimmed[trimmed.index(after: trimmed.startIndex)..<end]))
    }
    return found
}

private func pluralKeys(of language: String) throws -> [String: Set<String>] {
    let url = localisationRoot.appendingPathComponent("\(language).lproj/Localizable.stringsdict")
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    guard let table = plist as? [String: [String: Any]] else { return [:] }
    return table.reduce(into: [:]) { result, entry in
        guard let rules = entry.value["count"] as? [String: Any] else { return }
        result[entry.key] = Set(rules.keys.filter { !$0.hasPrefix("NSString") })
    }
}

/// The application's own sources, which the key sweep reads.
private let sourceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Sources")

/// Every key the code asks for: the plain ones through `L`, the counted ones through `LN`.
private func keysInSources() throws -> (asked: Set<String>, counted: Set<String>) {
    var asked: Set<String> = []
    var counted: Set<String> = []
    guard let walker = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) else {
        return ([], [])
    }
    for case let url as URL in walker where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        collect(from: text, call: "L(\"", into: &asked)
        collect(from: text, call: "LN(\"", into: &counted)
    }
    return (asked, counted)
}

/// The literals after a call, `L("a.b")` and `LN("a.b", …)`, taking care not to read `LN(` as
/// an `L(` that happens to follow a letter.
private func collect(from text: String, call: String, into keys: inout Set<String>) {
    var index = text.startIndex
    while let start = text.range(of: call, range: index..<text.endIndex) {
        index = start.upperBound
        if start.lowerBound > text.startIndex {
            let before = text[text.index(before: start.lowerBound)]
            if before.isLetter || before.isNumber || before == "_" { continue }
        }
        guard let end = text[index...].firstIndex(of: "\"") else { break }
        keys.insert(String(text[index..<end]))
    }
}

func runLocalisationTests(_ run: TestRun) async {
    run.section("Localisation - the tables")

    let languages = ["en", "de", "es", "fr", "it", "ru"]

    await run.test("every language says everything English says, and nothing it does not") {
        let english = try keys(of: "en")
        try expect(!english.isEmpty, "the English table is the source; an empty one means it was not found")
        for language in languages.dropFirst() {
            let theirs = try keys(of: language)
            try expect(english.subtracting(theirs).isEmpty,
                       "\(language) is missing \(english.subtracting(theirs).sorted().joined(separator: ", "))")
            try expect(theirs.subtracting(english).isEmpty,
                       "\(language) has keys English does not: \(theirs.subtracting(english).sorted().joined(separator: ", "))")
        }
    }

    await run.test("a count carries the forms its language actually has") {
        for language in languages {
            let plurals = try pluralKeys(of: language)
            try expect(!plurals.isEmpty, "\(language) has no plural table")
            for (key, forms) in plurals {
                try expect(forms.contains("other"), "\(language) \(key) has no other form")
                try expect(forms.contains("one"), "\(language) \(key) has no singular")
                if language == "ru" {
                    // Russian has three: 1, 2-4, 5 and up. Joining a number to a word cannot do it.
                    try expect(forms.contains("few") && forms.contains("many"), "\(language) \(key) has only \(forms.sorted())")
                }
            }
        }
    }

    await run.test("the table and the code ask each other for the same keys") {
        // A key is a string on both sides, so nothing but a sweep of the sources catches a typo
        // in one of them, or a word left in the table after the thing that said it was removed.
        let (asked, counted) = try keysInSources()
        let english = try keys(of: "en")
        let plurals = Set(try pluralKeys(of: "en").keys)

        try expect(!asked.isEmpty, "the sources were not found: \(sourceRoot.path)")
        try expect(asked.subtracting(english).isEmpty,
                   "the code asks for keys no table has: \(asked.subtracting(english).sorted().joined(separator: ", "))")
        try expect(counted.subtracting(plurals).isEmpty,
                   "the code counts with keys no plural table has: \(counted.subtracting(plurals).sorted().joined(separator: ", "))")
        try expect(english.subtracting(asked).isEmpty,
                   "the table keeps words nothing says: \(english.subtracting(asked).sorted().joined(separator: ", "))")
        try expect(plurals.subtracting(counted).isEmpty,
                   "the plural table keeps counts nothing counts: \(plurals.subtracting(counted).sorted().joined(separator: ", "))")
    }

    run.section("Localisation - reading them")

    await run.test("a language is read from its own table, and falls back to English") {
        Strings.use(.russian, lookingIn: localisationRoot)
        try expectEqual(L("settings.language"), "Язык")
        try expectEqual(L("update.button.check"), "Проверить")
        try expectEqual(L("nothing.like.this"), "nothing.like.this", "a missing key shows itself")

        Strings.use(.german, lookingIn: localisationRoot)
        try expectEqual(L("settings.general.startAtLogin"), "Beim Anmelden starten")

        Strings.use(.italian, lookingIn: localisationRoot)
        try expectEqual(L("update.available", "0.17"), "0.17 è disponibile", "the argument lands where the language puts it")
    }

    await run.test("a count is worded by the language's own rules") {
        Strings.use(.russian, lookingIn: localisationRoot)
        try expectEqual(LN("attention.summary.stuck", 1), "1 застряло")
        try expectEqual(LN("attention.summary.stuck", 3), "3 застряли")
        try expectEqual(LN("attention.summary.stuck", 7), "7 застряло")

        Strings.use(.english, lookingIn: localisationRoot)
        try expectEqual(LN("attention.summary.waiting", 1), "1 waiting on you")
        try expectEqual(LN("attention.summary.waiting", 4), "4 waiting on you")
    }

    // Back to English, which is what the rest of the suite reads its expectations in.
    Strings.use(.english, lookingIn: localisationRoot)
}
