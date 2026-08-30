import Foundation

/// The last few lines of whatever a project is writing, as a card shows them.
public struct LogLines: Sendable, Equatable {
    /// Newest last, already trimmed and stripped of terminal escapes.
    public var lines: [String]
    /// What produced them, shown above the tray: `docker logs fusion-engine`, `ddev logs`,
    /// `tail ledwall-feed.log`. A tray that does not say where it is looking is a tray you
    /// cannot trust when it is empty.
    public var source: String?
    /// Why there is nothing, when there is nothing.
    public var detail: String?
    public var fetchedAt: Date?
    /// The file behind these lines, when there is one to open in full.
    public var fileURL: URL?

    public init(
        lines: [String] = [],
        source: String? = nil,
        detail: String? = nil,
        fetchedAt: Date? = nil,
        fileURL: URL? = nil
    ) {
        self.lines = lines
        self.source = source
        self.detail = detail
        self.fetchedAt = fetchedAt
        self.fileURL = fileURL
    }

    public var isEmpty: Bool { lines.isEmpty }
}

/// Turning command output into the handful of lines a card can hold.
///
/// Pure text handling, kept away from the three services that need it: Arc reads Docker, DDEV
/// reads the CLI and a plain project reads a file, and all three arrive as the same mess of
/// colour escapes, carriage returns and blank lines.
public enum LogTail {
    /// How many lines a tray holds. Six is what fits without the card becoming a log window,
    /// and a log window is what the arrow in the corner is for.
    public static let lineLimit = 6
    /// How much of a file is worth reading to find its last six lines. Generous: a line of
    /// build output can be long, and a start that failed prints a stack trace.
    public static let fileTailBytes = 64 * 1024

    /// The last `limit` useful lines of a command's output.
    ///
    /// Blank lines go, because a tray of six lines cannot afford two of them, and progress
    /// output drawn with carriage returns is split on those as well: without that, the whole of
    /// `docker compose` arrives as one line and the tray shows a single unreadable ribbon.
    public static func lines(from output: String, limit: Int = lineLimit) -> [String] {
        let cleaned = output
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { strippingEscapes(String($0)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(cleaned.suffix(limit))
    }

    /// Drops ANSI colour and cursor escapes.
    ///
    /// Every tool here paints: `ddev logs` colours by service, vite colours its banner, docker
    /// colours container names. Rendered as text those escapes are visible junk like `[32m`,
    /// and the tray is not a terminal.
    public static func strippingEscapes(_ line: String) -> String {
        var result = ""
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            guard characters[index] == "\u{1B}" else {
                result.append(characters[index])
                index += 1
                continue
            }
            // CSI: ESC [ parameters, then a letter that ends it. Anything else after ESC is a
            // two-character sequence.
            index += 1
            guard index < characters.count else { break }
            if characters[index] == "[" {
                index += 1
                while index < characters.count, !characters[index].isLetter { index += 1 }
            }
            index += 1
        }
        return result
    }

    /// The tail of a file, read without a shell.
    ///
    /// A detached start writes a log nobody else knows about, and it can grow to megabytes over
    /// a day. Reading the whole thing to show six lines is what makes a card stutter, so only
    /// the last chunk is read, and the first line of that chunk is dropped because it is almost
    /// certainly half a line.
    public static func tail(of url: URL, bytes: Int = fileTailBytes) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        guard offset > 0, let firstBreak = text.firstIndex(where: { $0 == "\n" || $0 == "\r" }) else {
            return text
        }
        return String(text[text.index(after: firstBreak)...])
    }
}
