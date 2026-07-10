## 1. Project Skeleton

- [x] 1.1 Add `Package.swift` declaring a macOS 26 platform, a `ClaudeStatsCore` library target, a `ClaudeStatsApp` executable target depending on it, and a `ClaudeStatsCoreTests` test target using swift-testing.
- [x] 1.2 Add `Makefile` with `build`, `test`, `run`, `app` and `clean` targets; `app` assembles `ClaudeStats.app` from the built binary plus a generated `Info.plist` with `LSMinimumSystemVersion` and `NSHighResolutionCapable`. The `dump` target is deferred to task 5.1, where the code it invokes first exists.
- [x] 1.3 Add `.gitignore` for `.build/`, `ClaudeStats.app/` and `.DS_Store`.
- [x] 1.4 Verify `make build` and `make test` succeed on an empty test suite before writing any logic.

## 2. Transcript Ingestion

- [x] 2.1 Add `TokenUsage` (input, output, cacheCreation, cacheRead) and `TranscriptEvent` (messageID, requestID, timestamp, sessionID, cwd, gitBranch, model, isSidechain, usage, toolNames) as value types in `ClaudeStatsCore`.
- [x] 2.2 Add `EventSource` protocol returning a `ScanResult` (events plus skipped-line count), and `StubEventSource` for tests. `StubEventSource` lives in the test target: the shipped library carries no test scaffolding.
- [x] 2.3 Write fixtures in `Tests/ClaudeStatsCoreTests/Fixtures/`: a message split across `text` and `tool_use` lines sharing one `usage`; a `<synthetic>` record; a sidechain record; non-assistant records; a malformed line mid-file; a truncated final line; a session crossing midnight; a session whose `cwd` changes. They sit under the test target rather than the repository root because SPM exposes resources through `Bundle.module` only from within a target's directory.
- [x] 2.4 Write failing tests for line-level parsing: assistant records extracted, non-assistant ignored, `<synthetic>` excluded, sidechain retained, timestamps parsed as instants with sub-second precision.
- [x] 2.5 Write failing tests for malformed input: mid-file bad line skipped and counted, truncated final line skipped and counted, preceding events preserved, scan never aborts.
- [x] 2.6 Implement `FileEventSource`: recursive `.jsonl` discovery under an injectable root, line-by-line decode via a `Decodable` shape matching only the needed fields, skipped-line counting. A user turn carries a `message` with no `id` or `model` and a bare string `content`; decoding tolerates that, so a well-formed user record is ignored rather than counted as a skipped line.
- [x] 2.7 Write failing tests for a missing root (empty-state condition, distinguishable from zero usage) and an empty root (zero events, zero skips); implement both.
- [x] 2.8 Add `FileScanState` recording each file's `mtime` and size; write failing tests for "nothing changed → no reparse", "file appended → reparse", "explicit refresh → always reparse"; implement.
- [x] 2.9 Add an opt-in check (`REAL_CORPUS=<dir> swift test --filter realCorpusSanityCheck`) that runs the parser over a real corpus and prints counts for cross-checking against `jq`.

## 3. Deduplication and Counting

- [ ] 3.1 Write a failing test proving a message split across two content-block lines contributes its `usage` exactly once, and that its two `tool_use` blocks contribute two tool invocations.
- [ ] 3.2 Write a failing test proving distinct `messageID` values are never merged.
- [ ] 3.3 Implement `deduplicatedMessages(from:)` keyed on `(messageID, requestID)`, keeping the first occurrence, and `toolInvocations(from:)` counting every `tool_use` block.
- [ ] 3.4 Add a regression test asserting the naive line-sum and the deduplicated sum differ on the split-message fixture, so a future refactor cannot silently reintroduce the inflation.

## 4. Aggregation

