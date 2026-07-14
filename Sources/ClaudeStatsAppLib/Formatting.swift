import ClaudeStatsCore
import Foundation

// Presentation names for core's vocabulary. They live here, not in the core: what a metric is
// called is a product decision, and the core has no opinions about English.

extension Metric {
    var title: String {
        switch self {
        case .inputOutput: "Input + output"
        case .cacheRead: "Cache read"
        case .cacheCreation: "Cache creation"
        case .allTokens: "All tokens"
        case .requests: "Requests"
        }
    }

    /// Whether the metric counts tokens. `requests` counts responses, and reads oddly as "2.1M".
    var countsTokens: Bool { self != .requests }
}

extension Timeframe {
    var title: String {
        switch self {
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .allTime: "All time"
        }
    }
}

extension Bucket {
    var title: String {
        switch self {
        case .day: "By day"
        case .hour: "By hour"
        case .week: "By week"
        }
    }
}

extension BreakdownDimension {
    var title: String {
        switch self {
        case .model: "Model"
        case .project: "Project"
        case .tool: "Tool"
        }
    }
}

extension BlockType {
    var title: String {
        switch self {
        case .bigNumber: "Number"
        case .cost: "Cost estimate"
        case .timeSeries: "Chart over time"
        case .breakdown: "Breakdown"
        case .sessionList: "Sessions"
        case .heatmap: "Heatmap"
        }
    }

    var symbol: String {
        switch self {
        case .bigNumber: "number"
        case .cost: "dollarsign.circle"
        case .timeSeries: "chart.bar"
        case .breakdown: "list.bullet"
        case .sessionList: "clock"
        case .heatmap: "square.grid.3x3"
        }
    }

    /// A block that draws its own fixed window instead of honoring `timeframe` returns that window's
    /// label here; a timeframe-driven block returns nil. One property drives both the card header and
    /// whether the editor offers a Timeframe control, so "ignores timeframe" lives in a single place —
    /// and the window length stays sourced from `Aggregation.heatmapWeeks`, never re-typed.
    var fixedWindowLabel: String? {
        switch self {
        case .heatmap: "Last \(Aggregation.heatmapWeeks) weeks"
        case .bigNumber, .cost, .timeSeries, .breakdown, .sessionList: nil
        }
    }
}

extension Int {
    /// `2.1M` for a headline, where the exact digit is noise. The precise figure belongs in a
    /// tooltip or `make dump`, not in a number the eye only compares.
    var compact: String { formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) }

    /// `2,041,714` — every digit, for a place the reader may want to check.
    var grouped: String { formatted(.number) }
}

extension Double {
    /// `$142.50` — a dollar estimate, always two decimals. The cost figures are US dollars; this is
    /// their one presentation, so the currency code lives in a single place.
    var currency: String {
        formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}

extension TimeInterval {
    /// `1h 20m`, or `4m` under the hour. A session lasting seconds is not worth a unit.
    var durationLabel: String {
        let minutes = Int(self / 60)
        guard minutes >= 60 else { return "\(max(minutes, 1))m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
