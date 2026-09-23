//+------------------------------------------------------------------+
//| GZ_MetricsEngine.mqh                                              |
//| GoldenZone STR - Phase 8 - Metrics + Reporting                    |
//|                                                                    |
//| Research Adapter concern (Roadmap Phase 17 vocabulary, same as    |
//| CGZTradeSimulator - see that file's header): a deterministic,     |
//| POST-HOC aggregator over an already-finished CGZJournalEngine      |
//| (Phase 7), the same construction model CGZEventLedger already      |
//| uses for the same reason (see GZ_EventLedger.mqh header) - every   |
//| metric here is fully determined by each GZ_TradeJournal's own,     |
//| already-final fields, so ONE pass, called ONCE after the replay    |
//| finishes, is enough. No bar-by-bar hook, no strategy decisions,    |
//| no mutation of anything Phase 1-7 produced.                        |
//|                                                                    |
//| See GZ_MetricsTypes.mqh for the full set of documented scope       |
//| decisions (population = closed trades only, R-based metrics,       |
//| Expectancy==Average R, Profit-Factor-undefined flag, drawdown/      |
//| streak methodology, breakdown dimensions, Filter Diagnostics stub).|
//+------------------------------------------------------------------+
#ifndef __GZ_METRICS_ENGINE_MQH__
#define __GZ_METRICS_ENGINE_MQH__

#include "GZ_MetricsTypes.mqh"
#include "..\Journal\GZ_JournalTypes.mqh"
#include "..\Journal\GZ_JournalEngine.mqh"
#include "..\Time\GZ_TimeEngine.mqh"
#include "..\Time\GZ_Session.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

//+------------------------------------------------------------------+
//| Running accumulator folded one closed trade at a time, then       |
//| reduced into a public GZ_TradeStats by CGZMetricsEngine::         |
//| Finalize(). Kept separate from GZ_TradeStats itself (and at file  |
//| scope, not nested in the class, matching this repo's convention   |
//| of no nested types elsewhere) so the public type in                |
//| GZ_MetricsTypes.mqh stays free of internal running-sum fields -    |
//| this struct is purely CGZMetricsEngine's own scratch space, never  |
//| exposed on GZ_MetricsSummary.                                      |
//+------------------------------------------------------------------+
struct GZ_MetricsAccum
  {
   int      trade_count;
   int      winners;
   int      losers;
   double   sum_r;
   double   sum_win_r;
   double   sum_loss_r; // magnitude, >=0.0

   void Clear() { trade_count=0; winners=0; losers=0; sum_r=0.0; sum_win_r=0.0; sum_loss_r=0.0; }
  };

