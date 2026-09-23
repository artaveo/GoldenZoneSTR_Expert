//+------------------------------------------------------------------+
//| GZ_MonteCarloTypes.mqh                                            |
//| GoldenZone STR - Phase 14 - Monte Carlo Research - Types           |
//|                                                                    |
//| Shared structs/enums for the Monte Carlo Engine. Types only (see   |
//| GZ_MonteCarloEngine.mqh for the logic).                            |
//|                                                                    |
//| Roadmap Phase 14: trade-order randomization, return-sequence       |
//| randomization, drawdown distribution, losing-streak distribution,  |
//| equity-path variation. Recorded: number of simulations, seed,      |
//| median, percentiles, worst simulated cases. The original           |
//| historical ledger must not change.                                 |
//|                                                                    |
//| DESIGN NOTES (documented per spec Section 26 - the Roadmap        |
//| describes Phase 14 at a feature level, same situation as every    |
//| phase since Phase 3):                                              |
//|                                                                    |
//| 1) INPUT IS THE REALIZED-R SERIES, NOT THE LEDGER. The engine      |
//|    receives a plain double[] of closed-trade realized R in         |
//|    chronological order (BuildRSeries() extracts it from Phase 7's  |
//|    journal without modifying it - Phase 8's own convention: closed |
//|    trades only, journal order). It works on private copies, so the |
//|    original ledger/series cannot be altered (T151). Everything is  |
//|    R-based, like Phase 8 (no position-sizing/currency model).      |
//|                                                                    |
//| 2) THE TWO RANDOMIZATION MODES (Roadmap names both):               |
//|    TRADE_ORDER      - a random PERMUTATION (Fisher-Yates) of the   |
//|                       same trades. The multiset of R values, and   |
//|                       so the net R, is unchanged; only the path    |
//|                       (drawdown, streaks, equity curve) varies. It |
//|                       answers "how lucky/unlucky was the ORDER?".  |
//|    RETURN_SEQUENCE  - a BOOTSTRAP: n draws WITH replacement from   |
//|                       the trades' R values. Net R varies too. It   |
//|                       answers "what else could this edge have      |
//|                       produced?". Both assume trades are           |
//|                       exchangeable (no serial dependence) - a      |
//|                       documented limitation of any such shuffle.   |
//|                                                                    |
//| 3) OWN PRNG, NOT MathRand(). MathRand/MathSrand share global state |
//|    with the rest of the terminal and are not guaranteed identical  |
//|    across builds. This engine uses the Park-Miller MINSTD          |
//|    generator (state = state*48271 mod 2^31-1) - all intermediates  |
//|    fit in 64-bit integers, no overflow behavior is relied on - so  |
//|    the same seed gives the same numbers on every machine (T143     |
//|    pins exact values). Not cryptographic; irrelevant here.         |
//|    Each simulation k starts from its OWN state derived from        |
//|    (seed, k), so simulation k is the same whether 100 or 10000     |
//|    simulations are requested (prefix-stable, T150).                |
//|                                                                    |
//| 4) STATISTICS MIRROR PHASE 8: max drawdown = deepest peak-to-      |
//|    trough decline of cumulative R (peak starts at 0); a losing     |
//|    streak = consecutive final_r<0, a breakeven (==0) ends it.      |
//|    Percentiles use linear interpolation between order statistics   |
//|    (position p*(n-1)).                                              |
//|                                                                    |
//| 5) EQUITY-PATH VARIATION uses fixed CHECKPOINTS (at most           |
//|    GZ_MC_MAX_CHECKPOINTS, evenly spaced by trade count, the last   |
//|    always the final trade) instead of every trade, so the result   |
//|    stays a bounded fixed-size struct (GZ_ExperimentTypes.mqh design|
//|    note 5's reasoning). At each checkpoint: 5th/50th/95th          |
//|    percentile of simulated equity plus the historical equity.      |
//|                                                                    |
//| 6) RANKS. hist_dd_rank / hist_streak_rank = share of simulations   |
//|    whose value is <= the HISTORICAL value. Near 1.0 means the      |
//|    actual order was unusually BAD (worse than almost every         |
//|    reshuffle); near 0.0 means unusually GOOD (the historical       |
//|    drawdown understates what the same trades can do).              |
//|                                                                    |
//| 7) Simulation count is capped (GZ_DEFAULT_MC_MAX_SIMULATIONS) and  |
//|    an over-cap request is REJECTED outright, never truncated -     |
//|    same rule as every other phase's batch cap. ID format           |
//|    "MC_%06d", per-instance counter (design note 3 of Phase 9).     |
//+------------------------------------------------------------------+
#ifndef __GZ_MONTECARLO_TYPES_MQH__
#define __GZ_MONTECARLO_TYPES_MQH__

#include "..\Core\GZ_Types.mqh"
#include "..\Core\GZ_Constants.mqh"

