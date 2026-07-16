import Foundation

/// The result of parsing a single JSONL line.
public enum LineOutcome: Equatable, Sendable {
    /// An assistant record carrying `usage` — the only kind that holds statistics.
    case event(TranscriptEvent)
    /// A well-formed line that carries no statistics: user, attachment, `<synthetic>` and so on.
    case ignored
    /// The line did not parse. These are counted and surfaced — never dropped silently.
    case malformed
}

public enum TranscriptParser {
    /// Claude Code marks records with no API call behind them this way; their usage is all zeros.
    private static let syntheticModel = "<synthetic>"

    /// A caller reading many lines should hand in one decoder rather than pay for one per line.
    public static func parseLine(_ line: String, using decoder: JSONDecoder = JSONDecoder())
        -> LineOutcome
    {
        guard let data = line.data(using: .utf8) else { return .malformed }
        let raw: RawLine
        do {
            raw = try decoder.decode(RawLine.self, from: data)
        } catch {
            return .malformed
        }

        guard raw.type == "assistant", let message = raw.message, let usage = message.usage,
            let messageID = message.id, let model = message.model, model != syntheticModel
        else {
            return .ignored
        }
        guard let rawTimestamp = raw.timestamp, let timestamp = parseTimestamp(rawTimestamp),
            let sessionID = raw.sessionId, let cwd = raw.cwd
        else {
            return .malformed
        }

        return .event(
            TranscriptEvent(
                messageID: messageID,
                requestID: raw.requestId,
                timestamp: timestamp,
                sessionID: sessionID,
                cwd: cwd,
                gitBranch: raw.gitBranch,
                model: model,
                isSidechain: raw.isSidechain ?? false,
                attributionAgent: raw.attributionAgent,
                usage: TokenUsage(
                    input: usage.input_tokens,
                    output: usage.output_tokens,
                    cacheCreation: usage.cache_creation_input_tokens,
                    cacheRead: usage.cache_read_input_tokens
                ),
                stopReason: message.stop_reason,
                toolNames: message.content?.compactMap { $0.type == "tool_use" ? $0.name : nil } ?? []
            )
        )
    }

    /// `ISO8601FormatStyle` is a Sendable value type, unlike `ISO8601DateFormatter`, which Swift 6
    /// refuses to hold in a static property. So both styles are built once.
    private static let withFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withWholeSeconds = Date.ISO8601FormatStyle()

    /// Transcripts write fractional seconds (`…T09:43:05.761Z`), but not always, so both forms are tried.
    private static func parseTimestamp(_ text: String) -> Date? {
        if let date = try? withFractionalSeconds.parse(text) { return date }
        return try? withWholeSeconds.parse(text)
    }
}

// The JSON shape, narrowed to the fields we read. snake_case mirrors the transcript so that four
// counters do not need a CodingKeys block.
private struct RawLine: Decodable {
    let type: String
    let timestamp: String?
    let sessionId: String?
    let cwd: String?
    let gitBranch: String?
    let isSidechain: Bool?
    let attributionAgent: String?
    let requestId: String?
    let message: RawMessage?
}

/// Every record type shares the `message` key, but the shapes differ: a user turn has no `id` or
/// `model`, and its `content` is a bare string rather than an array of blocks. Decoding must
/// tolerate that — a well-formed user turn is data we ignore, not data we failed to read.
private struct RawMessage: Decodable {
    let id: String?
    let model: String?
    let content: [RawContentBlock]?
    let usage: RawUsage?
    /// Non-nil only on the line that ends a response; that line carries the true token counts.
    let stop_reason: String?

    // Writing `init(from:)` by hand switches off the synthesis of `CodingKeys` too, so it stays.
    private enum CodingKeys: String, CodingKey {
        case id, model, content, usage, stop_reason
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        content = try? container.decodeIfPresent([RawContentBlock].self, forKey: .content)
        usage = try container.decodeIfPresent(RawUsage.self, forKey: .usage)
        stop_reason = try? container.decodeIfPresent(String.self, forKey: .stop_reason)
    }
}

private struct RawContentBlock: Decodable {
    let type: String
    let name: String?
}

private struct RawUsage: Decodable {
    let input_tokens: Int
    let output_tokens: Int
    let cache_creation_input_tokens: Int
    let cache_read_input_tokens: Int
}
