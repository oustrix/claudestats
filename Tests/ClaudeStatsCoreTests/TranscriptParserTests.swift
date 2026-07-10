import Foundation
import Testing

@testable import ClaudeStatsCore

/// An assistant record as Claude Code writes it, narrowed to the fields the parser reads.
private let assistantLine = """
{"type":"assistant","timestamp":"2026-07-02T09:43:05.761Z","sessionId":"s-1",\
"cwd":"/Users/me/proj","gitBranch":"main","isSidechain":false,"requestId":"req-1",\
"message":{"id":"msg-1","model":"claude-opus-4-8",\
"content":[{"type":"text","text":"hi"}],\
"usage":{"input_tokens":2,"output_tokens":207,"cache_creation_input_tokens":5481,"cache_read_input_tokens":75382}}}
"""

@Test func assistantRecordIsExtracted() throws {
    let outcome = TranscriptParser.parseLine(assistantLine)

    guard case .event(let event) = outcome else {
        Issue.record("expected an event, got \(outcome)")
        return
    }
    #expect(event.messageID == "msg-1")
    #expect(event.requestID == "req-1")
    #expect(event.sessionID == "s-1")
    #expect(event.cwd == "/Users/me/proj")
    #expect(event.gitBranch == "main")
    #expect(event.model == "claude-opus-4-8")
    #expect(event.isSidechain == false)
    #expect(event.usage.input == 2)
    #expect(event.usage.output == 207)
    #expect(event.usage.cacheCreation == 5481)
    #expect(event.usage.cacheRead == 75382)
    #expect(event.toolNames.isEmpty)

    // Milliseconds must survive. Exact Double equality is not required: ISO8601FormatStyle yields
    // 1782985385.7610002 — a representation artifact, not a loss of precision.
    let expected = 1_782_985_385.761
    #expect(abs(event.timestamp.timeIntervalSince1970 - expected) < 0.001)
}

/// `<synthetic>` records stand for no API call: their usage is all zeros.
@Test func syntheticRecordsAreExcluded() {
    let line = assistantLine.replacingOccurrences(of: "claude-opus-4-8", with: "<synthetic>")

    #expect(TranscriptParser.parseLine(line) == .ignored)
}

@Test(arguments: [
    #"{"type":"user","timestamp":"2026-07-02T09:43:05.761Z","sessionId":"s","cwd":"/p"}"#,
    #"{"type":"attachment","sessionId":"s"}"#,
    #"{"type":"file-history-snapshot"}"#,
    // An assistant record without usage, e.g. an interrupted response.
    #"{"type":"assistant","timestamp":"2026-07-02T09:43:05.761Z","sessionId":"s","cwd":"/p","message":{"id":"m","model":"claude-opus-4-8"}}"#,
    // A user record carries a `message` too, but it has neither id nor model. Decoding it must not
    // fail: a well-formed user turn is ignored, never counted as a skipped line.
    #"{"type":"user","timestamp":"2026-07-02T09:43:00.000Z","sessionId":"s","cwd":"/p","message":{"role":"user","content":"hello"}}"#,
])
func recordsWithoutUsageAreIgnored(line: String) {
    #expect(TranscriptParser.parseLine(line) == .ignored)
}

@Test func sidechainRecordsAreRetainedWithTheirFlag() throws {
    let line = assistantLine.replacingOccurrences(
        of: #""isSidechain":false"#, with: #""isSidechain":true"#)

    guard case .event(let event) = TranscriptParser.parseLine(line) else {
        Issue.record("subagent records must reach the statistics")
        return
    }
    #expect(event.isSidechain)
}

/// One line may carry several `tool_use` blocks; every one of them is a real invocation.
@Test func everyToolUseBlockIsCollected() throws {
    let line = assistantLine.replacingOccurrences(
        of: #"[{"type":"text","text":"hi"}]"#,
        with: #"[{"type":"text","text":"hi"},{"type":"tool_use","name":"Bash"},{"type":"tool_use","name":"Read"}]"#
    )

    guard case .event(let event) = TranscriptParser.parseLine(line) else {
        Issue.record("expected an event")
        return
    }
    #expect(event.toolNames == ["Bash", "Read"])
}

@Test(arguments: [
    "not json at all",
    "",
    // A final line cut mid-write while the transcript was being appended to.
    #"{"type":"assistant","timestamp":"2026-07-02T09:43:05.761Z","sess"#,
])
func brokenLinesAreMalformed(line: String) {
    #expect(TranscriptParser.parseLine(line) == .malformed)
}

/// Valid JSON, but missing the fields without which an event carries no meaning.
@Test func assistantRecordMissingRequiredFieldsIsMalformed() {
    let noCwd = #"""
        {"type":"assistant","timestamp":"2026-07-02T09:43:05.761Z","sessionId":"s",\#
        "message":{"id":"m","model":"claude-opus-4-8",\#
        "usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """#

    #expect(TranscriptParser.parseLine(noCwd) == .malformed)
}

/// Some records carry no requestId; that is no reason to lose the event.
@Test func missingRequestIDIsTolerated() throws {
    let line = assistantLine.replacingOccurrences(of: #""requestId":"req-1","#, with: "")

    guard case .event(let event) = TranscriptParser.parseLine(line) else {
        Issue.record("expected an event")
        return
    }
    #expect(event.requestID == nil)
}
