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
    @Environment(\.theme) private var theme

    private var rows: [BreakdownRow] {
        Aggregation.breakdown(
            block.resolvedDimension, metric: block.resolvedMetric, over: events,
            limit: block.resolvedLimit, home: home, timeframe: block.timeframe, now: .now)
    }

    var body: some View {
        BreakdownRowList(rows: rows, barColor: theme.accent, valueColor: theme.sub)
    }
}

/// The ranked list of breakdown rows shared by the card and its expand-modal, so the row layout, the
/// bar-width maths and the empty-state message live in one place. The two callers differ only in the
/// optional rank column and which theme tokens paint the bar and value.
struct BreakdownRowList: View {
    let rows: [BreakdownRow]
    let barColor: Color
    let valueColor: Color
    /// The detail modal numbers its rows; the card does not.
    var ranked: Bool = false
    var rowSpacing: CGFloat = 6
    @Environment(\.theme) private var theme

    var body: some View {
        if rows.isEmpty {
            Text("Nothing in this timeframe").font(.callout).foregroundStyle(theme.sub)
        } else {
            // Rows arrive sorted descending, so the first is the largest and the bars are drawn as a
            // proportion of it.
            let largest = rows.first?.value ?? 0
            VStack(spacing: rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.element.label) { index, row in
                    BreakdownRowView(
                        row: row, largest: largest, rank: ranked ? index + 1 : nil,
                        barColor: barColor, valueColor: valueColor)
                }
            }
        }
    }
}

/// One breakdown row: an optional rank, a truncating label, a proportional bar, and the value. The
/// bar is drawn as a fraction of the list's largest row so the eye compares lengths, not numbers.
struct BreakdownRowView: View {
    let row: BreakdownRow
    let largest: Int
    var rank: Int? = nil
    let barColor: Color
    let valueColor: Color
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(theme.faint)
                    .frame(width: 24, alignment: .trailing)
            }

            Text(row.label)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(theme.txt)
                .help(row.detail ?? row.label)
                .frame(width: 150, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(theme.track)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(
                            width: largest > 0
                                ? max(2, geometry.size.width * CGFloat(row.value) / CGFloat(largest))
                                : 0)
                }
            }
            .frame(height: 14)

            Text(row.value.compact)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .help(row.value.grouped)
                .frame(width: 60, alignment: .trailing)
        }
    }
}
