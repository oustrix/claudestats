import ClaudeStatsCore
import SwiftUI

/// A GitHub-style calendar heatmap: a grid of squares shaded by activity intensity. Unlike
/// `TimeSeriesBlockView` it is not rasterised with `.drawingGroup()` — a static grid of rectangles
/// is cheap to redraw, and flattening it would kill the per-cell hover.
///
/// Colour is `.tint` at an opacity ramped by the cell's discrete level (1…4 → 0.25/0.5/0.75/1.0);
/// an empty cell is `.quaternary`, distinct from any lit level. The levels and cut points come from
/// the core's quantile binning, so a cache-read outlier cannot wash the scale out.
struct HeatmapBlockView: View {
    let block: BlockConfig
    let events: [TranscriptEvent]

    private var heatmap: Heatmap {
        Aggregation.heatmap(
            block.resolvedMetric, over: events, bucket: block.resolvedBucket, now: .now)
    }

    var body: some View {
        // The aggregation runs here and is handed down as a value, so hovering a cell — which lives
        // in the child's @State — re-renders only the child, never re-running the aggregation.
        HeatmapContent(map: heatmap, unit: block.resolvedMetric.countsTokens ? "tokens" : "requests")
    }
}

/// Owns the hover selection and lays out the grid, the legend and the floating tooltip. Split from
/// `HeatmapBlockView` so a hover cannot invalidate the aggregation above it.
///
/// A native tooltip (`.help`, and even an AppKit `toolTip`) never fired on cells this small, so the
/// value is shown in a GitHub-style bubble drawn just above the hovered cell. It is a single overlay
/// on the whole grid — positioned from the hovered cell's bounds anchor — so it floats over its
/// neighbours with no per-cell z-order fights.
private struct HeatmapContent: View {
    let map: Heatmap
    let unit: String
    @State private var hovered: HeatmapCell?
    @State private var bubbleSize: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if map.bucket == .week {
                WeekHeatmapGrid(cells: map.cells, hovered: $hovered)
            } else {
                DayHeatmapGrid(cells: map.cells, hovered: $hovered)
            }
            HeatmapLegend(thresholds: map.thresholds)
        }
        .overlayPreferenceValue(HoverAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, let cell = hovered {
                    let rect = proxy[anchor]
                    // Above the cell when there is room, otherwise flipped below; clamped so the
                    // bubble never spills past the grid's edges.
                    let above = rect.minY > bubbleSize.height + 10
                    let y =
                        above
                        ? rect.minY - 6 - bubbleSize.height / 2
                        : rect.maxY + 6 + bubbleSize.height / 2
                    let halfWidth = bubbleSize.width / 2
                    let x = min(max(rect.midX, halfWidth), proxy.size.width - halfWidth)
                    TooltipBubble(text: label(for: cell))
                        .background(
                            GeometryReader { bubble in
                                Color.clear.preference(
                                    key: BubbleSizeKey.self, value: bubble.size)
                            }
                        )
                        .position(x: x, y: y)
                }
            }
            .allowsHitTesting(false)
        }
        .onPreferenceChange(BubbleSizeKey.self) { bubbleSize = $0 }
        // The grid is a fixed width; center it so it sits in the middle of the card rather than
        // hugging the left edge with a wide gap to its right.
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func label(for cell: HeatmapCell) -> String {
        let day = cell.date.formatted(.dateTime.year().month(.abbreviated).day())
        let when = map.bucket == .week ? "Week of \(day)" : day
        return "\(when): \(cell.value.grouped) \(unit)"
    }
}

/// The floating value bubble. One line, self-sizing, over a material so it reads above the grid.
private struct TooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
    }
}

/// The bounds of the cell under the cursor, resolved by the grid's overlay to place the bubble.
private struct HoverAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// The measured size of the bubble, so the overlay can center and clamp it before it is placed.
private struct BubbleSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

// MARK: - Cell colour

/// The fill for an intensity level, straight off the theme's heat ramp: index 0 is an empty cell,
/// 1…4 the lit bands. A level past the ramp is clamped to its darkest/brightest end rather than
/// crashing on a bad index.
private func heatColor(_ level: Int, heat: [Color]) -> Color {
    guard !heat.isEmpty else { return .clear }
    return heat[min(max(level, 0), heat.count - 1)]
}

private let cellSize: CGFloat = 11
private let cellGap: CGFloat = 3

