# GoldenZone STR — Phase 1 Implementation Specification v1.0

## Phase 1: Data Layer + Data Validator + Time Engine

**Project:** GoldenZone STR  
**Platform:** MetaTrader 5 / MQL5  
**Phase:** 1 of 18  
**Status:** Implementation specification  
**Research mode:** Historical data / deterministic simulation only

---

# 1. Phase Objective

Phase 1 builds the trusted foundation for all later GoldenZone STR research.

The phase must provide:

1. Historical M1/M5 data access.
2. Optional M15 data access for later phases.
3. Dataset validation.
4. Timezone normalization.
5. Broker-time, UTC, and New-York-time conversion.
6. DST handling.
7. Session-window evaluation.
8. Deterministic output.
9. Diagnostic logging.
10. A testable interface that later phases can consume.

No strategy logic is implemented in Phase 1.

---

# 2. Strict Scope

## IN SCOPE

- Data access
- Data normalization
- Data validation
- Timestamp conversion
- DST state
- Session-window calculation
- Dataset metadata
- Diagnostics
- Logging
- Deterministic test harness
- Phase 1 report

## OUT OF SCOPE

Do NOT implement:

- Swing detection
- Pivot logic
- Leg detection
- Break detection
- Fibonacci
- Entry logic
- SL/TP
- Break-even
- Trade simulation
- Filters
- VWAP
- News logic
- M15 structure logic
- Parameter optimization
- Walk-forward
- Monte Carlo
- Live order placement
- Position management
- Any future Phase 2+ strategy behavior

If a later phase requires an interface, create only the minimal interface/stub required by architecture. Do not implement the later phase itself.

---

# 3. Critical Design Principle

The Phase 1 code must be reusable by both:

- the future historical Research Adapter;
- the future Execution Adapter.

However, Phase 1 itself must not execute live trades or submit orders.

The Time Engine must also be independent from Strategy Logic.

The strategy must never need to know how DST is calculated.

---

# 4. Recommended Project Structure

Claude may adapt the exact filenames to the existing repository, but the architecture must remain equivalent.

Recommended:

```text
GoldenZoneSTR/
│
├── Experts/
│   └── GoldenZoneSTR_Research.mq5
│
├── Include/
│   └── GoldenZoneSTR/
│       ├── Core/
│       │   ├── GZ_Types.mqh
│       │   ├── GZ_Config.mqh
│       │   └── GZ_Constants.mqh
│       │
│       ├── Data/
│       │   ├── GZ_DataProvider.mqh
│       │   ├── GZ_DataValidator.mqh
│       │   └── GZ_DatasetInfo.mqh
│       │
│       ├── Time/
│       │   ├── GZ_TimeEngine.mqh
│       │   ├── GZ_DST.mqh
│       │   └── GZ_Session.mqh
│       │
│       └── Diagnostics/
│           ├── GZ_Logger.mqh
│           └── GZ_TestHarness.mqh
│
└── Docs/
    └── Phase1_TestReport.md
```

Claude may use a different structure if the existing repository already has conventions. It must explain any deviation before applying it.

---

# 5. Core Types

Create strongly typed structures/enums where appropriate.

## Data Validation Status

```text
UNKNOWN
VALID
VALID_WITH_WARNINGS
INVALID
```

## Time Mode

```text
BROKER
UTC
NEW_YORK
```

## DST Mode

```text
AUTO
FIXED
DISABLED
```

## Session Result

```text
INSIDE
OUTSIDE
```

## Severity

```text
INFO
WARNING
ERROR
FATAL
```

---

# 6. Dataset Metadata

Create a dataset information structure containing at minimum:

```text
Symbol
Execution Timeframe
Structure Timeframe
Optional Context Timeframe
Start Timestamp
End Timestamp
Broker Timezone Offset/Metadata
Total Bars
First Bar
Last Bar
Missing Bar Count
Duplicate Count
Invalid OHLC Count
Timestamp Error Count
Spread Availability
Tick Volume Availability
Real Volume Availability
Validation Status
Warnings
Errors
```

The exact implementation may use MQL5 structs/classes as appropriate.

---

# 7. Data Provider

Implement a clean data-access abstraction.

Required capabilities:

- Load/copy historical M1 data.
- Load/copy historical M5 data.
- Support optional M15 retrieval.
- Respect requested start/end timestamps.
- Return chronological data.
- Expose bar count.
- Expose timestamp/ OHLC / volume / spread information where available.

The provider must not implement trading logic.

---

# 8. Data Normalization

Before validation:

1. Ensure chronological ordering.
2. Preserve source timestamps.
3. Do not silently fabricate missing candles.
4. Do not silently delete suspicious candles.
5. Do not modify market prices to make data pass validation.
6. Record any normalization action in diagnostics.

