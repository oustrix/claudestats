import Foundation
import Testing

@testable import ClaudeStatsCore

/// The usage object a split message repeats on every one of its lines.
private let sharedUsage = TokenUsage(input: 2, output: 207, cacheCreation: 5481, cacheRead: 75382)

/// One assistant message written as two lines: a `text` block and a `tool_use` block, each
/// carrying the same final `usage`. This is the shape that inflates naive counts.
private let splitMessage = [
    makeEvent(messageID: "msg-1", requestID: "req-1", usage: sharedUsage, toolNames: []),
    makeEvent(messageID: "msg-1", requestID: "req-1", usage: sharedUsage, toolNames: ["Bash"]),
]

@Test func tokensOfASplitMessageAreCountedOnce() {
    let messages = deduplicatedMessages(from: splitMessage)

    #expect(messages.count == 1)
    #expect(messages.first?.usage == sharedUsage)
}

@Test func everyToolBlockOfASplitMessageIsCounted() {
    let tools = toolInvocations(from: splitMessage)

    #expect(tools == ["Bash"])
}

/// Two lines of one message, each with a tool block: two invocations, one usage.
@Test func toolsAreNotDeduplicatedWhileTokensAre() {
    let events = [
        makeEvent(messageID: "m", requestID: "r", usage: sharedUsage, toolNames: ["Bash"]),
        makeEvent(messageID: "m", requestID: "r", usage: sharedUsage, toolNames: ["Read"]),
    ]

    #expect(deduplicatedMessages(from: events).count == 1)
    #expect(toolInvocations(from: events) == ["Bash", "Read"])
}

@Test func distinctMessagesAreNeverMerged() {
    let events = [
        makeEvent(messageID: "msg-1", requestID: "req-1"),
        makeEvent(messageID: "msg-2", requestID: "req-1"),
        makeEvent(messageID: "msg-2", requestID: "req-2"),
    ]

    #expect(deduplicatedMessages(from: events).map(\.messageID) == ["msg-1", "msg-2", "msg-2"])
}

/// A missing requestId must not collapse two messages into one.
@Test func messagesWithoutRequestIDStayDistinct() {
    let events = [
        makeEvent(messageID: "msg-1", requestID: nil),
        makeEvent(messageID: "msg-2", requestID: nil),
    ]

    #expect(deduplicatedMessages(from: events).count == 2)
}

@Test func deduplicationKeepsTheFirstOccurrenceAndItsOrder() {
    let events = [
        makeEvent(messageID: "b", requestID: "r", model: "first"),
        makeEvent(messageID: "a", requestID: "r"),
        makeEvent(messageID: "b", requestID: "r", model: "second"),
    ]

    let messages = deduplicatedMessages(from: events)

    #expect(messages.map(\.messageID) == ["b", "a"])
    #expect(messages.first?.model == "first")
}

/// The whole reason this module exists. If someone ever "simplifies" the counting back to summing
/// lines, this test fails: the naive total is 2x the true one on a message split across two lines.
@Test func naiveLineSumInflatesTheTrueTotal() {
    let naive = splitMessage.reduce(0) { $0 + $1.usage.input + $1.usage.output }
    let honest = deduplicatedMessages(from: splitMessage)
        .reduce(0) { $0 + $1.usage.input + $1.usage.output }

    #expect(naive == 418)
    #expect(honest == 209)
}

@Test func emptyInputYieldsEmptyOutput() {
    #expect(deduplicatedMessages(from: []).isEmpty)
    #expect(toolInvocations(from: []).isEmpty)
}
