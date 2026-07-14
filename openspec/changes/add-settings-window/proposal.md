## Why

The dashboard's theme is a hard-coded constant, its refresh cadence is a hard-coded 30 seconds, and its transcripts root is always `~/.claude/projects` — none of them are reachable by the user, and there is no way to reset a hand-broken layout from the interface. This is phase 2 of the four-phase redesign — a settings sheet backed by persisted preferences — turning the seams phase 1 deliberately left behind into user-facing controls. (Cost estimation is phase 3; breakdown modals are phase 4.)

## What Changes

- Add a `Preferences` value type and a `PreferencesStore` in Core that persists `settings.json` beside `layout.json` in Application Support, pretty-printed and hand-editable, falling back to defaults on a missing or corrupt file exactly as `LayoutStore` does. Fields: `theme` (`slate` | `claude`, default `slate`), `refreshInterval` (15 | 30 | 60 seconds, default 30), and an optional `transcriptRoot` path (absent means the built-in default). The shape is trivially extendable — phase 3 adds `showCost` with one field.
- Add a Settings gear to the toolbar that presents a themed modal sheet (not a `Settings` scene, no ⌘,) with three sections:
  - **Appearance**: two theme cards; selecting one recolors the app live and persists.
  - **Data**: a transcripts-folder row with a "Change…" button (an `NSOpenPanel` restricted to directories) that re-scans against the chosen root, and a 15/30/60-second refresh-interval segmented control that retimes the live refresh.
  - **Layout**: a layout-file row with a "Reset…" button (confirmed) that restores `Layout.default` — the user-facing reset that was missing.
- Replace the phase-1 seams with preference reads: the live theme comes from `Preferences.theme`, the refresh loop reads `Preferences.refreshInterval`, and the store's root comes from `Preferences.transcriptRoot ?? default`. Changing any of them takes effect without relaunch.

## Capabilities

### New Capabilities
- `settings-preferences`: persisted, hand-editable user preferences (theme, refresh interval, transcripts root) with graceful defaults, surfaced through a themed settings sheet that drives the live theme, refresh cadence, transcripts root, and a layout reset.

### Modified Capabilities
<!-- None. Phase 1's dashboard-blocks requirements are unchanged; the theme it painted from a fixed constant is now driven by a preference, which is new behavior captured under the new capability rather than a change to an existing requirement. -->

## Impact

- **Core (`ClaudeStatsCore`)**: new `Preferences` (Codable, defensive decode: unknown theme/interval → default), `ThemeChoice` and `RefreshInterval` enums, and `PreferencesStore` mirroring `LayoutStore` (missing/corrupt → defaults, pretty-printed, seeds the file). No counting or aggregation touched — every counted number is identical.
- **App (`ClaudeStatsAppLib`)**: `DashboardModel` gains observed `preferences` plus `setTheme`/`setRefreshInterval`/`setTranscriptRoot`/`resetLayout`; a store factory it can call to rebuild `StatsStore` for a new root; a new `SettingsView` sheet; `DashboardView` grows the gear, maps `ThemeChoice` → `Theme`, and reads the refresh interval from preferences. `Theme` gains a `ThemeChoice` initializer.
- **Tests**: Core tests for `PreferencesStore` (round-trip, missing/corrupt → defaults, pretty-print, unknown enum → default); app tests for theme/refresh/transcript-root wiring and layout reset. All inject scratch files — no test touches real `~/.claude` or real Application Support.
- No new dependencies. Older builds skip unknown fields and this build tolerates a partial file, so `settings.json` stays forward- and backward-compatible.
