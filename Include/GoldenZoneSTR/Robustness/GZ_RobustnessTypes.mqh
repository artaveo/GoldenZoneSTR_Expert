//+------------------------------------------------------------------+
//| GZ_RobustnessTypes.mqh                                            |
//| GoldenZone STR - Phase 12 - Robustness + Sensitivity Research -   |
//| Types                                                              |
//|                                                                    |
//| Shared structs/enums for the Robustness Engine. This file contains|
//| NO sweep/analysis logic (see GZ_RobustnessEngine.mqh). Types only,|
//| same discipline as every other Phase's own *Types.mqh file.       |
//|                                                                    |
//| DESIGN NOTES (documented per spec Section 26 - the Roadmap        |
//| describes Phase 12 at a feature level, same situation as every    |
//| phase since Phase 3):                                              |
//|                                                                    |
//| 1) UNLIKE Phase 11 (a post-hoc MASK over an already-final setup/   |
//|    trade population - see GZ_FilterComboTypes.mqh), a robustness   |
//|    axis here (e.g. break-buffer ATR multiple, SL ATR multiple, fib |
//|    zone ratio, pivot strength...) changes the underlying Leg/      |
//|    Break/Setup/Trade population ITSELF. Filtering the same trades  |
//|    differently is not enough - each swept value needs its own FULL |
//|    Phase 2-8 re-simulation. This engine does that the same way     |
//|    Phase 9's own CGZExperimentRunner already does it for a SWEEP   |
//|    (design note 2, GZ_ExperimentTypes.mqh) - GZ_RobustnessEngine   |
//|    adds NO new simulation logic of its own; it only builds the     |
//|    neighborhood of GZ_ExperimentConfig values, runs them through   |
//|    the EXISTING CGZExperimentRunner, and analyzes the resulting    |
//|    GZ_ExperimentResult metrics curve for sensitivity.               |
//|                                                                    |
//| 2) FIXED-size arrays only (GZ_ExperimentTypes.mqh design note 5's  |
//|    own reasoning, reapplied here): a dynamic array nested inside a |
//|    struct that is itself stored in another dynamic array is a      |
//|    documented MQL5 trouble spot this repo avoids everywhere. Both  |
//|    a sweep REQUEST's values[] and a sweep RESULT's points[] are    |
//|    therefore bounded (GZ_MAX_ROBUSTNESS_POINTS) fixed arrays with a |
//|    count, exactly like GZ_ExperimentResult.warnings[]/GZ_TradeJournal|
//|    .reach_hit[]. GZ_RobustnessPoint nests one GZ_ExperimentResult -  |
//|    safe, because GZ_ExperimentResult itself has no dynamic array    |
//|    members (only its own fixed warnings[GZ_MAX_EXPERIMENT_WARNINGS]).|
//|                                                                    |
//| 3) Sweep ID format mirrors Phase 9/11's own pattern (design note 3,|
//|    GZ_ExperimentTypes.mqh) - "ROB_%06d", a fresh per-instance       |
//|    sequential counter, no cross-session persistence.                |
//|                                                                    |
//| 4) Flag thresholds (Roadmap: "Flagها: Narrow peak / Flat region /  |
//|    Unstable zone / Parameter sensitivity" - named, not defined, no  |
//|    formula given) are documented, conventional defaults living in  |
//|    GZ_Constants.mqh (same "no baseline stated -> documented         |
//|    default" pattern as GZ_DEFAULT_ATR_PERIOD in Phase 3) - see      |
//|    GZ_RobustnessEngine.mqh::Analyze() for the exact rules.          |
//|                                                                    |
//| 5) "بالاترین مقدار تاریخی به‌تنهایی به‌عنوان انتخاب نهایی پذیرفته   |
//|    نشود" (Roadmap Phase 12) is implemented as safe_to_adopt_best -  |
//|    best_idx alone is never presented as a final answer; it is only |
//|    "safe" when narrow_peak and unstable_zone are BOTH false.        |
//+------------------------------------------------------------------+
#ifndef __GZ_ROBUSTNESS_TYPES_MQH__
#define __GZ_ROBUSTNESS_TYPES_MQH__

#include "..\Core\GZ_Types.mqh"
#include "..\Core\GZ_Constants.mqh"
#include "..\Experiment\GZ_ExperimentTypes.mqh"

#define GZ_MAX_ROBUSTNESS_POINTS  15   // per single sweep - Roadmap's own worked example uses 7; headroom documented, not silently expanded
#define GZ_MAX_ROBUSTNESS_NOTES   8    // mirrors GZ_MAX_EXPERIMENT_WARNINGS's own bounded-checkpoint pattern

