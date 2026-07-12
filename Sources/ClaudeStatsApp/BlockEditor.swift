import ClaudeStatsCore
import SwiftUI

/// Edits one block's parameters. Only the parameters its type actually uses are offered, so the
/// interface cannot express a `sessionList` with a `bucket`.
struct BlockEditor: View {
    @State var block: BlockConfig
    let onChange: (BlockConfig) -> Void

    var body: some View {
        Form {
            if block.type != .sessionList {
                Picker("Metric", selection: metric) {
                    ForEach(Metric.allCases, id: \.self) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .disabled(block.dimension == .tool)
                // Tokens cannot be attributed to a single tool call, so the metric would be a lie.
                .help(block.dimension == .tool ? "A tool breakdown counts invocations" : "")
            }

            // A fixed-window block draws its own span, so a timeframe would be a dead control.
            if block.type.fixedWindowLabel == nil {
                Picker("Timeframe", selection: $block.timeframe) {
                    ForEach(Timeframe.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            // Each type offers only the buckets it can draw, never `Bucket.allCases` blindly.
            if !block.type.supportedBuckets.isEmpty {
                Picker("Bucket", selection: bucket) {
                    ForEach(block.type.supportedBuckets, id: \.self) { Text($0.title).tag($0) }
                }
            }

            if block.type == .breakdown {
                Picker("Group by", selection: dimension) {
                    ForEach(BreakdownDimension.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            if block.type == .breakdown || block.type == .sessionList {
                Stepper("Rows: \(block.resolvedLimit)", value: limit, in: 1...30)
            }
        }
        .formStyle(.grouped)
        .frame(width: 280)
        .onChange(of: block) { _, updated in onChange(updated) }
    }

    // Bindings that give a default to parameters stored as optional.
    private var metric: Binding<Metric> {
        Binding(get: { block.resolvedMetric }, set: { block.metric = $0 })
    }
    private var bucket: Binding<Bucket> {
        Binding(get: { block.resolvedBucket }, set: { block.bucket = $0 })
    }
    private var dimension: Binding<BreakdownDimension> {
        Binding(get: { block.resolvedDimension }, set: { block.dimension = $0 })
    }
    private var limit: Binding<Int> {
        Binding(get: { block.resolvedLimit }, set: { block.limit = $0 })
    }
}
