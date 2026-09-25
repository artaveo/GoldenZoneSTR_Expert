//+------------------------------------------------------------------+
//| GZ_RewardBeTypes.mqh                                              |
//| GoldenZone STR - Phase 15.5 - Reward / TP x Risk-Free (BE)        |
//| Research Matrix - Types                                            |
//|                                                                    |
//| Types only (no simulation, no analysis) - same discipline as every |
//| other *Types.mqh file in this repo.                                |
//|                                                                    |
//| DESIGN NOTES                                                       |
//| 1) GRIDS (revised twice): TP 0.5R..4.5R in 0.5R steps (9 values).   |
//|    For every TP: BE OFF + BE triggers strictly below TP, with 0.25R |
//|    and 0.75R never used. TP<2R: TP0.5 none, TP1.0 -> 0.5, TP1.5 ->  |
//|    1.0. TP>=2R: whole-R triggers only (1,2,3,4 that are < TP). A BE |
//|    trigger >=TP |
//|    is NEVER executed (TP is evaluated before BE arming on every     |
//|    bar, so such a run would just repeat BE OFF).                     |
//|    BE LEVEL = Entry, offset = 0R ONLY. Main matrix = 26 configs     |
//|    (9 OFF + 17 BE-active) + ONE high-TP reference run.               |
//| 2) ROW KINDS. OFF = BE disabled. BE_ACTIVE = 0 < trigger < TP.      |
//|    BE_INACTIVE_EQUIVALENT is kept as an enum value for labeling only|
//|    and is never produced by the engine. REFERENCE_ONLY /            |
//|    HIGH_TP_REACH_REFERENCE = the TP=1000R / BE-off run (reduced-    |
//|    censoring reach diagnostic; NOT a strategy TP, NOT in the TP     |
//|    grid, NOT rankable; a tiny-risk trade CAN reach 1000R).           |
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
#include "..\Cost\GZ_CostTypes.mqh"

#define GZ_RB_TP_COUNT           9
#define GZ_RB_BE_STEP_R          0.25   // BE trigger step (R)
#define GZ_RB_MAX_TP_R           4.5    // highest TP of the main matrix
#define GZ_RB_WHOLE_R_FROM_TP    2.0    // from this TP upward only whole-R BE triggers (1R,2R,...) are used
#define GZ_RB_EXIT_SLOTS         7      // indexed by ENUM_GZ_EXIT_REASON value; slot 0 (NONE) unused
#define GZ_RB_REFERENCE_TP_R     1000.0 // very high TP used ONLY for the HIGH_TP_REACH_REFERENCE run (not a strategy TP)
#define GZ_RB_EPS                1.0e-9

//--- TP grid: 0.5R .. 4.5R step 0.5R (9 values). 5.0R is intentionally absent.
void GZRewardBeTpGrid(double &out[])
  {
   ArrayResize(out, GZ_RB_TP_COUNT);
   out[0]=0.5; out[1]=1.0; out[2]=1.5; out[3]=2.0; out[4]=2.5;
   out[5]=3.0; out[6]=3.5; out[7]=4.0; out[8]=4.5;
  }

//--- BE triggers for one TP (user-defined reduced grid). Always strictly below TP; BE OFF is separate.
//---  TP < 2R : TP 0.5: none | TP 1.0: 0.5 | TP 1.5: 1.0   (never 0.25R or 0.75R)
//---  TP >= 2R: whole-R triggers only (1R, 2R, 3R, 4R) that are < TP
//---             -> TP 2.0: 1 | 2.5: 1,2 | 3.0: 1,2 | 3.5: 1,2,3 | 4.0: 1,2,3 | 4.5: 1,2,3,4
//--- Integer arithmetic on quarter-R units. A trigger >= TP is never produced. Returns the count (may be 0).
int GZRewardBeTriggersForTp(double tp, double &out[])
  {
   int tp_q = (int)MathRound(tp/GZ_RB_BE_STEP_R);     // TP in 0.25R units
   ArrayResize(out, 0);
   int n = 0;
   if(tp < GZ_RB_WHOLE_R_FROM_TP-1.0e-9)
     {
      if(tp_q==4)      { ArrayResize(out, 1); out[n++] = 0.5; }   // TP 1.0R -> BE 0.5R
      else if(tp_q==6) { ArrayResize(out, 1); out[n++] = 1.0; }   // TP 1.5R -> BE 1.0R
      // TP 0.5R -> BE OFF only
     }
   else
     {
      for(int q=4; q<tp_q; q+=4)                        // 1R, 2R, 3R, ... (whole R) strictly below TP
        {
         ArrayResize(out, n+1);
         out[n++] = q*GZ_RB_BE_STEP_R;
        }
     }
   return n;
  }

enum ENUM_GZ_RB_KIND
  {
   GZ_RB_OFF = 0,                    // BE disabled
   GZ_RB_BE_ACTIVE,                  // trigger < TP
   GZ_RB_BE_INACTIVE_EQUIVALENT,     // label only - trigger >= TP is never executed in the revised matrix
   GZ_RB_REFERENCE_ONLY              // TP=1000R, BE off (HIGH_TP_REACH_REFERENCE)
  };

string GZRewardBeKindToString(ENUM_GZ_RB_KIND k)
  {
   switch(k)
     {
      case GZ_RB_OFF:                     return "BE_OFF";
      case GZ_RB_BE_ACTIVE:               return "BE_ACTIVE";
      case GZ_RB_BE_INACTIVE_EQUIVALENT:  return "BE_INACTIVE_EQUIVALENT";
      case GZ_RB_REFERENCE_ONLY:          return "REFERENCE_ONLY/HIGH_TP_REACH_REFERENCE";
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

   //--- Journal accounting diagnostics (MFE/MAE/Reach are updated with the FULL candle range, exit candle included)
   int              mfe_set_on_exit_bar;               // trades whose final MFE was last set on their exit candle
   int              mae_set_on_exit_bar;               // trades whose final MAE was last set on their exit candle
   int              tp_exit_mfe_overshoot;             // TP_HIT trades whose MFE exceeds the TP R (exit candle high beyond TP)
   int              sl_exit_mae_beyond_stop;           // SL_HIT trades whose MAE exceeds 1R (exit candle low beyond the stop)

   GZ_PairStats     pair;                              // vs BE-off run of the same TP (valid only for BE runs)

   GZ_NetSummary    net;                               // Phase 15.8 Part B: post-hoc net-of-cost figures (gross fields above are never changed)

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
      mfe_set_on_exit_bar=0; mae_set_on_exit_bar=0; tp_exit_mfe_overshoot=0; sl_exit_mae_beyond_stop=0;
      pair.Clear();
      net.Clear();
     }
  };

#endif // __GZ_REWARDBE_TYPES_MQH__
