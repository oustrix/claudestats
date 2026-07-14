## Why

The dashboard reports tokens but never dollars. Users want a rough sense of what a corpus "cost", and every other stat is already computed from the same deduplicated messages — the money figure is one multiplication away. This is phase 3 of the four-phase redesign: a dollar cost *estimate*, computed in Core from the deduplicated messages and rendered as a KPI card and a per-session column. (Breakdown expand-to-modal is phase 4.)

Cost must never flow through the token-counting machinery: it is derived, per-model, from the four token kinds times published per-model rates. And it must never lie — an unpriced model is surfaced, never silently costed at $0.

## What Changes

- Add a `Pricing` value type and a `PricingStore` in Core that persist a pretty-printed, hand-editable `pricing.json` beside `layout.json`/`settings.json` in Application Support, falling back to bundled defaults on a missing or corrupt file exactly as `LayoutStore`/`PreferencesStore` do. Rates are per-model-family, in US dollars per 1,000,000 tokens, for the four token kinds: input, output, cacheWrite (cacheCreation), cacheRead.
- Add `Aggregation.cost(over:pricing:timeframe:now:calendar:)` — an Aggregation-style entry point that takes raw `[TranscriptEvent]`, deduplicates internally via `Counting.messages`, and returns an estimated dollar total plus a per-model breakdown and the set of unpriced model ids. Cost is derived; there is no `Metric.cost`.
- Extend `Aggregation.sessions` with an optional `pricing`, so each `Session` can carry an `estimatedCost`.
- Add `showCost: Bool` (default true) to `Preferences` — one field, forward/backward compatible with the phase-2 `settings.json`.
- Add a new `BlockType.cost` KPI card ("Cost estimate", accent-coloured currency, "estimate · not a bill"), and make it the third of four span-3 KPI cards in `Layout.default` (Input+output, Requests, Cost estimate, Cache read).
- Gate everything cost-related on `showCost`: hide cost blocks and the per-session cost column when off.
- Add a Cost section to the settings sheet, and cost output to `make dump`.

## Capabilities

### New Capabilities
- `cost-estimate`: a per-model dollar cost estimate derived from deduplicated messages and user-owned, hand-editable pricing, surfaced as a KPI card, a per-session column, and a `make dump` line, gated by a `showCost` preference, with unpriced models surfaced rather than silently costed at zero.

### Modified Capabilities
<!-- None. Phase 1/2 requirements are unchanged; cost is additive and perturbs no counted token number. -->

## Impact

- **Core (`ClaudeStatsCore`)**: new `Pricing`/`ModelRate`, `PricingStore` (mirrors `LayoutStore`), `CostEstimate`; `Aggregation.cost`; `Session.estimatedCost` and a `pricing` parameter on `Aggregation.sessions`; `Preferences.showCost`. No token counter changes — every token number is byte-identical.
- **App (`ClaudeStatsAppLib`)**: `DashboardModel` loads `Pricing` and exposes `showCost`/`setShowCost`; a `CostBlockView`; `DashboardView` filters cost blocks when `showCost` is off; `SessionListBlockView` gains an accent cost column; `SettingsView` gains a Cost section; `Layout.default` gains the cost card.
- **Dump (`ClaudeStatsDump`)**: prints the estimated total and per-model cost.
- No new dependencies. `pricing.json` and the extra `settings.json` field are both forward- and backward-compatible.
