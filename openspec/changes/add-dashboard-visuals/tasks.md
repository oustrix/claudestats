## 1. Core: span field (TDD)

- [x] 1.1 Write failing `ClaudeStatsCoreTests` cases: a spanless block JSON decodes with `span == 12`; an explicit-span layout round-trips its spans; the default layout's block types/metrics/spans match the mockup arrangement
- [x] 1.2 Add `span: Int` to `BlockConfig` with a decode default of 12 (`decodeIfPresent ?? 12`), always encoded; keep the initializer's `span` parameter defaulting to 12
- [x] 1.3 Re-seed `Layout.default`: three `bigNumber` (inputOutput, requests, cacheRead) span 4; `timeSeries` span 12; three `breakdown` (model, project, tool) span 4; `heatmap` span 12; `sessionList` span 12
- [x] 1.4 Update the existing default-layout Core tests that no longer hold (e.g. the "covers every type except heatmap" test) to the new arrangement
- [x] 1.5 Promote `Timeframe.days` to `public` so the app can compose a preceding window
- [x] 1.6 Confirm the Core suite is green

## 2. App: theme system

- [x] 2.1 Add a `Theme` struct of semantic colour roles plus a hex/rgba `Color` initializer, and the two dark palettes `.slate` and `.claude` copied exactly from the mockup values
- [x] 2.2 Add a `theme` `EnvironmentKey` defaulting to `.slate`, and a `Theme.default` constant (the single seam phase 2's settings will drive); inject it in `DashboardView`
- [x] 2.3 Paint the window/content background `theme.back` and the toolbar region `theme.tb`; keep native traffic lights (no Settings gear in phase 1)
- [x] 2.4 Restyle `BlockCard` to `theme.card` with a 1px `theme.cardB` border, ~12px radius; card title/subtitle use `theme.txt`/`theme.sub`
- [x] 2.5 Repoint block views off `.tint`/`.secondary`/`.quaternary` onto theme roles: `TimeSeriesBlockView` bar → `theme.bar`, axis/grid → `theme.grid`/`theme.mut`; `BreakdownBlockView` bar → `theme.accent`, track → `theme.track`; `HeatmapBlockView` cells → `theme.heat` ramp, empty → `theme.pill`; `SessionListBlockView` text roles; `StateViews`/`LayoutNotices` surfaces

## 3. App: 12-column grid (TDD)

- [x] 3.1 Write failing `ClaudeStatsAppLibTests` for a pure `pack(spans:columns:) -> [[Int]]`: greedy packing, overflow to new row, order preserved, an over-12 span on its own row
- [x] 3.2 Implement the pure packing function and clamp spans to 1–12
- [x] 3.3 Replace the single-column `LazyVStack` in `DashboardView` with a grid that maps each packed row to an `HStack` whose children are sized `span`/12 of the row width; notices and empty state still render above
- [x] 3.4 Confirm the app suite is green

## 4. App: KPI stat card (TDD)

- [x] 4.1 Write failing `ClaudeStatsAppLibTests` for the delta helper: bounded window with prior activity yields a signed percentage; previous == 0 yields nil; `allTime` yields nil
- [x] 4.2 Implement the delta as an app-layer helper composing `Aggregation.total` twice (current window; same timeframe with `now` shifted back by `timeframe.days`)
- [x] 4.3 Restyle `BigNumberBlockView` to the KPI card: ~40px tabular number, a small timeframe pill, and a "▲ N% vs prev." delta line; positive uses `theme.pos`, negative distinct, absent delta hidden
- [x] 4.4 Confirm the app suite is green

## 5. Verification

- [x] 5.1 `make build` clean and `make test` green (both suites)
- [x] 5.2 Run `make dump` and diff every aggregate against the pre-change baseline — all identical to the unit (phase 1 changes no counts)
- [x] 5.3 Launch the app (`make run`) briefly and confirm it does not crash; check the log for errors
- [x] 5.4 `openspec validate --strict add-dashboard-visuals`
- [x] 5.5 Commit in logical steps with conventional one-line messages; leave the branch for review (do not merge)
