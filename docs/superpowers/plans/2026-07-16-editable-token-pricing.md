# Editable Token Pricing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Pricing tab to the Settings sheet that edits the four model families' four rates each, persists them to `pricing.json`, and re-prices the cost cards live.

**Architecture:** `DashboardModel.pricing` becomes an observed `var` with `setRate`/`resetPricing` methods that persist through the injected `PricingStore` (mirroring the existing preferences setters). `SettingsView` grows a theme-painted tab bar (reusing its own `SegmentedControl`) splitting a General tab from a new Pricing tab whose numeric fields commit on submit through a tested pure validation helper.

**Tech Stack:** Swift, SwiftUI, swift-testing (`import Testing`), `os.Logger`.

## Global Constraints

- Everything committed is in English — code, comments, tests, commit messages.
- Commits: Conventional Commits, one line, no body, no `Co-Authored-By`. Scopes: `core`, `app`, `spec`, `make`.
- TDD: write the failing test, watch it fail for the right reason, then implement.
- `Sources/ClaudeStatsCore/` imports only `Foundation` (+ `Observation`) — never SwiftUI/AppKit/Charts.
- Never lie silently: a failed persist is logged via `Log.settings.error`, never swallowed without a trace.
- The "tokens unreachable outside the module" invariant is untouched: only public `Pricing`/`ModelRate` (prices) change, never `TokenUsage`.
- Commands: `make test`, `make build`, `make run`.

---

### Task 1: Make pricing editable in DashboardModel

**Files:**
- Modify: `Sources/ClaudeStatsAppLib/DashboardModel.swift` (line 23 `let pricing`; init at 53–78; setters region after line 196)
- Test: `Tests/ClaudeStatsAppLibTests/DashboardModelTests.swift`

**Interfaces:**
- Consumes: `seededModel(_ blocks:file:events:)`, `scratchPricingStore(besides:)`, `makeScratchLayoutFile(_:)`, `home` from `TestSupport.swift`; `Pricing`, `ModelRate`, `PricingStore` from `ClaudeStatsCore`.
- Produces: `DashboardModel.pricing: Pricing` (now `private(set) var`), `func setRate(family: String, rate: ModelRate)`, `func resetPricing()`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/ClaudeStatsAppLibTests/DashboardModelTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test 2>&1 | grep -A2 "setRateUpdates\|resetPricingRestores"`
Expected: compile failure — `value of type 'DashboardModel' has no member 'setRate'` (and `resetPricing`).

- [ ] **Step 3: Store the pricing store and make `pricing` a var**

In `Sources/ClaudeStatsAppLib/DashboardModel.swift`, change line 21–23 comment + declaration:

```swift
    /// The per-model rates the cost cards and per-session column price with. Loaded from the user's
    /// `pricing.json` and now editable in the Pricing tab; observed, so an edit re-prices the cost
    /// cards live. The file stays hand-editable too — both paths write the same `pricing.json`.
    private(set) var pricing: Pricing
```

Add the stored store alongside the other `@ObservationIgnored` stores (after line 48):

```swift
    @ObservationIgnored private let pricingStore: PricingStore
```

In `init`, assign it (the parameter already exists at line 57); after `self.preferencesStore = preferencesStore` (line 62) add:

```swift
        self.pricingStore = pricingStore
```

(`self.pricing = pricingStore.load()` at line 68 stays as-is.)

- [ ] **Step 4: Add the setters**

In the `// MARK: - Preferences` region, after `persistPreferences()` (after line 207, before the closing brace of the class):

```swift
    // MARK: - Pricing

    /// Replaces one family's rate and persists. The view reads `pricing`, so the cost cards and the
    /// per-session cost column re-price on the next render.
    func setRate(family: String, rate: ModelRate) {
        pricing.rates[family] = rate
        persistPricing()
    }

    /// Restores the bundled published defaults and persists — the same shape as `resetLayout`.
    func resetPricing() {
        pricing = .default
        persistPricing()
    }

    /// A failed pricing write is logged, not surfaced, for the same reason as `persistPreferences`:
    /// the sheet has no error affordance, the file is hand-editable, and the change still applies for
    /// the session. The "never lie silently" invariant is met by the log line.
    private func persistPricing() {
        do {
            try pricingStore.save(pricing)
        } catch {
            Log.settings.error("could not save pricing: \(error, privacy: .public)")
        }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test 2>&1 | tail -5`
