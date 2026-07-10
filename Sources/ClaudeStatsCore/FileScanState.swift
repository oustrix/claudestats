import Foundation

/// A fingerprint of the transcript tree: every `.jsonl` file with its size and modification time.
///
/// Comparing two of these answers "did anything move?" without reading a byte of content. That is
/// the whole mechanism behind the periodic refresh: transcripts are appended to, never rewritten,
/// so size and mtime are enough. `FSEvents` would buy instant reaction at the cost of debouncing
/// and partial-line handling — see openspec `design.md`, "Refresh without a file watcher".
public struct FileScanState: Equatable, Sendable {
    private let stamps: [String: Stamp]

    private enum Stamp: Equatable, Sendable {
        case measured(size: Int, modified: Date)
        /// Present but unreadable. A case of its own, so no reader has to know that a size of -1
        /// is a lie. A file that later becomes readable compares unequal and triggers a reparse.
        case unreadable
    }

    public static func capture(root: URL) -> FileScanState {
        capture(files: transcriptFiles(under: root))
    }

    /// Takes the file list so a caller that already enumerated the tree does not walk it twice.
    static func capture(files: [URL]) -> FileScanState {
        var stamps: [String: Stamp] = [:]
        for file in files {
            let values = try? file.resourceValues(forKeys: [
                .fileSizeKey, .contentModificationDateKey,
            ])
            if let size = values?.fileSize, let modified = values?.contentModificationDate {
                stamps[file.path()] = .measured(size: size, modified: modified)
            } else {
                stamps[file.path()] = .unreadable
            }
        }
        return FileScanState(stamps: stamps)
    }
}
