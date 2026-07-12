## Why

Claude Code records every model interaction as JSONL under `~/.claude/projects/`, but there is no way to see how that usage accumulates over time, across projects, models and tools. The existing `ccusage` CLI reports token totals and dollar estimates, yet it prints a fixed report to a terminal, cannot show trends, and exposes none of the other dimensions present in the transcripts (tools, sessions, git branches).

The transcripts contain a counting trap that any naive reader falls into. A single assistant message is written as multiple JSONL lines — one per content block (text, `tool_use`) — and every line repeats the same final `usage` object. Summing lines instead of messages inflates token counts by a factor of 2.27 on the current corpus (189.3M naive vs 83.5M correct). A dedicated tool must get this right and must be verifiable.

## What Changes

- Add a native macOS SwiftUI application that reads Claude Code transcripts and renders usage statistics as a configurable dashboard.
- Read all transcripts into memory on launch, on explicit refresh, and on a 30-second timer that skips work when no file changed (`mtime` + size comparison).
- Count token usage once per unique `(message.id, requestId)` pair; count tool invocations once per `tool_use` content block without deduplication.
- Exclude `<synthetic>` assistant records, which carry zero usage and represent no API call.
- Include subagent records (`isSidechain: true`) in all statistics, preserving the flag so a filter can be added later.
- Attribute each session to the `cwd` and calendar date of its first record; attribute each token to the calendar date of its own record, in the user's local timezone.
- Render the dashboard as an ordered list of blocks drawn from a closed catalog (`bigNumber`, `timeSeries`, `breakdown`, `sessionList`), each parameterised by metric, timeframe and dimension.
- Persist the block list to `~/Library/Application Support/ClaudeStats/layout.json` as a versioned, hand-editable document; allow adding, removing, configuring and reordering blocks from the UI.
- Report data quality in the UI: number of records read and number of malformed lines skipped. Never silently drop data.
- Ship a `make dump` command that prints aggregates to stdout so the app's numbers can be cross-checked against `ccusage` and against ad-hoc `jq` queries.
- Do not compute dollar costs in this change. Token counts are recorded facts; prices are not, and a stale price table lies silently.

## Capabilities

### New Capabilities

- `transcript-ingestion`: Discovery, parsing and deduplication of Claude Code JSONL transcripts into a flat event stream, with explicit handling of malformed input.
- `usage-aggregation`: Pure aggregation of transcript events into the metrics the dashboard renders — totals, time series, breakdowns by model/project/tool, and sessions.
- `dashboard-blocks`: A configurable dashboard of typed blocks with a persisted, versioned layout.

### Modified Capabilities

None.

## Impact

- New Swift package at the repository root with two targets: `ClaudeStatsCore` (library, no UI imports) and `ClaudeStatsApp` (SwiftUI executable).
- New `Makefile` producing `ClaudeStats.app` by assembling the `swift build` binary with an `Info.plist`; targets for `run`, `test` and `dump`.
- Tests in `Tests/ClaudeStatsCoreTests` running against hand-written fixtures in `Fixtures/`, covering deduplication, synthetic exclusion, tool counting, midnight-crossing sessions, `cwd` changes mid-session, malformed lines and empty directories.
- Reads `~/.claude/projects/` recursively. Writes only `~/Library/Application Support/ClaudeStats/layout.json`.
- App Sandbox is disabled, because a sandboxed app cannot read `~/.claude`. Consequence: the app cannot be distributed through the Mac App Store, and is unsigned on first launch.
- No app icon and no code signing in this change.
- No runtime dependencies beyond the macOS SDK: `Charts` and `Observation` ship with macOS 26.
