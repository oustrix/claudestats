import Foundation

/// The closed catalog of blocks a dashboard can hold. Closed on purpose: an open one would drift
/// into a query builder, and a bad query builder is worse than a good dashboard.
public enum BlockType: String, Codable, CaseIterable, Sendable {
    case bigNumber
    case timeSeries
    case breakdown
    case sessionList
    case heatmap
    /// A headline dollar cost estimate. Not a token metric — it carries only a timeframe, and its
    /// number is derived per model from the pricing (see `Aggregation.cost`).
    case cost
}

extension BlockType {
    /// The buckets this type can actually draw, so the editor never offers an unusable granularity:
    /// a `timeSeries` plots by `day`/`hour`, a `heatmap` grids by `day`/`week`. Types with no bucket
    /// parameter offer none. `Aggregation.heatmap` coerces a stray `.hour` to `.day` to match.
    public var supportedBuckets: [Bucket] {
        switch self {
        case .timeSeries: [.day, .hour]
        case .heatmap: [.day, .week]
        case .bigNumber, .breakdown, .sessionList, .cost: []
        }
    }
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
    /// How many of the dashboard's twelve columns this block occupies, 1…12. A block written before
    /// spans existed had a row to itself, so a decode that finds no span reads it as `fullSpan` (12),
    /// preserving the one-block-per-row layout it was authored under.
    public var span: Int

    public init(
        id: UUID = UUID(), type: BlockType, metric: Metric? = nil, timeframe: Timeframe,
        bucket: Bucket? = nil, dimension: BreakdownDimension? = nil, limit: Int? = nil,
        span: Int = BlockConfig.fullSpan
    ) {
        self.id = id
        self.type = type
        self.metric = metric
        self.timeframe = timeframe
        self.bucket = bucket
        self.dimension = dimension
        self.limit = limit
        self.span = span
    }

    /// The full width of the twelve-column grid. Also the migration default: a spanless block fills
    /// its row, as every block did before spans were a concept.
    public static let fullSpan = 12

    /// A missing `span` is not an error but a pre-spans layout: it decodes to `fullSpan`. Every other
    /// field keeps its synthesized behaviour, so a legible hand-edited file still round-trips.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(BlockType.self, forKey: .type)
        metric = try container.decodeIfPresent(Metric.self, forKey: .metric)
        timeframe = try container.decode(Timeframe.self, forKey: .timeframe)
        bucket = try container.decodeIfPresent(Bucket.self, forKey: .bucket)
        dimension = try container.decodeIfPresent(BreakdownDimension.self, forKey: .dimension)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        span = try container.decodeIfPresent(Int.self, forKey: .span) ?? BlockConfig.fullSpan
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

    /// What a new user sees: the mockup arrangement on the twelve-column grid. A top row of four KPI
    /// cards (span 3 each) — input+output, requests, cost estimate, cache read — a full-width time
    /// series, a row of three breakdowns (span 4 each), then a full-width heatmap and session list.
    /// The headline metric is `inputOutput`, not `allTokens`: cache reads are over 90% of every token,
    /// so a headline of "all tokens" would be a headline about the cache. The cost card sits third; a
    /// `showCost = false` preference filters it out, leaving a trailing gap in the KPI row rather than
    /// rebalancing spans.
    public static let `default` = Layout(blocks: [
        BlockConfig(type: .bigNumber, metric: .inputOutput, timeframe: .last7Days, span: 3),
        BlockConfig(type: .bigNumber, metric: .requests, timeframe: .last7Days, span: 3),
        BlockConfig(type: .cost, timeframe: .last30Days, span: 3),
        BlockConfig(type: .bigNumber, metric: .cacheRead, timeframe: .last7Days, span: 3),
        BlockConfig(
            type: .timeSeries, metric: .inputOutput, timeframe: .last30Days, bucket: .day, span: 12),
        BlockConfig(
            type: .breakdown, metric: .inputOutput, timeframe: .last30Days, dimension: .model,
            limit: 8, span: 4),
        BlockConfig(
            type: .breakdown, metric: .inputOutput, timeframe: .last30Days, dimension: .project,
            limit: 8, span: 4),
        BlockConfig(
            type: .breakdown, metric: .requests, timeframe: .last30Days, dimension: .tool, limit: 10,
            span: 4),
        BlockConfig(
            type: .heatmap, metric: .inputOutput, timeframe: .last30Days, bucket: .day, span: 12),
        BlockConfig(type: .sessionList, timeframe: .last7Days, limit: 10, span: 12),
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

        init(from decoder: any Decoder) throws {
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
