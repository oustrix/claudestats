import Foundation
import Testing

@testable import ClaudeStatsCore

private let home = "/Users/me"

private func event(
    _ id: String, model: String = "claude-opus-4-8", cwd: String = "/Users/me/proj",
    input: Int = 0, tools: [String] = [], sidechain: Bool = false, agent: String? = nil
) -> TranscriptEvent {
    makeEvent(
        messageID: id, requestID: "r-\(id)", cwd: cwd, model: model, isSidechain: sidechain,
        attributionAgent: agent,
        usage: TokenUsage(input: input, output: 0, cacheCreation: 0, cacheRead: 0),
        toolNames: tools)
}

@Test func breakdownByModelRanksDescending() {
    let events = [
        event("a", model: "haiku", input: 5),
        event("b", model: "opus", input: 100),
        event("c", model: "haiku", input: 7),
    ]

    let rows = Aggregation.breakdown(.model, metric: .inputOutput, over: events, limit: 10, home: home, timeframe: .allTime)

    #expect(rows.map(\.label) == ["opus", "haiku"])
    #expect(rows.map(\.value) == [100, 12])
}

/// Unknown model identifiers appear as they are, neither classified nor dropped.
@Test func unknownModelsAreReportedVerbatim() {
    let rows = Aggregation.breakdown(
        .model, metric: .requests, over: [event("a", model: "gpt-5.5")], limit: 10, home: home, timeframe: .allTime)

    #expect(rows.map(\.label) == ["gpt-5.5"])
}

/// Tokens are counted once per message even when the message spans several lines.
@Test func breakdownByModelDeduplicatesMessages() {
    let usage = TokenUsage(input: 50, output: 0, cacheCreation: 0, cacheRead: 0)
    let split = [
        makeEvent(messageID: "m", requestID: "r", model: "opus", usage: usage),
        makeEvent(messageID: "m", requestID: "r", model: "opus", usage: usage, toolNames: ["Bash"]),
    ]

    let rows = Aggregation.breakdown(.model, metric: .inputOutput, over: split, limit: 10, home: home, timeframe: .allTime)

    #expect(rows.map(\.value) == [50])
}

@Test func breakdownByProjectUsesShortNameAndKeepsTheFullPath() throws {
    let events = [
        event("a", cwd: "/Users/me/go/snitch", input: 3),
        event("b", cwd: "/Users/me/go/snitch", input: 4),
    ]

    let rows = Aggregation.breakdown(
        .project, metric: .inputOutput, over: events, limit: 10, home: home, timeframe: .allTime)

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

    let byTokens = Aggregation.breakdown(.tool, metric: .inputOutput, over: split, limit: 10, home: home, timeframe: .allTime)
    let byRequests = Aggregation.breakdown(.tool, metric: .requests, over: split, limit: 10, home: home, timeframe: .allTime)

    #expect(byTokens.map(\.label) == ["Bash", "Read"])
    #expect(byTokens.map(\.value) == [2, 1])
    #expect(byTokens == byRequests)
}

@Test func limitTruncatesTheTail() {
    let events = (1...5).map { event("\($0)", model: "m\($0)", input: $0) }

    let rows = Aggregation.breakdown(.model, metric: .inputOutput, over: events, limit: 2, home: home, timeframe: .allTime)

    #expect(rows.map(\.label) == ["m5", "m4"])
}

@Test func breakdownOverNoEventsIsEmpty() {
    for dimension in BreakdownDimension.allCases {
        #expect(Aggregation.breakdown(dimension, metric: .allTokens, over: [], limit: 5, home: home, timeframe: .allTime).isEmpty)
    }
}

/// Ties must not reorder run to run, or the chart would flicker between renders.
@Test func tiesAreBrokenByLabelSoOrderIsStable() {
    let events = [event("a", model: "zebra", input: 1), event("b", model: "alpha", input: 1)]

    let rows = Aggregation.breakdown(.model, metric: .inputOutput, over: events, limit: 10, home: home, timeframe: .allTime)

    #expect(rows.map(\.label) == ["alpha", "zebra"])
}

@Test func breakdownByAgentSeparatesMainFromTypes() {
    let events = [
        event("a", input: 100),
        event("b", input: 60, sidechain: true, agent: "general-purpose"),
        event("c", input: 30, sidechain: true, agent: "Explore"),
        event("d", input: 10, sidechain: true, agent: "general-purpose"),
    ]

    let rows = Aggregation.breakdown(
        .agent, metric: .allTokens, over: events, limit: 10, home: home, timeframe: .allTime)

    #expect(rows.map(\.label) == ["main", "general-purpose", "Explore"])
    #expect(rows.map(\.value) == [100, 70, 30])
}

@Test func breakdownByAgentBucketsUntypedSidechainUnderSubagent() {
    let rows = Aggregation.breakdown(
        .agent, metric: .allTokens,
        over: [event("a", input: 5, sidechain: true, agent: nil)],
        limit: 10, home: home, timeframe: .allTime)

    #expect(rows.map(\.label) == ["subagent"])
    #expect(rows.map(\.value) == [5])
}

@Test func agentBreakdownConservesTheAllTokensTotal() {
    let events = [
        event("a", input: 100),
        event("b", input: 60, sidechain: true, agent: "general-purpose"),
        event("c", input: 5, sidechain: true, agent: nil),
    ]

    let rowsSum = Aggregation.breakdown(
        .agent, metric: .allTokens, over: events, limit: .max, home: home, timeframe: .allTime
    ).reduce(0) { $0 + $1.value }
    let total = Aggregation.total(.allTokens, over: events, timeframe: .allTime)

    #expect(rowsSum == total)
}