If data is incomplete, report it.

---

# 9. OHLC Validation

For every bar:

```text
High >= max(Open, Close)
Low  <= min(Open, Close)
High >= Low
```

Also reject impossible numeric states such as:

- NaN/infinite values where detectable;
- non-positive price where the symbol/data source makes that invalid;
- invalid timestamps.

Invalid bars must be counted and reported.

Do not silently repair them.

---

# 10. Timestamp Validation

Verify:

- chronological ordering;
- no duplicate timestamps;
- expected timeframe spacing;
- start/end range correctness.

Do not interpret every market closure as a missing candle.

The validator must distinguish between:

### Expected gaps
Examples:
- weekends;
- known market closures;
- broker trading schedule gaps.

### Unexpected gaps
Potentially:
- missing historical data;
- corrupted dataset;
- import failure.

The validator should report both separately.

---

# 11. M1 / M5 Synchronization

Because later strategy logic uses:

- M1 execution;
- M5 structure;

Phase 1 must expose enough information to align both datasets deterministically.

The implementation must not assume that array indices are identical between M1 and M5.

Use timestamps / bar time as the synchronization key.

Required test:

Given an M1 timestamp, the engine must be able to determine the corresponding M5 context deterministically.

No future M5 bar may be used merely because it has a later index.

---

# 12. Time Engine

The Time Engine is one of the most important components.

Input:

```text
Broker timestamp
Time Mode
DST Mode
Session configuration
```

Output:

```text
Broker Time
UTC Time
New York Time
DST State
Session ID
Inside Session
```

The Time Engine must be independent of strategy logic.

---

# 13. Time Modes

## BROKER

Session boundaries are interpreted directly in broker/server clock.

Example:

```text
16:30 → 20:30 broker time
```

No NY conversion is applied to the session definition.

---

## UTC

Session boundaries are interpreted in UTC.

---

## NEW_YORK

Session boundaries are defined in New York local time.

The engine converts New York local time to UTC using the applicable DST rule and then evaluates the event.

---

# 14. DST Modes

## AUTO

Determine whether New York is observing standard time or daylight time based on the configured date.

For US New York rules, the engine must account for the applicable DST calendar rather than assuming a fixed UTC offset throughout the year.

## FIXED

Allow explicit configuration of the assumed offset.

Example:

```text
UTC-5
UTC-4
```

## DISABLED

No automatic DST adjustment.

This mode is useful for controlled historical experiments and diagnostics.

---

# 15. New York DST Requirement

The implementation must not hard-code one permanent New York offset.

For New York local time, the engine must correctly distinguish:

```text
EST = UTC-5
EDT = UTC-4
```

and determine the applicable state from the date under the configured rules.

The exact DST transition calculation must be unit-tested around transition dates.

---

# 16. Broker Time

The broker timestamp is the source timestamp supplied by MT5/historical data.

Do not infer the broker timezone merely from the computer's local timezone.

The configuration must explicitly represent the assumed broker/server offset or the source's documented timezone behavior.

If the data source's timezone cannot be established reliably, the system must report:

```text
TIMEZONE_STATUS = UNKNOWN
```

rather than pretending it is known.

---

# 17. Session Engine

Create a reusable session-window abstraction.

A session profile should contain:

```text
Session ID
Name
Time Mode
Start HH:MM
End HH:MM
Include/Exclude
Enabled
```

Examples:

```text
PROFILE_01
BROKER
16:30
20:30
INCLUDE
```

The architecture should support later:

- multiple windows;
- overnight sessions;
- exclusion windows;
- custom session profiles.

---

# 18. Session Boundary Rules

Define exact behavior for:

```text
start time
end time
exact boundary
overnight window
```

Recommended baseline:

```text
[start, end)
```

Meaning:

- start is included;
- end is excluded.

Example:

```text
16:30 = inside
20:29 = inside
20:30 = outside
```

This rule must be documented and tested.

---

# 19. Session and Date Range Independence

Date range and session window are separate controls.

Example:

```text
Date:
2026-01-01 → 2026-03-31

Session:
16:30 → 20:30
```

The engine must first determine whether a bar belongs to the requested research date range, then evaluate the configured session condition.

---

# 20. Event Time Context

Every later event should be able to attach:

```text
Broker Timestamp
UTC Timestamp
New York Timestamp
DST State
Session Profile
Inside Session
```

Phase 1 should expose a reusable `TimeContext` structure for later phases.

---

# 21. Logging

Logging must be useful for debugging but not flood the journal unnecessarily.

Support levels:

