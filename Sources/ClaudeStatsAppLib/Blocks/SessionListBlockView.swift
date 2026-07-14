import ClaudeStatsCore
import SwiftUI

/// Recent sessions, newest first.
///
/// The duration is the span between a session's first and last response. It counts the lunch break
/// you took in the middle, and there is nothing in the transcripts that would let it not to — so it
/// is labelled "span", not "active time".
struct SessionListBlockView: View {
    let block: BlockConfig
    let events: [TranscriptEvent]
    let home: String
    /// The pricing to cost each session with, and nil when cost is turned off — which also drops the
    /// cost column. One flag drives both: no pricing in, no cost out.
    var pricing: Pricing?
    @Environment(\.theme) private var theme

    private var sessions: [Session] {
        Array(
            Aggregation.sessions(
                from: events, home: home, timeframe: block.timeframe, now: .now, pricing: pricing
            ).prefix(block.resolvedLimit))
    }

    var body: some View {
        let sessions = sessions

        if sessions.isEmpty {
            Text("No sessions in this timeframe").font(.callout).foregroundStyle(theme.sub)
        } else {
            VStack(spacing: 8) {
                ForEach(sessions) { session in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.project.displayName)
                                .lineLimit(1)
                                .foregroundStyle(theme.txt)
                                .help(session.project.abbreviatedPath)
                            Text(session.start, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(theme.mut)
                        }
                        Spacer(minLength: 8)

                        Text(session.end.timeIntervalSince(session.start).durationLabel)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(theme.sub)
                            .help("Span from first to last response, breaks included")
                            .frame(width: 60, alignment: .trailing)

                        Text((session.usage.input + session.usage.output).compact)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(theme.txt)
                            .help("\(session.messageCount) responses")
                            .frame(width: 60, alignment: .trailing)

                        // Shown only when cost is on: `pricing` is nil off, so `estimatedCost` is nil.
                        if let cost = session.estimatedCost {
                            Text(cost.currency)
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(theme.accent)
                                .help("Estimated cost")
                                .frame(width: 70, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}
