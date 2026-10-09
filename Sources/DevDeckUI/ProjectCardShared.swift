import DevDeckCore
import DevDeckEngine
import SwiftUI

/// The chip block: tooling, a divider, then the environments.
public struct ProjectChipRow: View {
    private let tools: [DeckProjectCardModel.Chip]
    private let environments: [DeckProjectCardModel.Chip]
    private let onCommand: (DeckCommand) -> Void

    public init(
        tools: [DeckProjectCardModel.Chip],
        environments: [DeckProjectCardModel.Chip],
        onCommand: @escaping (DeckCommand) -> Void
    ) {
        self.tools = tools
        self.environments = environments
        self.onCommand = onCommand
    }

    public var body: some View {
        // The divider is a subview like any other, so the layout is told which index it sits at
        // rather than being asked to work out what the chips mean.
        let breakBefore = CardChipFlow.breakIndex(
            tools: tools.map(\.label),
            environments: environments.map(\.label)
        )

        return CardChipLayout(breakBefore: breakBefore) {
            ForEach(tools) { chip in
                view(for: chip)
            }
            // Only when the two groups share a line. A break says the same thing, and better.
            if breakBefore == nil, !tools.isEmpty, !environments.isEmpty {
                CardChipDivider()
            }
            ForEach(environments) { chip in
                view(for: chip)
            }
        }
        .padding(.top, CardChipFlow.topPadding)
    }

    private func view(for chip: DeckProjectCardModel.Chip) -> some View {
        CardChip(chip.label, color: Self.colour(for: chip.kind), isDimmed: chip.isDimmed, help: chip.help) {
            guard let command = chip.command else { return }
            onCommand(command)
        }
    }

    /// Production is the one worth a beat of hesitation, so it is the one that is not calm.
    public nonisolated static func colour(for kind: DeckProjectCardModel.Chip.Kind) -> Color {
        switch kind {
        case .tool: return DeckTheme.blue
        case .local: return DeckTheme.green
        case .production: return DeckTheme.amber
        case .environment: return DeckTheme.violet
        }
    }
}

/// The height arithmetic every project card shares.
///
/// One place, because three cards and the panel that hosts them have to agree on it exactly: a
/// disagreement shows up as a clipped control row or a strip of empty glass.
public enum ProjectCardMetrics {
    public nonisolated static func height(
        tools: [String],
        environments: [String],
        hasBranch: Bool,
        hasMetaRow: Bool
    ) -> Double {
        CardChromeMetrics.topPadding
            + CardChromeMetrics.headerHeight
            + CardHeroRow.topPadding + CardHeroRow.height
            + CardMetaBlock.height(hasBranch: hasBranch, hasRow: hasMetaRow)
            + CardChipFlow.height(tools: tools, environments: environments)
            + CardActionRow.height
            + CardChromeMetrics.bottomPadding
    }
}
