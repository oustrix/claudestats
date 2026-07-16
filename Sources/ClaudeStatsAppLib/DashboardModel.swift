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
    /// The store the dashboard reads. A `var` because a transcripts-root change rebuilds it against
    /// the new root; views read `model.stats` and re-render when it is swapped.
    private(set) var stats: StatsStore
    let home: String

    /// The user's live preferences. Observed, so the theme, refresh cadence and root take effect the
    /// moment the settings sheet mutates them.
    private(set) var preferences: Preferences

    /// The per-model rates the cost cards and per-session column price with. Loaded from the user's
    /// `pricing.json` and now editable in the Pricing tab; observed, so an edit re-prices the cost
    /// cards live. The file stays hand-editable too — both paths write the same `pricing.json`.
    private(set) var pricing: Pricing

    private(set) var blocks: [BlockConfig]

    /// The breakdown card whose full ranked list is shown in the detail modal, or none. Transient UI
    /// state — a modal is not part of the saved dashboard — so it is deliberately outside `persist()`
    /// and never reaches `layout.json`. The whole `BlockConfig` is held, not just the dimension, so
    /// the modal reflects the exact card (its metric and timeframe) that was expanded.
    private(set) var expandedBreakdown: BlockConfig?

    /// Whether the dashboard is in layout-editing mode. Only then do the per-card reorder/configure/
    /// remove controls appear, so the resting dashboard reads clean like the mockup. Transient UI
    /// state — an editing session is not part of the saved layout — so it is outside `persist()`,
    /// never reaches `layout.json`, and starts off on every launch.
    var isEditing = false

    /// Blocks the layout named that this build could not render.
    private(set) var skipped: [SkippedBlock]
    /// The layout file was unreadable and has been replaced by the default.
    private(set) var wasReset: Bool
    /// The layout could not be written back. Shown, because a dashboard that forgets your edits
    /// without saying so is worse than one that refuses to change.
    private(set) var persistenceError: String?

    @ObservationIgnored private let layoutStore: LayoutStore
    @ObservationIgnored private let preferencesStore: PreferencesStore
    @ObservationIgnored private let pricingStore: PricingStore
    /// Builds a store for a root. The injection seam that lets a root change be tested without a
    /// filesystem, and that keeps the default path a plain `StatsStore(transcriptRoot:)`.
    @ObservationIgnored private let makeStore: @MainActor (URL) -> StatsStore

    init(
        stats: StatsStore? = nil,
        layoutStore: LayoutStore = LayoutStore(fileURL: LayoutStore.defaultURL),
        preferencesStore: PreferencesStore = PreferencesStore(fileURL: PreferencesStore.defaultURL),
        pricingStore: PricingStore = PricingStore(fileURL: PricingStore.defaultURL),
        home: String = NSHomeDirectory(),
        makeStore: @escaping @MainActor (URL) -> StatsStore = { StatsStore(transcriptRoot: $0) }
    ) {
        self.layoutStore = layoutStore
        self.preferencesStore = preferencesStore
        self.pricingStore = pricingStore
        self.home = home
        self.makeStore = makeStore

        let preferences = preferencesStore.load()
        self.preferences = preferences
        self.pricing = pricingStore.load()
        // A test may inject a store directly; the app builds one against the stored root so an
        // override is honored on launch.
        self.stats = stats ?? makeStore(preferences.resolvedTranscriptRoot)

        let loaded = layoutStore.load()
        blocks = loaded.layout.blocks
        skipped = loaded.skipped
        wasReset = loaded.wasReset
        persistenceError = loaded.persistenceError.map { String(describing: $0) }
    }

    /// The path to the layout file, for the settings sheet to display.
    var layoutFileURL: URL { layoutStore.fileURL }

    /// The path to the pricing file, for the settings sheet to display.
    var pricingFileURL: URL { pricingStore.fileURL }

    var scan: ScanResult? {
        if case .loaded(let result) = stats.state { result } else { nil }
    }

    /// The events of the most recent successful scan, or none.
    var events: [TranscriptEvent] { scan?.events ?? [] }

    /// When the numbers were last made current, for the toolbar's freshness line. `nil` before the
    /// first successful scan.
    var lastRefreshedAt: Date? { stats.lastRefreshedAt }

    /// The all-time number of API responses across the loaded corpus — the toolbar's "N responses".
    /// Derived through the same deduplicating aggregation every count uses, so a caller cannot get a
    /// per-line inflation here.
    var responseCount: Int {
        Aggregation.total(.requests, over: events, timeframe: .allTime, now: .now)
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

    /// Opens the full-ranking detail modal for `block`, replacing any card already expanded — one
    /// modal at a time. Not persisted: assigning here never calls `persist()`.
    func expandBreakdown(_ block: BlockConfig) {
        expandedBreakdown = block
    }

    /// Closes the detail modal.
    func collapseBreakdown() {
        expandedBreakdown = nil
    }

    /// Enters or leaves layout-editing mode. Transient, like the detail modal: it reveals the card
    /// controls but changes no block, so it never calls `persist()`.
    func setEditing(_ editing: Bool) {
        isEditing = editing
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

    /// Restores the phase-1 default arrangement — the user-facing reset that was missing. Reuses the
    /// same `persist()` the editing actions use, so there is one place layout writes happen.
    func resetLayout() {
        blocks = Layout.default.blocks
        // A reset clears any prior skip/reset notices: the default layout names no unknown blocks.
        skipped = []
        wasReset = false
        persist()
    }

    // MARK: - Preferences

    /// Selecting a theme recolors the app immediately (the view reads `preferences.theme`) and
    /// persists.
    func setTheme(_ theme: ThemeChoice) {
        preferences.theme = theme
        persistPreferences()
    }

    /// The refresh loop reads `preferences.refreshInterval` each tick, so a change takes effect on
    /// the next cycle without a relaunch.
    func setRefreshInterval(_ interval: RefreshInterval) {
        preferences.refreshInterval = interval
        persistPreferences()
    }

    /// Toggling cost hides or shows the cost cards and the per-session cost column immediately (the
    /// views read `preferences.showCost`) and persists.
    func setShowCost(_ showCost: Bool) {
        preferences.showCost = showCost
        persistPreferences()
    }

    /// Points the store at a new transcripts root (or back to the default when `path` is nil), then
    /// rebuilds and re-scans: a new root is a new corpus. An empty string means no override.
    func setTranscriptRoot(_ path: String?) {
        preferences.transcriptRoot = Preferences.normalizedRoot(path)
        persistPreferences()
        stats = makeStore(preferences.resolvedTranscriptRoot)
        Task { await stats.refresh() }
    }

    /// A failed settings write is logged, not surfaced: the sheet has no error affordance, the file
    /// is hand-editable, and the change still applies for the session. The invariant "never lie
    /// silently" is met by the log line.
    private func persistPreferences() {
        do {
            try preferencesStore.save(preferences)
        } catch {
            Log.settings.error("could not save settings: \(error, privacy: .public)")
        }
    }

    // MARK: - Pricing

    /// Replaces one family's rate and persists. The view reads `pricing`, so the cost cards and the
    /// per-session cost column re-price on the next render.
    func setRate(family: String, rate: ModelRate) {
        pricing.rates[family] = rate
        persistPricing()
    }

    /// Restores the bundled published defaults and persists — the same shape as `resetLayout`.
    func resetPricing() {
        pricing = .default
        persistPricing()
    }

    /// A failed pricing write is logged, not surfaced, for the same reason as `persistPreferences`:
    /// the sheet has no error affordance, the file is hand-editable, and the change still applies for
    /// the session. The "never lie silently" invariant is met by the log line.
    private func persistPricing() {
        do {
            try pricingStore.save(pricing)
        } catch {
            Log.settings.error("could not save pricing: \(error, privacy: .public)")
        }
    }
}

extension BlockConfig {
    /// A newly added block starts with parameters that make sense for its type. Parameter defaults
    /// come from `BlockConfig`'s shared set, so a fresh block and a hand-edited one that omits a
    /// field resolve to the same values.
    static func newBlock(of type: BlockType) -> BlockConfig {
        switch type {
        case .bigNumber:
            BlockConfig(type: type, metric: defaultMetric, timeframe: .last7Days)
        case .cost:
            // Cost carries no metric — its number is derived per model from the pricing.
            BlockConfig(type: type, timeframe: .last30Days)
        case .timeSeries:
            BlockConfig(
                type: type, metric: defaultMetric, timeframe: .last30Days, bucket: defaultBucket)
        case .breakdown:
            BlockConfig(
                type: type, metric: defaultMetric, timeframe: .last30Days,
                dimension: defaultDimension, limit: defaultLimit(for: type))
        case .sessionList:
            BlockConfig(type: type, timeframe: .last7Days, limit: defaultLimit(for: type))
        case .heatmap:
            // Timeframe is required by the shape but ignored by the heatmap, which draws its own
            // fixed window; the bucket (`day`/`week`) and metric are what it actually reads.
            BlockConfig(
                type: type, metric: defaultMetric, timeframe: .last30Days, bucket: defaultBucket)
        }
    }

    var title: String {
        switch type {
        case .bigNumber: metric?.title ?? "Number"
        case .cost: "Cost estimate"
        case .timeSeries: "\(metric?.title ?? "Tokens") over time"
        case .breakdown:
            // A tool breakdown counts invocations and ignores the metric, so naming one would lie;
            // every other dimension leads with its metric, like `timeSeries`/`heatmap` do, so two
            // breakdowns of the same dimension on different metrics read apart at a glance.
            dimension == .tool
                ? "By tool"
                : "\(metric?.title ?? "Tokens") by \(dimension?.title.lowercased() ?? "dimension")"
        case .sessionList: "Sessions"
        case .heatmap: "\(metric?.title ?? "Tokens") heatmap"
        }
    }
}
