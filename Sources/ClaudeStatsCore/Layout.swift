import Foundation

/// The closed catalog of blocks a dashboard can hold. Closed on purpose: an open one would drift
/// into a query builder, and a bad query builder is worse than a good dashboard.
public enum BlockType: String, Codable, CaseIterable, Sendable {
    case bigNumber
    case timeSeries
    case breakdown
    case sessionList
}

/// One block and its parameters, flat so that `layout.json` stays legible to a human editing it.
/// Parameters a given type does not use are simply absent.
public struct BlockConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var type: BlockType
    public var metric: Metric?
    public var timeframe: Timeframe
    public var bucket: Bucket?
    public var dimension: Dimension?
    public var limit: Int?

    public init(
        id: UUID = UUID(), type: BlockType, metric: Metric? = nil, timeframe: Timeframe,
        bucket: Bucket? = nil, dimension: Dimension? = nil, limit: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.metric = metric
        self.timeframe = timeframe
        self.bucket = bucket
        self.dimension = dimension
        self.limit = limit
    }
}

/// The dashboard, as stored on disk.
public struct Layout: Equatable, Sendable {
    public var version: Int
    public var blocks: [BlockConfig]

    public init(version: Int = Layout.currentVersion, blocks: [BlockConfig]) {
        self.version = version
        self.blocks = blocks
    }

    public static let currentVersion = 1

    /// What a new user sees. The headline is `inputOutput`, not `allTokens`: cache reads are over
    /// 90% of every token, so a headline of "all tokens" would be a headline about the cache.
    public static let `default` = Layout(blocks: [
        BlockConfig(type: .bigNumber, metric: .inputOutput, timeframe: .last7Days),
        BlockConfig(type: .timeSeries, metric: .inputOutput, timeframe: .last30Days, bucket: .day),
        BlockConfig(
            type: .breakdown, metric: .inputOutput, timeframe: .last30Days, dimension: .model,
            limit: 8),
        BlockConfig(
            type: .breakdown, metric: .inputOutput, timeframe: .last30Days, dimension: .project,
            limit: 8),
        BlockConfig(
            type: .breakdown, metric: .requests, timeframe: .last30Days, dimension: .tool, limit: 10),
        BlockConfig(type: .sessionList, timeframe: .last7Days, limit: 10),
    ])

    /// What a decode produced, and what it had to leave behind.
    public struct Decoded: Equatable, Sendable {
        public let layout: Layout
        /// Blocks this build could not render, named so the user learns why the dashboard is short.
        public let skippedTypes: [String]
    }

    /// A block this build cannot render is skipped, never fatal: an older build must survive a
    /// config written by a newer one. A block whose *type* is unreadable is named by its raw string;
    /// a block whose type is known but whose parameters are not is named by that type.
    public static func decode(_ data: Data) throws -> Decoded {
        let document = try JSONDecoder().decode(RawLayout.self, from: data)
        var blocks: [BlockConfig] = []
        var skipped: [String] = []

        for raw in document.blocks {
            switch raw {
            case .block(let block): blocks.append(block)
            case .unreadable(let name): skipped.append(name)
            }
        }
        return Decoded(layout: Layout(version: document.version, blocks: blocks), skippedTypes: skipped)
    }

    public static func encode(_ layout: Layout) throws -> Data {
        let encoder = JSONEncoder()
        // The user edits this file by hand, so it is formatted for eyes rather than for bytes.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(RawLayout(version: layout.version, blocks: layout.blocks))
    }
}

/// Decoding shape that tolerates blocks it cannot understand.
private struct RawLayout: Codable {
    let version: Int
    let blocks: [Entry]

    init(version: Int, blocks: [BlockConfig]) {
        self.version = version
        self.blocks = blocks.map(Entry.block)
    }

    enum Entry: Codable {
        case block(BlockConfig)
        /// The raw `type` string, or `"?"` when even that is missing.
        case unreadable(String)

        private struct TypeProbe: Decodable {
            let type: String?
        }

        init(from decoder: Decoder) throws {
            if let block = try? BlockConfig(from: decoder) {
                self = .block(block)
                return
            }
            let probe = try? TypeProbe(from: decoder)
            self = .unreadable(probe?.type ?? "?")
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .block(let block): try block.encode(to: encoder)
            case .unreadable(let name):
                var container = encoder.singleValueContainer()
                try container.encode(name)
            }
        }
    }
}