//--- Which single GZ_ExperimentConfig field a sweep varies. MQL5 has no
//--- pointer-to-member/generics (same limitation GZ_ExperimentTypes.mqh
//--- design note 2 already documents for Phase 9's own modes) - so the
//--- axis is named explicitly, and GZ_RobustnessEngine's private
//--- ApplyAxisValue()/AxisBaselineValue()/IsValidAxisValue() switch on it.
enum ENUM_GZ_ROBUSTNESS_PARAM
  {
   GZ_ROBUST_PIVOT_STRENGTH = 0,        // Phase 2 - int, domain >=1
   GZ_ROBUST_BREAK_BUFFER_ATR,          // Phase 3 - break_config.buffer_atr_mult, domain >=0
   GZ_ROBUST_ATR_PERIOD,                // Phase 3 - break_config.atr_period (shared by Phase 3 Break Engine and
                                         // Phase 6's ATR SL model - this repo's single ATR-period config field), int, domain >=1
   GZ_ROBUST_FIB_ZONE_MIN_RATIO,        // Phase 4 - domain (0,1), must stay < fib_zone_max_ratio
   GZ_ROBUST_FIB_ZONE_MAX_RATIO,        // Phase 4 - domain (0,1], must stay > fib_zone_min_ratio
   GZ_ROBUST_ENTRY_PENETRATION_ATR,     // Phase 5 - entry_config.penetration_atr_mult, domain >=0
   GZ_ROBUST_CONFIRMATION_CANDLES,      // Phase 5 - entry_config.confirmation_candles, int, domain >=1
   GZ_ROBUST_SL_ATR_MULT,               // Phase 6 - exit_config.sl_atr_mult, domain >0
   GZ_ROBUST_SL_BUFFER_ATR,             // Phase 6 - exit_config.sl_buffer_atr_mult, domain >=0
   GZ_ROBUST_TP_R_MULTIPLE,             // Phase 6 - exit_config.tp_r_multiple, domain >0
   GZ_ROBUST_BE_TRIGGER_R,              // Phase 6 - exit_config.be_trigger_r, domain >=0 (0 = OFF)
   GZ_ROBUST_PARAM_COUNT                // sentinel - not a real axis
  };

string GZRobustnessParamToString(ENUM_GZ_ROBUSTNESS_PARAM p)
  {
   switch(p)
     {
      case GZ_ROBUST_PIVOT_STRENGTH:       return "PIVOT_STRENGTH";
      case GZ_ROBUST_BREAK_BUFFER_ATR:     return "BREAK_BUFFER_ATR";
      case GZ_ROBUST_ATR_PERIOD:           return "ATR_PERIOD";
      case GZ_ROBUST_FIB_ZONE_MIN_RATIO:   return "FIB_ZONE_MIN_RATIO";
      case GZ_ROBUST_FIB_ZONE_MAX_RATIO:   return "FIB_ZONE_MAX_RATIO";
      case GZ_ROBUST_ENTRY_PENETRATION_ATR:return "ENTRY_PENETRATION_ATR";
      case GZ_ROBUST_CONFIRMATION_CANDLES: return "CONFIRMATION_CANDLES";
      case GZ_ROBUST_SL_ATR_MULT:          return "SL_ATR_MULT";
      case GZ_ROBUST_SL_BUFFER_ATR:        return "SL_BUFFER_ATR";
      case GZ_ROBUST_TP_R_MULTIPLE:        return "TP_R_MULTIPLE";
      case GZ_ROBUST_BE_TRIGGER_R:         return "BE_TRIGGER_R";
      default:                             return "UNKNOWN";
     }
  }

//--- Roadmap Phase 12's own worked example (Section: "مثال برای 1.50
//--- ATR": 1.25 / 1.35 / 1.40 / 1.50 / 1.60 / 1.65 / 1.75) reproduced
//--- LITERALLY as offsets from whatever baseline value is actually being
//--- swept - the default, denser-near-center neighborhood for ATR-
//--- multiple-style axes (BREAK_BUFFER_ATR, SL_ATR_MULT, SL_BUFFER_ATR,
//--- ENTRY_PENETRATION_ATR).
void GZRobustnessDefaultAtrOffsets(double &out[])
  {
   ArrayResize(out, 7);
   out[0]=-0.25; out[1]=-0.15; out[2]=-0.10; out[3]=0.0; out[4]=0.10; out[5]=0.15; out[6]=0.25;
  }

