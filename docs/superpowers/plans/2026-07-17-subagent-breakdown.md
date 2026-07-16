# Subagent Breakdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a breakdown dimension `agent` that splits token usage into the main conversation (`main`) versus each subagent type, without changing any existing total.

**Architecture:** Thread an optional `attributionAgent` string from the transcript record through `TranscriptEvent` → `Message`, expose a computed `Message.agentLabel`, and add one `BreakdownDimension.agent` case that reuses the existing `totals(…keyedBy:)` path. UI gets the new dimension for free from `BreakdownDimension.allCases`.

**Tech Stack:** Swift 6, swift-testing, SwiftUI (app only). No new dependencies.

## Global Constraints

- Everything committed is in **English** — code, comments, tests, commit messages.
- Commits: **Conventional Commits, one line, no body, no `Co-Authored-By`.** Scopes: `core`, `app`, `spec`, `make`.
- **TDD:** write the failing test, watch it fail for the right reason, then implement.
- `ClaudeStatsCore` imports only `Foundation` (+ `Observation`). **Never** import SwiftUI/Charts/AppKit there.
- `TranscriptEvent.usage` and `attributionAgent` stay **`internal`**: tokens/attribution reach the outside only through a `Message`.
- **No number moves.** Subagent tokens were always in the totals. Before the final commit, cross-check with `make dump` + an independent `jq` pass over a *snapshot* + `ccusage`; all four counters and the total agree to the unit.
- Build: `make build`. Tests: `make test` (both suites).

---

### Task 1: Extract `attributionAgent` onto the event

**Files:**
- Modify: `Sources/ClaudeStatsCore/TranscriptEvent.swift:43-44`
- Modify: `Sources/ClaudeStatsCore/TranscriptParser.swift:40-59` (init call) and `:82` (RawLine)
- Modify: `Tests/ClaudeStatsCoreTests/StubEventSource.swift:54-80` (`makeEvent` factory)
- Modify: `Tests/ClaudeStatsAppLibTests/TestSupport.swift:124-150` (`makeEvent` factory)
- Test: `Tests/ClaudeStatsCoreTests/TranscriptParserTests.swift`

**Interfaces:**
- Produces: `TranscriptEvent.attributionAgent: String?` (internal stored field); both `makeEvent(...)` test factories gain `attributionAgent: String? = nil`.

- [ ] **Step 1: Write the failing test**

Add to `Tests/ClaudeStatsCoreTests/TranscriptParserTests.swift`:

```swift
@Test func attributionAgentIsExtractedWhenPresent() {
    let line = #"{"type":"assistant","timestamp":"2026-07-02T09:43:05.761Z","sessionId":"s","cwd":"/Users/me","gitBranch":"main","isSidechain":true,"attributionAgent":"general-purpose","requestId":"r","message":{"id":"m","model":"claude-opus-4-8","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
    guard case let .event(event) = TranscriptParser.parseLine(line) else {
        Issue.record("expected an event"); return
    }
    #expect(event.attributionAgent == "general-purpose")
    #expect(event.isSidechain)
}

@Test func attributionAgentIsNilWhenAbsent() {
    let line = #"{"type":"assistant","timestamp":"2026-07-02T09:43:05.761Z","sessionId":"s","cwd":"/Users/me","gitBranch":"main","isSidechain":false,"requestId":"r","message":{"id":"m","model":"claude-opus-4-8","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
    guard case let .event(event) = TranscriptParser.parseLine(line) else {
        Issue.record("expected an event"); return
    }
    #expect(event.attributionAgent == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter attributionAgent`
Expected: FAIL — `value of type 'TranscriptEvent' has no member 'attributionAgent'` (compile error).

- [ ] **Step 3: Add the stored field to `TranscriptEvent`**

In `Sources/ClaudeStatsCore/TranscriptEvent.swift`, after the `isSidechain` line (`:43`):

```swift
    public let isSidechain: Bool
    /// The subagent type this record was attributed to (`general-purpose`, `Explore`, …). Internal,
    /// like `usage`: it reaches the outside only through `Message.agentLabel`. Nil on the main
    /// conversation and on old-format sidechain records that predate the field.
    let attributionAgent: String?
    let usage: TokenUsage
```

- [ ] **Step 4: Extract it in the parser**

