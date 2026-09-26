//+------------------------------------------------------------------+
//| GZ_CostEngine.mqh                                                 |
//| GoldenZone STR - Phase 15.8 Part B - Net-of-cost R layer          |
//|                                                                    |
//| Deterministic POST-HOC pass over a finished run's per-trade record |
//| (CGZRunDetail). It never touches the simulator, the entry/exit     |
//| engines, the journal or any gross figure (see GZ_CostTypes.mqh     |
//| design notes 1-6 for the formula, the venue proposal, swap and the |
//| documented approximation).                                          |
//|                                                                    |
//| Net drawdown / streaks / profit factor / win rate are NOT           |
//| re-implemented: the net R series is fed to the EXISTING Phase 8     |
//| CGZMetricsEngine through a temporary CGZJournalEngine (the same     |
//| hand-built-journal route the unit tests use). Nothing inside the    |
//| metrics or journal engines changed.                                 |
//+------------------------------------------------------------------+
#ifndef __GZ_COST_ENGINE_MQH__
#define __GZ_COST_ENGINE_MQH__

#include "GZ_CostTypes.mqh"
#include "..\Core\GZ_Config.mqh"
#include "..\Entry\GZ_EntryTypes.mqh"
#include "..\Journal\GZ_JournalEngine.mqh"
#include "..\Metrics\GZ_MetricsTypes.mqh"
#include "..\Metrics\GZ_MetricsEngine.mqh"
#include "..\Time\GZ_TimeEngine.mqh"
#include "..\Time\GZ_Session.mqh"
#include "..\RewardBe\GZ_RunDetail.mqh"

string GZCostPadL(string s, int w) { while(StringLen(s)<w) s = " " + s; return s; }
string GZCostPadR(string s, int w) { while(StringLen(s)<w) s += " "; return s; }

//--- median of a set (even count: mean of the two middle values); 0.0 when empty
double GZCostMedian(const double &a[])
  {
   int n = ArraySize(a);
   if(n<=0) return 0.0;
   double tmp[];
   ArrayResize(tmp, n);
   ArrayCopy(tmp, a);
   ArraySort(tmp);
   if(n%2==1) return tmp[n/2];
   return 0.5*(tmp[n/2-1] + tmp[n/2]);
  }

//--- nearest-rank percentile (p in 0..100): value at index ceil(p/100*n)-1 of the ascending sort; 0.0 when empty
double GZCostPercentile(const double &a[], double p)
  {
   int n = ArraySize(a);
   if(n<=0) return 0.0;
   double tmp[];
   ArrayResize(tmp, n);
   ArrayCopy(tmp, a);
   ArraySort(tmp);
   int idx = (int)MathCeil(p/100.0*(double)n) - 1;
   if(idx < 0) idx = 0;
   if(idx > n-1) idx = n-1;
   return tmp[idx];
  }

//--- totals of the recorded ENTRY-bar spread statistics (points)
struct GZ_SpreadStatsTotals
  {
   int      n;             // trades with a recorded spread lookup
   int      missing;       // trades whose entry bar was not found in the M1 data
   double   avg;
   double   median;
   double   p95;
   double   zero_share;    // share of entry bars with spread 0 (0 may mean "not recorded")
   bool     implausible;   // zero share >= 50% or median == 0

   void Clear() { n = 0; missing = 0; avg = 0.0; median = 0.0; p95 = 0.0; zero_share = 0.0; implausible = false; }
  };

