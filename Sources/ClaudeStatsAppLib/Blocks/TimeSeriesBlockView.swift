import Charts
import ClaudeStatsCore
import SwiftUI

/// Tokens over time, as bars: the data is a count per discrete bucket, not a continuous quantity,
/// and a line between two days would draw a value for the moment between them that never existed.
///
/// One series, so no legend — the block title names it. One hue, so no palette to validate.
///
/// The chart is rasterised with `.drawingGroup()`. A Swift Charts view is redrawn from its vectors
/// on every frame it moves, which stutters a scroll; drawn into a texture once, it scrolls as a flat
/// image. There is no per-bar hover, so nothing interactive is lost by flattening it.
struct TimeSeriesBlockView: View {
    let block: BlockConfig
    let events: [TranscriptEvent]
    @Environment(\.theme) private var theme

    private var points: [DataPoint] {
        Aggregation.timeSeries(
            block.resolvedMetric, over: events, bucket: block.resolvedBucket,
            timeframe: block.timeframe, now: .now)
    }

    var body: some View {
        Chart(points, id: \.date) { point in
            BarMark(
                x: .value("Date", point.date, unit: block.resolvedBucket == .hour ? .hour : .day),
                y: .value("Tokens", point.value)
            )
            .cornerRadius(3)
            .foregroundStyle(theme.bar)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(theme.grid)
                AxisValueLabel {
                    if let tokens = value.as(Int.self) {
                        Text(tokens.compact).foregroundStyle(theme.mut)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned) {
                AxisGridLine().foregroundStyle(theme.grid)
                AxisTick().foregroundStyle(theme.grid)
                AxisValueLabel().foregroundStyle(theme.mut)
            }
        }
        .frame(height: 180)
        // Note: `.drawingGroup()` was dropped here. Its offscreen buffer does not reliably inherit
        // the app's forced-dark colour scheme, which risks light-mode axis labels on the dark card.
        // The chart is small enough to redraw as vectors; the human verifies the render visually.
    }
}
