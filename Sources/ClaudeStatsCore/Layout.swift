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
    public var dimension: BreakdownDimension?
    public var limit: Int?

    public init(
        id: UUID = UUID(), type: BlockType, metric: Metric? = nil, timeframe: Timeframe,
        bucket: Bucket? = nil, dimension: BreakdownDimension? = nil, limit: Int? = nil
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

extension BlockConfig {
    /// The value each optional parameter takes when the stored layout omits it. `newBlock(of:)`
    /// seeds a fresh block with these same defaults, so a hand-edited block that drops a field
    /// renders identically to a freshly added one — the single source both paths read from.
    public static let defaultMetric: Metric = .inputOutput
    public static let defaultBucket: Bucket = .day
    public static let defaultDimension: BreakdownDimension = .model
    public static func defaultLimit(for type: BlockType) -> Int { type == .sessionList ? 10 : 8 }

    /// Parameters are optional so `layout.json` can omit the ones a type does not use, but a view
    /// always needs a concrete value. These resolve an absent parameter to its default, so the
    /// render path and the editor cannot disagree about what "unset" means.
    public var resolvedMetric: Metric { metric ?? Self.defaultMetric }
    public var resolvedBucket: Bucket { bucket ?? Self.defaultBucket }
    public var resolvedDimension: BreakdownDimension { dimension ?? Self.defaultDimension }
    public var resolvedLimit: Int { limit ?? Self.defaultLimit(for: type) }
}

/// A block the layout named but this build could not render. The two cases call for different
/// answers from the user, so they are not flattened into one: an unknown type means the config was
/// written by a newer build, while unreadable parameters mean a typo this build can point at.
public enum SkippedBlock: Hashable, Sendable {
    /// The `type` string is not in this build's catalog. Carries the raw string.
    case unknownType(String)
    /// The type is known, but one of its parameters is not a value this build understands.
    case unreadableParameters(type: BlockType)
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
        public let skipped: [SkippedBlock]
    }

    /// A block this build cannot render is skipped, never fatal: an older build must survive a
    /// config written by a newer one.
    public static func decode(_ data: Data) throws -> Decoded {
        let document = try JSONDecoder().decode(RawLayout.self, from: data)
        var blocks: [BlockConfig] = []
        var skipped: [SkippedBlock] = []

        for entry in document.blocks {
            switch entry {
            case .block(let block): blocks.append(block)
            case .skipped(let reason): skipped.append(reason)
            }
        }
        return Decoded(layout: Layout(version: document.version, blocks: blocks), skipped: skipped)
    }

    public static func encode(_ layout: Layout) throws -> Data {
        let encoder = JSONEncoder()
        // The user edits this file by hand, so it is formatted for eyes rather than for bytes.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(EncodedLayout(version: layout.version, blocks: layout.blocks))
    }
}

/// The written form. Skipped blocks are never written back, so this shape knows nothing about them.
private struct EncodedLayout: Encodable {
    let version: Int
    let blocks: [BlockConfig]
}

/// The read form, which must survive blocks it cannot understand.
private struct RawLayout: Decodable {
    let version: Int
    let blocks: [Entry]

    enum Entry: Decodable {
        case block(BlockConfig)
        case skipped(SkippedBlock)

        private struct TypeProbe: Decodable {
            let type: String?
        }

        init(from decoder: Decoder) throws {
            if let block = try? BlockConfig(from: decoder) {
                self = .block(block)
                return
            }
            // The block did not decode. Whether its *type* is unknown or merely its parameters
            // decides what the user should be told, so probe the raw type string to find out.
            let rawType = (try? TypeProbe(from: decoder))?.type
            switch rawType.flatMap(BlockType.init(rawValue:)) {
            case .some(let known): self = .skipped(.unreadableParameters(type: known))
            case .none: self = .skipped(.unknownType(rawType ?? "?"))
            }
        }
    }
}
