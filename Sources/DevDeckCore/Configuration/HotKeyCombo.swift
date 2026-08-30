import Foundation

/// A key and its modifiers, as the deck's summon shortcut.
///
/// Carbon's numbers rather than AppKit's, because Carbon is what registers the shortcut: a
/// system-wide hot key that needs no Input Monitoring permission is `RegisterEventHotKey`, and
/// it speaks in virtual key codes and its own modifier mask. Translating once, here, keeps that
/// detail out of both the settings screen and the app delegate.
public struct HotKeyCombo: Sendable, Equatable, Codable {
    /// Carbon modifier bits, the same values `RegisterEventHotKey` takes.
    public struct Modifiers: OptionSet, Sendable, Equatable, Codable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 8)
        public static let shift = Modifiers(rawValue: 1 << 9)
        public static let option = Modifiers(rawValue: 1 << 11)
        public static let control = Modifiers(rawValue: 1 << 12)
    }

    public let keyCode: UInt32
    public let modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌥Space. Space because it is the key everybody already reads as "show me the thing", and
    /// Option because Command and Control are where applications put their own shortcuts.
    public static let optionSpace = HotKeyCombo(keyCode: 49, modifiers: .option)

    // MARK: Storage

    /// `keyCode|modifiers`. Two numbers, in the form a person can read in `defaults read` and
    /// correct by hand when they have bound something unreachable.
    public var storage: String { "\(keyCode)|\(modifiers.rawValue)" }

    public init?(storage: String) {
        let parts = storage.split(separator: "|")
        guard parts.count == 2, let key = UInt32(parts[0]), let mods = UInt32(parts[1]) else {
            return nil
        }
        self.init(keyCode: key, modifiers: Modifiers(rawValue: mods))
    }

    // MARK: Reading it back

    /// Whether this is safe to register system-wide.
    ///
    /// A bare key would be taken from every application on the machine, so pressing `k` in an
    /// editor would raise the deck instead of typing. The settings screen refuses to record one
    /// rather than letting somebody discover it later.
    public var isValid: Bool { !modifiers.isEmpty && Self.name(for: keyCode) != nil }

    /// The shortcut as it is written on a menu: modifiers in Apple's order, then the key.
    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (Self.name(for: keyCode) ?? "?")
    }

    /// Virtual key codes are positions on the keyboard rather than letters, so this is a table
    /// and cannot be anything else. Only the keys worth binding are here: a shortcut on a key
    /// this does not know would show as `?`, so it is refused at the point of recording.
    public static func name(for keyCode: UInt32) -> String? { names[keyCode] }

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "5", 23: "6", 25: "9", 26: "7", 28: "8", 29: "0",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    ]
}
