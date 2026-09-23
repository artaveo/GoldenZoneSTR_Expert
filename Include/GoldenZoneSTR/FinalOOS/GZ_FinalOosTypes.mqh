//+------------------------------------------------------------------+
//| GZ_FinalOosTypes.mqh                                              |
//| GoldenZone STR - Phase 15 - Final OOS - Types                      |
//|                                                                    |
//| Roadmap Phase 15: the Final OOS is NOT used in Optimization, NOT   |
//| used in Filter selection, NOT used in Parameter tuning, and is     |
//| reported SEPARATELY. Output: OOS trades, PF, expectancy, DD,       |
//| MAE/MFE, distribution, and a comparison with Development.          |
//|                                                                    |
//| DESIGN NOTES (spec Section 26 - Roadmap gives feature level only):|
//|                                                                    |
//| 1) THE FINAL OOS IS A DATE RANGE THAT NO EARLIER PHASE LOADS. The  |
//|    Development range is InpRangeStart..InpRangeEnd - the only data |
//|    Phases 1-14 ever read. The OOS range is loaded separately, only |
//|    by Phase 15, and must START AT OR AFTER the Development range   |
//|    END (CheckSeparation() rejects anything else, never silently    |
//|    shifting it). So "not used in optimization/filters/tuning" is   |
//|    enforced by construction, not by convention.                    |
//| 2) NO SELECTION HERE. One FROZEN configuration (the EA's inputs,   |
//|    exactly what Phases 9-14 used as their base) is run ONCE on the |
//|    Development range and ONCE on the OOS range through the same    |
//|    Phase 9 runner (full Phase 2-8 pipeline). Nothing is chosen or  |
//|    tuned from the OOS result.                                      |
//| 3) BOUNDARY BARS. If the two ranges share a boundary, bars with    |
//|    time <= the Development range's last bar are DROPPED from the   |
//|    OOS series (counted, reported) so no bar is ever in both.       |
//| 4) COMPARISON (no Roadmap formula): deltas OOS minus Development;  |
//|    expectancy_retention = OOS expectancy / Development expectancy, |
//|    UNDEFINED unless Development expectancy > GZ_OOS_NOISE_FLOOR_R. |
//|    Flags: LOW_OOS_TRADES (< min trades), OOS_NO_TRADES,            |
//|    OOS_NEGATIVE (trades>0 and expectancy<=0), OOS_DEGRADED         |
//|    (retention defined and < GZ_OOS_RETENTION_MIN).                 |
//| 5) SINGLE-LOOK DISCIPLINE cannot be enforced by code: if you       |
//|    change parameters after seeing this result, the OOS data is     |
//|    contaminated. The Roadmap's answer is Phase 16 (freeze, new     |
//|    version, NEW OOS data) - the report says so.                    |
//| 6) Each range is simulated from a cold start (warm-up bars are     |
//|    consumed inside the range) - same documented limitation as      |
//|    Phase 13. ID format "OOS_%06d", per-instance counter.           |
//+------------------------------------------------------------------+
#ifndef __GZ_FINALOOS_TYPES_MQH__
#define __GZ_FINALOOS_TYPES_MQH__

#include "..\Core\GZ_Types.mqh"
#include "..\Core\GZ_Constants.mqh"
#include "..\Experiment\GZ_ExperimentTypes.mqh"
#include "..\Metrics\GZ_MetricsTypes.mqh"

#define GZ_MAX_OOS_NOTES 8

enum ENUM_GZ_OOS_STATUS
  {
   GZ_OOS_OK = 0,
   GZ_OOS_REJECTED_BAD_RANGE,   // OOS end <= OOS start
   GZ_OOS_REJECTED_OVERLAP,     // OOS start earlier than the Development range end (design note 1)
   GZ_OOS_NO_DEV_DATA,          // no Development M5 bars to compare against
   GZ_OOS_NO_OOS_DATA           // no OOS M5 bars (after boundary trimming)
  };

string GZOosStatusToString(ENUM_GZ_OOS_STATUS s)
  {
   switch(s)
     {
      case GZ_OOS_OK:                return "OK";
      case GZ_OOS_REJECTED_BAD_RANGE:return "REJECTED_BAD_RANGE";
      case GZ_OOS_REJECTED_OVERLAP:  return "REJECTED_OVERLAP";
      case GZ_OOS_NO_DEV_DATA:       return "NO_DEV_DATA";
      case GZ_OOS_NO_OOS_DATA:       return "NO_OOS_DATA";
      default:                       return "UNKNOWN";
     }
  }

struct GZ_FinalOosResult
  {
   string               id;
   ENUM_GZ_OOS_STATUS   status;
   string               strategy_version;
   GZ_ExperimentConfig  config;             // the frozen configuration used for BOTH ranges

   datetime             dev_req_start, dev_req_end;   // requested ranges
   datetime             oos_req_start, oos_req_end;
   datetime             dev_first, dev_last;          // actual first/last M5 bar used
   datetime             oos_first, oos_last;
   int                  dev_m5_bars;
   int                  oos_m5_bars;
   int                  oos_boundary_bars_dropped;    // design note 3 (M5 + M1 together)
   ENUM_GZ_VALIDATION_STATUS oos_m1_status, oos_m5_status;

   GZ_MetricsSummary    dev;                 // Development-range Phase 8 summary
   GZ_MetricsSummary    oos;                 // Final OOS Phase 8 summary

   //--- Comparison (design note 4); deltas are OOS minus Development
   double               expectancy_delta;
   double               win_rate_delta;
   double               profit_factor_delta;
   bool                 profit_factor_delta_defined;
   double               max_dd_delta;
   double               avg_mae_delta;
   double               avg_mfe_delta;
   bool                 retention_defined;
   double               expectancy_retention;
   bool                 low_oos_trades;
   bool                 oos_no_trades;
   bool                 oos_negative;
   bool                 oos_degraded;

   string               notes[GZ_MAX_OOS_NOTES];
   int                  note_count;

   void ClearComparison()
     {
      expectancy_delta = 0.0; win_rate_delta = 0.0; profit_factor_delta = 0.0; profit_factor_delta_defined = false;
      max_dd_delta = 0.0; avg_mae_delta = 0.0; avg_mfe_delta = 0.0;
      retention_defined = false; expectancy_retention = 0.0;
      low_oos_trades = false; oos_no_trades = false; oos_negative = false; oos_degraded = false;
     }

   void Clear()
     {
      id = ""; status = GZ_OOS_OK; strategy_version = "";
      config.Default();
      dev_req_start = 0; dev_req_end = 0; oos_req_start = 0; oos_req_end = 0;
      dev_first = 0; dev_last = 0; oos_first = 0; oos_last = 0;
      dev_m5_bars = 0; oos_m5_bars = 0; oos_boundary_bars_dropped = 0;
      oos_m1_status = GZ_VAL_UNKNOWN; oos_m5_status = GZ_VAL_UNKNOWN;
      dev.Clear(); oos.Clear();
      ClearComparison();
      for(int i=0;i<GZ_MAX_OOS_NOTES;i++) notes[i]="";
      note_count = 0;
     }

   void AddNote(string n)
     {
      if(note_count<GZ_MAX_OOS_NOTES)
        {
         notes[note_count] = n;
         note_count++;
        }
     }
  };

#endif // __GZ_FINALOOS_TYPES_MQH__
