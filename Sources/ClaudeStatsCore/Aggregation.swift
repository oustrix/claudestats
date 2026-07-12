import Foundation

/// Anything that happened at a moment in time, and can therefore be filtered by timeframe.
public protocol Timestamped {
    var timestamp: Date { get }
}

extension TranscriptEvent: Timestamped {}
extension Message: Timestamped {}

/// One point of a time series: the start of a bucket, and the metric's value within it.
public struct DataPoint: Equatable, Sendable {
    public let date: Date
    public let value: Int
}

/// One cell of a heatmap: the start of its bucket, the metric's value within it, and the discrete
/// intensity level (0 for empty, 1…4 by quantile) the view shades it with.
public struct HeatmapCell: Equatable, Sendable {
    public let date: Date
    public let value: Int
    public let level: Int
}

/// A calendar heatmap over the fixed 52-week window: dense, zero-filled cells plus the quantile cut
/// points a legend needs. `bucket` is the resolved granularity (`day` or `week`), never `hour`.
public struct Heatmap: Equatable, Sendable {
    public let cells: [HeatmapCell]
    public let bucket: Bucket
    /// The up to three quantile cut points between non-zero levels, ascending. Empty when there is
    /// at most one distinct non-zero value (a single lit level needs no legend divisions).
    public let thresholds: [Int]
}

/// One row of a breakdown: what it is, where it lives, and how much of the metric it accounts for.
public struct BreakdownRow: Equatable, Sendable {
    public let label: String
    /// Secondary text. Carries the abbreviated path for projects; `nil` otherwise.
    public let detail: String?
    public let value: Int
}

