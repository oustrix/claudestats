import Foundation
import Testing

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

/// The settings sheet's behaviour, asserted against `DashboardModel` where it lives — the sheet's
/// controls are thin wrappers over these methods, and the `NSOpenPanel` a folder change routes
/// through is a runtime modal ViewInspector cannot drive, so the outcome is tested here.

private func loadPreferences(besides file: URL) -> Preferences {
    scratchPreferencesStore(besides: file).load()
}

@MainActor @Test func settingTheThemeUpdatesPreferencesAndPersists() async throws {
    let file = try makeScratchLayoutFile("set-theme")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)
    #expect(model.preferences.theme == .slate)

    model.setTheme(.claude)

    #expect(model.preferences.theme == .claude)
    #expect(loadPreferences(besides: file).theme == .claude)
}

@MainActor @Test func settingTheRefreshIntervalUpdatesPreferencesAndPersists() async throws {
    let file = try makeScratchLayoutFile("set-interval")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)
    #expect(model.preferences.refreshInterval == .thirty)

    model.setRefreshInterval(.fifteen)

    #expect(model.preferences.refreshInterval == .fifteen)
    #expect(loadPreferences(besides: file).refreshInterval == .fifteen)
}

@MainActor @Test func settingTheTranscriptRootRebuildsTheStoreForThatRootAndPersists() async throws {
    let file = try makeScratchLayoutFile("set-root")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var capturedRoots: [URL] = []
    let model = DashboardModel(
        layoutStore: LayoutStore(fileURL: file),
        preferencesStore: scratchPreferencesStore(besides: file), home: home,
        makeStore: { root in
            capturedRoots.append(root)
            return StatsStore(source: StubEventSource(events: []))
        })
    let storeBefore = model.stats

    model.setTranscriptRoot("/custom/root")

    #expect(capturedRoots.last == URL(filePath: "/custom/root"))
    #expect(model.stats !== storeBefore)
    #expect(model.preferences.transcriptRoot == "/custom/root")
    #expect(loadPreferences(besides: file).transcriptRoot == "/custom/root")
}

/// An empty selection clears the override rather than storing a path that resolves to nothing.
@MainActor @Test func clearingTheTranscriptRootFallsBackToTheDefaultRoot() async throws {
    let file = try makeScratchLayoutFile("clear-root")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var capturedRoots: [URL] = []
    let model = DashboardModel(
        layoutStore: LayoutStore(fileURL: file),
        preferencesStore: scratchPreferencesStore(besides: file), home: home,
        makeStore: { root in
            capturedRoots.append(root)
            return StatsStore(source: StubEventSource(events: []))
        })

    model.setTranscriptRoot("")

    #expect(model.preferences.transcriptRoot == nil)
    #expect(capturedRoots.last == FileEventSource.defaultRoot)
}

@MainActor @Test func resetLayoutRestoresTheDefaultAndPersists() async throws {
    let file = try makeScratchLayoutFile("reset-layout")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let custom = [BlockConfig(type: .sessionList, timeframe: .allTime, limit: 3)]
    let model = await seededModel(custom, file: file)
    #expect(model.blocks == custom)

    model.resetLayout()

    #expect(model.blocks == Layout.default.blocks)
    #expect(LayoutStore(fileURL: file).load().layout == Layout.default)
}

/// The store is built against the stored override the moment the model loads, not only after a change.
@MainActor @Test func aStoredRootIsHonoredOnLaunch() async throws {
    let file = try makeScratchLayoutFile("launch-root")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let prefsStore = scratchPreferencesStore(besides: file)
    try prefsStore.save(Preferences(transcriptRoot: "/on/disk"))
    var capturedRoots: [URL] = []

    _ = DashboardModel(
        layoutStore: LayoutStore(fileURL: file), preferencesStore: prefsStore, home: home,
        makeStore: { root in
            capturedRoots.append(root)
            return StatsStore(source: StubEventSource(events: []))
        })

    #expect(capturedRoots == [URL(filePath: "/on/disk")])
}

@MainActor @Test func settingShowCostUpdatesPreferencesAndPersists() async throws {
    let file = try makeScratchLayoutFile("set-showcost")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)
    #expect(model.preferences.showCost == true)

    model.setShowCost(false)

    #expect(model.preferences.showCost == false)
    #expect(loadPreferences(besides: file).showCost == false)
}

/// The model loads its rates from the injected pricing store, so the cost cards have prices to draw.
@MainActor @Test func theModelLoadsPricingFromItsStore() async throws {
    let file = try makeScratchLayoutFile("model-pricing")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)

    #expect(model.pricing == .default)
}