Expected: build succeeds, suite passes (0 failures).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeStatsAppLib/DashboardModel.swift Tests/ClaudeStatsAppLibTests/DashboardModelTests.swift
git commit -m "feat(app): make token pricing editable and persisted in the model"
```

---

### Task 2: A pure, tested rate-input parser

**Files:**
- Modify: `Sources/ClaudeStatsAppLib/SettingsView.swift` (add a fileprivate-but-testable helper near the top)
- Test: `Tests/ClaudeStatsAppLibTests/SettingsViewTests.swift` (create)

**Interfaces:**
- Produces: `func parseRate(_ text: String) -> Double?` — returns a finite, non-negative `Double`, or `nil` for empty/non-numeric/negative/infinite input. Trims surrounding whitespace and accepts a leading `$`.

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeStatsAppLibTests/SettingsViewTests.swift`:

```swift
import Testing

@testable import ClaudeStatsAppLib

@Test func parseRateAcceptsNonNegativeDecimals() {
    #expect(parseRate("3") == 3)
    #expect(parseRate("6.25") == 6.25)
    #expect(parseRate("0") == 0)
    #expect(parseRate(" 12.5 ") == 12.5)
    #expect(parseRate("$5") == 5)
}

@Test func parseRateRejectsBadInput() {
    #expect(parseRate("") == nil)
    #expect(parseRate("abc") == nil)
    #expect(parseRate("-1") == nil)
    #expect(parseRate("1.2.3") == nil)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make test 2>&1 | grep -A2 "parseRate"`
Expected: compile failure — `cannot find 'parseRate' in scope`.

- [ ] **Step 3: Implement the helper**

In `Sources/ClaudeStatsAppLib/SettingsView.swift`, after the imports (after line 3), add:

```swift
/// Parses a rate field's text into a finite, non-negative dollars-per-Mtok value, or nil when the
/// text is empty, non-numeric, negative, or not finite. Accepts surrounding whitespace and a leading
/// `$` so a pasted "$5" is understood. Not `private` so the parsing is unit-tested without a view.
func parseRate(_ text: String) -> Double? {
    var trimmed = text.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("$") { trimmed.removeFirst() }
    guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
    return value
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `make test 2>&1 | tail -5`
Expected: build succeeds, suite passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatsAppLib/SettingsView.swift Tests/ClaudeStatsAppLibTests/SettingsViewTests.swift
git commit -m "feat(app): add a validated rate parser for the pricing editor"
```

---

### Task 3: Tab bar and the Pricing tab UI

**Files:**
- Modify: `Sources/ClaudeStatsAppLib/SettingsView.swift` (`body`, the `model`/state declarations, the `cost` caption to reuse; add `SettingsTab`, the `initialTab` init, tab bar, pricing views). Note: `parseRate` from Task 2 already lives near the top of this file — do not redefine it.
- Modify (append): `Tests/ClaudeStatsAppLibTests/SettingsViewTests.swift` (existing ViewInspector suite).

**Interfaces:**
- Consumes: `DashboardModel.pricing`, `setRate(family:rate:)`, `resetPricing()` (Task 1); `parseRate(_:)` (Task 2, already in `SettingsView.swift`); existing `SegmentedControl`, `Section`, `SettingsRow`, `PricingStore.defaultURL`, `ModelRate`.
- Produces: `SettingsView.init(model:initialTab:)` with an internal `SettingsTab` enum, so a ViewInspector test can render the Pricing tab directly.

**Testing note — this project DOES test the settings view.** `Tests/ClaudeStatsAppLibTests/SettingsViewTests.swift` already exists and uses **ViewInspector** (a test-only dependency in `Package.swift`) to assert that each settings section's copy is present. Two obligations follow:
1. The existing tests must stay green. They inspect the default render, and General is the default tab, so the Appearance/Data/Cost/Layout copy they look for (`"Slate"`, `"Transcripts folder"`, `"Refresh interval"`, `"Layout file"`, `"Show cost estimate"`, `"COST"`, `model.layoutFileURL.path()`) still renders. Do not change those tests.
2. The Pricing tab needs matching coverage. Because `body` renders only the active tab (`switch tab`), the test constructs the view on the Pricing tab via the `initialTab` seam below and asserts the Pricing copy.

- [ ] **Step 1: Add the tab enum, the `initialTab` seam, and tab state**

In `Sources/ClaudeStatsAppLib/SettingsView.swift`, add the enum below the imports (after the `parseRate` helper from Task 2). It is `internal` (no `private`) so the test target can name it:

```swift
/// The two Settings tabs. `general` holds the original sections; `pricing` holds the rate editor.
/// Not `private`: a ViewInspector test constructs `SettingsView` on a chosen tab via `initialTab`.
enum SettingsTab: String, CaseIterable, Hashable {
    case general, pricing
    var title: String {
        switch self {
        case .general: "General"
        case .pricing: "Pricing"
        }
    }
}
```