In `Sources/ClaudeStatsCore/TranscriptParser.swift`, add the field to `RawLine` (after `isSidechain` at `:82`):

```swift
    let isSidechain: Bool?
    let attributionAgent: String?
```

Then pass it into the `TranscriptEvent(...)` init (after the `isSidechain:` argument at `:49`):

```swift
                isSidechain: raw.isSidechain ?? false,
                attributionAgent: raw.attributionAgent,
                usage: TokenUsage(
```

- [ ] **Step 5: Update both `makeEvent` factories**

The memberwise init now requires the new argument. In **both** `Tests/ClaudeStatsCoreTests/StubEventSource.swift` and `Tests/ClaudeStatsAppLibTests/TestSupport.swift`, add the parameter (after `isSidechain: Bool = false,`):

```swift
    isSidechain: Bool = false,
    attributionAgent: String? = nil,
```

and pass it in the `TranscriptEvent(...)` call (after `isSidechain: isSidechain,`):

```swift
        isSidechain: isSidechain,
        attributionAgent: attributionAgent,
        usage: usage,
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter attributionAgent`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add Sources/ClaudeStatsCore/TranscriptEvent.swift Sources/ClaudeStatsCore/TranscriptParser.swift Tests/ClaudeStatsCoreTests/StubEventSource.swift Tests/ClaudeStatsAppLibTests/TestSupport.swift Tests/ClaudeStatsCoreTests/TranscriptParserTests.swift
git commit -m "feat(core): extract attributionAgent from transcript records"
```

---

### Task 2: Carry it to `Message` and expose `agentLabel`

**Files:**
- Modify: `Sources/ClaudeStatsCore/Message.swift:17-34,49-54`
- Test: `Tests/ClaudeStatsCoreTests/CountingTests.swift`

**Interfaces:**
- Consumes: `TranscriptEvent.attributionAgent` (Task 1).
- Produces: `Message.attributionAgent: String?` and computed `var agentLabel: String` = `isSidechain ? (attributionAgent ?? "subagent") : "main"`.

- [ ] **Step 1: Write the failing test**

Add to `Tests/ClaudeStatsCoreTests/CountingTests.swift`:

```swift
@Test func agentLabelIsMainForTheMainConversation() {
    let message = Counting.messages(from: [makeEvent(isSidechain: false)]).first!
    #expect(message.agentLabel == "main")
}

@Test func agentLabelIsTheSubagentTypeForSidechain() {
    let message = Counting.messages(
        from: [makeEvent(isSidechain: true, attributionAgent: "Explore")]).first!
    #expect(message.agentLabel == "Explore")
}

