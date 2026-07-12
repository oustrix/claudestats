## Context

The dashboard renders an ordered list of blocks from a closed catalog (`bigNumber`, `timeSeries`, `breakdown`, `sessionList`). Daily totals already exist: `Aggregation.timeSeries(.day)` returns one dense `DataPoint` per local calendar day, zero-filled across gaps, and those daily totals reconcile to the grand total. A heatmap needs the same daily (or weekly) totals, laid out as a calendar grid and coloured by intensity instead of drawn as bars.

Constraints carried from the project: the core imports only `Foundation`; every aggregate is a pure function of raw `[TranscriptEvent]` and dedups internally; timeframes are whole **local** calendar days with `now` and `calendar` passed in; nothing lies silently. The block catalog is closed on purpose — a `heatmap` is a new case, not a query builder.

## Goals / Non-Goals

**Goals:**
- A `heatmap` block that reads the rhythm of usage at a glance for any metric.
- Day and week granularity, chosen per block via the existing `bucket` parameter.
- Colour that stays legible when cache-read outliers dominate the distribution.
- Exact values reachable on hover.

**Non-Goals:**
- A configurable time window. The heatmap is fixed at the last 52 weeks (GitHub has no window control, and an arbitrary window is mostly a way to make the grid ugly).
- Weekly bars in the time-series block. `Bucket.week` exists for the heatmap; the time-series editor keeps offering only `day`/`hour`.
- Per-cell drill-down, selection, or a second dimension. One metric, one grid.

## Decisions

### A new `BlockType.heatmap`, reusing `metric` and `bucket`

The heatmap is a closed-catalog case like the others. It reuses `metric` (default `inputOutput`) and `bucket` (`day`/`week`). `timeframe` is present in `BlockConfig` but **ignored** by the heatmap; `dimension`/`limit` are unused. The card header shows a fixed-window label ("Last 52 weeks") for a heatmap rather than `timeframe.title`, because the timeframe does not apply.

*Alternative considered:* a bespoke config shape for the heatmap. Rejected — the flat, optional-parameter `BlockConfig` keeps `layout.json` legible and the decode path uniform; a new shape would fork both.

### `Bucket.week` joins `day`/`hour`; the editor gates buckets per block type

Adding `week` to the shared `Bucket` enum keeps one vocabulary for cell granularity. The block editor stops offering `Bucket.allCases` blindly and instead offers each block type its supported subset: `timeSeries` → `day`/`hour`, `heatmap` → `day`/`week`. This keeps a `heatmap` with `.hour` (or a `timeSeries` with `.week`) out of the UI.

The data model can still *express* a hand-edited `heatmap` with `.hour`. Rather than treat that as unreadable, `Aggregation.heatmap` **coerces** any non-`week` bucket to `day` — the safe, non-lying resolution, consistent with how `resolvedBucket` already defaults an absent value.

*Alternative considered:* a separate `HeatmapBucket` enum. Rejected — it duplicates `day` and forces a second picker abstraction for no gain.

### Fixed 52-week window, aligned to the local week

The heatmap ignores `timeframe` and always covers the last 52 weeks. The window's lower bound is the start of the week (per `calendar.firstWeekday`) 51 weeks before the week containing `now`, so the grid is a clean rectangle of 52 week-columns. In `day` mode the grid is 7 rows (weekdays) × 52 columns; in `week` mode each cell is one week's total.

`now` and `calendar` are passed in exactly as the other aggregates take them — no clock read inside the pure function.

### Quantile intensity levels (0 = empty, 1–4)

`Aggregation.heatmap` returns dense cells (one per bucket across the window, zero-filled) plus a `level` per cell. Level 0 is reserved for `value == 0`. The non-zero values are split into four bins by **quartile** of their own distribution; `thresholds` (the three cut points) are returned so the view can render a legend. Quartiles are used rather than fractions of the max because cache-read days produce extreme outliers that would otherwise push almost every real day into the lowest bin.

*Alternative considered:* continuous gradient, and fixed absolute thresholds. Continuous is hard to read and outlier-sensitive; absolute thresholds are not comparable across metrics (a `requests` day and a `cacheRead` day live on different scales).

### Reconciliation invariant

The sum of a heatmap's cell values over its window MUST equal `Aggregation.total` for the same metric over the same explicit day range. This is asserted in tests and surfaced by `make dump`, matching the existing "daily totals reconcile with the grand total" guarantee.

### View: a hand-drawn grid, not Swift Charts

`HeatmapBlockView` draws a grid of `RoundedRectangle`s coloured by `.tint` opacity ramped by level (1–4 → 0.25/0.5/0.75/1.0; level 0 → `.quaternary`). Month labels run across the top, weekday labels down the left, and a "Less ▢▢▢▢ More" legend sits below. Each cell carries a `.help("Jul 12: 2,041,714 tokens")` tooltip (exact value via `.grouped`). Unlike `TimeSeriesBlockView`, no `.drawingGroup()` — a static grid of rectangles is cheap to redraw, and rasterising would kill the per-cell tooltip.

## Risks / Trade-offs

- **Quartile bins collapse when few distinct non-zero values exist** (e.g. three active days) → bin by the distinct sorted values, so all four levels are never forced onto three data points; a degenerate distribution simply uses fewer levels. Covered by a spec scenario.
- **A `heatmap` with a hand-edited `.hour` bucket** → coerced to `day` in aggregation, not skipped as unreadable; the editor never produces it.
- **`week` mode grid layout** → laid out as 13-week rows (a quarter per row), four rows per year, one cell per week. Confirmed during design.
- **52 weeks of empty cells for a brand-new user** → the grid still renders (all level 0); the fixed window is honest about "no activity yet" rather than collapsing to a stub.
