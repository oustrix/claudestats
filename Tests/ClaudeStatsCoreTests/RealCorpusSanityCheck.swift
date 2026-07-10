import Foundation
import Testing

@testable import ClaudeStatsCore

/// Runs the parser over a real transcript corpus and prints counts that can be cross-checked
/// against an independent tool. Disabled unless `REAL_CORPUS` is set; set it to a directory to scan
/// that directory, or to any value to scan `~/.claude/projects`.
///
/// Cross-check with jq over the same directory, taking a snapshot first — a live transcript grows
/// while you measure it:
///
///     find . -name '*.jsonl' -exec jq -r 'select(.type=="assistant" and .message.usage
///       and .message.model != "<synthetic>") | "\(.message.id)|\(.requestId // "nil")"' {} \;
@Test(.enabled(if: ProcessInfo.processInfo.environment["REAL_CORPUS"] != nil))
func realCorpusSanityCheck() throws {
    let root =
        ProcessInfo.processInfo.environment["REAL_CORPUS"].map { URL(filePath: $0) }
        ?? URL.homeDirectory.appending(path: ".claude/projects")
    let result = try FileEventSource(root: root).loadEvents()

    let messages = Counting.messages(from: result.events)
    let totals = messages.reduce(into: (input: 0, output: 0, creation: 0, read: 0)) {
        $0.input += $1.usage.input
        $0.output += $1.usage.output
        $0.creation += $1.usage.cacheCreation
        $0.read += $1.usage.cacheRead
    }
    // Deliberately re-derived here rather than through the production sum: this check exists to
    // disagree with the code when the code is wrong.
    let naive = result.events.reduce(0) { $0 + $1.usage.input + $1.usage.output }
    let honest = totals.input + totals.output

    print("EVENTS=\(result.events.count)")
    print("SKIPPED=\(result.skippedLines)")
    print("UNIQUE_MESSAGES=\(messages.count)")
    print("TOOL_INVOCATIONS=\(result.events.reduce(0) { $0 + $1.toolNames.count })")
    print("INPUT=\(totals.input)")
    print("OUTPUT=\(totals.output)")
    print("CACHE_CREATION=\(totals.creation)")
    print("CACHE_READ=\(totals.read)")
    print("INFLATION=\(Double(naive) / Double(honest))")
}