//--- Conventional, documented default for ratio-style axes in (0,1)
//--- (FIB_ZONE_MIN_RATIO/FIB_ZONE_MAX_RATIO) - no Roadmap example given
//--- for these, unlike the ATR case above.
void GZRobustnessDefaultRatioOffsets(double &out[])
  {
   ArrayResize(out, 5);
   out[0]=-0.10; out[1]=-0.05; out[2]=0.0; out[3]=0.05; out[4]=0.10;
  }

//--- Conventional, documented default for small-integer axes
//--- (PIVOT_STRENGTH, ATR_PERIOD steps, CONFIRMATION_CANDLES).
void GZRobustnessDefaultIntOffsets(double &out[])
  {
   ArrayResize(out, 5);
   out[0]=-2; out[1]=-1; out[2]=0; out[3]=1; out[4]=2;
  }

//--- One request: sweep ONE axis of ONE base config across up to
//--- GZ_MAX_ROBUSTNESS_POINTS already-computed values (design note 2).
struct GZ_RobustnessSweepRequest
  {
   ENUM_GZ_ROBUSTNESS_PARAM param;
   string                   label;          // display label; defaults to GZRobustnessParamToString(param) if empty
   GZ_ExperimentConfig      base_config;     // every other field held fixed while `param` varies
   double                   values[GZ_MAX_ROBUSTNESS_POINTS];
   int                      value_count;

   void Clear()
     {
      param = GZ_ROBUST_BREAK_BUFFER_ATR;
      label = "";
      base_config.Default();
      for(int i=0;i<GZ_MAX_ROBUSTNESS_POINTS;i++) values[i]=0.0;
      value_count = 0;
     }
  };

//--- One swept value's own full result (design note 2 - GZ_ExperimentResult
//--- has no dynamic array members, so nesting it here in a FIXED array is safe).
struct GZ_RobustnessPoint
  {
   double               param_value;    // the actual value this point ran with (post axis-apply)
   bool                 value_applied;  // false only for a defensively-unfilled slot; every point actually run is true
   GZ_ExperimentResult  result;

   void Clear()
     {
      param_value   = 0.0;
      value_applied = false;
      result.Clear();
     }
  };

//--- One full sweep's result (Roadmap Phase 12: examine dependency on one
//--- specific number; flag Narrow peak/Flat region/Unstable zone/
//--- Parameter sensitivity; never accept the single highest historical
//--- value alone - design note 5).
struct GZ_RobustnessSweepResult
  {
   string                    id;              // "ROB_000001" (design note 3)
   ENUM_GZ_ROBUSTNESS_PARAM  param;
   string                    param_label;
   double                    baseline_value;   // the base_config's own value for `param` before sweeping

   GZ_RobustnessPoint        points[GZ_MAX_ROBUSTNESS_POINTS]; // sorted ascending by param_value after RunSweep()/Analyze()
   int                       point_count;

   int                       best_idx;         // index into points[] with the highest expectancy among trade_count>0 points; -1 if none
   bool                      narrow_peak;
   bool                      flat_region;
   bool                      unstable_zone;
   bool                      parameter_sensitive;
   bool                      safe_to_adopt_best; // best_idx>=0 AND !narrow_peak AND !unstable_zone (design note 5)

   string                    notes[GZ_MAX_ROBUSTNESS_NOTES];
   int                       note_count;

   void Clear()
     {
      id = ""; param = GZ_ROBUST_BREAK_BUFFER_ATR; param_label = ""; baseline_value = 0.0;
      for(int i=0;i<GZ_MAX_ROBUSTNESS_POINTS;i++) points[i].Clear();
      point_count = 0;
      best_idx = -1;
      narrow_peak = false; flat_region = false; unstable_zone = false; parameter_sensitive = false;
      safe_to_adopt_best = false;
      for(int i=0;i<GZ_MAX_ROBUSTNESS_NOTES;i++) notes[i]="";
      note_count = 0;
     }

   void AddNote(string n)
     {
      if(note_count<GZ_MAX_ROBUSTNESS_NOTES)
        {
         notes[note_count] = n;
         note_count++;
        }
     }
  };

//--- Outcome of a RunSweepBatch() call - mirrors ENUM_GZ_BATCH_STATUS/
//--- ENUM_GZ_FILTER_COMBO_BATCH_STATUS (Roadmap: stage research, don't
//--- run one huge Grid at once).
enum ENUM_GZ_ROBUSTNESS_BATCH_STATUS
  {
   GZ_ROBUST_BATCH_OK = 0,
   GZ_ROBUST_BATCH_REJECTED_EMPTY,
   GZ_ROBUST_BATCH_REJECTED_TOO_LARGE
  };

#endif // __GZ_ROBUSTNESS_TYPES_MQH__
