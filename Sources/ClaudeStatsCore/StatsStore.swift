import Foundation
import Observation

/// The single observable the dashboard reads. Holds the events once; blocks recompute from them.
///
/// The store owns no timer. A caller ticks it, which keeps the refresh policy in the UI where it
/// can be seen, and keeps the store testable without waiting thirty seconds.
///
/// Main-actor isolated: this is interface state, read by views. The reading of transcripts, which
/// is the only slow part, is handed to a detached task.
@MainActor
@Observable
public final class StatsStore {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded(ScanResult)
        /// The transcript directory does not exist. Distinct from "zero usage recorded".
        case noTranscripts(URL)
        /// Something else went wrong. The error itself is in `lastError`, which is the one place it
        /// lives — a copy in the state would be a second thing to keep in step.
        case failed
    }

    public private(set) var state: State = .idle
    /// The most recent failure, kept even when earlier events are still on screen. Typed, because a
    /// caller that must distinguish a missing directory from a broken one cannot do it on a string.
    public private(set) var lastError: (any Error)?
    /// When the view was last made current: the wall-clock instant a scan completed without error,
    /// whether or not the corpus had changed. `nil` until the first successful scan. The toolbar reads
    /// it to say how fresh the numbers are; it is the store's impure IO layer, not a pure aggregation,
    /// so reading the clock here does not break the "no clock in pure functions" rule.
    public private(set) var lastRefreshedAt: Date?

    @ObservationIgnored private let source: any EventSource
    @ObservationIgnored private var lastScan: FileScanState?
    /// The read in flight, if any. Holding it lets overlapping refreshes join rather than pile up.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public init(source: any EventSource) {
        self.source = source
    }

    public convenience init(transcriptRoot: URL = FileEventSource.defaultRoot) {
        self.init(source: FileEventSource(root: transcriptRoot))
    }

    /// Reads the transcripts off the main thread. Passing `force` discards the remembered scan
    /// state, so an explicit refresh always reparses.
    ///
    /// Overlapping calls join the read already running rather than starting a second. SwiftUI fires
    /// several refreshes while a window sets up, and without this each would read `lastScan` before
    /// the first had written it — defeating change detection and reparsing the whole corpus N times.
    public func refresh(force: Bool = false) async {
        if let running = refreshTask {
            await running.value
            if !force { return }
        }
        let task = Task { await self.performRefresh(force: force) }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh(force: Bool) async {
        if force { lastScan = nil }
        let previous = lastScan
        if case .idle = state { state = .loading }

        let source = self.source
        let outcome = await Task.detached(priority: .utility) {
            Result { try source.loadEventsIfChanged(since: previous) }
        }.value

        switch outcome {
        case .success(nil):
            // Nothing changed. Whatever is on screen is still true — and still fresh: we just checked.
            lastRefreshedAt = Date()
            Log.store.debug("refresh: nothing changed")

        case .success(.some(let scan)):
            lastScan = scan.state
            lastError = nil
            lastRefreshedAt = Date()
            state = .loaded(scan.result)
            Log.store.debug("refresh: loaded \(scan.result.events.count) events")

        case .failure(let error):
            lastError = error
            if case EventSourceError.rootNotFound(let root) = error {
                state = .noTranscripts(root)
                Log.store.notice("refresh: no transcripts at \(root.path(), privacy: .public)")
                break
            }
            // A failed refresh must not erase numbers that were already read successfully.
            let keepEarlier: Bool = switch state { case .loaded: true; default: false }
            Log.store.error(
                "refresh failed: \(error, privacy: .public)\(keepEarlier ? " (keeping earlier events)" : "", privacy: .public)")
            if !keepEarlier { state = .failed }
        }
    }
}
