import DevDeckCore
import DevDeckEngine
import SwiftUI

/// "GitHub Actions": draws `ActionsCardModel`, which the engine has already decided.
public struct ActionsCard: View {
    public nonisolated static let size = CGSize(width: CardMetrics.width, height: 190)

    private let model: ActionsCardModel
    private let onCommand: (DeckCommand) -> Void

    public init(model: ActionsCardModel, onCommand: @escaping (DeckCommand) -> Void = { _ in }) {
        self.model = model
        self.onCommand = onCommand
    }

    /// A fixed height, unlike the other list cards: this one always draws two rows.
    public nonisolated static func size(isCollapsed: Bool) -> CGSize {
        isCollapsed ? CGSize(width: CardMetrics.width, height: CollapsedCardMetrics.height) : size
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
    private func content(_ content: ActionsCardModel.Content) -> some View {
        switch content {
        case .unconfigured(let notice):
            self.notice(notice, detailLines: nil)
        case .quiet(let notice, let footer):
            self.notice(notice, detailLines: 2)
            CardFooter(footer)
        case .runs(let headline, let headlineTone, let caption, let rows, let footer):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(headline)
                    .font(.system(size: 42, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(headlineTone.color)
                Text(caption)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DeckTheme.label)
            }
            .padding(.top, 2)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    self.row(row)
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 4)

            CardFooter(footer)
        }
    }

    /// Words in place of numbers: what the card does and why there is nothing in it, or what was
    /// looked at and for how long, with the one thing to do about it when there is one.
    private func notice(_ notice: ActionsCardModel.Notice, detailLines: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 8)
            Text(notice.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DeckTheme.value)
            Text(notice.detail)
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.label)
                .lineLimit(detailLines)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let link = notice.link {
                Text(link.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DeckTheme.blue)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .clickable(cornerRadius: 5)
                    .onTapGesture { onCommand(link.command) }
                    .padding(.top, 6)
            }
            Spacer(minLength: 8)
        }
    }

    private func row(_ row: ActionsCardModel.Row) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(row.tone.color)
                .frame(width: 7, height: 7)
            Text(row.title)
                .font(.system(size: 12.5))
                .foregroundStyle(DeckTheme.value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(row.trailing)
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.label)
                .fixedSize()
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1) }
        .contentShape(Rectangle())
        .clickable(isEnabled: row.command != nil)
        .onTapGesture { if let command = row.command { onCommand(command) } }
        .help(row.help)
    }
}
