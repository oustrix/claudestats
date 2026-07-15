import AppKit
import ClaudeStatsAppLib
import SwiftUI

@main
struct ClaudeStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("ClaudeStats") {
            DashboardView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 900, height: 720)
    }
}

/// Backstops Cmd+Q. The default Quit menu item is bound to the "q" key equivalent, but on a non-Latin
/// layout (e.g. Cyrillic) the Q key emits a different character, and while a sheet owns the key window
/// AppKit's Latin fallback does not fire it — so Cmd+Q does nothing. A local key monitor matches the
/// physical Q key regardless of layout and exits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The physical Q key (`kVK_ANSI_Q`). Matching the hardware key, not the produced character, makes
    /// Cmd+Q quit on any layout — on a Cyrillic layout the Q position emits "й", not "q".
    private static let qKeyCode: UInt16 = 12

    private var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command), event.keyCode == Self.qKeyCode {
                // `exit(0)`, not `NSApp.terminate`: terminate is swallowed when called from inside
                // event-monitor dispatch, and the app persists its state on every change, so there is
                // nothing to flush on the way out.
                exit(0)
            }
            return event
        }
    }
}
