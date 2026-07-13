import Foundation
import Testing

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

/// The KPI card compares the current timeframe to the immediately preceding equal-length window.
/// The comparison is composed from `Aggregation.total`, so these pin the composition, not a new
/// counting rule. A fixed `now` and calendar keep the windows from drifting with the wall clock.

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private let now = Date(timeIntervalSince1970: 1_800_000_000)  // fixed reference instant

/// An event `daysAgo` before `now`, carrying `io` input tokens (input+output = io).
private func event(daysAgo: Int, io: Int) -> TranscriptEvent {
    makeEvent(
        messageID: "\(daysAgo)-\(io)", requestID: "\(daysAgo)-\(io)",
        timestamp: utc.date(byAdding: .day, value: -daysAgo, to: now)!,
        usage: TokenUsage(input: io, output: 0, cacheCreation: 0, cacheRead: 0))
}

@Test func aBoundedWindowWithPriorActivityYieldsASignedFraction() {
    // Current window (last 7 days): 118. Preceding window (the 7 days before that): 100.
    let events = [event(daysAgo: 0, io: 118), event(daysAgo: 8, io: 100)]

    let delta = periodDelta(.inputOutput, over: events, timeframe: .last7Days, now: now, calendar: utc)

    #expect(delta != nil)
    #expect(abs(delta! - 0.18) < 0.0001)
}

@Test func aDropShowsANegativeFraction() {
    let events = [event(daysAgo: 0, io: 50), event(daysAgo: 8, io: 100)]

    let delta = periodDelta(.inputOutput, over: events, timeframe: .last7Days, now: now, calendar: utc)

    #expect(delta != nil)
    #expect(abs(delta! - (-0.5)) < 0.0001)
}

@Test func noPriorActivityYieldsNoDelta() {
    // Only a current-window event: dividing by a zero prior total would be meaningless.
    let events = [event(daysAgo: 0, io: 118)]

    #expect(periodDelta(.inputOutput, over: events, timeframe: .last7Days, now: now, calendar: utc) == nil)
}

@Test func anUnboundedTimeframeYieldsNoDelta() {
    let events = [event(daysAgo: 0, io: 118), event(daysAgo: 8, io: 100)]

    #expect(periodDelta(.inputOutput, over: events, timeframe: .allTime, now: now, calendar: utc) == nil)
}
