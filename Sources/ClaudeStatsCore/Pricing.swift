import Foundation

/// Per-model-family dollar rates for the four token kinds, in US dollars per 1,000,000 tokens.
/// `cacheWrite` prices `TokenUsage.cacheCreation`; `cacheRead` prices `TokenUsage.cacheRead`.
public struct ModelRate: Codable, Equatable, Sendable {
    public var input: Double
    public var output: Double
    public var cacheWrite: Double
    public var cacheRead: Double

    public init(input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }
}

/// A price list, keyed by model *family* (`opus`, `sonnet`, `haiku`, `fable`) rather than by exact
/// model id, so a new dated snapshot of a known family is priced without an edit. Family rates are
/// editable from the app's Pricing tab; a user who wants a per-id override edits `pricing.json`
/// directly — the file is theirs.
///
/// Cost is derived, never a token metric: it is the only way tokens turn into dollars, and it is
/// computed per model from a `Message`'s usage, so a caller cannot sum a per-line, model-erased
/// figure. See `Aggregation.cost`.
public struct Pricing: Codable, Equatable, Sendable {
    /// Rates keyed by the normalized family name.
    public var rates: [String: ModelRate]

    public init(rates: [String: ModelRate]) {
        self.rates = rates
    }

    /// Bundled defaults from Anthropic's currently published per-Mtok list prices. Cache-write uses
    /// the 5-minute-TTL multiplier (1.25x input); cache-read uses ~0.1x input. The user owns and
    /// corrects these in the Pricing tab or by hand-editing `pricing.json`.
    public static let `default` = Pricing(rates: [
        "opus": ModelRate(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5),
        "sonnet": ModelRate(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3),
        "haiku": ModelRate(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.1),
        "fable": ModelRate(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 1),
    ])

    /// The family a transcript model id belongs to: the token after the `claude-` prefix, so
    /// `claude-sonnet-4-6`, `claude-sonnet-5`, and any dated `claude-sonnet-…` snapshot all resolve to
    /// `sonnet`. A model id that is not a `claude-` model (e.g. `gpt-5.5`, `<synthetic>`) has no
    /// family — it must surface as unpriced, never be guessed into one.
    public static func family(of model: String) -> String? {
        let components = model.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count >= 2, components[0] == "claude", !components[1].isEmpty else {
            return nil
        }
        return String(components[1])
    }

    /// The rate for a model, or nil when its family has no entry.
    public func rate(for model: String) -> ModelRate? {
        Pricing.family(of: model).flatMap { rates[$0] }
    }

    /// The dollar cost of a single usage under this pricing, or nil when the model is unpriced. Nil,
    /// not zero: an unknown model must be surfaced by the caller, never silently costed free.
    public func cost(of usage: TokenUsage, model: String) -> Double? {
        guard let rate = rate(for: model) else { return nil }
        return (Double(usage.input) * rate.input
            + Double(usage.output) * rate.output
            + Double(usage.cacheCreation) * rate.cacheWrite
            + Double(usage.cacheRead) * rate.cacheRead) / 1_000_000
    }

    public static func decode(_ data: Data) throws -> Pricing {
        try JSONDecoder().decode(Pricing.self, from: data)
    }

    public static func encode(_ pricing: Pricing) throws -> Data {
        let encoder = JSONEncoder()
        // Hand-edited, so formatted for eyes — the same choice `Layout` and `Preferences` make.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(pricing)
    }
}

/// Reads and writes the pricing file, treating it as the user's, not the app's — the same philosophy
/// as `LayoutStore`/`PreferencesStore`: never crash, fall back to defaults, and seed a file so there
/// is something to hand-edit. A corrupt file is logged and answered with defaults.
public struct PricingStore: Sendable {
    /// Where the pricing lives. Public so the settings sheet can show the user the path it edits.
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Never throws. Missing file → defaults, seeded so there is something to edit. Corrupt file →
    /// defaults, logged, and reseeded so the next launch starts clean.
    public func load() -> Pricing {
        guard let data = try? Data(contentsOf: fileURL) else {
            try? save(.default)
            Log.settings.notice(
                "no readable pricing at \(fileURL.path(), privacy: .public), wrote default")
            return .default
        }
        guard let decoded = try? Pricing.decode(data) else {
            try? save(.default)
            Log.settings.error(
                "pricing at \(fileURL.path(), privacy: .public) was unreadable; reset to default")
            return .default
        }
        return decoded
    }

    public func save(_ pricing: Pricing) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Pricing.encode(pricing).write(to: fileURL, options: .atomic)
    }

    /// `~/Library/Application Support/ClaudeStats/pricing.json`, beside `layout.json`/`settings.json`.
    public static var defaultURL: URL {
        URL.claudeStatsSupportDirectory.appending(path: "pricing.json")
    }
}
