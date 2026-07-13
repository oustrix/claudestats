import Foundation
import Testing

@testable import ClaudeStatsCore

/// UTC+3 with weeks starting Monday, so the window's first cell is a Monday and a Wednesday message
/// lands in the week beginning the preceding Monday.
private let mondayWeek: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
    calendar.firstWeekday = 2  // Monday
    return calendar
}()

private func event(at iso: String, input: Int = 1) -> TranscriptEvent {
    makeEvent(
        messageID: iso, timestamp: instant(iso),
        usage: TokenUsage(input: input, output: 0, cacheCreation: 0, cacheRead: 0))
}

/// A Wednesday, so the current week begins Monday 2026-07-06.
private let now = instant("2026-07-08T12:00:00Z")

// MARK: - Window shape

/// 51 full week-columns plus the current week truncated at today. `now` is a Wednesday, the third
/// day of a Monday-based week, so the last column holds three cells rather than seven.
@Test func dayModeIsSevenRowsAcrossFiftyTwoWeeks() {
    let heatmap = Aggregation.heatmap(
        .inputOutput, over: [], bucket: .day, now: now, calendar: mondayWeek)

    #expect(heatmap.cells.count == (Aggregation.heatmapWeeks - 1) * 7 + 3)
    #expect(heatmap.bucket == .day)
}

@Test func weekModeIsOneCellPerWeek() {
    let heatmap = Aggregation.heatmap(
        .inputOutput, over: [], bucket: .week, now: now, calendar: mondayWeek)

    #expect(heatmap.cells.count == 52)
    #expect(heatmap.bucket == .week)
}

/// The window is aligned to whole weeks: its first cell falls on the calendar's first weekday.
@Test func theWindowStartsOnTheFirstWeekday() {
    let heatmap = Aggregation.heatmap(
        .inputOutput, over: [], bucket: .day, now: now, calendar: mondayWeek)

    let firstDate = try! #require(heatmap.cells.first?.date)
    #expect(mondayWeek.component(.weekday, from: firstDate) == mondayWeek.firstWeekday)
}

/// An hour bucket is unreadable as a calendar grid, so it is drawn by day rather than refused.
@Test func anHourBucketCoercesToDay() {
    let byHour = Aggregation.heatmap(
        .inputOutput, over: [], bucket: .hour, now: now, calendar: mondayWeek)
    let byDay = Aggregation.heatmap(
        .inputOutput, over: [], bucket: .day, now: now, calendar: mondayWeek)

    #expect(byHour.bucket == .day)
    #expect(byHour.cells.count == byDay.cells.count)
}

/// The current week is drawn only through today; days still to come are not rendered as empty
/// cells. `now` is a Wednesday, so the last cell is that Wednesday, not the following Sunday.
@Test func futureDaysInTheCurrentWeekAreNotDrawn() {
    let heatmap = Aggregation.heatmap(
        .inputOutput, over: [], bucket: .day, now: now, calendar: mondayWeek)

    let today = mondayWeek.startOfDay(for: now)
    #expect(heatmap.cells.allSatisfy { $0.date <= today })
    #expect(heatmap.cells.last?.date == today)
}

// MARK: - Density and reconciliation

@Test func emptyDaysAreZeroValuedLevelZeroCells() {
    let heatmap = Aggregation.heatmap(
        .inputOutput, over: [event(at: "2026-07-07T10:00:00Z", input: 5)],
        bucket: .day, now: now, calendar: mondayWeek)

    // Every day through today is present, and only the one active day is non-zero.
    #expect(heatmap.cells.count == (Aggregation.heatmapWeeks - 1) * 7 + 3)
    #expect(heatmap.cells.filter { $0.value == 0 }.allSatisfy { $0.level == 0 })
    #expect(heatmap.cells.filter { $0.value > 0 }.count == 1)
}

@Test func cellValuesReconcileWithTheTotalOverTheWindow() {
    let events = [
        event(at: "2026-06-15T10:00:00Z", input: 5),
        event(at: "2026-06-22T10:00:00Z", input: 7),
        event(at: "2026-07-07T20:00:00Z", input: 11),
    ]

    let heatmap = Aggregation.heatmap(
        .inputOutput, over: events, bucket: .day, now: now, calendar: mondayWeek)

    #expect(
        heatmap.cells.reduce(0) { $0 + $1.value }
            == Aggregation.total(.inputOutput, over: events, timeframe: .allTime))
}

/// Activity older than the fixed window is not counted, however recent the caller's `now`.
@Test func activityBeforeTheWindowIsExcluded() {
    let events = [
        event(at: "2024-01-01T10:00:00Z", input: 999),  // well before the 52-week window
        event(at: "2026-07-07T10:00:00Z", input: 3),
    ]

    let heatmap = Aggregation.heatmap(
        .inputOutput, over: events, bucket: .day, now: now, calendar: mondayWeek)

    #expect(heatmap.cells.reduce(0) { $0 + $1.value } == 3)
}

// MARK: - Quantile levels

/// A lone giant must not drag the varied moderate days down to a single level.
@Test func outliersDoNotFlattenTheScale() {
    let events = [
        event(at: "2026-07-01T10:00:00Z", input: 10),
        event(at: "2026-07-02T10:00:00Z", input: 20),
        event(at: "2026-07-03T10:00:00Z", input: 30),
        event(at: "2026-07-04T10:00:00Z", input: 40),
        event(at: "2026-07-05T10:00:00Z", input: 10_000_000),  // the outlier
    ]

    let heatmap = Aggregation.heatmap(
        .inputOutput, over: events, bucket: .day, now: now, calendar: mondayWeek)

    let moderateLevels = heatmap.cells.filter { $0.value > 0 && $0.value < 10_000_000 }.map(\.level)
    // The moderate days spread across levels rather than all collapsing to level 1.
    #expect(Set(moderateLevels).count > 1)
    #expect(moderateLevels.contains { $0 >= 2 })
    #expect(!heatmap.thresholds.isEmpty)
}

@Test func fewDistinctValuesUseFewerLevels() {
    let events = [
        event(at: "2026-07-01T10:00:00Z", input: 5),
        event(at: "2026-07-02T10:00:00Z", input: 50),
        event(at: "2026-07-03T10:00:00Z", input: 500),
    ]

    let heatmap = Aggregation.heatmap(
        .inputOutput, over: events, bucket: .day, now: now, calendar: mondayWeek)

    let nonZeroLevels = Set(heatmap.cells.map(\.level)).subtracting([0])
    // Three distinct values: at most three non-zero levels, never a fourth forced onto them.
    #expect(nonZeroLevels.count <= 3)
    #expect((nonZeroLevels.max() ?? 0) <= 3)
    #expect(heatmap.thresholds.count <= 2)
}
