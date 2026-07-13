## ADDED Requirements

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
