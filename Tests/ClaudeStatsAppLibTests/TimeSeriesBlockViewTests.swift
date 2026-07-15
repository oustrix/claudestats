import SwiftUI
import Testing
import ViewInspector

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

/// A `Chart`'s bars are opaque to ViewInspector, so this asserts only that the view builds a valid
/// tree for both empty and non-empty data — that it renders at all, in either state — not what the
/// bars look like.

@MainActor @Test func timeSeriesRendersWithData() throws {
    let block = BlockConfig(
        type: .timeSeries, metric: .inputOutput, timeframe: .allTime, bucket: .day)
    let events = [
        makeEvent(messageID: "a", requestID: "a"),
        makeEvent(messageID: "b", requestID: "b"),
    ]

    _ = try TimeSeriesBlockView(block: block, events: events).inspect()
}

@MainActor @Test func timeSeriesRendersWhenEmpty() throws {
    let block = BlockConfig(
        type: .timeSeries, metric: .inputOutput, timeframe: .allTime, bucket: .day)

    _ = try TimeSeriesBlockView(block: block, events: []).inspect()
}

// MARK: - Bar hover geometry

/// `barSlotIndex` is the lattice that maps a cursor's x to a bar, so the chart's opaque bars still get
/// a per-bar tooltip. These pin down the slot boundaries the hover depends on.

@Test func barSlotIndexMapsColumnsAcrossThePlot() {
    // Four slots of width 10 starting at x = 100 → the band [100, 140).
    #expect(barSlotIndex(x: 100, plotMinX: 100, slotWidth: 10, count: 4) == 0)
    #expect(barSlotIndex(x: 109.9, plotMinX: 100, slotWidth: 10, count: 4) == 0)
    #expect(barSlotIndex(x: 110, plotMinX: 100, slotWidth: 10, count: 4) == 1)
    #expect(barSlotIndex(x: 135, plotMinX: 100, slotWidth: 10, count: 4) == 3)
}

@Test func barSlotIndexRejectsPointsOutsideTheBand() {
    #expect(barSlotIndex(x: 99.9, plotMinX: 100, slotWidth: 10, count: 4) == nil)
    #expect(barSlotIndex(x: 140, plotMinX: 100, slotWidth: 10, count: 4) == nil)  // upper is exclusive
    #expect(barSlotIndex(x: 500, plotMinX: 100, slotWidth: 10, count: 4) == nil)
}

@Test func barSlotIndexHandlesDegenerateInput() {
    #expect(barSlotIndex(x: 5, plotMinX: 0, slotWidth: 10, count: 0) == nil)
    #expect(barSlotIndex(x: 5, plotMinX: 0, slotWidth: 0, count: 4) == nil)
}

// MARK: - Tooltip placement

@Test func tooltipSitsAboveTheTargetWhenThereIsRoom() {
    let target = CGRect(x: 40, y: 100, width: 10, height: 60)
    let bubble = CGSize(width: 80, height: 24)
    let position = tooltipPosition(target: target, bubbleSize: bubble, in: CGSize(width: 200, height: 200))
    #expect(position.x == 45)  // the target's midX
    let expectedY: CGFloat = 100 - 6 - 12  // above: minY − 6 − height/2
    #expect(position.y == expectedY)
}

@Test func tooltipFlipsBelowWhenTheTargetHugsTheTop() {
    let target = CGRect(x: 40, y: 5, width: 10, height: 60)  // no room above
    let bubble = CGSize(width: 80, height: 24)
    let position = tooltipPosition(target: target, bubbleSize: bubble, in: CGSize(width: 200, height: 200))
    #expect(position.y == target.maxY + 6 + 12)  // below: maxY + 6 + height/2
}

@Test func tooltipClampsToTheContainerEdges() {
    let bubble = CGSize(width: 80, height: 24)  // halfWidth 40
    let container = CGSize(width: 200, height: 200)
    let atLeft = tooltipPosition(
        target: CGRect(x: 0, y: 100, width: 4, height: 40), bubbleSize: bubble, in: container)
    #expect(atLeft.x == 40)  // clamped to halfWidth
    let atRight = tooltipPosition(
        target: CGRect(x: 196, y: 100, width: 4, height: 40), bubbleSize: bubble, in: container)
    #expect(atRight.x == 160)  // clamped to width − halfWidth
}

// MARK: - Tooltip label

@Test func timeSeriesLabelShowsTheExactValueAndUnit() {
    let point = DataPoint(date: Date(timeIntervalSince1970: 1_700_000_000), value: 1_234_567)
    let label = timeSeriesLabel(for: point, bucket: .day, unit: "tokens")
    #expect(label.contains(1_234_567.grouped))  // every digit, not the compact headline form
    #expect(label.hasSuffix("tokens"))
}

@Test func timeSeriesLabelAddsTheHourForHourBuckets() {
    let point = DataPoint(date: Date(timeIntervalSince1970: 1_700_000_000), value: 10)
    let day = timeSeriesLabel(for: point, bucket: .day, unit: "requests")
    let hour = timeSeriesLabel(for: point, bucket: .hour, unit: "requests")
    #expect(hour != day)
    #expect(hour.count > day.count)  // the hour component makes the hour label the longer one
}
