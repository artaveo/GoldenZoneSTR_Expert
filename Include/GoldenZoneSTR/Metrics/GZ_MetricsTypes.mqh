//+------------------------------------------------------------------+
//| GZ_MetricsTypes.mqh                                               |
//| GoldenZone STR - Phase 8 - Metrics + Reporting - Types            |
//|                                                                    |
//| Shared structs for the Metrics Engine. This file contains NO      |
//| aggregation logic (see GZ_MetricsEngine.mqh). Types only.         |
//|                                                                    |
//| DESIGN NOTES (documented per spec Section 26 - the Roadmap        |
//| describes Phase 8 at a feature level, same situation as every     |
//| phase since Phase 3):                                              |
//|                                                                    |
//| 1) Population = CLOSED trades only. Every metric in this file is  |
//|    computed from Phase 7's GZ_TradeJournal records with           |
//|    is_open==false (final_r/exit_time/duration_seconds are only    |
//|    meaningful once a trade has actually closed - see               |
//|    GZ_JournalTypes.mqh). An open trade contributes to neither the  |
//|    overall totals nor any breakdown bucket - this mirrors           |
//|    CGZJournalEngine::AverageMae()/AverageMfe()'s own existing       |
//|    convention, not a new one invented here.                        |
//|                                                                    |
//| 2) Currency-independent, R-based metrics. No position-sizing/      |
//|    leverage/account-currency model exists anywhere in Phases 1-7 - |
//|    every trade's outcome is already expressed only as a realized   |
//|    R-multiple (GZ_TradeExit.realized_r / GZ_TradeJournal.final_r). |
//|    Every metric here (Net R, Average R/Expectancy, Profit Factor,  |
//|    drawdown, streaks, etc.) is therefore computed in R-multiples,  |
//|    not account currency - a documented scope interpretation, not   |
//|    a silently dropped feature (a currency P&L model would need a   |
//|    position-sizing/risk-per-trade input the Roadmap never          |
//|    specifies for any earlier phase).                               |
//|                                                                    |
//| 3) Expectancy vs Average R. The Roadmap's Trade Metrics list names |
//|    "Expectancy" and "Average R" as two separate bullets. With no   |
//|    separate per-trade risk-weighting model (design note 2), both   |
//|    reduce to the exact same formula (net_r/trade_count) - both     |
//|    fields are exposed for direct Roadmap traceability but are      |
//|    documented here as intentionally identical, not a duplication   |
//|    bug.                                                             |
//|                                                                    |
//| 4) avg_loss_r / Profit Factor sign convention. avg_loss_r is a     |
//|    non-negative MAGNITUDE (mirrors GZ_TradeJournal.mae_r/mfe_r's   |
//|    own documented convention in GZ_JournalTypes.mqh design note 2),|
//|    not a signed value. Profit Factor = sum(winning R)/sum(|losing  |
//|    R|); when there are winners but no losers the true mathematical |
//|    value is infinite - profit_factor_undefined flags this case     |
//|    explicitly (profit_factor itself is reported as 0.0 in that     |
//|    case, a documented placeholder, never a silently fabricated     |
//|    number standing in for infinity).                               |
//|                                                                    |
//| 5) Risk stats (drawdown/streaks) run over the CLOSED-trade R       |
//|    equity curve in trade-completion (exit-time) order - the only   |
//|    already-available, currency-independent ordered series (see     |
//|    design note 2). Max Drawdown Duration is reported in TRADE      |
//|    COUNT (bars-of-equity-curve), not wall-clock time, since no     |
//|    continuous per-bar equity series is retained (same bounded-      |
//|    checkpoint philosophy already documented in GZ_JournalTypes.mqh |
//|    design note 1 for the Reach Matrix). Average Drawdown is the    |
//|    mean DEPTH (in R) of every distinct drawdown episode (a run of  |
//|    trades strictly below the running equity peak), including an    |
//|    unfinished episode still open when the data ends.                |
//|                                                                    |
//| 6) Breakdown dimensions (Roadmap: "Long/Short, Hour, Session, Day  |
//|    of week, Month, Date range"). Long/Short/Session/Day-of-week/   |
//|    Month are implemented as fixed-size bucket arrays, each holding |
//|    the same GZ_TradeStats used for the overall total - no new      |
//|    metric formulas, just the same ones applied to a subset. "Hour" |
//|    buckets the entry timestamp's own BROKER-CLOCK hour (0-23) -    |
//|    every timestamp already flowing through this pipeline is a      |
//|    broker timestamp (see GZ_TimeEngine.mqh); a caller wanting an   |
//|    NY-hour breakdown can already convert via the exposed            |
//|    CGZTimeEngine before/after calling this engine. "Session" uses  |
//|    the SAME CGZSessionEngine::Evaluate() the live pipeline itself   |
//|    already evaluates trades against (see GZ_TradeSimulator.mqh) -  |
//|    no second session-window concept invented. "Date range" is NOT  |
//|    implemented as a further breakdown array here: slicing an        |
//|    arbitrary sub-range is what Phase 9's Experiment Runner          |
//|    (SINGLE/SWEEP/GRID/BATCH over a configured date range) already   |
//|    exists to do - this engine instead reports the single overall    |
//|    [range_start,range_end] the supplied trades actually span, so    |
//|    the summary is self-describing without re-implementing Phase 9. |
//|                                                                    |
//| 7) Filter Diagnostics (Roadmap: "Setups before/after, Trades       |
//|    before/after, Rejections, Win-rate/PF/Expectancy/DD/Trade-count |
//|    deltas") needed a Filter Engine producing a WITH-filter and      |
//|    WITHOUT-filter population to diff - Phase 10's CGZFilterEngine   |
//|    (see GZ_Filter\GZ_FilterEngine.mqh) now IS that producer.        |
//|    GZ_FilterDiagnostics.available is true exactly when the caller   |
//|    ran that WITH/WITHOUT diff (GoldenZoneSTR_Research.mq5's Phase   |
//|    10 block: CGZMetricsEngine::Compute() for the unfiltered         |
//|    population, ::ComputeFiltered() for the filtered one, diffed     |
//|    field-by-field into this struct) - still false/zero from a bare  |
//|    CGZMetricsEngine::Compute() call with no such diff performed     |
//|    (e.g. every Phase 1-9 test in this harness), which is exactly    |
//|    the "available" flag's purpose: distinguish "no filter diagnostic|
//|    was computed for this summary" from "filters were computed and   |
//|    changed nothing" (both leave the delta fields at/near 0).        |
//+------------------------------------------------------------------+
#ifndef __GZ_METRICS_TYPES_MQH__
#define __GZ_METRICS_TYPES_MQH__

