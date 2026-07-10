import Foundation

/// Token counters of a single model response.
public struct TokenUsage: Equatable, Sendable {
    public let input: Int
    public let output: Int
    public let cacheCreation: Int
    public let cacheRead: Int

    public init(input: Int, output: Int, cacheCreation: Int, cacheRead: Int) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
    }
}

/// One JSONL line of `type: "assistant"`, flattened.
///
/// A single model message is written as several lines — one per content block — and each repeats
/// the same `usage`. So one event is not one API call: tokens are counted once per
/// `(messageID, requestID)` pair, while tool invocations are counted per block. See openspec
/// `design.md`, section "Two counting rules".
public struct TranscriptEvent: Equatable, Sendable {
    public let messageID: String
    public let requestID: String?
    public let timestamp: Date
    public let sessionID: String
    public let cwd: String
    public let gitBranch: String?
    public let model: String
    public let isSidechain: Bool
    public let usage: TokenUsage
    public let toolNames: [String]
}
