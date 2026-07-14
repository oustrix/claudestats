# settings-preferences Specification

## Purpose
TBD - created by archiving change add-settings-window. Update Purpose after archive.
## Requirements
### Requirement: Preferences persist to a hand-editable file with graceful defaults
The system SHALL persist user preferences to a pretty-printed `settings.json` in the same Application Support directory as the layout file, and SHALL treat that file as the user's to hand-edit. On a missing file the system SHALL return the built-in defaults and seed the file. On a structurally corrupt file the system SHALL return the built-in defaults without throwing to the interface. Preferences SHALL cover the theme, the refresh interval, and an optional transcripts-root override, and the stored shape SHALL be extendable with further fields without breaking older or newer readers.

#### Scenario: No file yields defaults and seeds one
- **WHEN** no `settings.json` exists
- **THEN** the system returns the default preferences and writes a default file so there is something to edit.

#### Scenario: A corrupt file falls back to defaults
- **WHEN** `settings.json` is not valid JSON
- **THEN** the system returns the default preferences and does not throw to the interface.

#### Scenario: Saved preferences survive a reload
- **WHEN** preferences are saved and then loaded again
- **THEN** the loaded preferences equal the saved ones.

#### Scenario: The file is written for human eyes
- **WHEN** the system writes `settings.json`
- **THEN** the output is pretty-printed so a person can read and edit it by hand.

### Requirement: Unknown or out-of-range preference values coerce to their default
Each preference SHALL decode defensively. An unrecognized theme name, a refresh interval that is not one of the offered values, or an empty transcripts-root path SHALL each resolve to that field's default (or to "no override") rather than discarding the whole file. The theme SHALL be one of `slate` or `claude` defaulting to `slate`; the refresh interval SHALL be one of 15, 30 or 60 seconds defaulting to 30; the transcripts root SHALL be an optional path where absent or empty means the built-in default `~/.claude/projects`.

#### Scenario: An unknown theme name becomes the default
- **WHEN** the stored theme is a string this build does not recognize
- **THEN** the loaded theme is the default `slate`, and the other preferences are preserved.

#### Scenario: An absent transcripts root means the built-in default
- **WHEN** the transcripts root is absent or empty
- **THEN** the system reads transcripts from the built-in default `~/.claude/projects`.

### Requirement: A settings sheet exposes the preferences and a layout reset
The dashboard SHALL present a settings surface as a themed modal sheet reached from a toolbar control — not a separate native settings scene. The sheet SHALL offer, styled from the active theme: an Appearance section to pick the theme, a Data section with a transcripts-folder control (choosing a directory) and a refresh-interval control, and a Layout section with a control that resets the dashboard layout to its built-in default after confirmation. The sheet SHALL NOT offer any cost-related control in this phase.

#### Scenario: The gear opens the settings sheet
- **WHEN** the user activates the settings control in the toolbar
- **THEN** a modal settings sheet appears over the dashboard, painted from the active theme.

#### Scenario: The reset control restores the default layout
- **WHEN** the user confirms the layout reset
- **THEN** the dashboard layout is restored to its built-in default and that default is persisted.

### Requirement: Changing a preference takes effect live and persists
Changing a preference in the settings sheet SHALL update the running app without a relaunch and SHALL persist the change. Selecting a theme SHALL recolor the app immediately. Choosing a transcripts folder SHALL re-scan against the new root. Selecting a refresh interval SHALL retime the periodic refresh. Each change SHALL be written to `settings.json`.

#### Scenario: Selecting a theme recolors the app and persists
- **WHEN** the user selects a different theme
- **THEN** the app recolors to that theme immediately and the choice is written to `settings.json`.

#### Scenario: Choosing a transcripts folder re-scans that folder
- **WHEN** the user chooses a new transcripts folder
- **THEN** the app rebuilds its data source against that folder and re-scans, and the path is persisted.

#### Scenario: Selecting a refresh interval retimes the refresh
- **WHEN** the user selects a different refresh interval
- **THEN** the periodic refresh uses the new interval without a relaunch and the value is persisted.

