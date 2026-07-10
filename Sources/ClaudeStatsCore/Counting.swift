import Foundation

/// The two counting rules. Tokens once per message, tool invocations once per block.
/// The rationale, and the corpus measurements behind it, live in openspec `design.md`.
public enum Counting {
    /// Identifies one API response. `messageID` alone is already unique per response; `requestID`
    /// is kept so that a missing or reused `messageID` disambiguates rather than silently
    /// collapsing two responses into one.
    private struct MessageKey: Hashable {
        let messageID: String
        let requestID: String?
    }

    /// Collapses the lines of each response into one `Message`. This is the only way a `Message` —
    /// and therefore a token count — is made.
    ///
    /// Token counts come from the line bearing a `stop_reason`. Claude Code streams: every earlier
    /// line of a response reports a placeholder `output_tokens` of 1, and taking one of those
    /// undercounts output by roughly 8% on a real corpus. The other three counters are identical
    /// across a response's lines.
    ///
    /// Order follows each response's first appearance, so the sequence still reads chronologically.
    public static func messages(from events: [TranscriptEvent]) -> [Message] {
        var positions: [MessageKey: Int] = [:]
        positions.reserveCapacity(events.count)
        var messages: [Message] = []

        for event in events {
            let key = MessageKey(messageID: event.messageID, requestID: event.requestID)
            if let position = positions[key] {
                messages[position].merge(event)
            } else {
                positions[key] = messages.count
                messages.append(Message(event))
            }
        }
        return messages
    }

    /// Every `tool_use` block across every line, in order. Never deduplicated: two lines of one
    /// response carrying a tool block each are two real invocations.
    public static func toolInvocations(from events: [TranscriptEvent]) -> [String] {
        events.flatMap(\.toolNames)
    }

    /// The wrong answer, on purpose: sums `input + output` once per *line*, double-counting every
    /// response written across several. Internal, so that no caller outside the module can mistake
    /// it for a usage figure. It reaches an audit only through `Aggregation.inflationAudit`.
    static func naiveLineSumOfInputAndOutput(_ events: [TranscriptEvent]) -> Int {
        events.reduce(0) { $0 + $1.usage.input + $1.usage.output }
    }
}
