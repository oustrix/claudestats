# ClaudeStats

A native macOS SwiftUI app that reads Claude Code transcripts from `~/.claude/projects/`
and renders token-usage statistics as a configurable dashboard. Spec and rationale live in
`openspec/changes/add-usage-dashboard/` (`design.md` first).

## Commands

- `make test` — run the suite (swift-testing).
- `make build` — debug build.
- `make dump [ROOT=<dir>]` — print the same aggregates the dashboard draws, for cross-checking
  against `ccusage` or `jq`. The auditing tool: trust no number the dump and an independent tool
  don't agree on.
- `make app` — assemble `ClaudeStats.app` (release binary + generated `Info.plist`). No `.xcodeproj`:
  it is XML only Xcode edits; this project is maintained as text.
- `make run` — launch the SwiftUI app.

## Layout

- `Sources/ClaudeStatsCore/` — library. Imports only `Foundation` (+ `Observation`). **Never** import
  SwiftUI, Charts, or AppKit here. All logic and tests live against this target.
- `Sources/ClaudeStatsApp/` — SwiftUI window.
- `Sources/ClaudeStatsDump/` — the `make dump` CLI.
- Data flow: `FileEventSource` → `[TranscriptEvent]` → `Counting.messages` → `Aggregation` → blocks.
  `EventSource` is the seam a future `SQLiteEventSource` slots into; tests inject through it.

## Load-bearing invariants — break these and the numbers silently lie

- **One response is written across several JSONL lines**, one per content block. Token counts come
  from the line bearing a `stop_reason` (streaming lines carry a placeholder `output_tokens: 1`);
  timestamp and cwd come from the *first* line. Summing per-line inflates ~2.3x. See
  `Counting.messages`.
- **Tokens are unreachable outside the module by design.** `TranscriptEvent.usage` is `internal`;
  the only way to a token count is a `Message`, made only by `Counting.messages`, which deduplicates.
  Keep it that way — do not make `usage` public.
- **Tool invocations are counted per block, never deduplicated** (`Counting.toolInvocations`).
- Every `Aggregation` entry point takes raw `[TranscriptEvent]` and dedups internally, so a caller
  cannot apply the wrong counting rule. Measured cost of a full 6-block render: 7.5 ms. No cache.
- Timeframes are whole **local** calendar days, not rolling 24h windows. Aggregation takes `now` and
  `calendar` explicitly — no reading the clock or `NSHomeDirectory()` inside pure functions; `home`
  is passed in.
- Never lie silently: unreadable files, skipped lines, and layout persistence failures are all
  surfaced, never swallowed.

## Conventions

- **Everything committed is in English** — code, comments, tests, fixtures, spec, commit messages.
  (Conversation with the user is in Russian.)
- Commits: Conventional Commits, one line, no body, no `Co-Authored-By`. Scopes: `core`, `app`,
  `spec`, `make`.
- TDD: write the failing test, watch it fail for the right reason, then implement. Cross-check any
  counting change against `ccusage` on a *snapshot* of the corpus (a live transcript grows mid-read).
- App Sandbox is off (a sandboxed app can't read `~/.claude`); no Mac App Store, unsigned first launch.
- `.gitignore` overrides a global one that hides `openspec/` and `.claude/` — both are versioned here.
