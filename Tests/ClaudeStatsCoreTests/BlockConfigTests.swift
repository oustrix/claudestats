import Testing

@testable import ClaudeStatsCore

/// The editor offers each block type only the buckets it can draw. This is the data behind that
/// rule; the `BlockEditor` field-presence tests confirm the view actually reads it.
@Test func supportedBucketsAreTheGranularitiesEachTypeCanDraw() {
    #expect(BlockType.timeSeries.supportedBuckets == [.day, .hour])
    #expect(BlockType.heatmap.supportedBuckets == [.day, .week])
    #expect(BlockType.bigNumber.supportedBuckets.isEmpty)
    #expect(BlockType.breakdown.supportedBuckets.isEmpty)
    #expect(BlockType.sessionList.supportedBuckets.isEmpty)
}

/// An omitted parameter resolves to the same default the factory seeds, so a hand-edited layout that
/// drops a field renders identically to a freshly added block.
@Test func resolvedParametersFallBackToTheSharedDefaults() {
    let bare = BlockConfig(type: .breakdown, timeframe: .last30Days)

    #expect(bare.resolvedMetric == BlockConfig.defaultMetric)
    #expect(bare.resolvedBucket == BlockConfig.defaultBucket)
    #expect(bare.resolvedDimension == BlockConfig.defaultDimension)
    #expect(bare.resolvedLimit == BlockConfig.defaultLimit(for: .breakdown))
}

@Test func resolvedParametersReturnTheStoredValueWhenPresent() {
    let full = BlockConfig(
        type: .breakdown, metric: .cacheRead, timeframe: .allTime, bucket: .week,
        dimension: .project, limit: 17)

    #expect(full.resolvedMetric == .cacheRead)
    #expect(full.resolvedBucket == .week)
    #expect(full.resolvedDimension == .project)
    #expect(full.resolvedLimit == 17)
}

/// The one place the "sessions default to 10 rows, everything else to 8" rule lives.
@Test func theDefaultRowLimitDependsOnTheType() {
    #expect(BlockConfig.defaultLimit(for: .sessionList) == 10)
    #expect(BlockConfig.defaultLimit(for: .breakdown) == 8)
}
