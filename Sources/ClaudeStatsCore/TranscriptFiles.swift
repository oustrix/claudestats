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
