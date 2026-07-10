import Foundation
import Testing

@testable import ClaudeStatsCore

/// A scratch transcript tree that the test can append to.
private func makeRoot() throws -> URL {
    let root = URL.temporaryDirectory.appending(path: "claudestats-scan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private let oneEvent = """
    {"type":"assistant","timestamp":"2026-07-02T09:43:05.761Z","sessionId":"s","cwd":"/p",\
    "requestId":"r","message":{"id":"m","model":"claude-opus-4-8","content":[],\
    "usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    """

@Test func unchangedFilesProduceTheSameScanState() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try (oneEvent + "\n").write(
        to: root.appending(path: "a.jsonl"), atomically: true, encoding: .utf8)

    let before = try FileScanState.capture(root: root)
    let after = try FileScanState.capture(root: root)

    #expect(before == after)
}

@Test func appendingToAFileChangesTheScanState() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "a.jsonl")
    try (oneEvent + "\n").write(to: file, atomically: true, encoding: .utf8)
    let before = try FileScanState.capture(root: root)

    let appended = oneEvent.replacingOccurrences(of: #""id":"m""#, with: #""id":"m2""#)
    try (oneEvent + "\n" + appended + "\n").write(to: file, atomically: true, encoding: .utf8)
    let after = try FileScanState.capture(root: root)

    #expect(before != after)
}

@Test func addingAFileChangesTheScanState() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try (oneEvent + "\n").write(
        to: root.appending(path: "a.jsonl"), atomically: true, encoding: .utf8)
    let before = try FileScanState.capture(root: root)

    try (oneEvent + "\n").write(
        to: root.appending(path: "b.jsonl"), atomically: true, encoding: .utf8)
    let after = try FileScanState.capture(root: root)

    #expect(before != after)
}

/// The point of the scan state: skip parsing entirely when no transcript moved.
@Test func loadSkipsParsingWhenNothingChanged() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try (oneEvent + "\n").write(
        to: root.appending(path: "a.jsonl"), atomically: true, encoding: .utf8)
    let source = FileEventSource(root: root)

    let first = try #require(try source.loadEventsIfChanged(since: nil))
    #expect(first.result.events.count == 1)

    #expect(try source.loadEventsIfChanged(since: first.state) == nil)
}

@Test func loadReparsesWhenAFileChanged() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "a.jsonl")
    try (oneEvent + "\n").write(to: file, atomically: true, encoding: .utf8)
    let source = FileEventSource(root: root)
    let first = try #require(try source.loadEventsIfChanged(since: nil))

    let appended = oneEvent.replacingOccurrences(of: #""id":"m""#, with: #""id":"m2""#)
    try (oneEvent + "\n" + appended + "\n").write(to: file, atomically: true, encoding: .utf8)

    let second = try #require(try source.loadEventsIfChanged(since: first.state))
    #expect(second.result.events.count == 2)
}

/// Passing no previous state means an explicit refresh: always reparse.
@Test func explicitRefreshAlwaysReparses() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try (oneEvent + "\n").write(
        to: root.appending(path: "a.jsonl"), atomically: true, encoding: .utf8)
    let source = FileEventSource(root: root)
    _ = try source.loadEventsIfChanged(since: nil)

    #expect(try source.loadEventsIfChanged(since: nil) != nil)
}
