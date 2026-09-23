//+------------------------------------------------------------------+
//| GZ_FilterEngine.mqh                                               |
//| GoldenZone STR - Phase 10 - Filter Engine                        |
//|                                                                    |
//| Deterministic, POST-HOC, per-setup filter evaluator - the same    |
//| construction model CGZEventLedger/CGZMetricsEngine already use    |
//| (see those files' headers): every result is fully determined by   |
//| a GZ_Setup's own already-final fields (leg.broken/break_time/      |
//| break_price/LegSize()) plus the read-only M5 rates array the      |
//| main pipeline already loaded - no bar-by-bar hook, no mutation of  |
//| anything Phase 1-9 produced.                                       |
//|                                                                    |
//| NO-LOOKAHEAD DISCIPLINE (kept even though this runs post-hoc, so   |
//| the exact same evaluation logic stays reusable, unchanged, by a    |
//| future live Execution Adapter - Roadmap Phase 17's Shared Strategy |
//| Core vision, the same reason CGZBreakEngine/CGZLegEngine already   |
//| document): every metric below is computed ONLY from M5 bars at or  |
//| BEFORE the setup's own break bar (FindBarIndex() below never       |
//| returns an index whose time is after the requested timestamp) -    |
//| no bar after the setup's own break/detection moment is ever read.  |
//+------------------------------------------------------------------+
#ifndef __GZ_FILTER_ENGINE_MQH__
#define __GZ_FILTER_ENGINE_MQH__