class CGZCostEngine
  {
private:
   GZ_CostConfig     m_cfg;
   CGZTimeEngine     m_time;        // used ONLY to classify trades for the metrics engine's by-* breakdowns
   CGZSessionEngine  m_session;
   GZ_SessionProfile m_profile;

   //--- index of the last M1 bar with time <= t (-1 if none)
   int               FindBarAtOrBefore(const MqlRates &a[], datetime t) const
     {
      int lo = 0, hi = ArraySize(a)-1, res = -1;
      while(lo<=hi)
        {
         int mid = (lo+hi)/2;
         if(a[mid].time <= t) { res = mid; lo = mid+1; }
         else hi = mid-1;
        }
      return res;
     }

   void              AggSimple(const double &net[], double &sum, double &expectancy, double &pf, bool &pf_undefined) const
     {
      int n = ArraySize(net);
      double sw = 0.0, sl = 0.0;
      sum = 0.0;
      for(int i=0;i<n;i++)
        {
         sum += net[i];
         if(net[i] > 0.0) sw += net[i];
         else if(net[i] < 0.0) sl += -net[i];
        }
      expectancy = (n>0) ? sum/(double)n : 0.0;
      if(sl > 0.0) { pf = sw/sl; pf_undefined = false; }
      else         { pf = 0.0;   pf_undefined = (sw > 0.0); }
     }

public:
                     CGZCostEngine()
     {
      m_cfg.Default();
      GZ_TimeConfig tc; tc.Default();
      m_time.Configure(tc);
      m_profile.Set("PROFILE_01", "Session", GZ_TIME_BROKER, 16, 30, 20, 30, true, true);
     }

   //--- cost configuration + the time/session context the existing metrics engine needs for its breakdowns
   void              Configure(const GZ_CostConfig &cfg, const GZ_TimeConfig &time_cfg, const GZ_SessionProfile &session_profile)
     {
      m_cfg = cfg;
      m_time.Configure(time_cfg);
      m_profile = session_profile;
     }

   GZ_CostConfig     Config() const { return m_cfg; }

   //--- commission part of the cost, in price units per ounce
   //--- Phase FCIS: delegates to the shared free function (GZ_CostTypes.mqh)
   //--- so the Entry Engine's Minimum Risk Gate (Step 4) uses the identical
   //--- formula without duplicating it.
   double            CommissionPrice(double open_price) const
     { return GZCost_CommissionPrice(open_price, m_cfg); }

   //--- total cost of one trade in price units per ounce. 0.0 when the costs are not deliberately configured.
   double            CostPrice(double open_price, double spread_pts, double slippage_pts) const
     { return GZCost_ComputeCostPrice(open_price, spread_pts, slippage_pts, m_cfg); }

   //--- spread of the ENTRY M1 bar (exact bar time preferred; else the last bar at/before it within one M5 window).
   //--- found=false when no such bar exists.
   double            EntrySpreadPts(const MqlRates &m1[], datetime entry_time, bool &found) const
     {
      found = false;
      int idx = FindBarAtOrBefore(m1, entry_time);
      if(idx < 0) return 0.0;
      if((long)(entry_time - m1[idx].time) >= GZ_SPACING_M5_SECONDS) return 0.0;
      found = true;
      return (double)m1[idx].spread;
     }

   //--- net R of every trade in `d` (same order) at the given slippage. spread_used[] = points charged.
   void              NetSeries(CGZRunDetail *d, const MqlRates &m1[], double slippage_pts,
                               double &net_r[], double &cost_r[], double &spread_used[], int &missing) const
     {
      int n = d.count;
      ArrayResize(net_r, n); ArrayResize(cost_r, n); ArrayResize(spread_used, n);
      missing = 0;
      for(int i=0;i<n;i++)
        {
         double spread = 0.0;
         if(m_cfg.configured)
           {
            if(m_cfg.spread_mode == GZ_COST_SPREAD_FIXED)
               spread = m_cfg.fixed_spread_pts;
            else
              {
               bool found;
               spread = EntrySpreadPts(m1, d.entry_time[i], found);
               if(!found) missing++;
              }
           }
         double cost_price = CostPrice(d.entry_price[i], spread, slippage_pts);
         double risk = d.initial_risk[i];
         double c_r = (risk > 0.0) ? cost_price/risk : 0.0;
         cost_r[i] = c_r;
         net_r[i] = d.realized_r[i] - c_r;
         spread_used[i] = spread;
        }
     }

   //--- net metrics through the EXISTING Phase 8 metrics engine (temporary journal carrying the NET R as final_r)
   void              NetMetrics(CGZRunDetail *d, const double &net_r[], GZ_MetricsSummary &ms)
     {
      CGZJournalEngine je;
      je.Init();
      int n = d.count;
      for(int i=0;i<n;i++)
        {
         GZ_Trade tr; tr.Clear();
         tr.id = d.trade_id[i]; tr.setup_id = d.trade_id[i];
         tr.entry_time = d.entry_time[i]; tr.entry_price = d.entry_price[i];
         tr.direction = (ENUM_GZ_LEG_DIR)d.direction[i];
         je.OnTradeEntered(tr, d.initial_risk[i]);
         je.OnTradeClosed(d.trade_id[i], d.exit_time[i], 0.0, net_r[i]);
        }
      CGZMetricsEngine me;
      me.Compute(je, m_time, m_session, m_profile, ms);
     }

   //--- Full net evaluation of one run's closed-trade population.
   void              Evaluate(CGZRunDetail *d, const MqlRates &m1[], GZ_NetSummary &out)
     {
      out.Clear();
      out.net_equals_gross = m_cfg.NetEqualsGross();
      int n = d.count;
      if(n <= 0) return;
      out.available = true;
      out.trades = n;

      double net[], cost[], spr[];
      int missing = 0;
      NetSeries(d, m1, m_cfg.slippage_pts, net, cost, spr, missing);
      out.spread_missing = missing;

      double sum_cost = 0.0, sum_spread = 0.0;
      for(int i=0;i<n;i++)
        {
         out.gross_net_r += d.realized_r[i];
         sum_cost += cost[i];
         if(cost[i] > out.max_cost_r) out.max_cost_r = cost[i];
         if(cost[i] >= 0.25) out.cost_ge_quarter_r++;
         sum_spread += spr[i];
         if(spr[i] <= 0.0) out.spread_zero++;
         if((long)d.exit_time[i] / GZ_SECONDS_PER_DAY > (long)d.entry_time[i] / GZ_SECONDS_PER_DAY) out.rollover_crossings++;
        }
      out.gross_expectancy = out.gross_net_r/(double)n;
      out.avg_cost_r = sum_cost/(double)n;
      out.avg_spread_pts = sum_spread/(double)n;

      GZ_MetricsSummary ms;
      NetMetrics(d, net, ms);
      out.net_r           = ms.trade.net_r;
      out.expectancy      = ms.trade.expectancy;
      out.profit_factor   = ms.trade.profit_factor;
      out.pf_undefined    = ms.trade.profit_factor_undefined;
      out.win_rate        = ms.trade.win_rate;
      out.max_dd_r        = ms.risk.max_drawdown_r;
      out.max_lose_streak = ms.risk.max_losing_streak;

      //--- slippage sensitivity (every other cost component as configured)
      for(int k=0;k<GZ_COST_SENS_COUNT;k++)
        {
         double net2[], cost2[], spr2[];
         int miss2 = 0;
         NetSeries(d, m1, GZ_COST_SENS_POINTS[k], net2, cost2, spr2, miss2);
         double s_sum = 0.0, s_exp = 0.0, s_pf = 0.0;
         bool   s_pfu = false;
         AggSimple(net2, s_sum, s_exp, s_pf, s_pfu);
         out.sens[k].slippage_pts  = GZ_COST_SENS_POINTS[k];
         out.sens[k].net_r         = s_sum;
         out.sens[k].expectancy    = s_exp;
         out.sens[k].profit_factor = s_pf;
         out.sens[k].pf_undefined  = s_pfu;
        }
     }

   //--- Recorded ENTRY-bar spread statistics per calendar year and overall (points), independent of the configured
   //--- spread mode. A 0 can mean "not recorded". Returns the text table; totals in `tot`.
   string            BuildSpreadStats(CGZRunDetail *d, const MqlRates &m1[], GZ_SpreadStatsTotals &tot) const
     {
      tot.Clear();
      int n = d.count;
      double all[];
      int    yrs[];
      ArrayResize(all, 0); ArrayResize(yrs, 0);
      int ymin = 9999, ymax = 0;
      for(int i=0;i<n;i++)
        {
         bool found;
         double sp = EntrySpreadPts(m1, d.entry_time[i], found);
         if(!found) { tot.missing++; continue; }
         int k = ArraySize(all);
         ArrayResize(all, k+1); ArrayResize(yrs, k+1);
         all[k] = sp;
         MqlDateTime dt;
         TimeToStruct(d.entry_time[i], dt);
         yrs[k] = dt.year;
         if(dt.year < ymin) ymin = dt.year;
         if(dt.year > ymax) ymax = dt.year;
        }

      string s = "";
      s += GZCostPadR("YEAR",7) + GZCostPadL("trades",8) + GZCostPadL("avg",9) + GZCostPadL("median",9) + GZCostPadL("p95",9) + GZCostPadL("zero%",8) + "\n";
      int total = ArraySize(all);
      for(int y=ymin; y<=ymax && total>0; y++)
        {
         double ys[];
         ArrayResize(ys, 0);
         double sum = 0.0;
         int zeros = 0;
         for(int i=0;i<total;i++)
            if(yrs[i]==y)
              {
               int k = ArraySize(ys);
               ArrayResize(ys, k+1);
               ys[k] = all[i];
               sum += all[i];
               if(all[i] <= 0.0) zeros++;
              }
         int c = ArraySize(ys);
         if(c==0) continue;
         s += GZCostPadR(IntegerToString(y),7) + GZCostPadL(IntegerToString(c),8) + GZCostPadL(DoubleToString(sum/(double)c,1),9)
              + GZCostPadL(DoubleToString(GZCostMedian(ys),1),9) + GZCostPadL(DoubleToString(GZCostPercentile(ys,95.0),1),9)
              + GZCostPadL(DoubleToString(100.0*(double)zeros/(double)c,1),8) + "\n";
        }

      tot.n = total;
      if(total > 0)
        {
         double sum_all = 0.0;
         int zeros_all = 0;
         for(int i=0;i<total;i++) { sum_all += all[i]; if(all[i] <= 0.0) zeros_all++; }
         tot.avg = sum_all/(double)total;
         tot.median = GZCostMedian(all);
         tot.p95 = GZCostPercentile(all, 95.0);
         tot.zero_share = (double)zeros_all/(double)total;
         tot.implausible = (tot.zero_share >= 0.5 || tot.median <= 0.0);
        }
      s += GZCostPadR("ALL",7) + GZCostPadL(IntegerToString(total),8) + GZCostPadL(DoubleToString(tot.avg,1),9)
           + GZCostPadL(DoubleToString(tot.median,1),9) + GZCostPadL(DoubleToString(tot.p95,1),9)
           + GZCostPadL(DoubleToString(100.0*tot.zero_share,1),8) + "\n";
      if(tot.missing > 0) s += StringFormat("(%d trades had no M1 entry bar in the data and are excluded from the table)\n", tot.missing);
      return s;
     }
  };

#endif // __GZ_COST_ENGINE_MQH__
