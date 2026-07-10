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
    public let usage: TokenUsage

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
    }

    private init(_ other: Message, usage: TokenUsage) {
        messageID = other.messageID
        requestID = other.requestID
        timestamp = other.timestamp
        sessionID = other.sessionID
        cwd = other.cwd
        gitBranch = other.gitBranch
        model = other.model
        isSidechain = other.isSidechain
        self.usage = usage
    }

    /// A response begins when its first line is written, but its token counts are only final on the
    /// last. So the timestamp comes from the first line and the usage from the last.
    func withFinalUsage(from event: TranscriptEvent) -> Message {
        Message(self, usage: event.usage)
    }
}
