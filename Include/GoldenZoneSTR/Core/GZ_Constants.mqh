//+------------------------------------------------------------------+
//| GZ_Constants.mqh                                                  |
//| GoldenZone STR - Phase 1 - Constants                              |
//+------------------------------------------------------------------+
#ifndef __GZ_CONSTANTS_MQH__
#define __GZ_CONSTANTS_MQH__

#define GZ_SECONDS_PER_MINUTE   60
#define GZ_SECONDS_PER_HOUR     3600
#define GZ_SECONDS_PER_DAY      86400

#define GZ_SPACING_M1_SECONDS   60
#define GZ_SPACING_M5_SECONDS   300
#define GZ_SPACING_M15_SECONDS  900

// New York standard/daylight UTC offsets (hours). Negative = behind UTC.
#define GZ_NY_STD_OFFSET_HOURS  (-5)
#define GZ_NY_DST_OFFSET_HOURS  (-4)

// US DST transition anchor: 2:00 AM local wall-clock time.
#define GZ_DST_TRANSITION_HOUR  2

#define GZ_PROJECT_VERSION      "GZ-P1-SPEC v1.0"

// Phase 2 - M5 Structure Engine: baseline pivot strength per roadmap.
// Research variants (1..5) are exposed as an EA input, not hard-coded.
#define GZ_DEFAULT_PIVOT_STRENGTH  2
#define GZ_PROJECT_VERSION_P2      "GZ-P2-ROADMAP v1.0"

// Phase 3 - Leg Engine + Break Engine.
// Baseline break mode = CLOSE (roadmap); WICK is the research variant.
// Break buffer baseline = 0 ATR; research grid: 0.05/0.10/0.15/0.20/0.30/0.50.
// ATR period: no explicit baseline stated in the roadmap - 14 used as the
// conventional default (documented, not silently assumed); research grid:
// 5/10/14/20/30, exposed as EA inputs, not hard-coded.
#define GZ_DEFAULT_BREAK_BUFFER_ATR  0.0
#define GZ_DEFAULT_ATR_PERIOD        14
#define GZ_PROJECT_VERSION_P3        "GZ-P3-ROADMAP v1.0"

// Phase 4 - Fibonacci Engine + Setup State Machine.
// Research levels: 0.30-0.90 grid, including 0.78, architecture extensible
// to 0.01 increments (Roadmap). The watched "zone" for WAITING_ENTRY is the
// price interval spanned by [min,max] of that grid; no single baseline
// ratio is stated in the Roadmap for the zone bounds themselves, so the
// grid's own min/max are used directly - documented, not silently assumed.
#define GZ_DEFAULT_FIB_ZONE_MIN_RATIO  0.30
#define GZ_DEFAULT_FIB_ZONE_MAX_RATIO  0.90
#define GZ_PROJECT_VERSION_P4          "GZ-P4-ROADMAP v1.0"

// Phase 5 - Entry Engine + Historical Trade Simulator.
// Baseline entry model = TOUCH (roadmap). entry_fib_ratio: no explicit
// roadmap baseline stated for the single trigger level within the watched
// zone - 0.618 used as the conventional default (documented, not silently
// assumed; see GZ_EntryTypes.mqh design note 1), fully configurable.
// Confirmation candles: research range 1-3 (roadmap). Penetration baseline
// = 0 ATR; research grid: 0.02/0.05/0.10/0.15 (roadmap).
#define GZ_DEFAULT_ENTRY_FIB_RATIO         0.618
#define GZ_DEFAULT_CONFIRMATION_CANDLES    1
#define GZ_DEFAULT_ENTRY_PENETRATION_ATR   0.0
#define GZ_PROJECT_VERSION_P5              "GZ-P5-ROADMAP v1.0"

// Phase 6 - Exit Engine (SL/TP/BE).
// SL baseline model = STRUCTURE (roadmap lists it first); buffer baseline
// = 0 ATR (mirrors the Break Engine's own buffer default). ATR SL model's
// multiple and TP's R-multiple have no stated Roadmap baseline - 1.5 and
// 2.0 used as conventional defaults (documented, not silently assumed,
// same pattern as GZ_DEFAULT_ATR_PERIOD in Phase 3). BE baseline = OFF
// (roadmap's own "OFF" grid value). Intrabar SL/TP conflict baseline =
// SL_FIRST (conservative - assumes the worse outcome when the true
// intrabar order cannot be known from OHLC alone).
#define GZ_DEFAULT_SL_BUFFER_ATR      0.0
#define GZ_DEFAULT_SL_ATR_MULT        1.5
#define GZ_DEFAULT_TP_R_MULTIPLE      2.0
#define GZ_DEFAULT_BE_TRIGGER_R       0.0
#define GZ_PROJECT_VERSION_P6         "GZ-P6-ROADMAP v1.0"

