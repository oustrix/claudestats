import Foundation

/// Reads and writes the dashboard layout, treating the file as the user's, not the app's.
public struct LayoutStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public struct Loaded: Sendable {
        public let layout: Layout
        /// Blocks this build could not render.
        public let skipped: [SkippedBlock]
        /// The file was unreadable and has been moved aside; the user is looking at defaults.
        public let wasReset: Bool
        /// The layout could not be written back — a read-only disk, or bad permissions. Without
        /// this the interface would announce a reset that never reached the disk, and the same
        /// broken file would greet the user at the next launch.
        public let persistenceError: (any Error)?
    }

    /// Never throws. A dashboard that refuses to open because its config is broken is worse than a
    /// dashboard that opens with defaults and says so.
    public func load() -> Loaded {
        guard let data = try? Data(contentsOf: fileURL) else {
            // No file yet, or it cannot be read. Either way the user gets defaults; seed the file
            // so there is something to edit.
            return Loaded(
                layout: .default, skipped: [], wasReset: false, persistenceError: attemptSave(.default))
        }

        guard let decoded = try? Layout.decode(data) else {
            let preserveError = preserve(data)
            let saveError = attemptSave(.default)
            return Loaded(
                layout: .default, skipped: [], wasReset: true,
                persistenceError: preserveError ?? saveError)
        }
        return Loaded(
            layout: decoded.layout, skipped: decoded.skipped, wasReset: false, persistenceError: nil)
    }

    public func save(_ layout: Layout) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Layout.encode(layout).write(to: fileURL, options: .atomic)
    }

    private func attemptSave(_ layout: Layout) -> (any Error)? {
        do {
            try save(layout)
            return nil
        } catch {
            return error
        }
    }

    /// Keeps the broken file rather than deleting it: it may be the only copy of a dashboard the
    /// user built by hand. A second breakage must not overwrite the first backup.
    private func preserve(_ data: Data) -> (any Error)? {
        var backup = fileURL.appendingPathExtension("bak")
        var attempt = 2
        while FileManager.default.fileExists(atPath: backup.path()) {
            backup = fileURL.appendingPathExtension("bak\(attempt)")
            attempt += 1
        }
        do {
            try data.write(to: backup, options: .atomic)
            return nil
        } catch {
            return error
        }
    }

    /// `~/Library/Application Support/ClaudeStats/layout.json`
    public static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "ClaudeStats")
            .appending(path: "layout.json")
    }
}
