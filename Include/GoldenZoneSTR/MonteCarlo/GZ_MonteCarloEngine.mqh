//+------------------------------------------------------------------+
//| GZ_MonteCarloEngine.mqh                                           |
//| GoldenZone STR - Phase 14 - Monte Carlo Research                   |
//|                                                                    |
//| Research Adapter concern (Roadmap Phase 17 vocabulary). Takes the  |
//| closed-trade realized-R series, and over N seeded simulations      |
//| either PERMUTES it (TRADE_ORDER) or BOOTSTRAPS it (RETURN_SEQUENCE)|
//| - see GZ_MonteCarloTypes.mqh design notes 1-7 - recording, per     |
//| simulation, the final net R, the max drawdown and the max losing   |
//| streak plus the equity at fixed checkpoints, then summarizing each |
//| as a distribution (mean/min/percentiles/max, worst case's          |
//| simulation index) next to the HISTORICAL value.                    |
//|                                                                    |
//| No strategy logic and no trade simulation: the only inputs are     |
//| numbers. Deterministic: own PRNG, no wall-clock, no MathRand.      |
//| The original series/ledger is never modified (const input, private |
//| working copies).                                                    |
//+------------------------------------------------------------------+
#ifndef __GZ_MONTECARLO_ENGINE_MQH__
#define __GZ_MONTECARLO_ENGINE_MQH__

