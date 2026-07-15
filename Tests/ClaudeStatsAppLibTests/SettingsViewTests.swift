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
    #expect(parseRate("1e19") == nil)
    #expect(parseRate("10000000000000000000") == nil)
    #expect(parseRate("1000001") == nil)
    #expect(parseRate("1000000") == 1_000_000)
}

/// The settings sheet now carries a General / Pricing tab bar; both titles are present.
@MainActor @Test func settingsSheetShowsTheTabBar() async throws {
    let file = try makeScratchLayoutFile("settings-tabs")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)

    let view = try SettingsView(model: model).inspect()

    _ = try view.find(text: "General")
    _ = try view.find(text: "Pricing")
}

/// The Pricing tab lists every priced family and the pricing file path. Rendered directly via
/// `initialTab`, since `body` only builds the active tab's subtree.
@MainActor @Test func settingsSheetPricingTabShowsFamiliesAndFilePath() async throws {
    let file = try makeScratchLayoutFile("settings-pricing")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)

    let view = try SettingsView(model: model, initialTab: .pricing).inspect()

    _ = try view.find(text: "PRICING")
    _ = try view.find(text: "Opus")
    _ = try view.find(text: "Sonnet")
    _ = try view.find(text: "Haiku")
    _ = try view.find(text: "Fable")
    _ = try view.find(text: "Pricing file")
    _ = try view.find(text: model.pricingFileURL.path())
}
