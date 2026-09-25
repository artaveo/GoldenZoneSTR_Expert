# Phase 15.8 - Dataset Partition + Net-of-Cost R Layer + Run Speed/Progress (design)

Three parts, additive on top of Phase 15.7 (Historical Data Expansion). No strategy rule, parameter,
TP/BE selection, freeze, or new Final OOS run happens here. Part A is the core; Parts B and C never
change a gross result.

## Part A - Partition architecture

```
Historical Dataset (validated once, Phase 15.7)
      -> Partition Manager (GZ_Partition.mqh)
            -> DEVELOPMENT     research allowed
            -> FINAL_OOS       new research cycle; research REFUSED
            -> LEGACY_TOUCHED  previously observed 2026 data; research REFUSED
```

All dates are half-open `[start, end)` **configuration** (EA inputs); nothing in `GZ_Partition.mqh`
hard-codes a date. Default partition (also the current one):

| Part | Range |
|---|---|
| Historical | 2020-07-01 00:00 -> 2026-09-25 00:00 |
| DEVELOPMENT | 2020-07-01 00:00 -> 2025-01-01 00:00 |
| FINAL_OOS (new) | 2025-01-01 00:00 -> 2026-01-01 00:00 |
| LEGACY_TOUCHED | 2026-01-01 00:00 -> 2026-09-25 00:00 |

`InpHistEnd` stays an **inclusive** M1 bar-open time (`GZHistEndExclusive()` converts it to the
half-open end the partition layer uses).

### Validation (`GZPartitionValidate`)
Contiguous (`dev_end == oos_start`, `oos_end == leg_start`), non-overlapping, every part inside
Historical, `start < end` for all four ranges. Historical data outside every part (an earlier start or
later end than the parts cover) is **accepted** and reported `UNASSIGNED` in a warning - it stays in the
dataset/coverage, research on it is refused until a partition input is moved to cover it. Any other
problem (overlap, gap, order, outside Historical) is a hard error: nothing runs.

### Classification and research gate (`GZPartitionClassify` / `GZPartitionGate`)
A half-open range classifies as `DEVELOPMENT | FINAL_OOS | LEGACY_TOUCHED | CROSSES_PARTITION_BOUNDARY |
UNASSIGNED | OUTSIDE_HISTORICAL | INVALID`. The gate runs research **only** on `DEVELOPMENT`. One
controlled exception: `GZ_RANGE_LEGACY_DEV` (the old `InpRangeStart..InpRangeEnd`, unaligned) classifying
as `LEGACY_TOUCHED` is allowed and labelled `REGRESSION_ONLY_LEGACY` - a reproduction of the validated
412-trade baseline (R07), never used for selection. Everything else refuses with a written reason;
`R11_NEW_FINAL_OOS_NOT_LOADED` proves the new Final OOS bars never enter the loaded research population
(measured range *and* warm-up window together).

## Boundary semantics

Half-open `[start, end)` at the partition layer; the engines keep their existing inclusive-end
convention: `end_inclusive = end_exclusive - 1 M1 minute`, then the unchanged M5 alignment (start
rounded UP, end rounded DOWN to the last minute of a complete M5 window). Each partition run is
simulated **separately**, from a clean state:

| Case | Result |
|---|---|
| A: setup begins before Development end, entry inside, exit after | Engines never see bars after the range end -> closed by the existing `DATA_END` rule at the last Development bar. Belongs to DEVELOPMENT by ENTRY time, flagged censored. |
| B: setup begins before a partition start, entry after | No setup survives a partition start; every run begins from a clean setup state. |
| C: warm-up | See below. |
| D: trade open at the boundary | Impossible - a trade is either closed at the partition end by `DATA_END` or was never opened (T220). |

## Warm-up vs measured population

