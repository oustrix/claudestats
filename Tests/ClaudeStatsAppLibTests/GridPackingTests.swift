import Testing

@testable import ClaudeStatsAppLib

/// The twelve-column grid packs blocks into rows greedily, preserving the authored order. These
/// pin the pure packing rule the `DashboardView` grid maps into `HStack`s.

@Test func threeSpanFourBlocksShareOneRow() {
    #expect(packRows(spans: [4, 4, 4]) == [[0, 1, 2]])
}

@Test func aFullRowIsFollowedByANewRow() {
    // Three span-4 blocks fill row one; a span-12 block cannot fit, so it starts row two.
    #expect(packRows(spans: [4, 4, 4, 12]) == [[0, 1, 2], [3]])
}

@Test func packingPreservesAuthoredOrder() {
    // A span-8 then a span-4 fill a row; the next span-8 overflows to its own row. Order is kept —
    // the later span-4 is not pulled up to fill the second row's gap.
    #expect(packRows(spans: [8, 4, 8, 4]) == [[0, 1], [2, 3]])
}

@Test func aRunThatExactlyFillsTwelveClosesTheRow() {
    #expect(packRows(spans: [6, 6, 6, 6]) == [[0, 1], [2, 3]])
}

@Test func spansAreClampedIntoRange() {
    // A hand-edited span of 0 or above 12 is coerced to 1…12 rather than breaking the packing.
    #expect(packRows(spans: [0, 99]) == [[0], [1]])
}

@Test func anEmptyLayoutPacksToNoRows() {
    #expect(packRows(spans: []) == [])
}

@Test func aSingleFullWidthBlockIsOneRow() {
    #expect(packRows(spans: [12]) == [[0]])
}
