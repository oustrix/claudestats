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

    let messages = deduplicatedMessages(from: result.events)
    let naive = result.events.reduce(0) { $0 + $1.usage.input + $1.usage.output }
    let honest = messages.reduce(0) { $0 + $1.usage.input + $1.usage.output }

    print("EVENTS=\(result.events.count)")
    print("SKIPPED=\(result.skippedLines)")
    print("UNIQUE_MESSAGES=\(messages.count)")
    print("TOOL_INVOCATIONS=\(toolInvocations(from: result.events).count)")
    print("INPUT=\(messages.reduce(0) { $0 + $1.usage.input })")
    print("OUTPUT=\(messages.reduce(0) { $0 + $1.usage.output })")
    print("CACHE_CREATION=\(messages.reduce(0) { $0 + $1.usage.cacheCreation })")
    print("CACHE_READ=\(messages.reduce(0) { $0 + $1.usage.cacheRead })")
    print("INFLATION=\(Double(naive) / Double(honest))")
}
