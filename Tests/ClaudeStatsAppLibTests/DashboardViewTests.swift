import SwiftUI
import Testing
import ViewInspector

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

/// The state screens `DashboardView` shows, reached through the internal model-injection
/// initializer. The 30-second `.task` refresh loop is a SwiftUI-runtime concern ViewInspector does
/// not drive; only the static content of each state is asserted — on the view type, so a copy edit
/// does not break the test.

@MainActor @Test func dashboardShowsTheFailureScreenWhenTheScanFailed() async throws {
    let file = try makeScratchLayoutFile("dashboard-failed")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = seededModel([], file: file, stats: await failedStore())

    let view = try DashboardView(model: model).inspect()

    _ = try view.find(LoadFailedView.self)
}

@MainActor @Test func dashboardShowsTheNoTranscriptsScreenWhenTheRootIsMissing() async throws {
    let file = try makeScratchLayoutFile("dashboard-none")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = seededModel([], file: file, stats: await noTranscriptsStore(URL(filePath: "/nowhere")))

    let view = try DashboardView(model: model).inspect()

    _ = try view.find(NoTranscriptsView.self)
}

/// A loaded scan with an empty layout shows the empty-dashboard state.
@MainActor @Test func dashboardShowsTheEmptyScreenWhenLoadedWithNoBlocks() async throws {
    let file = try makeScratchLayoutFile("dashboard-empty")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = seededModel([], file: file, stats: await loadedStore())

    let view = try DashboardView(model: model).inspect()

    _ = try view.find(EmptyDashboardView.self)
}
