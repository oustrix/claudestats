import Foundation
import Testing

@testable import ClaudeStatsCore

/// A source whose answers the test dictates, so the store can be driven without a filesystem.
private final class ScriptedSource: EventSource, @unchecked Sendable {
    var answers: [Result<(result: ScanResult, state: FileScanState)?, Error>] = []
    private(set) var callCount = 0
    private(set) var lastKnownState: FileScanState??

    func loadEvents() throws -> ScanResult {
        try loadEventsIfChanged(since: nil)!.result
    }

    func loadEventsIfChanged(since previous: FileScanState?) throws -> (
        result: ScanResult, state: FileScanState
    )? {
        callCount += 1
        lastKnownState = previous
        guard !answers.isEmpty else { return nil }
        return try answers.removeFirst().get()
    }
}

private func scan(_ events: [TranscriptEvent]) -> (result: ScanResult, state: FileScanState) {
    (ScanResult(events: events, skippedLines: 0, unreadableFiles: []), FileScanState.capture(files: []))
}

@MainActor @Test func aFreshStoreHasNotLoadedAnything() {
    #expect(StatsStore(source: ScriptedSource()).state == .idle)
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
