## 1. Core vocabulary

- [x] 1.1 Add `case week` to `Bucket`; add its `component` (`.weekOfYear`) and `start(of:in:)` (start of the local week per `calendar.firstWeekday`)
- [x] 1.2 Add `case heatmap` to `BlockType`
- [x] 1.3 Seed a new heatmap block with `bucket: .day` and `metric: .inputOutput` via the resolved-parameter defaults; leave `Layout.default` unchanged (heatmap is addable, not default)

## 2. Weekly bucketing (TDD)

- [x] 2.1 Write failing tests: a message maps to the local week of its timestamp for a given `firstWeekday`; weekly totals reconcile to the metric total over the period
- [x] 2.2 Make `Aggregation.timeSeries` (and the shared bucket path) handle `.week`; watch tests pass

## 3. Heatmap aggregation (TDD)

- [x] 3.1 Define `HeatmapCell { date, value, level }` and `Heatmap { cells, bucket, thresholds, maxValue }` in the core
- [x] 3.2 Write failing tests: dense cells over the fixed 52-week window; zero-filled empty buckets = level 0; window fixed regardless of timeframe; `.hour` coerces to `.day`; window aligned to `firstWeekday`; cell sum reconciles to `Aggregation.total` over the same day range
- [x] 3.3 Write failing tests for quantile levels: outlier does not flatten the scale; fewer than four distinct non-zero values use fewer levels; `thresholds` exposed
- [x] 3.4 Implement `Aggregation.heatmap(_:over:bucket:now:calendar:)`; watch tests pass

## 4. Presentation names

- [x] 4.1 Add `BlockType.heatmap` title ("Heatmap") and symbol (`square.grid.3x3`)
- [x] 4.2 Add `Bucket.week` title ("By week")

## 5. Heatmap view

- [x] 5.1 Build `HeatmapBlockView`: grid of `RoundedRectangle`s, `.tint` opacity ramped by level (1–4 → 0.25/0.5/0.75/1.0, level 0 → `.quaternary`)
- [x] 5.2 Day mode: 7 weekday rows × 52 week columns; week mode: 13-week rows, one cell per week
- [x] 5.3 Month labels across the top, weekday labels down the left, "Less ▢▢▢▢ More" legend below (from `thresholds`)
- [x] 5.4 Per-cell `.help("<date>: <value> tokens")` tooltip using `.grouped`
- [x] 5.5 Dispatch `heatmap` in `BlockCard.body(for:)`

## 6. Editor & card header

- [x] 6.1 In `BlockEditor`, show Metric + Bucket for heatmap; hide Timeframe/dimension/limit
- [x] 6.2 Offer per-type bucket subsets: `day`/`hour` for `timeSeries`, `day`/`week` for `heatmap`
- [x] 6.3 In `BlockCard`, show the fixed-window label ("Last 52 weeks") for a heatmap instead of `timeframe.title`

## 7. Dump & cross-check

- [x] 7.1 Add heatmap window totals to `make dump` output
- [x] 7.2 Cross-check the heatmap window total against `ccusage` and an independent `jq` pass over a corpus snapshot; all counters agree to the unit

## 8. Finalize

- [x] 8.1 `make test` green; `make build` clean
- [x] 8.2 Update `dashboard-blocks`/`usage-aggregation` spec Purpose lines if touched; run `openspec validate --strict`
