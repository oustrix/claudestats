## MODIFIED Requirements

### Requirement: Closed block catalog
The system SHALL render the dashboard as an ordered list of blocks, each of exactly one type from a closed catalog: `bigNumber` (metric, timeframe), `timeSeries` (metric, timeframe, bucket), `breakdown` (dimension, metric, timeframe, limit), `sessionList` (timeframe, limit) and `heatmap` (metric, bucket). The system SHALL NOT offer a free-form query language or arbitrary metric-dimension composition beyond this catalog.

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

#### Scenario: A heatmap block shades a calendar grid by intensity
- **WHEN** a `heatmap` block is configured with metric `inputOutput` and bucket `day`
- **THEN** it renders a calendar grid over the fixed heatmap window, one cell per local calendar day including days with zero usage
- **AND** each cell is shaded by the intensity level assigned to its value.

#### Scenario: A heatmap block ignores its timeframe
- **WHEN** a `heatmap` block is configured with any `timeframe`
- **THEN** the block draws the fixed heatmap window regardless of the configured timeframe
- **AND** the block's header labels the fixed window rather than the timeframe.

### Requirement: Layout editing
The system SHALL let the user add a block by choosing its type, remove a block, reorder blocks, and edit a block's parameters. Reordering SHALL be by direct manipulation of the block list. The parameter editor SHALL offer a block only the parameters its type uses, and for `bucket` SHALL offer only the buckets that type supports: `day`/`hour` for `timeSeries`, `day`/`week` for `heatmap`.

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

#### Scenario: The editor offers each block type only its supported buckets
- **WHEN** the user edits a `heatmap` block's bucket
- **THEN** the editor offers `day` and `week` only, and does not offer `hour`.

#### Scenario: A hand-edited heatmap with an unsupported bucket is not skipped
- **WHEN** the layout file contains a `heatmap` block whose bucket is `hour`
- **THEN** the system renders the heatmap by day rather than skipping it or reporting an unreadable parameter.
