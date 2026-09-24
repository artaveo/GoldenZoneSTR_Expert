# Phase 15.7 - Historical Data Expansion (design)

Data infrastructure only. No strategy logic, parameter, TP/BE grid or partition is changed or chosen.

## Flow
1. `CGZHistoricalDataset::Load()` - ONE `CopyRates` per timeframe for `InpHistStart..InpHistEnd`.
2. ONE validation with the unchanged Phase 1 validator (`ValidateOHLC`, `ValidateTimestamps`).
3. `CGZCoverage` - month-by-month tables (year rows are roll-ups): M1/M5 bars, M5 windows spanned by the M1 bars,
   unexpected / expected gaps (Phase 1 Saturday rule, reproduced exactly), gaps >= 4 days, spread / tick-volume presence,
   status `OK | OK_GAPS | MISMATCH | PARTIAL | MISSING`, plus head / tail / internal missing ranges.
4. `ResolveResearchRange()` turns ANY selector into one inclusive `[eff_start, eff_end]` (`GZ_ResearchRange`).
5. `Slice()` copies the bars by TIME (binary search). The engines (Phase 2-15.5) receive the copy exactly like a directly
   loaded range. The raw arrays are freed afterwards (`ReleaseBars()`); coverage and validation stay.

## Range semantics
- Inclusive ends, same as `CopyRates`: `start <= bar.time <= end`.
- YEAR / MONTH / DAY / WEEK: `[00:00 first day, 23:59 last day]` (leap years and Dec->Jan rollover covered by tests).
- M5 alignment (all kinds except LEGACY_DEV): start rounded UP to an M5 boundary, end rounded DOWN to the last minute of a
  complete M5 window. No M5 bar is built from minutes after the range end; no M1 minute belongs to an M5 window that opened
  before the start. Requested and effective values are both reported.
- LEGACY_DEV = `InpRangeStart..InpRangeEnd` unaligned, so it reproduces the old direct load bar for bar (runtime check R05).
- COLD START: swings, ATR, legs and setups begin empty at the slice start.

### Boundary rules (existing engine behaviour, unchanged)
| Situation | Result |
|---|---|
| Trade entered inside, would close after the end | Bars after the end do not exist for the engine -> closed by the existing `DATA_END` rule at the last slice bar |
| Trade entered before the start | Not in the population |
| Setup created before the start | Does not exist (cold start) |
| Setup created inside, entry would fall after the end | Cancelled by the existing `DATA_END` rule, never entered |

Consequence: results of two adjacent sub-ranges do not add up to the result of their union (edge warm-up and DATA_END
closures differ). Compare ranges only with each other, never by summing.

## Development / Final-OOS boundary
`InpOosStart` (2026-06-13 00:00) is preserved. `GZClassifyPartition()` labels every effective range
`DEVELOPMENT_ELIGIBLE | CROSSES_LEGACY_OOS | LEGACY_OOS_ONLY`. Research (main pipeline and the 15.5 matrix) runs only on
`DEVELOPMENT_ELIGIBLE` ranges; the others are refused with a written reason (never shifted, never clipped). The data after
the boundary stays in the dataset, in the coverage tables and can be sliced (tests T204). Phase 15 (the only Final-OOS
loader) is forced off while Phase 15.7 is active. No new OOS is defined here.

## Output
- `GZ_Phase157_Report.txt`, `GZ_Phase157_Coverage.csv` (Common\Files).
- Phase 15.5 files get the range label as suffix (`GZ_Phase155_Report_<label>.txt`, ...): identical schema, one file set per range.
- V03 (Phase 15 Development report comparison) is recorded only for LEGACY_DEV; other ranges do not carry that reference.

## Runtime validations
R01 dataset loaded | R02 no missing range | R03 Phase 1 status not INVALID | R04 M1/M5 compatible |
R05 legacy slice == direct load | R07 baseline regression (412 trades, TP 2R, BE off) | R08 slice bounds / no leakage |
R09 Final OOS not used.

## Tests
T188-T202 = the fifteen required date-slicing tests (full range, year, month, week, day, custom, month/year boundary,
incomplete coverage, no trades outside the range, determinism, no cross-run contamination, schema identity across range
sizes, grid preserved, removed values absent, baseline unchanged). T203-T208 = range builders, partition boundary, coverage
classification, validator consistency, M5 alignment, memory release.
