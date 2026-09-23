//+------------------------------------------------------------------+
//| GZ_WalkForwardTypes.mqh                                           |
//| GoldenZone STR - Phase 13 - Walk-Forward Research - Types          |
//|                                                                    |
//| Shared structs/enums for the Walk-Forward Engine. This file        |
//| contains NO window/selection/aggregation logic (see                |
//| GZ_WalkForwardEngine.mqh). Types only, same discipline as every    |
//| other Phase's own *Types.mqh file.                                 |
//|                                                                    |
//| Roadmap Phase 13: "Train -> Validate -> Move Window -> Train ->    |
//| Validate". Configurable: Training length, Validation length, Step  |
//| size, Minimum trades. Per window: Training result, Selected        |
//| configuration, Validation result, Stability information.           |
//|                                                                    |
//| DESIGN NOTES (documented per spec Section 26 - the Roadmap        |
//| describes Phase 13 at a feature level, same situation as every    |
//| phase since Phase 3):                                              |
//|                                                                    |
//| 1) WHAT "SELECTED CONFIGURATION" MEANS HERE. The Roadmap does not  |
//|    say what is being selected between. This phase selects ONE VALUE|
//|    of ONE Phase 12 axis (ENUM_GZ_ROBUSTNESS_PARAM - e.g. break     |
//|    buffer ATR, SL ATR multiple, pivot strength) from a supplied    |
//|    candidate list, per training window. That reuses Phase 12's own |
//|    axis vocabulary and its own tested sweep/analysis code          |
//|    (CGZRobustnessEngine) instead of inventing a second parameter   |
//|    DSL - the exact reason Phase 12 itself reuses Phase 9's runner. |
//|    Every other config field is held fixed at base_config's value.  |
//|    Multi-axis walk-forward is a documented extension point, NOT    |
//|    implemented (DEFERRED - not silently expanded).                 |
//|                                                                    |
//| 2) SELECTION RULE. Per training window: run every candidate value  |
//|    (a FULL Phase 2-8 re-simulation per candidate, via Phase 12's   |
//|    RunSweep -> Phase 9's runner - no new simulation logic here),   |
//|    discard candidates with fewer than min_trades training trades,  |
//|    then apply Phase 12's own Analyze() (best expectancy, narrow    |
//|    peak / unstable zone flags). Roadmap Phase 12 forbids accepting |
//|    the single highest historical value alone, so when              |
//|    require_safe_selection is true (default) an unsafe best is NOT  |
//|    taken: the window falls back to the BASELINE value if the       |
//|    baseline itself is eligible, else the window selects nothing    |
//|    (NO_SAFE_CANDIDATE) and is not validated. Validation data is    |
//|    NEVER consulted during selection.                               |
//|                                                                    |
//| 3) WINDOWS ARE TIME-BASED, HALF-OPEN, AND ROLLING. Training is     |
//|    [train_start, train_end), validation is [validate_start,        |
//|    validate_end) with validate_start == train_end (contiguous, no  |
//|    gap, no overlap between a window's own train and validate).     |
//|    The whole window slides by step_days. Lengths are CALENDAR days |
//|    (weekends included) so no boundary depends on a broker holiday  |
//|    calendar. A window is generated only if validate_end fits       |
//|    inside the data (last bar time + one M5 period) - a partial     |
//|    trailing window is never invented. Anchored (expanding) training|
//|    windows are not implemented (DEFERRED).                         |
//|                                                                    |
//| 4) EACH WINDOW IS SIMULATED ON ITS OWN DATA SLICE, FROM A COLD     |
//|    START (documented limitation): the Phase 2-8 pipeline is run    |
//|    fresh on just that window's M1/M5 bars, so ATR/swing warm-up    |
//|    bars at the start of a validation window are consumed inside    |
//|    the window. This is the only way to guarantee, structurally,    |
//|    that no training run can see validation bars (and no validation |
//|    run can see later bars) without touching the Phase 2-8 engines. |
//|                                                                    |
//| 5) FIXED-size arrays only (GZ_ExperimentTypes.mqh design note 5,   |
//|    reapplied): windows[] is a bounded fixed array with a count.    |
//|    A window stores COMPACT stats (GZ_TradeStats/GZ_RiskStats), not |
//|    the full GZ_ExperimentResult of every candidate - 24 windows x  |
//|    up to 15 candidates of full metrics would be pointless bulk.    |
//|    If the data would produce more than GZ_MAX_WALKFORWARD_WINDOWS  |
//|    windows, generation STOPS at the cap and windows_capped is set  |
//|    (never silently truncated without a flag).                      |
//|                                                                    |
//| 6) ID format mirrors Phase 9/11/12's own pattern - "WF_%06d", a    |
//|    fresh per-instance sequential counter, no cross-session state.  |
//|                                                                    |
//| 7) Stability flags (PARAM_UNSTABLE / OVERFIT_SUSPECT / NEGATIVE_   |
//|    OOS / VALIDATION_OVERLAP) have no Roadmap formula - documented  |
//|    conventional defaults in GZ_Constants.mqh, exact rules in       |
//|    GZ_WalkForwardEngine.mqh::Aggregate().                          |
//+------------------------------------------------------------------+
#ifndef __GZ_WALKFORWARD_TYPES_MQH__
#define __GZ_WALKFORWARD_TYPES_MQH__

