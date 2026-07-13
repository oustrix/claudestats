# project-integrity Specification

## Purpose
Keep the shipped application free of third-party code. External packages are allowed, but confined
to test targets and never linked into the distributed `.app` — the boundary drawn the first time an
external dependency (ViewInspector, test-only) entered the project.

## Requirements
### Requirement: Dependency isolation
The shipped application SHALL link no external, third-party dependencies. External dependencies MAY be used, but only by test targets, and SHALL NOT be reachable from any target compiled into the distributed `.app`. This draws an explicit line the first time an external package enters the project: the app stays dependency-free even as its tests do not.

#### Scenario: The shipped bundle links only first-party code
- **WHEN** the `ClaudeStats.app` bundle is assembled
- **THEN** its executable links only Apple frameworks and the project's own targets (`ClaudeStatsCore`, `ClaudeStatsAppLib`)
- **AND** no third-party package is linked into the bundle.

#### Scenario: A test-only dependency stays out of shipped code
- **WHEN** a test target depends on an external package such as a view-inspection library
- **THEN** none of `ClaudeStatsCore`, `ClaudeStatsAppLib`, `ClaudeStatsApp`, or `ClaudeStatsDump` depends on that package
- **AND** removing the package would break only the test targets, never the build of the app.

