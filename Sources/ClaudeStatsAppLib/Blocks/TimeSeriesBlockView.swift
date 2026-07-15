import Charts
import ClaudeStatsCore
import SwiftUI

/// Tokens over time, as bars: the data is a count per discrete bucket, not a continuous quantity,
/// and a line between two days would draw a value for the moment between them that never existed.
///
/// One series, so no legend — the block title names it. One hue, so no palette to validate.
///
/// Hover a bar for its exact value. The lesson the heatmap taught applies here: a Swift Charts view
/// re-vectorises every mark whenever the view holding it re-renders, so hover state kept beside the
/// chart stutters a scroll. Instead the aggregation runs here and is handed down as a value, and hover
/// lives in `BarHoverLayer` inside the chart overlay — a hover redraws only its bubble, never the bars.
struct TimeSeriesBlockView: View {
    let block: BlockConfig
    let events: [TranscriptEvent]

    private var points: [DataPoint] {
        Aggregation.timeSeries(
            block.resolvedMetric, over: events, bucket: block.resolvedBucket,
            timeframe: block.timeframe, now: .now)
    }

    var body: some View {
        TimeSeriesContent(
            points: points, bucket: block.resolvedBucket,
            unit: block.resolvedMetric.countsTokens ? "tokens" : "requests")
    }
}

/// Draws the chart and its axes, and hangs the hover layer over the plot. No hover `@State` lives here,
/// so its `body` runs only when the data changes — never on a hover, so the bars are not re-vectorised.
private struct TimeSeriesContent: View {
    let points: [DataPoint]
    let bucket: Bucket
    let unit: String
    @Environment(\.theme) private var theme

    var body: some View {
        Chart(points, id: \.date) { point in
            BarMark(
                x: .value("Date", point.date, unit: bucket == .hour ? .hour : .day),
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
        .chartOverlay { proxy in
            // The overlay closure re-runs only when this view's body does (data changes), so the bar
            // geometry is captured once here, not on every hover. `BarHoverLayer` owns the hover state.
            GeometryReader { geo in
                BarHoverLayer(
                    size: geo.size,
                    locate: locate(proxy: proxy, geo: geo),
                    label: { timeSeriesLabel(for: $0, bucket: bucket, unit: unit) })
            }
        }
        .frame(height: 180)
        // Note: `.drawingGroup()` is deliberately not used. Its offscreen buffer does not reliably
        // inherit the app's forced-dark colour scheme (risking light-mode axis labels on the dark
        // card), and it would flatten away the hover layer. The chart is small enough to redraw as
        // vectors on data changes; hover no longer forces those redraws.
    }

    /// Maps a pointer in the overlay's local space to the bar under it and that bar's anchor rect, by
    /// pure grid geometry — the same lattice trick the heatmap uses. The bars are evenly spaced buckets
    /// across the plot, so the column is plain division (`barSlotIndex`); the bar's top comes from the
    /// value scale so the bubble floats just above it.
    private func locate(proxy: ChartProxy, geo: GeometryProxy) -> (CGPoint) -> BarTarget? {
        guard !points.isEmpty, let anchor = proxy.plotFrame else { return { _ in nil } }
        let plot = geo[anchor]
        let slot = plot.width / CGFloat(points.count)
        return { pointer in
            guard pointer.y >= plot.minY, pointer.y <= plot.maxY,
                let index = barSlotIndex(
                    x: pointer.x, plotMinX: plot.minX, slotWidth: slot, count: points.count)
            else { return nil }
            let point = points[index]
            let top = plot.minY + (proxy.position(forY: point.value) ?? 0)
            let rect = CGRect(
                x: plot.minX + CGFloat(index) * slot, y: top,
                width: slot, height: max(0, plot.maxY - top))
            return BarTarget(point: point, rect: rect)
        }
    }
}

/// The bar under the cursor and its rect in the overlay's local space — the horizontal slot (so a
/// cursor in the gap between bars still tracks the nearer bar) from the bar's top down to the baseline.
private struct BarTarget: Equatable {
    let point: DataPoint
    let rect: CGRect
}

/// The index of the bar whose slot contains `x`, for `count` equal-width slots spanning
/// `[plotMinX, plotMinX + count·slotWidth)`; `nil` outside the band. Pure, so it is unit-tested.
func barSlotIndex(x: CGFloat, plotMinX: CGFloat, slotWidth: CGFloat, count: Int) -> Int? {
    guard count > 0, slotWidth > 0 else { return nil }
    guard x >= plotMinX, x < plotMinX + slotWidth * CGFloat(count) else { return nil }
    return min(max(Int((x - plotMinX) / slotWidth), 0), count - 1)
}

/// The tooltip line for a bar: the bucket's start and the exact value, e.g.
/// "Jul 15, 2026: 1,234,567 tokens". Hour buckets add the hour so two bars on one day read apart. The
/// year is kept because an all-time chart spans years, where a bare "Jul 15" would be ambiguous.
func timeSeriesLabel(for point: DataPoint, bucket: Bucket, unit: String) -> String {
    let date =
        bucket == .hour
        ? point.date.formatted(.dateTime.year().month(.abbreviated).day().hour())
        : point.date.formatted(.dateTime.year().month(.abbreviated).day())
    return "\(date): \(point.value.grouped) \(unit)"
}

/// One hover tracker for the whole plot. Like the heatmap's grid hover: a single `onContinuousHover`
/// reads the pointer and `locate` maps it to a bar by geometry, so a hover touches only this small
/// overlay — never the bars. It owns the hover state, keeping it off the chart-bearing view above.
private struct BarHoverLayer: View {
    let size: CGSize
    let locate: (CGPoint) -> BarTarget?
    let label: (DataPoint) -> String
    @State private var hovered: BarTarget?
    @State private var bubbleSize: CGSize = .zero

    var body: some View {
        // A clear, rectangular hit shape over the plot so the gaps between bars still track. It carries
        // no gesture, so the dashboard's scroll wheel passes straight through it.
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let pointer):
                    let target = locate(pointer)
                    // Publish only when the bar changes: the pointer fires many times within one bar,
                    // and each write would redraw the bubble's material for no visible change.
                    if target?.point != hovered?.point { hovered = target }
                case .ended:
                    hovered = nil
                }
            }
            .overlay {
                if let hovered {
                    TooltipBubble(text: label(hovered.point))
                        .measuredSize(into: $bubbleSize)
                        .position(
                            tooltipPosition(target: hovered.rect, bubbleSize: bubbleSize, in: size))
                        .allowsHitTesting(false)
                }
            }
    }
}