#include "..\Leg\GZ_LegTypes.mqh"

#define GZ_BREAKDOWN_DIRECTION_COUNT  2   // 0=LONG(bullish) 1=SHORT(bearish)
#define GZ_BREAKDOWN_SESSION_COUNT    2   // 0=INSIDE 1=OUTSIDE
#define GZ_BREAKDOWN_HOUR_COUNT       24  // broker-clock hour of entry, 0-23
#define GZ_BREAKDOWN_DOW_COUNT        7   // MqlDateTime.day_of_week, 0=Sunday
#define GZ_BREAKDOWN_MONTH_COUNT      12  // MqlDateTime.mon-1, 0=January

//+------------------------------------------------------------------+
//| One population's Trade Metrics (Roadmap Phase 8 "Trade Metrics"   |
//| list). Reused identically for the overall total and for every     |
//| breakdown bucket (design note 6) - same formulas, different       |
//| subset of closed trades.                                          |
//+------------------------------------------------------------------+
struct GZ_TradeStats
  {
   int      trade_count;
   int      winners;
   int      losers;              // trade_count-winners-losers = breakeven (final_r==0.0) trades
   double   win_rate;             // winners/trade_count, 0.0 if trade_count==0
   double   avg_win_r;            // mean realized R of winners only (0.0 if none)
   double   avg_loss_r;           // mean |realized R| of losers only, magnitude (design note 4)
   double   profit_factor;        // sum(win R)/sum(|loss R|); see profit_factor_undefined
   bool     profit_factor_undefined; // true = winners exist with zero losing R (mathematically infinite - design note 4)
   double   expectancy;           // == avg_r (design note 3)
   double   net_r;                // sum of realized R across the population
   double   avg_r;                // net_r/trade_count, 0.0 if trade_count==0

   void Clear()
     {
      trade_count             = 0;
      winners                 = 0;
      losers                  = 0;
      win_rate                = 0.0;
      avg_win_r                = 0.0;
      avg_loss_r               = 0.0;
      profit_factor            = 0.0;
      profit_factor_undefined  = false;
      expectancy               = 0.0;
      net_r                    = 0.0;
      avg_r                    = 0.0;
     }
  };

//+------------------------------------------------------------------+
//| Overall Risk Metrics (Roadmap Phase 8 "Risk" list) - see design   |
//| note 5. Computed ONLY over the overall population; per-Roadmap,   |
//| drawdown/streaks are not listed as a Breakdown dimension.         |
//+------------------------------------------------------------------+
struct GZ_RiskStats
  {
   double   max_drawdown_r;               // deepest peak-to-trough decline, in R
   double   avg_drawdown_r;               // mean depth of every distinct drawdown episode, in R
   int      max_drawdown_duration_trades; // length (in closed trades) of the deepest-drawdown's episode
   int      max_winning_streak;           // longest run of consecutive winners (final_r>0.0)
   int      max_losing_streak;            // longest run of consecutive losers (final_r<0.0)

   void Clear()
     {
      max_drawdown_r               = 0.0;
      avg_drawdown_r               = 0.0;
      max_drawdown_duration_trades = 0;
      max_winning_streak           = 0;
      max_losing_streak            = 0;
     }
  };

