## 1. Model: expand state (TDD)

- [x] 1.1 Write failing `DashboardModelTests`: `expandBreakdown(block)` sets `expandedBreakdown` to that block; a second call replaces it (one at a time); `collapseBreakdown()` clears it; neither writes `layout.json` (blocks on disk unchanged, no persistence error)
- [x] 1.2 Add `private(set) var expandedBreakdown: BlockConfig?` plus `expandBreakdown(_:)` / `collapseBreakdown()` to `DashboardModel`, outside the `persist()` path
- [x] 1.3 Confirm the app suite is green

## 2. Detail modal view (TDD)

- [x] 2.1 Write failing `BlockViewTests`/new tests for `BreakdownDetailView`: with more distinct entries than the card's limit, the modal renders a row per entry (a label absent from the data is not shown); the dimension title and the count-and-scope pill text appear; an empty timeframe shows the empty-state copy
- [x] 2.2 Add `BreakdownDetailView` computing rows via `Aggregation.breakdown(..., limit: .max, ...)`, scaled to its own max; header with `block.title`, the count-and-scope pill, and a themed ✕ close; a scrollable ranked list (rank, label, `theme.bar`-on-`theme.track` bar, `theme.mut` value)
- [x] 2.3 Add the reusable `BreakdownExpandButton` (maximize glyph, `theme.faint` → `theme.sub` on hover)
- [x] 2.4 Confirm the app suite is green

## 3. Wire the card and present the modal

- [x] 3.1 Add the expand button to `BlockCard`'s header, shown only for `.breakdown`, calling `model.expandBreakdown(block)`
- [x] 3.2 Present `BreakdownDetailView` from `DashboardView` as a `.sheet(item:)` bound to `model.expandedBreakdown`, dismissing via `collapseBreakdown()`, with the theme injected
- [x] 3.3 Confirm the app suite is green

## 4. Verification

- [x] 4.1 `make build` clean and `make test` green (both suites); note the before/after test count
- [x] 4.2 Counts unchanged (pure UI): rely on the green suite; do not diff live dumps across time
- [x] 4.3 `openspec validate add-breakdown-detail --strict`
- [x] 4.4 Commit in logical steps with conventional one-line messages; leave the branch for review (do not merge or push)
