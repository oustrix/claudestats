import ClaudeStatsCore
import SwiftUI

/// No transcripts at all. Deliberately not a dashboard of zeros: a zero the user reads as measured
/// is a lie, and this is the one place the difference matters most.
struct NoTranscriptsView: View {
    let root: URL

    var body: some View {
        ContentUnavailableView {
            Label("No transcripts found", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Nothing to read at \(root.path()). This is not zero usage — it is no data.")
        }
    }
}

/// A loaded scan with nothing to draw: the layout has no blocks. A named type, like its siblings
/// here, so it reads as one of the dashboard's states rather than an inline conditional.
struct EmptyDashboardView: View {
    var body: some View {
        ContentUnavailableView(
            "An empty dashboard", systemImage: "square.dashed",
            description: Text("Add a block from the toolbar."))
    }
}

struct LoadFailedView: View {
    let error: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Could not read transcripts", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error).font(.callout.monospaced())
        } actions: {
            Button("Try again", action: retry)
        }
    }
}

/// What the most recent scan managed to read, and what it did not. Shown always, not only on
/// failure: a count the user cannot audit is a count they have to take on faith.
struct ScanSummary: View {
    let scan: ScanResult

    var body: some View {
        HStack(spacing: 6) {
            Text("\(scan.events.count.grouped) lines")

            if scan.skippedLines > 0 {
                Text("· \(scan.skippedLines) skipped")
                    .foregroundStyle(.orange)
                    .help("Lines that did not parse. Each one loses a single response.")
            }
            if !scan.unreadableFiles.isEmpty {
                Text("· \(scan.unreadableFiles.count) unreadable")
                    .foregroundStyle(.red)
                    .help(
                        "Files that could not be opened. Every response they held is missing:\n"
                            + scan.unreadableFiles.map(\.path).joined(separator: "\n"))
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

/// Anything the layout file could not give us. Dismissible, because it describes a past event.
struct LayoutNotices: View {
    let skipped: [SkippedBlock]
    let wasReset: Bool
    let persistenceError: String?
    let dismiss: () -> Void

    var body: some View {
        if !skipped.isEmpty || wasReset || persistenceError != nil {
            VStack(alignment: .leading, spacing: 4) {
                if wasReset {
                    Label(
                        "The layout file could not be read. It was moved aside and replaced with the default.",
                        systemImage: "arrow.uturn.backward")
                }
                if let persistenceError {
                    Label(
                        "The layout could not be written: \(persistenceError)",
                        systemImage: "exclamationmark.triangle")
                }
                ForEach(skipped, id: \.self) { block in
                    switch block {
                    case .unknownType(let name):
                        Label(
                            "Skipped a block of unknown type “\(name)”. It may need a newer build.",
                            systemImage: "questionmark.square.dashed")
                    case .unreadableParameters(let type):
                        Label(
                            "Skipped a “\(type.title)” block: one of its parameters was not understood.",
                            systemImage: "exclamationmark.square.dashed")
                    }
                }
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .padding(6)
            }
        }
    }
}