@Test func agentLabelFallsBackToSubagentWhenUntyped() {
    let message = Counting.messages(
        from: [makeEvent(isSidechain: true, attributionAgent: nil)]).first!
    #expect(message.agentLabel == "subagent")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter agentLabel`
Expected: FAIL — `value of type 'Message' has no member 'agentLabel'`.

- [ ] **Step 3: Add the field, init, equality, and computed label to `Message`**

In `Sources/ClaudeStatsCore/Message.swift`:

Add the stored field after `isSidechain` (`:17`):

```swift
    public let isSidechain: Bool
    /// The subagent type, carried from the event's first line (like `cwd`). Nil for the main
    /// conversation and untyped old-format sidechain records.
    let attributionAgent: String?
```

Set it in `init(_ event:)` after `isSidechain = event.isSidechain` (`:31`):

```swift
        isSidechain = event.isSidechain
        attributionAgent = event.attributionAgent
```

Add it to `==` (extend the final line at `:53`):

```swift
            && lhs.isSidechain == rhs.isSidechain && lhs.attributionAgent == rhs.attributionAgent
            && lhs.usage == rhs.usage
```

Add the computed label just below the stored properties (after the `usageIsFinal` declaration, `:21`):

```swift
    /// How a breakdown by agent names this message: the main conversation is `main`; a subagent
    /// message is its type, or `subagent` when the type is unknown. Never drops a token silently.
    var agentLabel: String { isSidechain ? (attributionAgent ?? "subagent") : "main" }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter agentLabel`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatsCore/Message.swift Tests/ClaudeStatsCoreTests/CountingTests.swift
git commit -m "feat(core): give Message an agentLabel"
```

---

### Task 3: Add the `agent` breakdown dimension

**Files:**
- Modify: `Sources/ClaudeStatsCore/Metric.swift:67-71` (`BreakdownDimension`)
- Modify: `Sources/ClaudeStatsCore/Aggregation.swift:209-226` (breakdown switch)
- Test: `Tests/ClaudeStatsCoreTests/BreakdownTests.swift`

**Interfaces:**
- Consumes: `Message.agentLabel` (Task 2).
- Produces: `BreakdownDimension.agent`; `Aggregation.breakdown(.agent, …)` returns one `BreakdownRow` per agent label.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/ClaudeStatsCoreTests/BreakdownTests.swift`:

```swift
private func agentEvent(
    _ id: String, sidechain: Bool = false, agent: String? = nil, all: Int
) -> TranscriptEvent {
    makeEvent(
        messageID: id, requestID: "r-\(id)", isSidechain: sidechain, attributionAgent: agent,
        usage: TokenUsage(input: all, output: 0, cacheCreation: 0, cacheRead: 0))
}

@Test func breakdownByAgentSeparatesMainFromTypes() {
    let events = [
        agentEvent("a", all: 100),
        agentEvent("b", sidechain: true, agent: "general-purpose", all: 60),
        agentEvent("c", sidechain: true, agent: "Explore", all: 30),
        agentEvent("d", sidechain: true, agent: "general-purpose", all: 10),
    ]

    let rows = Aggregation.breakdown(
        .agent, metric: .allTokens, over: events, limit: 10, home: home, timeframe: .allTime)

    #expect(rows.map(\.label) == ["main", "general-purpose", "Explore"])
    #expect(rows.map(\.value) == [100, 70, 30])
}

@Test func breakdownByAgentBucketsUntypedSidechainUnderSubagent() {
    let rows = Aggregation.breakdown(
        .agent, metric: .allTokens,
        over: [agentEvent("a", sidechain: true, agent: nil, all: 5)],
        limit: 10, home: home, timeframe: .allTime)

    #expect(rows.map(\.label) == ["subagent"])
}

@Test func agentBreakdownConservesTheAllTokensTotal() {
    let events = [
        agentEvent("a", all: 100),
        agentEvent("b", sidechain: true, agent: "general-purpose", all: 60),
        agentEvent("c", sidechain: true, agent: nil, all: 5),
    ]

    let rowsSum = Aggregation.breakdown(
        .agent, metric: .allTokens, over: events, limit: .max, home: home, timeframe: .allTime
    ).reduce(0) { $0 + $1.value }
    let total = Aggregation.total(.allTokens, over: events, timeframe: .allTime)

    #expect(rowsSum == total)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter Agent`
Expected: FAIL — `type 'BreakdownDimension' has no member 'agent'`.

- [ ] **Step 3: Add the enum case**

In `Sources/ClaudeStatsCore/Metric.swift`, inside `BreakdownDimension` (`:67-71`):

```swift
public enum BreakdownDimension: String, Codable, CaseIterable, Sendable {
    case model
    case project
    case tool
    case agent
}
```

- [ ] **Step 4: Handle it in `Aggregation.breakdown`**

In `Sources/ClaudeStatsCore/Aggregation.swift`, add a case to the `switch dimension` (after the `.model` case, around `:216`):

```swift
        case .agent:
            rows = totals(over: events, metric: metric, keyedBy: \.agentLabel)
                .map { BreakdownRow(label: $0.key, detail: nil, value: $0.value) }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter Agent`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeStatsCore/Metric.swift Sources/ClaudeStatsCore/Aggregation.swift Tests/ClaudeStatsCoreTests/BreakdownTests.swift
git commit -m "feat(core): add the agent breakdown dimension"
```

---

### Task 4: Offer the dimension in the app UI

**Files:**
- Modify: `Sources/ClaudeStatsAppLib/Formatting.swift:52-59` (`BreakdownDimension.title`)
- Test: `Tests/ClaudeStatsAppLibTests/FormattingTests.swift` (create if absent)

**Interfaces:**
- Consumes: `BreakdownDimension.agent` (Task 3).
- Produces: `BreakdownDimension.agent.title == "Agent"`; the `BlockEditor` picker (built from `BreakdownDimension.allCases`) then lists it with no further change.

- [ ] **Step 1: Write the failing test**

Add to `Tests/ClaudeStatsAppLibTests/FormattingTests.swift` (create the file with this content if it does not exist):

```swift
import Testing

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

@Test func agentDimensionHasATitleAndIsOffered() {
    #expect(BreakdownDimension.agent.title == "Agent")
    #expect(BreakdownDimension.allCases.contains(.agent))
}

@Test func agentDimensionPluralizes() {
    #expect(BreakdownDimension.agent.countedNoun(1) == "1 agent")
    #expect(BreakdownDimension.agent.countedNoun(3) == "3 agents")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter agentDimension`
Expected: FAIL — `switch must be exhaustive` compile error in `Formatting.swift` (the `title` switch lacks `.agent`), or an assertion failure.

- [ ] **Step 3: Add the title**

In `Sources/ClaudeStatsAppLib/Formatting.swift`, add the case to the `BreakdownDimension.title` switch (`:55-57`):

```swift
        case .model: "Model"
        case .project: "Project"
        case .tool: "Tool"
        case .agent: "Agent"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter agentDimension`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeStatsAppLib/Formatting.swift Tests/ClaudeStatsAppLibTests/FormattingTests.swift
git commit -m "feat(app): offer the agent dimension in breakdown blocks"
```

---

### Task 5: Verify end-to-end and cross-check the totals

**Files:** none (verification only).

- [ ] **Step 1: Full build and suite**

Run: `make build && make test`
Expected: build clean; both suites green. Note the before/after test count (7 new tests added: 2 + 3 + 2, plus the Task 3 trio counted once).

- [ ] **Step 2: Confirm totals did not move (independent cross-check)**

Snapshot the corpus, then compare the dump against `jq` and `ccusage`:

```bash
make dump > /tmp/dump-after.txt
cat /tmp/dump-after.txt
```

Expected: all four token counters and the grand total are unchanged from a dump taken before this branch (subagent tokens were already counted). If any number moved, stop and fix — that is a bug, not an expected effect of this change.

- [ ] **Step 3: Cross-check the agent split against `jq`**

Over the same snapshot, group records by `attributionAgent` (a record is `main` when it is not a sidechain and has no `attributionAgent`) and confirm the per-agent `allTokens` sums, and their grand total, match a breakdown-by-agent dump. Reuse the project's existing `jq` cross-check recipe from the snapshot, adding a group key on `.attributionAgent`.

Expected: the `main` bucket plus every subagent-type bucket sum to the same grand total as Step 2.

- [ ] **Step 4: Eyeball it in the app (optional but recommended)**

Run: `make run`, add a breakdown block, set its dimension to **Agent**.
Expected: a `main` row plus one row per subagent type (`general-purpose`, `Explore`, …), ranked descending; the detail modal lists every row.

- [ ] **Step 5: Final branch state**

Leave the branch `feat/subagent-breakdown` for review. Do not merge or push unless asked.

---

## Self-Review

**1. Spec coverage** (design doc → task):
- Extract `attributionAgent` → Task 1. ✅
- `Message.agentLabel` rule `isSidechain ? (attributionAgent ?? "subagent") : "main"` → Task 2. ✅
- `BreakdownDimension.agent` via `totals(…keyedBy: \.agentLabel)` → Task 3. ✅
- Conservation invariant (sum of rows == `total(.allTokens)`) → Task 3 Step 1 test + Task 5 Step 2/3 cross-check. ✅
- UI offers the dimension → Task 4. ✅
- `internal` boundary preserved (`attributionAgent` never public) → Task 1 Step 3 / Task 2 Step 3 keep it non-public. ✅
- No number moves → Task 5. ✅
- Non-goals (per-dispatch, filter, project re-attribution) → not implemented, by design. ✅

**2. Placeholder scan:** No TBD/TODO; every code step shows full code. Task 5 Step 3 reuses "the project's existing `jq` recipe" — this is an existing documented procedure (CLAUDE.md cross-check rule), not an unwritten step.

**3. Type consistency:** `attributionAgent: String?` is the same name on `TranscriptEvent`, `RawLine`, `Message`, and both `makeEvent` factories. `agentLabel` is referenced identically in Task 2 (definition), Task 3 (`keyedBy: \.agentLabel`), and the tests. `BreakdownDimension.agent` is the same case in Metric, Aggregation, Formatting, and tests.
