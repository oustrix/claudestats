## Why

The dashboard works but looks like an unstyled `LazyVStack` of grey cards stacked one per row. A brainstormed-and-approved redesign targets a Claude-Design mockup: a dark, 12-column dashboard whose surfaces are painted from a coherent theme, whose blocks pack several to a row, and whose headline figures read as KPI cards with a period-over-period delta. This is phase 1 of a four-phase redesign — the visual system — and it changes no counted number. (Cost, a settings/preferences window, a theme picker, and breakdown modals arrive in later phases.)

## What Changes

- Add an app-layer `Theme` type holding semantic colour roles, with two dark palettes copied exactly from the mockup: `slate` (the default) and `claude`. Expose the current theme through the SwiftUI `Environment` so every block reads `theme.card` / `theme.accent` / `theme.txt` rather than the system `.tint`. Both palettes are dark; the app paints all surfaces itself and does not follow the system light/dark appearance. There is **no** theme-picker UI in this phase — the selection is a single named constant (`slate`) that phase 2's settings window will drive.
- Restyle the window and every block card to the theme: content background `theme.back`, cards `theme.card` with a 1px `theme.cardB` border and a ~12px radius, the toolbar/titlebar area tinted `theme.tb`. Native traffic-light dots are kept (no fake ones drawn). The existing scan summary, Add-block menu, and Refresh button stay in the toolbar.
- Add a `span` field (Int, 1–12) to `BlockConfig` in Core. Migration-safe: a `layout.json` written before spans decodes with `span = 12` (full width, today's behaviour). Replace the single-column `LazyVStack` with a flow layout that greedily packs blocks into rows up to 12 columns, each block `span/12` of the row width. The row-packing is a pure function, unit-tested.
- Restyle `BigNumberBlockView` as a KPI card: a large tabular number, a small timeframe pill, and a delta line ("▲ 18% vs prev.") comparing the current timeframe total to the immediately preceding equal-length window. The delta is composed in the app from two `Aggregation.total` calls (current window, and the same timeframe with `now` shifted back by the window length); zero/absent previous windows are handled without a divide-by-zero or a misleading arrow.
- Update the seeded default layout to the mockup arrangement: three KPI cards (`inputOutput`, `requests`, `cacheRead`) at span 4 each; a `timeSeries` at span 12; three `breakdown` blocks (`model`, `project`, `tool`) at span 4 each; a `heatmap` at span 12; a `sessionList` at span 12.

## Capabilities

### New Capabilities
<!-- None. The visual system restyles existing behaviour; it introduces no new user-facing capability. -->

### Modified Capabilities
- `dashboard-blocks`: `BlockConfig` gains a `span` (1–12) with a migration-safe default of 12; the dashboard lays blocks out in a 12-column grid packed greedily into rows rather than one block per row; the default seeded layout changes to the multi-column mockup arrangement; the big-number block additionally shows a period-over-period delta against the preceding equal-length window.

## Impact

- **Core (`ClaudeStatsCore`)**: `BlockConfig.span` (Codable, defaulting to 12 on decode); `Layout.default` re-seeded with spans; `Timeframe`'s day-count exposed so the app can compose the preceding window. No aggregation logic and no counting rule changes — every counted number is identical.
- **App (`ClaudeStatsAppLib`)**: new `Theme` type + `Environment` key; a pure row-packing helper and a grid container replacing the `LazyVStack`; restyled `DashboardView` chrome, `BlockCard`, and `BigNumberBlockView`; all block views read theme roles instead of `.tint`.
- **App entry (`ClaudeStatsApp`)**: window background painted from the theme.
- **Tests**: Core tests for `span` decode (old JSON → 12) and round-trip, and for the default layout's types/metrics/spans; app tests for the row-packing function and the KPI delta.
- No new dependencies. Older builds already skip unknown fields, and this build tolerates a spanless file, so the layout format stays backward- and forward-compatible.
