import Foundation
import Testing

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

private func blocksOnDisk(_ file: URL) -> [BlockConfig] {
    LayoutStore(fileURL: file).load().layout.blocks
}

// MARK: - init

@MainActor @Test func initLoadsTheBlocksFromAValidLayout() async throws {
    let file = try makeScratchLayoutFile("init-valid")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let blocks = [
        BlockConfig(type: .bigNumber, metric: .allTokens, timeframe: .last7Days),
        BlockConfig(type: .sessionList, timeframe: .allTime, limit: 3),
    ]

    let model = await seededModel(blocks, file: file)

    #expect(model.blocks == blocks)
    #expect(model.wasReset == false)
    #expect(model.skipped.isEmpty)
    #expect(model.persistenceError == nil)
}

@MainActor @Test func initResetsToDefaultsOnAMalformedLayout() async throws {
    let file = try makeScratchLayoutFile("init-malformed")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    try Data(malformedLayoutJSON.utf8).write(to: file)

    let model = DashboardModel(
        stats: await loadedStore(), layoutStore: LayoutStore(fileURL: file),
        preferencesStore: scratchPreferencesStore(besides: file), home: home)

    #expect(model.wasReset)
    #expect(model.blocks == Layout.default.blocks)
}

@MainActor @Test func initPropagatesSkippedBlocks() async throws {
    let file = try makeScratchLayoutFile("init-skipped")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    try Data(skippedTypeLayoutJSON.utf8).write(to: file)

    let model = DashboardModel(
        stats: await loadedStore(), layoutStore: LayoutStore(fileURL: file),
        preferencesStore: scratchPreferencesStore(besides: file), home: home)

    #expect(model.skipped == [.unknownType("flameGraph")])
    #expect(model.wasReset == false)
}

@MainActor @Test func initPropagatesAPersistenceError() async throws {
    // A broken file the loader will try to move aside — but the directory is read-only, so the
    // reset cannot be written and the error must surface rather than be swallowed.
    try await withScratchLayoutFile { file, makeReadOnly in
        try Data(malformedLayoutJSON.utf8).write(to: file)
        try makeReadOnly()

        let model = DashboardModel(
            stats: await loadedStore(), layoutStore: LayoutStore(fileURL: file),
        preferencesStore: scratchPreferencesStore(besides: file), home: home)

        #expect(model.wasReset)
        #expect(model.persistenceError != nil)
    }
}

// MARK: - editing

@MainActor @Test func addAppendsNewBlockOfEachTypeAndPersists() async throws {
    for type in BlockType.allCases {
        let file = try makeScratchLayoutFile("add-\(type)")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let model = await seededModel([], file: file)

        model.add(type)

        var expected = BlockConfig.newBlock(of: type)
        let appended = try #require(model.blocks.last)
        expected.id = appended.id
        #expect(appended == expected)
        #expect(blocksOnDisk(file) == model.blocks)
    }
}

@MainActor @Test func removeDropsTheBlockAndPersists() async throws {
    let file = try makeScratchLayoutFile("remove")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let a = BlockConfig(type: .bigNumber, timeframe: .last7Days)
    let b = BlockConfig(type: .sessionList, timeframe: .allTime)
    let model = await seededModel([a, b], file: file)

    model.remove(a)

    #expect(model.blocks == [b])
    #expect(blocksOnDisk(file) == [b])
}

@MainActor @Test func moveReordersAndPersists() async throws {
    let file = try makeScratchLayoutFile("move")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let a = BlockConfig(type: .bigNumber, timeframe: .last7Days)
    let b = BlockConfig(type: .timeSeries, timeframe: .last30Days, bucket: .day)
    let c = BlockConfig(type: .sessionList, timeframe: .allTime)
    let model = await seededModel([a, b, c], file: file)

    model.move(from: [0], to: 3)

    #expect(model.blocks == [b, c, a])
    #expect(blocksOnDisk(file) == model.blocks)
}

@MainActor @Test func updateReplacesTheSameIdBlockAndPersists() async throws {
    let file = try makeScratchLayoutFile("update")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let a = BlockConfig(type: .bigNumber, metric: .inputOutput, timeframe: .last7Days)
    let model = await seededModel([a], file: file)
    var edited = a
    edited.metric = .allTokens
    edited.timeframe = .allTime

    model.update(edited)

    #expect(model.blocks == [edited])
    #expect(blocksOnDisk(file) == [edited])
}

@MainActor @Test func updateWithAnUnknownIdIsANoOp() async throws {
    let file = try makeScratchLayoutFile("update-noop")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let a = BlockConfig(type: .bigNumber, timeframe: .last7Days)
    let model = await seededModel([a], file: file)

    model.update(BlockConfig(type: .heatmap, timeframe: .last30Days, bucket: .week))

    #expect(model.blocks == [a])
}

// MARK: - dismissNotices & persistence failure

@MainActor @Test func dismissNoticesClearsResetAndPersistenceError() async throws {
    try await withScratchLayoutFile { file, makeReadOnly in
        try Data(malformedLayoutJSON.utf8).write(to: file)
        try makeReadOnly()
        let model = DashboardModel(
            stats: await loadedStore(), layoutStore: LayoutStore(fileURL: file),
        preferencesStore: scratchPreferencesStore(besides: file), home: home)
        #expect(model.wasReset)
        #expect(model.persistenceError != nil)

        model.dismissNotices()

        #expect(model.wasReset == false)
        #expect(model.persistenceError == nil)
        #expect(model.skipped.isEmpty)
    }
}

