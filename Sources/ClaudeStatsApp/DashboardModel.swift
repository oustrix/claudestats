import ClaudeStatsCore
import Foundation
import Observation

/// Everything the window needs: the events, the layout, and the truth about what failed.
///
/// Layout mutations persist immediately. Each one is a discrete user action — a drop, a menu choice,
/// a popover dismissal — not a continuous gesture, so there is nothing to debounce.
@MainActor
@Observable
final class DashboardModel {
    let stats: StatsStore
    let home: String

    private(set) var blocks: [BlockConfig]
    /// Blocks the layout named that this build could not render.
    private(set) var skipped: [SkippedBlock]
    /// The layout file was unreadable and has been replaced by the default.
    private(set) var wasReset: Bool
    /// The layout could not be written back. Shown, because a dashboard that forgets your edits
    /// without saying so is worse than one that refuses to change.
    private(set) var persistenceError: String?

    @ObservationIgnored private let layoutStore: LayoutStore

    init(
        stats: StatsStore = StatsStore(),
        layoutStore: LayoutStore = LayoutStore(fileURL: LayoutStore.defaultURL),
        home: String = NSHomeDirectory()
    ) {
        self.stats = stats
        self.layoutStore = layoutStore
        self.home = home

        let loaded = layoutStore.load()
        blocks = loaded.layout.blocks
        skipped = loaded.skipped
        wasReset = loaded.wasReset
        persistenceError = loaded.persistenceError.map { String(describing: $0) }
    }

    /// The events of the most recent successful scan, or none.
    var events: [TranscriptEvent] {
        if case .loaded(let result) = stats.state { result.events } else { [] }
    }

    var scan: ScanResult? {
        if case .loaded(let result) = stats.state { result } else { nil }
    }

    // MARK: - Layout editing

    func add(_ type: BlockType) {
        blocks.append(BlockConfig.newBlock(of: type))
        persist()
    }

    func remove(_ block: BlockConfig) {
        blocks.removeAll { $0.id == block.id }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        blocks.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func update(_ block: BlockConfig) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        blocks[index] = block
        persist()
    }

    func dismissNotices() {
        skipped = []
        wasReset = false
        persistenceError = nil
    }

    private func persist() {
        do {
            try layoutStore.save(Layout(blocks: blocks))
            persistenceError = nil
        } catch {
            persistenceError = String(describing: error)
        }
    }
}

extension BlockConfig {
    /// A newly added block starts with parameters that make sense for its type.
    static func newBlock(of type: BlockType) -> BlockConfig {
        switch type {
        case .bigNumber:
            BlockConfig(type: .bigNumber, metric: .inputOutput, timeframe: .last7Days)
        case .timeSeries:
            BlockConfig(type: .timeSeries, metric: .inputOutput, timeframe: .last30Days, bucket: .day)
        case .breakdown:
            BlockConfig(
                type: .breakdown, metric: .inputOutput, timeframe: .last30Days, dimension: .model,
                limit: 8)
        case .sessionList:
            BlockConfig(type: .sessionList, timeframe: .last7Days, limit: 10)
        }
    }

    var title: String {
        switch type {
        case .bigNumber: metric?.title ?? "Number"
        case .timeSeries: "\(metric?.title ?? "Tokens") over time"
        case .breakdown: "By \(dimension?.title.lowercased() ?? "dimension")"
        case .sessionList: "Sessions"
        }
    }
}
