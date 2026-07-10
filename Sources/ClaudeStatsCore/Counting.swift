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

    /// Collapses the lines of each response into one `Message`, keeping the first line seen and
    /// preserving order. This is the only way a `Message` — and therefore a token count — is made.
    public static func messages(from events: [TranscriptEvent]) -> [Message] {
        var seen: Set<MessageKey> = []
        seen.reserveCapacity(events.count)
        return events.compactMap { event in
            let key = MessageKey(messageID: event.messageID, requestID: event.requestID)
            return seen.insert(key).inserted ? Message(event) : nil
        }
    }

    /// Every `tool_use` block across every line, in order. Never deduplicated: two lines of one
    /// response carrying a tool block each are two real invocations.
    public static func toolInvocations(from events: [TranscriptEvent]) -> [String] {
        events.flatMap(\.toolNames)
    }
}
