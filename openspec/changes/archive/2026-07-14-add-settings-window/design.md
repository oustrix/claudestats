## Context

Phase 1 shipped the visual system but left three deliberate seams: `Theme.default`, a single named constant; a hard-coded `refreshInterval = Duration.seconds(30)` in `DashboardView`; and `StatsStore(transcriptRoot:)`, which the app always calls with the built-in default. `LayoutStore` already persists `layout.json` to Application Support with a mature philosophy — never crash, fall back to defaults, surface (not swallow) failures — and there is a `Layout.default` but no user-facing way to reset to it.

Phase 2 turns those seams into a settings sheet backed by a persisted `Preferences`. The Core constraint holds: Core imports only `Foundation` (+ `Observation`) and never SwiftUI/AppKit, so the Codable model and its file IO live in Core (like `LayoutStore`), while the `ThemeChoice` → SwiftUI `Color` mapping stays in the app. No counting or aggregation is touched; this phase changes no counted number.

## Goals / Non-Goals

**Goals:**

- A `Preferences` value type persisted as hand-editable, pretty-printed `settings.json` beside `layout.json`, with graceful defaults on a missing or corrupt file — the `LayoutStore` philosophy, mirrored.
- Defensive, forward-compatible decode: an unknown `theme` string or out-of-range `refreshInterval` falls back to its default rather than discarding the file, and the shape extends to phase-3 `showCost` with one field.
- A themed modal **sheet** (not a native `Settings` scene) with Appearance, Data, and Layout sections that drive the live theme, refresh cadence, transcripts root, and a layout reset — each taking effect without relaunch.
- Testable wiring: theme change, refresh-interval change, transcripts-root change, and layout reset are all assertable against `DashboardModel` with injected scratch files — no test touches real `~/.claude` or real Application Support.

**Non-Goals:**

- Dollar-cost estimation and any `showCost` field or Cost settings section (phase 3).
- Breakdown expand-to-modal (phase 4).
- A native `Settings` scene / ⌘, keyboard entry — the mockup is a sheet.
- Light themes or following the system appearance — both palettes stay dark.

## Decisions

### `Preferences`/`PreferencesStore` in Core, `Theme` mapping in the app

`Preferences` is a Codable struct in Core holding `theme: ThemeChoice`, `refreshInterval: RefreshInterval`, and `transcriptRoot: String?`. `ThemeChoice` (`slate`/`claude`) and `RefreshInterval` (raw `Int` 15/30/60) are Core enums — string/int-backed so the JSON is legible. `PreferencesStore` mirrors `LayoutStore`: a `fileURL`, a `load()` that never throws (missing → seed default; corrupt → log and return default), a throwing `save`, pretty-printed with sorted keys, and a `defaultURL` at `Application Support/ClaudeStats/settings.json`. The `ThemeChoice` → `Theme` switch lives in the app's `Theme.swift`, keeping SwiftUI out of Core.

*Why Core, not the app?* `LayoutStore` sets the precedent, and putting the store in Core makes its file-IO edge cases (missing, corrupt, pretty-print) unit-testable in the Core suite without a SwiftUI host.

### Defensive decode: unknown values coerce to defaults, not a wholesale reset

`Preferences` has a custom `init(from:)` that decodes each field with `decodeIfPresent` and coerces an unknown `theme` string or out-of-range `refreshInterval` to its default; an empty `transcriptRoot` reads as `nil`. This is finer-grained than `LayoutStore`, which resets the whole file on any decode failure: a settings file is a flat bag of independent knobs, so one stale value should not blow away the others. A structurally broken file (not valid JSON) still throws and the store falls back to full defaults, matching `LayoutStore`.

*Why not reuse `LayoutStore`'s all-or-nothing reset?* A layout is one interdependent document; preferences are independent knobs. Per-field coercion also makes the shape forward-compatible — a `settings.json` written by a phase-3 build carrying `showCost` loads cleanly on a phase-2 build, and vice versa.

### `DashboardModel` owns preferences and the store factory

The model already owns `layoutStore`, `stats`, and the layout-mutation methods, and it is the app's single `@Observable`. Phase 2 adds an observed `preferences`, a `PreferencesStore`, and a `makeStore: (URL) -> StatsStore` factory. `stats` becomes `private(set) var` so a transcripts-root change can rebuild it via the factory and kick a refresh; `setTheme`/`setRefreshInterval` mutate `preferences` and persist; `resetLayout` reuses the existing `persist()` machinery to write `Layout.default`. The initial store is built from `preferences.transcriptRoot` through the same factory, so the real app honors a stored override on launch.

*Why the model, not a separate `SettingsModel`?* Reset needs the layout blocks and `layoutStore`; the transcripts-root change needs to rebuild `stats`; the theme and interval need to be observed by `DashboardView`. All of that already lives on `DashboardModel`; a second observable would split one screen's state across two objects.

*Why a store factory?* It is the injection seam that makes "a root change rebuilds the store for that root" assertable without a filesystem — a test passes a recording factory returning a stub store. It also lets the default path stay `StatsStore(transcriptRoot:)`.

### The refresh loop reads the interval each tick

`DashboardView`'s `.task` loop sleeps for `Duration.seconds(preferences.refreshInterval.rawValue)` read on each iteration, rather than capturing a fixed value. Changing the interval in settings takes effect on the next tick without restarting the task or relaunching — the in-flight sleep simply finishes at its old duration. This keeps the refresh policy visible in the view (the phase-1 rationale for keeping it out of the store) while making it a preference.

### Settings as a sheet; `NSOpenPanel` for the folder picker

The gear presents `SettingsView` via `.sheet`, themed from the environment and pinned to `.preferredColorScheme(.dark)` like the dashboard. "Change…" opens an `NSOpenPanel` restricted to directories — AppKit, which the app layer (unlike Core) may import, and which is legitimate because the app is non-sandboxed and can read arbitrary folders. The panel is a runtime modal ViewInspector cannot drive, so its outcome is funneled through `model.setTranscriptRoot`, which is where the behavior is tested; the view test only asserts the sheet's static structure.

## Risks / Trade-offs

- **A settings-save failure is logged, not surfaced in the sheet** → Unlike a layout persistence error (which the dashboard already banners), a failed `settings.json` write is logged and the in-memory preference still applies for the session. Application Support is writable in practice, the file is hand-editable, and the mockup has no error affordance; adding one is disproportionate. The invariant "never lie silently" is met by the log line.
- **Interval change lags by up to one old cycle** → The running sleep finishes before the new interval is read. Cancelling and restarting the task would be immediate but adds churn for a sub-minute knob; reading per-tick is simpler and "takes effect without relaunch" holds.
- **Rebuilding `StatsStore` on a root change drops the old scan state** → Intended: a new root is a new corpus, so a full re-scan is correct, and the brief `.loading` flash is honest.

## Migration Plan

No migration. A first launch with no `settings.json` seeds the default file; an older build ignores unknown fields and this build tolerates a partial or newer file, so the format is forward- and backward-compatible. Nothing to roll back — deleting `settings.json` restores defaults on the next launch.

## Open Questions

None. The design is fixed for phase 2.
