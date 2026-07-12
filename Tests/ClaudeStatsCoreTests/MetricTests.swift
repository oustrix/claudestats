import Foundation
import Testing

@testable import ClaudeStatsCore

private let usage = TokenUsage(input: 10, output: 20, cacheCreation: 300, cacheRead: 4000)

/// One response written across two lines, so every metric must see it once.
private let splitMessage = [
    makeEvent(messageID: "m", requestID: "r", usage: usage),
    makeEvent(messageID: "m", requestID: "r", usage: usage),
]

@Test func inputOutputExcludesCacheCounters() {
    #expect(Aggregation.total(.inputOutput, over: splitMessage, timeframe: .allTime) == 30)
}

@Test func cacheMetricsReportTheirOwnCounter() {
    #expect(Aggregation.total(.cacheRead, over: splitMessage, timeframe: .allTime) == 4000)
    #expect(Aggregation.total(.cacheCreation, over: splitMessage, timeframe: .allTime) == 300)
}

@Test func allTokensSumsEveryCounter() {
    #expect(Aggregation.total(.allTokens, over: splitMessage, timeframe: .allTime) == 4330)
}

/// The requests metric counts responses, not the lines they were written across.
@Test func requestsCountsMessagesNotLines() {
    let threeLinesOneMessage = [
        makeEvent(messageID: "m", requestID: "r"),
        makeEvent(messageID: "m", requestID: "r"),
        makeEvent(messageID: "m", requestID: "r"),
    ]

    #expect(Aggregation.total(.requests, over: threeLinesOneMessage, timeframe: .allTime) == 1)
}

@Test func totalsOverNoEventsAreZero() {
    for metric in Metric.allCases {
        #expect(Aggregation.total(metric, over: [], timeframe: .allTime) == 0)
    }
}

@Test func totalsAddUpAcrossMessages() {
    let events = [
        makeEvent(messageID: "a", usage: TokenUsage(input: 1, output: 2, cacheCreation: 3, cacheRead: 4)),
        makeEvent(messageID: "b", usage: TokenUsage(input: 10, output: 20, cacheCreation: 30, cacheRead: 40)),
    ]

    #expect(Aggregation.total(.inputOutput, over: events, timeframe: .allTime) == 33)
    #expect(Aggregation.total(.allTokens, over: events, timeframe: .allTime) == 110)
    #expect(Aggregation.total(.requests, over: events, timeframe: .allTime) == 2)
}
