# Phase 15.5 - Reward / TP x Risk-Free (BE) Research Matrix

Position: Phase 15 -> **15.5** -> Phase 16 (not started). Research + measurement only. Development data only
(`InpRangeStart..InpRangeEnd`). The Final OOS is never loaded (Phase 15 is forced OFF while `InpRunPhase155=true`).
No TP/BE setting is selected, ranked or frozen.

## Audit summary (before any change)
* A. Already implemented: TP/BE/SL in `CGZExitEngine`; entry is independent of exit (trades overlap, ids stable);
  `CGZExperimentRunner` re-simulates per config; Phase 12 has `TP_R_MULTIPLE` / `BE_TRIGGER_R` axes.
* B. Implemented, not reported: the TP x BE matrix was never run/reported (Phase 12 only swept BREAK_BUFFER_ATR, SL_ATR_MULT).
* C. Missing: per-experiment exit-reason/BE/reach detail (discarded after `Execute`), pairwise BE analysis, avg losing streak,
  max MAE/MFE, CSV output, an end-to-end TP/BE test (T119 only tests a pure request builder).
* D. Risks: Reach Matrix is censored by the run's own exits; SL/TP/BE are evaluated on the trade's own entry candle; a newly
  armed BE stop applies from the NEXT candle (candle-level ambiguity unmeasured); no cost model (R is gross);
  Phase 8 says trade order is "exit order" but journals are appended at entry (kept as-is).
* E. Changes: see below.

## Files
New: `Include/GoldenZoneSTR/RewardBe/{GZ_RunDetail,GZ_RewardBeTypes,GZ_RewardBeEngine,GZ_RewardBeTests}.mqh`
Modified (additive, no behavior change): `Exit/GZ_ExitTypes.mqh`, `Exit/GZ_ExitEngine.mqh` (3 diagnostic fields only),
`Experiment/GZ_ExperimentRunner.mqh` (optional detail capture + `RunSingleDetailed`), `Diagnostics/GZ_TestHarness.mqh`
(calls T167-T180), `Experts/GoldenZoneSTR_Research.mq5` (inputs, guards, run block, report emission).

## Grid
TP 0.5..5.0 step 0.5 (10). BE trigger OFF + 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.50 3.00 4.00 5.00 R. BE level = Entry, offset 0R only.
Runs: 10 BE-off + 75 BE-active (trigger < TP) + 45 BE_INACTIVE_EQUIVALENT (trigger >= TP, validation only) + 1 REFERENCE_ONLY
(TP=1000R, BE off, UNCENSORED_REACH) = 131 matrix runs, +2 determinism repeats = 133 experiments.

## Outputs (Common\Files)
`GZ_Phase155_Report.txt` (sections A-G), `GZ_Phase155_Matrix.csv` (all rows), `GZ_Phase155_Pairwise.csv` (all BE-on runs).

## Pairwise categories (BE off vs BE on, same TP, joined by trade_id)
A SL->BE (protected) | B TP->BE (premature) | C TP->TP | D SL->SL | E other (be-from-other / same-other / anomaly).

## Recommended run
Attach the EA with defaults (`InpRunPhase155=true`, `InpPhase155Only=true`); Phase 15 and Phases 11-14 are skipped automatically.