- [ ] 4.1 Add `Metric` (`inputOutput`, `cacheRead`, `cacheCreation`, `allTokens`, `requests`), `Dimension` (`model`, `project`, `tool`), `Timeframe` (`last7Days`, `last30Days`, `allTime`) and `Bucket` (`day`, `hour`).
- [ ] 4.2 Write failing tests for metric arithmetic: `inputOutput` excludes cache counters, `allTokens` sums all four, `requests` counts deduplicated messages not lines; implement `total(_:over:)`.
- [ ] 4.3 Write failing tests for timeframe filtering against local calendar days, with an injected reference date and timezone; implement `filter(_:timeframe:now:calendar:)`.
- [ ] 4.4 Write failing tests for daily bucketing: an evening UTC timestamp lands on the correct local day; daily totals sum to the grand total; a midnight-crossing session splits its tokens across two days. Implement `timeSeries(_:bucket:)`.
- [ ] 4.5 Write failing tests for sessions: attribution to the earliest event's day and `cwd`; a `cwd` change mid-session resolves to the first `cwd`; start and end times come from event timestamps. Implement `sessions(from:)`.
- [ ] 4.6 Write failing tests for project identity: full `cwd` is the key, display name is the last component, `~` for home, `/a/snitch` and `/b/snitch` stay distinct. Implement `Project` with `id`, `displayName`, `fullPath`.
- [ ] 4.7 Write failing tests for breakdowns: descending order, limit truncates the tail, unknown model identifiers appear verbatim, `dimension: tool` counts invocations and ignores the metric. Implement `breakdown(dimension:metric:limit:)`.
- [ ] 4.8 Confirm no file in `ClaudeStatsCore` imports SwiftUI or Charts.

## 5. Verification Against Reality

- [ ] 5.0 Surface unreadable files, not just malformed lines. `FileEventSource` currently skips a file it cannot open without counting it, so a permissions error or a non-UTF-8 transcript would silently drop all of that file's events — the exact swallowed error the design forbids. Add an unreadable-file count to `ScanResult` alongside `skippedLines`, cover it with a test, and show it wherever the skipped-line count is shown.
- [ ] 5.1 Implement `make dump`: run the core against the real `~/.claude/projects/`, print per-counter totals, per-model and per-project breakdowns, parsed-record and skipped-line counts.
- [ ] 5.2 Cross-check `make dump` totals against an independent `jq` computation over the same corpus; record the comparison in the change notes. Investigate any discrepancy before proceeding — a mismatch means the parser is wrong.
- [ ] 5.3 Cross-check per-model request counts against `ccusage`, noting any definitional differences rather than tuning numbers to match.

## 6. Store and Layout

- [ ] 6.1 Add `StatsStore` as an `@Observable` holding load state (`idle`, `loading`, `loaded(ScanResult)`, `failed(Error)`), performing loads off the main thread, exposing `refresh()` and driving a 30-second timer that consults `FileScanState`.
- [ ] 6.2 Add `BlockConfig` as a `Codable` sum of the four block types with their parameters, and `Layout` (`version`, `blocks`).
- [ ] 6.3 Write failing tests for layout decoding: a valid document round-trips; an unknown block `type` is skipped and named rather than throwing; a malformed document is reported as such. Implement.
- [ ] 6.4 Implement `LayoutStore`: read from `~/Library/Application Support/ClaudeStats/layout.json`, write on every mutation, move a malformed file aside to `layout.json.bak` and fall back to the default layout, create the directory if absent.
- [ ] 6.5 Define the default layout: a `bigNumber` on `inputOutput`/`last7Days`, a `timeSeries` on `inputOutput`/`last7Days`/`day`, a `breakdown` by `model`, a `breakdown` by `project`, a `breakdown` by `tool`, and a `sessionList`.

## 7. User Interface

- [ ] 7.1 Add the app entry point, a single window, and a toolbar carrying a refresh control and the parsed/skipped record counts.
- [ ] 7.2 Render the loaded, loading, failed and missing-transcripts states; the missing-transcripts state explains itself rather than showing zeros.
- [ ] 7.3 Implement `BigNumberBlockView` and `TimeSeriesBlockView` with Swift Charts, plotting one point per bucket including empty buckets.
- [ ] 7.4 Implement `BreakdownBlockView` as a ranked bar list; project rows show the short name with the full path on hover.
- [ ] 7.5 Implement `SessionListBlockView` showing project, start time, duration and token totals, newest first.
- [ ] 7.6 Implement block editing: an add-block menu over the catalog, per-block removal, drag-to-reorder, and a parameter popover per block type. Every mutation persists the layout.
- [ ] 7.7 Render a notice listing any block types skipped from the layout file.

## 8. Packaging

- [ ] 8.1 Confirm `make app` produces a launchable `ClaudeStats.app` that reads the real transcript directory, and document the unsigned-first-launch prompt in the README.
- [ ] 8.2 Confirm App Sandbox is not enabled and that the app reads `~/.claude/projects/` without a folder-access prompt.
- [ ] 8.3 Write a README covering `make` targets, the layout file location and format, the deduplication rule, and the absence of cost estimation.
- [ ] 8.4 Run the full test suite and `make dump`; confirm the app's headline number matches the dump before declaring the change complete.
