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
(calls T167-T187), `Experts/GoldenZoneSTR_Research.mq5` (inputs, guards, run block, report emission).

## Grid (final research grid)
TP 0.5..4.5 step 0.5 (9 values). BE OFF for every TP plus BE triggers strictly below TP; 0.25R and 0.75R never used.
TP0.5 {} | TP1.0 {0.5} | TP1.5 {1.0} | TP2.0 {1} | TP2.5 {1,2} | TP3.0 {1,2} | TP3.5 {1,2,3} | TP4.0 {1,2,3} | TP4.5 {1,2,3,4}.
BE >= TP is never executed. BE level = Entry, offset 0R only.
Main matrix = 9 BE-off + 17 BE-active = 26 configurations + 1 REFERENCE_ONLY / HIGH_TP_REACH_REFERENCE run (TP=1000R, BE off,
run once) = 27 matrix rows, +2 determinism repeats = 29 experiments.

## MFE / MAE / Reach accounting (audit, unchanged behavior)
Per M1 candle: entry engine -> hand-off (journal opened) -> ExitEngine.OnBar -> JournalEngine.OnBar -> SyncJournalClosures.
Entry candle and exit candle are counted with their FULL high/low (MFE may exceed the TP R, MAE may exceed 1R on an SL exit,
a same-candle SL+TP conflict resolved SL_FIRST still counts the high as Reach). BE-arm candle counted fully; new BE stop from
the next candle. Realized R is unaffected. Observable via report section H and tests T184-T187.

## Outputs (Common\Files)
`GZ_Phase155_Report.txt` (sections A-G), `GZ_Phase155_Matrix.csv` (all rows), `GZ_Phase155_Pairwise.csv` (all BE-on runs).

## Pairwise categories (BE off vs BE on, same TP, joined by trade_id)
A SL->BE (protected) | B TP->BE (premature) | C TP->TP | D SL->SL | E other (be-from-other / same-other / anomaly).

## Recommended run
Attach the EA with defaults (`InpRunPhase155=true`, `InpPhase155Only=true`); Phase 15 and Phases 11-14 are skipped automatically.
