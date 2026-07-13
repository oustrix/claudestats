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
