# dashboard-blocks Specification

## Purpose
The dashboard the app presents: an ordered list of blocks drawn from a closed catalog (`bigNumber`, `timeSeries`, `breakdown`, `sessionList`, `heatmap`), each a pure view over the loaded events and its own parameters. This capability governs what block types exist and what they render, how the user adds, removes, reorders and configures them, how the layout is persisted and versioned so a hand-edited or newer-build file is tolerated rather than fatal, and how scan quality and refreshes are surfaced. The catalog is closed on purpose: an open one drifts into a query builder, and a bad query builder is worse than a good dashboard.
## Requirements
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

### Requirement: Blocks derive their data from events
Each block SHALL compute what it renders as a pure function of the loaded events and its own parameters. Blocks SHALL NOT hold their own cached copies of aggregated data.

#### Scenario: A parameter change re-renders from source events
- **WHEN** a block's metric is changed from `inputOutput` to `cacheRead`
- **THEN** the block recomputes from the loaded events without a reload from disk.

#### Scenario: New events propagate to every block
- **WHEN** a refresh replaces the loaded events
- **THEN** every block re-renders from the new events.

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
- **AND** displays a notice naming the unrecognised type
- **AND** does not crash or overwrite the file.

#### Scenario: A block with an unreadable parameter is distinguished from an unknown type
- **WHEN** a block's `type` is recognised but one of its parameter values is not
- **THEN** the system skips that block and reports it as having unreadable parameters, naming its type
- **AND** does not report the type itself as unknown, because a user told their supported block type is unknown will look for a new release instead of for their typo.

#### Scenario: A malformed layout file is preserved and replaced
- **WHEN** the layout file is not valid JSON or fails to decode
- **THEN** the system moves it aside to `layout.json.bak`, or to the next free `layout.json.bakN` when a backup already exists
- **AND** renders the default layout
- **AND** informs the user that the layout was reset.

#### Scenario: A reset that cannot be written to disk is not announced as done
- **WHEN** the layout file is malformed and the backup or the replacement cannot be written
- **THEN** the system reports the persistence failure alongside the reset
- **AND** does not claim the file was moved aside when it was not.

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

### Requirement: Blocks lay out on a twelve-column grid
Each block SHALL carry a `span` between 1 and 12 (inclusive) describing how many of twelve columns it occupies. The dashboard SHALL lay blocks out left-to-right in the authored order, greedily packing consecutive blocks into a row while their spans sum to at most twelve, and starting a new row when the next block would overflow. A block SHALL be sized `span`/12 of the row's available width. The block order the user authored SHALL remain authoritative — the layout SHALL NOT reorder blocks to fill gaps.

#### Scenario: Blocks pack several to a row
- **WHEN** three consecutive blocks have spans 4, 4 and 4
- **THEN** they render side by side on one row, each one third of the row width.

#### Scenario: A row overflow starts a new row
- **WHEN** a block with span 12 follows a full row of three span-4 blocks
- **THEN** the span-12 block renders on its own new row, full width.

#### Scenario: Authored order is preserved
- **WHEN** blocks are laid out on the grid
- **THEN** they appear in the same order the layout lists them, never reordered to pack more tightly.

### Requirement: A layout without spans decodes to full-width blocks
The `span` field SHALL be migration-safe. When the layout file omits `span` for a block, the system SHALL decode that block with `span` equal to 12, so a layout written before spans existed renders one full-width block per row exactly as it did before. A hand-edited `span` outside 1–12 SHALL be coerced into range rather than crashing or corrupting the layout. New layouts SHALL always write an explicit `span`.

#### Scenario: An older layout file has no spans
- **WHEN** the layout file contains a block with no `span` field
- **THEN** the system decodes it with `span` 12 and renders it full width.

#### Scenario: A new layout round-trips its spans
- **WHEN** a layout with explicit spans is encoded and decoded again
- **THEN** every block's `span` is preserved unchanged.

### Requirement: The big-number block shows a period-over-period delta
A `bigNumber` block SHALL display, alongside its headline figure and a timeframe label, a delta comparing the current timeframe total to the immediately preceding window of equal length. A positive delta SHALL be visually distinguished from a negative one. When the timeframe is unbounded (`allTime`) or the preceding window's total is zero, the block SHALL show no delta rather than a misleading arrow or a division by zero. The delta SHALL be derived from the same aggregation the headline uses, over the loaded events, with no new counting rule.

#### Scenario: A bounded timeframe with prior activity shows a delta
- **WHEN** a `bigNumber` block with timeframe `last7Days` has a nonzero total in both the current seven days and the preceding seven days
- **THEN** it shows the percentage change from the preceding window to the current one, marking an increase distinctly from a decrease.

#### Scenario: No preceding activity shows no delta
- **WHEN** the preceding equal-length window has a total of zero
- **THEN** the block shows no delta percentage and no arrow.

#### Scenario: An unbounded timeframe shows no delta
- **WHEN** a `bigNumber` block's timeframe is `allTime`
- **THEN** the block shows no delta, because there is no bounded preceding window to compare against.

### Requirement: The dashboard is painted from a dark theme
The dashboard SHALL paint its window, toolbar region and block cards from a theme of semantic colour roles rather than from the system accent colour, and SHALL NOT follow the system light/dark appearance. Every block SHALL draw its accents, text and surfaces from the active theme's roles.

#### Scenario: Surfaces come from the theme
- **WHEN** the dashboard renders
- **THEN** the content background, toolbar region and card fills and borders are the active theme's roles, and block accents use the theme's accent rather than the system tint.

#### Scenario: The appearance stays dark regardless of system setting
- **WHEN** the system is set to light appearance
- **THEN** the dashboard remains dark, painted by its theme.

