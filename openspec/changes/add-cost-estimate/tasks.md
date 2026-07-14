## 1. Core: Pricing model and store (TDD)

- [x] 1.1 Write failing `ClaudeStatsCoreTests` for `Pricing`: family normalization (dated/undated Claude ids → same family; non-Claude id → none); a message's cost = tokens×rate to the cent; codable round-trip; pretty-printed encode
- [x] 1.2 Write failing `PricingStore` tests mirroring `PreferencesStoreTests`: missing file → defaults and seeds; corrupt file → defaults without throwing; a saved value survives a reload
- [x] 1.3 Add `ModelRate` and `Pricing` (Codable, `.default`, `family(of:)`, per-model cost of a `TokenUsage`) in Core
- [x] 1.4 Add `PricingStore` mirroring `LayoutStore`/`PreferencesStore`: `fileURL`, non-throwing `load()`, throwing pretty-printed `save`, `defaultURL` at `Application Support/ClaudeStats/pricing.json`
- [x] 1.5 Confirm the Core suite is green

## 2. Core: cost aggregation (TDD)

- [x] 2.1 Write failing tests for `Aggregation.cost`: exact total for known tokens×rates; unpriced model surfaced not silently zero; dedup matches token totals; per-model breakdown
- [x] 2.2 Write failing tests for per-session cost: `sessions(pricing:)` attaches `estimatedCost`; no pricing → nil
- [x] 2.3 Add `CostEstimate`, `Aggregation.cost`, `Session.estimatedCost`, and the `pricing` parameter on `Aggregation.sessions`
- [x] 2.4 Confirm the Core suite is green

## 3. Core: showCost preference (TDD)

- [x] 3.1 Extend `Preferences` with `showCost: Bool` (default true); update decode/tests for the new field; confirm forward/backward compatibility
- [x] 3.2 Confirm the Core suite is green

## 4. App: model wiring and default layout (TDD)

- [x] 4.1 Write failing `ClaudeStatsAppLibTests`: `DashboardModel` loads pricing via an injected `PricingStore`; `setShowCost` persists; `Layout.default` KPI row is the four span-3 cards with cost third
- [x] 4.2 Add `BlockType.cost` (catalog, `newBlock`, titles/symbol, no buckets); update `Layout.default`
- [x] 4.3 Extend `DashboardModel`: load `Pricing`, expose `pricing` and `showCost`, add `setShowCost`; inject a `PricingStore` (scratch in tests)
- [x] 4.4 Update the affected default-layout/blocktype tests for the new KPI row and the new block type
- [x] 4.5 Confirm the app suite is green

## 5. App: cost UI

- [x] 5.1 Add `CostBlockView` (currency + accent, "estimate · not a bill", pill), and render `.cost` in `BlockCard`
- [x] 5.2 Filter `.cost` blocks from the grid when `showCost` is off
- [x] 5.3 Add the accent per-session cost column in `SessionListBlockView`, shown only when `showCost`
- [x] 5.4 Add the Cost section to `SettingsView` (between Data and Layout) with a themed "Show cost estimate" toggle and the explanatory copy
- [x] 5.5 Add a `Double.currency` formatting helper
- [x] 5.6 A light view test that the cost card and settings section render

## 6. Dump

- [x] 6.1 Print the estimated total cost and per-model cost in `make dump` using `Pricing.default`

## 7. Verification

- [x] 7.1 `make build` clean and `make test` green (both suites); note the before/after test count
- [x] 7.2 Cross-check on a FROZEN snapshot: token counts byte-identical vs `main`; hand-compute one model's cost from its dumped tokens×default rate; note any ccusage methodology comparison
- [x] 7.3 `openspec validate add-cost-estimate --strict`
- [x] 7.4 Commit in logical steps with conventional one-line messages; leave the branch for review (do not merge or push)