//+------------------------------------------------------------------+
//| Overall Behavior Metrics (Roadmap Phase 8 "Behavior" list),       |
//| averaged straight from Phase 7's GZ_TradeJournal records.         |
//+------------------------------------------------------------------+
struct GZ_BehaviorStats
  {
   double   avg_mae_r;                  // mean MAE magnitude, in R
   double   avg_mfe_r;                  // mean MFE magnitude, in R
   double   avg_duration_seconds;       // mean entry->exit duration
   double   avg_time_to_mae_seconds;    // mean entry->time_to_mae offset
   double   avg_time_to_mfe_seconds;    // mean entry->time_to_mfe offset

   void Clear()
     {
      avg_mae_r                = 0.0;
      avg_mfe_r                = 0.0;
      avg_duration_seconds     = 0.0;
      avg_time_to_mae_seconds  = 0.0;
      avg_time_to_mfe_seconds  = 0.0;
     }
  };

//+------------------------------------------------------------------+
//| One labeled Breakdown bucket (design note 6) - a label plus the   |
//| same GZ_TradeStats formulas applied to just that bucket's trades. |
//+------------------------------------------------------------------+
struct GZ_BreakdownBucket
  {
   string          label;
   GZ_TradeStats   stats;

   void Clear()
     {
      label = "";
      stats.Clear();
     }
  };

//+------------------------------------------------------------------+
//| Phase 10 Filter Diagnostics (design note 7) - a WITH-filter vs    |
//| WITHOUT-filter population diff. CGZMetricsEngine itself never     |
//| populates this struct (it stays at Clear()'s zero/false default   |
//| from either Compute() or ComputeFiltered() alone) - the CALLER    |
//| fills it by diffing two GZ_MetricsSummary.trade/.risk results.    |
//+------------------------------------------------------------------+
struct GZ_FilterDiagnostics
  {
   bool     available;              // always false in this build (design note 7)
   int      setups_before;
   int      setups_after;
   int      trades_before;
   int      trades_after;
   int      rejections;
   double   win_rate_delta;
   double   profit_factor_delta;
   double   expectancy_delta;
   double   max_drawdown_delta;
   int      trade_count_delta;

   void Clear()
     {
      available            = false;
      setups_before        = 0;
      setups_after         = 0;
      trades_before        = 0;
      trades_after         = 0;
      rejections           = 0;
      win_rate_delta       = 0.0;
      profit_factor_delta  = 0.0;
      expectancy_delta     = 0.0;
      max_drawdown_delta   = 0.0;
      trade_count_delta    = 0;
     }
  };

//+------------------------------------------------------------------+
//| Full Phase 8 output - one call to CGZMetricsEngine::Compute()     |
//| fills exactly one of these from an already-final CGZJournalEngine |
//| (Phase 7). See GZ_MetricsEngine.mqh for the aggregation logic.    |
//+------------------------------------------------------------------+
struct GZ_MetricsSummary
  {
   GZ_TradeStats        trade;
   GZ_RiskStats         risk;
   GZ_BehaviorStats     behavior;
   GZ_FilterDiagnostics filters;    // reserved - see design note 7

   GZ_BreakdownBucket   by_direction[GZ_BREAKDOWN_DIRECTION_COUNT];
   GZ_BreakdownBucket   by_session[GZ_BREAKDOWN_SESSION_COUNT];
   GZ_BreakdownBucket   by_hour[GZ_BREAKDOWN_HOUR_COUNT];
   GZ_BreakdownBucket   by_dow[GZ_BREAKDOWN_DOW_COUNT];
   GZ_BreakdownBucket   by_month[GZ_BREAKDOWN_MONTH_COUNT];

   datetime             range_start;  // earliest closed-trade entry_time (0 if none)
   datetime             range_end;    // latest closed-trade exit_time (0 if none)
   int                  closed_trade_count; // == trade.trade_count, kept separately for report clarity

   void Clear()
     {
      trade.Clear();
      risk.Clear();
      behavior.Clear();
      filters.Clear();
      for(int i=0;i<GZ_BREAKDOWN_DIRECTION_COUNT;i++) by_direction[i].Clear();
      for(int i=0;i<GZ_BREAKDOWN_SESSION_COUNT;i++)   by_session[i].Clear();
      for(int i=0;i<GZ_BREAKDOWN_HOUR_COUNT;i++)      by_hour[i].Clear();
      for(int i=0;i<GZ_BREAKDOWN_DOW_COUNT;i++)       by_dow[i].Clear();
      for(int i=0;i<GZ_BREAKDOWN_MONTH_COUNT;i++)     by_month[i].Clear();
      range_start        = 0;
      range_end          = 0;
      closed_trade_count = 0;
     }
  };

#endif // __GZ_METRICS_TYPES_MQH__