/// One square. On hover it becomes the selection and publishes its bounds, so the grid's overlay can
/// float the value bubble above it.
private struct HeatmapSquare: View {
    let cell: HeatmapCell
    let size: CGFloat
    @Binding var hovered: HeatmapCell?
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(heatColor(cell.level, heat: theme.heat))
            .frame(width: size, height: size)
            .onHover { inside in
                if inside {
                    hovered = cell
                } else if hovered == cell {
                    hovered = nil
                }
            }
            .anchorPreference(key: HoverAnchorKey.self, value: .bounds) {
                hovered == cell ? $0 : nil
            }
    }
}

// MARK: - Day grid — 7 weekday rows × 52 week columns

private struct DayHeatmapGrid: View {
    let cells: [HeatmapCell]
    @Binding var hovered: HeatmapCell?

    /// One column per week: the cells arrive in date order, seven to a week.
    private var columns: [[HeatmapCell]] { cells.chunked(by: 7) }

    var body: some View {
        let columns = columns
        // A static grid, sized to its content — no ScrollView: its elastic bounce let the grid be
        // dragged, and it swallowed the per-cell hover.
        HStack(alignment: .top, spacing: cellGap) {
            weekdayLabels(firstColumn: columns.first ?? [])
            VStack(alignment: .leading, spacing: cellGap) {
                monthLabels(columns: columns)
                HStack(alignment: .top, spacing: cellGap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: cellGap) {
                            ForEach(column, id: \.date) { cell in
                                HeatmapSquare(cell: cell, size: cellSize, hovered: $hovered)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Weekday names down the left, on alternate rows so they do not crowd. A fixed width, or the
    /// greedy `Color.clear` spacer below would balloon the column and shove the grid off to the right.
    private func weekdayLabels(firstColumn: [HeatmapCell]) -> some View {
        VStack(alignment: .trailing, spacing: cellGap) {
            Color.clear.frame(height: monthLabelHeight)  // aligns rows past the month labels
            ForEach(Array(firstColumn.enumerated()), id: \.offset) { row, cell in
                Text(row.isMultiple(of: 2) ? "" : cell.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .frame(height: cellSize)
            }
        }
        .frame(width: weekdayLabelWidth, alignment: .trailing)
    }

    /// A month abbreviation above the first column of each new month.
    private func monthLabels(columns: [[HeatmapCell]]) -> some View {
        HStack(alignment: .bottom, spacing: cellGap) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                Text(monthLabel(at: index, columns: columns) ?? "")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: cellSize, alignment: .leading)
            }
        }
        .frame(height: monthLabelHeight, alignment: .bottom)
    }

    /// The first day of a column carries the column's month; label it only when the month changes.
    private func monthLabel(at index: Int, columns: [[HeatmapCell]]) -> String? {
        guard let date = columns[index].first?.date else { return nil }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        if index > 0, let previous = columns[index - 1].first?.date,
            calendar.component(.month, from: previous) == month
        {
            return nil
        }
        return date.formatted(.dateTime.month(.abbreviated))
    }
}

private let monthLabelHeight: CGFloat = 12
private let weekdayLabelWidth: CGFloat = 26

// MARK: - Week grid — 13-week rows, a quarter per row, one cell per week

private struct WeekHeatmapGrid: View {
    let cells: [HeatmapCell]
    @Binding var hovered: HeatmapCell?

    private var rows: [[HeatmapCell]] { cells.chunked(by: 13) }

    var body: some View {
        VStack(alignment: .leading, spacing: cellGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: cellGap) {
                    ForEach(row, id: \.date) { cell in
                        HeatmapSquare(cell: cell, size: cellSize * 1.6, hovered: $hovered)
                    }
                }
            }
        }
    }
}

// MARK: - Legend

/// "Less ▢▢▢▢ More", one square per non-zero level actually in use. The number of bands follows the
/// cut points: with few distinct values the scale uses fewer levels, and so does its legend.
private struct HeatmapLegend: View {
    let thresholds: [Int]
    @Environment(\.theme) private var theme

    private var bands: Int { max(1, thresholds.count + 1) }

    var body: some View {
        HStack(spacing: cellGap) {
            Text("Less").font(.caption2).foregroundStyle(theme.mut)
            ForEach(1...bands, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(heatColor(level, heat: theme.heat))
                    .frame(width: cellSize, height: cellSize)
            }
            Text("More").font(.caption2).foregroundStyle(theme.mut)
        }
    }
}

extension Array {
    /// Consecutive chunks of at most `size`, the row/column grouping both heatmap grids lay out.
    fileprivate func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
