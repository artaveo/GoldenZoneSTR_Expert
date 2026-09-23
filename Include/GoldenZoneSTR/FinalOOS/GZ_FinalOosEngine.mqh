//+------------------------------------------------------------------+
//| GZ_FinalOosEngine.mqh                                             |
//| GoldenZone STR - Phase 15 - Final OOS                              |
//|                                                                    |
//| Runs ONE frozen configuration through Phase 9's runner on the      |
//| Development data and on the separately loaded Final OOS data, and  |
//| compares them. No selection, no tuning, no strategy logic - see    |
//| GZ_FinalOosTypes.mqh design notes 1-6.                             |
//+------------------------------------------------------------------+
#ifndef __GZ_FINALOOS_ENGINE_MQH__
#define __GZ_FINALOOS_ENGINE_MQH__

#include "GZ_FinalOosTypes.mqh"
#include "..\Experiment\GZ_ExperimentRunner.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZFinalOosEngine
  {
private:
   CGZLogger  *m_logger;
   long        m_next_seq;

   string NextId()
     {
      string id = StringFormat("OOS_%06d", (int)m_next_seq);
      m_next_seq++;
      return id;
     }

public:
                     CGZFinalOosEngine(CGZLogger *logger=NULL)
     {
      m_logger   = logger;
      m_next_seq = 1;
     }

   long              NextSequence() const { return m_next_seq; }

   //--- Range rule (design note 1): OOS must end after it starts, and must
   //--- start at or after the Development range end. Pure.
   ENUM_GZ_OOS_STATUS CheckSeparation(datetime dev_end, datetime oos_start, datetime oos_end) const
     {
      if(oos_end<=oos_start)
         return GZ_OOS_REJECTED_BAD_RANGE;
      if(oos_start<dev_end)
         return GZ_OOS_REJECTED_OVERLAP;
      return GZ_OOS_OK;
     }

   //--- Keep only bars with time >= from_time AND time > after_time
   //--- (design note 3). Order preserved. Returns the kept count.
   int               TrimBoundary(const MqlRates &src[], datetime after_time, datetime from_time, MqlRates &dst[]) const
     {
      int n = ArraySize(src);
      ArrayResize(dst, 0);
      int c = 0;
      for(int i=0; i<n; i++)
        {
         if(src[i].time>=from_time && src[i].time>after_time)
           {
            ArrayResize(dst, c+1);
            dst[c] = src[i];
            c++;
           }
        }
      return c;
     }

   //--- Compare(): fills the comparison fields of r from r.dev / r.oos
   //--- (design note 4). Pure - callable on hand-built summaries.
   void              Compare(GZ_FinalOosResult &r, int min_oos_trades) const
     {
      r.ClearComparison();
      int    n_oos = r.oos.trade.trade_count;
      double e_dev = r.dev.trade.expectancy;
      double e_oos = r.oos.trade.expectancy;

      r.expectancy_delta = e_oos - e_dev;
      r.win_rate_delta   = r.oos.trade.win_rate - r.dev.trade.win_rate;
      if(!r.dev.trade.profit_factor_undefined && !r.oos.trade.profit_factor_undefined &&
         r.dev.trade.trade_count>0 && n_oos>0)
        {
         r.profit_factor_delta_defined = true;
         r.profit_factor_delta = r.oos.trade.profit_factor - r.dev.trade.profit_factor;
        }
      r.max_dd_delta  = r.oos.risk.max_drawdown_r - r.dev.risk.max_drawdown_r;
      r.avg_mae_delta = r.oos.behavior.avg_mae_r  - r.dev.behavior.avg_mae_r;
      r.avg_mfe_delta = r.oos.behavior.avg_mfe_r  - r.dev.behavior.avg_mfe_r;

      if(e_dev>GZ_OOS_NOISE_FLOOR_R)
        {
         r.retention_defined    = true;
         r.expectancy_retention = e_oos/e_dev;
        }

      r.oos_no_trades   = (n_oos==0);
      r.low_oos_trades  = (n_oos<min_oos_trades);
      r.oos_negative    = (n_oos>0 && e_oos<=0.0);
      r.oos_degraded    = (r.retention_defined && n_oos>0 && r.expectancy_retention<GZ_OOS_RETENTION_MIN);

      if(r.oos_no_trades)
         r.AddNote("OOS_NO_TRADES: the frozen configuration produced no closed trade on the OOS data.");
      else if(r.low_oos_trades)
         r.AddNote(StringFormat("LOW_OOS_TRADES: %d OOS trades < %d - weak statistical evidence either way.", n_oos, min_oos_trades));
      if(r.oos_negative)
         r.AddNote("OOS_NEGATIVE: OOS expectancy is not positive.");
      if(r.oos_degraded)
         r.AddNote(StringFormat("OOS_DEGRADED: OOS kept only %.0f%% of the Development expectancy (< %.0f%%).",
                    r.expectancy_retention*100.0, GZ_OOS_RETENTION_MIN*100.0));
      if(!r.retention_defined)
         r.AddNote("RETENTION_UNDEFINED: Development expectancy is at/below the noise floor - no meaningful ratio.");
     }

   //+---------------------------------------------------------------+
   //| Evaluate() - frozen cfg, ONE run per range, comparison.          |
   //| requested ranges are what the user configured (checked against   |
   //| the separation rule); the arrays are what was actually loaded.   |
   //| Inputs are const - the Development series is never touched.      |
   //+---------------------------------------------------------------+
   ENUM_GZ_OOS_STATUS Evaluate(const GZ_ExperimentConfig &cfg,
                               datetime dev_req_start, datetime dev_req_end, datetime oos_req_start, datetime oos_req_end,
                               int min_oos_trades,
                               const MqlRates &dev_m1[], const MqlRates &dev_m5[],
                               const MqlRates &oos_m1[], const MqlRates &oos_m5[],
                               ENUM_GZ_VALIDATION_STATUS dev_m1_status, ENUM_GZ_VALIDATION_STATUS dev_m5_status,
                               ENUM_GZ_VALIDATION_STATUS oos_m1_status, ENUM_GZ_VALIDATION_STATUS oos_m5_status,
                               string dataset_prefix, GZ_FinalOosResult &out)
     {
      out.Clear();
      out.id               = NextId();
      out.strategy_version = GZ_STRATEGY_VERSION;
      out.config           = cfg;
      out.dev_req_start = dev_req_start; out.dev_req_end = dev_req_end;
      out.oos_req_start = oos_req_start; out.oos_req_end = oos_req_end;
      out.oos_m1_status = oos_m1_status; out.oos_m5_status = oos_m5_status;

      out.status = CheckSeparation(dev_req_end, oos_req_start, oos_req_end);
      if(out.status!=GZ_OOS_OK)
        {
         out.AddNote(StringFormat("%s: OOS range [%s .. %s] vs Development end %s - nothing was run.",
                     GZOosStatusToString(out.status), TimeToString(oos_req_start), TimeToString(oos_req_end), TimeToString(dev_req_end)));
         if(m_logger!=NULL)
            m_logger.Error("FinalOOS", StringFormat("%s: %s - REJECTED.", out.id, GZOosStatusToString(out.status)));
         return out.status;
        }

      int n5d = ArraySize(dev_m5);
      if(n5d==0)
        {
         out.status = GZ_OOS_NO_DEV_DATA;
         out.AddNote("NO_DEV_DATA: no Development M5 bars supplied - nothing to compare against.");
         return out.status;
        }
      out.dev_first   = dev_m5[0].time;
      out.dev_last    = dev_m5[n5d-1].time;
      out.dev_m5_bars = n5d;

      //--- design note 3: no bar may belong to both ranges
      datetime after5 = out.dev_last;
      datetime after1 = out.dev_last;
      int n1d = ArraySize(dev_m1);
      if(n1d>0 && dev_m1[n1d-1].time>after1)
         after1 = dev_m1[n1d-1].time;

      MqlRates o5[], o1[];
      int kept5 = TrimBoundary(oos_m5, after5, oos_req_start, o5);
      int kept1 = TrimBoundary(oos_m1, after1, oos_req_start, o1);
      //--- boundary bars = bars inside the requested OOS range that were dropped only because
      //--- they are not after the Development range's last bar
      int in_range = 0;
      for(int i=0; i<ArraySize(oos_m5); i++) if(oos_m5[i].time>=oos_req_start) in_range++;
      for(int i=0; i<ArraySize(oos_m1); i++) if(oos_m1[i].time>=oos_req_start) in_range++;
      out.oos_boundary_bars_dropped = in_range - kept5 - kept1;
      if(out.oos_boundary_bars_dropped>0)
         out.AddNote(StringFormat("BOUNDARY_BARS_DROPPED: %d OOS bar(s) (M5+M1) were not after the Development range's last bar and were removed.", out.oos_boundary_bars_dropped));
      if(kept5==0)
        {
         out.status = GZ_OOS_NO_OOS_DATA;
         out.AddNote("NO_OOS_DATA: no M5 bars in the OOS range after boundary trimming - is the history downloaded in the terminal?");
         if(m_logger!=NULL)
            m_logger.Warning("FinalOOS", StringFormat("%s: no OOS M5 data - skipped.", out.id));
         return out.status;
        }
      out.oos_first   = o5[0].time;
      out.oos_last    = o5[kept5-1].time;
      out.oos_m5_bars = kept5;

      //--- ONE frozen configuration, ONE run per range (design note 2)
      CGZExperimentRunner runner(m_logger);
      GZ_ExperimentConfig dcfg = cfg;
      dcfg.range_start = out.dev_first; dcfg.range_end = out.dev_last;
      GZ_ExperimentConfig ocfg = cfg;
      ocfg.range_start = out.oos_first; ocfg.range_end = out.oos_last;

      GZ_ExperimentResult rd, ro;
      runner.RunSingle(dcfg, dev_m1, dev_m5, dataset_prefix+"_DEV", dev_m1_status, dev_m5_status, rd);
      runner.RunSingle(ocfg, o1, o5, dataset_prefix+"_OOS", oos_m1_status, oos_m5_status, ro);
      out.dev = rd.metrics;
      out.oos = ro.metrics;

      Compare(out, min_oos_trades);
      out.status = GZ_OOS_OK;

      if(m_logger!=NULL)
         m_logger.Info("FinalOOS", StringFormat(
            "%s: DEV trades=%d exp=%.4f pf=%.3f | OOS trades=%d exp=%.4f pf=%.3f | retention=%s flags: low=%s negative=%s degraded=%s",
            out.id, out.dev.trade.trade_count, out.dev.trade.expectancy, out.dev.trade.profit_factor,
            out.oos.trade.trade_count, out.oos.trade.expectancy, out.oos.trade.profit_factor,
            out.retention_defined ? DoubleToString(out.expectancy_retention,3) : "undefined",
            out.low_oos_trades?"true":"false", out.oos_negative?"true":"false", out.oos_degraded?"true":"false"));
      return out.status;
     }
  };

#endif // __GZ_FINALOOS_ENGINE_MQH__