```text
INFO
WARNING
ERROR
DEBUG
```

At minimum log:

- Initialization
- Configuration
- Dataset summary
- Validation summary
- Timezone configuration
- DST mode
- Session configuration
- Fatal validation errors
- Test results

Detailed per-bar logging should be optional.

---

# 22. Determinism

For identical:

- historical data;
- symbol;
- date range;
- configuration;
- timezone rules;

the Phase 1 output must be identical.

Do not use:

- random values;
- current wall-clock time;
- machine-local timezone;
- uncontrolled external state

to alter historical results.

If the current system clock is used only for diagnostics, it must not influence research calculations.

---

# 23. Test Harness

Create a lightweight Phase 1 test harness.

It should test components independently.

Required categories:

### T01 — OHLC Validation

Valid bar passes.

Invalid OHLC fails.

### T02 — Duplicate Timestamp

Duplicate is detected.

### T03 — Timestamp Ordering

Out-of-order bars are detected.

### T04 — Expected Market Gap

Known weekend/market closure is not incorrectly classified as a corrupted gap.

### T05 — Unexpected Gap

Artificial missing interval is detected.

### T06 — M1/M5 Alignment

Known M1 timestamp maps to the correct M5 bar.

### T07 — Broker Time

Known timestamp returns expected broker time representation.

### T08 — UTC Conversion

Known offset produces expected UTC.

### T09 — New York Standard Time

Known winter date maps to EST.

### T10 — New York Daylight Time

Known summer date maps to EDT.

### T11 — DST Transition

Test dates immediately before and after DST transition.

### T12 — Session Start Boundary

Start is inside.

### T13 — Session End Boundary

End is outside under `[start,end)`.

### T14 — Session Middle

Middle timestamp is inside.

### T15 — Outside Session

Outside timestamp is outside.

### T16 — Overnight Session

If implemented in Phase 1, verify correctly.

### T17 — Date Range

Before/inside/after range behave correctly.

### T18 — Determinism

Same dataset/config produces identical validation/time output.

---

# 24. User Verification Tests

Claude must distinguish automated tests from tests requiring the user.

If user verification is required, Claude must STOP and provide a numbered procedure.

Example:

```text
USER TEST REQUIRED #1

1. Open MT5.
2. Attach the Phase 1 research EA.
3. Set Symbol = XAUUSD.
4. Set Date Range = ...
5. Set Time Mode = BROKER.
6. Set Session = 16:30-20:30.
7. Run the test.
8. Send the Journal/Report output.

Expected:
...
```

Do not claim the user test passed until the user provides the result.

---

# 25. Acceptance Criteria

Phase 1 is COMPLETE only if all of the following are true:

1. Project compiles without errors.
2. Data Provider retrieves the required historical bars.
3. Validator detects malformed data.
4. Expected market gaps are not incorrectly treated as data corruption.
5. M1/M5 synchronization is deterministic.
6. Broker/UTC/New York time contexts are generated correctly.
7. New York DST is handled correctly.
8. Session boundaries are deterministic.
9. Date range and session logic are independent.
10. Diagnostics are readable.
11. Automated tests pass.
12. Any failed test is explained.
13. Any user-required test is explicitly identified.
14. No Phase 2+ strategy logic has been implemented.
15. A Phase 1 completion report is generated.

---

# 26. Failure Rules

If compilation fails:

STOP.

If a required automated test fails:

STOP.

If the implementation requires an architectural decision not defined here:

STOP and ask.

If the user must perform a test:

STOP after giving the test instructions.

If data is unavailable or malformed:

Do not fabricate data.

Report the issue.

If a later-phase requirement appears necessary:

Do not implement it silently.

Document it as:

```text
DEFERRED TO PHASE X
```

---

# 27. Phase Completion Report

At the end, Claude must report:

## Implementation

- Files created
- Files modified
- Classes/modules
- Interfaces
- Configuration inputs

## Tests

For every test:

```text
TEST ID
STATUS: PASS / FAIL / BLOCKED
DETAIL
```

## Data Validation

```text
Symbol
Timeframe
Date range
Bars
Missing
Duplicates
Invalid OHLC
Warnings
Status
```

## Time Validation

```text
Broker mode
UTC mode
New York mode
DST tests
Session tests
```

## User Tests

List every test still requiring user action.

## Deferred Work

List anything intentionally left for Phase 2+.

## Final Status

Exactly one:

```text
PHASE 1 COMPLETE
PHASE 1 BLOCKED
PHASE 1 FAILED
```

Claude must not declare COMPLETE if any mandatory acceptance criterion is unresolved.

---

# 28. Stop Condition

This is mandatory.

After Phase 1 is implemented and its automated tests are complete:

