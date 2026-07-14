## Context

Phase 1 shipped the visual system, phase 2 the settings sheet and `Preferences`/`PreferencesStore`. Every dashboard number already comes from `Counting.messages`, which collapses the several JSONL lines of one response into one `Message` and is the *only* way to a token count — `TranscriptEvent.usage` is internal by design. Phase 3 adds a dollar cost estimate. The load-bearing constraint: cost must be computed from those deduplicated messages, per-model, and must never flow through the token-sum machinery (no `Metric.cost`), because a token metric summed per line inflates ~2.3x and a per-model rate cannot be applied to a metric that has already lost its model.

## Goals / Non-Goals

**Goals:**

- A `Pricing` value type and `PricingStore` in Core, persisting a hand-editable `pricing.json` beside the other two files, with graceful defaults — the `LayoutStore`/`PreferencesStore` philosophy, mirrored.
- Cost as an `Aggregation` entry point over raw `[TranscriptEvent]` that dedups internally, returning a dollar total, a per-model breakdown, and the unpriced model ids.
- Per-session cost.
- A cost KPI card and a per-session cost column, both gated by `showCost`.
- Honesty: unpriced models surfaced (returned set + logged notice), never silently $0.

**Non-Goals:**

- A `Metric.cost` or any path that sums cost through the token machinery.
- Breakdown expand-to-modal (phase 4), light themes, any billing/invoice framing beyond "estimate".
- Dynamic span rebalancing when a cost card is hidden.

## Decisions

### `Pricing`/`PricingStore` in Core, keyed by model family

`ModelRate` holds four `Double` rates (input, output, cacheWrite, cacheRead) in **US dollars per 1,000,000 tokens**. `Pricing` wraps `[String: ModelRate]` keyed by a **model family** — `opus`, `sonnet`, `haiku`, `fable` — plus `Pricing.family(of:)` which normalises a transcript model id (`claude-sonnet-4-6`, `claude-opus-4-1-…`, `claude-haiku-4-5-20251001`) to its family by taking the token after the `claude-` prefix. A model id that does not start with `claude-` (e.g. `gpt-5.5`, `<synthetic>`) has no family and is unpriced.

`PricingStore` mirrors `LayoutStore`/`PreferencesStore`: a public `fileURL`, a non-throwing `load()` (missing → seed defaults; corrupt → log and return defaults), a throwing pretty-printed `save`, and a `defaultURL` at `Application Support/ClaudeStats/pricing.json`.

*Why family, not full id?* The file stays short and legible, and a new dated snapshot of a known family is priced automatically without an edit. A user who wants a per-id override edits the file — they own it.

### Bundled default rates

From Anthropic's currently published per-Mtok list prices. Cache-write uses the 5-minute-TTL multiplier (1.25× input); cache-read uses ~0.1× input:

| family | input | output | cacheWrite | cacheRead |
|---|---|---|---|---|
| opus   | 5.00  | 25.00  | 6.25  | 0.50 |
| sonnet | 3.00  | 15.00  | 3.75  | 0.30 |
| haiku  | 1.00  | 5.00   | 1.25  | 0.10 |
| fable  | 10.00 | 50.00  | 12.50 | 1.00 |

These are the source of truth for the cross-check hand-computation. The whole point of `pricing.json` is that the user owns and corrects them.

### Cost is a derived Aggregation entry point, not a Metric

`Aggregation.cost(over:pricing:timeframe:now:calendar:)` filters by timeframe, runs `Counting.messages`, and for each message multiplies its `TokenUsage` by the rate for its model, summing into a `CostEstimate { total: Double, perModel: [String: Double], unpricedModels: Set<String> }`. A message whose model has no rate contributes nothing to the total and adds its id to `unpricedModels`. There is deliberately no `Metric.cost`: the token metrics enumerate token *kinds*, and cost is a cross-kind, per-model dollar figure — modelling it as a metric would let a caller feed it to `total`/`timeSeries`/`breakdown` and get a per-line-summed, model-erased number. Keeping it a separate entry point that dedups internally matches the existing invariant that a caller cannot apply the wrong counting rule.

### Per-session cost via an optional `pricing` on `sessions`

`Aggregation.sessions` gains `pricing: Pricing? = nil`. When supplied, the accumulator sums each message's cost (per its own model) into the session's `estimatedCost: Double?`; when nil, `estimatedCost` is nil. Cost is per-message-model, so it is accumulated during the single pass, not derived from the session's summed `TokenUsage` (which has lost the per-model split). Unpriced messages contribute nothing; the global `unpricedModels` from `Aggregation.cost` carries the honesty signal.

### `BlockType.cost`, not a bigNumber metric

Cost gets its own block type. It carries only a `timeframe` (and span). The card reuses `BigNumberBlockView`'s KPI chrome but formats the number as currency in `theme.accent` with the subtitle "estimate · not a bill". Making it a block type — not a `bigNumber` with a magic metric — keeps cost out of `Metric` entirely and lets `showCost` gate it by type.

### showCost gating and the existing-layout case

When `showCost` is false the dashboard filters out `.cost` blocks and the session list hides its cost column; when true they show. `showCost` **gates visibility of cost blocks already present; it never injects a cost block into a layout that lacks one.** The curated `Layout.default` includes the cost card (fresh users see it); a phase-1/phase-2 `layout.json` with no cost block shows no cost card even with `showCost` on — the user adds one from the Add-block menu (`.cost` is in the catalog). Hiding the third of four span-3 KPI cards leaves a **trailing gap** in that row — no dynamic span rebalancing. This is the "(a) trailing gap" + "(b) default-only" combination from the phase-3 spec, chosen because it is honest (we never silently reshuffle a hand-built layout) and simple (no packing logic).

## Risks / Trade-offs

- **Estimate, not a bill.** Cache-write TTL, intro pricing, and per-id differences make the number approximate. Mitigated by the explicit "estimate · not a bill" copy, the settings explanation, and the user-owned `pricing.json`.
- **A hidden cost card leaves a visible gap.** Accepted over span-rebalancing, which would silently reshape a hand-built KPI row.
- **Dump uses `Pricing.default`, not the on-disk file** — so the cross-check is reproducible and independent of a user's edits.
