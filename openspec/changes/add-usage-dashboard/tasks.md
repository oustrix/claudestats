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
- [x] 2.9 Cross-check the parser against a snapshot of a real corpus using an independent `jq` pass. Superseded by `make dump` (task 5.1), which prints the same counts through the production aggregation; the temporary in-test harness was removed rather than maintained as a second audit path.

## 3. Deduplication and Counting

- [x] 3.1 Write a failing test proving a message split across two content-block lines contributes its `usage` exactly once, and that its two `tool_use` blocks contribute two tool invocations.
- [x] 3.2 Write a failing test proving distinct `messageID` values are never merged, including when `requestID` is absent on both.
- [x] 3.3 Implement `Counting.messages(from:)` keyed on `(messageID, requestID)`, and `Counting.toolInvocations(from:)` counting every `tool_use` block. Which line's counters win was settled later, in task 5.3: the line bearing a `stop_reason`.
- [x] 3.4 Add a regression test asserting the naive line-sum and the deduplicated sum differ on the split-message fixture, so a future refactor cannot silently reintroduce the inflation.
- [x] 3.5 Cross-check the deduplicated per-counter totals against an independent `jq` computation over a snapshot of the real corpus. Both agreed exactly on the rule as written at the time. The rule itself turned out to be wrong — see task 5.3, where `ccusage` exposed an 8% output undercount that a `jq` pass mirroring the same wrong rule could never reveal.

## 4. Aggregation

- [x] 4.1 Add `Metric` (`inputOutput`, `cacheRead`, `cacheCreation`, `allTokens`, `requests`), `Dimension` (`model`, `project`, `tool`), `Timeframe` (`last7Days`, `last30Days`, `allTime`) and `Bucket` (`day`, `hour`).
- [x] 4.2 Write failing tests for metric arithmetic: `inputOutput` excludes cache counters, `allTokens` sums all four, `requests` counts deduplicated messages not lines; implement `total(_:over:)`.
- [x] 4.3 Write failing tests for timeframe filtering against local calendar days, with an injected reference date and timezone; implement `filter(_:timeframe:now:calendar:)`. A timeframe spans whole local days, not a rolling 24-hour window.
- [x] 4.4 Write failing tests for daily bucketing: an evening UTC timestamp lands on the correct local day; daily totals sum to the grand total; a midnight-crossing session splits its tokens across two days; an empty day inside the span appears as a zero rather than being omitted. Implement `timeSeries(_:bucket:)`.
- [x] 4.5 Write failing tests for sessions: attribution to the earliest event's day and `cwd`; a `cwd` change mid-session resolves to the first `cwd`; start and end times come from event timestamps. Implement `sessions(from:)`.
- [x] 4.6 Write failing tests for project identity: full `cwd` is the key, display name is the last component, `~` for home, `/a/snitch` and `/b/snitch` stay distinct, and `/Users/median` is not abbreviated as a child of `/Users/me`. Implement `Project` with `fullPath`, `displayName`, `abbreviatedPath`.
- [x] 4.7 Write failing tests for breakdowns: descending order, ties broken by label so the order never flickers, limit truncates the tail, unknown model identifiers appear verbatim, `dimension: tool` counts invocations and ignores the metric. Implement `breakdown(_:metric:over:limit:)`, which takes raw events and performs the message/block split itself so a caller cannot apply the wrong counting rule.
- [x] 4.8 Confirm no file in `ClaudeStatsCore` imports SwiftUI or Charts. It imports only `Foundation`.

## 5. Verification Against Reality

- [x] 5.0 Surface unreadable files, not just malformed lines. `FileEventSource` skipped a file it could not open without counting it, so a permissions error or a non-UTF-8 transcript would silently drop all of that file's events. `ScanResult` now carries `unreadableFiles` beside `skippedLines`, covered by tests for a permission-denied file and a non-UTF-8 file.
- [x] 5.1 Implement `make dump` as a separate `ClaudeStatsDump` executable: per-counter totals, per-model, per-project and per-tool breakdowns, session count, parsed lines, skipped lines and unreadable files. Also prints the naive line-sum and its ratio to the true total.
- [x] 5.2 Cross-check `make dump` totals against an independent `jq` computation over a snapshot of the corpus. Both agree on every counter. A snapshot is required: a live transcript grows while it is measured.
- [x] 5.3 Cross-check against `ccusage` (`CLAUDE_CONFIG_DIR` pointed at the snapshot). **This found a real bug.** Three counters matched; output was 8% low. Claude Code streams a response, writing intermediate lines with a placeholder `output_tokens` of 1; only the line that gains a `stop_reason` reports the real count. Deduplication now takes that line's counters and the first line's timestamp — keyed on the stop reason itself, not on position, so reordered or concatenated files cannot reinstate the undercount. All four counters, and the 112 942 871 total, match `ccusage` exactly.

## 6. Store and Layout

