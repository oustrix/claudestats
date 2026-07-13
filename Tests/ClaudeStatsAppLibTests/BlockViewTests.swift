import SwiftUI
import Testing
import ViewInspector

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

/// All timeframes here are `.allTime`, so `Aggregation.filter` ignores `now` (it has no lower bound)
/// and the rendered result does not drift with the wall clock — the determinism the design calls for.
/// A missing `find` throws, which fails the test on its own; no assertion wrapper is needed.

// MARK: - BigNumberBlockView

@MainActor @Test func bigNumberShowsTheFormattedTotalAndMetricTitle() throws {
    let block = BlockConfig(type: .bigNumber, metric: .inputOutput, timeframe: .allTime)
    let events = [
        makeEvent(messageID: "a", requestID: "a", usage: TokenUsage(input: 10, output: 5, cacheCreation: 0, cacheRead: 0))
    ]
    let view = try BigNumberBlockView(block: block, events: events).inspect()

    // input + output = 15, formatted compactly.
    _ = try view.find(text: "15")
    _ = try view.find(text: "Input + output")
}

// MARK: - BreakdownBlockView

@MainActor @Test func breakdownShowsOneRowPerModelWithItsLabel() throws {
    let block = BlockConfig(
        type: .breakdown, metric: .inputOutput, timeframe: .allTime, dimension: .model, limit: 8)
    let events = [
        makeEvent(messageID: "a", requestID: "a", model: "alpha-model"),
        makeEvent(messageID: "b", requestID: "b", model: "beta-model"),
        makeEvent(messageID: "c", requestID: "c", model: "gamma-model"),
    ]
    let view = try BreakdownBlockView(block: block, events: events, home: home).inspect()

    _ = try view.find(text: "alpha-model")
    _ = try view.find(text: "beta-model")
    _ = try view.find(text: "gamma-model")
    // A label that was never in the data is not rendered — the row count is exactly the models seen.
    #expect((try? view.find(text: "delta-model")) == nil)
}

@MainActor @Test func breakdownShowsAnEmptyMessageWithNoData() throws {
    let block = BlockConfig(
        type: .breakdown, metric: .inputOutput, timeframe: .allTime, dimension: .model, limit: 8)
    let view = try BreakdownBlockView(block: block, events: [], home: home).inspect()

    _ = try view.find(text: "Nothing in this timeframe")
}

// MARK: - SessionListBlockView

@MainActor @Test func sessionListShowsOneRowPerSession() throws {
    let block = BlockConfig(type: .sessionList, timeframe: .allTime, limit: 10)
    let events = [
        makeEvent(messageID: "a", requestID: "a", sessionID: "s1", cwd: "/Users/me/proj-a"),
        makeEvent(messageID: "b", requestID: "b", sessionID: "s2", cwd: "/Users/me/proj-b"),
    ]
    let view = try SessionListBlockView(block: block, events: events, home: home).inspect()

    _ = try view.find(text: "proj-a")
    _ = try view.find(text: "proj-b")
}

@MainActor @Test func sessionListShowsAnEmptyMessageWithNoData() throws {
    let block = BlockConfig(type: .sessionList, timeframe: .allTime, limit: 10)
    let view = try SessionListBlockView(block: block, events: [], home: home).inspect()

    _ = try view.find(text: "No sessions in this timeframe")
}
