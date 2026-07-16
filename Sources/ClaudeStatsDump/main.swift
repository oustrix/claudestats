import ClaudeStatsCore
import Foundation

// Prints the aggregates the dashboard draws, computed by the same functions, so the numbers can be
// checked against `ccusage` or an ad-hoc `jq` pass. A dashboard that cannot be audited is a
// dashboard that is trusted for no reason.
//
// Usage: claudestats-dump [transcript-root]

let home = NSHomeDirectory()
let root =
    CommandLine.arguments.count > 1
    ? URL(filePath: CommandLine.arguments[1])
    : FileEventSource.defaultRoot

let result: ScanResult
do {
    result = try FileEventSource(root: root).loadEvents()
} catch {
    let reason =
        switch error {
        case EventSourceError.rootNotFound(let missing): "no transcripts found at \(missing.path())"
        default: "could not read transcripts: \(error)"
        }
    FileHandle.standardError.write(Data("\(reason)\n".utf8))
    exit(1)
}

let events = result.events

func heading(_ text: String) {
    print("\n\(text)")
    print(String(repeating: "─", count: text.count))
}

print("root: \(root.path())")
print("lines parsed:     \(events.count)")
print("lines skipped:    \(result.skippedLines)")
print("files unreadable: \(result.unreadableFiles.count)")
for file in result.unreadableFiles {
    print("  ! \(file.path())")
}

heading("Tokens (deduplicated per message)")
print("requests:       \(Aggregation.total(.requests, over: events, timeframe: .allTime).formatted())")
print("input + output: \(Aggregation.total(.inputOutput, over: events, timeframe: .allTime).formatted())")
print("cache creation: \(Aggregation.total(.cacheCreation, over: events, timeframe: .allTime).formatted())")
print("cache read:     \(Aggregation.total(.cacheRead, over: events, timeframe: .allTime).formatted())")
print("all tokens:     \(Aggregation.total(.allTokens, over: events, timeframe: .allTime).formatted())")

// The number this whole project exists to get right: summing lines instead of messages.
let audit = Aggregation.inflationAudit(over: events)
if let ratio = audit.ratio {
    let times = ratio.formatted(.number.precision(.fractionLength(2)))
    print("\nnaive line-sum of input+output: \(audit.naiveLineSum.formatted())  (\(times)x the true total)")
}

// The heatmap draws a fixed 52-week window, so its total is the metric summed over just that span.
// Day and week bucketing must agree with each other, and — when all activity is within the window —
// with the all-time total above. This is the number `ccusage`/`jq` over the same range check against.
heading("Heatmap window (last 52 weeks, input + output)")
let byDay = Aggregation.heatmap(.inputOutput, over: events, bucket: .day, now: Date())
let byWeek = Aggregation.heatmap(.inputOutput, over: events, bucket: .week, now: Date())
let dayTotal = byDay.cells.reduce(0) { $0 + $1.value }
let weekTotal = byWeek.cells.reduce(0) { $0 + $1.value }
print("by day:   \(dayTotal.formatted())")
print("by week:  \(weekTotal.formatted())  \(dayTotal == weekTotal ? "✓ agrees" : "✗ MISMATCH")")
if let busiest = byDay.cells.max(by: { $0.value < $1.value }), busiest.value > 0 {
    let day = busiest.date.formatted(.dateTime.year().month(.abbreviated).day())
    print("busiest:  \(day) — \(busiest.value.formatted()) (level \(busiest.level))")
}

func printBreakdown(_ title: String, _ dimension: BreakdownDimension, metric: Metric) {
    heading(title)
    let rows = Aggregation.breakdown(
        dimension, metric: metric, over: events, limit: 15, home: home, timeframe: .allTime)
    guard !rows.isEmpty else {
        print("(none)")
        return
    }
    let width = rows.map(\.label.count).max() ?? 0
    for row in rows {
        let label = row.label.padding(toLength: width, withPad: " ", startingAt: 0)
        let detail = row.detail.map { "  \($0)" } ?? ""
        print("\(label)  \(row.value.formatted().paddedLeft(to: 14))\(detail)")
    }
}

printBreakdown("By model (input + output)", .model, metric: .inputOutput)
printBreakdown("By project (input + output)", .project, metric: .inputOutput)
printBreakdown("By tool (invocations)", .tool, metric: .requests)
printBreakdown("By agent (all tokens)", .agent, metric: .allTokens)

// Cost is derived per model from the bundled default rates — reproducible, independent of any
// user-edited pricing.json, so a cross-check against ccusage/jq compares the same methodology.
heading("Estimated cost (default pricing, all time)")
let cost = Aggregation.cost(over: events, pricing: .default, timeframe: .allTime)
func dollars(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
}
print("total: $\(dollars(cost.total))")
for (model, amount) in cost.perModel.sorted(by: { $0.value > $1.value }) {
    print("  \(model.padding(toLength: 32, withPad: " ", startingAt: 0)) $\(dollars(amount))")
}
if !cost.unpricedModels.isEmpty {
    print("unpriced (not costed): \(cost.unpricedModels.sorted().joined(separator: ", "))")
}

heading("Sessions")
let sessions = Aggregation.sessions(from: events, home: home, timeframe: .allTime)
print("count: \(sessions.count)")
if let newest = sessions.first {
    print("newest: \(newest.project.displayName) — \(newest.messageCount) messages")
}

extension String {
    fileprivate func paddedLeft(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
