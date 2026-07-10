import Foundation
import Testing

@testable import ClaudeStatsCore

private let oneEvent = assistantJSONLine(messageID: "m", content: "[]")

/// A file we cannot open removes all of its events from the totals. Counting a truncated *line* but
/// swallowing a whole unreadable *file* would report a confidently wrong number — the swallowed
/// error the design forbids.
@Test func unreadableFilesAreCountedNotSwallowed() throws {
    let root = try makeScratchRoot("unreadable")
    defer { try? FileManager.default.removeItem(at: root) }

    let readable = root.appending(path: "good.jsonl")
    try (oneEvent + "\n").write(to: readable, atomically: true, encoding: .utf8)

    let denied = root.appending(path: "denied.jsonl")
    try (oneEvent + "\n").write(to: denied, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path())
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: denied.path()) }

    let result = try FileEventSource(root: root).loadEvents()

    #expect(result.events.count == 1)
    #expect(result.unreadableFiles == 1)
    #expect(result.skippedLines == 0)
}

/// A file that is not valid UTF-8 cannot be decoded, and that is a whole-file failure too.
@Test func nonUTF8FilesAreCountedAsUnreadable() throws {
    let root = try makeScratchRoot("binary")
    defer { try? FileManager.default.removeItem(at: root) }

    try Data([0xFF, 0xFE, 0x00, 0x80]).write(to: root.appending(path: "binary.jsonl"))

    let result = try FileEventSource(root: root).loadEvents()

    #expect(result.events.isEmpty)
    #expect(result.unreadableFiles == 1)
}

@Test func readableFilesReportNoUnreadableCount() throws {
    let root = try makeScratchRoot("fine")
    defer { try? FileManager.default.removeItem(at: root) }
    try (oneEvent + "\n").write(to: root.appending(path: "a.jsonl"), atomically: true, encoding: .utf8)

    #expect(try FileEventSource(root: root).loadEvents().unreadableFiles == 0)
}
