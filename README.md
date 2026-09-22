# GoldenZone STR — Phase 1

Data Layer + Data Validator + Time Engine. No strategy logic, no live trading.

## Install

1. In MetaTrader 5: File → Open Data Folder → `MQL5`.
2. Copy the `Include/GoldenZoneSTR/` folder into `MQL5/Include/` (so the final path is
   `MQL5/Include/GoldenZoneSTR/Core/...`, `.../Data/...`, etc.).
3. Copy `Experts/GoldenZoneSTR_Research.mq5` into `MQL5/Experts/`.
4. Open MetaEditor, open `GoldenZoneSTR_Research.mq5`, press **F7** to compile.
5. Attach the compiled EA to an XAUUSD chart (any chart timeframe — Phase 1 loads its own M1/M5
   internally, independent of the chart's timeframe).
6. Check the **Experts** log tab for the Phase 1 report, and
   `MQL5/Files/GZ_Phase1_Report.txt` (common Files folder) for the saved copy.

## What this does

- Loads M1 and M5 historical bars for the configured symbol/date range (M15 optional).
- Validates OHLC integrity and timestamp behavior (duplicates, ordering, expected vs.
  unexpected gaps).
- Builds Broker/UTC/New-York time contexts with correct US DST handling.
- Evaluates a configurable session window using the `[start, end)` rule.
- Runs 18 deterministic, synthetic-data self-tests (T01–T18) and reports PASS/FAIL for each.
- Prints and saves a full Phase 1 completion report.
- Does **not** place any trades, and does **not** implement any Phase 2+ strategy logic
  (swing/leg/break/fibonacci/entry/exit). It stops after the report.

## Before trusting the output

Set `InpBrokerUtcOffsetHrs` to your broker's real UTC offset and `InpBrokerOffsetKnown = true`
once you've verified it — otherwise Broker→UTC→NY conversions are only internally consistent,
not guaranteed correct for your specific broker.

See `Docs/Phase1_TestReport.md` for the full report template and required user verification
steps.
