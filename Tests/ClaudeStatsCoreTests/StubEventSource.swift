import Foundation
import Testing

@testable import ClaudeStatsCore

/// Feeds a fixed set of events to anything that reads through `EventSource`, so aggregation can be
/// tested without touching the filesystem.
struct StubEventSource: EventSource {
    let result: ScanResult

    init(events: [TranscriptEvent], skippedLines: Int = 0, unreadableFiles: [URL] = []) {
        result = ScanResult(
            events: events, skippedLines: skippedLines, unreadableFiles: unreadableFiles)
    }

    func loadEvents() throws -> ScanResult { result }
}

/// Parses an ISO-8601 instant, trapping on a malformed literal — a test fixture is not input.
func instant(_ iso: String) -> Date {
    try! Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(iso)
}

/// A scratch transcript directory, removed by the caller's `defer`.
func makeScratchRoot(_ label: String = "root") throws -> URL {
    let root = URL.temporaryDirectory.appending(path: "claudestats-\(label)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// One assistant JSONL line. The single in-code definition of the shape `TranscriptParser` reads:
/// the snake_case usage keys here must stay in step with `RawUsage`.
func assistantJSONLine(
    messageID: String = "msg-1",
    requestID: String = "req-1",
    timestamp: String = "2026-07-02T09:43:05.761Z",
    sessionID: String = "s-1",
    cwd: String = "/Users/me/proj",
    model: String = "claude-opus-4-8",
    isSidechain: Bool = false,
    content: String = #"[{"type":"text","text":"hi"}]"#,
    usage: String =
        #"{"input_tokens":2,"output_tokens":207,"cache_creation_input_tokens":5481,"cache_read_input_tokens":75382}"#
) -> String {
    """
    {"type":"assistant","timestamp":"\(timestamp)","sessionId":"\(sessionID)",\
    "cwd":"\(cwd)","gitBranch":"main","isSidechain":\(isSidechain),"requestId":"\(requestID)",\
    "message":{"id":"\(messageID)","model":"\(model)",\
    "content":\(content),"usage":\(usage)}}
    """
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
    stopReason: String? = nil,
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
        stopReason: stopReason,
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
