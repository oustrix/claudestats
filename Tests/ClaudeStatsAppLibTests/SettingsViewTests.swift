import SwiftUI
import Testing
import ViewInspector

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

/// The settings sheet's static structure. The `NSOpenPanel` and the toolbar/sheet plumbing are
/// runtime concerns ViewInspector does not drive; only the presence of each section's copy is
/// asserted, so a restyle does not break the test.

@MainActor @Test func settingsSheetShowsBothThemeCards() async throws {
    let file = try makeScratchLayoutFile("settings-themes")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)

    let view = try SettingsView(model: model).inspect()

    _ = try view.find(text: "Slate")
    _ = try view.find(text: "Claude")
}

@MainActor @Test func settingsSheetShowsTheDataAndLayoutSections() async throws {
    let file = try makeScratchLayoutFile("settings-sections")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)

    let view = try SettingsView(model: model).inspect()

    _ = try view.find(text: "Transcripts folder")
    _ = try view.find(text: "Refresh interval")
    _ = try view.find(text: "Layout file")
}

/// The layout row shows the very file the model persists to, not a hard-coded default path.
@MainActor @Test func settingsSheetShowsTheLayoutFilePath() async throws {
    let file = try makeScratchLayoutFile("settings-path")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)

    let view = try SettingsView(model: model).inspect()

    _ = try view.find(text: model.layoutFileURL.path())
}

/// The Cost section names its toggle and carries the "not a billing document" explanation.
@MainActor @Test func settingsSheetShowsTheCostSection() async throws {
    let file = try makeScratchLayoutFile("settings-cost")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)

    let view = try SettingsView(model: model).inspect()

    _ = try view.find(text: "Show cost estimate")
    // The section header is uppercased, matching the other sections' style.
    _ = try view.find(text: "COST")
}

@Test func parseRateAcceptsNonNegativeDecimals() {
    #expect(parseRate("3") == 3)
    #expect(parseRate("6.25") == 6.25)
    #expect(parseRate("0") == 0)
    #expect(parseRate(" 12.5 ") == 12.5)
    #expect(parseRate("$5") == 5)
}

@Test func parseRateRejectsBadInput() {
    #expect(parseRate("") == nil)
    #expect(parseRate("abc") == nil)
    #expect(parseRate("-1") == nil)
    #expect(parseRate("1.2.3") == nil)
}
