import Foundation
import Testing

@testable import ClaudeStatsCore

/// A source whose answers the test dictates, so the store can be driven without a filesystem.
/// Locked, because the store reads through a detached task and the coalescing test calls it from
/// several at once — an unsynchronised stub would crash on the race rather than fail the assertion.
private final class ScriptedSource: EventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _answers: [Result<(result: ScanResult, state: FileScanState)?, Error>] = []
    private var _callCount = 0
    private var _lastKnownState: FileScanState??

    var answers: [Result<(result: ScanResult, state: FileScanState)?, Error>] {
        get { lock.withLock { _answers } }
        set { lock.withLock { _answers = newValue } }
    }
    var callCount: Int { lock.withLock { _callCount } }
    var lastKnownState: FileScanState?? { lock.withLock { _lastKnownState } }

    func loadEvents() throws -> ScanResult {
        try loadEventsIfChanged(since: nil)!.result
    }

    func loadEventsIfChanged(since previous: FileScanState?) throws -> (
        result: ScanResult, state: FileScanState
    )? {
        try lock.withLock {
            _callCount += 1
            _lastKnownState = previous
            guard !_answers.isEmpty else { return nil }
            return try _answers.removeFirst().get()
        }
    }
}

private func scan(_ events: [TranscriptEvent]) -> (result: ScanResult, state: FileScanState) {
    (ScanResult(events: events, skippedLines: 0, unreadableFiles: []), FileScanState.capture(files: []))
}

@MainActor @Test func aFreshStoreHasNotLoadedAnything() {
    #expect(StatsStore(source: ScriptedSource()).state == .idle)
}

/// A fresh store has no refresh stamp; a completed scan records when the view was last made current,
/// so the toolbar can say how fresh its numbers are.
@MainActor @Test func aCompletedScanStampsTheRefreshTime() async {
    let source = ScriptedSource()
    source.answers = [.success(scan([makeEvent(messageID: "a")]))]
    let store = StatsStore(source: source)
    #expect(store.lastRefreshedAt == nil)

    await store.refresh()

    #expect(store.lastRefreshedAt != nil)
}

@MainActor @Test func refreshPublishesTheLoadedEvents() async throws {
    let source = ScriptedSource()
    source.answers = [.success(scan([makeEvent(messageID: "a")]))]
    let store = StatsStore(source: source)

    await store.refresh()

    guard case .loaded(let result) = store.state else {
        Issue.record("expected loaded, got \(store.state)")
        return
    }
    #expect(result.events.count == 1)
}

/// The whole point of the scan state: when nothing changed, the previous events stay put.
@MainActor @Test func anUnchangedScanLeavesTheLoadedEventsAlone() async throws {
    let source = ScriptedSource()
    source.answers = [.success(scan([makeEvent(messageID: "a")])), .success(nil)]
    let store = StatsStore(source: source)
    await store.refresh()

    await store.refresh()

    guard case .loaded(let result) = store.state else {
        Issue.record("expected the earlier events to survive, got \(store.state)")
        return
    }
    #expect(result.events.count == 1)
    #expect(source.callCount == 2)
}

/// An explicit refresh forgets what it knew, so the source cannot answer "nothing changed".
@MainActor @Test func anExplicitRefreshForcesAReparse() async throws {
    let source = ScriptedSource()
    source.answers = [.success(scan([])), .success(scan([]))]
    let store = StatsStore(source: source)
    await store.refresh()

    await store.refresh(force: true)

    #expect(source.lastKnownState == .some(nil))
}

/// A periodic refresh passes what it last saw, so an unchanged tree costs no parsing.
@MainActor @Test func aPeriodicRefreshRemembersTheLastScanState() async throws {
    let source = ScriptedSource()
    source.answers = [.success(scan([])), .success(nil)]
    let store = StatsStore(source: source)
    await store.refresh()

    await store.refresh()

    #expect(source.lastKnownState != .some(nil))
}

@MainActor @Test func aMissingTranscriptRootIsItsOwnState() async {
    let source = ScriptedSource()
    let missing = URL(filePath: "/nowhere")
    source.answers = [.failure(EventSourceError.rootNotFound(missing))]
    let store = StatsStore(source: source)

    await store.refresh()

    #expect(store.state == .noTranscripts(missing))
}

/// Any other failure is reported, never rendered as zeros.
@MainActor @Test func aFailureIsSurfacedRatherThanShownAsZeroUsage() async {
    struct Boom: Error {}
    let source = ScriptedSource()
    source.answers = [.failure(Boom())]
    let store = StatsStore(source: source)

    await store.refresh()

    guard case .failed = store.state else {
        Issue.record("expected failed, got \(store.state)")
        return
    }
}

/// Overlapping refreshes join one scan instead of each launching a redundant parse. Without this,
/// the several refreshes SwiftUI fires during window setup all read `lastScan == nil` — because it
/// is written only after a parse finishes — and all reparse the whole corpus.
@MainActor @Test func concurrentRefreshesCoalesceIntoOneScan() async {
    let source = ScriptedSource()
    source.answers = [.success(scan([makeEvent(messageID: "a")]))]
    let store = StatsStore(source: source)

    async let a: Void = store.refresh()
    async let b: Void = store.refresh()
    async let c: Void = store.refresh()
    _ = await (a, b, c)

    #expect(source.callCount == 1)
}

/// A failure after a successful load must not erase the numbers already on screen.
@MainActor @Test func aFailedRefreshKeepsTheEventsAlreadyLoaded() async {
    struct Boom: Error {}
    let source = ScriptedSource()
    source.answers = [.success(scan([makeEvent(messageID: "a")])), .failure(Boom())]
    let store = StatsStore(source: source)
    await store.refresh()

    await store.refresh()

    guard case .loaded = store.state else {
        Issue.record("expected the earlier events to survive a failed refresh, got \(store.state)")
        return
    }
    #expect(store.lastError != nil)
}
