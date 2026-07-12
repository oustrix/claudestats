import Foundation
import Testing

@testable import ClaudeStatsCore

/// UTC+3, so a late-evening UTC timestamp falls on the next local day.
private let moscow: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
    return calendar
}()

private func event(at iso: String, input: Int = 1) -> TranscriptEvent {
    makeEvent(
        messageID: iso, timestamp: instant(iso),
        usage: TokenUsage(input: input, output: 0, cacheCreation: 0, cacheRead: 0))
}

// MARK: - Timeframe filtering

@Test func lastSevenDaysIncludesTodayAndSixPrecedingDays() {
    let now = instant("2026-07-10T12:00:00Z")
    let events = [
        event(at: "2026-07-10T00:30:00Z"),  // today
        event(at: "2026-07-04T23:00:00Z"),  // 2026-07-05 local — the sixth preceding day
        event(at: "2026-07-03T10:00:00Z"),  // 2026-07-03 local — outside
    ]

    #expect(Aggregation.filter(events, timeframe: .last7Days, now: now, calendar: moscow).count == 2)
}

@Test func allTimeKeepsEveryEvent() {
    let events = [event(at: "2020-01-01T00:00:00Z"), event(at: "2026-07-10T00:00:00Z")]

    let kept = Aggregation.filter(
        events, timeframe: .allTime, now: instant("2026-07-10T12:00:00Z"), calendar: moscow)

    #expect(kept.count == 2)
}

@Test func lastThirtyDaysReachesFurtherBackThanSeven() {
    let now = instant("2026-07-10T12:00:00Z")
    let events = [event(at: "2026-06-20T10:00:00Z")]

    #expect(Aggregation.filter(events, timeframe: .last7Days, now: now, calendar: moscow).isEmpty)
    #expect(Aggregation.filter(events, timeframe: .last30Days, now: now, calendar: moscow).count == 1)
}

/// The same filter serves messages, since both carry a timestamp.
@Test func filteringWorksOnMessagesToo() {
    let messages = Counting.messages(from: [event(at: "2020-01-01T00:00:00Z")])

    let kept = Aggregation.filter(
        messages, timeframe: .last7Days, now: instant("2026-07-10T12:00:00Z"), calendar: moscow)

    #expect(kept.isEmpty)
}

// MARK: - Daily bucketing

/// 21:30 UTC is 00:30 the next day in UTC+3, and that is the day the user worked.
@Test func anEveningMessageIsAttributedToItsLocalDay() {
    let series = Aggregation.timeSeries(
        .inputOutput, over: [event(at: "2026-07-02T21:30:00Z")], bucket: .day,
        timeframe: .allTime, now: instant("2026-07-03T12:00:00Z"), calendar: moscow)

    #expect(series.count == 1)
    #expect(moscow.dateComponents([.day], from: series[0].date).day == 3)
}

@Test func dailyTotalsSumToTheGrandTotal() {
    let events = [
        event(at: "2026-07-01T10:00:00Z", input: 5),
        event(at: "2026-07-02T10:00:00Z", input: 7),
        event(at: "2026-07-02T20:00:00Z", input: 11),
    ]

    let series = Aggregation.timeSeries(
        .inputOutput, over: events, bucket: .day, timeframe: .allTime,
        now: instant("2026-07-03T00:00:00Z"), calendar: moscow)

    #expect(
        series.reduce(0) { $0 + $1.value }
            == Aggregation.total(.inputOutput, over: events, timeframe: .allTime))
}

/// A session spanning midnight contributes to both days, each message on its own day.
@Test func aSessionCrossingMidnightSplitsItsTokensAcrossTwoDays() {
    let events = [
        event(at: "2026-07-02T20:40:00Z", input: 100),  // 23:40 local, 2 July
        event(at: "2026-07-02T22:20:00Z", input: 30),  // 01:20 local, 3 July
    ]

    let series = Aggregation.timeSeries(
        .inputOutput, over: events, bucket: .day, timeframe: .allTime,
        now: instant("2026-07-03T12:00:00Z"), calendar: moscow)

    #expect(series.map(\.value) == [100, 30])
}

/// A gap in the middle of a range is a zero, not a missing point: the chart must not lie by
/// connecting two distant days as if they were adjacent.
@Test func emptyDaysAppearAsZeroes() {
    let events = [
        event(at: "2026-07-01T10:00:00Z", input: 5),
        event(at: "2026-07-04T10:00:00Z", input: 9),
    ]

    let series = Aggregation.timeSeries(
        .inputOutput, over: events, bucket: .day, timeframe: .allTime,
        now: instant("2026-07-04T20:00:00Z"), calendar: moscow)

    #expect(series.map(\.value) == [5, 0, 0, 9])
}

@Test func hourBucketsSplitADayIntoHours() {
    let events = [
        event(at: "2026-07-02T09:10:00Z", input: 2),
        event(at: "2026-07-02T09:50:00Z", input: 3),
        event(at: "2026-07-02T11:00:00Z", input: 4),
    ]

    let series = Aggregation.timeSeries(
        .inputOutput, over: events, bucket: .hour, timeframe: .allTime,
        now: instant("2026-07-02T12:00:00Z"), calendar: moscow)

    #expect(series.map(\.value) == [5, 0, 4])
}

/// The entry point windows its events by the timeframe it is given — the caller does not pre-filter.
@Test func aTimeSeriesWindowsByItsTimeframe() {
    let now = instant("2026-07-10T12:00:00Z")
    let events = [event(at: "2020-01-01T00:00:00Z"), event(at: "2026-07-10T09:00:00Z")]

    let series = Aggregation.timeSeries(
        .inputOutput, over: events, bucket: .day, timeframe: .last7Days, now: now, calendar: moscow)

    #expect(series.count == 1)
}

@Test func aTimeSeriesOverNoEventsIsEmpty() {
    let series = Aggregation.timeSeries(
        .inputOutput, over: [], bucket: .day, timeframe: .allTime,
        now: instant("2026-07-02T12:00:00Z"), calendar: moscow)

    #expect(series.isEmpty)
}
