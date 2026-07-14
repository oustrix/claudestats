## Context

Phases 1–3 are merged: the 12-column grid and themes (phase 1), the settings sheet with its themed controls (phase 2), and the cost estimate (phase 3). A `breakdown` card (`BreakdownBlockView`) draws a top-N ranked list — a label, a proportional bar, a value — where N is `block.resolvedLimit`. The card's header (title + timeframe) and chrome live in `BlockCard` inside `DashboardView`, not in `BreakdownBlockView` itself. The mockup gives each breakdown card a maximize glyph that opens a modal listing the *full* ranking. This phase is the last one, and is app-layer only.

## Goals / Non-Goals

**Goals:**
- Expand any of the three breakdown cards (model, project, tool) into one reusable themed modal that lists the full ranked breakdown for that card's dimension, metric and timeframe.
- Reuse the phase-2 settings-sheet presentation and theming so the modal is visually consistent (window `theme.win`, border `theme.bord`, radius, `.tint(theme.accent)`, `.preferredColorScheme(.dark)`, themed close).
- Keep the open/closed state as local, testable UI state — never persisted to `layout.json`.

**Non-Goals:**
- No Core changes (the aggregation already yields all rows for a large limit). No new metrics, no new preferences, no light themes, no persistence of modal state, no drag/reorder changes.

## Decisions

- **No Core change; unbounded limit via `Int.max`.** `Aggregation.breakdown` ends in `.prefix(limit)`, which returns every row when `limit` exceeds the row count. The modal passes `limit: .max`; the card keeps passing `block.resolvedLimit`. Alternative — adding a `limit: Int?` "unlimited" sentinel to the Core signature — was rejected: it changes a public Core API and its tests for a caller that `Int.max` already satisfies exactly.

- **State on `DashboardModel`, presented as `.sheet(item:)`.** Add `private(set) var expandedBreakdown: BlockConfig?` with `expandBreakdown(_:)` / `collapseBreakdown()`. `BlockConfig` is already `Identifiable`, so `.sheet(item:)` binds directly; setting the target replaces any prior one, giving "one modal at a time" for free. The state is not written through `persist()`, so it never reaches `layout.json` — mirroring how `editing`/`showingSettings` are transient view state. Tracking the whole `BlockConfig` (not just the dimension) is deliberate: two "By model" cards can differ in metric or timeframe, and the modal must reflect the card that was expanded.

- **Expand button in `BlockCard`'s header, gated on `.breakdown`.** The header is `BlockCard`'s, so the button lives there, to the left of the reorder/edit/trash controls, shown only when `block.type == .breakdown`. It is a small reusable `BreakdownExpandButton` (maximize glyph `arrow.up.left.and.arrow.down.right`), drawn `theme.faint` and hovering to `theme.sub`, calling `model.expandBreakdown(block)`.

- **`BreakdownDetailView` mirrors `SettingsView`'s chrome.** Same `.padding`, fixed width, `.background(theme.win)`, `.tint(theme.accent)`, `.environment(\.theme,)`, `.preferredColorScheme(.dark)`. Header: `block.title` ("By model") + a count-and-scope pill on `theme.pill`; a themed ✕ close calling `dismiss`. Body: a `ScrollView` of ranked rows. Each row: a rank number (`theme.faint`, monospaced, fixed width), the label (`theme.txt`, truncating middle), a proportional bar (`theme.bar` on `theme.track`, width = value / modal-max — so the top row is full width and bars are scaled to the modal's own largest row, not the card's), and the value (`theme.mut`, monospaced). The pill scope reads the timeframe title for model/project and "invocations" for tool (which ignores the metric and counts invocations), reusing `BreakdownDimension.title` and `Timeframe.title` from `Formatting.swift`.

## Risks / Trade-offs

- [`Int.max` as "all rows"] → `.prefix(Int.max)` is well-defined and cheap at corpus size; a Core test already covers `breakdown` returning fewer rows than the limit. Documented at the call site so the intent is legible.
- [Header button lives in `BlockCard`, not `BreakdownBlockView`] → The header has always been `BlockCard`'s; splitting it would be a larger refactor for no gain. The button is a reusable typed view and the behaviour is tested through the model, so the seam is still covered.
- [Modal state not persisted] → Intended: a transient view is not part of the saved dashboard. A relaunch opens to a closed modal, which is correct.