Replace `SettingsView`'s stored properties and add an initializer so the starting tab is injectable
(production callers keep constructing `SettingsView(model:)` — `initialTab` defaults to `.general`).
The current declarations are `let model` (line 9) and `@State private var confirmingReset = false`
(line 12); replace that region with:

```swift
    let model: DashboardModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var tab: SettingsTab
    @State private var confirmingReset = false
    @State private var confirmingPricingReset = false

    /// `initialTab` defaults to `.general`, so the app constructs `SettingsView(model:)` unchanged; a
    /// test passes `.pricing` to render and inspect the Pricing tab, which `body`'s `switch` would
    /// otherwise leave out of the tree.
    init(model: DashboardModel, initialTab: SettingsTab = .general) {
        self.model = model
        _tab = State(initialValue: initialTab)
    }
```

(Keep whatever other `@Environment`/`@State` lines the file already had — the block above is the
full replacement for the `model` + environment + `confirmingReset` declarations, now including the
new `tab`/`confirmingPricingReset` state and the initializer.)

- [ ] **Step 2: Split `body` into a tab bar and per-tab content**

Replace `body` (lines 14–32) with:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            SegmentedControl(
                options: SettingsTab.allCases, selection: tab,
                label: \.title, select: { tab = $0 })
            switch tab {
            case .general: general
            case .pricing: pricing
            }
            Divider().overlay(theme.bord)
            footer
        }
        .padding(24)
        .frame(width: 460)
        .background(theme.win)
        .tint(theme.accent)
        .environment(\.theme, theme)
        .preferredColorScheme(.dark)
    }

    /// The original sections, now the General tab.
    private var general: some View {
        VStack(alignment: .leading, spacing: 24) {
            appearance
            data
            cost
            layout
        }
    }
```

- [ ] **Step 3: Add the Pricing tab**

Add after the `layout` computed property (after line 147):

```swift
    // MARK: - Pricing

    /// The families shown, in the default price list's conventional order (most to least expensive),
    /// not the dictionary's undefined order.
    private static let pricingFamilies = ["opus", "sonnet", "haiku", "fable"]

    private var pricing: some View {
        Section(title: "Pricing") {
            Text(
                "Estimated from average published prices, in US dollars per 1,000,000 tokens. Not a "
                    + "billing document — the transcripts record tokens, not dollars."
            )
            .font(.caption)
            .foregroundStyle(theme.mut)
            .fixedSize(horizontal: false, vertical: true)

            PricingHeaderRow()
            ForEach(Self.pricingFamilies, id: \.self) { family in
                PricingRow(
                    family: family,
                    rate: model.pricing.rates[family] ?? ModelRate(
                        input: 0, output: 0, cacheWrite: 0, cacheRead: 0),
                    setRate: { model.setRate(family: family, rate: $0) })
            }

            SettingsRow(label: "Pricing file", detail: PricingStore.defaultURL.path()) {
                Button("Reset…") { confirmingPricingReset = true }
                    .foregroundStyle(theme.accent)
            }
        }
        .confirmationDialog(
            "Reset prices to the published defaults?", isPresented: $confirmingPricingReset
        ) {
            Button("Reset prices", role: .destructive) { model.resetPricing() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your edited token prices will be replaced by the built-in published defaults.")
        }
    }
```

- [ ] **Step 4: Add the row views**

Add near the other private view structs (e.g. after `SegmentedControl`, before `ThemedToggle` — anywhere at file scope inside the file):

```swift
/// The column headers over the four rate fields.
private struct PricingHeaderRow: View {
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 8) {
            Text("").frame(width: 56, alignment: .leading)
            ForEach(["In", "Out", "Write", "Read"], id: \.self) { title in
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.mut)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

/// One family's four editable rate fields. Each field commits on submit or focus loss: an invalid
/// or negative value reverts to the current rate, a valid one calls `setRate` with the whole
/// updated `ModelRate`. Editing per-field but writing the whole rate keeps `setRate` atomic.
private struct PricingRow: View {
    let family: String
    let rate: ModelRate
    let setRate: (ModelRate) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(family.capitalized)
                .foregroundStyle(theme.txt)
                .frame(width: 56, alignment: .leading)
            RateField(value: rate.input) { setRate(with(\.input, $0)) }
            RateField(value: rate.output) { setRate(with(\.output, $0)) }
            RateField(value: rate.cacheWrite) { setRate(with(\.cacheWrite, $0)) }
            RateField(value: rate.cacheRead) { setRate(with(\.cacheRead, $0)) }
        }
    }

    /// A copy of `rate` with one keypath replaced — so a single field edit produces a whole rate.
    private func with(_ keyPath: WritableKeyPath<ModelRate, Double>, _ newValue: Double) -> ModelRate {
        var updated = rate
        updated[keyPath: keyPath] = newValue
        return updated
    }
}

