import ClaudeStatsCore
import SwiftUI

/// A headline figure. Not a chart: one number has no shape to see, and drawing it as one bar would
/// invite a comparison that does not exist.
struct BigNumberBlockView: View {
    let block: BlockConfig
    let events: [TranscriptEvent]

    private var value: Int {
        Aggregation.total(block.resolvedMetric, over: events, timeframe: block.timeframe, now: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.compact)
                .font(.system(size: 44, weight: .medium, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                // The exact figure is one hover away; the headline stays readable.
                .help(value.grouped)

            Text(block.resolvedMetric.title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
