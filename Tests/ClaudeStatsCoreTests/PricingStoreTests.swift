import Foundation
import Testing

@testable import ClaudeStatsCore

private func scratchPricingFile() throws -> URL {
    try makeScratchRoot("pricing").appending(path: "pricing.json")
}

@Test func noPricingFileYieldsDefaultsAndWritesOne() throws {
    let file = try scratchPricingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

    let loaded = PricingStore(fileURL: file).load()

    #expect(loaded == Pricing.default)
    #expect(FileManager.default.fileExists(atPath: file.path()))
}

@Test func savedPricingSurvivesAReload() throws {
    let file = try scratchPricingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let store = PricingStore(fileURL: file)
    let pricing = Pricing(rates: ["opus": ModelRate(input: 7, output: 30, cacheWrite: 8, cacheRead: 1)])

    try store.save(pricing)

    #expect(PricingStore(fileURL: file).load() == pricing)
}

/// A broken file must not crash or throw to the interface — it loads the bundled defaults.
@Test func aCorruptPricingFileFallsBackToDefaults() throws {
    let file = try scratchPricingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    try Data("{ not json".utf8).write(to: file)

    let loaded = PricingStore(fileURL: file).load()

    #expect(loaded == Pricing.default)
}

@Test func savingPricingCreatesMissingDirectories() throws {
    let root = try makeScratchRoot("pricing-nested")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "a/b/pricing.json")

    try PricingStore(fileURL: file).save(.default)

    #expect(FileManager.default.fileExists(atPath: file.path()))
}
