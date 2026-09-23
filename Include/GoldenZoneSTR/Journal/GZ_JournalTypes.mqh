//+------------------------------------------------------------------+
//| GZ_JournalTypes.mqh                                               |
//| GoldenZone STR - Phase 7 - MAE/MFE + R-Path - Types               |
//|                                                                    |
//| Shared struct for per-trade excursion tracking. This file         |
//| contains NO update logic (see GZ_JournalEngine.mqh) and NO        |
//| event-ledger logic (see GZ_LedgerTypes.mqh / GZ_EventLedger.mqh). |
//| Types only.                                                        |
//|                                                                    |
//| DESIGN NOTES (documented per spec Section 26 - the Roadmap         |
//| describes Phase 7 at a feature level, same situation as every      |
//| phase since Phase 3):                                              |
//|                                                                    |
//| 1) "R-multiple path". The Roadmap lists MAE, MFE, Time to MAE,     |
//|    Time to MFE, Trade duration and "R-multiple path" as separate   |
//|    items to record. Storing a full continuous bar-by-bar path for  |
//|    every trade over a multi-year M1 dataset would be memory-       |
//|    unbounded (thousands of trades x tens of thousands of open-bar  |
//|    samples each) and the Roadmap's own later use of this data      |
//|    (Phase 12 Robustness, Phase 6/Phase 11 TP/BE grid research)     |
//|    only ever needs discrete R-multiple checkpoints, not a          |
//|    continuous curve. The "R-multiple path" requirement is          |
//|    therefore satisfied here as a compact, bounded summary of that  |
//|    path: the Reach Matrix (which R-multiples of FAVORABLE          |
//|    excursion were reached, and when - see GZ_REACH_LEVELS below),  |
//|    together with MAE/MFE (the path's two extremes) and the final   |
//|    realized_r (the path's terminal point, already produced by      |
//|    Phase 6's GZ_TradeExit). This is a documented interpretation,   |
//|    not a silently reduced feature - a full continuous path is      |
//|    deliberately NOT implemented; if a later phase needs the raw    |
//|    curve, it can be re-derived by re-running the replay with       |
//|    per-bar callbacks, since everything here is already             |
//|    deterministic (see T74).                                        |
//|                                                                    |
//| 2) MAE/MFE sign convention. Both mae_r and mfe_r are stored as     |
//|    non-negative MAGNITUDES ("how many R did this trade move        |
//|    against/in-favor-of the position at its worst/best point"),     |
//|    not signed values - this avoids the ambiguity of whether an     |
//|    "MAE" of -1.2R means 1.2R adverse or a typo for +1.2R. mae_price|
//|    /mfe_price are the raw prices behind those magnitudes, useful   |
//|    for verification/plotting without re-deriving from R.           |
//|                                                                    |
//| 3) Granularity. Excursion tracking runs at M1 (execution)          |
//|    granularity exclusively - the SAME documented choice already    |
//|    made by Phase 6's Exit Engine for SL/TP/BE (see                 |
//|    GZ_ExitEngine.mqh header) - one shared, consistent granularity  |
//|    for everything that watches an open trade bar-by-bar.           |
//|                                                                    |
//| 4) Bar-range excursion (documented, deterministic - no intrabar    |
//|    path data exists, only OHLC, same limitation Phase 6 already    |
//|    documents for SL/TP hit detection): each M1 bar's full high/low |
//|    is treated as reachable excursion for MAE/MFE purposes,         |
//|    INCLUDING the bar on which the trade closes. This means a       |
//|    trade's MAE can exceed 1.0R (SL is a price level, not a hard    |
//|    ceiling on the recorded excursion - real intrabar wicks can and |
//|    do move further than the stop before the position is actually  |
//|    closed out) - this is realistic MAE/MFE behavior, not a bug.    |
//|                                                                    |
//| 5) initial_risk<=0.0 guard. Mirrors CGZExitEngine::ComputeRealizedR|
//|    's own defensive check (should not happen by construction -     |
//|    GZ_TradeExit.initial_risk is always >0 once a trade has SL/TP - |
//|    but guarded here too rather than dividing by zero): mae_r/mfe_r |
//|    simply stay 0.0 while mae_price/mfe_price still update          |
//|    normally (see T68).                                             |
//+------------------------------------------------------------------+
#ifndef __GZ_JOURNAL_TYPES_MQH__
#define __GZ_JOURNAL_TYPES_MQH__

