import ClaudeStatsCore
import Foundation

/// The fractional change of a metric's current-timeframe total against the immediately preceding
/// window of equal length — the "▲ 18% vs prev." a KPI card shows. `0.18` means an 18% increase,
/// `-0.5` a halving. Returns `nil` when there is no honest comparison to draw:
///
/// - an unbounded timeframe (`allTime`) has no preceding window;
/// - a preceding total of zero would make the change infinite, so no arrow is shown.
///
/// Composed from `Aggregation.total`, never a new counting rule. The composition leans on one
/// load-bearing property of `Aggregation.filter`: it bounds a window only from *below*, never from
/// above. So a single shifted call cannot isolate the preceding window — summing over `now` shifted
/// back by the window length yields *both* windows nested, and the current total is subtracted off
/// to leave the preceding one. Because the earlier call's window strictly contains the later one,
/// the subtraction is exact regardless of any events dated after `now`. Should `filter` ever gain an
/// upper bound, the two windows become disjoint and this subtraction must be revisited (see the note
/// on `Aggregation.filter`).
func periodDelta(
    _ metric: Metric, over events: [TranscriptEvent], timeframe: Timeframe, now: Date,
    calendar: Calendar = .current
) -> Double? {
    guard let days = timeframe.days else { return nil }

    let current = Aggregation.total(
        metric, over: events, timeframe: timeframe, now: now, calendar: calendar)

    guard let priorNow = calendar.date(byAdding: .day, value: -days, to: now) else { return nil }
    let currentAndPrior = Aggregation.total(
        metric, over: events, timeframe: timeframe, now: priorNow, calendar: calendar)
    let previous = currentAndPrior - current

    guard previous > 0 else { return nil }
    return Double(current - previous) / Double(previous)
}
