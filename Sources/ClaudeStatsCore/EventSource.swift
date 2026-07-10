import Foundation

/// Everything one scan of the transcripts produced.
///
/// `skippedLines` is part of the result, not a side channel: a number the user sees must be able to
/// say how much of the input it failed to read.
public struct ScanResult: Equatable, Sendable {
    public let events: [TranscriptEvent]
    public let skippedLines: Int

    public init(events: [TranscriptEvent], skippedLines: Int) {
        self.events = events
        self.skippedLines = skippedLines
    }
}

public enum EventSourceError: Error, Equatable {
    /// The transcript directory does not exist. Distinct from "no usage recorded".
    case rootNotFound(URL)
}

/// The seam between reading and everything else. `FileEventSource` implements it today; a
/// `SQLiteEventSource` could implement it later without aggregation or UI changing. Tests inject
/// fixtures through the same protocol.
public protocol EventSource: Sendable {
    func loadEvents() throws -> ScanResult
}

/// Reads every `.jsonl` below a root directory, in one pass, keeping nothing between runs.
///
/// The corpus is small — a few thousand lines, parsed in milliseconds — so there is no cache to
/// invalidate. See openspec `design.md`, section "Parse everything, every time".
public struct FileEventSource: EventSource {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func loadEvents() throws -> ScanResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path(), isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw EventSourceError.rootNotFound(root)
        }

        var events: [TranscriptEvent] = []
        var skippedLines = 0

        for file in transcriptFiles(under: root) {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else {
                // An unreadable file is not a malformed line; it is a file we could not open.
                continue
            }
            for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
                // Blank lines are structure, not data: every transcript ends with a newline.
                guard !line.allSatisfy(\.isWhitespace) else { continue }

                switch TranscriptParser.parseLine(String(line)) {
                case .event(let event): events.append(event)
                case .ignored: continue
                case .malformed: skippedLines += 1
                }
            }
        }
        return ScanResult(events: events, skippedLines: skippedLines)
    }

    /// Returns `nil` when no transcript changed since `previous`, meaning nothing was parsed.
    /// Pass `nil` for `previous` to force a reparse — that is what an explicit refresh does.
    public func loadEventsIfChanged(since previous: FileScanState?) throws -> (
        result: ScanResult, state: FileScanState
    )? {
        let state = try FileScanState.capture(root: root)
        if let previous, previous == state { return nil }
        return (try loadEvents(), state)
    }
}
