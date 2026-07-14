import Foundation
import Testing

@testable import ClaudeStatsCore

@Test func preferencesRoundTripThroughEncodeDecode() throws {
    let prefs = Preferences(theme: .claude, refreshInterval: .sixty, transcriptRoot: "/some/where")

    let decoded = try Preferences.decode(Preferences.encode(prefs))

    #expect(decoded == prefs)
}

@Test func theDefaultPreferencesAreSlate30AndNoOverride() {
    #expect(Preferences.default.theme == .slate)
    #expect(Preferences.default.refreshInterval == .thirty)
    #expect(Preferences.default.transcriptRoot == nil)
    #expect(Preferences.default.showCost == true)
}

/// A phase-2 settings file has no `showCost` key: it must decode to true so cost stays visible.
@Test func anAbsentShowCostDecodesToTrue() throws {
    let json = Data(#"{"theme": "claude", "refreshInterval": 60}"#.utf8)

    let decoded = try Preferences.decode(json)

    #expect(decoded.showCost == true)
    #expect(decoded.theme == .claude)
}

/// A stored `false` survives, so turning cost off persists across launches.
@Test func showCostRoundTrips() throws {
    let prefs = Preferences(showCost: false)

    #expect(try Preferences.decode(Preferences.encode(prefs)).showCost == false)
}

/// A settings file is a flat bag of independent knobs: one stale value must not discard the rest.
@Test func anUnknownThemeStringDecodesToTheDefaultWithoutLosingOtherFields() throws {
    let json = Data(
        """
        {"theme": "midnight", "refreshInterval": 60, "transcriptRoot": "/keep/me"}
        """.utf8)

    let decoded = try Preferences.decode(json)

    #expect(decoded.theme == .slate)
    #expect(decoded.refreshInterval == .sixty)
    #expect(decoded.transcriptRoot == "/keep/me")
}

@Test func anOutOfRangeRefreshIntervalDecodesToTheDefault() throws {
    let json = Data(#"{"refreshInterval": 45}"#.utf8)

    #expect(try Preferences.decode(json).refreshInterval == .thirty)
}

@Test func anEmptyTranscriptRootDecodesToNoOverride() throws {
    let json = Data(#"{"transcriptRoot": ""}"#.utf8)

    #expect(try Preferences.decode(json).transcriptRoot == nil)
}

@Test func anEmptyObjectDecodesToTheDefaults() throws {
    #expect(try Preferences.decode(Data("{}".utf8)) == Preferences.default)
}

/// The user edits this file by hand, so it is written for eyes rather than for bytes.
@Test func encodedPreferencesArePrettyPrinted() throws {
    let text = try String(decoding: Preferences.encode(.default), as: UTF8.self)

    #expect(text.contains("\n"))
    #expect(text.contains("  "))
}

/// An absent override resolves to Claude Code's own transcripts directory.
@Test func resolvedTranscriptRootFallsBackToTheDefault() {
    #expect(Preferences.default.resolvedTranscriptRoot == FileEventSource.defaultRoot)
    #expect(
        Preferences(transcriptRoot: "/custom").resolvedTranscriptRoot
            == URL(filePath: "/custom"))
}