#include "..\Core\GZ_Types.mqh"
#include "..\Core\GZ_Constants.mqh"
#include "..\Experiment\GZ_ExperimentTypes.mqh"
#include "..\Metrics\GZ_MetricsTypes.mqh"
#include "..\Robustness\GZ_RobustnessTypes.mqh"

#define GZ_MAX_WALKFORWARD_WINDOWS  24   // documented cap (design note 5), never silently exceeded
#define GZ_MAX_WALKFORWARD_NOTES    10

//--- Outcome of one window's training-time selection (design note 2).
enum ENUM_GZ_WF_SELECTION_STATUS
  {
   GZ_WF_SEL_NOT_RUN = 0,        // window never processed (Clear() default)
   GZ_WF_SEL_SELECTED,           // Phase 12's best eligible value was accepted
   GZ_WF_SEL_FALLBACK_BASELINE,  // best was unsafe (narrow peak / unstable) -> baseline value used instead
   GZ_WF_SEL_NO_ELIGIBLE,        // no candidate reached min_trades on the training slice
   GZ_WF_SEL_NO_SAFE_CANDIDATE,  // best unsafe AND baseline itself ineligible -> nothing selected
   GZ_WF_SEL_NO_DATA             // training slice had no M5 bars
  };

string GZWfSelectionStatusToString(ENUM_GZ_WF_SELECTION_STATUS s)
  {
   switch(s)
     {
      case GZ_WF_SEL_NOT_RUN:          return "NOT_RUN";
      case GZ_WF_SEL_SELECTED:         return "SELECTED";
      case GZ_WF_SEL_FALLBACK_BASELINE:return "FALLBACK_BASELINE";
      case GZ_WF_SEL_NO_ELIGIBLE:      return "NO_ELIGIBLE";
      case GZ_WF_SEL_NO_SAFE_CANDIDATE:return "NO_SAFE_CANDIDATE";
      case GZ_WF_SEL_NO_DATA:          return "NO_DATA";
      default:                         return "UNKNOWN";
     }
  }

//--- Default candidate-value offsets per axis. Deliberately IDENTICAL to
//--- the neighborhoods the Phase 12 EA section already uses (ATR-style
//--- axes -> Roadmap's own worked example, ratio axes, small-int axes),
//--- so Phase 13 introduces no second, different grid definition.
//--- Candidate values = the base config's own current value + offset.
void GZWalkForwardDefaultOffsets(ENUM_GZ_ROBUSTNESS_PARAM axis, double &out[])
  {
   switch(axis)
     {
      case GZ_ROBUST_BREAK_BUFFER_ATR:
      case GZ_ROBUST_SL_ATR_MULT:
      case GZ_ROBUST_SL_BUFFER_ATR:
      case GZ_ROBUST_ENTRY_PENETRATION_ATR:
         GZRobustnessDefaultAtrOffsets(out);
         break;
      case GZ_ROBUST_FIB_ZONE_MIN_RATIO:
      case GZ_ROBUST_FIB_ZONE_MAX_RATIO:
         GZRobustnessDefaultRatioOffsets(out);
         break;
      default:
         GZRobustnessDefaultIntOffsets(out);
         break;
     }
  }

