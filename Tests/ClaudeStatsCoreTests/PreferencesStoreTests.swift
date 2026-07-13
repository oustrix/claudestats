import Foundation
import Testing

@testable import ClaudeStatsCore

private func scratchSettingsFile() throws -> URL {
    try makeScratchRoot("settings").appending(path: "settings.json")
}

@Test func noSettingsFileYieldsDefaultsAndWritesOne() throws {
    let file = try scratchSettingsFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

    let loaded = PreferencesStore(fileURL: file).load()

    #expect(loaded == Preferences.default)
    #expect(FileManager.default.fileExists(atPath: file.path()))
}

@Test func savedPreferencesSurviveAReload() throws {
    let file = try scratchSettingsFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let store = PreferencesStore(fileURL: file)
    let prefs = Preferences(theme: .claude, refreshInterval: .fifteen, transcriptRoot: "/here")

    try store.save(prefs)

    #expect(PreferencesStore(fileURL: file).load() == prefs)
}

/// A broken file must not crash the app or bubble a throw to the interface — it loads defaults.
@Test func aCorruptSettingsFileFallsBackToDefaults() throws {
    let file = try scratchSettingsFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    try Data("{ not json".utf8).write(to: file)

    let loaded = PreferencesStore(fileURL: file).load()

    #expect(loaded == Preferences.default)
}

@Test func savingSettingsCreatesMissingDirectories() throws {
    let root = try makeScratchRoot("settings-nested")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "a/b/settings.json")

    try PreferencesStore(fileURL: file).save(.default)

    #expect(FileManager.default.fileExists(atPath: file.path()))
}
