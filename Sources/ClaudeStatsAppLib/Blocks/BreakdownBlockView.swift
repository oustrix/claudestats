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
        // The card packs rows tighter than the modal: a narrower label column, smaller type, and a
        // thinner bar, so a span-4 card shows its top-N without the modal's generous spacing.
        BreakdownRowList(
            rows: rows, barColor: theme.accent, valueColor: theme.sub, rowSpacing: 8, compact: true)
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
    /// The card draws compact rows; the modal draws full-size ones.
    var compact: Bool = false
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
                        barColor: barColor, valueColor: valueColor, compact: compact)
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
    /// Compact card sizing vs. the modal's roomier layout: a narrower label, smaller type, thinner bar.
    var compact: Bool = false
    @Environment(\.theme) private var theme

    private var labelWidth: CGFloat { compact ? 100 : 150 }
    private var barHeight: CGFloat { compact ? 12 : 14 }
    private var valueWidth: CGFloat { compact ? 52 : 60 }
    private var rowFont: Font { compact ? .system(size: 12) : .callout }
    @State private var hovering = false
    /// True when the label is wider than its column, so it is drawn truncated — the only case a
    /// name tooltip has anything to add.
    @State private var truncated = false

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
                .font(rowFont)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(theme.txt)
                .frame(width: labelWidth, alignment: .leading)
                // The full label's intrinsic width, measured off-screen, tells us whether the on-screen
                // one is truncated.
                .background(widthProbe)
                .onPreferenceChange(LabelWidthKey.self) { truncated = $0 > labelWidth + 0.5 }
                // A custom bubble rather than `.help`: the native tooltip only appears after the
                // system's multi-second hover delay, and this reveals the full name at once. It floats
                // above the row and is ignored for hit-testing, so it never eats the hover it depends on.
                .onHover { hovering = $0 }
                .overlay(alignment: .topLeading) {
                    if hovering && truncated {
                        NameTooltip(text: row.detail ?? row.label)
                            .offset(y: -30)
                            .allowsHitTesting(false)
                            .zIndex(1)
                    }
                }

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
            .frame(height: barHeight)

            Text(row.value.compact)
                .font(rowFont)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .help(row.value.grouped)
                .frame(width: valueWidth, alignment: .trailing)
        }
    }

    /// A hidden, unclipped copy of the label at its natural width; its measured width is published so
    /// the row can tell whether the visible, column-clipped label is truncated. `hidden()` keeps it
    /// out of the drawing, and it never affects layout because it lives in the label's `.background`.
    private var widthProbe: some View {
        Text(row.label)
            .font(rowFont)
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: LabelWidthKey.self, value: proxy.size.width)
                }
            )
            .allowsHitTesting(false)
    }
}

/// The measured natural width of a breakdown label, reported from the off-screen probe.
private struct LabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The instant hover bubble carrying a row's full name. Themed to sit above the dashboard's own
/// surfaces, self-sizing to one line.
private struct NameTooltip: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(theme.txt)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(theme.pill, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardB, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}
