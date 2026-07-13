## 1. Restructure into library + thin executable (no behaviour change)

- [x] 1.1 Create `Sources/ClaudeStatsAppLib/` and move every file from `Sources/ClaudeStatsApp/` into it **except** `ClaudeStatsApp.swift` (`DashboardModel`, `DashboardView`, `BlockEditor`, `Formatting`, `StateViews`, `Blocks/*`)
- [x] 1.2 Make `DashboardView` (and its initializer) `public`; leave everything else `internal`
- [x] 1.3 In `ClaudeStatsApp.swift`, `import ClaudeStatsAppLib`; the executable now holds only the `@main` `App` struct
- [x] 1.4 In `Package.swift`: add the `ClaudeStatsAppLib` library target (depends on `ClaudeStatsCore`), point the `ClaudeStatsApp` executable target at it, apply the same three `swiftSettings` upcoming-feature flags to the new target
- [x] 1.5 Verify no behaviour change: `make build` clean, `make run` launches, `make app` assembles a working bundle (Makefile unchanged — executable target name preserved)

## 2. DashboardModel behaviour (TDD, zero-dep, `@MainActor @Test`)

- [x] 2.1 Add the `ClaudeStatsAppLibTests` target to `Package.swift` (depends on `ClaudeStatsAppLib`); add a local stub `EventSource` helper for seeding a `StatsStore`
- [x] 2.2 Write failing tests for `init`: a valid layout file loads its blocks; a malformed file yields `wasReset == true` + defaults; `skipped`/`persistenceError` are propagated from `LayoutStore.Loaded`
- [x] 2.3 Write failing tests for editing: `add(type)` for each `BlockType` appends `newBlock(of:)` and a re-read from disk confirms persistence; `remove` / `move` mutate and persist; `update` replaces the same-id block and persists; `update` with an unknown id is a no-op
- [x] 2.4 Write failing tests for `dismissNotices` (clears `skipped`/`wasReset`/`persistenceError`) and for persistence failure: a `LayoutStore` at an unwritable path (under a regular file) sets `persistenceError` on mutation; the success path leaves it `nil`
- [x] 2.5 Write failing tests for the projection: `scan`/`events` derive from `stats.state` (`.loaded` → events; otherwise `nil`/empty)
- [x] 2.6 Watch them fail for the right reason, then confirm green (the logic already exists; this is coverage, so most pass once the target compiles — any red is a real bug to fix)

## 3. Editor invariants as pure tests (zero-dep)

- [x] 3.1 In `ClaudeStatsCoreTests`: cover `BlockType.supportedBuckets` (correct subset per type, empty where none) and `BlockConfig.resolvedMetric`/`resolvedBucket`/`resolvedDimension`/`resolvedLimit` defaults. (`fixedWindowLabel` lives in `ClaudeStatsAppLib`/`Formatting.swift`, not Core — its test is folded into 3.2.)
- [x] 3.2 In `ClaudeStatsAppLibTests`: cover `newBlock(of:)` for each `BlockType` — the used parameters are set to the documented defaults and the unused ones are `nil`; plus `fixedWindowLabel` (set for `heatmap`, `nil` elsewhere), tested here because it is app-layer

## 4. View tests via ViewInspector

- [x] 4.1 **Spike gate**: add ViewInspector to `ClaudeStatsAppLibTests` only, pin an exact version that builds; write one trivial synchronous `try view.inspect()` on `BlockEditor`; confirm it builds and passes under Swift 6.2 / macOS 26 / swift-testing. If it fails, stop §4, keep §1–3, and report. (Pinned `exact: "0.10.3"`; spike green.)
- [x] 4.2 `BlockEditor` field presence per `BlockType`: assert which of Metric / Timeframe / Bucket / Group-by / Rows render — directly proving "a `sessionList` cannot be expressed with a `bucket`"
- [x] 4.3 `BlockEditor`: Metric picker is `.disabled` when `dimension == .tool` (only if ViewInspector exposes the modifier; otherwise skip with a note). ViewInspector exposes `.isDisabled()`; both the disabled (`.tool`) and enabled (`.model`) cases are asserted.
- [x] 4.4 Block views render expected content for given data: `BigNumberBlockView` shows the formatted value; `BreakdownBlockView` shows the expected row count/labels; `SessionListBlockView` shows the sessions; empty/no-data states asserted on the plain `Text` the block views actually render (`ContentUnavailableView` is a dashboard-level state, asserted in 4.6). All fixtures use `.allTime`, so the result does not depend on `.now`.
- [x] 4.5 `TimeSeriesBlockView`: assert it renders (title/empty state), not its bars — `Chart` internals are opaque to ViewInspector
- [x] 4.6 (Optional, low priority) `DashboardView`: add a model-injection initializer if needed and assert the empty/failure state screens (added `init(model:)`; assert `LoadFailedView`, `NoTranscriptsView`, and the empty-dashboard `ContentUnavailableView`)

## 5. Finalize

- [x] 5.1 `make test` green (both suites, 151 tests), `make build` clean, `make app` assembles a working bundle (`make run` launches a GUI window that cannot be observed headless; build + bundle are the verifiable evidence)
- [x] 5.2 Confirm ViewInspector appears only under the test target in `Package.swift` — the shipped executable links nothing new (release binary: 0 ViewInspector symbols, only `/usr/lib` + `/System/Library` linked)
- [x] 5.3 `openspec validate --strict` for this change (passes, 0 issues); archive on completion — run `/opsx:archive` (left to the user, alongside the commit)
