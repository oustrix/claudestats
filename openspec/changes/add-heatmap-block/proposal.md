## Why

The dashboard shows totals, trends and rankings, but nothing conveys *rhythm* — which days are heavy, which are idle, how usage clusters across weeks. A GitHub-style calendar heatmap reads that pattern at a glance, and the daily totals it needs are already computed.

## What Changes

- Add a `heatmap` block to the closed catalog: a calendar grid whose cells are coloured by activity intensity for a chosen metric.
- Add a `week` bucket alongside `day` and `hour`. The heatmap offers `day`/`week`; the time-series block keeps `day`/`hour`. The block editor offers each block type only the buckets it supports.
- The heatmap draws a **fixed** window (the last 52 weeks), ignoring `timeframe`, like GitHub — one fewer way to produce an unreadable grid.
- Cell colour is a discrete level (0 = empty, 1–4) assigned by **quantiles** of the window's non-zero values, so cache-read outliers do not flatten the scale.
- Each cell exposes an on-hover tooltip with its exact date and value.

## Capabilities

### New Capabilities
<!-- None. The heatmap extends existing capabilities rather than introducing a new one. -->

### Modified Capabilities
- `dashboard-blocks`: the closed catalog gains a `heatmap` block type (metric, bucket), and layout editing offers per-type bucket choices.
- `usage-aggregation`: adds weekly bucketing and a heatmap aggregation that assigns quantile intensity levels over a fixed 52-week window.

## Impact

- **Core (`ClaudeStatsCore`)**: `BlockType.heatmap`, `Bucket.week`, `Aggregation.heatmap` returning cells with quantile levels; `Layout` decode/encode already tolerant of the new type.
- **App (`ClaudeStatsApp`)**: new `HeatmapBlockView`, block-editor and card-header adjustments, presentation names/symbols.
- **Dump (`ClaudeStatsDump`)**: heatmap window totals join the cross-check output.
- No new dependencies; no breaking changes (older builds skip an unknown block type by existing behaviour).
