import Foundation

/// Finds every transcript below `root`. One definition, shared by the scanner and the reader, so
/// the two can never disagree about which files count.
func transcriptFiles(under root: URL) -> [URL] {
    guard
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey])
    else {
        return []
    }
    return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
}

/// A fingerprint of the transcript tree: every `.jsonl` file with its size and modification time.
///
/// Comparing two of these answers "did anything move?" without reading a byte of content. That is
/// the whole mechanism behind the periodic refresh: transcripts are appended to, never rewritten,
/// so size and mtime are enough. `FSEvents` would buy instant reaction at the cost of debouncing
/// and partial-line handling — see openspec `design.md`, "Refresh without a file watcher".
public struct FileScanState: Equatable, Sendable {
    private let stamps: [String: Stamp]

    private struct Stamp: Equatable, Sendable {
        let size: Int
        let modified: Date
    }

    public static func capture(root: URL) throws -> FileScanState {
        var stamps: [String: Stamp] = [:]
        for file in transcriptFiles(under: root) {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let size = values?.fileSize, let modified = values?.contentModificationDate else {
                // A file we cannot stat still belongs in the fingerprint, or its later appearance
                // would look like "nothing changed".
                stamps[file.path()] = Stamp(size: -1, modified: .distantPast)
                continue
            }
            stamps[file.path()] = Stamp(size: size, modified: modified)
        }
        return FileScanState(stamps: stamps)
    }
}
