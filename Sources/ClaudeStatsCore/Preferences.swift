import Foundation

/// Which of the two dark palettes the app paints from. String-backed so `settings.json` names the
/// palette in words a person editing the file recognizes. The app maps this to a SwiftUI `Theme`;
/// Core stays free of SwiftUI.
public enum ThemeChoice: String, Codable, CaseIterable, Sendable {
    case slate
    case claude
}

/// How often the dashboard re-scans, in seconds. A closed set rather than a free integer: the
/// settings sheet offers three choices, and a raw `Int` on disk stays legible while decoding back to
/// exactly one of them.
public enum RefreshInterval: Int, Codable, CaseIterable, Sendable {
    case fifteen = 15
    case thirty = 30
    case sixty = 60
}

/// The user's preferences, as stored on disk. A flat bag of independent knobs — theme, refresh
/// cadence, and an optional transcripts-root override — kept deliberately small and easy to extend:
/// a later phase adds a field (e.g. cost display) by naming it here and in the two coding methods.
///
/// Decoding is defensive on purpose. Unlike a layout, which is one interdependent document, these
/// knobs are independent, so a single unrecognized value (an unknown theme, an interval the build
/// no longer offers) coerces to that field's default rather than discarding the whole file. Only a
/// structurally broken file (not valid JSON) fails to decode, and `PreferencesStore` answers that
/// with the full defaults.
public struct Preferences: Codable, Equatable, Sendable {
    public var theme: ThemeChoice
    public var refreshInterval: RefreshInterval
    /// A path to read transcripts from. `nil` (absent or empty on disk) means the built-in default,
    /// `~/.claude/projects`.
    public var transcriptRoot: String?
    /// Whether the dashboard shows the dollar cost estimate — the cost KPI card(s) and the per-session
    /// cost column. Default true, matching the mockup. A phase-2 `settings.json` with no `showCost`
    /// key decodes to true, so an older file keeps cost visible.
    public var showCost: Bool

    public init(
        theme: ThemeChoice = .slate,
        refreshInterval: RefreshInterval = .thirty,
        transcriptRoot: String? = nil,
        showCost: Bool = true
    ) {
        self.theme = theme
        self.refreshInterval = refreshInterval
        self.transcriptRoot = transcriptRoot
        self.showCost = showCost
    }

    /// Slate palette, a 30-second refresh, and the built-in transcripts root.
    public static let `default` = Preferences()

    /// The root to actually read from: the override if one is set, else Claude Code's own directory.
    public var resolvedTranscriptRoot: URL {
        transcriptRoot.map { URL(filePath: $0) } ?? FileEventSource.defaultRoot
    }

    /// "Empty means no override" is the one rule for a transcripts path — applied on decode and on a
    /// settings change alike, so a blank selection and a blank file resolve identically.
    public static func normalizedRoot(_ path: String?) -> String? {
        (path?.isEmpty ?? true) ? nil : path
    }

    private enum CodingKeys: String, CodingKey {
        case theme, refreshInterval, transcriptRoot, showCost
    }

    /// Each field is read independently and coerced to its default when absent or unrecognized, so a
    /// stale or hand-mistyped value never costs the user their other settings.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawTheme = try container.decodeIfPresent(String.self, forKey: .theme)
        theme = rawTheme.flatMap(ThemeChoice.init(rawValue:)) ?? .slate
        let rawInterval = try container.decodeIfPresent(Int.self, forKey: .refreshInterval)
        refreshInterval = rawInterval.flatMap(RefreshInterval.init(rawValue:)) ?? .thirty
        transcriptRoot = Preferences.normalizedRoot(
            try container.decodeIfPresent(String.self, forKey: .transcriptRoot))
        // Absent (a phase-2 file) reads as true, so cost stays visible for an older settings file.
        showCost = try container.decodeIfPresent(Bool.self, forKey: .showCost) ?? true
    }

    // `encode(to:)` is the compiler-synthesized one: a custom `init(from:)` and `CodingKeys` do not
    // suppress it, and the synthesized encoder already writes each enum as its raw value and omits an
    // absent optional — exactly the on-disk shape decode expects. Only the static `encode(_:)` below
    // is custom, for the pretty-printing.

    public static func decode(_ data: Data) throws -> Preferences {
        try JSONDecoder().decode(Preferences.self, from: data)
    }

    public static func encode(_ preferences: Preferences) throws -> Data {
        let encoder = JSONEncoder()
        // Hand-edited, so formatted for eyes rather than for bytes — the same choice `Layout` makes.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(preferences)
    }
}

/// Reads and writes the preferences file, treating it as the user's, not the app's — the same
/// philosophy as `LayoutStore`: never crash, fall back to defaults, and seed a file so there is
/// something to hand-edit. Simpler than `LayoutStore` because a settings file has no per-block
/// migration to report; a corrupt file is logged and answered with defaults.
public struct PreferencesStore: Sendable {
    /// Where the settings live. Public so the settings sheet can show the user the path it edits.
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Never throws. Missing file → defaults, seeded so there is something to edit. Corrupt file →
    /// defaults, logged, and reseeded so the next launch starts clean.
    public func load() -> Preferences {
        guard let data = try? Data(contentsOf: fileURL) else {
            try? save(.default)
            Log.settings.notice(
                "no readable settings at \(fileURL.path(), privacy: .public), wrote default")
            return .default
        }
        guard let decoded = try? Preferences.decode(data) else {
            try? save(.default)
            Log.settings.error(
                "settings at \(fileURL.path(), privacy: .public) were unreadable; reset to default")
            return .default
        }
        return decoded
    }

    public func save(_ preferences: Preferences) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Preferences.encode(preferences).write(to: fileURL, options: .atomic)
    }

    /// `~/Library/Application Support/ClaudeStats/settings.json`, beside `layout.json`.
    public static var defaultURL: URL {
        URL.claudeStatsSupportDirectory.appending(path: "settings.json")
    }
}
