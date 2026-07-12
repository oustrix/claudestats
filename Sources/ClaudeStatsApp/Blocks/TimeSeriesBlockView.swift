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
            .foregroundStyle(.tint)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let tokens = value.as(Int.self) { Text(tokens.compact) }
                }
            }
        }
        .chartXAxis { AxisMarks(preset: .aligned) }
        .frame(height: 180)
        .drawingGroup()
    }
}
