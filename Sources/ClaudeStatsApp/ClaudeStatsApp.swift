import ClaudeStatsCore
import SwiftUI

@main
struct ClaudeStatsApp: App {
    var body: some Scene {
        WindowGroup("ClaudeStats") {
            Text("ClaudeStats \(ClaudeStats.version)")
                .frame(minWidth: 800, minHeight: 600)
        }
    }
}