- [x] 6.0 Measure the cost of a render in which every block recomputes from raw events, before adding any cache. Release build, 3 454 events: one dedup pass 0.7 ms; `bigNumber` 0.8 ms; `timeSeries` 3.1 ms; `breakdown` 1.1 ms; `sessionList` 1.3 ms; a full six-block render **7.5 ms**, against a 16 ms frame. No cache. Revisit only if a measurement, not an intuition, says otherwise.
- [x] 6.1 Add `StatsStore` as an `@Observable` holding load state (`idle`, `loading`, `loaded(ScanResult)`, `noTranscripts(URL)`, `failed(String)`), performing loads off the main thread and exposing `refresh(force:)`. **The store owns no timer.** A timer inside it could not be tested without waiting thirty seconds; the caller ticks it instead, which also keeps the refresh policy visible in the UI. A failed refresh keeps the events already on screen and records `lastError`, rather than replacing real numbers with an error.
- [x] 6.2 Add `BlockConfig` as a flat `Codable` struct (`id`, `type`, and the parameters a type uses) and `Layout` (`version`, `blocks`). Flat rather than an enum with associated values, because `layout.json` is edited by hand and a tagged union reads badly as JSON.
- [x] 6.3 Write failing tests for layout decoding: a valid document round-trips; an unknown block `type` is skipped and named rather than throwing; an unknown *parameter* value skips its block and names the type; a malformed document throws. Implement.
- [x] 6.4 Implement `LayoutStore`: read from `~/Library/Application Support/ClaudeStats/layout.json`, write on every mutation, move a malformed file aside and fall back to the default layout, create missing directories. `load()` never throws. A second breakage does not overwrite the first backup: it becomes `layout.json.bak2`, because a backup may hold the only copy of a dashboard the user built.
- [x] 6.5 Define the default layout: a `bigNumber` on `inputOutput`/`last7Days`, a `timeSeries` on `inputOutput`/`last30Days`/`day`, breakdowns by `model`, `project` and `tool`, and a `sessionList`. Covered by a test asserting the default exercises every block type.

## 7. User Interface

- [x] 7.1 Add the app entry point, a single window, and a toolbar carrying a refresh control and the parsed/skipped record counts. The 30-second timer lives in the view's `.task`, not in the store: a policy you can see is a policy you can change.
- [x] 7.2 Render the loaded, loading, failed and missing-transcripts states; the missing-transcripts state explains itself rather than showing zeros.
- [x] 7.3 Implement `BigNumberBlockView` and `TimeSeriesBlockView`. The headline is not a chart — one number has no shape to see; its exact figure sits behind a `.help` tooltip so the compact form stays readable. The time series is bars, not a line: the data is a count per discrete bucket, and a line would draw values for the moments between days that never existed. One series, so no legend and one hue. The chart is rasterised with `.drawingGroup()`: a Swift Charts view is redrawn from its vectors on every frame it moves, which stuttered scrolling badly (confirmed by measurement — the aggregation recomputed only a handful of times, so the cost was the chart's own redraw). Per-bar selection was removed: it fought the scroll gesture and added nothing the tooltip does not.
- [x] 7.4 Implement `BreakdownBlockView` as a ranked bar list, horizontal because the labels are words and a vertical axis would tilt `claude-haiku-4-5-20251001` into illegibility. Bars are drawn as a proportion of the largest row. One hue for every row: rank is already encoded by position, and colouring by rank would repaint the survivors whenever a filter changed the order. Project rows show the short name with the full path on hover.
- [x] 7.5 Implement `SessionListBlockView` showing project, start time, span and token totals, newest first. The span counts breaks: the transcripts hold nothing that would let it not to, so it is labelled a span rather than active time.
- [x] 7.6 Implement block editing: an add-block menu over the catalog, per-block removal, reordering, and a parameter popover per block type that offers only the parameters that type uses. Every mutation persists the layout. Reordering is by buttons rather than drag — a drag inside a scrolling column of charts fights the scroll — which also means each persist follows a discrete action and needs no debounce.
- [x] 7.7 Render a notice listing any blocks skipped from the layout file, distinguishing an unknown block type from unreadable parameters, and report a layout that could not be written.
- [x] 7.8 Rename `Dimension` to `BreakdownDimension`. Foundation ships a unit-of-measurement type by that name, and the collision forced a qualification at every call site.

## 8. Packaging

- [ ] 8.1 Confirm `make app` produces a launchable `ClaudeStats.app` that reads the real transcript directory, and document the unsigned-first-launch prompt in the README.
- [ ] 8.2 Confirm App Sandbox is not enabled and that the app reads `~/.claude/projects/` without a folder-access prompt.
- [ ] 8.3 Write a README covering `make` targets, the layout file location and format, the deduplication rule, and the absence of cost estimation.
- [ ] 8.4 Run the full test suite and `make dump`; confirm the app's headline number matches the dump before declaring the change complete.
