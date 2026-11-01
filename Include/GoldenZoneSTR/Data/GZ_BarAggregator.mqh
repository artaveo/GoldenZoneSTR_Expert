//+------------------------------------------------------------------+
//| GZ_BarAggregator.mqh                                              |
//| GoldenZone STR - Execution Timeframe (M1 / M5 / M15)              |
//|                                                                    |
//| The trade simulator (entry / exit / journal / cost lookups) replays|
//| an "execution" bar series against the M5 STRUCTURE series. Until    |
//| now that execution series was always M1. This file builds an M5 or |
//| M15 execution series by aggregating the SAME already-loaded,        |
//| already-validated, already-range-sliced M1 bars - no extra data    |
//| load, no second validator, and the structure side (swings / legs / |
//| breaks / fib) is untouched.                                         |
//|                                                                    |
//| Rules (deterministic, no lookahead added):                         |
//|  1) Bucket = floor(broker_time / period_seconds) - the same alignment|
//|     MT5's own M5/M15 bars use.                                      |
//|  2) time = bucket START; open = first M1 open in the bucket; high /  |
//|     low = extremes; close = last M1 close; tick/real volume = sums.  |
//|  3) spread = the MAXIMUM M1 spread inside the bucket (conservative:  |
//|     a coarser bar cannot know which minute the fill happens in, so   |
//|     it never assumes the cheapest one).                              |
//|  4) Missing minutes are simply absent - never fabricated. A bucket   |
//|     with no M1 data produces no bar.                                 |
//|  5) The simulator only ever lets an execution bar see structure as   |
//|     of BEFORE that bar's open (it is driven by bar timestamps), so a |
//|     coarser bar just sees structure a little later - never earlier.  |
//+------------------------------------------------------------------+
#ifndef __GZ_BAR_AGGREGATOR_MQH__
#define __GZ_BAR_AGGREGATOR_MQH__

enum ENUM_GZ_EXEC_TF
  {
   GZ_EXEC_M1  = 1,    // baseline: execution replays M1 bars (unchanged behavior)
   GZ_EXEC_M5  = 5,    // execution replays M5 bars aggregated from M1
   GZ_EXEC_M15 = 15    // execution replays M15 bars aggregated from M1
  };

string GZExecTfLabel(int minutes)
  {
   return StringFormat("M%d", minutes);
  }

//--- Aggregate ascending `src` (M1) into `dst` (period_min-minute bars).
//--- `dst` MUST be a different array from `src`. period_min<=1 returns a
//--- plain copy (so the default M1 setting is byte-identical to before).
//--- Returns the number of bars written to `dst`.
int GZAggregateBars(const MqlRates &src[], int period_min, MqlRates &dst[])
  {
   int n = ArraySize(src);
   if(period_min<=1 || n==0)
     {
      ArrayResize(dst, n);
      for(int i=0;i<n;i++)
         dst[i] = src[i];
      return n;
     }

   long psec = (long)period_min*60;
   ArrayResize(dst, 0, 65536);
   int  cnt = 0;
   long cur = -1;
   for(int i=0;i<n;i++)
     {
      long b = (long)src[i].time / psec;
      if(b!=cur)
        {
         cnt++;
         ArrayResize(dst, cnt, 65536);
         dst[cnt-1]      = src[i];
         dst[cnt-1].time = (datetime)(b*psec);
         cur = b;
        }
      else
        {
         int k = cnt-1;
         if(src[i].high > dst[k].high) dst[k].high = src[i].high;
         if(src[i].low  < dst[k].low)  dst[k].low  = src[i].low;
         dst[k].close        = src[i].close;
         dst[k].tick_volume += src[i].tick_volume;
         dst[k].real_volume += src[i].real_volume;
         if(src[i].spread > dst[k].spread) dst[k].spread = src[i].spread;
        }
     }
   return cnt;
  }

#endif // __GZ_BAR_AGGREGATOR_MQH__
