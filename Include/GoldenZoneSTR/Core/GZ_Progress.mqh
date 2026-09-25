//+------------------------------------------------------------------+
//| GZ_Progress.mqh                                                   |
//| GoldenZone STR - Phase 15.8 - run progress / ETA text helpers     |
//|                                                                    |
//| DIAGNOSTIC TEXT ONLY. Pure functions of their arguments (no clock |
//| is read here): the caller passes elapsed milliseconds. Nothing in  |
//| this file can influence a research result.                         |
//+------------------------------------------------------------------+
#ifndef __GZ_PROGRESS_MQH__
#define __GZ_PROGRESS_MQH__

//--- "1h 02m 03s" / "4m 05s" / "12s"
string GZFormatDurationMs(ulong ms)
  {
   ulong total_s = ms / 1000;
   ulong h = total_s / 3600;
   ulong m = (total_s % 3600) / 60;
   ulong s = total_s % 60;
   if(h > 0) return StringFormat("%dh %02dm %02ds", (int)h, (int)m, (int)s);
   if(m > 0) return StringFormat("%dm %02ds", (int)m, (int)s);
   return StringFormat("%ds", (int)s);
  }

//--- percent of `total` runs already COMPLETED (0..100)
double GZProgressPercent(int completed, int total)
  {
   if(total <= 0) return 0.0;
   double p = 100.0 * (double)completed / (double)total;
   if(p < 0.0) p = 0.0;
   if(p > 100.0) p = 100.0;
   return p;
  }

//--- remaining time estimated from the COMPLETED runs only (mean duration x runs left); 0 when nothing completed yet
ulong GZEstimateRemainingMs(int completed, int total, ulong elapsed_ms)
  {
   if(completed <= 0 || total <= completed) return 0;
   double per_run = (double)elapsed_ms / (double)completed;
   return (ulong)(per_run * (double)(total - completed) + 0.5);
  }

//--- One progress line printed BEFORE run `run_no` (1-based) of `total`. completed = run_no - 1.
string GZProgressLine(int run_no, int total, ulong elapsed_ms, string what)
  {
   int completed = run_no - 1;
   string eta = (completed > 0) ? GZFormatDurationMs(GZEstimateRemainingMs(completed, total, elapsed_ms)) : "n/a (no run completed yet)";
   return StringFormat("[GZ][PROGRESS] run %d/%d | %.1f%% completed | elapsed %s | estimated remaining %s | %s",
                       run_no, total, GZProgressPercent(completed, total), GZFormatDurationMs(elapsed_ms), eta, what);
  }

#endif // __GZ_PROGRESS_MQH__
