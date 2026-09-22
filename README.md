# GoldenZone STR — Phase 1 + 2 + 3 + 4

Data Layer + Data Validator + Time Engine (Phase 1), M5 Structure/Swing Engine (Phase 2),
Leg Engine + Break Engine (Phase 3), Fibonacci Engine + Setup State Machine (Phase 4).
No entry/exit/simulation logic, no live trading.

## Install

1. In MetaTrader 5: File → Open Data Folder → `MQL5`.
2. Copy the `Include/GoldenZoneSTR/` folder into `MQL5/Include/` (so the final path is
   `MQL5/Include/GoldenZoneSTR/Core/...`, `.../Data/...`, `.../Structure/...`, `.../Leg/...`,
   `.../Setup/...`, etc.).
3. Copy `Experts/GoldenZoneSTR_Research.mq5` into `MQL5/Experts/`.
4. Open MetaEditor, open `GoldenZoneSTR_Research.mq5`, press **F7** to compile.
5. Attach the compiled EA to an XAUUSD chart (any chart timeframe — the EA loads its own M1/M5
   internally, independent of the chart's timeframe).
6. Check the **Experts** log tab for the report, and
   `MQL5/Files/GZ_Phase1_2_3_4_Report.txt` (common Files folder) for the saved copy.

## What this does

- Loads M1 and M5 historical bars for the configured symbol/date range (M15 optional).
- Validates OHLC integrity and timestamp behavior (duplicates, ordering, expected vs.
  unexpected gaps).
- Builds Broker/UTC/New-York time contexts with correct US DST handling.
- Evaluates a configurable session window using the `[start, end)` rule.
- **Phase 2:** detects M5 swing highs/lows with a configurable pivot strength
  (`InpPivotStrength`, baseline 2), with no lookahead.
- **Phase 3:** builds Leg candidates from consecutive, opposite-direction confirmed swings
  (`InpLegVariant`), tracks each open leg's running extreme bar-by-bar, and detects breaks
  (`InpBreakMode`, `InpBreakBufferAtrMult`, `InpAtrPeriod`), no lookahead.
- **Phase 4:** computes Fibonacci levels on a locked leg (bullish: 0%=Leg High, 100%=Leg
  Origin Low; bearish: 0%=Leg Low, 100%=Leg Origin High) and drives a Setup State Machine
  through LEG_DETECTED → BREAK_CONFIRMED → LEG_LOCKED → FIB_ACTIVE → WAITING_ENTRY, applying
  cancellation rules (`OPPOSITE_BREAK`, `NEW_VALID_SETUP`, `SESSION_END` when
  `InpApplySessionFilter=true`, `DATA_END`). At most one non-terminal setup per direction is
  ever left standing. `ENTERED`/`EXITED` are defined states but never assigned — deciding when
  a setup is actually entered/exited is Phase 5/6's job. `InpFibZoneMinRatio`/
  `InpFibZoneMaxRatio` (baseline 0.30/0.90) set the watched retracement zone.
- Runs 45 deterministic, synthetic-data self-tests (T01–T45: T01–T18 Phase 1, T19–T23 Phase 2,
  T24–T34 Phase 3, T35–T45 Phase 4) and reports PASS/FAIL for each.
- Prints and saves a full Phase 1+2+3+4 completion report.
- Does **not** place any trades, and does **not** implement any Phase 5+ strategy logic
  (entry/exit/filters/simulator/metrics). It stops after the report.

## Before trusting the output

Set `InpBrokerUtcOffsetHrs` to your broker's real UTC offset and `InpBrokerOffsetKnown = true`
once you've verified it — otherwise Broker→UTC→NY conversions are only internally consistent,
not guaranteed correct for your specific broker.

See `Docs/Phase1_TestReport.md` for the Phase 1 report template and required user verification
steps (the same verification requirement — compile/attach in MetaEditor/MT5 and confirm the
broker UTC offset — still applies to this Phase 1+2+3+4 build).