#include "..\Leg\GZ_LegTypes.mqh"

//--- Reach Matrix grid (Roadmap Phase 7: "minimum 0.5R/1R/1.5R/.../5R").
//--- Architecture extensible: add levels here (and bump the count) if a
//--- later phase needs a finer grid - nothing else in this file assumes
//--- exactly 10 entries beyond this one definition point.
#define GZ_REACH_LEVEL_COUNT 10
const double GZ_REACH_LEVELS[GZ_REACH_LEVEL_COUNT] =
  {
   0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0
  };

//+------------------------------------------------------------------+
//| One journal record per GZ_Trade (see design notes above), keyed   |
//| by trade_id/setup_id - same join pattern as Phase 6's             |
//| GZ_TradeExit. Produced once at OnTradeEntered() and updated       |
//| bar-by-bar by CGZJournalEngine.OnBar() until the trade closes.    |
//+------------------------------------------------------------------+
struct GZ_TradeJournal
  {
   long                 trade_id;
   long                 setup_id;
   ENUM_GZ_LEG_DIR      direction;
   datetime             entry_time;
   double               entry_price;
   double               initial_risk;

   bool                 is_open;
   datetime             exit_time;
   double               exit_price;
   double               final_r;        // copy of GZ_TradeExit.realized_r once closed (0.0 while open)
   int                  duration_seconds; // exit_time-entry_time once closed (0 while open)

   double               mae_price;      // worst price reached against the position
   double               mae_r;          // magnitude, >=0.0 (design note 2)
   datetime             time_to_mae;    // time the CURRENT mae_r was (last) set/improved

   double               mfe_price;      // best price reached in favor of the position
   double               mfe_r;          // magnitude, >=0.0 (design note 2)
   datetime             time_to_mfe;    // time the CURRENT mfe_r was (last) set/improved

   bool                 reach_hit[GZ_REACH_LEVEL_COUNT];  // favorable R-levels reached (Reach Matrix)
   datetime             reach_time[GZ_REACH_LEVEL_COUNT]; // first time each level was reached (0 if never)

   void Clear()
     {
      trade_id      = 0;
      setup_id      = 0;
      direction     = GZ_LEG_BULLISH;
      entry_time    = 0;
      entry_price   = 0.0;
      initial_risk  = 0.0;
      is_open       = true;
      exit_time     = 0;
      exit_price    = 0.0;
      final_r       = 0.0;
      duration_seconds = 0;
      mae_price     = 0.0;
      mae_r         = 0.0;
      time_to_mae   = 0;
      mfe_price     = 0.0;
      mfe_r         = 0.0;
      time_to_mfe   = 0;
      for(int i=0;i<GZ_REACH_LEVEL_COUNT;i++)
        {
         reach_hit[i]  = false;
         reach_time[i] = 0;
        }
     }

   string DirectionToString() const { return (direction==GZ_LEG_BULLISH) ? "BULLISH" : "BEARISH"; }

   //--- Highest reach level actually hit, in R (0.0 if none). Convenience
   //--- accessor for reporting - not stored redundantly, derived on demand.
   double HighestReachHit() const
     {
      double best = 0.0;
      for(int i=0;i<GZ_REACH_LEVEL_COUNT;i++)
         if(reach_hit[i] && GZ_REACH_LEVELS[i]>best)
            best = GZ_REACH_LEVELS[i];
      return best;
     }
  };

#endif // __GZ_JOURNAL_TYPES_MQH__
