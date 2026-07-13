## Context

The project keeps all logic in `ClaudeStatsCore` and tests it there against injected seams (`EventSource`, real `LayoutStore` in temp dirs, injected `now`/`calendar`). `ClaudeStatsApp` is an `executableTarget` with a `@main` `App` struct. Its `DashboardModel` is `@MainActor @Observable` but imports no SwiftUI (only `ClaudeStatsCore`/`Foundation`/`Observation`) — it is plain logic that happens to live in the executable. That placement, plus the fact that a test target cannot cleanly `@testable import` an executable target, is the only reason the App layer is untested.

Two facts pin the restructuring:
- The Makefile builds and runs the executable **by target name** (`swift run ClaudeStatsApp`; `make app` copies `.build/release/ClaudeStatsApp`). Keeping the executable target named `ClaudeStatsApp` means the Makefile needs no changes.
- `ClaudeStatsApp.swift` is nothing but `@main` + a `WindowGroup { DashboardView() }`. Everything worth testing already lives in other files.

## Goals / Non-Goals

**Goals:**
- Close the App-layer coverage gap: `DashboardModel` behaviour, the `newBlock` factory, the editor's parameter rules, and the views' rendered output.
- Keep the shipped app dependency-free — any external dependency stays confined to the test target.
- Preserve behaviour exactly; the restructuring is mechanical.

**Non-Goals:**
- Moving `DashboardModel` into `ClaudeStatsCore`. It is app-layer state; the library split gives it a testable home without blurring the "core is pure" boundary.
- Snapshot/pixel testing. ViewInspector asserts view *structure* (which controls render, what text shows), not pixels — no reference images to manage.
- Testing the 30-second refresh loop or `.task` lifecycle. Those are SwiftUI-runtime concerns ViewInspector does not drive; static inspection is the scope.

## Decisions

### Split into `ClaudeStatsAppLib` (library) + `ClaudeStatsApp` (thin executable)

All of `Sources/ClaudeStatsApp/` moves into a new `ClaudeStatsAppLib` library target **except** `ClaudeStatsApp.swift`. The executable keeps only the `@main` `App` struct and `import ClaudeStatsAppLib`. `DashboardView` becomes `public` (the one symbol the executable references); everything else stays `internal` and is reached by tests via `@testable import ClaudeStatsAppLib`.

*Alternative considered:* move `DashboardModel` into `ClaudeStatsCore` and add a separate App library only for views. Rejected — it splits App tests across two targets and puts a view-model in the pure-core library for no gain over a single App library.

*Alternative considered:* a test target that `@testable import`s the executable target directly. Rejected — `@main` in a test bundle is fragile and ViewInspector against an executable target is untrodden; the library split is the standard, boring path.

### ViewInspector is a test-only dependency, gated by a spike

ViewInspector is added only to `ClaudeStatsAppLibTests`. Because it is the project's first dependency and its compatibility with Swift 6.2 / macOS 26 / swift-testing is unverified, the first implementation step is a **spike**: add the package, write one trivial `try view.inspect()` on `BlockEditor`, and confirm it builds and passes. Only synchronous inspection is used — the XCTest-oriented `ViewHosting`/`on(...)` callback APIs are avoided so the tests stay in swift-testing. If the spike fails, the view-testing section is dropped and the model/editor coverage (which needs no dependency) still lands; the outcome is reported rather than worked around.

### `DashboardModel` tested against real disk, no persistence protocol

Model tests use a real `LayoutStore` pointed at a temp directory and a local stub `EventSource` to seed the `StatsStore` — matching how `StatsStoreTests`/`LayoutStoreTests` already work. A persistence failure is forced by pointing the `LayoutStore` at a path under an existing regular file, so `createDirectory` throws. No `LayoutPersisting` protocol is introduced — it would be a Core change to buy one test, and the concrete store on real disk is consistent with the existing suite.

*Accepted limitation:* the failure→recovery transition (`persistenceError` set, then cleared by a later successful save) is not covered, because a concrete `LayoutStore` cannot be flipped from failing to succeeding mid-test without `chmod` gymnastics. Failure-sets-error and success-leaves-nil are each covered directly.

### Editor invariants tested as data, not as pixels

The rule "a block type offers only the parameters it can use" lives as pure data in `ClaudeStatsCore` (`BlockType.supportedBuckets`, `fixedWindowLabel`, `BlockConfig.resolvedX`) and as the `newBlock(of:)` factory in the App library. These are tested directly — Core rules in `ClaudeStatsCoreTests`, the factory in the App suite. The ViewInspector field-presence tests then confirm `BlockEditor` actually reads those rules, closing the loop without duplicating the logic.

### Deterministic view data

Block views read `now` inline (`.now`) when aggregating. View tests choose fixtures and timeframes whose aggregation window does not depend on the current instant (e.g. events all within any plausible window, or assertions on row **count**/labels rather than time-bucketed values), so a test's result does not drift with wall-clock time. If a specific assertion genuinely needs a fixed `now`, the block view gains a `now` parameter defaulting to `.now` — a seam mirroring the core aggregates.

## Risks / Trade-offs

- **ViewInspector incompatibility** with Swift 6.2 / macOS 26 / swift-testing → the spike gate catches it before any breadth is built; the fallback (model + editor coverage only) is already dependency-free and valuable.
- **Opaque views**: `Chart` internals and some modifiers (`.disabled`) are not reliably inspectable → those assertions are marked "if reachable"; `TimeSeriesBlockView` is verified by presence/empty-state, not by its bars. The plan does not depend on them.
- **First external dependency**: a supply-chain and build-time cost the project has so far avoided → mitigated by confining it to the test target (never shipped) and pinning an exact version at the spike.
- **Restructuring risk**: moving files between targets could break the build or the `make app` bundle → verified by `make build`, `make run`, and `make app` after the split, before any test is written.