class CGZMetricsEngine
  {
private:
   CGZLogger        *m_logger;

   void AccumulateOne(GZ_MetricsAccum &acc, double r) const
     {
      acc.trade_count++;
      acc.sum_r += r;
      if(r>0.0)
        {
         acc.winners++;
         acc.sum_win_r += r;
        }
      else if(r<0.0)
        {
         acc.losers++;
         acc.sum_loss_r += (-r);
        }
      // r==0.0 (breakeven): counted in trade_count only - design note 1 (GZ_MetricsTypes.mqh)
     }

   void Finalize(const GZ_MetricsAccum &acc, GZ_TradeStats &out) const
     {
      out.Clear();
      out.trade_count = acc.trade_count;
      out.winners     = acc.winners;
      out.losers      = acc.losers;
      out.net_r        = acc.sum_r;
      out.avg_r        = (acc.trade_count>0) ? acc.sum_r/acc.trade_count : 0.0;
      out.expectancy   = out.avg_r; // design note 3 (GZ_MetricsTypes.mqh) - intentionally identical
      out.win_rate     = (acc.trade_count>0) ? (double)acc.winners/acc.trade_count : 0.0;
      out.avg_win_r    = (acc.winners>0) ? acc.sum_win_r/acc.winners : 0.0;
      out.avg_loss_r   = (acc.losers>0)  ? acc.sum_loss_r/acc.losers : 0.0;

      if(acc.sum_loss_r>0.0)
        {
         out.profit_factor           = acc.sum_win_r/acc.sum_loss_r;
         out.profit_factor_undefined = false;
        }
      else
        {
         out.profit_factor           = 0.0;                    // design note 4 - documented placeholder
         out.profit_factor_undefined = (acc.sum_win_r>0.0);     // winners, no losers -> mathematically infinite
        }
     }

   //--- Risk stats over the chronological (exit-order) realized-R
   //--- sequence - see GZ_MetricsTypes.mqh design note 5.
   void ComputeRisk(const double &r_sequence[], GZ_RiskStats &out) const
     {
      out.Clear();
      int n = ArraySize(r_sequence);
      if(n==0)
         return;

      double equity = 0.0, peak = 0.0;
      double max_dd  = 0.0;
      int    dd_len  = 0, max_dd_len = 0;

      bool   in_drawdown    = false;
      double episode_peak_dd = 0.0;
      double dd_episode_sum  = 0.0;
      int    dd_episode_count= 0;

      int win_streak=0, lose_streak=0, max_win_streak=0, max_lose_streak=0;

      for(int i=0;i<n;i++)
        {
         equity += r_sequence[i];

         if(equity>peak)
           {
            // New equity high - close out any drawdown episode in progress.
            if(in_drawdown)
              {
               dd_episode_sum += episode_peak_dd;
               dd_episode_count++;
               in_drawdown     = false;
               episode_peak_dd = 0.0;
              }
            peak   = equity;
            dd_len = 0;
           }
         else
           {
            dd_len++;
            double dd = peak - equity;
            if(dd>0.0)
              {
               in_drawdown = true;
               if(dd>episode_peak_dd)
                  episode_peak_dd = dd;
              }
            if(dd>max_dd)
               max_dd = dd;
            if(dd_len>max_dd_len)
               max_dd_len = dd_len;
           }

         if(r_sequence[i]>0.0)
           {
            win_streak++; lose_streak=0;
            if(win_streak>max_win_streak) max_win_streak=win_streak;
           }
         else if(r_sequence[i]<0.0)
           {
            lose_streak++; win_streak=0;
            if(lose_streak>max_lose_streak) max_lose_streak=lose_streak;
           }
         else
           {
            // Breakeven trade: documented as breaking both streaks (design
            // note 5 - a flat outcome is neither a win nor a loss streak
            // continuation).
            win_streak=0; lose_streak=0;
           }
        }

      // An episode still open when the sequence ends still counts (the
      // drawdown genuinely happened, even though no new high followed it
      // within this dataset).
      if(in_drawdown)
        {
         dd_episode_sum += episode_peak_dd;
         dd_episode_count++;
        }

      out.max_drawdown_r               = max_dd;
      out.avg_drawdown_r               = (dd_episode_count>0) ? dd_episode_sum/dd_episode_count : 0.0;
      out.max_drawdown_duration_trades = max_dd_len;
      out.max_winning_streak           = max_win_streak;
      out.max_losing_streak            = max_lose_streak;
     }

   //--- Shared aggregation core (Phase 8, unmodified) plus an OPTIONAL
   //--- Phase 10 inclusion mask - see Compute()/ComputeFiltered() below.
   //--- use_mask==false reproduces the exact Phase 8 behavior (every
   //--- closed journal entry included) with zero new branching cost for
   //--- every caller written before Phase 10 existed. When use_mask is
   //--- true, mask[i] (aligned 1:1 with journal_engine.GetJournal(i), the
   //--- SAME index space CGZFilterEngine's caller builds it in - see
   //--- GoldenZoneSTR_Research.mq5) decides whether journal entry i is
   //--- folded into the summary at all; mask is never consulted for an
   //--- OPEN journal entry (design note 1, GZ_MetricsTypes.mqh - those
   //--- are already excluded either way).
   void ComputeInternal(CGZJournalEngine &journal_engine, CGZTimeEngine &time_engine,
                         CGZSessionEngine &session_engine, const GZ_SessionProfile &session_profile,
                         bool use_mask, const bool &mask[], GZ_MetricsSummary &out) const
     {
      out.Clear();

      int n = journal_engine.JournalCount();

      GZ_MetricsAccum total; total.Clear();
      GZ_MetricsAccum by_dir[GZ_BREAKDOWN_DIRECTION_COUNT];
      GZ_MetricsAccum by_sess[GZ_BREAKDOWN_SESSION_COUNT];
      GZ_MetricsAccum by_hour[GZ_BREAKDOWN_HOUR_COUNT];
      GZ_MetricsAccum by_dow[GZ_BREAKDOWN_DOW_COUNT];
      GZ_MetricsAccum by_month[GZ_BREAKDOWN_MONTH_COUNT];
      int i;
      for(i=0;i<GZ_BREAKDOWN_DIRECTION_COUNT;i++) by_dir[i].Clear();
      for(i=0;i<GZ_BREAKDOWN_SESSION_COUNT;i++)   by_sess[i].Clear();
      for(i=0;i<GZ_BREAKDOWN_HOUR_COUNT;i++)      by_hour[i].Clear();
      for(i=0;i<GZ_BREAKDOWN_DOW_COUNT;i++)       by_dow[i].Clear();
      for(i=0;i<GZ_BREAKDOWN_MONTH_COUNT;i++)     by_month[i].Clear();

      double sum_mae=0.0, sum_mfe=0.0, sum_duration=0.0, sum_ttmae=0.0, sum_ttmfe=0.0;
      int closed_count=0;

      // Chronological (exit-order) realized-R sequence for risk stats.
      // CGZTradeSimulator appends journals in the order CGZExitEngine
      // closes them, which is itself strictly bar-chronological (see
      // GZ_TradeSimulator.mqh) - no re-sort needed for a live-replay-
      // produced journal_engine. A caller feeding a hand-built/out-of-
      // order journal_engine (e.g. a unit test) is responsible for
      // supplying it in the order it wants treated as chronological,
      // same trust-the-caller convention CGZEventLedger::
      // BuildFromFinalState() already uses.
      double r_sequence[];
      ArrayResize(r_sequence, 0);

      datetime range_start = 0, range_end = 0;

      for(i=0;i<n;i++)
        {
         GZ_TradeJournal j = journal_engine.GetJournal(i);
         if(j.is_open)
            continue; // design note 1 (GZ_MetricsTypes.mqh) - closed trades only
         if(use_mask && !mask[i])
            continue; // Phase 10 - this closed trade's setup was filtered out

         closed_count++;
         double r = j.final_r;
         AccumulateOne(total, r);

         int dir_idx = (j.direction==GZ_LEG_BULLISH) ? 0 : 1;
         AccumulateOne(by_dir[dir_idx], r);

         GZ_TimeContext ctx;
         time_engine.BuildContext(j.entry_time, ctx);
         bool inside = (session_engine.Evaluate(ctx, session_profile)==GZ_SESSION_INSIDE);
         AccumulateOne(by_sess[inside?0:1], r);

         MqlDateTime dt;
         TimeToStruct(j.entry_time, dt);
         AccumulateOne(by_hour[dt.hour], r);
         AccumulateOne(by_dow[dt.day_of_week], r);
         AccumulateOne(by_month[dt.mon-1], r);

         sum_mae      += j.mae_r;
         sum_mfe      += j.mfe_r;
         sum_duration += j.duration_seconds;
         sum_ttmae    += (double)(j.time_to_mae - j.entry_time);
         sum_ttmfe    += (double)(j.time_to_mfe - j.entry_time);

         if(range_start==0 || j.entry_time<range_start) range_start = j.entry_time;
         if(range_end==0   || j.exit_time>range_end)     range_end   = j.exit_time;

         int rn = ArraySize(r_sequence);
         ArrayResize(r_sequence, rn+1);
         r_sequence[rn] = r;
        }

      Finalize(total, out.trade);

      string dow_names[7]   = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};
      string month_names[12]= {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};

      for(i=0;i<GZ_BREAKDOWN_DIRECTION_COUNT;i++)
        {
         out.by_direction[i].label = (i==0) ? "LONG" : "SHORT";
         Finalize(by_dir[i], out.by_direction[i].stats);
        }
      for(i=0;i<GZ_BREAKDOWN_SESSION_COUNT;i++)
        {
         out.by_session[i].label = (i==0) ? "INSIDE" : "OUTSIDE";
         Finalize(by_sess[i], out.by_session[i].stats);
        }
      for(i=0;i<GZ_BREAKDOWN_HOUR_COUNT;i++)
        {
         out.by_hour[i].label = StringFormat("%02d", i);
         Finalize(by_hour[i], out.by_hour[i].stats);
        }
      for(i=0;i<GZ_BREAKDOWN_DOW_COUNT;i++)
        {
         out.by_dow[i].label = dow_names[i];
         Finalize(by_dow[i], out.by_dow[i].stats);
        }
      for(i=0;i<GZ_BREAKDOWN_MONTH_COUNT;i++)
        {
         out.by_month[i].label = month_names[i];
         Finalize(by_month[i], out.by_month[i].stats);
        }

      out.behavior.avg_mae_r               = (closed_count>0) ? sum_mae/closed_count      : 0.0;
      out.behavior.avg_mfe_r               = (closed_count>0) ? sum_mfe/closed_count      : 0.0;
      out.behavior.avg_duration_seconds    = (closed_count>0) ? sum_duration/closed_count : 0.0;
      out.behavior.avg_time_to_mae_seconds = (closed_count>0) ? sum_ttmae/closed_count    : 0.0;
      out.behavior.avg_time_to_mfe_seconds = (closed_count>0) ? sum_ttmfe/closed_count    : 0.0;

      out.range_start        = range_start;
      out.range_end          = range_end;
      out.closed_trade_count = closed_count;

      // out.filters stays at its Clear()-ed default here - a WITH/WITHOUT
      // population diff needs TWO ComputeInternal() passes (unfiltered +
      // masked) to compare, which is the CALLER's job (see
      // GoldenZoneSTR_Research.mq5's Phase 10 block) - populating
      // out.filters from a single pass would be meaningless.

      ComputeRisk(r_sequence, out.risk);

      if(m_logger!=NULL)
         m_logger.Info("Metrics", StringFormat(
            "%s: closed_trades=%d net_r=%.3f avg_r=%.3f win_rate=%.1f%% pf=%s max_dd=%.3fR max_win_streak=%d max_lose_streak=%d",
            use_mask?"Metrics(filtered)":"Metrics", out.trade.trade_count, out.trade.net_r, out.trade.avg_r, out.trade.win_rate*100.0,
            out.trade.profit_factor_undefined ? "UNDEFINED(inf)" : DoubleToString(out.trade.profit_factor,3),
            out.risk.max_drawdown_r, out.risk.max_winning_streak, out.risk.max_losing_streak));
     }

