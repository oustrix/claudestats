## Context

Claude Code writes one JSONL file per session under `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`. Measurements on the author's machine (2026-07-10): 143 files, 36 MB, 7 878 lines, of which 3 095 are `type: "assistant"` records carrying a `usage` object. A full `jq` pass over the entire corpus takes 0.19 s.

The byte size is dominated by message text, not by record count. This single fact drives the architecture: there are barely more than a thousand billable events, so there is nothing to cache, index or incrementally maintain.

## Goals / Non-Goals

**Goals**

- Correct token counts, provably so, cross-checkable against an independent tool.
- A dashboard whose blocks the user composes, rather than a fixed set of screens.
- A core library that is testable without a UI and replaceable underneath without touching the UI.

**Non-Goals**

- Dollar cost estimation. Deferred until there is a reason to maintain a price table.
- Subscription limit tracking. Anthropic does not publish the limits; any number would be a guess.
- A query builder or dashboard DSL. The block catalog is closed on purpose.
- Real-time streaming of in-flight sessions. A 30-second timer is enough for retrospective statistics.
- Persistence, caching or a database. See "SQLite seam" below.

## Decisions

### Parse everything, every time

`FileEventSource` walks `~/.claude/projects/`, reads each `.jsonl` line by line, decodes the fields the dashboard needs and returns a flat `[TranscriptEvent]`. Nothing is stored between runs.

The alternative — a SQLite cache with incremental tail reads — was rejected. It buys back 0.19 s of work at the cost of a schema, migrations, cache invalidation and an entire class of "the database disagrees with the files" bugs. The corpus would need to grow by two orders of magnitude before this trade reverses.

**SQLite seam.** `EventSource` is a protocol with a single method returning `[TranscriptEvent]`. `FileEventSource` implements it today; a `SQLiteEventSource` could implement it later without aggregation or UI changing. The same protocol is what tests use to inject fixtures. No further abstraction is built in anticipation of a database — no repository layer, no query interface, no storage configuration.

### Two counting rules, because the data has two shapes

An assistant message is serialised as one JSONL line per content block. All lines of a message share `message.id`, `requestId` and an identical `usage` object. Verified example: `msg_0111B98NftZ5LKVQGFFTGHDC` appears twice — once with a `text` block, once with a `tool_use` block — both carrying `usage {input: 2, output: 207, cache_creation: 5481, cache_read: 75382}`.

- **Token usage** is counted once per distinct `(messageID, requestID)`. Deduplication is by first occurrence; the `usage` objects are identical, so the choice is immaterial.
- **Tool invocations** are counted once per `tool_use` block, across all lines. Two lines of one message mean two distinct tool calls, and both are real.

Measured effect of getting this wrong: 189 288 158 tokens naive versus 83 457 634 deduplicated, a 2.27× inflation. (A later snapshot, taken while implementing, measured 2.36× on input plus output — the ratio drifts with the corpus, the failure does not.)

**The rule is enforced by the type system, not by convention.** `TranscriptEvent.usage` is internal to `ClaudeStatsCore`; tokens are reachable only through `Message`, and the only way to obtain a `Message` is `Counting.messages(from:)`, which deduplicates. Summing tokens per line does not compile outside the module. `toolNames` stays public on the raw event, because that is where tool invocations legitimately live.

### Cache tokens dominate, so no single "total" is meaningful

Deduplicated totals over the corpus: cache read 78.1M (93.6%), cache creation 3.5M (4.2%), input 0.96M (1.2%), output 0.83M (1.0%).

A chart of "total tokens per day" is, to within rounding, a chart of cache reads; input and output are thinner than a pixel. Rather than pick a headline metric globally, metric selection is a **block parameter**. The default layout uses `input + output` for the headline number and time series, and gives cache its own block.

### Attribution: tokens by event, sessions by start

A session spanning midnight would otherwise be double-counted or misplaced.

- Each `usage` record contributes to the calendar day of **its own** `timestamp`, converted to the local timezone. Daily token totals therefore always sum to the grand total.
- Each session is attributed to the day and `cwd` of **its first** record. "Sessions on Tuesday" means sessions that started on Tuesday.

Two sessions in the corpus change `cwd` mid-session; first-record attribution resolves them deterministically.

