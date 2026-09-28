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

   //--- HTF Bias cache (the formerly-reserved M15 Context slot). Built ONCE
   //--- per (M5 array, period, EMA) signature by bucketing the already-loaded
   //--- M5 series into higher-timeframe bars - no extra data load, no
   //--- per-setup rescan (a 4.5-year run has ~77k setups; a per-setup rescan
   //--- of ~400k bars would be far too slow). No lookahead: a setup only ever
   //--- sees HTF buckets whose nominal END is at or before its own break_time,
   //--- i.e. fully completed bars; the still-forming HTF bar is never read.
   int               m_htf_n;
   datetime          m_htf_first;
   datetime          m_htf_last;
   double            m_htf_last_close;   // + mid_close: signature guard so two DIFFERENT
   double            m_htf_mid_close;    //   arrays with identical size/first/last time never share a cache
   int               m_htf_period_min;
   int               m_htf_ema_period;
   datetime          m_htf_end[];     // nominal end time of each HTF bucket (ascending)
   int               m_htf_bias[];    // +1 close>EMA, -1 close<EMA, 0 = EMA warm-up / equal

   void HtfPush(long bucket, double close, long psec, int ema_period, double alpha,
                double &ema, int &cnt, double &sum)
     {
      cnt++;
      if(cnt<=ema_period)
        {
         sum += close;
         if(cnt==ema_period)
            ema = sum/ema_period;
        }
      else
         ema = ema + alpha*(close-ema);
      int bias = 0;
      if(cnt>=ema_period)
        {
         if(close>ema)      bias = 1;
         else if(close<ema) bias = -1;
        }
      int sz = ArraySize(m_htf_end);
      ArrayResize(m_htf_end,  sz+1, 4096);
      ArrayResize(m_htf_bias, sz+1, 4096);
      m_htf_end[sz]  = (datetime)((bucket+1)*psec);
      m_htf_bias[sz] = bias;
     }

   //--- (Re)build the HTF series if the signature differs. An invalid
   //--- period (<5 or not a multiple of 5) or empty array leaves the series
   //--- empty -> every lookup reports NOT_AVAILABLE (never a guessed PASS).
   void EnsureHtf(const MqlRates &m5[], int period_min, int ema_period)
     {
      int n = ArraySize(m5);
      datetime first = (n>0) ? m5[0].time : 0;
      datetime last  = (n>0) ? m5[n-1].time : 0;
      double last_close = (n>0) ? m5[n-1].close : 0.0;
      double mid_close  = (n>0) ? m5[n/2].close : 0.0;
      if(m_htf_n==n && m_htf_first==first && m_htf_last==last &&
         m_htf_last_close==last_close && m_htf_mid_close==mid_close &&
         m_htf_period_min==period_min && m_htf_ema_period==ema_period)
         return;

      m_htf_n=n; m_htf_first=first; m_htf_last=last;
      m_htf_last_close=last_close; m_htf_mid_close=mid_close;
      m_htf_period_min=period_min; m_htf_ema_period=ema_period;
      ArrayResize(m_htf_end,0);
      ArrayResize(m_htf_bias,0);
      if(n==0 || period_min<5 || (period_min%5)!=0 || ema_period<1)
         return;

      long   psec  = (long)period_min*60;
      double alpha = 2.0/(double)(ema_period+1);
      double ema=0.0, sum=0.0; int cnt=0;
      long   cur=-1; double close=0.0;
      for(int i=0;i<n;i++)
        {
         long b = (long)m5[i].time/psec;
         if(b!=cur)
           {
            if(cur>=0)
               HtfPush(cur, close, psec, ema_period, alpha, ema, cnt, sum);
            cur=b;
           }
         close = m5[i].close;
        }
      if(cur>=0)
         HtfPush(cur, close, psec, ema_period, alpha, ema, cnt, sum);
     }

   //--- Bias of the last HTF bucket completed at or before t. ok=false when
   //--- there is none or its EMA is still warming up.
   int HtfBiasAt(datetime t, bool &ok) const
     {
      ok = false;
      int n = ArraySize(m_htf_end);
      if(n==0 || m_htf_end[0]>t)
         return 0;
      int lo=0, hi=n-1, best=-1;
      while(lo<=hi)
        {
         int mid=(lo+hi)/2;
         if(m_htf_end[mid]<=t) { best=mid; lo=mid+1; }
         else                    hi=mid-1;
        }
      if(best<0)
         return 0;
      int b = m_htf_bias[best];
      ok = (b!=0);
      return b;
     }

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
                     CGZFilterEngine(CGZLogger *logger=NULL)
     {
      m_logger=logger;
      m_htf_n=-1; m_htf_first=0; m_htf_last=0; m_htf_last_close=0.0; m_htf_mid_close=0.0; m_htf_period_min=0; m_htf_ema_period=0;
     }

   //--- Evaluate every filter for one setup against the supplied M5      |
   //--- rates (the SAME already-loaded/validated array the main          |
   //--- pipeline used - Phase 1's Data Provider, not a second load) and  |
   //--- combine into a single overall decision (design notes 2/3,        |
   //--- GZ_FilterTypes.mqh). Deterministic: identical setup+rates+cfg    |
   //--- always produce an identical outcome (T105).                      |
   void Evaluate(const GZ_Setup &setup, const MqlRates &m5[], const GZ_FilterSetConfig &cfg,
                 CGZTimeEngine &time_engine, CGZSessionEngine &session_engine,
                 GZ_SetupFilterOutcome &out)
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

      //--- HTF Bias (the formerly-reserved M15 Context slot): the setup's
      //--- direction must agree with the higher-timeframe trend - last
      //--- COMPLETED HTF bar's close vs the EMA of HTF closes - as of the
      //--- setup's break_time. PASS = aligned, FAIL = counter-trend,
      //--- NOT_AVAILABLE = no break yet / EMA warm-up / invalid period.
      //--- metric_value = +1 (HTF bullish) or -1 (HTF bearish). Evaluated
      //--- only when this filter is enabled (mode != OFF), so every run with
      //--- it OFF is byte-identical to before.
      {
       out.results[GZ_FILTER_M15_CONTEXT].result = GZ_FILTER_NOT_AVAILABLE;
       out.results[GZ_FILTER_M15_CONTEXT].metric_value = 0.0;
       if(cfg.mode[GZ_FILTER_M15_CONTEXT]!=GZ_FILTER_OFF && have_break)
         {
          EnsureHtf(m5, cfg.htf_period_minutes, cfg.htf_ema_period);
          bool ok;
          int bias = HtfBiasAt(setup.leg.break_time, ok);
          if(ok)
            {
             bool bullish_setup = (setup.leg.direction==GZ_LEG_BULLISH);
             bool aligned = (bullish_setup && bias>0) || (!bullish_setup && bias<0);
             out.results[GZ_FILTER_M15_CONTEXT].metric_value = (double)bias;
             out.results[GZ_FILTER_M15_CONTEXT].result = aligned ? GZ_FILTER_PASS : GZ_FILTER_FAIL;
            }
         }
      }

      //--- VWAP / News: reserved - see GZ_FilterTypes.mqh design note 1.
      //--- Left at Clear()'s GZ_FILTER_NOT_AVAILABLE default.

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
