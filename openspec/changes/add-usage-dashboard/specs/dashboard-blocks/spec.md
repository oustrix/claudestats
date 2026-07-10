## ADDED Requirements

### Requirement: Closed block catalog
The system SHALL render the dashboard as an ordered list of blocks, each of exactly one type from a closed catalog: `bigNumber` (metric, timeframe), `timeSeries` (metric, timeframe, bucket), `breakdown` (dimension, metric, timeframe, limit) and `sessionList` (timeframe, limit). The system SHALL NOT offer a free-form query language or arbitrary metric-dimension composition beyond this catalog.

#### Scenario: A big-number block shows one metric
- **WHEN** a `bigNumber` block is configured with metric `inputOutput` and timeframe `last7Days`
- **THEN** it displays the sum of input and output tokens over the last seven local days.

#### Scenario: A time-series block plots a metric over days
- **WHEN** a `timeSeries` block is configured with bucket `day`
- **THEN** it plots one point per local calendar day in the timeframe, including days with zero usage.

#### Scenario: A breakdown block ranks a dimension
- **WHEN** a `breakdown` block is configured with dimension `model` and limit `5`
- **THEN** it displays at most five models ranked by the configured metric, descending.

#### Scenario: A session-list block lists recent sessions
- **WHEN** a `sessionList` block is configured with timeframe `last7Days` and limit `10`
- **THEN** it lists at most ten sessions that started within the last seven local days, newest first, each showing its project, start time, duration and token totals.

### Requirement: Blocks derive their data from events
Each block SHALL compute what it renders as a pure function of the loaded events and its own parameters. Blocks SHALL NOT hold their own cached copies of aggregated data.

#### Scenario: A parameter change re-renders from source events
- **WHEN** a block's metric is changed from `inputOutput` to `cacheRead`
- **THEN** the block recomputes from the loaded events without a reload from disk.

#### Scenario: New events propagate to every block
- **WHEN** a refresh replaces the loaded events
- **THEN** every block re-renders from the new events.

### Requirement: Layout editing
The system SHALL let the user add a block by choosing its type, remove a block, reorder blocks, and edit a block's parameters. Reordering SHALL be by direct manipulation of the block list.

#### Scenario: A block is added
- **WHEN** the user adds a block of a chosen type
- **THEN** the block appears at the end of the list with default parameters for its type
- **AND** the layout is persisted.

#### Scenario: A block is removed
- **WHEN** the user removes a block
- **THEN** the block disappears from the dashboard and the layout is persisted.

#### Scenario: Blocks are reordered
- **WHEN** the user drags a block to a new position
- **THEN** the dashboard renders the blocks in the new order and the layout is persisted.

#### Scenario: A block is reconfigured
- **WHEN** the user changes a block's metric, dimension, timeframe, bucket or limit
- **THEN** the block re-renders with the new parameters and the layout is persisted.

### Requirement: Layout persistence and versioning
The system SHALL persist the block list to `~/Library/Application Support/ClaudeStats/layout.json` as a JSON document carrying a `version` field and a `blocks` array. The document SHALL be human-readable and hand-editable.

#### Scenario: Layout survives a restart
- **WHEN** the user configures a dashboard and quits the application
- **THEN** relaunching the application restores the same blocks in the same order with the same parameters.

#### Scenario: No layout file exists yet
- **WHEN** the application launches and no layout file is present
- **THEN** the system renders a default layout and writes it to disk.

#### Scenario: A block of unknown type is skipped, not fatal
- **WHEN** the layout file contains a block whose `type` this build does not recognise
- **THEN** the system renders the remaining blocks
- **AND** displays a notice naming the skipped block type
- **AND** does not crash or overwrite the file.

#### Scenario: A malformed layout file is preserved and replaced
- **WHEN** the layout file is not valid JSON or fails to decode
- **THEN** the system moves it aside to `layout.json.bak`
- **AND** renders the default layout
- **AND** informs the user that the layout was reset.

### Requirement: Data quality is visible
The system SHALL display the number of parsed records and the number of skipped lines from the most recent scan, and SHALL surface load failures rather than rendering zeros.

#### Scenario: Skipped lines are shown
- **WHEN** the most recent scan skipped one or more malformed lines
- **THEN** the interface shows both the parsed-record count and the skipped-line count.

#### Scenario: Missing transcript directory is explained
- **WHEN** `~/.claude/projects/` does not exist
- **THEN** the interface explains that no transcripts were found
- **AND** does not display token totals of zero as though they had been measured.

### Requirement: Refresh behaviour
The system SHALL load transcripts on launch, on an explicit refresh action, and on a 30-second timer while the window is open. Loading SHALL happen off the main thread, and the interface SHALL indicate that a load is in progress.

#### Scenario: The window loads on launch
- **WHEN** the application launches
- **THEN** transcripts are read and the dashboard renders the result.

#### Scenario: The timer skips unchanged data
- **WHEN** the 30-second timer fires and no transcript file changed
- **THEN** the dashboard is left untouched and no parsing occurs.

#### Scenario: The interface stays responsive during a load
- **WHEN** transcripts are being read
- **THEN** the interface remains responsive and indicates the in-progress load.
