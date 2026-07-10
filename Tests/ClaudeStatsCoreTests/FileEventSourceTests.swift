import Foundation
import Testing

@testable import ClaudeStatsCore

/// The checked-in transcript tree under `Fixtures/`, laid out the way `~/.claude/projects/` is.
private var fixtureRoot: URL {
    Bundle.module.resourceURL!.appending(path: "Fixtures")
}

@Test func scanReadsEveryTranscriptBelowTheRoot() throws {
    let result = try FileEventSource(root: fixtureRoot).loadEvents()

    // session-a: two lines of msg-1, one of msg-2. session-b: msg-5, msg-6.
    // The user record and the `<synthetic>` one are ignored, not counted as skipped.
    #expect(result.events.count == 5)
    #expect(Set(result.events.map(\.messageID)) == ["msg-1", "msg-2", "msg-5", "msg-6"])
}

/// A malformed line mid-file and a truncated final line: both skipped, both counted, and every
/// other line of the same file still parsed.
@Test func malformedLinesAreSkippedAndCounted() throws {
    let result = try FileEventSource(root: fixtureRoot).loadEvents()

    #expect(result.skippedLines == 2)
}

@Test func missingRootIsReportedAsSuch() {
    let missing = URL(filePath: "/nonexistent/claude/projects")

    #expect(throws: EventSourceError.rootNotFound(missing)) {
        try FileEventSource(root: missing).loadEvents()
    }
}

@Test func emptyRootYieldsNoEventsAndNoSkips() throws {
    let empty = URL.temporaryDirectory.appending(path: "claudestats-empty-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: empty) }

    let result = try FileEventSource(root: empty).loadEvents()

    #expect(result.events.isEmpty)
    #expect(result.skippedLines == 0)
}

/// Files that are not transcripts must not be read at all.
@Test func nonJSONLFilesAreIgnored() throws {
    let root = URL.temporaryDirectory.appending(path: "claudestats-mixed-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try "garbage".write(to: root.appending(path: "notes.txt"), atomically: true, encoding: .utf8)

    let result = try FileEventSource(root: root).loadEvents()

    #expect(result.events.isEmpty)
    #expect(result.skippedLines == 0)
}