//+------------------------------------------------------------------+
//| Full, reconstructable configuration for one walk-forward run      |
//+------------------------------------------------------------------+
struct GZ_WalkForwardConfig
  {
   GZ_ExperimentConfig       base_config;      // every field except `axis` is held fixed at this value
   ENUM_GZ_ROBUSTNESS_PARAM  axis;             // the ONE axis whose value is selected per window (design note 1)
   double                    candidates[GZ_MAX_ROBUSTNESS_POINTS]; // absolute candidate values for `axis`
   int                       candidate_count;

   int                       train_days;       // calendar days (design note 3)
   int                       validate_days;
   int                       step_days;
   int                       min_trades;             // training eligibility floor (design note 2)
   int                       min_validation_trades;  // below this a validated window is flagged LOW_VALIDATION_TRADES
   bool                      require_safe_selection; // design note 2

   void Default()
     {
      base_config.Default();
      axis                   = GZ_ROBUST_BREAK_BUFFER_ATR;
      for(int i=0;i<GZ_MAX_ROBUSTNESS_POINTS;i++) candidates[i]=0.0;
      candidate_count        = 0;
      train_days             = GZ_DEFAULT_WF_TRAIN_DAYS;
      validate_days          = GZ_DEFAULT_WF_VALIDATE_DAYS;
      step_days              = GZ_DEFAULT_WF_STEP_DAYS;
      min_trades             = GZ_DEFAULT_WF_MIN_TRADES;
      min_validation_trades  = GZ_DEFAULT_WF_MIN_VALIDATION_TRADES;
      require_safe_selection = true;
     }
  };

//+------------------------------------------------------------------+
//| One walk-forward window: boundaries + training result + selected   |
//| value + validation result + stability information.                 |
//+------------------------------------------------------------------+
struct GZ_WalkForwardWindow
  {
   int         index;
   datetime    train_start;       // inclusive
   datetime    train_end;         // EXCLUSIVE - equals validate_start
   datetime    validate_start;    // inclusive
   datetime    validate_end;      // EXCLUSIVE

   int         train_m5_bars;
   int         validate_m5_bars;

   //--- Training result + selection (design note 2)
   ENUM_GZ_WF_SELECTION_STATUS status;
   int         train_candidates_run;       // candidates actually simulated (out-of-domain ones are skipped by Phase 12)
   int         train_candidates_eligible;  // of those, how many reached min_trades
   double      baseline_value;             // base_config's own value for the axis
   double      train_best_value;           // Phase 12's raw best eligible value BEFORE the safety rule (valid only if train_has_best)
   bool        train_has_best;
   bool        train_narrow_peak;
   bool        train_flat_region;
   bool        train_unstable_zone;
   bool        train_param_sensitive;
   bool        train_safe_to_adopt;
   double      selected_value;             // valid only if status is SELECTED or FALLBACK_BASELINE
   GZ_TradeStats train_stats;              // the SELECTED value's own training-slice stats

   //--- Validation result (only when a value was selected)
   bool        validation_ran;
   bool        low_validation_trades;
   GZ_TradeStats val_stats;                // selected value on the validation slice
   GZ_RiskStats  val_risk;
   bool        baseline_val_ran;
   GZ_TradeStats baseline_val_stats;       // fixed BASELINE value on the same validation slice (what selection is compared against)

   void Clear()
     {
      index = 0;
      train_start = 0; train_end = 0; validate_start = 0; validate_end = 0;
      train_m5_bars = 0; validate_m5_bars = 0;
      status = GZ_WF_SEL_NOT_RUN;
      train_candidates_run = 0; train_candidates_eligible = 0;
      baseline_value = 0.0; train_best_value = 0.0; train_has_best = false;
      train_narrow_peak = false; train_flat_region = false; train_unstable_zone = false;
      train_param_sensitive = false; train_safe_to_adopt = false;
      selected_value = 0.0;
      train_stats.Clear();
      validation_ran = false; low_validation_trades = false;
      val_stats.Clear(); val_risk.Clear();
      baseline_val_ran = false; baseline_val_stats.Clear();
     }

   bool HasSelection() const
     {
      return (status==GZ_WF_SEL_SELECTED || status==GZ_WF_SEL_FALLBACK_BASELINE);
     }
  };