**STOP.**

Do not begin:

- Swing Engine
- Leg Engine
- Break Engine
- Fibonacci
- Entry
- Exit
- Filters
- Experiment Runner

until the user explicitly approves Phase 1 and requests Phase 2.

---

# 29. Suggested Commit

If the repository uses Git, create a clean Phase 1 commit only after tests pass.

Suggested message:

```text
GZ Phase 1 - Data Validation and Time Engine
```

Do not mix Phase 2 work into this commit.

---

# 30. Claude Execution Prompt

The following prompt is intended to be sent to Claude together with the Master Roadmap and this Phase 1 Specification.

---

## START CLAUDE PROMPT

You are implementing Phase 1 of the GoldenZone STR MQL5 research system.

Read the supplied Master Roadmap and the supplied Phase 1 Implementation Specification before modifying code.

### Mission

Implement ONLY:

- Data Layer
- Data Validator
- Time Engine
- Session Engine
- Diagnostics
- Phase 1 test harness

The goal is to create a reliable foundation for later research phases.

### Absolute restrictions

Do NOT implement:

- Swing detection
- Pivot logic
- Leg detection
- Break detection
- Fibonacci
- Entry logic
- SL/TP
- Break-even
- Trade simulation
- Filters
- News
- VWAP
- Optimization
- Walk-forward
- Monte Carlo
- Live order execution
- Any Phase 2+ strategy logic

Do not silently expand scope.

### First action

Before coding:

1. Inspect the existing repository.
2. Identify existing MQL5 files and architecture.
3. Identify whether an EA already exists.
4. Identify build conventions.
5. Check whether any existing code should be preserved.
6. Compare the repository structure with the Phase 1 specification.
7. Report the intended implementation plan briefly.

Do not rewrite unrelated code.

### Implementation rules

- Prefer modular MQL5 classes/structs/enums.
- Keep Strategy Logic separate from Time/Data infrastructure.
- Do not hard-code the computer's local timezone.
- Do not use current local time to alter historical calculations.
- Do not fabricate missing market data.
- Do not silently repair invalid data.
- Record warnings/errors.
- Make outputs deterministic.
- Use timestamps for M1/M5 synchronization, not array-index assumptions.
- Treat NOT_AVAILABLE as a distinct state where applicable.
- Keep later-phase interfaces extensible without implementing later logic.

### Data validation

Implement the validation rules from the Phase 1 specification.

Distinguish:

- expected market/session gaps;
- unexpected historical-data gaps.

Do not label every missing timestamp as corrupted data.

### Time engine

Implement:

- BROKER
- UTC
- NEW_YORK

and:

- DST AUTO
- DST FIXED
- DST DISABLED

New York must not use one fixed UTC offset for the whole year.

Implement and test the applicable US DST transition rules.

### Session engine

Implement the documented `[start,end)` boundary convention.

Example:

16:30 = inside
20:29 = inside
20:30 = outside

Keep date range and session filtering independent.

### Tests

Implement the automated tests T01–T18 from the Phase 1 specification, adapting only where technically necessary.

Every test must produce a clear PASS/FAIL result.

### Build

Compile the project.

If compilation fails:

- diagnose the actual cause;
- fix it;
- recompile;
- do not move to Phase 2.

### Test report

At the end provide:

1. Files created.
2. Files modified.
3. Architecture summary.
4. Build result.
5. T01–T18 results.
6. Dataset validation result.
7. Time/DST/session test results.
8. Known limitations.
9. User verification tests, if any.
10. Deferred Phase 2+ work.
11. Final status.

Use exactly one final status:

- PHASE 1 COMPLETE
- PHASE 1 BLOCKED
- PHASE 1 FAILED

### User verification

If any test cannot be performed automatically and requires MT5/user interaction:

1. Stop.
2. Explain exactly why it requires the user.
3. Give numbered steps.
4. Give the expected result.
5. Tell the user exactly what output/screenshot/log to return.
6. Do not declare Phase 1 complete until the result is reviewed.

### Stop rule

When Phase 1 is complete, STOP.

Do not proactively start Phase 2.

Wait for explicit user approval before modifying the project for Phase 2.

## END CLAUDE PROMPT

---

# 31. Phase 1 Handoff

Required inputs for Claude:

1. GoldenZone STR Master Roadmap v1.0
2. This Phase 1 Implementation Specification
3. The current MQL5 repository/project

Claude should work against the actual repository rather than inventing a new unrelated project.

---

# 32. Version Control

Specification version:

`GZ-P1-SPEC v1.0`

Master roadmap:

`GZ-ROADMAP v1.0`

Any material change to Phase 1 requirements should increment the specification version.