#define GZ_MC_MAX_CHECKPOINTS  20
#define GZ_MC_MAX_NOTES        8

enum ENUM_GZ_MC_MODE
  {
   GZ_MC_TRADE_ORDER = 0,
   GZ_MC_RETURN_SEQUENCE
  };

string GZMcModeToString(ENUM_GZ_MC_MODE m)
  {
   switch(m)
     {
      case GZ_MC_TRADE_ORDER:      return "TRADE_ORDER";
      case GZ_MC_RETURN_SEQUENCE:  return "RETURN_SEQUENCE";
      default:                     return "UNKNOWN";
     }
  }

enum ENUM_GZ_MC_STATUS
  {
   GZ_MC_OK = 0,
   GZ_MC_REJECTED_INVALID_SIMS,      // simulations <= 0
   GZ_MC_REJECTED_TOO_MANY_SIMS,     // simulations > max cap (design note 7)
   GZ_MC_INSUFFICIENT_TRADES         // fewer than GZ_MC_MIN_TRADES trades
  };

string GZMcStatusToString(ENUM_GZ_MC_STATUS s)
  {
   switch(s)
     {
      case GZ_MC_OK:                    return "OK";
      case GZ_MC_REJECTED_INVALID_SIMS: return "REJECTED_INVALID_SIMS";
      case GZ_MC_REJECTED_TOO_MANY_SIMS:return "REJECTED_TOO_MANY_SIMS";
      case GZ_MC_INSUFFICIENT_TRADES:   return "INSUFFICIENT_TRADES";
      default:                          return "UNKNOWN";
     }
  }

//--- Summary of one metric across all simulations.
struct GZ_McDistribution
  {
   int      count;
   double   mean;
   double   minimum;
   double   p05;
   double   p25;
   double   median;
   double   p75;
   double   p95;
   double   maximum;
   int      min_sim_index;   // 0-based index of the (first) simulation that produced `minimum`
   int      max_sim_index;   // ... and `maximum`

   void Clear()
     {
      count = 0; mean = 0.0; minimum = 0.0; p05 = 0.0; p25 = 0.0; median = 0.0; p75 = 0.0; p95 = 0.0; maximum = 0.0;
      min_sim_index = -1; max_sim_index = -1;
     }
  };

//--- One full Monte Carlo run (one mode).
struct GZ_McResult
  {
   string             id;                  // "MC_000001"
   ENUM_GZ_MC_MODE    mode;
   ENUM_GZ_MC_STATUS  status;
   uint               seed;
   int                simulations_requested;
   int                simulations_run;     // == requested when status==OK, else 0
   int                trade_count;         // size of the R series that was shuffled/resampled

   //--- Historical (original order) reference values, same formulas
   double             hist_net_r;
   double             hist_max_dd;
   int                hist_max_losing_streak;

   //--- Distributions across simulations (design note 4)
   GZ_McDistribution  net_r;
   GZ_McDistribution  max_dd;
   GZ_McDistribution  max_losing_streak;

   double             frac_net_r_negative; // share of simulations ending below 0 R
   double             hist_dd_rank;        // design note 6
   double             hist_streak_rank;

   //--- Equity-path variation (design note 5)
   int                checkpoint_count;
   int                checkpoint_trades[GZ_MC_MAX_CHECKPOINTS]; // trades elapsed at each checkpoint
   double             hist_equity[GZ_MC_MAX_CHECKPOINTS];
   double             eq_p05[GZ_MC_MAX_CHECKPOINTS];
   double             eq_p50[GZ_MC_MAX_CHECKPOINTS];
   double             eq_p95[GZ_MC_MAX_CHECKPOINTS];

   string             notes[GZ_MC_MAX_NOTES];
   int                note_count;

   void Clear()
     {
      id = ""; mode = GZ_MC_TRADE_ORDER; status = GZ_MC_OK; seed = 0;
      simulations_requested = 0; simulations_run = 0; trade_count = 0;
      hist_net_r = 0.0; hist_max_dd = 0.0; hist_max_losing_streak = 0;
      net_r.Clear(); max_dd.Clear(); max_losing_streak.Clear();
      frac_net_r_negative = 0.0; hist_dd_rank = 0.0; hist_streak_rank = 0.0;
      checkpoint_count = 0;
      for(int i=0;i<GZ_MC_MAX_CHECKPOINTS;i++)
        {
         checkpoint_trades[i] = 0; hist_equity[i] = 0.0; eq_p05[i] = 0.0; eq_p50[i] = 0.0; eq_p95[i] = 0.0;
        }
      for(int i=0;i<GZ_MC_MAX_NOTES;i++) notes[i] = "";
      note_count = 0;
     }

   void AddNote(string n)
     {
      if(note_count<GZ_MC_MAX_NOTES)
        {
         notes[note_count] = n;
         note_count++;
        }
     }
  };

#endif // __GZ_MONTECARLO_TYPES_MQH__
