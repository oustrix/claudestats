import Foundation

// The transcripts hold two kinds of fact, and they must be counted by different rules.
//
// A single model message is written as one JSONL line per content block, and every line repeats
// the same final `usage`. Summing lines inflates tokens 2.27x on a real corpus. But the `tool_use`
// blocks on those lines are distinct invocations, and deduplicating them would undercount tools.
//
// So: tokens once per message, tools once per block. See openspec `design.md`, "Two counting rules".

/// Identifies one API response. `messageID` alone is already unique per response; `requestID` is
/// kept so that a missing or reused `messageID` disambiguates rather than silently collapsing two
/// responses into one.
private struct MessageKey: Hashable {
    let messageID: String
    let requestID: String?
}

/// Keeps one event per `(messageID, requestID)` pair — the first seen — preserving input order.
public func deduplicatedMessages(from events: [TranscriptEvent]) -> [TranscriptEvent] {
    var seen: Set<MessageKey> = []
    return events.filter { event in
        seen.insert(MessageKey(messageID: event.messageID, requestID: event.requestID)).inserted
    }
}

/// Every `tool_use` block across every line, in order. Never deduplicated.
public func toolInvocations(from events: [TranscriptEvent]) -> [String] {
    events.flatMap(\.toolNames)
}
