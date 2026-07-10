import Foundation
import Testing

@testable import ClaudeStatsCore

private let home = "/Users/me"

private func event(
    _ id: String, model: String = "claude-opus-4-8", cwd: String = "/Users/me/proj",
    input: Int = 0, tools: [String] = []
) -> TranscriptEvent {
    makeEvent(
        messageID: id, requestID: "r-\(id)", cwd: cwd, model: model,
        usage: TokenUsage(input: input, output: 0, cacheCreation: 0, cacheRead: 0),
        toolNames: tools)
}

@Test func breakdownByModelRanksDescending() {
    let events = [
        event("a", model: "haiku", input: 5),
        event("b", model: "opus", input: 100),
        event("c", model: "haiku", input: 7),
    ]

    let rows = Aggregation.breakdown(.model, metric: .inputOutput, over: events, limit: 10, home: home)

    #expect(rows.map(\.label) == ["opus", "haiku"])
    #expect(rows.map(\.value) == [100, 12])
}

/// Unknown model identifiers appear as they are, neither classified nor dropped.
@Test func unknownModelsAreReportedVerbatim() {
    let rows = Aggregation.breakdown(
        .model, metric: .requests, over: [event("a", model: "gpt-5.5")], limit: 10, home: home)

    #expect(rows.map(\.label) == ["gpt-5.5"])
}

/// Tokens are counted once per message even when the message spans several lines.
@Test func breakdownByModelDeduplicatesMessages() {
    let usage = TokenUsage(input: 50, output: 0, cacheCreation: 0, cacheRead: 0)
    let split = [
        makeEvent(messageID: "m", requestID: "r", model: "opus", usage: usage),
        makeEvent(messageID: "m", requestID: "r", model: "opus", usage: usage, toolNames: ["Bash"]),
    ]

    let rows = Aggregation.breakdown(.model, metric: .inputOutput, over: split, limit: 10, home: home)

    #expect(rows.map(\.value) == [50])
}

@Test func breakdownByProjectUsesShortNameAndKeepsTheFullPath() throws {
    let events = [
        event("a", cwd: "/Users/me/go/snitch", input: 3),
        event("b", cwd: "/Users/me/go/snitch", input: 4),
    ]

    let rows = Aggregation.breakdown(
        .project, metric: .inputOutput, over: events, limit: 10, home: home)

    let row = try #require(rows.first)
    #expect(row.label == "snitch")
    #expect(row.detail == "~/go/snitch")
    #expect(row.value == 7)
}

/// Tool invocations are counted per block, and the token metric does not affect the result.
@Test func breakdownByToolCountsInvocationsAndIgnoresTheMetric() {
    let split = [
        makeEvent(messageID: "m", requestID: "r", toolNames: ["Bash"]),
        makeEvent(messageID: "m", requestID: "r", toolNames: ["Bash", "Read"]),
    ]

    let byTokens = Aggregation.breakdown(.tool, metric: .inputOutput, over: split, limit: 10, home: home)
    let byRequests = Aggregation.breakdown(.tool, metric: .requests, over: split, limit: 10, home: home)

    #expect(byTokens.map(\.label) == ["Bash", "Read"])
    #expect(byTokens.map(\.value) == [2, 1])
    #expect(byTokens == byRequests)
}

@Test func limitTruncatesTheTail() {
    let events = (1...5).map { event("\($0)", model: "m\($0)", input: $0) }

    let rows = Aggregation.breakdown(.model, metric: .inputOutput, over: events, limit: 2, home: home)

    #expect(rows.map(\.label) == ["m5", "m4"])
}

@Test func breakdownOverNoEventsIsEmpty() {
    for dimension in Dimension.allCases {
        #expect(Aggregation.breakdown(dimension, metric: .allTokens, over: [], limit: 5, home: home).isEmpty)
    }
}

/// Ties must not reorder run to run, or the chart would flicker between renders.
@Test func tiesAreBrokenByLabelSoOrderIsStable() {
    let events = [event("a", model: "zebra", input: 1), event("b", model: "alpha", input: 1)]

    let rows = Aggregation.breakdown(.model, metric: .inputOutput, over: events, limit: 10, home: home)

    #expect(rows.map(\.label) == ["alpha", "zebra"])
}
