# usage-aggregation Specification

## Purpose
TBD - created by archiving change add-usage-dashboard. Update Purpose after archive.
## Requirements
### Requirement: Usage metrics
The system SHALL expose four token metrics — `inputOutput` (input plus output), `cacheRead`, `cacheCreation` and `allTokens` (the sum of all four counters) — and one count metric, `requests` (the number of deduplicated messages). Every metric SHALL be computed from deduplicated messages.

#### Scenario: Input-output metric excludes cache counters
- **WHEN** the `inputOutput` metric is computed
- **THEN** it equals the sum of input tokens and output tokens across deduplicated messages
- **AND** it does not include cache-read or cache-creation tokens.

#### Scenario: All-tokens metric includes every counter
- **WHEN** the `allTokens` metric is computed
- **THEN** it equals the sum of input, output, cache-creation and cache-read tokens across deduplicated messages.

#### Scenario: Requests metric counts messages, not lines
- **WHEN** the `requests` metric is computed over a message written as three content-block lines
- **THEN** it counts one request.

### Requirement: Daily bucketing in the local timezone
The system SHALL attribute each deduplicated message to the calendar day of its own timestamp, converted to the machine's current local timezone. Daily totals for a metric SHALL sum to that metric's total over the same period.

#### Scenario: An evening message stays on its local day
- **WHEN** a message has timestamp `2026-07-02T21:30:00Z` and the local timezone is UTC+3
- **THEN** the message is attributed to `2026-07-03` local time.

#### Scenario: Daily totals reconcile with the grand total
- **WHEN** daily totals for a metric are summed over a period
- **THEN** the result equals the metric computed over all messages in that period.

#### Scenario: A session crossing midnight splits its tokens
- **WHEN** a session starts at `23:40` local time and ends at `01:20` the next local day
- **THEN** messages before midnight are attributed to the first day
- **AND** messages after midnight are attributed to the second day.

### Requirement: Session identity and attribution
The system SHALL group events by `sessionID`. Each session SHALL be attributed to the working directory and the local calendar day of its earliest event. A session SHALL expose its start time, end time, message count and token totals.

#### Scenario: A session is attributed to its start day
- **WHEN** a session starts at `23:40` local time and ends the next day
- **THEN** the session counts towards the first day's session count
- **AND** it does not count towards the second day's session count.

#### Scenario: A session whose working directory changes
- **WHEN** the events of one session carry more than one distinct `cwd`
- **THEN** the session is attributed to the `cwd` of its earliest event.

#### Scenario: Session boundaries come from event timestamps
- **WHEN** a session's events are aggregated
- **THEN** its start time is the earliest event timestamp and its end time is the latest.

### Requirement: Project identity and display
The system SHALL identify a project by the `cwd` of a session's earliest event, using the full path as the identity. The system SHALL display the final path component as the project name and SHALL make the full path available, with the home directory rendered as `~`. The system SHALL NOT derive project identity from the encoded directory name under `~/.claude/projects/`.

#### Scenario: A nested project is named by its last component
- **WHEN** a session's working directory is `/Users/me/go/projects/gitlab.example.com/ob/snitch`
- **THEN** the project name displays as `snitch`
- **AND** the full path is available as `~/go/projects/gitlab.example.com/ob/snitch`.

#### Scenario: The home directory is its own project
- **WHEN** a session's working directory is the user's home directory
- **THEN** the project name displays as `~`.

#### Scenario: Identically named directories stay distinct
- **WHEN** two sessions run in `/a/snitch` and `/b/snitch`
- **THEN** the system reports two projects, each retaining its full path.

### Requirement: Breakdown by dimension
The system SHALL aggregate a chosen metric by `model`, by `project` or by `tool`, sorted descending by value, limited to a caller-supplied count. Breakdown by `tool` SHALL report tool-invocation counts rather than tokens, because tokens are not attributable to individual tool calls.

#### Scenario: Breakdown by model reports token metrics
- **WHEN** a breakdown by `model` is requested for the `inputOutput` metric
- **THEN** each model's deduplicated input plus output tokens are reported, sorted descending.

#### Scenario: Unknown models are reported verbatim
- **WHEN** an event carries a model identifier the system does not recognise
- **THEN** the model appears in the breakdown under its raw identifier, without classification and without being dropped.

#### Scenario: Breakdown by tool counts invocations
- **WHEN** a breakdown by `tool` is requested
- **THEN** each tool name is reported with its total number of `tool_use` blocks
- **AND** the requested token metric does not affect the result.

#### Scenario: Limit truncates the tail
- **WHEN** a breakdown is requested with a limit smaller than the number of distinct values
- **THEN** only the highest-valued entries up to the limit are returned.

### Requirement: Timeframe filtering
The system SHALL filter events by timeframe before aggregation, supporting `last7Days`, `last30Days` and `allTime`. Relative timeframes SHALL be evaluated against local calendar days.

#### Scenario: Last seven days includes today
- **WHEN** the `last7Days` timeframe is applied
- **THEN** events from today and the six preceding local calendar days are included.

#### Scenario: All-time applies no filter
- **WHEN** the `allTime` timeframe is applied
- **THEN** every event is included.

### Requirement: Aggregates are pure and reusable
Aggregation SHALL be implemented as pure functions of events and parameters, with no dependency on the user interface, and SHALL be reachable from a command-line entry point that prints the aggregates for cross-checking against independent tools.

#### Scenario: Aggregation does not depend on the UI
- **WHEN** the core library is compiled for tests
- **THEN** aggregation functions are usable without importing any UI framework.

#### Scenario: Aggregates can be dumped to stdout
- **WHEN** the `dump` command is run
- **THEN** the system prints total tokens per counter, per-model and per-project breakdowns, and the count of parsed and skipped records
- **AND** the printed numbers are produced by the same functions the dashboard uses.

