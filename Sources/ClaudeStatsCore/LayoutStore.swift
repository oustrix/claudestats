import Foundation

/// Reads and writes the dashboard layout, treating the file as the user's, not the app's.
public struct LayoutStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public struct Loaded: Equatable, Sendable {
        public let layout: Layout
        /// Block types this build could not render.
        public let skippedTypes: [String]
        /// The file was unreadable and has been moved aside; the user is looking at defaults.
        public let wasReset: Bool
    }

    /// Never throws. A dashboard that refuses to open because its config is broken is worse than a
    /// dashboard that opens with defaults and says so.
    public func load() -> Loaded {
        guard let data = try? Data(contentsOf: fileURL) else {
            // No file yet: write the default so the user has something to edit.
            try? save(.default)
            return Loaded(layout: .default, skippedTypes: [], wasReset: false)
        }

        guard let decoded = try? Layout.decode(data) else {
            preserve(data)
            try? save(.default)
            return Loaded(layout: .default, skippedTypes: [], wasReset: true)
        }
        return Loaded(layout: decoded.layout, skippedTypes: decoded.skippedTypes, wasReset: false)
    }

    public func save(_ layout: Layout) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Layout.encode(layout).write(to: fileURL, options: .atomic)
    }

    /// Keeps the broken file rather than deleting it: it may be the only copy of a dashboard the
    /// user built by hand. A second breakage must not overwrite the first backup.
    private func preserve(_ data: Data) {
        var backup = fileURL.appendingPathExtension("bak")
        var attempt = 2
        while FileManager.default.fileExists(atPath: backup.path()) {
            backup = fileURL.appendingPathExtension("bak\(attempt)")
            attempt += 1
        }
        try? data.write(to: backup, options: .atomic)
    }

    /// `~/Library/Application Support/ClaudeStats/layout.json`
    public static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "ClaudeStats")
            .appending(path: "layout.json")
    }
}
