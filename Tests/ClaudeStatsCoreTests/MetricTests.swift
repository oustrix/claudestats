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
    let messages = Counting.messages(from: splitMessage)

    #expect(Aggregation.total(.inputOutput, over: messages) == 30)
}

@Test func cacheMetricsReportTheirOwnCounter() {
    let messages = Counting.messages(from: splitMessage)

    #expect(Aggregation.total(.cacheRead, over: messages) == 4000)
    #expect(Aggregation.total(.cacheCreation, over: messages) == 300)
}

@Test func allTokensSumsEveryCounter() {
    let messages = Counting.messages(from: splitMessage)

    #expect(Aggregation.total(.allTokens, over: messages) == 4330)
}

/// The requests metric counts responses, not the lines they were written across.
@Test func requestsCountsMessagesNotLines() {
    let threeLinesOneMessage = [
        makeEvent(messageID: "m", requestID: "r"),
        makeEvent(messageID: "m", requestID: "r"),
        makeEvent(messageID: "m", requestID: "r"),
    ]

    #expect(Aggregation.total(.requests, over: Counting.messages(from: threeLinesOneMessage)) == 1)
}

@Test func totalsOverNoMessagesAreZero() {
    for metric in Metric.allCases {
        #expect(Aggregation.total(metric, over: []) == 0)
    }
}

@Test func totalsAddUpAcrossMessages() {
    let messages = Counting.messages(from: [
        makeEvent(messageID: "a", usage: TokenUsage(input: 1, output: 2, cacheCreation: 3, cacheRead: 4)),
        makeEvent(messageID: "b", usage: TokenUsage(input: 10, output: 20, cacheCreation: 30, cacheRead: 40)),
    ])

    #expect(Aggregation.total(.inputOutput, over: messages) == 33)
    #expect(Aggregation.total(.allTokens, over: messages) == 110)
    #expect(Aggregation.total(.requests, over: messages) == 2)
}
