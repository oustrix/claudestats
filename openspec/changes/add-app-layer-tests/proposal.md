## Why

The core library is tested to the unit, but the entire App layer has zero coverage. `DashboardModel` owns layout editing and persistence — `add`/`remove`/`move`/`update`, `persist()`, the `persistenceError` surfacing, `dismissNotices`, and the `scan`/`events` projection — and none of it is exercised. Neither is the `newBlock(of:)` factory, nor the rules the block editor relies on ("which parameters a block type offers"), nor any SwiftUI view. A regression that drops a user's layout edit, or an editor that starts offering a parameter a block type cannot use, would ship silently. The audit called this out as the one real gap in an otherwise well-tested codebase.

## What Changes

- Split the App into a **testable library** (`ClaudeStatsAppLib`) and a **thin `@main` executable** (`ClaudeStatsApp`), so a test target can import the app code. A test target cannot cleanly `@testable import` an executable target, so this split is the enabling move. The Makefile is unchanged — the executable target keeps its name and product.
- Add a `ClaudeStatsAppLibTests` target and the project's **first dependency, ViewInspector**, scoped to tests only. It is never linked into the shipped app.
- Cover `DashboardModel` behaviour (editing, persistence, error surfacing, `scan`/`events`) with zero-dependency `@MainActor` tests, in the style of the existing `StatsStoreTests`.
- Cover the editor invariants — `newBlock(of:)` defaults and the `BlockType` → supported-parameter rules (`supportedBuckets`, `fixedWindowLabel`, `resolvedMetric`/`resolvedBucket`/`resolvedDimension`/`resolvedLimit`) — as pure tests.
- Cover the SwiftUI views with ViewInspector — which fields the editor renders per block type, and what each block view displays for given data — **behind a spike gate** that confirms ViewInspector builds under Swift 6.2 / macOS 26 / swift-testing before the suite is expanded.

## Capabilities

### New Capabilities
- `project-integrity`: formalizes that the shipped application links no external dependencies; external dependencies are confined to test targets. This line is worth drawing precisely because this change adds the project's first external dependency (ViewInspector, test-only).

### Modified Capabilities
<!-- None. The behaviours under test are already specified (e.g. `dashboard-blocks` already says the editor offers each block type only the parameters it supports). The two seams added for testability — a `public` `DashboardView` and an injectable model — are not behavioural. -->

## Impact

- **App (`ClaudeStatsApp`)**: `Sources/ClaudeStatsApp/` is split. Everything but the `@main` entry point moves to a new `ClaudeStatsAppLib` library target (`DashboardModel`, all views, `Formatting`, `Blocks/*`); the executable keeps only `ClaudeStatsApp.swift`. `DashboardView` becomes `public`; `DashboardView` gains an optional model-injection initializer.
- **Tests**: new `ClaudeStatsAppLibTests` target; a handful of new pure tests added to `ClaudeStatsCoreTests` for the `BlockType`/`BlockConfig` editor rules.
- **Dependencies**: adds **ViewInspector as a test-only dependency** — the first external dependency in the project, deliberately confined to the test target so the shipped app stays dependency-free.
- No behaviour change; no change to `ClaudeStatsCore` sources; Makefile unchanged; no new runtime dependency.
