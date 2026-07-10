import Foundation

/// Pure functions from messages to the numbers a block draws. No UI, no I/O, no caching: at a few
/// thousand messages, recomputing is cheaper than remembering.
/// One point of a time series: the start of a bucket, and the metric's value within it.
public struct DataPoint: Equatable, Sendable {
    public let date: Date
    public let value: Int
}

/// One row of a breakdown: what it is, where it lives, and how much of the metric it accounts for.
public struct BreakdownRow: Equatable, Sendable {
    public let label: String
    /// Secondary text, shown on hover. Carries the full path for projects; `nil` otherwise.
    public let detail: String?
    public let value: Int
}

public enum Aggregation {
    /// Timeframes are whole local calendar days, not rolling 24-hour windows: "the last 7 days"
    /// means today and the six days before it, whatever the hour.
    public static func filter(
        _ messages: [Message], timeframe: Timeframe, now: Date, calendar: Calendar = .current
    ) -> [Message] {
        guard let days = timeframe.days else { return messages }
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return messages
        }
        return messages.filter { $0.timestamp >= start }
    }

    /// One point per bucket across the whole span, including buckets with no activity — a gap must
    /// read as zero, not as two distant days drawn side by side.
    public static func timeSeries(
        _ metric: Metric, over messages: [Message], bucket: Bucket, timeframe: Timeframe,
        now: Date, calendar: Calendar = .current
    ) -> [DataPoint] {
        let kept = filter(messages, timeframe: timeframe, now: now, calendar: calendar)
        guard !kept.isEmpty else { return [] }

        var totals: [Date: Int] = [:]
        for message in kept {
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

    /// Groups messages into sessions, newest first. A session's project and day come from its
    /// earliest message, so a run that crosses midnight stays one session on one day — while its
    /// tokens still land on the days they were actually spent.
    public static func sessions(
        from messages: [Message], home: String = NSHomeDirectory()
    ) -> [Session] {
        Dictionary(grouping: messages, by: \.sessionID)
            .compactMap { id, group in
                let ordered = group.sorted { $0.timestamp < $1.timestamp }
                guard let first = ordered.first, let last = ordered.last else { return nil }
                return Session(
                    id: id,
                    project: Project(cwd: first.cwd, home: home),
                    start: first.timestamp,
                    end: last.timestamp,
                    messageCount: ordered.count,
                    usage: ordered.reduce(TokenUsage.zero) { $0 + $1.usage }
                )
            }
            .sorted { $0.start > $1.start }
    }

    /// Ranks a dimension by a metric, descending, ties broken by label so the order never flickers.
    ///
    /// Takes raw events rather than messages, because the two dimensions read them differently:
    /// token metrics are summed over deduplicated messages, tool invocations over every block. The
    /// caller cannot get that wrong because the caller never performs the split.
    public static func breakdown(
        _ dimension: Dimension, metric: Metric, over events: [TranscriptEvent], limit: Int,
        home: String = NSHomeDirectory()
    ) -> [BreakdownRow] {
        let rows: [BreakdownRow]
        switch dimension {
        case .tool:
            // Tokens cannot be attributed to an individual tool call, so the metric is ignored.
            let counts = Counting.toolInvocations(from: events)
                .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            rows = counts.map { BreakdownRow(label: $0.key, detail: nil, value: $0.value) }

        case .model:
            let totals = Counting.messages(from: events)
                .reduce(into: [String: Int]()) { $0[$1.model, default: 0] += value(of: metric, in: $1.usage) }
            rows = totals.map { BreakdownRow(label: $0.key, detail: nil, value: $0.value) }

        case .project:
            let totals = Counting.messages(from: events)
                .reduce(into: [Project: Int]()) {
                    $0[Project(cwd: $1.cwd, home: home), default: 0] += value(of: metric, in: $1.usage)
                }
            rows = totals.map {
                BreakdownRow(
                    label: $0.key.displayName, detail: $0.key.abbreviatedPath, value: $0.value)
            }
        }

        return
            rows
            .sorted { ($0.value, $1.label) > ($1.value, $0.label) }
            .prefix(limit)
            .map { $0 }
    }

    public static func total(_ metric: Metric, over messages: [Message]) -> Int {
        if case .requests = metric { return messages.count }
        return messages.reduce(0) { $0 + value(of: metric, in: $1.usage) }
    }

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
