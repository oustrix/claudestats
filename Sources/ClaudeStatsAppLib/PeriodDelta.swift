import ClaudeStatsCore
import Foundation

/// The fractional change of a metric's current-timeframe total against the immediately preceding
/// window of equal length — the "▲ 18% vs prev." a KPI card shows. `0.18` means an 18% increase,
/// `-0.5` a halving. Returns `nil` when there is no honest comparison to draw:
///
/// - an unbounded timeframe (`allTime`) has no preceding window;
/// - a preceding total of zero would make the change infinite, so no arrow is shown.
///
/// Composed from `Aggregation.total`, never a new counting rule. `Aggregation.filter` bounds a
/// window only from below (it assumes `now` is the present), so the preceding window is not a single
/// shifted call: summing over `now` shifted back by the window length yields *both* windows, and the
/// current total is subtracted off to isolate the preceding one. This is exact because transcripts
/// hold no events later than `now`.
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