//+------------------------------------------------------------------+
//| One full walk-forward run: windows + aggregate stability info.     |
//+------------------------------------------------------------------+
struct GZ_WalkForwardResult
  {
   string                    id;              // "WF_000001" (design note 6)
   string                    dataset_id;
   ENUM_GZ_ROBUSTNESS_PARAM  axis;
   string                    axis_label;
   double                    baseline_value;
   GZ_WalkForwardConfig      config;          // full copy - the run is reconstructable from this
   string                    strategy_version;
   ENUM_GZ_VALIDATION_STATUS m1_validation_status;
   ENUM_GZ_VALIDATION_STATUS m5_validation_status;

   GZ_WalkForwardWindow      windows[GZ_MAX_WALKFORWARD_WINDOWS];
   int                       window_count;
   bool                      windows_capped;  // true = more windows would have fit but GZ_MAX_WALKFORWARD_WINDOWS stopped generation

   //--- Aggregate (filled by CGZWalkForwardEngine::Aggregate())
   int         windows_selected;              // windows where a value was selected
   int         windows_validated;             // windows where validation actually ran
   int         windows_low_validation_trades; // validated windows below min_validation_trades
   int         positive_windows;              // validated windows with validation net R > 0

   int         pooled_trades;                 // all validated windows' OOS trades, concatenated
   int         pooled_winners;
   int         pooled_losers;
   double      pooled_net_r;
   double      pooled_expectancy;
   double      pooled_win_rate;
   double      pooled_profit_factor;
   bool        pooled_profit_factor_undefined; // winners exist with zero losing R (same meaning as GZ_TradeStats)

   int         baseline_pooled_trades;        // the fixed BASELINE value over the SAME validation slices
   double      baseline_pooled_net_r;
   double      baseline_pooled_expectancy;
   bool        selection_edge_defined;        // both pooled populations non-empty
   double      selection_edge_expectancy;     // pooled_expectancy - baseline_pooled_expectancy

   double      mean_train_expectancy;         // mean over validated windows, each window weighted equally
   double      mean_val_expectancy;
   bool        efficiency_defined;
   double      walk_forward_efficiency;       // mean_val_expectancy / mean_train_expectancy (only if efficiency_defined)

   int         distinct_selected_values;
   int         most_common_selected_count;
   int         selection_changes;             // consecutive selected windows whose chosen value differs
   double      selected_value_min;
   double      selected_value_max;

   bool        validation_overlap;            // step_days < validate_days -> validation windows overlap, pooled trades double-count
   bool        param_unstable;
   bool        overfit_suspect;
   bool        negative_oos;

   string      notes[GZ_MAX_WALKFORWARD_NOTES];
   int         note_count;

   void ClearAggregate()
     {
      windows_selected = 0; windows_validated = 0; windows_low_validation_trades = 0; positive_windows = 0;
      pooled_trades = 0; pooled_winners = 0; pooled_losers = 0;
      pooled_net_r = 0.0; pooled_expectancy = 0.0; pooled_win_rate = 0.0;
      pooled_profit_factor = 0.0; pooled_profit_factor_undefined = false;
      baseline_pooled_trades = 0; baseline_pooled_net_r = 0.0; baseline_pooled_expectancy = 0.0;
      selection_edge_defined = false; selection_edge_expectancy = 0.0;
      mean_train_expectancy = 0.0; mean_val_expectancy = 0.0;
      efficiency_defined = false; walk_forward_efficiency = 0.0;
      distinct_selected_values = 0; most_common_selected_count = 0; selection_changes = 0;
      selected_value_min = 0.0; selected_value_max = 0.0;
      validation_overlap = false; param_unstable = false; overfit_suspect = false; negative_oos = false;
     }

   void Clear()
     {
      id = ""; dataset_id = "";
      axis = GZ_ROBUST_BREAK_BUFFER_ATR; axis_label = ""; baseline_value = 0.0;
      config.Default();
      strategy_version = "";
      m1_validation_status = GZ_VAL_UNKNOWN;
      m5_validation_status = GZ_VAL_UNKNOWN;
      for(int i=0;i<GZ_MAX_WALKFORWARD_WINDOWS;i++) windows[i].Clear();
      window_count = 0;
      windows_capped = false;
      ClearAggregate();
      for(int i=0;i<GZ_MAX_WALKFORWARD_NOTES;i++) notes[i]="";
      note_count = 0;
     }

   void AddNote(string n)
     {
      if(note_count<GZ_MAX_WALKFORWARD_NOTES)
        {
         notes[note_count] = n;
         note_count++;
        }
     }
  };

#endif // __GZ_WALKFORWARD_TYPES_MQH__
