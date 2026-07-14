## ADDED Requirements

### Requirement: A breakdown card expands into a full-ranking detail modal
A `breakdown` card SHALL offer an expand affordance in its header that opens a detail modal listing the FULL ranked breakdown for that card's dimension, metric and timeframe — every row, not just the card's top-N. The card itself SHALL continue to draw only its configured top-N. The modal SHALL be presented over the dashboard and themed consistently with the settings sheet (window fill, hairline border, accent tint, a themed close control). Exactly one detail modal SHALL be open at a time, and the open/closed state SHALL be transient UI state that is NOT persisted to the layout file.

#### Scenario: The modal lists every row, not just the card's top-N
- **WHEN** a breakdown card configured with a limit smaller than the number of ranked entries is expanded
- **THEN** the modal lists all ranked entries for that dimension, metric and timeframe — a superset of the card's visible rows.

#### Scenario: Rows are ranked and bars scale to the modal's own largest row
- **WHEN** the detail modal renders its list
- **THEN** each row shows a contiguous rank (1, 2, 3, …) in descending value order, its label, its formatted value, and a proportional bar whose width is the row's value over the modal's largest value, so the top row's bar is full width.

#### Scenario: Only one modal is open, and closing clears it
- **WHEN** a breakdown card is expanded and then the modal is closed
- **THEN** opening a card records exactly that card as the expanded target, replacing any previously expanded one, and closing clears the target so no modal is shown.

#### Scenario: Modal state is not persisted
- **WHEN** a breakdown card is expanded
- **THEN** the layout file is not written as a result, because the expanded state is transient UI state, not part of the saved dashboard.
