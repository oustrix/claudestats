# cost-estimate Specification

## Purpose
TBD - created by archiving change add-cost-estimate. Update Purpose after archive.
## Requirements
### Requirement: Pricing persists to a hand-editable file with graceful defaults
The system SHALL persist per-model pricing to a pretty-printed `pricing.json` in the same Application Support directory as the layout and settings files, and SHALL treat that file as the user's to hand-edit. Rates SHALL be expressed in US dollars per 1,000,000 tokens for the four token kinds — input, output, cacheWrite (cache creation), cacheRead — keyed by model family. On a missing file the system SHALL return the bundled default rates and seed the file. On a structurally corrupt file the system SHALL return the bundled default rates without throwing to the interface.

#### Scenario: No file yields defaults and seeds one
- **WHEN** no `pricing.json` exists
- **THEN** the system returns the bundled default pricing and writes a default file so there is something to edit.

#### Scenario: A corrupt file falls back to defaults
- **WHEN** `pricing.json` is not valid JSON
- **THEN** the system returns the bundled default pricing and does not throw to the interface.

#### Scenario: Saved pricing survives a reload
- **WHEN** pricing is saved and then loaded again
- **THEN** the loaded pricing equals the saved pricing.

#### Scenario: The file is written for human eyes
- **WHEN** the system writes `pricing.json`
- **THEN** the output is pretty-printed so a person can read and edit it by hand.

### Requirement: Model names match a family by prefix normalization
The system SHALL match a transcript model id to a pricing family by normalizing it — taking the family token that follows the `claude-` prefix (so `claude-sonnet-4-6`, `claude-sonnet-5`, and a dated `claude-sonnet-…` snapshot all resolve to the `sonnet` family). A model id that does not begin with `claude-` SHALL have no family and therefore no rate.

#### Scenario: Dated and undated ids share a family
- **WHEN** the model ids `claude-haiku-4-5` and `claude-haiku-4-5-20251001` are normalized
- **THEN** both resolve to the `haiku` family and are priced at the same rate.

#### Scenario: A non-Claude id has no rate
- **WHEN** a model id such as `gpt-5.5` or `<synthetic>` is normalized
- **THEN** it resolves to no family and is treated as unpriced.

### Requirement: Cost is estimated from deduplicated messages, per model, never silently zero
The system SHALL provide a cost estimate as an aggregation entry point that takes raw transcript events, deduplicates them into messages by the same rule as every token counter, and sums, over the messages in the timeframe, each message's tokens-by-kind times its model's rate-by-kind. The result SHALL carry the estimated dollar total, a per-model breakdown, and the set of model ids that had no rate. An unpriced model SHALL NOT be silently costed at zero: it SHALL contribute nothing to the total and SHALL be surfaced in the returned set of unpriced model ids. Cost SHALL NOT be modelled as a token metric that flows through the token-sum machinery.

#### Scenario: Exact cost for known tokens and known rates
- **WHEN** the cost is computed over messages with known token counts under known per-model rates
- **THEN** the returned total equals the hand-computed dollar sum to the cent.

#### Scenario: An unpriced model is surfaced, not costed at zero
- **WHEN** a message's model has no matching rate
- **THEN** that message adds nothing to the total and its model id appears in the returned set of unpriced models.

#### Scenario: Cost deduplicates like the token counters
- **WHEN** a response is written across several streaming lines and then costed
- **THEN** its tokens are counted once, matching the deduplicated token total, not the inflated per-line sum.

### Requirement: Sessions can carry an estimated cost
The system SHALL let the sessions aggregation accept an optional pricing and, when supplied, attach to each session an estimated cost summed per the model of each of its messages. Without a pricing, a session's estimated cost SHALL be absent.

#### Scenario: A session sums the cost of its messages
- **WHEN** sessions are aggregated with a pricing over messages of a known model and known tokens
- **THEN** each session's estimated cost equals the hand-computed dollar sum of its messages.

#### Scenario: No pricing means no session cost
- **WHEN** sessions are aggregated without a pricing
- **THEN** each session's estimated cost is absent.

### Requirement: A cost estimate is shown as a KPI card and a per-session column, gated by a preference
The dashboard SHALL offer a cost estimate as a KPI card labelled as an estimate — currency-formatted in the accent colour with copy making clear it is an estimate, not a bill — and as a per-session cost column. A `showCost` preference (default true, persisted to `settings.json`, forward- and backward-compatible) SHALL gate both: when off, the dashboard SHALL hide cost blocks and the per-session cost column; when on, it SHALL show them. The default dashboard layout SHALL include the cost card as the third of four span-3 KPI cards (input+output, requests, cost estimate, cache read). Toggling `showCost` SHALL NOT inject a cost block into a layout that has none; it only shows or hides cost blocks already present.

#### Scenario: The default layout includes the cost card third
- **WHEN** a fresh default layout is created
- **THEN** its KPI row is four span-3 cards — input+output, requests, cost estimate, cache read — in that order.

#### Scenario: Turning cost off hides the cost blocks and column
- **WHEN** the user turns `showCost` off
- **THEN** the dashboard hides cost blocks and the per-session cost column, and persists the choice.

#### Scenario: Turning cost on does not inject a card into a cost-less layout
- **WHEN** `showCost` is turned on over a layout that contains no cost block
- **THEN** no cost card appears, and the user can add one from the block catalog.

### Requirement: The audit tool reports the cost estimate
The `make dump` auditing tool SHALL print the estimated total cost, and the per-model cost, alongside the existing aggregates, so the dollar figure can be cross-checked independently.

#### Scenario: Dump prints cost
- **WHEN** the dump tool runs over a corpus
- **THEN** it prints the estimated total cost and the per-model cost.

