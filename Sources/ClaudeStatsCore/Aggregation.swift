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
/// Every entry point takes raw events and performs the message/block split itself. A caller never
/// holds a `Message`, so it cannot apply a counting rule to the wrong collection.
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

    public static func total(_ metric: Metric, over events: [TranscriptEvent]) -> Int {
        Counting.messages(from: events).reduce(0) { $0 + value(of: metric, in: $1.usage) }
    }

    /// One point per bucket across the whole span, including buckets with no activity — a gap must
    /// read as zero, not as two distant days drawn side by side.
    public static func timeSeries(
        _ metric: Metric, over events: [TranscriptEvent], bucket: Bucket,
        now: Date, calendar: Calendar = .current
    ) -> [DataPoint] {
        var totals: [Date: Int] = [:]
        for message in Counting.messages(from: events) {
            let start = bucket.start(of: message.timestamp, in: calendar)
            totals[start, default: 0] += value(of: metric, in: message.usage)
        }
        guard let first = totals.keys.min(), let last = totals.keys.max() else { return [] }

        var points: [DataPoint] = []
        var cursor = first
        while cursor <= last {
            points.append(DataPoint(date: cursor, value: totals[cursor] ?? 0))
            guard let next = calendar.date(byAdding: bucket.component, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return points
    }

    /// Groups events into sessions, newest first. A session's project and start come from its
    /// earliest message, so a run that crosses midnight stays one session — while its tokens still
    /// land on the days they were actually spent.
    public static func sessions(from events: [TranscriptEvent], home: String) -> [Session] {
        var accumulators: [String: SessionAccumulator] = [:]
        for message in Counting.messages(from: events) {
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
        _ dimension: Dimension, metric: Metric, over events: [TranscriptEvent], limit: Int,
        home: String
    ) -> [BreakdownRow] {
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
        let honest = total(.inputOutput, over: events)
        let naive = Counting.naiveLineSumOfInputAndOutput(events)
        return (honest, naive, honest > 0 ? Double(naive) / Double(honest) : nil)
    }

    // MARK: - Internals

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
