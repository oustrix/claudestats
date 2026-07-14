import Foundation
import Testing

@testable import ClaudeStatsCore

private let opusOnly = Pricing(rates: [
    "opus": ModelRate(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5)
])

private func costEvent(
    _ id: String, model: String = "claude-opus-4-8", at iso: String = "2026-07-13T12:00:00Z",
    input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0,
    stopReason: String? = "end_turn"
) -> TranscriptEvent {
    makeEvent(
        messageID: id, requestID: "r-\(id)", timestamp: instant(iso), model: model,
        usage: TokenUsage(
            input: input, output: output, cacheCreation: cacheCreation, cacheRead: cacheRead),
        stopReason: stopReason)
}

/// Exact dollars for known tokens under known rates, to the cent.
@Test func costIsTokensTimesRateSummedOverMessages() {
    let events = [
        // $5/Mtok input over 1M = $5, plus $25/Mtok output over 200K = $5 → $10
        costEvent("a", input: 1_000_000, output: 200_000),
        // $0.50/Mtok cache-read over 2M = $1
        costEvent("b", cacheRead: 2_000_000),
    ]
    let estimate = Aggregation.cost(over: events, pricing: opusOnly, timeframe: .allTime)
    #expect(estimate.total == 11)
    #expect(estimate.unpricedModels.isEmpty)
    #expect(estimate.perModel["claude-opus-4-8"] == 11)
}

/// An unpriced model contributes nothing and is surfaced, never silently costed at zero.
@Test func anUnpricedModelIsSurfacedNotCostedZero() {
    let events = [
        costEvent("a", input: 1_000_000),  // opus → $5
        costEvent("b", model: "gpt-5.5", input: 1_000_000),  // unpriced → nothing
    ]
    let estimate = Aggregation.cost(over: events, pricing: opusOnly, timeframe: .allTime)
    #expect(estimate.total == 5)
    #expect(estimate.unpricedModels == ["gpt-5.5"])
    #expect(estimate.perModel["gpt-5.5"] == nil)
}

/// Cost deduplicates like the token counters: a response written across several streaming lines is
/// costed once, from the line bearing the stop reason.
@Test func costDeduplicatesResponsesWrittenAcrossLines() {
    // Streaming placeholder line then the final line, same message id.
    let events = [
        costEvent("m", output: 1, stopReason: nil),
        costEvent("m", output: 1_000_000, stopReason: "end_turn"),
    ]
    let estimate = Aggregation.cost(over: events, pricing: opusOnly, timeframe: .allTime)
    // $25/Mtok over 1M output, counted once, not twice.
    #expect(estimate.total == 25)
}

/// Cost windows by timeframe exactly like the token totals.
@Test func costHonorsTheTimeframe() {
    let now = instant("2026-07-13T12:00:00Z")
    let events = [
        costEvent("recent", at: "2026-07-13T09:00:00Z", input: 1_000_000),
        costEvent("old", at: "2026-06-01T09:00:00Z", input: 1_000_000),
    ]
    let estimate = Aggregation.cost(over: events, pricing: opusOnly, timeframe: .last7Days, now: now)
    #expect(estimate.total == 5)
}

/// A session carries the summed cost of its messages when a pricing is supplied.
@Test func sessionsCarryEstimatedCostWhenPriced() throws {
    let events = [
        costEvent("a", at: "2026-07-02T09:00:00Z", input: 1_000_000),
        costEvent("b", at: "2026-07-02T10:00:00Z", output: 400_000),  // $10/Mtok? no: $25*0.4 = $10
    ]
    let sessions = Aggregation.sessions(
        from: events, home: "/Users/me", timeframe: .allTime, pricing: opusOnly)
    let session = try #require(sessions.first)
    #expect(session.estimatedCost == 15)  // $5 + $10
}

/// Without a pricing, a session has no cost.
@Test func sessionsHaveNoCostWithoutPricing() throws {
    let sessions = Aggregation.sessions(
        from: [costEvent("a", input: 1_000_000)], home: "/Users/me", timeframe: .allTime)
    #expect(try #require(sessions.first).estimatedCost == nil)
}