/// Pure functions from transcript events to the numbers a block draws. No UI, no I/O, no caching:
/// at a few thousand events, recomputing is cheaper than remembering.
///
/// Every entry point takes raw events and both windows them by timeframe and performs the
/// message/block split itself. A caller states the timeframe but never holds a `Message` or a
/// pre-filtered array, so it cannot window against the wrong clock or apply a counting rule to the
/// wrong collection. `now` is consulted only for a bounded timeframe, so an `.allTime` aggregation
/// ignores it.
public enum Aggregation {
    /// Timeframes are whole local calendar days, not rolling 24-hour windows: "the last 7 days"
    /// means today and the six days before it, whatever the hour.
    public static func filter<T: Timestamped>(
        _ items: [T], timeframe: Timeframe, now: Date, calendar: Calendar = .current
    ) -> [T] {
        guard let days = timeframe.days else { return items }
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return items
        }
        return items.filter { $0.timestamp >= start }
    }

    public static func total(
        _ metric: Metric, over events: [TranscriptEvent],
        timeframe: Timeframe, now: Date = .distantPast, calendar: Calendar = .current
    ) -> Int {
        sum(metric, over: filter(events, timeframe: timeframe, now: now, calendar: calendar))
    }

    /// One point per bucket across the whole span, including buckets with no activity — a gap must
    /// read as zero, not as two distant days drawn side by side.
    public static func timeSeries(
        _ metric: Metric, over events: [TranscriptEvent], bucket: Bucket,
        timeframe: Timeframe, now: Date = .distantPast, calendar: Calendar = .current
    ) -> [DataPoint] {
        let messages = Counting.messages(
            from: filter(events, timeframe: timeframe, now: now, calendar: calendar))
        let totals = bucketTotals(messages, metric: metric, bucket: bucket, calendar: calendar)
        guard let first = totals.keys.min(), let last = totals.keys.max() else { return [] }

        return denseDates(from: first, through: last, bucket: bucket, calendar: calendar)
            .map { DataPoint(date: $0, value: totals[$0] ?? 0) }
    }

    /// The number of whole weeks the heatmap window spans, GitHub-style. Fixed: a configurable
    /// window is mostly a way to make the grid ugly.
    public static let heatmapWeeks = 52

    /// A dense calendar grid over the last 52 weeks: one cell per bucket (`day` or `week`),
    /// zero-filled across gaps, each carrying a quantile intensity level. The window ignores any
    /// timeframe and is aligned to whole local weeks ending with the week containing `now`; `now`
    /// and `calendar` are supplied, never read from the clock. A bucket other than `week` is treated
    /// as `day` — a hand-edited `.hour` heatmap is drawn by day, not refused.
    ///
    /// The sum of the cell values equals `total` for the same metric over the same day range, the
    /// same reconciliation the daily time series already guarantees.
    public static func heatmap(
        _ metric: Metric, over events: [TranscriptEvent], bucket rawBucket: Bucket,
        now: Date, calendar: Calendar = .current
    ) -> Heatmap {
        let bucket: Bucket = rawBucket == .week ? .week : .day

        // A clean rectangle of 52 week-columns ending with the week containing `now`.
        let currentWeekStart = Bucket.week.start(of: now, in: calendar)
        guard
            let windowStart = calendar.date(
                byAdding: .weekOfYear, value: -(heatmapWeeks - 1), to: currentWeekStart),
            let windowEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart)
        else {
            return Heatmap(cells: [], bucket: bucket, thresholds: [])
        }

        // Tally only the messages inside the fixed window, keyed by their bucket start.
        let windowed = Counting.messages(from: events).filter {
            $0.timestamp >= windowStart && $0.timestamp < windowEnd
        }
        let totals = bucketTotals(windowed, metric: metric, bucket: bucket, calendar: calendar)

        // The last cell is the bucket ending the window; `denseDates` is inclusive of it.
        guard let lastCell = calendar.date(byAdding: bucket.component, value: -1, to: windowEnd)
        else {
            return Heatmap(cells: [], bucket: bucket, thresholds: [])
        }
        let dates = denseDates(from: windowStart, through: lastCell, bucket: bucket, calendar: calendar)
        let values = dates.map { totals[$0] ?? 0 }

        let (levels, thresholds) = intensityLevels(for: values)
        let cells = zip(dates, zip(values, levels)).map { date, valueAndLevel in
            HeatmapCell(date: date, value: valueAndLevel.0, level: valueAndLevel.1)
        }
        return Heatmap(cells: cells, bucket: bucket, thresholds: thresholds)
    }

    /// Groups events into sessions, newest first. A session's project and start come from its
    /// earliest message, so a run that crosses midnight stays one session — while its tokens still
    /// land on the days they were actually spent.
    public static func sessions(
        from events: [TranscriptEvent], home: String,
        timeframe: Timeframe, now: Date = .distantPast, calendar: Calendar = .current
    ) -> [Session] {
        var accumulators: [String: SessionAccumulator] = [:]
        for message in Counting.messages(
            from: filter(events, timeframe: timeframe, now: now, calendar: calendar))
        {
            accumulators[message.sessionID, default: SessionAccumulator()].add(message)
        }
        return accumulators
            .compactMap { id, accumulator in accumulator.session(id: id, home: home) }
            .sorted { $0.start > $1.start }
    }

    /// Ranks a dimension by a metric, descending, ties broken by label so the order never flickers.
    ///
    /// The two dimensions read the events differently: token metrics are summed over deduplicated
    /// messages, tool invocations over every block. `tool` therefore ignores the metric, because
    /// tokens cannot be attributed to an individual tool call.
    public static func breakdown(
        _ dimension: BreakdownDimension, metric: Metric, over events: [TranscriptEvent], limit: Int,
        home: String, timeframe: Timeframe, now: Date = .distantPast, calendar: Calendar = .current
    ) -> [BreakdownRow] {
        let events = filter(events, timeframe: timeframe, now: now, calendar: calendar)
        let rows: [BreakdownRow]
        switch dimension {
        case .tool:
            rows = tally(Counting.toolInvocations(from: events))
                .map { BreakdownRow(label: $0.key, detail: nil, value: $0.value) }

        case .model:
            rows = totals(over: events, metric: metric, keyedBy: \.model)
                .map { BreakdownRow(label: $0.key, detail: nil, value: $0.value) }

        case .project:
            // Keyed by the raw path, so one `Project` is built per distinct project, not per message.
            rows = totals(over: events, metric: metric, keyedBy: \.cwd)
                .map { cwd, value in
                    let project = Project(cwd: cwd, home: home)
                    return BreakdownRow(
                        label: project.displayName, detail: project.abbreviatedPath, value: value)
                }
        }

        return Array(
            rows
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.label < $1.label }
                .prefix(limit))
    }

    /// How far a naive per-line sum of `input + output` strays from the true total. Returned as a
    /// pair so the wrong number is never handed out on its own, only next to the right one.
    ///
    /// `ratio` is `nil` when there is nothing to compare.
    public static func inflationAudit(over events: [TranscriptEvent]) -> (
        honest: Int, naiveLineSum: Int, ratio: Double?
    ) {
        let honest = sum(.inputOutput, over: events)
        let naive = Counting.naiveLineSumOfInputAndOutput(events)
        return (honest, naive, honest > 0 ? Double(naive) / Double(honest) : nil)
    }

    // MARK: - Internals

    /// Sums a token metric over already-windowed events. The public `total` filters first; the
    /// all-corpus audit sums directly.
    private static func sum(_ metric: Metric, over events: [TranscriptEvent]) -> Int {
        Counting.messages(from: events).reduce(0) { $0 + value(of: metric, in: $1.usage) }
    }

    private static func totals<Key: Hashable>(
        over events: [TranscriptEvent], metric: Metric, keyedBy key: KeyPath<Message, Key>
    ) -> [Key: Int] {
        Counting.messages(from: events).reduce(into: [Key: Int]()) {
            $0[$1[keyPath: key], default: 0] += value(of: metric, in: $1.usage)
        }
    }

    private static func tally(_ names: [String]) -> [String: Int] {
        names.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
    }

    /// Sums a metric over already-windowed messages, keyed by the start of each message's bucket.
    /// The one place the "one bucket per message's local bucket-start" rule lives, so the time
    /// series and the heatmap cannot drift apart on it.
    private static func bucketTotals(
        _ messages: [Message], metric: Metric, bucket: Bucket, calendar: Calendar
    ) -> [Date: Int] {
        messages.reduce(into: [Date: Int]()) {
            $0[bucket.start(of: $1.timestamp, in: calendar), default: 0] += value(of: metric, in: $1.usage)
        }
    }

    /// The bucket-start dates from `from` through `through` inclusive, one step of `bucket` apart —
    /// the dense, gap-free spine both the time series and the heatmap lay their values along. Breaks
    /// rather than looping forever if the calendar cannot advance the cursor.
    private static func denseDates(
        from start: Date, through last: Date, bucket: Bucket, calendar: Calendar
    ) -> [Date] {
        var dates: [Date] = []
        var cursor = start
        while cursor <= last {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: bucket.component, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return dates
    }

    /// Buckets each value into an intensity level: 0 for empty, then 1…4 by quantiles of the
    /// *non-zero* distribution. Quantiles rather than fractions of the max: a single cache-read day
    /// dwarfs every real one, and a max-relative scale would sink almost every real day to level 1.
    ///
    /// With fewer than four distinct non-zero values the scale uses fewer levels rather than forcing
    /// four onto three data points. Returns the per-value levels and the ascending cut points, so a
    /// legend can name each band.
    private static func intensityLevels(for values: [Int]) -> (levels: [Int], thresholds: [Int]) {
        let nonzero = values.filter { $0 > 0 }.sorted()
        let levelCount = min(4, Set(nonzero).count)
        guard levelCount >= 2 else {
            // Zero or one distinct non-zero value: one lit level, no divisions to draw.
            return (values.map { $0 > 0 ? 1 : 0 }, [])
        }
        let n = nonzero.count
        let thresholds = (1..<levelCount).map { i in nonzero[min(n * i / levelCount, n - 1)] }
        let levels = values.map { value in
            value == 0 ? 0 : 1 + thresholds.filter { value >= $0 }.count
        }
        return (levels, thresholds)
    }

    /// `requests` counts responses rather than tokens, so each message contributes exactly one.
    private static func value(of metric: Metric, in usage: TokenUsage) -> Int {
        switch metric {
        case .inputOutput: usage.input + usage.output
        case .cacheRead: usage.cacheRead
        case .cacheCreation: usage.cacheCreation
        case .allTokens: usage.input + usage.output + usage.cacheCreation + usage.cacheRead
        case .requests: 1
        }
    }
}

/// Collects a session's endpoints and totals in a single pass, with no per-group sorting.
private struct SessionAccumulator {
    private var earliest: Message?
    private var latest: Date?
    private var count = 0
    private var usage = TokenUsage.zero

    mutating func add(_ message: Message) {
        if earliest == nil || message.timestamp < earliest!.timestamp { earliest = message }
        if latest == nil || message.timestamp > latest! { latest = message.timestamp }
        count += 1
        usage = usage + message.usage
    }

    func session(id: String, home: String) -> Session? {
        guard let earliest, let latest else { return nil }
        return Session(
            id: id,
            project: Project(cwd: earliest.cwd, home: home),
            start: earliest.timestamp,
            end: latest,
            messageCount: count,
            usage: usage
        )
    }
}
