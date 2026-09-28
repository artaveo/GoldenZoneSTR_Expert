//+------------------------------------------------------------------+
//| GZ_HtfBiasTests.mqh                                               |
//| GoldenZone STR - HTF Bias filter (the M15 Context slot) - T278-284|
//|                                                                    |
//| Synthetic M5 series only, same self-contained-suite convention as  |
//| GZ_CostRSymTests.mqh / GZ_ConcurrencyTests.mqh. Every fixture uses |
//| htf_period_minutes=60 and htf_ema_period=3 so the EMA warm-up is   |
//| only three hourly bars and the expected bias can be checked by hand|
//| (a rising series closes ABOVE its lagging EMA -> bullish, a falling|
//| one BELOW -> bearish; verified independently of the MQL5 code).    |
//+------------------------------------------------------------------+
#ifndef __GZ_HTF_BIAS_TESTS_MQH__
#define __GZ_HTF_BIAS_TESTS_MQH__

#include "GZ_FilterEngine.mqh"
#include "GZ_FilterTypes.mqh"
#include "..\Time\GZ_TimeEngine.mqh"
#include "..\Time\GZ_Session.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZHtfBiasTests
  {
private:
   CGZLogger        *m_logger;
   GZ_TestResult     m_results[];

   void AddResult(string id, bool passed, string detail)
     {
      int n = ArraySize(m_results);
      ArrayResize(m_results, n+1);
      m_results[n].id = id; m_results[n].passed = passed; m_results[n].blocked = false; m_results[n].detail = detail;
      if(m_logger!=NULL)
         m_logger.Info("Test", StringFormat("%s: %s - %s", id, passed?"PASS":"FAIL", detail));
     }

   datetime MakeTime(int y,int mo,int d,int h,int mi,int s=0) const
     {
      MqlDateTime dt;
      dt.year=y; dt.mon=mo; dt.day=d; dt.hour=h; dt.min=mi; dt.sec=s;
      return StructToTime(dt);
     }

   MqlRates MakeBar(datetime t, double c) const
     {
      MqlRates r;
      r.time=t; r.open=c; r.high=c+0.5; r.low=c-0.5; r.close=c;
      r.tick_volume=100; r.spread=1; r.real_volume=0;
      return r;
     }

   //--- 14 hours of M5 bars. slope>0 rising, slope<0 falling; when
   //--- flip_bar>=0 every bar from that index on closes at exactly 50.
   void BuildSeries(MqlRates &r[], datetime t0, double slope, int flip_bar=-1) const
     {
      int n = 12*14;
      ArrayResize(r, n);
      for(int i=0;i<n;i++)
        {
         double c = 100.0 + slope*i;
         if(flip_bar>=0 && i>=flip_bar) c = 50.0;
         r[i] = MakeBar(t0+i*300, c);
        }
     }

   GZ_Setup MakeSetup(ENUM_GZ_LEG_DIR dir, datetime break_time) const
     {
      GZ_Setup s; s.Clear();
      s.id = 1;
      s.leg.Clear();
      s.leg.id = 1;
      s.leg.direction = dir;
      s.leg.broken = true;
      s.leg.break_time = break_time;
      s.leg.break_price = 100.0;
      s.detected_time = break_time-3600;
      s.state = GZ_SETUP_BREAK_CONFIRMED;
      return s;
     }

   GZ_FilterSetConfig MakeCfg(ENUM_GZ_FILTER_MODE mode, int period_min=60, int ema=3) const
     {
      GZ_FilterSetConfig c; c.Default();
      c.mode[GZ_FILTER_M15_CONTEXT] = mode;
      c.htf_period_minutes = period_min;
      c.htf_ema_period     = ema;
      return c;
     }

   //--- All struct arguments are built as locals here: MQL5 passes structs
   //--- by reference only, so function-call results must not be handed
   //--- straight to a reference parameter.
   void Run(CGZFilterEngine &fe, ENUM_GZ_LEG_DIR dir, datetime break_time, const MqlRates &bars[],
            ENUM_GZ_FILTER_MODE mode, GZ_SetupFilterOutcome &out, int period_min=60, int ema=3)
     {
      GZ_Setup s = MakeSetup(dir, break_time);
      GZ_FilterSetConfig cfg = MakeCfg(mode, period_min, ema);
      CGZTimeEngine te(m_logger); GZ_TimeConfig tc; tc.Default(); te.Configure(tc);
      CGZSessionEngine se;
      fe.Evaluate(s, bars, cfg, te, se, out);
     }

   //--- T278: rising market, INCLUDE: bullish setup PASSES, bearish setup
   //--- FAILS (counter-trend) and is rejected overall.
   void T278_RisingIncludeAlignment()
     {
      datetime t0 = MakeTime(2026,3,2,0,0);
      MqlRates bars[]; BuildSeries(bars, t0, +0.05);
      CGZFilterEngine fe(m_logger);
      GZ_SetupFilterOutcome oL, oS;
      Run(fe, GZ_LEG_BULLISH, t0+10*3600, bars, GZ_FILTER_INCLUDE, oL);
      Run(fe, GZ_LEG_BEARISH, t0+10*3600, bars, GZ_FILTER_INCLUDE, oS);
      bool ok = (oL.results[GZ_FILTER_M15_CONTEXT].result==GZ_FILTER_PASS) && oL.overall_pass &&
                (oS.results[GZ_FILTER_M15_CONTEXT].result==GZ_FILTER_FAIL) && !oS.overall_pass &&
                (oL.results[GZ_FILTER_M15_CONTEXT].metric_value>0.0);
      AddResult("T278", ok, StringFormat("rising HTF, INCLUDE: long=%s(overall %s) short=%s(overall %s) bias=%.0f (expect PASS/true, FAIL/false, +1)",
                GZFilterResultToString(oL.results[GZ_FILTER_M15_CONTEXT].result), oL.overall_pass?"true":"false",
                GZFilterResultToString(oS.results[GZ_FILTER_M15_CONTEXT].result), oS.overall_pass?"true":"false",
                oL.results[GZ_FILTER_M15_CONTEXT].metric_value));
     }

   //--- T279: falling market mirrors it, and EXCLUDE mirrors INCLUDE.
   void T279_FallingAndExcludeMirror()
     {
      datetime t0 = MakeTime(2026,3,2,0,0);
      MqlRates bars[]; BuildSeries(bars, t0, -0.05);
      CGZFilterEngine fe(m_logger);
      GZ_SetupFilterOutcome inL, inS, exL, exS;
      Run(fe, GZ_LEG_BULLISH, t0+10*3600, bars, GZ_FILTER_INCLUDE, inL);
      Run(fe, GZ_LEG_BEARISH, t0+10*3600, bars, GZ_FILTER_INCLUDE, inS);
      Run(fe, GZ_LEG_BULLISH, t0+10*3600, bars, GZ_FILTER_EXCLUDE, exL);
      Run(fe, GZ_LEG_BEARISH, t0+10*3600, bars, GZ_FILTER_EXCLUDE, exS);
      bool ok = (!inL.overall_pass) && inS.overall_pass && exL.overall_pass && (!exS.overall_pass) &&
                (inS.results[GZ_FILTER_M15_CONTEXT].metric_value<0.0);
      AddResult("T279", ok, StringFormat("falling HTF: INCLUDE long/short=%s/%s EXCLUDE long/short=%s/%s (expect false/true, true/false)",
                inL.overall_pass?"true":"false", inS.overall_pass?"true":"false",
                exL.overall_pass?"true":"false", exS.overall_pass?"true":"false"));
     }

   //--- T280: EMA warm-up -> NOT_AVAILABLE, and an enabled filter never
   //--- auto-passes it (explicit Roadmap rule).
   void T280_WarmupNotAvailableNeverPasses()
     {
      datetime t0 = MakeTime(2026,3,2,0,0);
      MqlRates bars[]; BuildSeries(bars, t0, +0.05);
      CGZFilterEngine fe(m_logger);
      GZ_SetupFilterOutcome o;
      Run(fe, GZ_LEG_BULLISH, t0+2*3600+1800, bars, GZ_FILTER_INCLUDE, o); // only 2 completed HTF bars, EMA needs 3
      bool ok = (o.results[GZ_FILTER_M15_CONTEXT].result==GZ_FILTER_NOT_AVAILABLE) && !o.overall_pass;
      AddResult("T280", ok, StringFormat("break at 02:30 (2 completed HTF bars < EMA period 3): result=%s overall_pass=%s (expect NOT_AVAILABLE/false)",
                GZFilterResultToString(o.results[GZ_FILTER_M15_CONTEXT].result), o.overall_pass?"true":"false"));
     }

   //--- T281: NO LOOKAHEAD. The market collapses inside hour 10. A break at
   //--- 10:30 must still see the LAST COMPLETED bar (hour 9, bullish) - the
   //--- forming hour-10 bar is never read. A break at 11:00 (hour 10 now
   //--- complete) must see the collapse (bearish).
   void T281_NoLookaheadFormingBarNeverRead()
     {
      datetime t0 = MakeTime(2026,3,2,0,0);
      MqlRates bars[]; BuildSeries(bars, t0, +0.05, 120); // bars 0-119 (hours 0-9) rise, hour 10+ closes at 50
      CGZFilterEngine fe(m_logger);
      GZ_SetupFilterOutcome oMid, oAfter;
      Run(fe, GZ_LEG_BULLISH, t0+10*3600+1800, bars, GZ_FILTER_INCLUDE, oMid);
      Run(fe, GZ_LEG_BULLISH, t0+11*3600, bars, GZ_FILTER_INCLUDE, oAfter);
      bool ok = (oMid.results[GZ_FILTER_M15_CONTEXT].metric_value>0.0) &&
                (oMid.results[GZ_FILTER_M15_CONTEXT].result==GZ_FILTER_PASS) &&
                (oAfter.results[GZ_FILTER_M15_CONTEXT].metric_value<0.0) &&
                (oAfter.results[GZ_FILTER_M15_CONTEXT].result==GZ_FILTER_FAIL);
      AddResult("T281", ok, StringFormat("break 10:30 (hour 10 still forming) bias=%.0f -> %s | break 11:00 (hour 10 complete) bias=%.0f -> %s (expect +1 PASS, -1 FAIL)",
                oMid.results[GZ_FILTER_M15_CONTEXT].metric_value, GZFilterResultToString(oMid.results[GZ_FILTER_M15_CONTEXT].result),
                oAfter.results[GZ_FILTER_M15_CONTEXT].metric_value, GZFilterResultToString(oAfter.results[GZ_FILTER_M15_CONTEXT].result)));
     }

   //--- T282: invalid HTF period (not a multiple of 5) -> NOT_AVAILABLE,
   //--- never a guessed result.
   void T282_InvalidPeriodNotAvailable()
     {
      datetime t0 = MakeTime(2026,3,2,0,0);
      MqlRates bars[]; BuildSeries(bars, t0, +0.05);
      CGZFilterEngine fe(m_logger);
      GZ_SetupFilterOutcome o7, o0;
      Run(fe, GZ_LEG_BULLISH, t0+10*3600, bars, GZ_FILTER_INCLUDE, o7, 7, 3);
      Run(fe, GZ_LEG_BULLISH, t0+10*3600, bars, GZ_FILTER_INCLUDE, o0, 60, 0);
      bool ok = (o7.results[GZ_FILTER_M15_CONTEXT].result==GZ_FILTER_NOT_AVAILABLE) &&
                (o0.results[GZ_FILTER_M15_CONTEXT].result==GZ_FILTER_NOT_AVAILABLE);
      AddResult("T282", ok, StringFormat("period=7min -> %s, EMA period=0 -> %s (expect NOT_AVAILABLE both)",
                GZFilterResultToString(o7.results[GZ_FILTER_M15_CONTEXT].result),
                GZFilterResultToString(o0.results[GZ_FILTER_M15_CONTEXT].result)));
     }

   //--- T283: REGRESSION - filter OFF (the default) is not evaluated at all:
   //--- result stays NOT_AVAILABLE and overall_pass stays true, exactly as
   //--- before this feature existed, even on a market where it would FAIL.
   void T283_OffIsByteIdenticalToBefore()
     {
      datetime t0 = MakeTime(2026,3,2,0,0);
      MqlRates bars[]; BuildSeries(bars, t0, +0.05);
      CGZFilterEngine fe(m_logger);
      GZ_SetupFilterOutcome o;
      Run(fe, GZ_LEG_BEARISH, t0+10*3600, bars, GZ_FILTER_OFF, o); // would be FAIL if evaluated
      bool ok = (o.results[GZ_FILTER_M15_CONTEXT].result==GZ_FILTER_NOT_AVAILABLE) && o.overall_pass;
      AddResult("T283", ok, StringFormat("mode OFF, counter-trend setup: result=%s overall_pass=%s (expect NOT_AVAILABLE/true)",
                GZFilterResultToString(o.results[GZ_FILTER_M15_CONTEXT].result), o.overall_pass?"true":"false"));
     }

   //--- T284: the SAME engine instance must not reuse a cached HTF series
   //--- for a DIFFERENT market that has identical size and timestamps.
   void T284_CacheNeverSharedAcrossDifferentData()
     {
      datetime t0 = MakeTime(2026,3,2,0,0);
      MqlRates up[]; BuildSeries(up, t0, +0.05);
      MqlRates dn[]; BuildSeries(dn, t0, -0.05);
      CGZFilterEngine fe(m_logger);
      GZ_SetupFilterOutcome a, b, c;
      Run(fe, GZ_LEG_BULLISH, t0+10*3600, up, GZ_FILTER_INCLUDE, a);
      Run(fe, GZ_LEG_BULLISH, t0+10*3600, dn, GZ_FILTER_INCLUDE, b);   // same engine, same size/first/last time, different closes
      Run(fe, GZ_LEG_BULLISH, t0+10*3600, up, GZ_FILTER_INCLUDE, c);   // back again
      bool ok = (a.results[GZ_FILTER_M15_CONTEXT].result==GZ_FILTER_PASS) &&
                (b.results[GZ_FILTER_M15_CONTEXT].result==GZ_FILTER_FAIL) &&
                (c.results[GZ_FILTER_M15_CONTEXT].result==GZ_FILTER_PASS);
      AddResult("T284", ok, StringFormat("same engine, rising->falling->rising data: %s -> %s -> %s (expect PASS, FAIL, PASS)",
                GZFilterResultToString(a.results[GZ_FILTER_M15_CONTEXT].result),
                GZFilterResultToString(b.results[GZ_FILTER_M15_CONTEXT].result),
                GZFilterResultToString(c.results[GZ_FILTER_M15_CONTEXT].result)));
     }

public:
                     CGZHtfBiasTests(CGZLogger *logger=NULL) { m_logger=logger; }

   int               ResultCount() const { return ArraySize(m_results); }
   GZ_TestResult     GetResult(int i) const { return m_results[i]; }

   void              RunAll()
     {
      T278_RisingIncludeAlignment();
      T279_FallingAndExcludeMirror();
      T280_WarmupNotAvailableNeverPasses();
      T281_NoLookaheadFormingBarNeverRead();
      T282_InvalidPeriodNotAvailable();
      T283_OffIsByteIdenticalToBefore();
      T284_CacheNeverSharedAcrossDifferentData();
     }
  };

#endif // __GZ_HTF_BIAS_TESTS_MQH__
