import SwiftUI
import Testing
import ViewInspector

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

/// All timeframes here are `.allTime`, so `Aggregation.filter` ignores `now` (it has no lower bound)
/// and the rendered result does not drift with the wall clock — the determinism the design calls for.
/// A missing `find` throws, which fails the test on its own; no assertion wrapper is needed.

// MARK: - BigNumberBlockView

@MainActor @Test func bigNumberShowsTheFormattedTotal() throws {
    let block = BlockConfig(type: .bigNumber, metric: .inputOutput, timeframe: .allTime)
    let events = [
        makeEvent(messageID: "a", requestID: "a", usage: TokenUsage(input: 10, output: 5, cacheCreation: 0, cacheRead: 0))
    ]
    let view = try BigNumberBlockView(block: block, events: events).inspect()

    // input + output = 15, formatted compactly. The metric name and timeframe are the card header's
    // job (`BlockCard`), so the body no longer repeats them — it is just the figure and its delta.
    _ = try view.find(text: "15")
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

// MARK: - BreakdownDetailView

/// The card shows a top-N; the modal shows every row. With a limit of 2 and three models, the modal
/// still lists all three — the full ranking, not the card's truncation.
@MainActor @Test func breakdownDetailListsEveryRowBeyondTheCardLimit() throws {
    let block = BlockConfig(
        type: .breakdown, metric: .inputOutput, timeframe: .allTime, dimension: .model, limit: 2)
    let events = [
        makeEvent(messageID: "a", requestID: "a", model: "alpha-model"),
        makeEvent(messageID: "b", requestID: "b", model: "beta-model"),
        makeEvent(messageID: "c", requestID: "c", model: "gamma-model"),
    ]
    let view = try BreakdownDetailView(block: block, events: events, home: home).inspect()

    _ = try view.find(text: "alpha-model")
    _ = try view.find(text: "beta-model")
    _ = try view.find(text: "gamma-model")
}

/// The modal header names the dimension and carries a count-and-scope pill: N rows and the timeframe.
@MainActor @Test func breakdownDetailShowsTheDimensionTitleAndCountPill() throws {
    let block = BlockConfig(
        type: .breakdown, metric: .inputOutput, timeframe: .allTime, dimension: .model, limit: 8)
    let events = [
        makeEvent(messageID: "a", requestID: "a", model: "alpha-model"),
        makeEvent(messageID: "b", requestID: "b", model: "beta-model"),
    ]
    let view = try BreakdownDetailView(block: block, events: events, home: home).inspect()

    _ = try view.find(text: "Input + output by model")
    _ = try view.find(text: "2 models · All time")
}

/// A tool breakdown ignores the metric and counts invocations, so its pill scope reads "invocations".
@MainActor @Test func breakdownDetailToolPillReadsInvocations() throws {
    let block = BlockConfig(
        type: .breakdown, metric: .requests, timeframe: .allTime, dimension: .tool, limit: 8)
    let events = [makeEvent(messageID: "a", requestID: "a", toolNames: ["Bash"])]
    let view = try BreakdownDetailView(block: block, events: events, home: home).inspect()

    _ = try view.find(text: "By tool")
    _ = try view.find(text: "1 tool · invocations")
}

@MainActor @Test func breakdownDetailShowsAnEmptyMessageWithNoData() throws {
    let block = BlockConfig(
        type: .breakdown, metric: .inputOutput, timeframe: .allTime, dimension: .model, limit: 8)
    let view = try BreakdownDetailView(block: block, events: [], home: home).inspect()

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

// MARK: - CostBlockView

/// A rate of $5/Mtok input over 2,000,000 input tokens is $10.00, drawn as currency.
@MainActor @Test func costCardShowsTheCurrencyEstimate() throws {
    let block = BlockConfig(type: .cost, timeframe: .allTime)
    let pricing = Pricing(rates: ["opus": ModelRate(input: 5, output: 0, cacheWrite: 0, cacheRead: 0)])
    let events = [
        makeEvent(
            messageID: "a", requestID: "a", model: "claude-opus-4-8",
            usage: TokenUsage(input: 2_000_000, output: 0, cacheCreation: 0, cacheRead: 0))
    ]
    let view = try CostBlockView(block: block, events: events, pricing: pricing).inspect()

    _ = try view.find(text: "$10.00")
    _ = try view.find(text: "estimate · not a bill")
}

/// An unpriced model is named, not silently costed at zero.
@MainActor @Test func costCardSurfacesAnUnpricedModel() throws {
    let block = BlockConfig(type: .cost, timeframe: .allTime)
    let events = [makeEvent(messageID: "a", requestID: "a", model: "gpt-5.5")]
    let view = try CostBlockView(block: block, events: events, pricing: .default).inspect()

    _ = try view.find(text: "1 model(s) unpriced")
}

/// With a pricing, the session row carries an accent-coloured cost column; without one, it does not.
@MainActor @Test func sessionListShowsCostColumnOnlyWhenPriced() throws {
    let block = BlockConfig(type: .sessionList, timeframe: .allTime, limit: 10)
    let pricing = Pricing(rates: ["opus": ModelRate(input: 5, output: 0, cacheWrite: 0, cacheRead: 0)])
    let events = [
        makeEvent(
            messageID: "a", requestID: "a", sessionID: "s1", cwd: "/Users/me/proj-a",
            model: "claude-opus-4-8",
            usage: TokenUsage(input: 1_000_000, output: 0, cacheCreation: 0, cacheRead: 0))
    ]

    let priced = try SessionListBlockView(
        block: block, events: events, home: home, pricing: pricing).inspect()
    _ = try priced.find(text: "$5.00")

    let unpriced = try SessionListBlockView(
        block: block, events: events, home: home, pricing: nil).inspect()
    #expect((try? unpriced.find(text: "$5.00")) == nil)
}
