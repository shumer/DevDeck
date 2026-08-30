import DevDeckCore
import SwiftUI

/// The small switch in a card's header that opens its log tray.
///
/// In the header rather than in the control row on purpose. Four buttons already need 311
/// points and the row has 303, so a fifth would shrink every one of them and undo the reason
/// the card is 352 points wide in the first place.
public struct CardHeaderToggle: Identifiable {
    public let id: String
    public let isOn: Bool
    public let isEnabled: Bool
    public let systemImage: String
    public let help: String
    public let action: () -> Void
    /// Shown hanging off the button while it is on. The log tray has none: it lives in the card.
    public let popover: AnyView?

    public init(
        id: String = "log",
        isOn: Bool,
        isEnabled: Bool = true,
        systemImage: String = "text.alignleft",
        help: String,
        popover: AnyView? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.systemImage = systemImage
        self.help = help
        self.popover = popover
        self.action = action
    }

    public nonisolated static let width: Double = 20
}

/// The last few lines the project is writing, on the card itself.
///
/// A card that can start something has to be able to show what that something said. The Logs
/// button used to open a file in Console, which answers the question and costs a context
/// switch; six lines in place answer it without one. It is not a terminal: no following, no
/// scrolling, no colour. The arrow opens the real log when six lines are not enough.
public struct CardLogTray: View {
    private let logs: LogLines
    private let onOpenFile: ((URL) -> Void)?

    public init(logs: LogLines, onOpenFile: ((URL) -> Void)? = nil) {
        self.logs = logs
        self.onOpenFile = onOpenFile
    }

    public nonisolated static let topPadding: Double = 11
    public nonisolated static let ruleGap: Double = 7
    public nonisolated static let sourceHeight: Double = 13
    public nonisolated static let sourceGap: Double = 4
    public nonisolated static let lineHeight: Double = 13

    /// What the tray costs, for the panel to add up. A tray with nothing in it still shows one
    /// line saying so, because an empty box on a card is a bug report waiting to happen.
    public nonisolated static func height(lineCount: Int) -> Double {
        let lines = max(1, min(lineCount, LogTail.lineLimit))
        return topPadding + 1 + ruleGap + sourceHeight + sourceGap + lineHeight * Double(lines)
    }

    /// How tall this particular tray is.
    public nonisolated static func height(for logs: LogLines?) -> Double {
        guard let logs else { return 0 }
        return height(lineCount: logs.lines.count)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(DeckTheme.faint)
                .frame(height: 1)
                .padding(.bottom, Self.ruleGap)

            HStack(spacing: 6) {
                Text(logs.source ?? "log")
                    .font(.system(size: 9.5, weight: .medium))
                    .kerning(0.3)
                    .textCase(.uppercase)
                    .foregroundStyle(DeckTheme.value.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let url = logs.fileURL, let onOpenFile {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DeckTheme.value.opacity(0.5))
                        .contentShape(Rectangle())
                        .clickable(cornerRadius: 4)
                        .onTapGesture { onOpenFile(url) }
                        .help("open the whole log")
                }
            }
            .frame(height: Self.sourceHeight)
            .padding(.bottom, Self.sourceGap)

            if logs.lines.isEmpty {
                line(logs.detail ?? "nothing logged yet", isDim: true)
            } else {
                ForEach(Array(logs.lines.enumerated()), id: \.offset) { _, text in
                    line(text, isDim: false)
                }
            }
        }
        .padding(.top, Self.topPadding)
    }

    /// The newest lines matter most, so a long line is cut at the end rather than the middle:
    /// what a tool prints first on a line is what says which line it is.
    private func line(_ text: String, isDim: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(DeckTheme.value.opacity(isDim ? 0.4 : 0.58))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: Self.lineHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
