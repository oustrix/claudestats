# Editable token pricing — a Pricing tab in Settings

## Problem

Token prices (`pricing.json`) are editable today only by hand-editing the file. The app loads
pricing once into `DashboardModel.pricing` (a `let`, unobserved) and never writes it back. Users
who want to correct a rate must find the file, edit JSON, and relaunch. We want to edit prices in
the Settings sheet and have the cost cards re-price live.

## Goals

- A **Pricing** tab in Settings that edits the four known model families' four rates each.
- Edits persist to `pricing.json` and re-price the cost cards / per-session cost column live.
- A **Reset** to the published defaults.
- Hand-editing the file keeps working — the app remains a writer of the same file, not the owner.

## Non-goals (YAGNI)

- Adding or removing model families in the UI (still done by hand-editing the file).
- Per-exact-model-id overrides in the UI (still the file).
- Debounced per-keystroke persistence.

## Design

### 1. Tabbed Settings

`SettingsView.body` today is a `VStack` of `header / appearance / data / cost / layout / footer`.
Introduce `@State private var tab: SettingsTab = .general` (`enum SettingsTab { case general,
pricing }`) and a tab bar beneath the header. `header` and `footer` stay shared; the middle content
switches on `tab`:

- **General** — the existing Appearance / Data / Cost / Layout sections, moved verbatim.
- **Pricing** — the new price editor.

The tab bar reuses the existing theme-painted `SegmentedControl` in this file (it recolours with
the theme where a native `TabView`/`Picker(.segmented)` would not). No new component, no native
`TabView`. Window width stays 460.

### 2. Model: prices become editable

In `DashboardModel`:

- `let pricing` → `private(set) var pricing`. Now observed, so a change re-renders `DashboardView`,
  which passes the new value into `CostBlockView` and `SessionListBlockView` — live re-pricing with
  no extra plumbing.
- Keep `@ObservationIgnored private let pricingStore` (hold the injected store).
- New methods, mirroring `setTheme` / `persistPreferences`:
  - `func setRate(family: String, rate: ModelRate)` — replace one family's rate, then persist.
  - `func resetPricing()` — `pricing = .default`, then persist.
  - `private func persistPricing()` — `try pricingStore.save(pricing)`; on failure log via
    `Log.settings.error`, do not crash (same "never lie silently, but the sheet has no error
    affordance" stance as `persistPreferences`). The change still applies for the session.

The "tokens are unreachable outside the module" invariant is untouched: only the public
`Pricing`/`ModelRate` (prices) change, never `TokenUsage`. Update the stale comments in
`Pricing.swift` and `DashboardModel.swift` that say pricing is "hand-edited rather than changed in
the app" — both paths now exist and coexist.

### 3. The Pricing editor

A table: four family rows (opus / sonnet / haiku / fable) × four numeric fields (input / output /
cache-write / cache-read), values in USD per 1,000,000 tokens. Plus:

- An explanatory caption (reuse the Cost section's "estimated from published prices, not a billing
  document" text).
- A row showing the `pricing.json` path (like Layout's "Layout file" row) — the file is still
  theirs.
- A **Reset…** button opening a `confirmationDialog` ("Reset prices to the published defaults?") →
  `model.resetPricing()`, the same pattern as Reset layout.

**Input behaviour:** each field is a `TextField` bound to a local `@State` draft string, committed
**on Enter / focus loss** (`.onSubmit` / focus tracking), not per keystroke — so intermediate
values (empty, `"1."`) never drive a re-price or write. On commit: parse `Double`; reject invalid
or negative (revert the draft to the current value); a valid value calls `model.setRate(...)`.
Fixed-width monospaced fields, matching the `detail` style.

### 4. Testing (TDD, core/model-first)

- `DashboardModelTests`: `setRate` and `resetPricing` change `pricing` and persist through the
  injected `PricingStore` (the initializer already injects it).
- Extract input parse/validation into a small pure helper (parse string → valid non-negative
  `Double?`), tested without SwiftUI (reject negative, reject non-numeric, accept decimals).
- `PricingStore` load/save is already covered.

## Cross-checks

No token-counting logic changes, so `make dump` totals are unaffected. After the change, verify a
cost card re-prices when a rate is edited, and that `pricing.json` reflects the edit.