// Phase 7 - MAE/MFE + R-Path + Event Ledger.
// Reach Matrix grid itself is defined in GZ_JournalTypes.mqh
// (GZ_REACH_LEVELS/GZ_REACH_LEVEL_COUNT) since it is a data-shape constant
// tightly coupled to GZ_TradeJournal's fixed-size arrays, not a tunable
// research parameter like the constants above - kept here only as a
// version marker for the phase completion report.
#define GZ_PROJECT_VERSION_P7         "GZ-P7-ROADMAP v1.0"

// Phase 8 - Metrics + Reporting.
// No tunable research parameters of its own (a pure post-hoc aggregator
// over Phase 7's already-final CGZJournalEngine - see GZ_MetricsEngine.mqh
// header); kept here only as a version marker for the phase completion
// report, same pattern as GZ_PROJECT_VERSION_P7.
#define GZ_PROJECT_VERSION_P8         "GZ-P8-ROADMAP v1.0"

// Phase 9 - Experiment Configuration + Runner.
// GZ_STRATEGY_VERSION is the pre-freeze strategy tag every GZ_ExperimentResult
// carries as its "Strategy version" field (Roadmap Result requirement). It
// deliberately uses the exact vocabulary the Roadmap's own Phase 16 (Research
// Freeze) example uses ("GZ_STR v1.0 -> GZ_STR v1.1") - Phase 16 itself is not
// implemented yet, so this constant is the single, not-yet-bumped baseline tag;
// bumping it on a material change is explicitly Phase 16's job, not Phase 9's.
// GZ_DEFAULT_MAX_EXPERIMENT_BATCH_SIZE enforces the Roadmap's own Phase 9 rule
// ("do not use a huge Grid all at once; research should be staged") as an
// actual runtime cap, not just a comment - see GZ_ExperimentRunner.mqh.
#define GZ_STRATEGY_VERSION                    "GZ_STR v1.0"
#define GZ_DEFAULT_MAX_EXPERIMENT_BATCH_SIZE    200
#define GZ_PROJECT_VERSION_P9                   "GZ-P9-ROADMAP v1.0"

// Phase 10 - Filter Engine.
// Defaults documented in GZ_FilterTypes.mqh (GZ_FilterSetConfig::Default()):
// every filter mode defaults to OFF (safe - a fresh Phase 10 run changes
// nothing about the Phase 1-9 trade population until a filter is explicitly
// enabled via EA input), atr_period=14 mirrors GZ_DEFAULT_ATR_PERIOD (Phase 3).
#define GZ_PROJECT_VERSION_P10                  "GZ-P10-ROADMAP v1.0"

// Phase 11 - Filter Combination Research.
// GZ_DEFAULT_MAX_FILTER_COMBO_BATCH_SIZE mirrors GZ_DEFAULT_MAX_EXPERIMENT_BATCH_SIZE's
// own "stage research, don't run one huge Grid at once" cap (Phase 9), reapplied to
// CGZFilterComboEngine::RunBatch() - see GZ_FilterComboEngine.mqh. Kept as its own,
// smaller constant (not the Phase 9 one reused) because Phase 11's batches are
// combination counts (single/pair/multi-filter requests), a much smaller space than
// Phase 9's full strategy-config sweeps; 50 comfortably covers R11-A (5) + R11-B
// (up to 11) + R11-C (a handful) in one run with room to grow.
#define GZ_DEFAULT_MAX_FILTER_COMBO_BATCH_SIZE   50
#define GZ_PROJECT_VERSION_P11                   "GZ-P11-ROADMAP v1.0"

