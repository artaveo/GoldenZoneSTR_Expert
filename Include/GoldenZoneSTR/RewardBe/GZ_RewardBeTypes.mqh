//+------------------------------------------------------------------+
//| GZ_RewardBeTypes.mqh                                              |
//| GoldenZone STR - Phase 15.5 - Reward / TP x Risk-Free (BE)        |
//| Research Matrix - Types                                            |
//|                                                                    |
//| Types only (no simulation, no analysis) - same discipline as every |
//| other *Types.mqh file in this repo.                                |
//|                                                                    |
//| DESIGN NOTES                                                       |
//| 1) GRIDS come from the Roadmap (Phase 6): TP research 0.5R..5R in  |
//|    0.5R steps (10 values); BE trigger research OFF + 0.25 0.50     |
//|    0.75 1.00 1.25 1.50 1.75 2.00 2.50 3.00 4.00 5.00 R (12 values  |
//|    + OFF). BE LEVEL = Entry, offset = 0R ONLY (approved decision;  |
//|    positive offsets are NOT part of this phase).                   |
//| 2) ROW KINDS. OFF = BE disabled. BE_ACTIVE = trigger < TP (the BE  |
//|    can arm before TP is reachable). BE_INACTIVE_EQUIVALENT =        |
//|    trigger >= TP: TP is evaluated before BE arming on every bar,   |
//|    so such a run is mechanically identical to OFF - it is run ONLY |
//|    as a validation, never presented as an independent BE config.    |
//|    REFERENCE_ONLY = the TP=1000R / BE-off UNCENSORED_REACH run; it |
//|    is a measurement instrument, NOT a strategy configuration.       |
//| 3) REACH vs EXIT stay separate: reach_count[] is "how many trades   |
//|    touched +xR while OPEN in THIS run" (censored by that run's own  |
//|    exits); exit_count[] / win_rate come from realized R. Nothing    |
//|    in this phase derives a TP win rate from a reach count.          |
//| 4) Fixed-size arrays only inside structs (repo convention).         |
//+------------------------------------------------------------------+
#ifndef __GZ_REWARDBE_TYPES_MQH__
#define __GZ_REWARDBE_TYPES_MQH__

#include "..\Core\GZ_Types.mqh"
#include "..\Exit\GZ_ExitTypes.mqh"
#include "..\Journal\GZ_JournalTypes.mqh"

#define GZ_RB_TP_COUNT           10
#define GZ_RB_TRIGGER_COUNT      12
#define GZ_RB_EXIT_SLOTS         7      // indexed by ENUM_GZ_EXIT_REASON value; slot 0 (NONE) unused
#define GZ_RB_REFERENCE_TP_R     1000.0 // "unreachable" TP for the uncensored reach reference run
#define GZ_RB_EPS                1.0e-9

//--- TP grid (Roadmap Phase 6 "TP Research")
void GZRewardBeTpGrid(double &out[])
  {
   ArrayResize(out, GZ_RB_TP_COUNT);
   out[0]=0.5; out[1]=1.0; out[2]=1.5; out[3]=2.0; out[4]=2.5;
   out[5]=3.0; out[6]=3.5; out[7]=4.0; out[8]=4.5; out[9]=5.0;
  }

//--- BE trigger grid (Roadmap Phase 6 "BE Research"; OFF is handled separately as trigger 0.0)
void GZRewardBeTriggerGrid(double &out[])
  {
   ArrayResize(out, GZ_RB_TRIGGER_COUNT);
   out[0]=0.25; out[1]=0.50; out[2]=0.75; out[3]=1.00; out[4]=1.25; out[5]=1.50;
   out[6]=1.75; out[7]=2.00; out[8]=2.50; out[9]=3.00; out[10]=4.00; out[11]=5.00;
  }

enum ENUM_GZ_RB_KIND
  {
   GZ_RB_OFF = 0,                    // BE disabled
   GZ_RB_BE_ACTIVE,                  // trigger < TP
   GZ_RB_BE_INACTIVE_EQUIVALENT,     // trigger >= TP (validation run only)
   GZ_RB_REFERENCE_ONLY              // TP=1000R, BE off (UNCENSORED_REACH)
  };

string GZRewardBeKindToString(ENUM_GZ_RB_KIND k)
  {
   switch(k)
     {
      case GZ_RB_OFF:                     return "BE_OFF";
      case GZ_RB_BE_ACTIVE:               return "BE_ACTIVE";
      case GZ_RB_BE_INACTIVE_EQUIVALENT:  return "BE_INACTIVE_EQUIVALENT";
      case GZ_RB_REFERENCE_ONLY:          return "REFERENCE_ONLY/UNCENSORED_REACH";
     }
   return "UNKNOWN";
  }

enum ENUM_GZ_RB_STATUS
  {
   GZ_RB_STATUS_OK = 0,
   GZ_RB_STATUS_NO_DATA,
   GZ_RB_STATUS_REJECTED_OOS_OVERLAP   // dev range end is after the protected OOS start
  };

