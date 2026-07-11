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

    @ObservationIgnored private let source: any EventSource
    @ObservationIgnored private var lastScan: FileScanState?

    public init(source: any EventSource) {
        self.source = source
    }

    public convenience init(transcriptRoot: URL = FileEventSource.defaultRoot) {
        self.init(source: FileEventSource(root: transcriptRoot))
    }

    /// Reads the transcripts off the main thread. Passing `force` discards the remembered scan
    /// state, so an explicit refresh always reparses.
    public func refresh(force: Bool = false) async {
        if force { lastScan = nil }
        let previous = lastScan
        if case .idle = state { state = .loading }

        let source = self.source
        let outcome = await Task.detached(priority: .utility) {
            Result { try source.loadEventsIfChanged(since: previous) }
        }.value

        switch outcome {
        case .success(nil):
            // Nothing changed. Whatever is on screen is still true.
            Log.store.debug("refresh: nothing changed")

        case .success(.some(let scan)):
            lastScan = scan.state
            lastError = nil
            state = .loaded(scan.result)
            Log.store.debug("refresh: loaded \(scan.result.events.count, privacy: .public) events")

        case .failure(let error):
            lastError = error
            if case EventSourceError.rootNotFound(let root) = error {
                state = .noTranscripts(root)
                Log.store.notice("refresh: no transcripts at \(root.path(), privacy: .public)")
                break
            }
            // A failed refresh must not erase numbers that were already read successfully.
            let kept = { if case .loaded = state { return true } else { return false } }()
            Log.store.error(
                "refresh failed: \(error, privacy: .public)\(kept ? " (keeping earlier events)" : "")")
            if kept { break }
            state = .failed
        }
    }
}
