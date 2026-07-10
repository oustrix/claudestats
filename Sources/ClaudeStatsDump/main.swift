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
    : URL(filePath: home).appending(path: ".claude/projects")

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
print("requests:       \(Aggregation.total(.requests, over: events).formatted())")
print("input + output: \(Aggregation.total(.inputOutput, over: events).formatted())")
print("cache creation: \(Aggregation.total(.cacheCreation, over: events).formatted())")
print("cache read:     \(Aggregation.total(.cacheRead, over: events).formatted())")
print("all tokens:     \(Aggregation.total(.allTokens, over: events).formatted())")

// The number this whole project exists to get right: summing lines instead of messages.
let audit = Aggregation.inflationAudit(over: events)
if let ratio = audit.ratio {
    let times = ratio.formatted(.number.precision(.fractionLength(2)))
    print("\nnaive line-sum of input+output: \(audit.naiveLineSum.formatted())  (\(times)x the true total)")
}

// `Dimension` is qualified: Foundation ships a unit-of-measurement type by the same name.
func printBreakdown(_ title: String, _ dimension: ClaudeStatsCore.Dimension, metric: Metric) {
    heading(title)
    let rows = Aggregation.breakdown(dimension, metric: metric, over: events, limit: 15, home: home)
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

heading("Sessions")
let sessions = Aggregation.sessions(from: events, home: home)
print("count: \(sessions.count)")
if let newest = sessions.first {
    print("newest: \(newest.project.displayName) — \(newest.messageCount) messages")
}

extension String {
    fileprivate func paddedLeft(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
