## ADDED Requirements

### Requirement: Weekly bucketing in the local timezone
The system SHALL support a `week` bucket that attributes each deduplicated message to the local calendar week containing its timestamp. A week SHALL begin on the calendar's configured first weekday. Weekly totals for a metric SHALL sum to that metric's total over the same period.

#### Scenario: A message is attributed to its local week
- **WHEN** the calendar's first weekday is Monday and a message has a timestamp on a Wednesday
- **THEN** the message is attributed to the week beginning on the preceding Monday.

#### Scenario: Weekly totals reconcile with the grand total
- **WHEN** weekly totals for a metric are summed over a period
- **THEN** the result equals the metric computed over all messages in that period.

### Requirement: Heatmap aggregation over a fixed window
The system SHALL provide a pure aggregation that, given a metric and a bucket of `day` or `week`, returns one dense cell per bucket across a fixed window of the last 52 weeks, zero-filled across buckets with no activity. The window SHALL be aligned to whole local weeks ending with the week containing `now`, and SHALL be independent of any timeframe. `now` and the calendar SHALL be supplied by the caller, never read from the clock inside the function. A bucket other than `week` SHALL be treated as `day`.

#### Scenario: The window is dense and fixed
- **WHEN** heatmap aggregation runs with bucket `day`
- **THEN** it returns one cell for every local day in the last 52 weeks, including days with no usage as zero-valued cells.

#### Scenario: The window ignores timeframe
- **WHEN** heatmap aggregation runs
- **THEN** the returned window spans the last 52 weeks regardless of any timeframe the caller might otherwise apply.

#### Scenario: Heatmap totals reconcile with the total over the window
- **WHEN** the values of all heatmap cells are summed
- **THEN** the result equals the metric's total computed over the same day range.

#### Scenario: An unsupported bucket falls back to day
- **WHEN** heatmap aggregation runs with bucket `hour`
- **THEN** it returns daily cells, as though bucket `day` had been requested.

### Requirement: Heatmap intensity levels by quantile
The system SHALL assign each heatmap cell an intensity level. A cell whose value is zero SHALL have level 0. Non-zero values SHALL be divided into up to four levels (1 through 4) by quantiles of the non-zero distribution, so that extreme outliers do not push typical values into the lowest level. When there are fewer distinct non-zero values than four, the system SHALL use fewer levels rather than forcing four. The system SHALL expose the quantile cut points so a legend can be drawn.

#### Scenario: Outliers do not flatten the scale
- **WHEN** one day's value is far larger than all others and the rest are moderate and varied
- **THEN** the moderate days occupy the middle levels rather than all collapsing to level 1.

#### Scenario: An empty day is level zero
- **WHEN** a day has no usage
- **THEN** its cell has level 0, distinct from any non-zero level.

#### Scenario: Few distinct values use fewer levels
- **WHEN** the window contains only three distinct non-zero values
- **THEN** the system assigns at most three non-zero levels rather than forcing four.
