import Foundation

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

/// The home directory the suite abbreviates project paths against. One value, so a change to the
/// assumed home is a single edit rather than a sweep across every model and view test.
let home = "/Users/me"

/// A layout that is not valid JSON at all — the loader moves it aside and falls back to defaults.
let malformedLayoutJSON = "{ broken"

/// A layout naming one block of a type this build does not know. It decodes cleanly but yields a
/// single `.unknownType` skip, leaving `wasReset` false.
let skippedTypeLayoutJSON = """
    {"version": 1, "blocks": [
      {"id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "type": "flameGraph", "timeframe": "allTime"}
    ]}
    """

/// Feeds a fixed set of events to a `StatsStore`, so the model can be driven without a filesystem.
struct StubEventSource: EventSource {
    let result: ScanResult

    init(events: [TranscriptEvent], skippedLines: Int = 0, unreadableFiles: [URL] = []) {
        result = ScanResult(
            events: events, skippedLines: skippedLines, unreadableFiles: unreadableFiles)
    }

    func loadEvents() throws -> ScanResult { result }
}

/// A `StatsStore` already in `.loaded` with the given events — the state the dashboard renders from.
@MainActor
func loadedStore(_ events: [TranscriptEvent] = [makeEvent()]) async -> StatsStore {
    let store = StatsStore(source: StubEventSource(events: events))
    await store.refresh()
    return store
}

/// A source that always throws, for driving a store into `.failed` / `.noTranscripts`.
struct FailingEventSource: EventSource {
    let error: any Error
    func loadEvents() throws -> ScanResult { throw error }
}

/// A `StatsStore` in `.failed`.
@MainActor
func failedStore() async -> StatsStore {
    struct Boom: Error {}
    let store = StatsStore(source: FailingEventSource(error: Boom()))
    await store.refresh()
    return store
}

/// A `StatsStore` in `.noTranscripts` for the given missing root.
@MainActor
func noTranscriptsStore(_ root: URL) async -> StatsStore {
    let store = StatsStore(source: FailingEventSource(error: EventSourceError.rootNotFound(root)))
    await store.refresh()
    return store
}

/// A scratch layout file under a fresh temp directory. The caller removes the directory in a `defer`.
func makeScratchLayoutFile(_ label: String = "layout") throws -> URL {
    let root = URL.temporaryDirectory.appending(
        path: "claudestats-applib-\(label)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appending(path: "layout.json")
}

/// Runs `body` with a scratch `layout.json` and an action that makes its parent directory read-only,
/// so a save must fail. Permissions are restored and the directory removed afterward however `body`
/// exits — centralizing the teardown the permission tests would otherwise each repeat and risk
/// forgetting.
@MainActor
func withScratchLayoutFile(
    _ body: (_ file: URL, _ makeParentReadOnly: () throws -> Void) async throws -> Void
) async throws {
    let file = try makeScratchLayoutFile("readonly")
    let dir = file.deletingLastPathComponent()
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path())
        try? FileManager.default.removeItem(at: dir)
    }
    try await body(file) {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path())
    }
}

/// A preferences store beside a scratch layout `file`, so a model test drives its own `settings.json`
/// in the same temp directory and never reads or writes the real `~/Library` one.
func scratchPreferencesStore(besides file: URL) -> PreferencesStore {
    PreferencesStore(fileURL: file.deletingLastPathComponent().appending(path: "settings.json"))
}

/// A pricing store beside a scratch layout `file`, so a model test never seeds the real `pricing.json`.
func scratchPricingStore(besides file: URL) -> PricingStore {
    PricingStore(fileURL: file.deletingLastPathComponent().appending(path: "pricing.json"))
}

/// A model whose layout is seeded on `file` and whose store is the one given. Every model test points
/// at its own temp file, so none touches the real `~/Library` layout or settings.
@MainActor
func seededModel(_ blocks: [BlockConfig], file: URL, stats: StatsStore) -> DashboardModel {
    try? LayoutStore(fileURL: file).save(Layout(blocks: blocks))
    return DashboardModel(
        stats: stats, layoutStore: LayoutStore(fileURL: file),
        preferencesStore: scratchPreferencesStore(besides: file),
        pricingStore: scratchPricingStore(besides: file), home: home)
}

/// The same, over a loaded store seeded with `events` — the common case for editing tests.
@MainActor
func seededModel(
    _ blocks: [BlockConfig], file: URL, events: [TranscriptEvent] = [makeEvent()]
) async -> DashboardModel {
    seededModel(blocks, file: file, stats: await loadedStore(events))
}

/// Builds an event with everything defaulted, so a test names only the fields it cares about.
/// Mirrors the core suite's helper; `TranscriptEvent`'s initializer is internal, hence the
/// `@testable` import.
func makeEvent(
    messageID: String = "msg",
    requestID: String? = "req",
    timestamp: Date = Date(timeIntervalSince1970: 1_782_985_385),
    sessionID: String = "session",
    cwd: String = "/Users/me/proj",
    gitBranch: String? = "main",
    model: String = "claude-opus-4-8",
    isSidechain: Bool = false,
    attributionAgent: String? = nil,
    usage: TokenUsage = TokenUsage(input: 1, output: 2, cacheCreation: 3, cacheRead: 4),
    stopReason: String? = "end_turn",
    toolNames: [String] = []
) -> TranscriptEvent {
    TranscriptEvent(
        messageID: messageID,
        requestID: requestID,
        timestamp: timestamp,
        sessionID: sessionID,
        cwd: cwd,
        gitBranch: gitBranch,
        model: model,
        isSidechain: isSidechain,
        attributionAgent: attributionAgent,
        usage: usage,
        stopReason: stopReason,
        toolNames: toolNames
    )
}
