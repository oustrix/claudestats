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

    public static let zero = TokenUsage(input: 0, output: 0, cacheCreation: 0, cacheRead: 0)

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheCreation: lhs.cacheCreation + rhs.cacheCreation,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }
}

/// One JSONL line of `type: "assistant"`, flattened. An event is a line, not an API call: a single
/// response is written across several lines, one per content block.
///
/// `usage` is internal on purpose. Tokens are only reachable through `Message`, which
/// `Counting.messages(from:)` produces one per response — so no caller outside this module can sum
/// tokens per line and inflate the total.
public struct TranscriptEvent: Equatable, Sendable {
    public let messageID: String
    public let requestID: String?
    public let timestamp: Date
    public let sessionID: String
    public let cwd: String
    public let gitBranch: String?
    public let model: String
    public let isSidechain: Bool
    /// The subagent type this record was attributed to (`general-purpose`, `Explore`, …). Internal,
    /// like `usage`: it reaches the outside only through `Message.agentLabel`. Nil on the main
    /// conversation and on old-format sidechain records that predate the field.
    let attributionAgent: String?
    let usage: TokenUsage
    /// Present only on the line that ends a response. Claude Code streams: every earlier line of the
    /// same response reports a placeholder `output_tokens`, so this is how the real count is found.
    let stopReason: String?
    /// Counted per block, never deduplicated: two lines of one response, each with a tool block,
    /// are two real invocations.
    public let toolNames: [String]
}
