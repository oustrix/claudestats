import ClaudeStatsCore
import SwiftUI

/// A headline figure as a KPI card: a large tabular number, a small timeframe pill, and a delta
/// against the immediately preceding equal-length window. Not a chart — one number has no shape to
/// see, and drawing it as one bar would invite a comparison that does not exist. The delta is that
/// comparison, drawn as a word rather than a shape.
struct BigNumberBlockView: View {
    let block: BlockConfig
    let events: [TranscriptEvent]
    @Environment(\.theme) private var theme

    private var value: Int {
        Aggregation.total(block.resolvedMetric, over: events, timeframe: block.timeframe, now: .now)
    }

    /// The fractional change vs. the preceding window, or `nil` when there is no honest one to show
    /// (an unbounded timeframe, or a preceding total of zero).
    private var delta: Double? {
        periodDelta(block.resolvedMetric, over: events, timeframe: block.timeframe, now: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(block.timeframe.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.mut)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(theme.pill, in: Capsule())

            Text(value.compact)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.txt)
                .contentTransition(.numericText())
                // The exact figure is one hover away; the headline stays readable.
                .help(value.grouped)

            Text(block.resolvedMetric.title)
                .font(.callout)
                .foregroundStyle(theme.sub)

            if let delta { deltaLabel(delta) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "▲ 18% vs prev." A rise is `theme.pos`; a fall is muted, so the eye reads direction from the
    /// colour as well as the arrow.
    private func deltaLabel(_ delta: Double) -> some View {
        let up = delta >= 0
        let percent = abs(delta).formatted(.percent.precision(.fractionLength(0)))
        return Text("\(up ? "▲" : "▼") \(percent) vs prev.")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(up ? theme.pos : theme.mut)
    }
}
