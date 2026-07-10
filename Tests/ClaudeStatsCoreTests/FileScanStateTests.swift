import Foundation
import Testing

@testable import ClaudeStatsCore

private let oneEvent = assistantJSONLine(messageID: "m", content: "[]")
private let secondEvent = assistantJSONLine(messageID: "m2", content: "[]")

private func write(_ lines: String..., to file: URL) throws {
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
}

@Test func unchangedFilesProduceTheSameScanState() throws {
    let root = try makeScratchRoot("scan")
    defer { try? FileManager.default.removeItem(at: root) }
    try write(oneEvent, to: root.appending(path: "a.jsonl"))

    #expect(FileScanState.capture(root: root) == FileScanState.capture(root: root))
}

@Test func appendingToAFileChangesTheScanState() throws {
    let root = try makeScratchRoot("scan")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "a.jsonl")
    try write(oneEvent, to: file)
    let before = FileScanState.capture(root: root)

    try write(oneEvent, secondEvent, to: file)

    #expect(before != FileScanState.capture(root: root))
}

@Test func addingAFileChangesTheScanState() throws {
    let root = try makeScratchRoot("scan")
    defer { try? FileManager.default.removeItem(at: root) }
    try write(oneEvent, to: root.appending(path: "a.jsonl"))
    let before = FileScanState.capture(root: root)

    try write(oneEvent, to: root.appending(path: "b.jsonl"))

    #expect(before != FileScanState.capture(root: root))
}

/// The point of the scan state: skip parsing entirely when no transcript moved.
@Test func loadSkipsParsingWhenNothingChanged() throws {
    let root = try makeScratchRoot("scan")
    defer { try? FileManager.default.removeItem(at: root) }
    try write(oneEvent, to: root.appending(path: "a.jsonl"))
    let source = FileEventSource(root: root)

    let first = try #require(try source.loadEventsIfChanged(since: nil))
    #expect(first.result.events.count == 1)

    #expect(try source.loadEventsIfChanged(since: first.state) == nil)
}

@Test func loadReparsesWhenAFileChanged() throws {
    let root = try makeScratchRoot("scan")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "a.jsonl")
    try write(oneEvent, to: file)
    let source = FileEventSource(root: root)
    let first = try #require(try source.loadEventsIfChanged(since: nil))

    try write(oneEvent, secondEvent, to: file)

    let second = try #require(try source.loadEventsIfChanged(since: first.state))
    #expect(second.result.events.count == 2)
}

/// Passing no previous state means an explicit refresh: always reparse.
@Test func explicitRefreshAlwaysReparses() throws {
    let root = try makeScratchRoot("scan")
    defer { try? FileManager.default.removeItem(at: root) }
    try write(oneEvent, to: root.appending(path: "a.jsonl"))
    let source = FileEventSource(root: root)
    _ = try source.loadEventsIfChanged(since: nil)

    #expect(try source.loadEventsIfChanged(since: nil) != nil)
}