#include "GZ_MonteCarloTypes.mqh"
#include "..\Journal\GZ_JournalTypes.mqh"
#include "..\Journal\GZ_JournalEngine.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZMonteCarloEngine
  {
private:
   CGZLogger        *m_logger;
   long              m_next_seq;
   int               m_max_sims;

   string NextId()
     {
      string id = StringFormat("MC_%06d", (int)m_next_seq);
      m_next_seq++;
      return id;
     }

public:
                     CGZMonteCarloEngine(CGZLogger *logger=NULL)
     {
      m_logger   = logger;
      m_next_seq = 1;
      m_max_sims = GZ_DEFAULT_MC_MAX_SIMULATIONS;
     }

   void              SetMaxSimulations(int max_sims) { m_max_sims = (max_sims>0) ? max_sims : GZ_DEFAULT_MC_MAX_SIMULATIONS; }
   int               MaxSimulations() const { return m_max_sims; }
   long              NextSequence()   const { return m_next_seq; }

   //+---------------------------------------------------------------+
   //| PRNG (design note 3, Types file): Park-Miller MINSTD.           |
   //+---------------------------------------------------------------+
   ulong             AdvanceState(ulong s) const
     {
      return (s * 48271) % 2147483647;
     }

   //--- Starting state for simulation `sim` (0-based) of `seed`; always
   //--- in [1, 2147483646] (0 would be a fixed point of the generator).
   //--- Depends ONLY on (seed, sim), never on the total simulation count.
   ulong             SeedForSim(uint seed, int sim) const
     {
      ulong mixed = (ulong)seed * 1000003 + (ulong)(sim+1) * 2654435761;
      return (mixed % 2147483646) + 1;
     }

   //--- Uniform integer in [0, m-1] from a state (m >= 1).
   int               IndexFromState(ulong s, int m) const
     {
      int j = (int)((double)s / 2147483647.0 * (double)m);
      if(j>=m) j = m-1;
      if(j<0)  j = 0;
      return j;
     }

   //+---------------------------------------------------------------+
   //| GenerateSequence() - PUBLIC so tests can inspect one simulated   |
   //| path. Fills out[0..n-1] for simulation `sim`:                    |
   //|  TRADE_ORDER      : Fisher-Yates permutation of orig            |
   //|  RETURN_SEQUENCE  : n draws with replacement from orig          |
   //| First 4 draws after seeding are discarded (decorrelates the     |
   //| streams of neighboring simulations).                             |
   //+---------------------------------------------------------------+
   void              GenerateSequence(ENUM_GZ_MC_MODE mode, const double &orig[], int n, uint seed, int sim, double &out[]) const
     {
      ArrayResize(out, n);
      if(n<=0)
         return;

      ulong st = SeedForSim(seed, sim);
      for(int d=0; d<4; d++)
         st = AdvanceState(st);

      if(mode==GZ_MC_TRADE_ORDER)
        {
         for(int i=0; i<n; i++)
            out[i] = orig[i];
         for(int i=n-1; i>=1; i--)
           {
            st = AdvanceState(st);
            int j = IndexFromState(st, i+1);
            double tmp = out[i];
            out[i] = out[j];
            out[j] = tmp;
           }
        }
      else
        {
         for(int i=0; i<n; i++)
           {
            st = AdvanceState(st);
            out[i] = orig[IndexFromState(st, n)];
           }
        }
     }

   //+---------------------------------------------------------------+
   //| ComputeStats() - net R, max drawdown (R) and max losing streak  |
   //| of one R sequence, same conventions as Phase 8 (design note 4).  |
   //+---------------------------------------------------------------+
   void              ComputeStats(const double &seq[], int n, double &net, double &max_dd, int &max_streak) const
     {
      net = 0.0; max_dd = 0.0; max_streak = 0;
      double equity = 0.0, peak = 0.0;
      int streak = 0;
      for(int i=0; i<n; i++)
        {
         equity += seq[i];
         if(equity>peak)
            peak = equity;
         else if(peak-equity>max_dd)
            max_dd = peak-equity;

         if(seq[i]<0.0)
           {
            streak++;
            if(streak>max_streak) max_streak = streak;
           }
         else
            streak = 0;   // a win OR a breakeven ends a losing streak
        }
      net = equity;
     }

   //--- Linear-interpolation percentile of an ASCENDING-sorted array.
   double            Percentile(const double &sorted[], int n, double p) const
     {
      if(n<=0) return 0.0;
      if(n==1) return sorted[0];
      double pos = p * (double)(n-1);
      int lo = (int)MathFloor(pos);
      if(lo>=n-1) return sorted[n-1];
      if(lo<0) return sorted[0];
      double frac = pos - (double)lo;
      return sorted[lo] + frac*(sorted[lo+1]-sorted[lo]);
     }

   //--- Summarize() - fills `out` from `values` (one entry per
   //--- simulation, in simulation order). NOTE: `values` is SORTED in
   //--- place afterwards (min/max simulation indices are taken first).
   void              Summarize(double &values[], GZ_McDistribution &out) const
     {
      out.Clear();
      int n = ArraySize(values);
      if(n<=0)
         return;
      double sum = 0.0;
      out.minimum = values[0]; out.maximum = values[0];
      out.min_sim_index = 0;   out.max_sim_index = 0;
      for(int i=0; i<n; i++)
        {
         sum += values[i];
         if(values[i]<out.minimum) { out.minimum = values[i]; out.min_sim_index = i; }
         if(values[i]>out.maximum) { out.maximum = values[i]; out.max_sim_index = i; }
        }
      out.count = n;
      out.mean  = sum/(double)n;
      ArraySort(values);
      out.p05    = Percentile(values, n, 0.05);
      out.p25    = Percentile(values, n, 0.25);
      out.median = Percentile(values, n, 0.50);
      out.p75    = Percentile(values, n, 0.75);
      out.p95    = Percentile(values, n, 0.95);
     }

   //--- Closed trades' realized R, in journal order, WITHOUT touching the
   //--- journal (Phase 8's population convention - design note 1).
   int               BuildRSeries(CGZJournalEngine &journal, double &out[]) const
     {
      ArrayResize(out, 0);
      int n = journal.JournalCount();
      int c = 0;
      for(int i=0; i<n; i++)
        {
         GZ_TradeJournal j = journal.GetJournal(i);
         if(j.is_open)
            continue;
         ArrayResize(out, c+1);
         out[c] = j.final_r;
         c++;
        }
      return c;
     }

   //+---------------------------------------------------------------+
   //| Run() - one mode, N simulations. Guards leave a well-formed      |
   //| result with status != OK and nothing simulated.                  |
   //+---------------------------------------------------------------+
   ENUM_GZ_MC_STATUS Run(ENUM_GZ_MC_MODE mode, const double &r_series[], int simulations, uint seed, GZ_McResult &out)
     {
      out.Clear();
      out.id                    = NextId();
      out.mode                  = mode;
      out.seed                  = seed;
      out.simulations_requested = simulations;

      int n = ArraySize(r_series);
      out.trade_count = n;

      if(simulations<=0)
        {
         out.status = GZ_MC_REJECTED_INVALID_SIMS;
         out.AddNote("REJECTED_INVALID_SIMS: simulations must be > 0.");
         return out.status;
        }
      if(simulations>m_max_sims)
        {
         out.status = GZ_MC_REJECTED_TOO_MANY_SIMS;
         out.AddNote(StringFormat("REJECTED_TOO_MANY_SIMS: %d simulations exceeds the cap %d (Roadmap: stage research) - nothing was run.", simulations, m_max_sims));
         if(m_logger!=NULL)
            m_logger.Error("MonteCarlo", StringFormat("%s: %d simulations exceeds cap %d - REJECTED.", out.id, simulations, m_max_sims));
         return out.status;
        }
      if(n<GZ_MC_MIN_TRADES)
        {
         out.status = GZ_MC_INSUFFICIENT_TRADES;
         out.AddNote(StringFormat("INSUFFICIENT_TRADES: %d trade(s) - at least %d are needed for a shuffle/bootstrap to mean anything.", n, GZ_MC_MIN_TRADES));
         if(m_logger!=NULL)
            m_logger.Warning("MonteCarlo", StringFormat("%s: only %d trade(s) - skipped.", out.id, n));
         return out.status;
        }

      //--- private working copy - the caller's series is never modified
      double orig[];
      ArrayResize(orig, n);
      for(int i=0; i<n; i++)
         orig[i] = r_series[i];

      //--- checkpoints (design note 5): evenly spaced by trade count, last == n
      int cp = (n<GZ_MC_MAX_CHECKPOINTS) ? n : GZ_MC_MAX_CHECKPOINTS;
      out.checkpoint_count = cp;
      for(int c=0; c<cp; c++)
        {
         int t = (int)MathRound((double)(c+1)*(double)n/(double)cp);
         if(t<1) t = 1;
         if(t>n) t = n;
         out.checkpoint_trades[c] = t;
        }
      out.checkpoint_trades[cp-1] = n;

      //--- historical reference (original order)
      ComputeStats(orig, n, out.hist_net_r, out.hist_max_dd, out.hist_max_losing_streak);
      {
       double eq = 0.0;
       int c = 0;
       for(int i=0; i<n && c<cp; i++)
         {
          eq += orig[i];
          if(i+1==out.checkpoint_trades[c])
            {
             out.hist_equity[c] = eq;
             c++;
            }
         }
      }

      //--- simulations
      double v_net[], v_dd[], v_streak[], cpv[], seq[];
      ArrayResize(v_net, simulations);
      ArrayResize(v_dd, simulations);
      ArrayResize(v_streak, simulations);
      ArrayResize(cpv, simulations*cp);

      int neg = 0, dd_le = 0, st_le = 0;
      for(int k=0; k<simulations; k++)
        {
         GenerateSequence(mode, orig, n, seed, k, seq);

         double net, dd; int streak;
         ComputeStats(seq, n, net, dd, streak);
         v_net[k]    = net;
         v_dd[k]     = dd;
         v_streak[k] = (double)streak;

         if(net<0.0)                                   neg++;
         if(dd<=out.hist_max_dd+0.0000001)             dd_le++;
         if(streak<=out.hist_max_losing_streak)        st_le++;

         double eq = 0.0;
         int c = 0;
         for(int i=0; i<n && c<cp; i++)
           {
            eq += seq[i];
            if(i+1==out.checkpoint_trades[c])
              {
               cpv[k*cp+c] = eq;
               c++;
              }
           }
        }

      Summarize(v_net, out.net_r);
      Summarize(v_dd, out.max_dd);
      Summarize(v_streak, out.max_losing_streak);
      out.frac_net_r_negative = (double)neg   / (double)simulations;
      out.hist_dd_rank        = (double)dd_le / (double)simulations;
      out.hist_streak_rank    = (double)st_le / (double)simulations;

      double col[];
      ArrayResize(col, simulations);
      for(int c=0; c<cp; c++)
        {
         for(int k=0; k<simulations; k++)
            col[k] = cpv[k*cp+c];
         ArraySort(col);
         out.eq_p05[c] = Percentile(col, simulations, 0.05);
         out.eq_p50[c] = Percentile(col, simulations, 0.50);
         out.eq_p95[c] = Percentile(col, simulations, 0.95);
        }

      out.simulations_run = simulations;
      out.status          = GZ_MC_OK;

      if(mode==GZ_MC_TRADE_ORDER)
         out.AddNote("TRADE_ORDER keeps every trade, so net R is identical in every simulation - only drawdown, streaks and the equity path vary.");
      else
         out.AddNote("RETURN_SEQUENCE resamples trades WITH replacement, so net R varies as well. Both modes assume trades are exchangeable (no serial dependence).");

      if(m_logger!=NULL)
         m_logger.Info("MonteCarlo", StringFormat(
            "%s [%s] seed=%u sims=%d trades=%d | hist: net_r=%.3f max_dd=%.3f max_streak=%d | sim max_dd: median=%.3f p95=%.3f worst=%.3f | sim streak: median=%.1f p95=%.1f worst=%.0f | dd_rank=%.3f P(net<0)=%.3f",
            out.id, GZMcModeToString(mode), seed, simulations, n, out.hist_net_r, out.hist_max_dd, out.hist_max_losing_streak,
            out.max_dd.median, out.max_dd.p95, out.max_dd.maximum,
            out.max_losing_streak.median, out.max_losing_streak.p95, out.max_losing_streak.maximum,
            out.hist_dd_rank, out.frac_net_r_negative));
      return out.status;
     }
  };

#endif // __GZ_MONTECARLO_ENGINE_MQH__
