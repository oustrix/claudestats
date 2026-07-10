import Foundation
import Testing

@testable import ClaudeStatsCore

private func instant(_ iso: String) -> Date {
    try! Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(iso)
}

private func message(
    _ id: String, session: String, at iso: String, cwd: String = "/Users/me/proj", input: Int = 1
) -> Message {
    Counting.messages(from: [
        makeEvent(
            messageID: id, timestamp: instant(iso), sessionID: session, cwd: cwd,
            usage: TokenUsage(input: input, output: 0, cacheCreation: 0, cacheRead: 0))
    ])[0]
}

@Test func sessionBoundariesComeFromEventTimestamps() throws {
    let sessions = Aggregation.sessions(
        from: [
            message("b", session: "s", at: "2026-07-02T12:00:00Z"),
            message("a", session: "s", at: "2026-07-02T09:00:00Z"),
            message("c", session: "s", at: "2026-07-02T15:00:00Z"),
        ])

    let session = try #require(sessions.first)
    #expect(sessions.count == 1)
    #expect(session.start == instant("2026-07-02T09:00:00Z"))
    #expect(session.end == instant("2026-07-02T15:00:00Z"))
    #expect(session.messageCount == 3)
}

@Test func aSessionSumsTheTokensOfItsMessages() throws {
    let sessions = Aggregation.sessions(
        from: [
            message("a", session: "s", at: "2026-07-02T09:00:00Z", input: 10),
            message("b", session: "s", at: "2026-07-02T10:00:00Z", input: 5),
        ])

    #expect(try #require(sessions.first).usage.input == 15)
}

/// Two sessions in the corpus change `cwd` mid-session. The first record decides the project.
@Test func aSessionWhoseWorkingDirectoryChangesKeepsItsFirstOne() throws {
    let sessions = Aggregation.sessions(
        from: [
            message("b", session: "s", at: "2026-07-03T01:20:00Z", cwd: "/Users/me/other"),
            message("a", session: "s", at: "2026-07-02T23:40:00Z", cwd: "/Users/me/proj"),
        ])

    #expect(try #require(sessions.first).project.fullPath == "/Users/me/proj")
}

@Test func sessionsAreGroupedBySessionIdentifier() {
    let sessions = Aggregation.sessions(
        from: [
            message("a", session: "s1", at: "2026-07-02T09:00:00Z"),
            message("b", session: "s2", at: "2026-07-02T10:00:00Z"),
            message("c", session: "s1", at: "2026-07-02T11:00:00Z"),
        ])

    #expect(sessions.count == 2)
    #expect(Set(sessions.map(\.id)) == ["s1", "s2"])
}

/// Sessions are listed newest first, by the time they started.
@Test func sessionsAreSortedByStartDescending() {
    let sessions = Aggregation.sessions(
        from: [
            message("a", session: "old", at: "2026-07-01T09:00:00Z"),
            message("b", session: "new", at: "2026-07-05T09:00:00Z"),
        ])

    #expect(sessions.map(\.id) == ["new", "old"])
}

// MARK: - Projects

@Test func aNestedProjectIsNamedByItsLastPathComponent() {
    let project = Project(cwd: "/Users/me/go/projects/gitlab.example.com/ob/snitch", home: "/Users/me")

    #expect(project.displayName == "snitch")
    #expect(project.fullPath == "/Users/me/go/projects/gitlab.example.com/ob/snitch")
    #expect(project.abbreviatedPath == "~/go/projects/gitlab.example.com/ob/snitch")
}

@Test func theHomeDirectoryIsItsOwnProject() {
    let project = Project(cwd: "/Users/me", home: "/Users/me")

    #expect(project.displayName == "~")
    #expect(project.abbreviatedPath == "~")
}

/// Identity is the full path: two directories of the same name are two projects.
@Test func identicallyNamedDirectoriesStayDistinct() {
    let a = Project(cwd: "/a/snitch", home: "/Users/me")
    let b = Project(cwd: "/b/snitch", home: "/Users/me")

    #expect(a.displayName == b.displayName)
    #expect(a != b)
}

/// A path outside the home directory keeps its absolute form.
@Test func pathsOutsideHomeAreNotAbbreviated() {
    let project = Project(cwd: "/tmp/scratch", home: "/Users/me")

    #expect(project.abbreviatedPath == "/tmp/scratch")
}

/// `/Users/median` must not be mistaken for a child of `/Users/me`.
@Test func abbreviationMatchesWholePathComponents() {
    let project = Project(cwd: "/Users/median/work", home: "/Users/me")

    #expect(project.abbreviatedPath == "/Users/median/work")
}
