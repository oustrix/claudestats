# Subagent breakdown — design

## Context

The dashboard reads Claude Code transcripts and renders token-usage statistics. Subagent
runs — dispatched via the Task tool — are written to
`~/.claude/projects/<project>/<session>/subagents/agent-*.jsonl`. The recursive
`FileManager.enumerator` in `transcriptFiles(under:)` already walks those files, their assistant
records carry `message.usage`, and `TranscriptParser` sets `isSidechain: true` on them. **Their
tokens are therefore already in every total the dashboard draws** — they are simply not
distinguishable from main-conversation tokens once counted.

Each subagent file also carries an `attributionAgent` string naming the subagent type. A corpus
snapshot shows it present on 100% of subagent files:

| Type | Dispatches | ~all-tokens |
|---|---:|---:|
| general-purpose | 221 | 150.3M |
| Explore | 67 | 13.7M |
| fork | 1 | 2.4M |
| claude-code-guide | 2 | 0.18M |
| statusline-setup | 4 | 0.17M |

Old-format sidechain records embedded in a main file — the shape the existing fixtures cover —
have `isSidechain: true` but no `attributionAgent`.

This change adds a **lens over data already ingested**. It changes no counted number.

## Goals / Non-Goals

**Goals:**
- Extract `attributionAgent` and carry it to aggregation.
- Add one breakdown dimension, `agent`, that answers both user questions in a single view: the
  subagent **share** (the `main` row against the rest) and the per-**type** split (one row per
  subagent type).
- Prove, by test and by cross-check, that totals are unchanged.

**Non-Goals (deliberately deferred):**
- Per-dispatch statistics (cost or token count per subagent run, grouping by `agentId`).
- A dashboard-wide subagent filter, or any control that removes subagent tokens from a total.
- Re-attributing a subagent's tokens to the project that dispatched it (subagent records carry
  their own `cwd`, often the home directory; this design does not reinterpret it).

## Architecture & data flow

Unchanged pipeline: `FileEventSource` → `[TranscriptEvent]` → `Counting.messages` →
`Aggregation` → blocks. The change threads one optional string through it and adds one dimension
case.

1. **Extraction** — `TranscriptParser` reads `attributionAgent` from each record (nil-tolerant)
   into a new `internal` field `TranscriptEvent.attributionAgent: String?`. Kept `internal` like
   `usage`, so tokens/attribution reach the outside only through a `Message`.
2. **Counting** — `Counting.messages` copies `attributionAgent` onto `Message` from the response's
   first line, consistent with how `cwd`/`timestamp` are taken. `Message` exposes a computed
   `var agentLabel: String = isSidechain ? (attributionAgent ?? "subagent") : "main"`.
3. **Aggregation** — `BreakdownDimension` gains `case agent`; `Aggregation.breakdown` handles it via
   the existing `totals(over:metric:keyedBy: \.agentLabel)`, inheriting deduplication and the
   sort/limit path. No new aggregation entry point.
4. **UI** — `Formatting.swift` adds a `.title` for `.agent`; the `BlockEditor` dimension picker is
   built from `BreakdownDimension.allCases`, so it offers the new dimension with no further change.
   The already-built breakdown detail modal renders its rows as-is.

## Decisions

- **A dimension, not a new block or a filter.** Both user questions live at the message grain that
  `Counting.messages` → `Aggregation.breakdown` already serves. A single dimension labelled `main`
  for the primary conversation and the subagent type otherwise expresses both at once: `main` vs the
  sum of the rest is the share; the remaining rows are the type split. Reuses the block, its sort,
  its limit, and the detail modal. *Rejected:* a dedicated composite "subagents" block (more UI, no
  extra insight, sits outside the catalog); a per-block main/subagent/all scope toggle (a filter in
  disguise, which the user did not want).
- **Label rule `isSidechain ? (attributionAgent ?? "subagent") : "main"`.** Main ranks as a peer
  row. An untyped (old-format) sidechain message falls back to `subagent` rather than being dropped
  — never lose a token silently. *Rejected:* labelling untyped records `unknown` — `subagent` states
  what is actually known.
- **`attributionAgent` stays `internal` on the event**, reaching the outside only as
  `Message.agentLabel`, preserving the module boundary the project guards.

## Testing

- **Core (TDD):** a fixture with a main message + two typed subagents (`general-purpose`, `Explore`)
  + one untyped old-format sidechain. Parser test: typed → value, main/old-format → nil, all
  retained. Aggregation test: `breakdown(.agent, …)` yields `main` + per-type rows sorted
  descending, untyped buckets under `subagent`.
- **Conservation invariant:** for `allTokens`, the sum of `agent` breakdown rows **equals**
  `total(.allTokens)` over the same events and timeframe — catches double-count and drop.
- **App suite:** breakdown block renders `agent` rows with correct labels; a `BlockConfig` with the
  new dimension round-trips through Codable.
- **Cross-check before commit** (project rule): `make dump` + independent `jq` + `ccusage` — all four
  counters and the total agree to the unit; no number moves. Additionally, a `jq` pass grouping a
  snapshot by `attributionAgent` (main = absent-and-not-sidechain) must match the per-agent
  `allTokens` sums.

## Risks / Trade-offs

- **`main` dwarfs the subagent rows in a bar chart** → Accepted: that a type is a thin slice is
  itself the answer to "how much"; the detail modal ranks every row.
- **Field-name drift upstream** (`attributionAgent` renamed) → Extraction is optional/nil-tolerant;
  a rename degrades to every sidechain row showing `subagent`, never a crash or lost token, and the
  conservation invariant still holds.
- **Untyped old-format sidechains bucket into `subagent`** → Correct and honest; the fixture pins
  this path so it can never regress into a drop.

## Migration

Additive and pure-data; no persistence format change. `agent` is a new enum case, so any persisted
`BlockConfig` continues to decode. Rollback is deleting the case and its extraction.
