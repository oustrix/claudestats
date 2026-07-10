import Foundation

/// What a dashboard block counts.
///
/// Cache reads dominate a real corpus — over 90% of all tokens — so `allTokens` is, to within
/// rounding, a chart of cache reads. That is why the metric is a block parameter and not a global
/// choice. See openspec `design.md`, "Cache tokens dominate".
public enum Metric: String, Codable, CaseIterable, Sendable {
    case inputOutput
    case cacheRead
    case cacheCreation
    case allTokens
    /// The number of API responses, which is the number of `Message` values.
    case requests
}

/// How far back a block looks, counted in whole local calendar days.
public enum Timeframe: String, Codable, CaseIterable, Sendable {
    case last7Days
    case last30Days
    case allTime

    /// The number of local days the window spans, today included. `nil` means no lower bound.
    var days: Int? {
        switch self {
        case .last7Days: 7
        case .last30Days: 30
        case .allTime: nil
        }
    }
}

/// The width of one point on a time series.
public enum Bucket: String, Codable, CaseIterable, Sendable {
    case day
    case hour

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .hour: .hour
        }
    }

    /// The instant the bucket containing `date` begins, in the given calendar's timezone.
    func start(of date: Date, in calendar: Calendar) -> Date {
        switch self {
        case .day:
            calendar.startOfDay(for: date)
        case .hour:
            calendar.date(
                from: calendar.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
        }
    }
}

/// What a breakdown block groups by.
public enum Dimension: String, Codable, CaseIterable, Sendable {
    case model
    case project
    case tool
}
