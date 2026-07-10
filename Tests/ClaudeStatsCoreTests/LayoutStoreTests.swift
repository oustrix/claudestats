import Foundation
import Testing

@testable import ClaudeStatsCore

private func scratchFile() throws -> URL {
    try makeScratchRoot("layout").appending(path: "layout.json")
}

@Test func noLayoutFileYieldsTheDefaultAndWritesIt() throws {
    let file = try scratchFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

    let loaded = LayoutStore(fileURL: file).load()

    #expect(loaded.layout == Layout.default)
    #expect(loaded.wasReset == false)
    #expect(loaded.persistenceError == nil)
    #expect(FileManager.default.fileExists(atPath: file.path()))
}

@Test func aSavedLayoutSurvivesAReload() throws {
    let file = try scratchFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let store = LayoutStore(fileURL: file)
    let layout = Layout(blocks: [BlockConfig(type: .sessionList, timeframe: .allTime, limit: 3)])

    try store.save(layout)

    #expect(LayoutStore(fileURL: file).load().layout == layout)
}

/// A broken file is preserved, not deleted: it may be the only copy of a dashboard the user built.
@Test func aMalformedLayoutIsMovedAsideAndReplacedByTheDefault() throws {
    let file = try scratchFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    try Data("{ this is not json".utf8).write(to: file)

    let loaded = LayoutStore(fileURL: file).load()

    #expect(loaded.layout == Layout.default)
    #expect(loaded.wasReset)
    let backup = file.appendingPathExtension("bak")
    #expect(FileManager.default.fileExists(atPath: backup.path()))
    #expect(try String(contentsOf: backup, encoding: .utf8) == "{ this is not json")
}

/// An unknown block type is not corruption. The file stays put; the dashboard just draws less.
@Test func anUnknownBlockTypeIsReportedWithoutResettingTheFile() throws {
    let file = try scratchFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    try Data(
        """
        {"version": 1, "blocks": [
          {"id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "type": "flameGraph", "timeframe": "allTime"}
        ]}
        """.utf8
    ).write(to: file)

    let loaded = LayoutStore(fileURL: file).load()

    #expect(loaded.skipped == [.unknownType("flameGraph")])
    #expect(loaded.wasReset == false)
    #expect(loaded.layout.blocks.isEmpty)
    #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("bak").path()) == false)
}

/// Announcing a reset that never reached the disk would be a lie: the broken file is still there,
/// and it will greet the user again at the next launch.
@Test func aResetThatCannotBeWrittenSaysSo() throws {
    let root = try makeScratchRoot("readonly")
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path())
        try? FileManager.default.removeItem(at: root)
    }
    let file = root.appending(path: "layout.json")
    try Data("{ broken".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path())

    let loaded = LayoutStore(fileURL: file).load()

    #expect(loaded.wasReset)
    #expect(loaded.persistenceError != nil)
}

@Test func savingCreatesMissingDirectories() throws {
    let root = try makeScratchRoot("nested")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "a/b/layout.json")

    try LayoutStore(fileURL: file).save(Layout.default)

    #expect(FileManager.default.fileExists(atPath: file.path()))
}

/// A second reset must not silently destroy the first backup.
@Test func anExistingBackupIsNotOverwrittenSilently() throws {
    let file = try scratchFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    try Data("first breakage".utf8).write(to: file)
    _ = LayoutStore(fileURL: file).load()
    try Data("second breakage".utf8).write(to: file)

    _ = LayoutStore(fileURL: file).load()

    let backups = try FileManager.default.contentsOfDirectory(
        atPath: file.deletingLastPathComponent().path()
    ).filter { $0.contains("bak") }
    #expect(backups.count == 2)
}
