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

    let unique = Set(result.events.map { "\($0.messageID)|\($0.requestID ?? "nil")" })
    let tools = result.events.flatMap(\.toolNames).count

    print("EVENTS=\(result.events.count)")
    print("SKIPPED=\(result.skippedLines)")
    print("UNIQUE_MESSAGES=\(unique.count)")
    print("TOOL_INVOCATIONS=\(tools)")
}