/// A single numeric rate field. Holds a local text draft so intermediate keystrokes never re-price;
/// commits on submit/blur via `parseRate`, reverting the draft when the text is invalid or negative.
private struct RateField: View {
    let value: Double
    let commit: (Double) -> Void
    @Environment(\.theme) private var theme
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.callout.monospaced())
            .foregroundStyle(theme.txt)
            .frame(width: 56)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(theme.pill, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardB, lineWidth: 1))
            .focused($focused)
            .onSubmit(commitDraft)
            .onChange(of: focused) { _, isFocused in if !isFocused { commitDraft() } }
            .onChange(of: value) { _, _ in text = Self.format(value) }
            .onAppear { text = Self.format(value) }
    }

    private func commitDraft() {
        if let parsed = parseRate(text) {
            commit(parsed)
            text = Self.format(parsed)
        } else {
            text = Self.format(value)  // revert: invalid, negative, or empty
        }
    }

    /// Formats a rate the way it is typed back — trimming a trailing `.0` so "3" shows as "3".
    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
```

- [ ] **Step 5: Add the ViewInspector tests for the tab bar and Pricing tab**

Append to `Tests/ClaudeStatsAppLibTests/SettingsViewTests.swift` (alongside the existing settings
tests, matching their style — construct a model over a scratch file, `.inspect()`, assert copy):

```swift
/// The settings sheet now carries a General / Pricing tab bar; both titles are present.
@MainActor @Test func settingsSheetShowsTheTabBar() async throws {
    let file = try makeScratchLayoutFile("settings-tabs")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)

    let view = try SettingsView(model: model).inspect()

    _ = try view.find(text: "General")
    _ = try view.find(text: "Pricing")
}

/// The Pricing tab lists every priced family and the pricing file path. Rendered directly via
/// `initialTab`, since `body` only builds the active tab's subtree.
@MainActor @Test func settingsSheetPricingTabShowsFamiliesAndFilePath() async throws {
    let file = try makeScratchLayoutFile("settings-pricing")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let model = await seededModel([], file: file)

    let view = try SettingsView(model: model, initialTab: .pricing).inspect()

    _ = try view.find(text: "PRICING")
    _ = try view.find(text: "Opus")
    _ = try view.find(text: "Sonnet")
    _ = try view.find(text: "Haiku")
    _ = try view.find(text: "Fable")
    _ = try view.find(text: "Pricing file")
}
```

- [ ] **Step 6: Run the suite (build + existing + new tests)**

Run: `make test 2>&1 | tail -8`
Expected: build succeeds; the two new tests pass; the four pre-existing `settingsSheet…` tests
(`ShowsBothThemeCards`, `ShowsTheDataAndLayoutSections`, `ShowsTheLayoutFilePath`,
`ShowsTheCostSection`) still pass — the tab restructure left the General tab as the default render.
If a pre-existing test now fails, the General tab is not rendering its sections by default: fix the
`body`/`general` wiring, do not edit those tests.

- [ ] **Step 7: Manual verification**

Run: `make run`

Verify, in the running app:
1. Open Settings — a `General | Pricing` tab bar sits under the title; General shows the original Appearance/Data/Cost/Layout sections.
2. Switch to Pricing — four family rows with four fields each, the caption, the file path, and a Reset button.
3. Edit opus's Output to `99`, press Enter — if a Cost or session-list block is on the dashboard, its dollar figure changes.
4. Type `abc` into a field and press Enter — it reverts to the prior number.
5. Reset… → confirm — fields return to defaults (opus output back to `25`).
6. Quit and relaunch — the edited/reset prices persist.

- [ ] **Step 8: Cross-check counts are unaffected**

Run: `make dump 2>&1 | tail -20`
Expected: token counters (input/output/cache) are unchanged from before this feature — only dollar figures depend on pricing. (No token-counting logic changed, so this is a sanity check, not a diff.)

- [ ] **Step 9: Commit**

```bash
git add Sources/ClaudeStatsAppLib/SettingsView.swift Tests/ClaudeStatsAppLibTests/SettingsViewTests.swift
git commit -m "feat(app): add a Pricing tab to settings for editing token rates"
```

---

## Notes on stale comments

While in `Sources/ClaudeStatsCore/Pricing.swift`, the doc comments at lines 20–22 and 36 say prices
are corrected "by hand-editing `pricing.json`". They are no longer the *only* path. If touched,
soften to "hand-edited or edited in the Pricing tab" — but this is not required for the feature to
work and can be folded into Task 1's commit if convenient. Do not change any pricing *logic*.
