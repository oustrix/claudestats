import ClaudeStatsCore
import SwiftUI

/// The full-ranking detail modal a breakdown card expands into. The card draws only its configured
/// top-N; this lists *every* row for the same dimension, metric and timeframe. Presented as a sheet
/// and themed exactly like the settings sheet — window fill `theme.win`, an accent tint, pinned dark
/// — so moving between the two reads as one surface.
struct BreakdownDetailView: View {
    let block: BlockConfig
    let events: [TranscriptEvent]
    let home: String
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// The full ranking. `Int.max` as the limit means `Aggregation.breakdown`'s trailing
    /// `.prefix(limit)` keeps every row, so — unlike the card — the modal is never truncated. No new
    /// Core affordance is needed: a limit past the row count already yields all rows.
    private var rows: [BreakdownRow] {
        Aggregation.breakdown(
            block.resolvedDimension, metric: block.resolvedMetric, over: events,
            limit: .max, home: home, timeframe: block.timeframe, now: .now)
    }

    var body: some View {
        let rows = rows
        return VStack(alignment: .leading, spacing: 16) {
            header(rowCount: rows.count)
            Divider().overlay(theme.bord)
            // The card and the modal share one row renderer; the modal numbers its rows and paints
            // the bar/value with the modal's own tokens (`bar`/`mut` vs the card's `accent`/`sub`).
            ScrollView {
                BreakdownRowList(
                    rows: rows, barColor: theme.bar, valueColor: theme.mut, ranked: true,
                    rowSpacing: 8
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 460)
        }
        .padding(24)
        .frame(width: 460)
        .background(theme.win)
        // Drives the accent the system paints for controls that ignore `foregroundStyle`, matching
        // the settings sheet.
        .tint(theme.accent)
        .environment(\.theme, theme)
        .preferredColorScheme(.dark)
    }

    private func header(rowCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(block.title).font(.title2.bold()).foregroundStyle(theme.txt)
            Text(scope(rowCount: rowCount))
                .font(.caption)
                .foregroundStyle(theme.sub)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(theme.pill, in: Capsule())
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.mut)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
    }

    /// The count-and-scope pill: how many rows, and what the value means. The tool dimension ignores
    /// the metric and counts invocations, so its scope reads "invocations"; the rest scope by the
    /// card's timeframe, reusing the same wording the card header shows.
    private func scope(rowCount: Int) -> String {
        let noun = block.resolvedDimension.countedNoun(rowCount)
        let descriptor = block.resolvedDimension == .tool ? "invocations" : block.timeframe.title
        return "\(noun) · \(descriptor)"
    }
}

/// The maximize affordance on a breakdown card's header: faint at rest, brightening to `theme.sub`
/// on hover, so it reads as available without competing with the card's data.
struct BreakdownExpandButton: View {
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .foregroundStyle(hovering ? theme.sub : theme.faint)
        .onHover { hovering = $0 }
        .help("Expand")
        .accessibilityLabel("Expand breakdown")
    }
}
