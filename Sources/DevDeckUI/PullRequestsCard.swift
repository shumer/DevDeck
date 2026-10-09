import DevDeckCore
import DevDeckEngine
import GitHubKit
import SwiftUI

public extension PullRequestHealth {
    var color: Color {
        switch self {
        case .blocked: return DeckTheme.red
        case .attention: return DeckTheme.amber
        case .ready: return DeckTheme.green
        }
    }
}

/// Pull requests: draws `PullRequestsCardModel`, which the engine has already decided.
public struct PullRequestsCard: View {
    /// Everything that is not a row: chrome, the count, the distribution bar and the footer.
    public nonisolated static let baseHeight: Double = 110

    private let model: PullRequestsCardModel
    private let onCommand: (DeckCommand) -> Void

    public init(model: PullRequestsCardModel, onCommand: @escaping (DeckCommand) -> Void = { _ in }) {
        self.model = model
        self.onCommand = onCommand
    }

    /// Panel size for the current contents. The app resizes the window with this, so the card
    /// and the panel never disagree about how much room the rows need.
    public nonisolated static func size(for model: PullRequestsCardModel) -> CGSize {
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
            CardChrome(title: model.title, glyph: model.mark.glyph, timestamp: model.timestamp) {
                if let content = model.content {
                    self.content(content)
                } else {
                    CardPlaceholderView(model.placeholder)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ content: PullRequestsCardModel.Content) -> some View {
        // The count is the hero, but 26 rather than the 42 it used to be: it was the largest
        // thing on the deck and it is not the most important one. It is also plain now. A number
        // that turns red when something is blocked says the same thing twice, since the words
        // beside it already say which and how many.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(content.count)")
                .font(.system(size: 26, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(DeckTheme.value.opacity(0.85))
            Text(content.unit)
                .font(.system(size: 12))
                .foregroundStyle(DeckTheme.label)
            Spacer(minLength: 6)
            if let pill = content.pill {
                StatusPill(pill)
            }
        }
        .frame(height: 30)
        .padding(.top, 6)

        healthBar(content.shares)

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

        CardFooter(content.footer)
    }

    /// How the open pull requests are spread across blocked, needs-attention and ready.
    ///
    /// Three points of height for the shape of the whole list, which the three visible rows
    /// cannot give: two blocked out of eight reads differently from two out of two.
    @ViewBuilder
    private func healthBar(_ shares: [PullRequestsCardModel.Share]) -> some View {
        if !shares.isEmpty {
            HStack(spacing: 2) {
                ForEach(Array(shares.enumerated()), id: \.offset) { _, share in
                    Capsule()
                        .fill(share.tone.color.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .layoutPriority(Double(share.count))
                }
            }
            .frame(height: 3)
            .padding(.top, 8)
        }
    }

    private func row(_ row: PullRequestsCardModel.Row) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(row.tone.color)
                .frame(width: 6, height: 6)
            if let account = row.account {
                AccountChip(account)
            }
            if let icon = row.icon {
                Image(systemName: icon.glyph.systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(icon.tone.color)
                    .help(icon.help ?? "")
            }
            if let key = row.key {
                Text(key)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeckTheme.value.opacity(0.55))
                    .fixedSize()
            }
            Text(row.title)
                .font(.system(size: 11.5))
                .foregroundStyle(DeckTheme.value.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(row.trailing)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(DeckTheme.value.opacity(0.58))
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