public:
                     CGZMetricsEngine(CGZLogger *logger=NULL) { m_logger=logger; }

   //--- Compute the full Phase 8 summary from an already-Init()'d,
   //--- already-run CGZJournalEngine (Phase 7). time_engine/
   //--- session_engine/session_profile are used ONLY to classify each
   //--- trade's entry as inside/outside the configured session window
   //--- for the by-session breakdown - the exact same evaluation the
   //--- live pipeline already performs on every bar (see
   //--- GZ_TradeSimulator.mqh); passing the caller's own already-
   //--- configured instances guarantees this matches, rather than
   //--- re-deriving a second session concept here.
   void Compute(CGZJournalEngine &journal_engine, CGZTimeEngine &time_engine,
                CGZSessionEngine &session_engine, const GZ_SessionProfile &session_profile,
                GZ_MetricsSummary &out) const
     {
      bool dummy_mask[];
      ComputeInternal(journal_engine, time_engine, session_engine, session_profile, false, dummy_mask, out);
     }

   //--- Phase 10: identical to Compute() except journal entry i is
   //--- folded in only when mask[i]==true (ArraySize(mask) must equal
   //--- journal_engine.JournalCount() - the caller builds it by index,
   //--- aligned to GetJournal(i), typically from a CGZFilterEngine
   //--- outcome keyed by that same entry's setup_id). Used to produce
   //--- the WITH-filter population that GZ_FilterDiagnostics diffs
   //--- against an unfiltered Compute() call - see
   //--- GoldenZoneSTR_Research.mq5's Phase 10 block and T106.
   void ComputeFiltered(CGZJournalEngine &journal_engine, CGZTimeEngine &time_engine,
                         CGZSessionEngine &session_engine, const GZ_SessionProfile &session_profile,
                         const bool &mask[], GZ_MetricsSummary &out) const
     {
      ComputeInternal(journal_engine, time_engine, session_engine, session_profile, true, mask, out);
     }
  };

#endif // __GZ_METRICS_ENGINE_MQH__
