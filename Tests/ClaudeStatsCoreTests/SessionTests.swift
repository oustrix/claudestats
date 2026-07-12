import Foundation
import Testing

@testable import ClaudeStatsCore

private let home = "/Users/me"

private func event(
    _ id: String, session: String, at iso: String, cwd: String = "/Users/me/proj", input: Int = 1
) -> TranscriptEvent {
    makeEvent(
        messageID: id, requestID: "r-\(id)", timestamp: instant(iso), sessionID: session, cwd: cwd,
        usage: TokenUsage(input: input, output: 0, cacheCreation: 0, cacheRead: 0))
}

@Test func sessionBoundariesComeFromEventTimestamps() throws {
    let sessions = Aggregation.sessions(
        from: [
            event("b", session: "s", at: "2026-07-02T12:00:00Z"),
            event("a", session: "s", at: "2026-07-02T09:00:00Z"),
            event("c", session: "s", at: "2026-07-02T15:00:00Z"),
        ], home: home, timeframe: .allTime)

    let session = try #require(sessions.first)
    #expect(sessions.count == 1)
    #expect(session.start == instant("2026-07-02T09:00:00Z"))
    #expect(session.end == instant("2026-07-02T15:00:00Z"))
    #expect(session.messageCount == 3)
}

@Test func aSessionSumsTheTokensOfItsMessages() throws {
    let sessions = Aggregation.sessions(
        from: [
            event("a", session: "s", at: "2026-07-02T09:00:00Z", input: 10),
            event("b", session: "s", at: "2026-07-02T10:00:00Z", input: 5),
        ], home: home, timeframe: .allTime)

    #expect(try #require(sessions.first).usage.input == 15)
}

/// A response written across two lines must not count twice towards a session's totals.
@Test func aSessionCountsMessagesNotLines() throws {
    let usage = TokenUsage(input: 7, output: 0, cacheCreation: 0, cacheRead: 0)
    let sessions = Aggregation.sessions(
        from: [
            makeEvent(messageID: "m", requestID: "r", sessionID: "s", usage: usage),
            makeEvent(messageID: "m", requestID: "r", sessionID: "s", usage: usage),
        ], home: home, timeframe: .allTime)

    let session = try #require(sessions.first)
    #expect(session.messageCount == 1)
    #expect(session.usage.input == 7)
}

/// Two sessions in the corpus change `cwd` mid-session. The first record decides the project.
@Test func aSessionWhoseWorkingDirectoryChangesKeepsItsFirstOne() throws {
    let sessions = Aggregation.sessions(
        from: [
            event("b", session: "s", at: "2026-07-03T01:20:00Z", cwd: "/Users/me/other"),
            event("a", session: "s", at: "2026-07-02T23:40:00Z", cwd: "/Users/me/proj"),
        ], home: home, timeframe: .allTime)

    #expect(try #require(sessions.first).project.fullPath == "/Users/me/proj")
}

@Test func sessionsAreGroupedBySessionIdentifier() {
    let sessions = Aggregation.sessions(
        from: [
            event("a", session: "s1", at: "2026-07-02T09:00:00Z"),
            event("b", session: "s2", at: "2026-07-02T10:00:00Z"),
            event("c", session: "s1", at: "2026-07-02T11:00:00Z"),
        ], home: home, timeframe: .allTime)

    #expect(sessions.count == 2)
    #expect(Set(sessions.map(\.id)) == ["s1", "s2"])
}

/// Sessions are listed newest first, by the time they started.
@Test func sessionsAreSortedByStartDescending() {
    let sessions = Aggregation.sessions(
        from: [
            event("a", session: "old", at: "2026-07-01T09:00:00Z"),
            event("b", session: "new", at: "2026-07-05T09:00:00Z"),
        ], home: home, timeframe: .allTime)

    #expect(sessions.map(\.id) == ["new", "old"])
}

// MARK: - Projects

@Test func aNestedProjectIsNamedByItsLastPathComponent() {
    let project = Project(cwd: "/Users/me/go/projects/gitlab.example.com/ob/snitch", home: home)

    #expect(project.displayName == "snitch")
    #expect(project.fullPath == "/Users/me/go/projects/gitlab.example.com/ob/snitch")
    #expect(project.abbreviatedPath == "~/go/projects/gitlab.example.com/ob/snitch")
}

@Test func theHomeDirectoryIsItsOwnProject() {
    let project = Project(cwd: home, home: home)

    #expect(project.displayName == "~")
    #expect(project.abbreviatedPath == "~")
}

/// Identity is the full path: two directories of the same name are two projects.
@Test func identicallyNamedDirectoriesStayDistinct() {
    let a = Project(cwd: "/a/snitch", home: home)
    let b = Project(cwd: "/b/snitch", home: home)

    #expect(a.displayName == b.displayName)
    #expect(a != b)
}

/// A path outside the home directory keeps its absolute form.
@Test func pathsOutsideHomeAreNotAbbreviated() {
    #expect(Project(cwd: "/tmp/scratch", home: home).abbreviatedPath == "/tmp/scratch")
}

/// `/Users/median` must not be mistaken for a child of `/Users/me`.
@Test func abbreviationMatchesWholePathComponents() {
    #expect(Project(cwd: "/Users/median/work", home: home).abbreviatedPath == "/Users/median/work")
}
