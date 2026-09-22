# GoldenZone STR — Phase 1 + 2 + 3

Data Layer + Data Validator + Time Engine (Phase 1), M5 Structure/Swing Engine (Phase 2),
Leg Engine + Break Engine (Phase 3). No fibonacci/setup-state/entry/exit logic, no live trading.

## Install

1. In MetaTrader 5: File → Open Data Folder → `MQL5`.
2. Copy the `Include/GoldenZoneSTR/` folder into `MQL5/Include/` (so the final path is
   `MQL5/Include/GoldenZoneSTR/Core/...`, `.../Data/...`, `.../Structure/...`, `.../Leg/...`,
   etc.).
3. Copy `Experts/GoldenZoneSTR_Research.mq5` into `MQL5/Experts/`.
4. Open MetaEditor, open `GoldenZoneSTR_Research.mq5`, press **F7** to compile.
5. Attach the compiled EA to an XAUUSD chart (any chart timeframe — the EA loads its own M1/M5
   internally, independent of the chart's timeframe).
6. Check the **Experts** log tab for the report, and
   `MQL5/Files/GZ_Phase1_2_3_Report.txt` (common Files folder) for the saved copy.

## What this does

- Loads M1 and M5 historical bars for the configured symbol/date range (M15 optional).
- Validates OHLC integrity and timestamp behavior (duplicates, ordering, expected vs.
  unexpected gaps).
- Builds Broker/UTC/New-York time contexts with correct US DST handling.
- Evaluates a configurable session window using the `[start, end)` rule.
- **Phase 2:** detects M5 swing highs/lows with a configurable pivot strength
  (`InpPivotStrength`, baseline 2), with no lookahead — a swing is only ever confirmed once
  that many bars have closed on its right side.
- **Phase 3:** builds Leg candidates from consecutive, opposite-direction confirmed swings
  (`InpLegVariant` — baseline: last confirmed opposite swing; research: minimum-distance /
  minimum-ATR-distance), tracks each open leg's running price extreme bar-by-bar, and detects
  when a leg's target level is broken (`InpBreakMode` — baseline CLOSE, research WICK —
  `InpBreakBufferAtrMult` / `InpAtrPeriod` for an ATR-scaled buffer). No lookahead: a leg's
  extreme only ever consumes bars at/after its target swing's confirmation time, and a break is
  only ever confirmed on the exact bar that clears the configured level+buffer.
- Runs 34 deterministic, synthetic-data self-tests (T01–T34: T01–T18 Phase 1, T19–T23 Phase 2,
  T24–T34 Phase 3) and reports PASS/FAIL for each.
- Prints and saves a full Phase 1+2+3 completion report.
- Does **not** place any trades, and does **not** implement any Phase 4+ strategy logic
  (fibonacci/setup-state-machine/entry/exit/filters/simulator). It stops after the report.
- Selecting/cancelling among multiple simultaneously-open legs is explicitly out of scope here
  and deferred to Phase 4 (Setup State Machine) — Phase 3 only produces candidate Leg records
  and their break state.

## Before trusting the output

Set `InpBrokerUtcOffsetHrs` to your broker's real UTC offset and `InpBrokerOffsetKnown = true`
once you've verified it — otherwise Broker→UTC→NY conversions are only internally consistent,
not guaranteed correct for your specific broker.

See `Docs/Phase1_TestReport.md` for the Phase 1 report template and required user verification
steps (the same verification requirement — compile/attach in MetaEditor/MT5 and confirm the
broker UTC offset — still applies to this Phase 1+2+3 build).
