## Context

The dashboard is functionally complete but visually unstyled: a single-column `LazyVStack` of `.quaternary`-tinted cards, one block per row, coloured from the system `.tint`. A brainstormed-and-approved redesign targets a Claude-Design mockup — a dark, 12-column dashboard with two colour themes, KPI cards, and multi-column rows. The redesign is scoped into four phases; this is **phase 1, the visual system**, and it is a hard invariant that phase 1 changes **no counted number**. The counting invariants in `CLAUDE.md` (dedup in `Counting.messages`, `usage` internal, aggregation-owns-windowing) stay untouched.

The Core library may import only `Foundation` (+ `Observation`); it must never see SwiftUI. So the theme, the grid layout, and the KPI delta arithmetic all live in `ClaudeStatsAppLib`. The only Core changes are a new stored field (`span`) and exposing an existing day-count so the app can compose a preceding window — neither is aggregation.

## Goals / Non-Goals

**Goals:**

- A single `Theme` value type holding every semantic colour role, with two dark palettes (`slate`, `claude`) copied exactly from the mockup hex values, reachable from any view via the SwiftUI `Environment`.
- A 12-column grid: blocks carry a `span` (1–12) and pack greedily into rows. The packing is a pure, unit-tested function so the layout cannot silently misbehave.
- Backward/forward-compatible layout: a `layout.json` without `span` still loads (defaults to full width); a newer file round-trips.
- A KPI stat card with a period-over-period delta, computed by composing existing aggregation — no new aggregation entry point unless composition is genuinely impossible.

**Non-Goals (explicitly deferred to later phases):**

- Dollar-cost estimation anywhere (phase 3).
- A settings/preferences window, refresh-interval or transcripts-folder UI, and the **theme-picker UI** (phase 2). Phase 1 wires the environment with `slate` as a fixed default and leaves one obvious seam for phase 2 to drive it.
- Breakdown expand-to-modal (phase 4).
- Light themes. Both palettes are dark; the app does not follow the system appearance.

## Decisions

### Theme as an app-layer value type in the Environment

`Theme` is a plain `struct` of `Color` roles (`back`, `win`, `tb`, `bord`, `card`, `cardB`, `txt`, `sub`, `mut`, `faint`, `pill`, `track`, `accent`, `bar`, `pos`, `onAccent`, `grid`, an ordered `heat: [Color]`, and `overlay`). It defines two static palettes, `.slate` and `.claude`, built from the exact mockup hex/rgba values via a small hex initializer. A custom `EnvironmentKey` defaults to `.slate`; `DashboardView` injects it with `.environment(\.theme, Theme.default)`, and `Theme.default` is the single named constant phase 2 will replace with a preference read. Views pull it with `@Environment(\.theme) private var theme`.

*Why not the system `.tint` / asset catalogs?* Asset catalogs need Xcode's binary editor, which this text-only project forbids. `.tint` gives one accent, not the dozen surface roles the mockup needs, and it follows system light/dark, which these fixed-dark palettes must not. A code-defined value type is testable, versionable as text, and dark-only by construction.

### `span` on `BlockConfig`, decode-defaulted to 12

`span: Int` is added to `BlockConfig`. Because `Codable` synthesises a failing decode for a missing non-optional field, the decoder is customised (or `span` is decoded with `decodeIfPresent ?? 12`) so a spanless file yields `span = 12` — full width, i.e. exactly today's one-per-row behaviour. `span` is always **encoded**, so new files are explicit. The value is clamped/validated to 1–12 at the grid layer; an out-of-range hand-edited span is coerced rather than crashing. This keeps `layout.json` a legible, hand-editable document.

*Why 12 as the default, not 4?* The migration contract is "an old file renders as it did before." Old files were one block per row = full width = span 12. Defaulting to 4 would silently re-flow a hand-built dashboard.

### Greedy row-packing as a pure function

Layout is a pure function `pack(spans: [Int], columns: Int = 12) -> [[Int]]` returning rows of block indices. It walks blocks in order, adding each to the current row while the running span-sum stays ≤ 12, else starting a new row. A single block wider than 12 (only possible via a bad hand-edit not caught upstream) occupies its own row. Order is preserved — the user's block order is still authoritative. The `DashboardView` maps each returned row to an `HStack` whose children are sized `span/12` of the available width (via a `GeometryReader` or layout proportional widths). This function is unit-tested in `ClaudeStatsAppLibTests` independent of any view.

*Why greedy, not a bin-packer?* The user orders blocks deliberately; reordering them to fill gaps would fight that intent. Greedy preserves order and is trivially predictable.

### KPI delta by composing `Aggregation.total`, not new Core aggregation

The delta compares the current window's total to the immediately preceding equal-length window. `Aggregation.total` already takes `now`; the preceding window is the same call with `now` shifted back by the window's day-count. The only thing the app lacks is that day-count, which already exists as `Timeframe.days` (internal). It is promoted to `public` so the app can compute `prevNow = now - days` and call `total` twice. `.allTime` has no bounded window (`days == nil`), so it shows no delta. The percentage is `(current - previous) / previous`; when `previous == 0` (or there is no previous window) no arrow and no percentage are shown — a delta "from zero" is infinite and meaningless. A positive delta is painted `theme.pos`.

*Why not a new `Aggregation.delta`?* The spec says compose if you can; you can. Exposing an existing, well-defined day-count is metadata, not a new counting rule, and keeps the counting surface unchanged.

### Chrome from the theme, native traffic lights kept

The window/content background is `theme.back`; the toolbar/titlebar region is tinted `theme.tb`. Cards are `theme.card` filled with a 1px `theme.cardB` stroke at ~12px radius. Traffic-light dots stay native — the app draws none. A Settings gear placeholder is **omitted** in phase 1 (the toolbar keeps only the scan summary, Add-block menu, and Refresh); phase 2 adds the gear when it has a window to open. This is noted so phase 2 knows the toolbar is the insertion point.

## Risks / Trade-offs

- **[A missing `span` decodes wrong and re-flows old dashboards]** → Explicit `decodeIfPresent ?? 12` plus a Core test that decodes spanless JSON and asserts `span == 12`, and a round-trip test for new JSON.
- **[A hand-edited span outside 1–12 breaks layout math]** → The grid clamps to 1–12; a block wider than a row gets its own row. No crash, no divide error.
- **[A visual restyle accidentally perturbs a counted number]** → Phase 1 touches no aggregation or counting code. Verified by running `make dump` before and after and diffing every total; they must be identical to the unit.
- **[ViewInspector cannot see `Environment`-injected theme colours]** → View tests assert structure/among-text content, not colour values; the theme is exercised by the app building and launching, and by the pure packing/delta tests. Colour correctness is a human visual check via `make run`.
- **[The KPI delta drifts with the wall clock in tests]** → Delta tests use `.allTime` (no delta) for the null case and inject a fixed `now`/events for the numeric case, mirroring the existing suite's determinism convention.
