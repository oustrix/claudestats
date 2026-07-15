import ClaudeStatsCore
import SwiftUI

/// A GitHub-style calendar heatmap: a grid of squares shaded by activity intensity. Unlike
/// `TimeSeriesBlockView` it is not rasterised with `.drawingGroup()` — a static grid of rectangles
/// is cheap to redraw, and flattening it would kill the hover overlay.
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
        // The aggregation runs here and is handed down as a value, so hover state — which lives in the
        // grid below — re-renders only its own tooltip overlay, never re-running the aggregation.
        HeatmapContent(map: heatmap, unit: block.resolvedMetric.countsTokens ? "tokens" : "requests")
    }
}

/// Lays out the grid and the legend. Hover — and the floating value bubble — is owned by the grid
/// below via `HeatmapGridHover`, not here: pointer tracking lives on the cell region, so this view is
/// a plain, hover-agnostic stack.
private struct HeatmapContent: View {
    let map: Heatmap
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if map.bucket == .week {
                WeekHeatmapGrid(cells: map.cells, label: label(for:))
            } else {
                DayHeatmapGrid(cells: map.cells, label: label(for:))
            }
            HeatmapLegend(thresholds: map.thresholds)
        }
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

/// One hover tracker for a whole cell grid. The per-cell approach — a tracking area and a bounds
/// anchor on each of the hundreds of squares — made every square re-render on each hover, so a scroll
/// that swept the cursor across the grid fired a storm of full-grid re-renders (measured: ~28k square
/// body evaluations in a few seconds). Here a single `onContinuousHover` reads the pointer and
/// `locate` maps it to the cell and that cell's rect by pure grid geometry. The bubble is an overlay
/// in the same local space, so a hover touches only this modifier's small overlay — never the cells.
private struct HeatmapGridHover: ViewModifier {
    let label: (HeatmapCell) -> String
    let locate: (CGPoint) -> HoverTarget?
    @State private var hovered: HoverTarget?
    @State private var bubbleSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            // A rectangular hit shape so the gaps between cells still track — otherwise a pointer in a
            // gap reads as "outside" and the bubble flickers off between adjacent cells.
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    let target = locate(point)
                    // Publish only when the cell changes: the pointer fires many times inside one
                    // cell, and each write would redraw the bubble's material for no visible change.
                    if target?.cell != hovered?.cell { hovered = target }
                case .ended:
                    hovered = nil
                }
            }
            .overlay {
                GeometryReader { proxy in
                    if let hovered {
                        let rect = hovered.rect
                        // Above the cell when there is room, otherwise flipped below; clamped so the
                        // bubble never spills past the grid's edges.
                        let above = rect.minY > bubbleSize.height + 10
                        let y =
                            above
                            ? rect.minY - 6 - bubbleSize.height / 2
                            : rect.maxY + 6 + bubbleSize.height / 2
                        let halfWidth = bubbleSize.width / 2
                        let x = min(max(rect.midX, halfWidth), proxy.size.width - halfWidth)
                        TooltipBubble(text: label(hovered.cell))
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
    }
}

/// The cell under the cursor and its rectangle in the grid's local space, from grid geometry.
private struct HoverTarget: Equatable {
    let cell: HeatmapCell
    let rect: CGRect
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

/// One cell: a plain coloured square. Hover for the whole grid is tracked by `HeatmapGridHover`, so a
/// square carries no tracking area or state of its own and never re-renders on a hover.
private struct HeatmapSquare: View {
    let cell: HeatmapCell
    let size: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(heatColor(cell.level, heat: theme.heat))
            .frame(width: size, height: size)
    }
}

// MARK: - Day grid — 7 weekday rows × 52 week columns

private struct DayHeatmapGrid: View {
    let cells: [HeatmapCell]
    let label: (HeatmapCell) -> String

    /// One column per week: the cells arrive in date order, seven to a week.
    private var columns: [[HeatmapCell]] { cells.chunked(by: 7) }

    var body: some View {
        let columns = columns
        // A static grid, sized to its content — no ScrollView: its elastic bounce let the grid be
        // dragged, and it swallowed the hover.
        HStack(alignment: .top, spacing: cellGap) {
            weekdayLabels(firstColumn: columns.first ?? [])
            VStack(alignment: .leading, spacing: cellGap) {
                monthLabels(columns: columns)
                HStack(alignment: .top, spacing: cellGap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: cellGap) {
                            ForEach(column, id: \.date) { cell in
                                HeatmapSquare(cell: cell, size: cellSize)
                            }
                        }
                    }
                }
                .modifier(HeatmapGridHover(label: label, locate: locate(columns: columns)))
            }
        }
    }

    /// Maps a pointer in the cell grid's local space to the week column and weekday row it falls in —
    /// the grid is a fixed lattice of `cellSize` squares on a `cellGap` pitch, so it is plain division.
    private func locate(columns: [[HeatmapCell]]) -> (CGPoint) -> HoverTarget? {
        { point in
            let step = cellSize + cellGap
            guard point.x >= 0, point.y >= 0 else { return nil }
            let col = Int(point.x / step)
            let row = Int(point.y / step)
            guard col < columns.count, row < columns[col].count else { return nil }
            let rect = CGRect(
                x: CGFloat(col) * step, y: CGFloat(row) * step, width: cellSize, height: cellSize)
            return HoverTarget(cell: columns[col][row], rect: rect)
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
    let label: (HeatmapCell) -> String

    /// A week cell is bigger than a day cell: one per week reads better enlarged.
    private static let size = cellSize * 1.6

    private var rows: [[HeatmapCell]] { cells.chunked(by: 13) }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: cellGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: cellGap) {
                    ForEach(row, id: \.date) { cell in
                        HeatmapSquare(cell: cell, size: Self.size)
                    }
                }
            }
        }
        .modifier(HeatmapGridHover(label: label, locate: locate(rows: rows)))
    }

    /// Maps a pointer in the grid's local space to the quarter row and the week within it.
    private func locate(rows: [[HeatmapCell]]) -> (CGPoint) -> HoverTarget? {
        { point in
            let step = Self.size + cellGap
            guard point.x >= 0, point.y >= 0 else { return nil }
            let col = Int(point.x / step)
            let row = Int(point.y / step)
            guard row < rows.count, col < rows[row].count else { return nil }
            let rect = CGRect(
                x: CGFloat(col) * step, y: CGFloat(row) * step, width: Self.size, height: Self.size)
            return HoverTarget(cell: rows[row][col], rect: rect)
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
