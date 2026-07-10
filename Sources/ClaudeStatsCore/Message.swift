import Foundation

/// One API response, with its tokens counted exactly once.
///
/// The only way to obtain a `Message` is `Counting.messages(from:)`, which collapses the several
/// JSONL lines a single response is written across. `TranscriptEvent.usage` is deliberately not
/// public, so summing tokens straight off raw events — which more than doubles the true total —
/// does not compile outside this module. Measurements: openspec `design.md`, "Two counting rules".
public struct Message: Equatable, Sendable {
    public let messageID: String
    public let requestID: String?
    public let timestamp: Date
    public let sessionID: String
    public let cwd: String
    public let gitBranch: String?
    public let model: String
    public let isSidechain: Bool
    /// Settable within the module only: `Counting` replaces it when a response's final line arrives.
    public internal(set) var usage: TokenUsage
    /// Whether `usage` came from the line that ended the response, rather than a streaming placeholder.
    var usageIsFinal: Bool

    init(_ event: TranscriptEvent) {
        messageID = event.messageID
        requestID = event.requestID
        timestamp = event.timestamp
        sessionID = event.sessionID
        cwd = event.cwd
        gitBranch = event.gitBranch
        model = event.model
        isSidechain = event.isSidechain
        usage = event.usage
        usageIsFinal = event.stopReason != nil
    }

    /// Folds a further line of the same response into this message. The timestamp and working
    /// directory stay as the first line reported them, because that is when the response began.
    ///
    /// Token counts are taken from the line that ended the response — the one bearing a
    /// `stop_reason`. Until such a line appears, the newest line wins, so an interrupted response
    /// still reports the last figures it managed to emit.
    mutating func merge(_ event: TranscriptEvent) {
        let lineIsFinal = event.stopReason != nil
        guard lineIsFinal || !usageIsFinal else { return }
        usage = event.usage
        usageIsFinal = lineIsFinal || usageIsFinal
    }

    public static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.messageID == rhs.messageID && lhs.requestID == rhs.requestID
            && lhs.timestamp == rhs.timestamp && lhs.sessionID == rhs.sessionID
            && lhs.cwd == rhs.cwd && lhs.gitBranch == rhs.gitBranch && lhs.model == rhs.model
            && lhs.isSidechain == rhs.isSidechain && lhs.usage == rhs.usage
    }
}
