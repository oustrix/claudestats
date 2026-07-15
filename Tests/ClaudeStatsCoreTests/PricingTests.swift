import Foundation
import Testing

@testable import ClaudeStatsCore

/// A dated snapshot and its undated alias are the same model family, so both are priced identically —
/// the whole point of matching by family rather than by exact id.
@Test func datedAndUndatedClaudeIdsShareAFamily() {
    #expect(Pricing.family(of: "claude-haiku-4-5") == "haiku")
    #expect(Pricing.family(of: "claude-haiku-4-5-20251001") == "haiku")
    #expect(Pricing.family(of: "claude-sonnet-4-6") == "sonnet")
    #expect(Pricing.family(of: "claude-sonnet-5") == "sonnet")
    #expect(Pricing.family(of: "claude-opus-4-8") == "opus")
    #expect(Pricing.family(of: "claude-opus-4-1-20250805") == "opus")
    #expect(Pricing.family(of: "claude-fable-5") == "fable")
}

/// Anything that is not a `claude-` model has no family — it must surface as unpriced, never be
/// guessed into one.
@Test func nonClaudeIdsHaveNoFamily() {
    #expect(Pricing.family(of: "gpt-5.5") == nil)
    #expect(Pricing.family(of: "<synthetic>") == nil)
    #expect(Pricing.family(of: "") == nil)
    #expect(Pricing.family(of: "claude") == nil)
}

/// Cost of one usage under one rate, to the cent. Rates are dollars per 1,000,000 tokens.
@Test func costOfAUsageIsTokensTimesRatePerMillion() {
    // A rate of $5/$25/$6.25/$0.50 per Mtok over 1M/1M/1M/1M tokens is exactly $5+$25+$6.25+$0.50.
    let rate = ModelRate(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5)
    let pricing = Pricing(rates: ["opus": rate])
    let usage = TokenUsage(
        input: 1_000_000, output: 1_000_000, cacheCreation: 1_000_000, cacheRead: 1_000_000)
    #expect(pricing.cost(of: usage, model: "claude-opus-4-8") == 36.75)
}

/// An unpriced model returns nil — the caller decides how to surface it; it is never treated as $0.
@Test func costOfAnUnpricedModelIsNil() {
    #expect(Pricing.default.cost(of: TokenUsage(input: 1, output: 1, cacheCreation: 1, cacheRead: 1),
        model: "gpt-5.5") == nil)
}

/// The bundled defaults cover exactly the known families, and vice versa — the roster and the rates
/// are one source of truth, so neither drifts from the other.
@Test func defaultPricingCoversTheClaudeFamilies() {
    #expect(Set(Pricing.default.rates.keys) == Set(Pricing.families))
}

/// Round-trips through Codable unchanged, and encodes pretty for a person to edit.
@Test func pricingRoundTripsAndEncodesPretty() throws {
    let pricing = Pricing(rates: ["opus": ModelRate(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5)])
    let data = try Pricing.encode(pricing)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\n"))  // pretty-printed
    #expect(try Pricing.decode(data) == pricing)
}
