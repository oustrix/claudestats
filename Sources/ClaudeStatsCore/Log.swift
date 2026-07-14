import Foundation
import os

/// Unified-logging channels, one subsystem, one category per concern. Read them from a terminal
/// without the app in the foreground:
///
///     log stream --predicate 'subsystem == "com.oustrix.claudestats"' --level debug
///     log show   --predicate 'subsystem == "com.oustrix.claudestats"' --last 5m --debug --info
///
/// `.debug` lines need the `--debug` flag to appear in `log show`; `.error` and `.notice` persist
/// on their own. This is the app's debugging surface: an agent driving it has no window to look at,
/// so what happened has to be legible from the log.
public enum Log {
    static let subsystem = "com.oustrix.claudestats"

    /// Reading and parsing transcripts.
    public static let scan = Logger(subsystem: subsystem, category: "scan")
    /// The store's load state and refresh decisions.
    public static let store = Logger(subsystem: subsystem, category: "store")
    /// The layout file: what was loaded, reset, skipped, or failed to persist.
    public static let layout = Logger(subsystem: subsystem, category: "layout")
    /// The settings file: what was loaded, reset, or failed to persist.
    public static let settings = Logger(subsystem: subsystem, category: "settings")

    /// Instruments "Points of Interest" — wrap a span to see it on the timeline.
    public static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
