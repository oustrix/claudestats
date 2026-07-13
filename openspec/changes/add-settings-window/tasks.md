## 1. Core: Preferences model and store (TDD)

- [ ] 1.1 Write failing `ClaudeStatsCoreTests` for `Preferences`: codable round-trip; unknown theme string → `slate`; out-of-range interval → 30; empty transcripts root → nil; pretty-printed encode output
- [ ] 1.2 Write failing `PreferencesStore` tests mirroring `LayoutStoreTests`: missing file → defaults and seeds the file; corrupt file → defaults without throwing; a saved value survives a reload
- [ ] 1.3 Add `ThemeChoice` (`slate`/`claude`, String-backed) and `RefreshInterval` (Int-backed 15/30/60) enums in Core
- [ ] 1.4 Add `Preferences` (Codable, custom defensive `init(from:)` and `encode(to:)`, `.default`, `resolvedTranscriptRoot`) in Core
- [ ] 1.5 Add `PreferencesStore` mirroring `LayoutStore`: `fileURL`, non-throwing `load()`, throwing pretty-printed `save`, `defaultURL` at `Application Support/ClaudeStats/settings.json`
- [ ] 1.6 Confirm the Core suite is green

## 2. App: theme mapping and model wiring (TDD)

- [ ] 2.1 Add `Theme(_ choice: ThemeChoice)` mapping in `Theme.swift`
- [ ] 2.2 Write failing `ClaudeStatsAppLibTests`: `setTheme` updates `preferences.theme` and persists; `setRefreshInterval` persists and is readable; `setTranscriptRoot` rebuilds the store via an injected factory for the new root and persists; `resetLayout` restores `Layout.default` and persists
- [ ] 2.3 Extend `DashboardModel`: observed `preferences`, injected `PreferencesStore` and `makeStore` factory, `stats` as `private(set) var`; add `setTheme`/`setRefreshInterval`/`setTranscriptRoot`/`resetLayout`; build the initial store from `preferences.resolvedTranscriptRoot`
- [ ] 2.4 Update test support (`seededModel`, direct `DashboardModel` constructions) to inject a scratch `PreferencesStore` so no test touches real Application Support
- [ ] 2.5 Confirm the app suite is green

## 3. App: settings sheet UI

- [ ] 3.1 Add a Settings gear toolbar item and a `.sheet` presentation in `DashboardView`, themed and pinned to dark
- [ ] 3.2 Build `SettingsView`: Appearance theme cards (active ringed with `theme.accent`), Data transcripts-folder row (`NSOpenPanel`, directories only) + refresh-interval segmented control, Layout file row + confirmed Reset, and the footer line
- [ ] 3.3 Replace the phase-1 seams in `DashboardView`: theme from `Theme(model.preferences.theme)`, refresh loop reads `model.preferences.refreshInterval` each tick
- [ ] 3.4 Add a light app-layer view test that `SettingsView` renders its sections/theme cards

## 4. Verification

- [ ] 4.1 `make build` clean and `make test` green (both suites); note the before/after test count
- [ ] 4.2 `openspec validate add-settings-window --strict`
- [ ] 4.3 Commit in logical steps with conventional one-line messages; leave the branch for review (do not merge or push)
