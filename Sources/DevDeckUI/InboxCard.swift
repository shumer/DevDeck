import AppKit
import DevDeckCore
import DevDeckEngine
import SwiftUI

/// "GitHub inbox": draws `InboxCardModel`, which the engine has already decided.
public struct InboxCard: View {
    public nonisolated static let baseHeight: Double = 119

    private let model: InboxCardModel
    private let onCommand: (DeckCommand) -> Void

    public init(model: InboxCardModel, onCommand: @escaping (DeckCommand) -> Void = { _ in }) {
        self.model = model
        self.onCommand = onCommand
    }

    public nonisolated static func size(for model: InboxCardModel) -> CGSize {
        guard !model.isCollapsed else {
            return CGSize(width: CardMetrics.width, height: CollapsedCardMetrics.height)
        }
        return CGSize(
            width: CardMetrics.width,
            height: CardMetrics.height(base: baseHeight, total: model.total, isExpanded: model.isExpanded)
        )
    }

    public var body: some View {
        if model.isCollapsed {
            CardCollapsedRow(model.collapsed, onCommand: onCommand)
        } else {
            CardChrome(title: model.title, pill: model.pill.map { ($0.text, $0.tone.color) }) {
                if let content = model.content {
                    self.content(content)
                } else {
                    CardPlaceholderView(model.placeholder)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ content: InboxCardModel.Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(content.count)
                .font(.system(size: 42, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(content.countTone.color)
            Text(content.unit)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DeckTheme.label)
        }
        .padding(.top, 2)

        VStack(spacing: 0) {
            ForEach(content.rows) { row in
                self.row(row)
            }
        }
        .padding(.top, 6)

        if let expander = content.expander {
            CardExpanderView(expander, onCommand: onCommand)
        }

        Spacer(minLength: 4)

        footer(content.footer)
    }

    @ViewBuilder
    private func footer(_ footer: InboxCardModel.Footer) -> some View {
        if let progress = footer.progress {
            HStack {
                Text(progress)
                    .foregroundStyle(footer.progressFailed ? DeckTheme.amber : DeckTheme.label)
                    .truncationMode(.tail)
                    .help(progress)
                Spacer(minLength: 6)
                clock(footer)
            }
            .font(.system(size: 10.5))
            .lineLimit(1)
            .frame(height: CardFooter.height)
        } else if let clearing = footer.clearing {
            HStack {
                InboxClearLink(normal: clearing, withOption: footer.clearingWithOption ?? clearing, onCommand: onCommand)
                Spacer(minLength: 6)
                clock(footer)
            }
            .font(.system(size: 10.5))
            .lineLimit(1)
            .frame(height: CardFooter.height)
        } else {
            CardFooter(leading: footer.leading, trailing: footer.clock, isStale: footer.isStale)
        }
    }

    private func clock(_ footer: InboxCardModel.Footer) -> some View {
        Text(footer.clock)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(footer.isStale ? DeckTheme.amber : DeckTheme.label)
            .fixedSize()
    }

    private func row(_ row: InboxCardModel.Row) -> some View {
        HStack(spacing: 8) {
            Text(row.chip)
                .font(.system(size: 10))
                .foregroundStyle(DeckTheme.label)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            if let account = row.account {
                AccountChip(account)
            }
            Text(row.title)
                .font(.system(size: 12.5))
                .foregroundStyle(row.isRead ? DeckTheme.label : DeckTheme.value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(row.age)
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.label)
                .fixedSize()
        }
        .frame(height: CardMetrics.rowHeight - 1)
        .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1) }
        .contentShape(Rectangle())
        .clickable(isEnabled: row.command != nil)
        .onTapGesture { if let command = row.command { onCommand(command) } }
        .contextMenu {
            ForEach(Array(row.menu.enumerated()), id: \.offset) { _, item in
                Button(item.title) { onCommand(item.command) }
            }
        }
        .help(row.help)
    }
}

/// The footer's link on the inbox card: "Mark the rest as read", or with ⌥ held, all of it.
///
/// ⌥ is read while the pointer is over the link, a few times a second, so the words change
/// the moment the key goes down rather than on the next mouse move. Nothing is watched while
/// the pointer is elsewhere, and no keyboard monitor is needed for it. Both versions of the link
/// come from the model; the key only picks one.
struct InboxClearLink: View {
    let normal: DeckLinkModel
    let withOption: DeckLinkModel
    let onCommand: (DeckCommand) -> Void

    // Written out rather than as `@State`: see `ClickableHighlight`.
    private var _isOptionDown = State(initialValue: false)
    private var isOptionDown: Bool {
        get { _isOptionDown.wrappedValue }
        nonmutating set { _isOptionDown.wrappedValue = newValue }
    }
    private var _watch = State(initialValue: OptionWatch())

    init(normal: DeckLinkModel, withOption: DeckLinkModel, onCommand: @escaping (DeckCommand) -> Void) {
        self.normal = normal
        self.withOption = withOption
        self.onCommand = onCommand
    }

    var body: some View {
        let link = isOptionDown ? withOption : normal
        Text(link.title)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(DeckTheme.blue)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
            .clickable(cornerRadius: 4)
            .onHover { hovering in
                let flag = _isOptionDown
                _watch.wrappedValue.follow(hovering) { flag.wrappedValue = $0 }
            }
            .onTapGesture {
                // The key is read again at the click: the last poll may be a tenth of a second
                // old, and the click is what counts.
                let option = NSEvent.modifierFlags.contains(.option)
                onCommand((option ? withOption : normal).command)
            }
            .help(link.help)
            .padding(.leading, -3)
    }
}

/// Polls ⌥ while the pointer is over something that cares, and stops when it leaves.
@MainActor
final class OptionWatch {
    private var timer: Timer?

    func follow(_ hovering: Bool, report: @escaping (Bool) -> Void) {
        timer?.invalidate()
        timer = nil
        guard hovering else {
            report(false)
            return
        }
        report(NSEvent.modifierFlags.contains(.option))
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            report(NSEvent.modifierFlags.contains(.option))
        }
    }
}
