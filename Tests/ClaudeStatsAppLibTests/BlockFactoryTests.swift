import Testing

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

/// `newBlock(of:)` seeds a fresh block with exactly the parameters its type uses — set to the shared
/// defaults — and leaves the rest `nil`, so `layout.json` never carries a field a type ignores.

@Test func newBigNumberUsesMetricAndTimeframeOnly() {
    let block = BlockConfig.newBlock(of: .bigNumber)
    #expect(block.type == .bigNumber)
    #expect(block.metric == BlockConfig.defaultMetric)
    #expect(block.timeframe == .last7Days)
    #expect(block.bucket == nil)
    #expect(block.dimension == nil)
    #expect(block.limit == nil)
}

@Test func newTimeSeriesUsesMetricTimeframeAndBucket() {
    let block = BlockConfig.newBlock(of: .timeSeries)
    #expect(block.type == .timeSeries)
    #expect(block.metric == BlockConfig.defaultMetric)
    #expect(block.timeframe == .last30Days)
    #expect(block.bucket == BlockConfig.defaultBucket)
    #expect(block.dimension == nil)
    #expect(block.limit == nil)
}

@Test func newBreakdownUsesMetricTimeframeDimensionAndLimit() {
    let block = BlockConfig.newBlock(of: .breakdown)
    #expect(block.type == .breakdown)
    #expect(block.metric == BlockConfig.defaultMetric)
    #expect(block.timeframe == .last30Days)
    #expect(block.dimension == BlockConfig.defaultDimension)
    #expect(block.limit == BlockConfig.defaultLimit(for: .breakdown))
    #expect(block.bucket == nil)
}

@Test func newSessionListUsesTimeframeAndLimitButNoMetric() {
    let block = BlockConfig.newBlock(of: .sessionList)
    #expect(block.type == .sessionList)
    #expect(block.metric == nil)
    #expect(block.timeframe == .last7Days)
    #expect(block.limit == BlockConfig.defaultLimit(for: .sessionList))
    #expect(block.bucket == nil)
    #expect(block.dimension == nil)
}

@Test func newHeatmapUsesMetricAndBucketButNoDimensionOrLimit() {
    let block = BlockConfig.newBlock(of: .heatmap)
    #expect(block.type == .heatmap)
    #expect(block.metric == BlockConfig.defaultMetric)
    #expect(block.bucket == BlockConfig.defaultBucket)
    #expect(block.dimension == nil)
    #expect(block.limit == nil)
}

/// Only a fixed-window block (the heatmap) labels its own span; a timeframe-driven block returns
/// `nil` here, which is also what tells the editor to drop the Timeframe control. Lives in the app
/// layer because the label is a presentation string.
@Test func fixedWindowLabelIsSetForTheHeatmapOnly() {
    #expect(BlockType.heatmap.fixedWindowLabel == "Last \(Aggregation.heatmapWeeks) weeks")
    #expect(BlockType.bigNumber.fixedWindowLabel == nil)
    #expect(BlockType.timeSeries.fixedWindowLabel == nil)
    #expect(BlockType.breakdown.fixedWindowLabel == nil)
    #expect(BlockType.sessionList.fixedWindowLabel == nil)
}
