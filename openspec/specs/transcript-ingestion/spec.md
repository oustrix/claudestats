# transcript-ingestion Specification

## Purpose
TBD - created by archiving change add-usage-dashboard. Update Purpose after archive.
## Requirements
### Requirement: Transcript discovery
The system SHALL discover Claude Code transcripts by recursively scanning `~/.claude/projects/` for files with a `.jsonl` extension. The transcript root SHALL be injectable so that tests can supply a fixture directory.

#### Scenario: Transcripts are found under the project root
- **WHEN** the transcript root contains project subdirectories holding `.jsonl` files
- **THEN** the system reads every `.jsonl` file found at any depth
- **AND** files without a `.jsonl` extension are ignored.

#### Scenario: Transcript root does not exist
- **WHEN** the transcript root is missing
- **THEN** the system reports an empty-state condition distinguishable from "zero usage"
- **AND** the system does not crash and does not report token totals of zero as if they were measured.

#### Scenario: Transcript root is empty
- **WHEN** the transcript root exists but contains no `.jsonl` files
- **THEN** the system returns an empty event list with zero skipped lines.

### Requirement: Event extraction
The system SHALL parse each JSONL line and retain only records with `type: "assistant"` that carry a `message.usage` object. For each retained record the system SHALL extract `message.id`, `requestId`, `timestamp`, `sessionId`, `cwd`, `gitBranch`, `message.model`, `isSidechain`, the four token counters, and the `name` of every `tool_use` content block.

#### Scenario: An assistant record is extracted
- **WHEN** a line has `type: "assistant"` and a `message.usage` object
- **THEN** the system produces one event carrying the message identifier, request identifier, timestamp, session identifier, working directory, git branch, model, sidechain flag, token counters and tool names.

#### Scenario: Non-assistant records are ignored
- **WHEN** a line has a `type` other than `"assistant"`, such as `"user"`, `"attachment"`, `"system"` or `"file-history-snapshot"`
- **THEN** the system produces no event for that line.

#### Scenario: Synthetic records are excluded
- **WHEN** an assistant record has `message.model` equal to `"<synthetic>"`
- **THEN** the system produces no event for that line, because no API call occurred.

#### Scenario: Subagent records are retained
- **WHEN** an assistant record has `isSidechain: true`
- **THEN** the system produces an event with the sidechain flag preserved
- **AND** the event participates in token and tool statistics.

#### Scenario: Timestamps are parsed as instants
- **WHEN** a record carries an ISO-8601 timestamp such as `2026-07-02T09:43:05.761Z`
- **THEN** the system parses it as an absolute instant, preserving sub-second precision, without applying a timezone offset at parse time.

### Requirement: Malformed input is skipped and counted
The system SHALL skip any line that is not valid JSON or that lacks required fields, SHALL count each skipped line, and SHALL report the count alongside the parsed events. The system SHALL NOT abort a file or the whole scan because of a malformed line.

#### Scenario: A truncated final line is skipped
- **WHEN** a transcript is being appended to and its final line is cut mid-write
- **THEN** the system skips that line, increments the skipped-line counter, and returns all preceding events from the same file.

#### Scenario: A malformed line in the middle of a file is skipped
- **WHEN** a line in the middle of a transcript is not valid JSON
- **THEN** the system skips that line and continues parsing subsequent lines in the same file.

#### Scenario: Skipped lines are reported, not hidden
- **WHEN** any line was skipped during a scan
- **THEN** the reported result carries both the number of parsed records and the number of skipped lines.

### Requirement: Token usage is deduplicated per message
The system SHALL treat all events sharing the same `(messageID, requestID)` pair as one billable API response and SHALL count its token usage exactly once, taking the token counters of the event bearing a `stop_reason`. Where no such event exists, the last event's counters SHALL be used. The response's timestamp, session and working directory SHALL come from the **first** such event.

#### Scenario: One message split across content blocks
- **WHEN** an assistant message is written as several JSONL lines, one per content block
- **THEN** the system counts that message's input, output, cache-creation and cache-read tokens exactly once.

#### Scenario: Streaming placeholders are superseded by the line bearing a stop reason
- **WHEN** the intermediate lines of a response report a placeholder `output_tokens` of 1 and the line carrying a `stop_reason` reports the real count
- **THEN** the system counts the token counters of the line carrying the `stop_reason`
- **AND** it does so regardless of where that line appears among the response's events
- **AND** the response is attributed to the timestamp and working directory of its first line.

#### Scenario: An interrupted response has no stop reason
- **WHEN** no line of a response carries a `stop_reason`
- **THEN** the system counts the token counters of that response's last event.

#### Scenario: Distinct messages are not merged
- **WHEN** two events carry different `messageID` values
- **THEN** the system counts both messages' token usage.

### Requirement: Tool invocations are not deduplicated
The system SHALL count one tool invocation per `tool_use` content block across all lines, including lines belonging to the same message.

#### Scenario: Two tool calls in one message
- **WHEN** an assistant message spans two lines, each containing one `tool_use` block
- **THEN** the system counts two tool invocations
- **AND** the system still counts that message's tokens only once.

### Requirement: Change detection without reparsing
The system SHALL determine whether any transcript changed by comparing each file's modification time and size against the previous scan, and SHALL skip parsing entirely when nothing changed. An explicit refresh SHALL bypass this comparison.

#### Scenario: No file changed since the last scan
- **WHEN** a periodic refresh runs and every file's modification time and size are unchanged
- **THEN** the system performs no parsing and leaves the previous events in place.

#### Scenario: A file was appended to
- **WHEN** a periodic refresh runs and at least one file's modification time or size differs
- **THEN** the system reparses the transcripts and replaces the event list.

#### Scenario: Explicit refresh always reparses
- **WHEN** the user requests a refresh
- **THEN** the system reparses regardless of modification times.

