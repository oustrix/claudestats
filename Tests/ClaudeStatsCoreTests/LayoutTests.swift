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

    #expect(decoded.skippedTypes.isEmpty)
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
    #expect(decoded.skippedTypes == ["flameGraph"])
}

/// An unknown *parameter* value is a different failure: the block type is known, the value is not.
@Test func anUnknownMetricIsSkippedAndNamed() throws {
    let data = json(
        """
        {"version": 1, "blocks": [
          {"id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "type": "bigNumber",
           "metric": "thoughtsPerSecond", "timeframe": "allTime"}
        ]}
        """)

    let decoded = try Layout.decode(data)

    #expect(decoded.layout.blocks.isEmpty)
    #expect(decoded.skippedTypes == ["bigNumber"])
}

@Test func malformedJSONIsReportedAsSuch() {
    #expect(throws: (any Error).self) {
        try Layout.decode(json("{this is not json"))
    }
}

@Test func aLayoutWithoutBlocksDecodesToAnEmptyDashboard() throws {
    let decoded = try Layout.decode(json(#"{"version": 1, "blocks": []}"#))

    #expect(decoded.layout.blocks.isEmpty)
    #expect(decoded.skippedTypes.isEmpty)
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

// MARK: - Default layout

@Test func theDefaultLayoutCoversEveryBlockType() {
    let types = Set(Layout.default.blocks.map(\.type))

    #expect(types == Set(BlockType.allCases))
}

/// Cache reads are over 90% of all tokens, so the headline number must be the work, not the cache.
@Test func theDefaultHeadlineMetricIsInputOutput() throws {
    let headline = try #require(Layout.default.blocks.first { $0.type == .bigNumber })

    #expect(headline.metric == .inputOutput)
}
