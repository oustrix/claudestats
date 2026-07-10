import Foundation

/// Everything one scan of the transcripts produced.
///
/// The two failure counts are part of the result, not a side channel: a number the user sees must
/// be able to say how much of the input it failed to read. A skipped line loses one response; an
/// unreadable file loses every response it held, which is the more dangerous of the two.
public struct ScanResult: Equatable, Sendable {
    public let events: [TranscriptEvent]
    public let skippedLines: Int
    public let unreadableFiles: Int

    public init(events: [TranscriptEvent], skippedLines: Int, unreadableFiles: Int = 0) {
        self.events = events
        self.skippedLines = skippedLines
        self.unreadableFiles = unreadableFiles
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
        parse(files: try discover())
    }

    /// Returns `nil` when no transcript changed since `previous`, meaning nothing was parsed.
    /// Pass `nil` for `previous` to force a reparse — that is what an explicit refresh does.
    public func loadEventsIfChanged(since previous: FileScanState?) throws -> (
        result: ScanResult, state: FileScanState
    )? {
        let files = try discover()
        let state = FileScanState.capture(files: files)
        if let previous, previous == state { return nil }
        return (parse(files: files), state)
    }

    private func discover() throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path(), isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw EventSourceError.rootNotFound(root)
        }
        return transcriptFiles(under: root)
    }

    private func parse(files: [URL]) -> ScanResult {
        var events: [TranscriptEvent] = []
        var skippedLines = 0
        var unreadableFiles = 0
        // One decoder for the whole scan: a fresh one per line would cost thousands of allocations.
        let decoder = JSONDecoder()

        for file in files {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else {
                // Permissions, a transient IO error, or bytes that are not UTF-8. Whatever the
                // cause, every response this file held is now missing from the totals — and the
                // user must be told, or the numbers lie.
                unreadableFiles += 1
                continue
            }
            for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
                // Blank lines are structure, not data: every transcript ends with a newline.
                guard !line.allSatisfy(\.isWhitespace) else { continue }

                switch TranscriptParser.parseLine(String(line), using: decoder) {
                case .event(let event): events.append(event)
                case .ignored: continue
                case .malformed: skippedLines += 1
                }
            }
        }
        return ScanResult(
            events: events, skippedLines: skippedLines, unreadableFiles: unreadableFiles)
    }
}
