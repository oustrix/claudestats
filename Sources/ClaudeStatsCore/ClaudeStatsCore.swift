/// ClaudeStats core: transcript reading and aggregation.
/// Imports only Foundation (+ Observation) — never SwiftUI, Charts, or AppKit. This is a structural
/// rule: the test target depends solely on this module, so any UI import here would be a deliberate
/// act, not an accident.
public enum ClaudeStats {
    public static let version = "0.1.0"
}
