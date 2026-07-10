import Foundation
import Observation

/// A source that can say "nothing changed" without reparsing. `FileEventSource` implements it; the
/// store depends on this rather than on the filesystem, so it can be driven in tests.
public protocol ChangeAwareEventSource: Sendable {
    func loadEventsIfChanged(since previous: FileScanState?) throws -> (
        result: ScanResult, state: FileScanState
    )?
}

extension FileEventSource: ChangeAwareEventSource {}

/// The single observable the dashboard reads. Holds the events once; blocks recompute from them.
///
/// The store owns no timer. A caller ticks it, which keeps the refresh policy in the UI where it
/// can be seen, and keeps the store testable without waiting thirty seconds.
@Observable
public final class StatsStore {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded(ScanResult)
        /// The transcript directory does not exist. Distinct from "zero usage recorded".
        case noTranscripts(URL)
        case failed(String)
    }

    public private(set) var state: State = .idle
    /// The most recent failure, kept even when earlier events are still on screen.
    public private(set) var lastError: String?

    @ObservationIgnored private let source: any ChangeAwareEventSource
    @ObservationIgnored private var lastScan: FileScanState?

    public init(source: any ChangeAwareEventSource) {
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
            break

        case .success(.some(let scan)):
            lastScan = scan.state
            lastError = nil
            state = .loaded(scan.result)

        case .failure(EventSourceError.rootNotFound(let root)):
            state = .noTranscripts(root)

        case .failure(let error):
            lastError = String(describing: error)
            // A failed refresh must not erase numbers that were already read successfully.
            if case .loaded = state { break }
            state = .failed(String(describing: error))
        }
    }
}
