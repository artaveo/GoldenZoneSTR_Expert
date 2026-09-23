# GoldenZone STR — Phase 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8

Data Layer + Data Validator + Time Engine (Phase 1), M5 Structure/Swing Engine (Phase 2),
Leg Engine + Break Engine (Phase 3), Fibonacci Engine + Setup State Machine (Phase 4),
Entry Engine + Historical Trade Simulator (Phase 5), Exit Engine SL/TP/BE (Phase 6),
MAE/MFE + R-Path + Event Ledger (Phase 7), Metrics + Reporting (Phase 8).
No filter/experiment-runner logic, no live trading.

## Install

1. In MetaTrader 5: File → Open Data Folder → `MQL5`.
2. Copy the `Include/GoldenZoneSTR/` folder into `MQL5/Include/` (so the final path is
   `MQL5/Include/GoldenZoneSTR/Core/...`, `.../Data/...`, `.../Structure/...`, `.../Leg/...`,
   `.../Setup/...`, `.../Entry/...`, `.../Exit/...`, `.../Journal/...`, etc.).
3. Copy `Experts/GoldenZoneSTR_Research.mq5` into `MQL5/Experts/`.
4. Open MetaEditor, open `GoldenZoneSTR_Research.mq5`, press **F7** to compile.
5. Attach the compiled EA to an XAUUSD chart (any chart timeframe — the EA loads its own M1/M5
   internally, independent of the chart's timeframe).
6. Check the **Experts** log tab for the report, and
   `MQL5/Files/GZ_Phase1_2_3_4_5_6_7_8_Report.txt` (common Files folder) for the saved copy.

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
  through LEG_DETECTED → BREAK_CONFIRMED → LEG_LOCKED → FIB_ACTIVE → WAITING_ENTRY → ENTERED →
  EXITED, applying cancellation rules (`OPPOSITE_BREAK`, `NEW_VALID_SETUP`, `SESSION_END` when
  `InpApplySessionFilter=true`, `INVALID_PENETRATION`, `DATA_END`).
- **Phase 5:** `CGZEntryEngine` watches FIB_ACTIVE/WAITING_ENTRY setups and decides when/at what
  price a setup is actually entered (`InpEntryModel`: TOUCH/LIMIT/CLOSE_CONFIRMATION/
  M1_CONFIRMATION), producing one `GZ_Trade` per fill. `CGZTradeSimulator` replays the whole
  M1/M5 dataset through the Leg/Break/Setup/Entry/Exit/Journal/Ledger engines with no lookahead
  across the M1/M5 boundary.
- **Phase 6:** `CGZExitEngine` manages every open trade at M1 granularity (SL model
  STRUCTURE/ATR, TP as an R-multiple, optional break-even, a documented intrabar SL/TP
  conflict policy), producing one `GZ_TradeExit` per trade and wiring `GZ_SETUP_EXITED` back
  onto the setup.
- **Phase 7:** `CGZJournalEngine` tracks running Maximum Adverse/Favorable Excursion (MAE/MFE,
  in price and R), when each was reached, and a 10-level Reach Matrix (0.5R–5R) per trade, all
  at M1 granularity, stopping the instant a trade closes. `CGZEventLedger` records Setup-
  Valid/Cancelled/Invalidated, Entry and Exit events, built once, deterministically, from the
  already-final Setup/Entry/Exit state at the end of each replay (two reserved event types,
  Rejection and Filter Result, exist for Phase 10's Filter Engine but are never emitted yet).
- **Phase 8:** `CGZMetricsEngine` computes a Phase 8 summary once, post-hoc, from Phase 7's final
  journal: Trade Metrics (win rate, avg win/loss, profit factor with an explicit
  undefined/infinite flag, expectancy, net R, average R), Risk (max/avg drawdown in R, drawdown
  duration in trades, longest winning/losing streak), Behavior (avg MAE/MFE, duration,
  time-to-MAE/MFE), and Breakdowns by direction, session, hour, day-of-week and month. All
  metrics are R-based (no position-sizing/currency model exists yet). Filter Diagnostics is a
  reserved, always-zero stub pending Phase 10's Filter Engine.
- Runs 86 deterministic, synthetic-data self-tests (T01–T86: T01–T18 Phase 1, T19–T23 Phase 2,
  T24–T34 Phase 3, T35–T45 Phase 4, T46–T54 Phase 5, T55–T64 Phase 6, T65–T74 Phase 7,
  T75–T86 Phase 8) and reports PASS/FAIL for each.
- Prints and saves a full Phase 1+2+3+4+5+6+7+8 completion report.
- Does **not** place any live trades, and does **not** implement any Phase 9+ logic
  (filters/experiment runner). It stops after the report.

## Before trusting the output

Set `InpBrokerUtcOffsetHrs` to your broker's real UTC offset and `InpBrokerOffsetKnown = true`
once you've verified it — otherwise Broker→UTC→NY conversions are only internally consistent,
not guaranteed correct for your specific broker.

See `Docs/Phase1_TestReport.md` for the Phase 1 report template and required user verification
steps (the same verification requirement — compile/attach in MetaEditor/MT5 and confirm the
broker UTC offset — still applies to this Phase 1+2+3+4+5+6+7+8 build).
