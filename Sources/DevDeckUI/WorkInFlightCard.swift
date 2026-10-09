import DevDeckCore
import DevDeckEngine
import SwiftUI

/// Every checkout at once: draws `WorkInFlightCardModel`, which the engine has already decided.
public struct WorkInFlightCard: View {
    public nonisolated static let baseHeight: Double = 96

    private let model: WorkInFlightCardModel
    private let onCommand: (DeckCommand) -> Void

    public init(model: WorkInFlightCardModel, onCommand: @escaping (DeckCommand) -> Void = { _ in }) {
        self.model = model
        self.onCommand = onCommand
    }

    public nonisolated static func size(for model: WorkInFlightCardModel) -> CGSize {
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
            CardChrome(title: model.title, glyph: nil, timestamp: model.timestamp) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(model.count)")
                        .font(.system(size: 26, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(DeckTheme.value.opacity(0.85))
                    Text(model.unit)
                        .font(.system(size: 12))
                        .foregroundStyle(DeckTheme.label)
                    Spacer(minLength: 6)
                    if let pill = model.pill {
                        StatusPill(pill)
                    }
                }
                .frame(height: 30)
                .padding(.top, 6)

                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        self.row(row)
                    }
                }
                .padding(.top, 6)

                if let expander = model.expander {
                    CardExpanderView(expander, onCommand: onCommand)
                }

                Spacer(minLength: 4)
                CardFooter(model.footer)
            }
        }
    }

    private func row(_ row: WorkInFlightCardModel.Row) -> some View {
        // Work that exists only here is the colour; the rest is quiet, quieter than a label.
        let isLoud = row.tone != .neutral
        return HStack(spacing: 7) {
            Circle()
                .fill(isLoud ? row.tone.color : DeckTheme.label.opacity(0.6))
                .frame(width: 6, height: 6)
            Text(row.title)
                .font(.system(size: 11.5))
                .foregroundStyle(DeckTheme.value.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(row.branch)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(DeckTheme.value.opacity(0.45))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(row.summary)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(isLoud ? row.tone.color : DeckTheme.value.opacity(0.58))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: CardMetrics.rowHeight - 1)
        .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1) }
        .contentShape(Rectangle())
        .clickable()
        .onTapGesture { onCommand(row.command) }
        .help(row.help)
    }
}
