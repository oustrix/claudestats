import ClaudeStatsCore
import SwiftUI

/// A ranked list with a bar behind each row. Horizontal, because the labels are words: a vertical
/// bar chart would turn `claude-haiku-4-5-20251001` into a tilted, unreadable axis.
///
/// The bar is drawn as a proportion of the largest row, so the eye compares lengths rather than
/// reading numbers. One hue for every row: rank is already encoded by position, and painting rank
/// with colour would repaint the survivors whenever a filter changed the order.
struct BreakdownBlockView: View {
    let block: BlockConfig
    let events: [TranscriptEvent]
    let home: String

    private var rows: [BreakdownRow] {
        let kept = Aggregation.filter(events, timeframe: block.timeframe, now: .now)
        return Aggregation.breakdown(
            block.dimension ?? .model, metric: block.metric ?? .inputOutput, over: kept,
            limit: block.limit ?? 8, home: home)
    }

    var body: some View {
        let rows = rows
        let largest = rows.first?.value ?? 0

        if rows.isEmpty {
            Text("Nothing in this timeframe").font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 6) {
                ForEach(rows, id: \.label) { row in
                    HStack(spacing: 12) {
                        Text(row.label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(row.detail ?? row.label)
                            .frame(width: 150, alignment: .leading)

                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.tint)
                                .frame(
                                    width: largest > 0
                                        ? max(2, geometry.size.width * CGFloat(row.value) / CGFloat(largest))
                                        : 0)
                        }
                        .frame(height: 14)

                        Text(row.value.compact)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .help(row.value.grouped)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
    }
}