// Phase 12 - Robustness + Sensitivity Research.
// UNLIKE Phase 11 (a post-hoc mask over an already-final population), a robustness
// axis (e.g. break/SL ATR multiple) changes the underlying Leg/Break/Setup/Trade
// population ITSELF, so each swept value requires a FULL Phase 2-8 re-simulation via
// Phase 9's own CGZExperimentRunner (see GZ_RobustnessTypes.mqh design note 1) - no
// re-simulation avoidance is possible here.
// Flag thresholds below have no Roadmap-stated formula ("Narrow peak / Flat region /
// Unstable zone / Parameter sensitivity" are named, not defined) - conventional,
// documented defaults (same pattern as GZ_DEFAULT_ATR_PERIOD in Phase 3); see
// GZ_RobustnessEngine.mqh::Analyze() for the exact rules that use them.
#define GZ_ROBUST_NARROW_PEAK_DROP_PCT         0.30  // peak's BOTH immediate neighbors must fall below (1-this)*peak to flag NARROW_PEAK
#define GZ_ROBUST_FLAT_REGION_MIN_POINTS       3     // contiguous points needed to flag FLAT_REGION
#define GZ_ROBUST_FLAT_REGION_TOL_PCT          0.15  // max-min within a flat window, as a fraction of the window's own max
#define GZ_ROBUST_UNSTABLE_SIGN_FLIPS_MIN      2     // consecutive-pair sign flips (above the noise floor) needed to flag UNSTABLE_ZONE
#define GZ_ROBUST_NOISE_FLOOR_R                0.05  // |expectancy| below this (in R) is treated as noise, not a real sign, for the flip count
#define GZ_ROBUST_PARAM_SENSITIVE_RANGE_PCT    0.75  // (max-min) over the whole sweep vs |best expectancy|, above which PARAMETER_SENSITIVE is flagged
#define GZ_ROBUST_PARAM_SENSITIVE_ABS_FLOOR    0.20  // absolute R floor used for the above when |best expectancy| is ~0
#define GZ_DEFAULT_MAX_ROBUSTNESS_BATCH_SIZE   20    // Roadmap "stage research, don't run one huge Grid at once" cap, reapplied to Phase 12 (axes per RunSweepBatch call)
#define GZ_PROJECT_VERSION_P12                 "GZ-P12-ROADMAP v1.0"

// Phase 13 - Walk-Forward Research.
// Roadmap: "Train -> Validate -> Move Window -> Train -> Validate", configurable
// Training length / Validation length / Step size / Minimum trades. The Roadmap
// gives NO numeric defaults, so the values below are conventional, documented
// defaults (same pattern as GZ_DEFAULT_ATR_PERIOD in Phase 3), all overridable
// via EA inputs. Window lengths are in CALENDAR days (weekends included) so a
// window boundary never depends on a broker holiday calendar.
// The stability thresholds have no Roadmap-stated formula either - see
// GZ_WalkForwardEngine.mqh::Aggregate() for the exact rules that use them.
#define GZ_DEFAULT_WF_TRAIN_DAYS               28    // training window length (calendar days)
#define GZ_DEFAULT_WF_VALIDATE_DAYS            14    // validation window length (calendar days)
#define GZ_DEFAULT_WF_STEP_DAYS                14    // how far the whole window slides each step (calendar days)
#define GZ_DEFAULT_WF_MIN_TRADES               30    // a TRAINING candidate needs at least this many trades to be eligible for selection
#define GZ_DEFAULT_WF_MIN_VALIDATION_TRADES    10    // a validation window with fewer trades is flagged LOW_VALIDATION_TRADES
#define GZ_WF_PARAM_UNSTABLE_CHANGE_PCT        0.50  // share of consecutive selected-window pairs whose chosen value changed, above which PARAM_UNSTABLE is flagged
#define GZ_WF_PARAM_UNSTABLE_MIN_WINDOWS       3     // PARAM_UNSTABLE is only ever flagged with at least this many selected windows (2 windows = 1 pair = no evidence)
#define GZ_WF_EFFICIENCY_MIN                   0.50  // walk-forward efficiency (mean validation expectancy / mean training expectancy) below this flags OVERFIT_SUSPECT
#define GZ_WF_NOISE_FLOOR_R                    0.05  // mean training expectancy at/below this (in R) makes the efficiency ratio UNDEFINED rather than a meaningless huge/negative number
#define GZ_PROJECT_VERSION_P13                 "GZ-P13-ROADMAP v1.0"

#endif // __GZ_CONSTANTS_MQH__
