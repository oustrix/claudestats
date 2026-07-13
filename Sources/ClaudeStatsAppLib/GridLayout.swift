import ClaudeStatsCore
import SwiftUI

/// The number of columns the dashboard grid spans. The same "full width" fact `BlockConfig.fullSpan`
/// encodes for the migration default, sourced once so the layout math and the decode default cannot
/// drift apart.
let gridColumns = BlockConfig.fullSpan

/// Coerces a raw span into 1…`gridColumns`. A hand-edited `layout.json` can hold a nonsense span; a
/// block should still draw, so an out-of-range value is clamped rather than crashing the layout.
func clampSpan(_ span: Int) -> Int { min(max(span, 1), gridColumns) }

/// Greedily packs block spans into rows of at most twelve columns, returning the block indices per
/// row. Walks the blocks in the authored order, adding each to the current row while the running
/// sum stays within twelve and starting a new row when the next block would overflow. Order is
/// preserved: the layout never reorders blocks to pack a gap, because the user's order is the point.
///
/// A pure function of the spans alone, so the packing is testable without a view. Spans are clamped
/// to 1…12 first (the shared `clampSpan`), so a block never demands more than a full row.
func packRows(spans: [Int]) -> [[Int]] {
    var rows: [[Int]] = []
    var current: [Int] = []
    var used = 0

    for (index, rawSpan) in spans.enumerated() {
        let span = clampSpan(rawSpan)
        if !current.isEmpty && used + span > gridColumns {
            rows.append(current)
            current = []
            used = 0
        }
        current.append(index)
        used += span
    }
    if !current.isEmpty { rows.append(current) }
    return rows
}

/// The point width of a `span`-column block on a grid `total` points wide with `spacing` between
/// columns. The twelve-column grid has eleven gutters; one column is `unit`, and a `span`-wide block
/// covers `span` columns plus the `span - 1` gutters it spans over — so a full row of three span-4
/// blocks (with two gaps between them) sums back to exactly `total`. Never negative, so a zero-width
/// first layout pass does not hand a view a negative frame.
func columnWidth(total: CGFloat, spacing: CGFloat, span: Int) -> CGFloat {
    let span = clampSpan(span)
    let unit = (total - spacing * CGFloat(gridColumns - 1)) / CGFloat(gridColumns)
    return max(0, unit * CGFloat(span) + spacing * CGFloat(span - 1))
}

/// Each block's span, attached to its view so the `GridFlowLayout` can read it back. Defaults to a
/// full row, matching `BlockConfig`'s decode default.
private struct SpanLayoutKey: LayoutValueKey {
    static let defaultValue = BlockConfig.fullSpan
}

extension View {
    /// Tags a block with the number of grid columns it should occupy.
    func gridSpan(_ span: Int) -> some View { layoutValue(key: SpanLayoutKey.self, value: span) }
}

/// Lays blocks out on the twelve-column grid: greedy row packing by span, each block sized to its
/// columns, rows stacked top to bottom. A real `Layout` rather than a measured-width feedback loop —
/// it reads the container width straight off the layout proposal, so there is no one-frame lag and no
/// zero-width first pass, and it reports a true intrinsic height so it composes inside a `ScrollView`.
/// The packing and column arithmetic are the same pure `packRows`/`columnWidth` the unit tests pin.
struct GridFlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 16

    private func spans(_ subviews: LayoutSubviews) -> [Int] {
        subviews.map { clampSpan($0[SpanLayoutKey.self]) }
    }

    /// The height of one packed row: the tallest of its blocks, each measured at the width its span
    /// earns on a grid `width` points wide.
    private func rowHeight(_ row: [Int], subviews: LayoutSubviews, width: CGFloat) -> CGFloat {
        row.map { index in
            let w = columnWidth(total: width, spacing: spacing, span: subviews[index][SpanLayoutKey.self])
            return subviews[index].sizeThatFits(.init(width: w, height: nil)).height
        }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = packRows(spans: spans(subviews))
        let heights = rows.map { rowHeight($0, subviews: subviews, width: width) }
        let total = heights.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: total)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void
    ) {
        let rows = packRows(spans: spans(subviews))
        var y = bounds.minY
        for row in rows {
            let height = rowHeight(row, subviews: subviews, width: bounds.width)
            var x = bounds.minX
            for index in row {
                let w = columnWidth(total: bounds.width, spacing: spacing, span: subviews[index][SpanLayoutKey.self])
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: .init(width: w, height: height))
                x += w + spacing
            }
            y += height + spacing
        }
    }
}
