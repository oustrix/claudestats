import SwiftUI
import Testing
import ViewInspector

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

/// The spike gate for §4. If ViewInspector cannot build or inspect a view under Swift 6.2 / macOS 26
/// / swift-testing, this fails and the rest of the view-testing section is dropped — the model and
/// editor-rule coverage (which needs no dependency) still stands. Only synchronous `inspect()` is
/// used; the XCTest-oriented `ViewHosting`/callback APIs are avoided so the suite stays in
/// swift-testing.
@MainActor @Test func viewInspectorCanInspectBlockEditor() throws {
    let editor = BlockEditor(
        block: BlockConfig(type: .bigNumber, timeframe: .last7Days), onChange: { _ in })

    _ = try editor.inspect()
}
