# Appendix — Phase "Cost Unification + R-Symmetry Fix" (GZ-COST-RSYM-SPEC v1.0)

NOTE: I don't have your current `GoldenZone_STR_Implementation_Roadmap_masterPromp_v1.3.md`
in this session (only the original v1.0 was attached to this project), so I could not edit it
in place as the Deliverable Convention asks. Paste this appendix into that file (as v1.4) rather
than treating this as a replacement.

## Status: implemented, NOT yet compiled/run in real MT5

Depends on: Phases 1–15.8, FCIS, FCIS_2, FCIS-updated (realistic-cost defaults).
Blocks Phase 15.9 and Phase 16 until confirmed complete in real MT5.

## What this phase found (re-verified against the actual repo, not assumed)

1. **Long/Short R-asymmetry (Bug 1)** — confirmed real. `GZ_ExitEngine.mqh::OnTradeEntered()`
   computed `initial_risk` from the raw structural SL price for a Short, never anticipating the
   ask-crossing `ExitFillPrice()` always adds to a Short's eventual SL/TP fill — while a Long's
   `initial_risk` already absorbed that same premium via its ask-adjusted `entry_price`. Fixed by
   two new helpers, `AnticipatedSlPriceIfShort()` and `AnticipatedTpLevelIfShort()`, so a Short's
   "1R" now anticipates the same future spread crossing a Long's already does — for both the SL
   risk denominator AND the stored TP level (the TP-level piece is a documented, necessary
   deviation from the spec's literal "no TP formula change" — without it, a Short's TP-hit lands
   short of the configured multiple by `spread/initial_risk` even after the SL-only fix; verified
   algebraically and by T-R-SYM-03/T271).
2. **Cost engine wiring (Bug 2)** — partially stale evidence: `CGZCostEngine` was already a fully
   generic, reusable class (from the FCIS-updated commit), not trapped inside
   `GZ_RewardBeEngine.mqh` as the original evidence suggested. The real remaining gap was narrower:
   `GZ_ExperimentConfig`/`CGZExperimentRunner::Execute()` never had a cost field, so Phase
   9/11/12/13/15/15.5 were the ones silently Gross-only. Fixed by adding `GZ_CostConfig
   cost_config` to `GZ_ExperimentConfig` and a parallel `GZ_NetSummary net_metrics` to
   `GZ_ExperimentResult`, computed inside `Execute()` via the same `CGZCostEngine` Section I
   already uses. Every downstream consumer (Robustness, Walk-Forward, Final OOS) inherits this for
   free because they all copy `GZ_ExperimentConfig` wholesale per point/window. Also fixed the
   same missing `exp_cfg.cost_config = g_cost_cfg` line in the main `.mq5` — the identical class of
   bug already found once for the FCIS gates.
3. **Double-spread-charging risk (Bug 3)** — fixed structurally, not just re-worded. A new
   `real_spread_fills_active` parameter on `GZCost_ComputeCostPrice()` forces the spread term to
   zero in code whenever true, regardless of `spread_mode`/`fixed_spread_pts`. Threaded through
   `CGZCostEngine`, `GZ_RewardBeEngine.mqh`, and the main pipeline's own cost call.
4. **Stale documentation (Bug 4)** — Section I's false "not modelled" claim replaced with a
   branch-correct statement (spread already modelled in-simulation when
   `InpUseRealSpreadFills=true`; entry-bar-spread proxy only applies when it's false).
5. **Baseline constants (Bug 5)** — only 2 real duplicated comparison sites existed in the actual
   code (not 3 as the original evidence loosely suggested): `R07` in the main `.mq5` and `V03` in
   `GZ_RewardBeEngine.mqh`. Both now call one shared function, `GZBaselineCompare()` (new file
   `GZ_BaselineCompare.mqh`), which adds the required third verdict —
   `BASELINE_NOT_APPLICABLE_THIS_CONFIG` — whenever the active configuration (TP/BE, every
   FCIS/concurrency/cost switch) doesn't match what `InpP155Ref*` was captured under, so a mismatch
   under today's realistic-cost defaults reads as "wrong config to compare," never as an
   unexplained contradiction.

## New tests: T269–T277 (`GZ_CostRSymTests.mqh`)

T269/T270/T271 = T-R-SYM-01/02/03. T272/T273/T274 = T-COST-WIRE-01/02/03. T275 = T-COST-DBL-01.
T276/T277 = T-BASELINE-01/02. Full suite is now T01–T277 (277 tests once compiled/run).

## Files touched

- `Include/GoldenZoneSTR/Exit/GZ_ExitEngine.mqh` — Sub-phase A
- `Include/GoldenZoneSTR/Cost/GZ_CostTypes.mqh`, `GZ_CostEngine.mqh` — Sub-phase C
- `Include/GoldenZoneSTR/Experiment/GZ_ExperimentTypes.mqh`, `GZ_ExperimentRunner.mqh` — Sub-phase B
- `Include/GoldenZoneSTR/RewardBe/GZ_RewardBeEngine.mqh` — Sub-phases C, D, E
- `Include/GoldenZoneSTR/RewardBe/GZ_BaselineCompare.mqh` — NEW, Sub-phase E
- `Include/GoldenZoneSTR/RewardBe/GZ_CostRSymTests.mqh` — NEW, T269–T277
- `Include/GoldenZoneSTR/Diagnostics/GZ_TestHarness.mqh` — hooks the new suite in
- `Experts/GoldenZoneSTR_Research.mq5` — R07 rewritten via the shared function, `exp_cfg.cost_config`
  wiring, Section D wording, `g_cost_engine.Evaluate()` now passes `InpUseRealSpreadFills`

No existing input, class, method, or file was renamed.
