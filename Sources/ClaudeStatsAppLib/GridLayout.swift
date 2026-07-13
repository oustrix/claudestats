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