### Project identity comes from `cwd`, not the directory name

The directory name `-Users-fomindan--claude-code-router` encodes `/Users/fomindan/.claude-code-router` by replacing path separators and dots with dashes. The encoding is not invertible: a dash in the decoded path is indistinguishable from an encoded separator. The `cwd` field carries the true path, so projects are keyed by the `cwd` of the session's first record.

Display shows the last path component (`snitch`); the full path, with `$HOME` abbreviated to `~`, appears on hover. The home directory displays as `~`.

### Blocks are a closed catalog, not a query language

```
BlockType      Parameters
─────────────────────────────────────────────────────────────
bigNumber      metric, timeframe
timeSeries     metric, timeframe, bucket (day | hour)
breakdown      dimension, metric, timeframe, limit
sessionList    timeframe, limit

metric     ::= inputOutput | cacheRead | cacheCreation | allTokens | requests
dimension  ::= model | project | tool
timeframe  ::= last7Days | last30Days | allTime
```

`breakdown` with `dimension: tool` uses the tool-invocation count and ignores `metric`, since tokens are not attributable to individual tool calls.

Blocks hold no state. Each renders a pure function of `(events, parameters)`. Recomputing 1 300 events per block costs microseconds, and in exchange there are no stale caches to invalidate. This is the same trade as re-parsing on every refresh: computing is cheaper than remembering.

### Layout is a versioned document the user owns

`~/Library/Application Support/ClaudeStats/layout.json` holds `{"version": 1, "blocks": [...]}`. It is plain JSON, hand-editable. A block of unknown `type` is skipped with a visible notice rather than crashing, so an older build survives a newer config. A malformed file is moved aside to `layout.json.bak` and replaced with the default layout.

### Refresh without a file watcher

A 30-second timer compares each file's `mtime` and size against the previous scan. If nothing changed, no parsing happens. Explicit refresh bypasses the comparison. `FSEvents` was rejected: it adds debouncing, partial-line handling and incremental parsing to serve a use case — watching numbers tick during a session — that retrospective statistics do not have.

### Errors are surfaced, never swallowed

Transcripts are appended to while the app runs, so the final line of a file may be truncated mid-write. Such a line is skipped, but skips are counted and shown: "1 304 records · 2 lines skipped". A missing `~/.claude/projects` yields an explanatory empty state, not zeros. Unknown model identifiers (`gpt-5.5` is already present in the corpus) are displayed verbatim rather than classified.

### App Sandbox is disabled

A sandboxed app cannot read `~/.claude`, and routing around that with a folder-picker prompt for a personal tool serves no one. The cost is exclusion from the Mac App Store, which is not a goal.

### Swift Package plus Makefile, not an Xcode project

An `.xcodeproj` is an XML database editable only through Xcode, which the author does not intend to open and which an agent cannot edit safely as text. Instead: `Package.swift` with two targets, and a `Makefile` that assembles `swift build` output plus an `Info.plist` into `ClaudeStats.app`.

## Risks / Trade-offs

- **Deduplication key.** The key is the pair `(messageID, requestID)`. `messageID` alone is already unique per API response, so `requestID` is redundant in practice; it is retained because a missing or reused `messageID` would then still be disambiguated rather than silently collapsing two responses into one. The corpus shows `requestId` present on every non-synthetic assistant record. Should Claude Code ever emit `requestId: null` for a real call, the pair degrades to `messageID` alone, which remains correct.
- **Unbounded memory growth.** All events live in memory. At ~1 300 events per two weeks, a decade of use is ~340 000 events — tens of megabytes of structs. Acceptable; if it stops being so, `SQLiteEventSource` replaces `FileEventSource` behind the existing protocol.
- **Timezone changes.** Aggregation uses the current local timezone at render time. Travelling across timezones will re-bucket historical days. Considered correct: "what did I do on Tuesday" means Tuesday where the user is now.
- **`make dump` may drift from the UI.** Both must call the same `ClaudeStatsCore` aggregation functions; `dump` exists precisely to catch drift between the app's numbers and an independent tool.

## Open Questions

None. Cost estimation, subagent filtering, git-branch statistics and a menu bar surface are deliberately deferred; each is additive and none constrains this design.
