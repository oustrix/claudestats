import Foundation
import Testing

@testable import ClaudeStatsCore

private func json(_ text: String) -> Data { Data(text.utf8) }

@Test func aValidLayoutRoundTrips() throws {
    let layout = Layout(blocks: [
        BlockConfig(type: .bigNumber, metric: .inputOutput, timeframe: .last7Days),
        BlockConfig(type: .breakdown, metric: .allTokens, timeframe: .allTime, dimension: .model, limit: 5),
    ])

    let decoded = try Layout.decode(Layout.encode(layout)).layout

    #expect(decoded == layout)
}

@Test func aLayoutDecodesFromHandWrittenJSON() throws {
    let data = json(
        """
        {"version": 1, "blocks": [
          {"id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "type": "timeSeries",
           "metric": "cacheRead", "timeframe": "last30Days", "bucket": "hour"}
        ]}
        """)

    let decoded = try Layout.decode(data)

    #expect(decoded.skipped.isEmpty)
    #expect(decoded.layout.blocks.count == 1)
    #expect(decoded.layout.blocks[0].type == .timeSeries)
    #expect(decoded.layout.blocks[0].metric == .cacheRead)
    #expect(decoded.layout.blocks[0].bucket == .hour)
}

/// An older build must survive a newer config: it draws what it understands and says what it did not.
@Test func anUnknownBlockTypeIsSkippedAndNamed() throws {
    let data = json(
        """
        {"version": 1, "blocks": [
          {"id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "type": "bigNumber",
           "metric": "inputOutput", "timeframe": "allTime"},
          {"id": "3F2504E0-4F89-11D3-9A0C-0305E82C3302", "type": "flameGraph",
           "timeframe": "allTime"}
        ]}
        """)

    let decoded = try Layout.decode(data)

    #expect(decoded.layout.blocks.count == 1)
    #expect(decoded.skipped == [.unknownType("flameGraph")])
}

/// An unknown *parameter* value is a different failure: the block type is known, the value is not.
/// Telling the user "unknown block type: bigNumber" about a type this build fully supports would
/// send them looking for a new release instead of for their typo.
@Test func anUnknownMetricIsReportedAsABadParameterNotABadType() throws {
    let data = json(
        """
        {"version": 1, "blocks": [
          {"id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "type": "bigNumber",
           "metric": "thoughtsPerSecond", "timeframe": "allTime"}
        ]}
        """)

    let decoded = try Layout.decode(data)

    #expect(decoded.layout.blocks.isEmpty)
    #expect(decoded.skipped == [.unreadableParameters(type: .bigNumber)])
}

@Test func malformedJSONIsReportedAsSuch() {
    #expect(throws: (any Error).self) {
        try Layout.decode(json("{this is not json"))
    }
}

@Test func aLayoutWithoutBlocksDecodesToAnEmptyDashboard() throws {
    let decoded = try Layout.decode(json(#"{"version": 1, "blocks": []}"#))

    #expect(decoded.layout.blocks.isEmpty)
    #expect(decoded.skipped.isEmpty)
}

/// Identity survives a round trip, so reordering a block does not recreate it.
@Test func blockIdentifiersArePreserved() throws {
    let block = BlockConfig(type: .sessionList, timeframe: .last7Days, limit: 10)
    let layout = Layout(blocks: [block])

    let decoded = try Layout.decode(Layout.encode(layout)).layout

    #expect(decoded.blocks[0].id == block.id)
}

@Test func theEncodedFormIsReadableAndVersioned() throws {
    let data = try Layout.encode(Layout(blocks: [BlockConfig(type: .bigNumber, timeframe: .allTime)]))
    let text = String(decoding: data, as: UTF8.self)

    #expect(text.contains("\"version\" : 1"))
    #expect(text.contains("\"type\" : \"bigNumber\""))
}

// MARK: - Span decoding and round-tripping

/// A layout written before spans existed had one full-width block per row. Decoding it must keep
/// that: a missing `span` means span 12, not a re-flowed dashboard.
@Test func aBlockWithoutASpanDecodesToFullWidth() throws {
    let data = json(
        """
        {"version": 1, "blocks": [
          {"id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "type": "bigNumber",
           "metric": "inputOutput", "timeframe": "allTime"}
        ]}
        """)

    let decoded = try Layout.decode(data)

    #expect(decoded.skipped.isEmpty)
    #expect(decoded.layout.blocks[0].span == 12)
}

/// A new layout carries explicit spans, and they survive an encode/decode round trip.
@Test func explicitSpansRoundTrip() throws {
    let layout = Layout(blocks: [
        BlockConfig(type: .bigNumber, metric: .inputOutput, timeframe: .last7Days, span: 4),
        BlockConfig(type: .timeSeries, metric: .inputOutput, timeframe: .last30Days, bucket: .day, span: 12),
    ])

    let decoded = try Layout.decode(Layout.encode(layout)).layout

    #expect(decoded.blocks.map(\.span) == [4, 12])
    #expect(decoded == layout)
}

// MARK: - Default layout

/// The default dashboard is the mockup arrangement: four KPI cards, a wide time series, three
/// breakdowns, a heatmap and a session list — with the spans that pack them into the grid.
@Test func theDefaultLayoutMatchesTheMockupArrangement() {
    let blocks = Layout.default.blocks

    #expect(blocks.map(\.type) == [
        .bigNumber, .bigNumber, .cost, .bigNumber, .timeSeries, .breakdown, .breakdown, .breakdown,
        .heatmap, .sessionList,
    ])
    #expect(blocks.map(\.span) == [3, 3, 3, 3, 12, 4, 4, 4, 12, 12])
}

/// The four KPI cards are input+output, requests, cost estimate and cache reads — the mockup's top
/// row, with the cost card third.
@Test func theDefaultKPICardsAreInputOutputRequestsCostAndCacheRead() {
    let kpis = Layout.default.blocks.prefix(4)

    #expect(kpis.map(\.type) == [.bigNumber, .bigNumber, .cost, .bigNumber])
    #expect(kpis.map(\.metric) == [.inputOutput, .requests, nil, .cacheRead])
}

/// The three breakdowns rank model, project and tool — the mockup's middle row.
@Test func theDefaultBreakdownsAreModelProjectAndTool() {
    let breakdowns = Layout.default.blocks.filter { $0.type == .breakdown }

    #expect(breakdowns.map(\.dimension) == [.model, .project, .tool])
}

/// Cache reads are over 90% of all tokens, so the headline number must be the work, not the cache.
@Test func theDefaultHeadlineMetricIsInputOutput() throws {
    let headline = try #require(Layout.default.blocks.first { $0.type == .bigNumber })

    #expect(headline.metric == .inputOutput)
}
