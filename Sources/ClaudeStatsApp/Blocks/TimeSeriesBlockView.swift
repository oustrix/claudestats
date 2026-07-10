import Charts
import ClaudeStatsCore
import SwiftUI

/// Tokens over time, as bars: the data is a count per discrete bucket, not a continuous quantity,
/// and a line between two days would draw a value for the moment between them that never existed.
///
/// One series, so no legend — the block title names it. One hue, so no palette to validate.
struct TimeSeriesBlockView: View {
    let block: BlockConfig
    let events: [TranscriptEvent]

    @State private var selected: Date?

    private var points: [DataPoint] {
        let kept = Aggregation.filter(events, timeframe: block.timeframe, now: .now)
        return Aggregation.timeSeries(
            block.metric ?? .inputOutput, over: kept, bucket: block.bucket ?? .day, now: .now)
    }

    private var selectedPoint: DataPoint? {
        guard let selected else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected))
        }
    }

    var body: some View {
        Chart(points, id: \.date) { point in
            BarMark(
                x: .value("Date", point.date, unit: block.bucket == .hour ? .hour : .day),
                y: .value("Tokens", point.value)
            )
            .cornerRadius(3)
            .foregroundStyle(.tint)
            .opacity(selectedPoint == nil || selectedPoint?.date == point.date ? 1 : 0.35)
        }
        .chartXSelection(value: $selected)
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
        .overlay(alignment: .topTrailing) {
            if let selectedPoint {
                readout(for: selectedPoint)
            }
        }
    }

    private func readout(for point: DataPoint) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(point.date, format: block.bucket == .hour ? .dateTime.hour() : .dateTime.month().day())
                .foregroundStyle(.secondary)
            Text(point.value.grouped).monospacedDigit()
        }
        .font(.caption)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
