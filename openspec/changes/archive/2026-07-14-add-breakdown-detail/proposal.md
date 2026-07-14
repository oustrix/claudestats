## Why

A breakdown card shows only its top-N rows (limit 8, sometimes 10), so on a real corpus the tail — the projects, models or tools past the cut — is invisible. This is phase 4, the last of the four-phase redesign: let a breakdown card expand into a themed detail modal that lists the *full* ranked breakdown, matching the mockup's maximize affordance. Pure UI — no counted number changes.

## What Changes

- Add an expand affordance (a maximize / diagonal-arrows glyph) to the header of each `breakdown` card, faint and hovering to a brighter tint, placed to the right of the title and timeframe.
- Add a themed detail modal, presented as a sheet over the dashboard exactly as the phase-2 settings sheet is (window fill `theme.win`, hairline `theme.bord`, a themed ✕ close, `.tint(theme.accent)`, pinned dark). Its header carries the dimension title ("By model" / "By project" / "By tool") and a count-and-scope pill ("N models · Last 30 days", "N tools · invocations"); its body is a scrollable list of ranked rows — a rank number, the truncating label, a proportional bar (`theme.bar` on `theme.track`, scaled to the modal's own largest row), and the formatted value.
- The card keeps drawing its existing top-N; the modal calls `Aggregation.breakdown` with an unbounded limit so it lists every row for that dimension, metric and timeframe.
- Track which breakdown is expanded as local, non-persisted UI state on `DashboardModel` (one modal at a time); opening/closing never touches `layout.json`.
- Respect the existing `showCost`/theme environment; no new preferences.

## Capabilities

### New Capabilities
<!-- None. Phase 4 adds a detail view over the existing breakdown block; it introduces no new capability, only extends how the breakdown block is presented. -->

### Modified Capabilities
- `dashboard-blocks`: the `breakdown` block gains an expand-to-modal detail view showing the full ranked list, over and above the card's top-N.

## Impact

- **App (`ClaudeStatsAppLib`)**: `DashboardModel` gains a non-persisted `expandedBreakdown` with `expandBreakdown`/`collapseBreakdown`; a new `BreakdownDetailView` (the modal) plus a reusable expand button; `DashboardView`/`BlockCard` add the expand button to a breakdown card's header and present the modal as a `.sheet(item:)`.
- **Core (`ClaudeStatsCore`)**: none. `Aggregation.breakdown` already returns all rows when the limit exceeds the row count (`.prefix(limit)`); the modal passes `Int.max`.
- No new dependencies, no persistence changes, no counted-number changes — every token figure is byte-identical.