@MainActor @Test func dismissNoticesClearsSkipped() async throws {
    let file = try makeScratchLayoutFile("dismiss-skipped")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    try Data(skippedTypeLayoutJSON.utf8).write(to: file)
    let model = DashboardModel(
        stats: await loadedStore(), layoutStore: LayoutStore(fileURL: file),
        preferencesStore: scratchPreferencesStore(besides: file), home: home)
    #expect(model.skipped.isEmpty == false)

    model.dismissNotices()

    #expect(model.skipped.isEmpty)
}

@MainActor @Test func aMutationSetsPersistenceErrorOnAnUnwritableStoreAndTheSuccessPathClearsIt()
    async throws
{
    try await withScratchLayoutFile { file, makeReadOnly in
        let model = await seededModel([], file: file)

        // Success path: a writable directory leaves the error nil.
        model.add(.bigNumber)
        #expect(model.persistenceError == nil)

        // Now the directory cannot be written; the next mutation must say so, not lose the edit.
        try makeReadOnly()
        model.add(.sessionList)
        #expect(model.persistenceError != nil)
    }
}

// MARK: - scan/events projection

@MainActor @Test func projectionIsEmptyWhenTheStoreHasNotLoaded() async throws {
    let file = try makeScratchLayoutFile("projection-idle")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = DashboardModel(
        stats: StatsStore(source: StubEventSource(events: [])),
        layoutStore: LayoutStore(fileURL: file),
        preferencesStore: scratchPreferencesStore(besides: file), home: home)

    #expect(model.scan == nil)
    #expect(model.events.isEmpty)
}

@MainActor @Test func projectionExposesTheLoadedEvents() async throws {
    let file = try makeScratchLayoutFile("projection-loaded")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let events = [makeEvent(messageID: "a"), makeEvent(messageID: "b")]
    let model = DashboardModel(
        stats: await loadedStore(events), layoutStore: LayoutStore(fileURL: file),
        preferencesStore: scratchPreferencesStore(besides: file), home: home)

    #expect(model.scan != nil)
    #expect(model.events.map(\.messageID) == ["a", "b"])
}

// MARK: - Edit mode

/// Edit mode starts off — the resting dashboard is clean — and toggling it is transient UI state
/// that never rewrites the layout file.
@MainActor @Test func editingStartsOffAndTogglesWithoutPersisting() async throws {
    let file = try makeScratchLayoutFile("editing")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([BlockConfig(type: .bigNumber, timeframe: .last7Days)], file: file)
    let before = blocksOnDisk(file)

    #expect(model.isEditing == false)

    model.setEditing(true)
    #expect(model.isEditing == true)

    model.setEditing(false)
    #expect(model.isEditing == false)
    #expect(blocksOnDisk(file) == before)
    #expect(model.persistenceError == nil)
}

// MARK: - Status projection

/// The toolbar's "N responses" is the all-time response count over the loaded events.
@MainActor @Test func responseCountIsTheAllTimeResponseTotal() async throws {
    let file = try makeScratchLayoutFile("response-count")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let events = [
        makeEvent(messageID: "a"), makeEvent(messageID: "b"), makeEvent(messageID: "c"),
    ]
    let model = await seededModel([], file: file, events: events)

    #expect(model.responseCount == 3)
}

// MARK: - Breakdown detail modal state

@MainActor @Test func expandBreakdownRecordsTheTargetAndReplacesAPriorOne() async throws {
    let file = try makeScratchLayoutFile("expand-breakdown")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let a = BlockConfig(type: .breakdown, timeframe: .last30Days, dimension: .model)
    let b = BlockConfig(type: .breakdown, timeframe: .last30Days, dimension: .tool)
    let model = await seededModel([a, b], file: file)

    #expect(model.expandedBreakdown == nil)

    model.expandBreakdown(a)
    #expect(model.expandedBreakdown == a)

    // Opening another card replaces the target — only one modal at a time.
    model.expandBreakdown(b)
    #expect(model.expandedBreakdown == b)
}

@MainActor @Test func collapseBreakdownClearsTheTarget() async throws {
    let file = try makeScratchLayoutFile("collapse-breakdown")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let a = BlockConfig(type: .breakdown, timeframe: .last30Days, dimension: .project)
    let model = await seededModel([a], file: file)

    model.expandBreakdown(a)
    model.collapseBreakdown()

    #expect(model.expandedBreakdown == nil)
}

/// Opening or closing the detail modal is transient UI state: it must not rewrite the layout file.
@MainActor @Test func expandingABreakdownDoesNotPersistTheLayout() async throws {
    let file = try makeScratchLayoutFile("expand-no-persist")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let a = BlockConfig(type: .breakdown, timeframe: .last30Days, dimension: .model)
    let model = await seededModel([a], file: file)
    let before = blocksOnDisk(file)

    model.expandBreakdown(a)
    model.collapseBreakdown()

    #expect(blocksOnDisk(file) == before)
    #expect(model.persistenceError == nil)
}

// MARK: - pricing

@MainActor @Test func setRateUpdatesPricingAndPersists() async throws {
    let file = try makeScratchLayoutFile("set-rate")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)

    let edited = ModelRate(input: 9, output: 90, cacheWrite: 11.25, cacheRead: 0.9)
    model.setRate(family: "opus", rate: edited)

    #expect(model.pricing.rates["opus"] == edited)
    // Persisted: a fresh store over the same file reads the edit back.
    let onDisk = scratchPricingStore(besides: file).load()
    #expect(onDisk.rates["opus"] == edited)
}

@MainActor @Test func resetPricingRestoresDefaultsAndPersists() async throws {
    let file = try makeScratchLayoutFile("reset-pricing")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)
    model.setRate(family: "opus", rate: ModelRate(input: 1, output: 1, cacheWrite: 1, cacheRead: 1))

    model.resetPricing()

    #expect(model.pricing == Pricing.default)
    #expect(scratchPricingStore(besides: file).load() == Pricing.default)
}