//--- Pairwise (BE OFF vs BE ON, same TP) transition counts, joined by stable trade_id.
//---  A: SL_HIT (off) -> BREAK_EVEN (on)   BE protected a trade from a full SL
//---  B: TP_HIT (off) -> BREAK_EVEN (on)   BE exited a trade that later reached TP
//---  C: TP_HIT -> TP_HIT                  no exit-state change
//---  D: SL_HIT -> SL_HIT                  no exit-state change (BE never armed)
//---  E: everything else (split into e_* sub-counters)
struct GZ_PairStats
  {
   bool     valid;
   int      matched;
   int      unmatched_on;
   int      unmatched_off;
   int      entry_mismatch;      // matched trades whose id/entry_time/entry_price/direction differ (must be 0)
   int      off_tp_total;        // OFF-run TP_HIT trades among matched
   int      off_sl_total;        // OFF-run SL_HIT trades among matched

   int      cat_a, cat_b, cat_c, cat_d, cat_e;
   int      e_be_from_other;     // off exit not TP/SL (e.g. DATA_END/SESSION_EXIT) -> BREAK_EVEN
   int      e_same_other;        // same non-TP/SL reason on both sides
   int      e_anomaly;           // any other reason change (not expected from a BE-only difference)

   int      no_change;           // same exit reason AND same R
   int      be_armed_total;      // BE-on trades whose BE armed at any time
   int      be_armed_no_change;  // ... and whose exit reason/R still equals OFF's

   double   dr_a, dr_b, dr_c, dr_d, dr_e; // sum of (R_on - R_off) per category
   double   dr_total;

   void Clear()
     {
      valid=false; matched=0; unmatched_on=0; unmatched_off=0; entry_mismatch=0; off_tp_total=0; off_sl_total=0;
      cat_a=0; cat_b=0; cat_c=0; cat_d=0; cat_e=0; e_be_from_other=0; e_same_other=0; e_anomaly=0;
      no_change=0; be_armed_total=0; be_armed_no_change=0;
      dr_a=0.0; dr_b=0.0; dr_c=0.0; dr_d=0.0; dr_e=0.0; dr_total=0.0;
     }
  };

//--- One experiment's full descriptive row (Section A-F of the report).
struct GZ_RewardBeRow
  {
   int              run_index;
   string           experiment_id;
   ENUM_GZ_RB_KIND  kind;
   double           tp_r;
   double           be_trigger_r;   // 0.0 = OFF
   double           be_offset_r;    // always 0.0 in this phase

   int              trades, winners, losers, flat;   // flat = realized R exactly 0
   double           win_rate, loss_rate, be_rate;     // be_rate = BREAK_EVEN exits / trades
   double           expectancy, profit_factor;
   bool             pf_undefined;
   double           net_r, avg_win_r, avg_loss_r;

   double           max_dd_r;
   int              max_lose_streak;
   double           avg_lose_streak;
   double           max_mae_r, avg_mae_r, max_mfe_r, avg_mfe_r;

   int              exit_count[GZ_RB_EXIT_SLOTS];     // by ENUM_GZ_EXIT_REASON value
   int              reach_count[GZ_REACH_LEVEL_COUNT];// measured WHILE OPEN in this run (exit-censored)

   int              be_armed;                          // trades whose BE armed
   int              intrabar_conflicts;                // SL and TP both touched on one candle
   int              eb_exit_total, eb_exit_tp, eb_exit_sl; // trades that CLOSED on their own entry candle
   int              be_armed_on_entry_bar;             // BE armed on the entry candle itself
   int              be_arm_retrace;                    // arming candle's own range also reached the new BE stop
   int              be_arm_retrace_non_entry;          // ... excluding entry-candle arms

   GZ_PairStats     pair;                              // vs BE-off run of the same TP (valid only for BE runs)
   bool             equiv_matches_off;                 // INACTIVE_EQUIVALENT rows: identical to OFF (expected true)

   void Clear()
     {
      run_index=0; experiment_id=""; kind=GZ_RB_OFF; tp_r=0.0; be_trigger_r=0.0; be_offset_r=0.0;
      trades=0; winners=0; losers=0; flat=0; win_rate=0.0; loss_rate=0.0; be_rate=0.0;
      expectancy=0.0; profit_factor=0.0; pf_undefined=false; net_r=0.0; avg_win_r=0.0; avg_loss_r=0.0;
      max_dd_r=0.0; max_lose_streak=0; avg_lose_streak=0.0; max_mae_r=0.0; avg_mae_r=0.0; max_mfe_r=0.0; avg_mfe_r=0.0;
      for(int i=0;i<GZ_RB_EXIT_SLOTS;i++) exit_count[i]=0;
      for(int i=0;i<GZ_REACH_LEVEL_COUNT;i++) reach_count[i]=0;
      be_armed=0; intrabar_conflicts=0; eb_exit_total=0; eb_exit_tp=0; eb_exit_sl=0;
      be_armed_on_entry_bar=0; be_arm_retrace=0; be_arm_retrace_non_entry=0;
      pair.Clear();
      equiv_matches_off=false;
     }
  };

#endif // __GZ_REWARDBE_TYPES_MQH__
