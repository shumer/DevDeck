import Foundation

/// Whether a folder is an Arc XP Fusion checkout: one that `npx fusion daemon` can start.
///
/// Nothing in such a checkout names the organisation or the site; those are typed. What it
/// does carry is the CLI in its `package.json`, which is the one file every Fusion checkout
/// has and no other project does.
public enum ArcCheckout {
    public static func isFusionCheckout(_ folder: URL) -> Bool {
        let manifest = folder.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        for section in ["dependencies", "devDependencies"] {
            if let packages = object[section] as? [String: Any], packages["@arc-fusion/cli"] != nil { return true }
        }
        return false
    }
}
