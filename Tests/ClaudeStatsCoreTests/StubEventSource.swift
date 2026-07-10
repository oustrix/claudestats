import Foundation
import Testing

@testable import ClaudeStatsCore

/// Feeds a fixed set of events to anything that reads through `EventSource`, so aggregation can be
/// tested without touching the filesystem.
struct StubEventSource: EventSource {
    let result: ScanResult

    init(events: [TranscriptEvent], skippedLines: Int = 0) {
        result = ScanResult(events: events, skippedLines: skippedLines)
    }

    func loadEvents() throws -> ScanResult { result }
}

/// Builds an event with everything defaulted, so a test names only the fields it cares about.
func makeEvent(
    messageID: String = "msg",
    requestID: String? = "req",
    timestamp: Date = Date(timeIntervalSince1970: 1_782_985_385),
    sessionID: String = "session",
    cwd: String = "/Users/me/proj",
    gitBranch: String? = "main",
    model: String = "claude-opus-4-8",
    isSidechain: Bool = false,
    usage: TokenUsage = TokenUsage(input: 1, output: 2, cacheCreation: 3, cacheRead: 4),
    toolNames: [String] = []
) -> TranscriptEvent {
    TranscriptEvent(
        messageID: messageID,
        requestID: requestID,
        timestamp: timestamp,
        sessionID: sessionID,
        cwd: cwd,
        gitBranch: gitBranch,
        model: model,
        isSidechain: isSidechain,
        usage: usage,
        toolNames: toolNames
    )
}

@Test func stubSourceReturnsWhatItWasGiven() throws {
    let source: EventSource = StubEventSource(
        events: [makeEvent(messageID: "a"), makeEvent(messageID: "b")], skippedLines: 7)

    let result = try source.loadEvents()

    #expect(result.events.map(\.messageID) == ["a", "b"])
    #expect(result.skippedLines == 7)
}