#include "GZ_FilterTypes.mqh"
#include "..\Setup\GZ_SetupTypes.mqh"
#include "..\Time\GZ_TimeEngine.mqh"
#include "..\Time\GZ_Session.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZFilterEngine
  {
private:
   CGZLogger        *m_logger;

   //--- Largest index idx such that r[idx].time <= t (last CLOSED bar at
   //--- or before t). Returns -1 if no such bar exists (t before the
   //--- first bar, or empty array). Never returns an index whose time is
   //--- AFTER t - see header no-lookahead note. -------------------------
   int FindBarIndex(const MqlRates &r[], datetime t) const
     {
      int n = ArraySize(r);
      if(n==0 || r[0].time>t)
         return -1;
      int lo=0, hi=n-1, best=-1;
      while(lo<=hi)
        {
         int mid=(lo+hi)/2;
         if(r[mid].time<=t) { best=mid; lo=mid+1; }
         else                 hi=mid-1;
        }
      return best;
     }

   //--- Simple-average True Range over the `period` bars ending at idx
   //--- (inclusive) - same SMA-of-TR methodology as CGZAtr (GZ_ATR.mqh),
   //--- recomputed on the already-loaded slice rather than requiring a
   //--- live streaming feed (this engine runs post-hoc - see header).
   //--- Requires idx>=period so every bar in the window has a previous
   //--- close available; sets ready=false and returns 0.0 otherwise. ----
   double AtrAt(const MqlRates &r[], int idx, int period, bool &ready) const
     {
      ready=false;
      if(period<1 || idx<period)
         return 0.0;
      double sum=0.0;
      for(int k=idx-period+1;k<=idx;k++)
        {
         double hl = r[k].high-r[k].low;
         double tr = hl;
         double hc = MathAbs(r[k].high-r[k-1].close);
         double lc = MathAbs(r[k].low -r[k-1].close);
         if(hc>tr) tr=hc;
         if(lc>tr) tr=lc;
         sum += tr;
        }
      ready=true;
      return sum/period;
     }

   //--- Trailing average tick_volume over `lookback` bars ending at idx
   //--- (inclusive). Requires idx>=lookback-1. ---------------------------
   double AvgVolumeAt(const MqlRates &r[], int idx, int lookback, bool &ready) const
     {
      ready=false;
      if(lookback<1 || idx<lookback-1)
         return 0.0;
      double sum=0.0;
      for(int k=idx-lookback+1;k<=idx;k++)
         sum += (double)r[k].tick_volume;
      ready=true;
      return sum/lookback;
     }

   //--- Evaluate one ATR-multiple "quality" filter (Break Quality / Leg
   //--- Quality / Volatility all reduce to "measured value, in ATR
   //--- multiples (or ratio), compared against a threshold"). -----------
   void EvalAtrThreshold(bool have_ref, double measured_distance, const MqlRates &r[], int idx,
                          int atr_period, double min_mult, GZ_FilterResult &out) const
     {
      out.result = GZ_FILTER_NOT_AVAILABLE;
      out.metric_value = 0.0;
      if(!have_ref || idx<0) return;
      bool ready;
      double atr = AtrAt(r, idx, atr_period, ready);
      if(!ready || atr<=0.0) return;
      out.metric_value = measured_distance/atr;
      out.result = (out.metric_value>=min_mult) ? GZ_FILTER_PASS : GZ_FILTER_FAIL;
     }

public:
                     CGZFilterEngine(CGZLogger *logger=NULL) { m_logger=logger; }

   //--- Evaluate every filter for one setup against the supplied M5      |
   //--- rates (the SAME already-loaded/validated array the main          |
   //--- pipeline used - Phase 1's Data Provider, not a second load) and  |
   //--- combine into a single overall decision (design notes 2/3,        |
   //--- GZ_FilterTypes.mqh). Deterministic: identical setup+rates+cfg    |
   //--- always produce an identical outcome (T105).                      |
   void Evaluate(const GZ_Setup &setup, const MqlRates &m5[], const GZ_FilterSetConfig &cfg,
                 CGZTimeEngine &time_engine, CGZSessionEngine &session_engine,
                 GZ_SetupFilterOutcome &out) const
     {
      out.Clear();
      out.setup_id = setup.id;
      for(int i=0;i<GZ_FILTER_COUNT;i++)
         out.results[i].id = (ENUM_GZ_FILTER_ID)i;

      bool have_break = setup.leg.broken;
      int  idx = have_break ? FindBarIndex(m5, setup.leg.break_time) : -1;

      //--- Break Quality: |break_price - target_swing.price| / ATR ------
      double break_dist = have_break ? MathAbs(setup.leg.break_price-setup.leg.target_swing.price) : 0.0;
      EvalAtrThreshold(have_break, break_dist, m5, idx, cfg.atr_period,
                        cfg.break_quality_min_atr_mult, out.results[GZ_FILTER_BREAK_QUALITY]);

      //--- Leg Quality: leg size / ATR ---------------------------------
      double leg_size = have_break ? setup.leg.LegSize() : 0.0;
      EvalAtrThreshold(have_break, leg_size, m5, idx, cfg.atr_period,
                        cfg.leg_quality_min_atr_mult, out.results[GZ_FILTER_LEG_QUALITY]);

      //--- Volume: break bar's tick_volume vs trailing average ---------
      {
       out.results[GZ_FILTER_VOLUME].result = GZ_FILTER_NOT_AVAILABLE;
       out.results[GZ_FILTER_VOLUME].metric_value = 0.0;
       if(have_break && idx>=0)
         {
          bool ready;
          double avg = AvgVolumeAt(m5, idx, cfg.volume_lookback, ready);
          if(ready && avg>0.0)
            {
             double metric = (double)m5[idx].tick_volume/avg;
             out.results[GZ_FILTER_VOLUME].metric_value = metric;
             out.results[GZ_FILTER_VOLUME].result = (metric>=cfg.volume_min_mult) ? GZ_FILTER_PASS : GZ_FILTER_FAIL;
            }
         }
      }

      //--- Volatility: current ATR / baseline (longer-lookback) ATR ----
      {
       out.results[GZ_FILTER_VOLATILITY].result = GZ_FILTER_NOT_AVAILABLE;
       out.results[GZ_FILTER_VOLATILITY].metric_value = 0.0;
       if(have_break && idx>=0)
         {
          bool ready_cur, ready_base;
          double atr_cur  = AtrAt(m5, idx, cfg.atr_period, ready_cur);
          double atr_base = AtrAt(m5, idx, cfg.volatility_lookback, ready_base);
          if(ready_cur && ready_base && atr_base>0.0)
            {
             double metric = atr_cur/atr_base;
             out.results[GZ_FILTER_VOLATILITY].metric_value = metric;
             out.results[GZ_FILTER_VOLATILITY].result = (metric>=cfg.volatility_min_mult && metric<=cfg.volatility_max_mult)
                         ? GZ_FILTER_PASS : GZ_FILTER_FAIL;
            }
         }
      }

      //--- VWAP / M15 Context / News: reserved - see GZ_FilterTypes.mqh
      //--- design note 1. Left at Clear()'s GZ_FILTER_NOT_AVAILABLE
      //--- default; never evaluated further in this build.

      //--- Session: reuse the SAME Time/Session Engine every other      |
      //--- phase already uses (GZ_Session.mqh) - a genuinely new,       |
      //--- standalone Roadmap Phase 10 gate, independently configurable |
      //--- from the entry/exit session window (cfg.session_profile is   |
      //--- the Filter Engine's own GZ_SessionProfile). -------------------
      {
       out.results[GZ_FILTER_SESSION].result = GZ_FILTER_NOT_AVAILABLE;
       out.results[GZ_FILTER_SESSION].metric_value = 0.0;
       datetime ref_time = have_break ? setup.leg.break_time : setup.detected_time;
       if(ref_time!=0)
         {
          GZ_TimeContext ctx;
          time_engine.BuildContext(ref_time, ctx);
          if(ctx.broker_tz_status==GZ_TZ_KNOWN)
            {
             ENUM_GZ_SESSION_RESULT sr = session_engine.Evaluate(ctx, cfg.session_profile);
             out.results[GZ_FILTER_SESSION].metric_value = (sr==GZ_SESSION_INSIDE) ? 1.0 : 0.0;
             out.results[GZ_FILTER_SESSION].result = (sr==GZ_SESSION_INSIDE) ? GZ_FILTER_PASS : GZ_FILTER_FAIL;
            }
         }
      }

      //--- Combine (design notes 2/3, GZ_FilterTypes.mqh): AND across    |
      //--- every ENABLED (non-OFF) filter; NOT_AVAILABLE never auto-     |
      //--- passes; OFF filters never gate anything. -----------------------
      bool pass = true;
      for(int i=0;i<GZ_FILTER_COUNT;i++)
        {
         ENUM_GZ_FILTER_MODE mode = cfg.mode[i];
         if(mode==GZ_FILTER_OFF)
            continue;
         ENUM_GZ_FILTER_RESULT res = out.results[i].result;
         bool allowed;
         if(res==GZ_FILTER_NOT_AVAILABLE)
            allowed = false;                          // design note 2 - never auto-pass
         else if(mode==GZ_FILTER_INCLUDE)
            allowed = (res==GZ_FILTER_PASS);
         else // GZ_FILTER_EXCLUDE
            allowed = (res==GZ_FILTER_FAIL);
         if(!allowed)
            pass = false;
        }
      out.overall_pass = pass;

      if(m_logger!=NULL)
         m_logger.Debug("Filter", StringFormat("Setup #%d %s", (int)setup.id, out.Summary()));
     }
  };

#endif // __GZ_FILTER_ENGINE_MQH__
