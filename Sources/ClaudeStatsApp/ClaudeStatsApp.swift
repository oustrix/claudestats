import ClaudeStatsAppLib
import SwiftUI

@main
struct ClaudeStatsApp: App {
    var body: some Scene {
        WindowGroup("ClaudeStats") {
            DashboardView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 900, height: 720)
    }
}
