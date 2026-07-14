import ClaudeStatsCore
import SwiftUI

/// The cost estimate as a KPI card: a large accent-coloured currency figure with a plain reminder
/// that it is an estimate, not a bill. Mirrors `BigNumberBlockView`'s chrome, but the number is
/// dollars derived per model from the pricing, not a token count — so it reads in `theme.accent` and
/// carries no period-over-period delta (a dollar drift is the token drift, already shown next door).
struct CostBlockView: View {
    let block: BlockConfig
    let events: [TranscriptEvent]
    let pricing: Pricing
    @Environment(\.theme) private var theme

    var body: some View {
        let estimate = Aggregation.cost(
            over: events, pricing: pricing, timeframe: block.timeframe, now: .now)
        VStack(alignment: .leading, spacing: 8) {
            Text(block.timeframe.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.mut)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(theme.pill, in: Capsule())

            Text(estimate.total.currency)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.accent)
                .contentTransition(.numericText())

            Text("estimate · not a bill")
                .font(.callout)
                .foregroundStyle(theme.sub)

            // Never lie silently: a model with no rate is named, not folded into the total as $0.
            if !estimate.unpricedModels.isEmpty {
                Text("\(estimate.unpricedModels.count) model(s) unpriced")
                    .font(.caption)
                    .foregroundStyle(theme.mut)
                    .help(estimate.unpricedModels.sorted().joined(separator: ", "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