New input `InpWarmupM5Bars` (M5 bars, **default 0 = exactly cold start** - every existing result and
the 412-trade regression stay identical). `CGZHistoricalDataset::WarmupStart()` returns the time of the
M5 bar `warm_bars` real stored bars before the measured start (never before the start of the measured
range's own partition, never before the first stored bar). With warm-up > 0 the run loads
`[measure_start - warm-up, measure_end]`; only trades whose **entry** time is `>= measure_start` belong
to the measured population. This needed one addition to `GZ_ExperimentConfig`
(`measure_from`, default 0) and a mask-based re-use of the **existing** `CGZMetricsEngine::ComputeFiltered`
- no simulator, entry, exit or journal logic changed (T218, T235).

## Contamination protection

`GZPartitionValidate` rejects (no research runs): OOS overlapping Development, a part outside
Historical, a reversed/empty range, an unintended gap. `GZPartitionGate` refuses (with a written reason)
any research request on `FINAL_OOS` or `LEGACY_TOUCHED` except the labelled `REGRESSION_ONLY_LEGACY`
case. Runtime check `R11_NEW_FINAL_OOS_NOT_LOADED` (Phase 15.7's existing `R09` is unchanged and still
guards the legacy Final OOS).

## Generic dates

`InpHistStart`/`InpHistEnd` are plain inputs; 2020-07-01 is only the current earliest usable date (before
it the broker holds sparse, hourly-like bars - flagged `PARTIAL` by the existing Phase 15.7 density
rule), not an engine limit. An earlier start is accepted by the partition layer (T216, T224); a later
end is accepted too (T217). Coverage quality (sparse/partial months) is reported regardless of what the
partition layer accepts.

---

## Part B - Net-of-cost R layer (`GZ_Cost*.mqh`)

Post-hoc and additive: reads a finished run's per-trade record (`CGZRunDetail`) plus the M1 `spread`
field, and writes NET figures **next to** the existing GROSS ones. It never touches the simulator,
entry/exit engines, journal, or any gross figure.

**Formula** (price units per ounce; XAUUSD is USD-quoted):
```
commission_price = open_price * commission_percent / 100        (PERCENT, charged once at open)
                  = commission_per_lot_round_turn / contract_size (FIXED)
cost_price = spread_points*point + 2*slippage_points*point + commission_price
net_R      = gross_R - cost_price / initial_risk_price
```
A BREAK_EVEN exit (gross R = 0) therefore ends slightly negative in net terms automatically.

**Venue model** (researched proposal, FundedNext MT5 gold): commission = lot x contract size x open
price x 0.0016%, charged once at opening, nothing at closing (FundedNext Help Center, structure
effective 2026-01-12; worked example: 1 lot XAUUSD @ 4466.22 -> $7.14). Applied to **all** history on
purpose - the goal is the cost of trading the strategy *now*. Older fixed $/lot figures describe older
structures and are not used as the default. Spread: `RECORDED` (the entry M1 bar's own `spread` field,
default) or `FIXED` (points). No slippage figure is published by the venue: default 0 plus a mandatory
sensitivity table at 0/20/50 points per side (10 points = $0.10 on XAUUSD).

**Swap is NOT modelled** - trades open across a server midnight are only counted (`rollover_crossings`)
so the omission can be judged.

**Approximation** (documented, one direction): candles are bid-based and the simulator fills on them; a
long is not really filled at the ask. The entry-bar spread is charged once as that proxy. Where the exit
spread is wider than the entry spread (news, rollover, fast stop-outs) the cost is **under-stated**; a
short's TP/SL really trigger on the ask, which is not modelled. Exact bid/ask fill modelling is out of
scope.

Net drawdown/streaks/PF/win-rate are **not** reimplemented: the net R series is fed through a temporary
`CGZJournalEngine` into the **existing** `CGZMetricsEngine::Compute()` (same pattern the Phase 15.5 unit
tests already use to hand-build a journal) - T232 proves the result against a hand-computed drawdown.

Recorded entry-bar spread statistics (average/median/p95/zero-share, per year and overall) are printed
so the person can judge plausibility without Claude guessing the broker; an implausible population
(mostly zero) is flagged.

New inputs: `InpCostSpreadMode`, `InpCostFixedSpreadPts`, `InpCostCommissionMode`,
`InpCostCommissionPercent`, `InpCostCommissionPerLot`, `InpCostContractSize`, `InpCostSlippagePts`,
`InpCostsConfigured` (false by default -> NET = GROSS everywhere, clearly labelled).

## Part C - Progress and speed

- `[GZ][PROGRESS]` lines before/after each of the Phase 15.5 matrix's experiments: run number, percent
  complete, elapsed time, estimated remaining time (mean duration of completed runs x runs left), and a
  start/end terminal-local timestamp per run (`GZ_Progress.mqh` - pure text functions of the arguments
  passed in; no clock read changes a result).
- `InpQuietMainPipeline` (default true): lowers the main pipeline's `CGZLogger` to `GZ_SEV_WARNING` for
  the duration of that one run only, then restores `GZ_SEV_INFO`. Log output only.
- `InpSkipDuplicateMainRun` (default false): when true (and only when the Phase 15.5 matrix with its
  "only" mode and TP=2R/BE-off is what's running), the duplicate main-pipeline execution is skipped and
  the TP 2R / BE off matrix row supplies the figures used everywhere the main run's numbers are needed
  (R07 regression, the main report's Phase 2-8/10/14 sections are marked empty-by-design). Proven
  identical to the un-skipped run by T229 and by R07 on the legacy range (412 trades either way).

## Tests

`T210`-`T224` = P158-01..15 (partition). `T225`-`T228` = P158-16..19 (net-of-cost). `T229` = quiet/skip
proof. `T230` = research gate (Development/OOS/Legacy/crossing/REGRESSION_ONLY_LEGACY). `T231` =
existing accepted-hole exception regression (still passes for the real hole, still fails for an
unrelated >= 4 day hole - no duplicate implementation, reuses `GZ_P157_ACCEPTED_HOLE_FROM/TO` and
`MissingRangesNotAccepted()`). `T232` = net metrics through the existing metrics engine (hand-computed).
`T233` = recorded spread statistics. `T234` = progress/ETA text. `T235` = warm-up never reads outside the
measured range's own partition. All existing tests T01-T209 are unchanged.

## Runtime validations (this attachment)

`R10_PARTITION_VALID` (new), `R11_NEW_FINAL_OOS_NOT_LOADED` (new; Phase 15.7's `R09` continues to guard
the legacy Final OOS loader), plus the unchanged R01-R08 from Phase 15.7. `R07` now also accepts the
`InpSkipDuplicateMainRun` figure source and labels the detail line `[REGRESSION_ONLY_LEGACY]`.

## Output

`GZ_Phase158_Report.txt` (Common\\Files), in addition to the unchanged Phase 15.7 files
(`GZ_Phase157_Report.txt`, `GZ_Phase157_Coverage.csv`) and the Phase 15.5 files (now carrying a net-of-cost
section and, per row, net figures in `GZ_Phase155_Matrix_<label>.csv`).
