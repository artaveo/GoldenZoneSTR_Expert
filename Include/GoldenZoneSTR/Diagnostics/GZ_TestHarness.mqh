//+------------------------------------------------------------------+
//| GZ_TestHarness.mqh                                                 |
//| GoldenZone STR - Automated Test Harness                           |
//| Phase 1 (T01-T18): Data Layer + Validator + Time Engine           |
//| Phase 2 (T19-T23): M5 Structure Engine (swing detection)          |
//| Phase 3 (T24-T34): Leg Engine + Break Engine                      |
//| Phase 4 (T35-T45): Fibonacci Engine + Setup State Machine         |
//| Phase 5 (T46-T54): Entry Engine + Historical Trade Simulator      |
//| Phase 6 (T55-T64): Exit Engine (SL/TP/BE)                         |
//| Phase 7 (T65-T74): MAE/MFE + R-Path + Event Ledger                |
//| Phase 8 (T75-T86): Metrics + Reporting                            |
//| Phase 9 (T87-T96): Experiment Configuration + Runner               |
//| Phase 10 (T97-T106): Filter Engine                                 |
//|                                                                    |
//| All tests use synthetic, hand-built data so results are fully    |
//| deterministic and do NOT depend on broker history being present. |
//| Each test returns PASS/FAIL; none require user interaction -     |
//| however running this EA still requires the user to compile and   |
//| attach it in MetaTrader (see Phase1_TestReport.md / chat reply). |
//+------------------------------------------------------------------+
#ifndef __GZ_TESTHARNESS_MQH__
#define __GZ_TESTHARNESS_MQH__

#include "..\Core\GZ_Types.mqh"
#include "..\Core\GZ_Config.mqh"
#include "..\Data\GZ_DataValidator.mqh"
#include "..\Data\GZ_DatasetInfo.mqh"
#include "..\Time\GZ_TimeEngine.mqh"
#include "..\Time\GZ_DST.mqh"
#include "..\Time\GZ_Session.mqh"
#include "..\Structure\GZ_StructureTypes.mqh"
#include "..\Structure\GZ_SwingEngine.mqh"
#include "..\Leg\GZ_LegTypes.mqh"
#include "..\Leg\GZ_ATR.mqh"
#include "..\Leg\GZ_LegEngine.mqh"
#include "..\Leg\GZ_BreakEngine.mqh"
#include "..\Setup\GZ_SetupTypes.mqh"
#include "..\Setup\GZ_FibEngine.mqh"
#include "..\Setup\GZ_SetupStateMachine.mqh"
#include "..\Entry\GZ_EntryTypes.mqh"
#include "..\Entry\GZ_EntryEngine.mqh"
#include "..\Entry\GZ_TradeSimulator.mqh"
#include "..\Exit\GZ_ExitTypes.mqh"
#include "..\Exit\GZ_ExitEngine.mqh"
#include "..\Journal\GZ_JournalTypes.mqh"
#include "..\Journal\GZ_JournalEngine.mqh"
#include "..\Journal\GZ_LedgerTypes.mqh"
#include "..\Journal\GZ_EventLedger.mqh"
#include "..\Metrics\GZ_MetricsTypes.mqh"
#include "..\Metrics\GZ_MetricsEngine.mqh"
#include "..\Experiment\GZ_ExperimentTypes.mqh"
#include "..\Experiment\GZ_ExperimentRunner.mqh"
#include "..\Filter\GZ_FilterTypes.mqh"
#include "..\Filter\GZ_FilterEngine.mqh"
#include "GZ_Logger.mqh"

class CGZTestHarness
  {
private:
   CGZLogger        *m_logger;
   GZ_TestResult     m_results[];

   void AddResult(string id, bool passed, string detail)
     {
      int n = ArraySize(m_results);
      ArrayResize(m_results, n+1);
      m_results[n].id      = id;
      m_results[n].passed  = passed;
      m_results[n].blocked = false;
      m_results[n].detail  = detail;
      if(m_logger!=NULL)
         m_logger.Info("Test", StringFormat("%s: %s - %s", id, passed?"PASS":"FAIL", detail));
     }

   //--- helper: build one synthetic bar --------------------------------
   MqlRates MakeBar(datetime t, double o, double h, double l, double c, long vol=100)
     {
      MqlRates r;
      r.time=t; r.open=o; r.high=h; r.low=l; r.close=c;
      r.tick_volume=vol; r.spread=1; r.real_volume=0;
      return r;
     }

   datetime MakeTime(int y,int mo,int d,int h,int mi,int s=0) const
     {
      MqlDateTime dt;
      dt.year=y; dt.mon=mo; dt.day=d; dt.hour=h; dt.min=mi; dt.sec=s;
      return StructToTime(dt);
     }

public:
                     CGZTestHarness(CGZLogger *logger=NULL) { m_logger=logger; }

   int               ResultCount() const { return ArraySize(m_results); }
   GZ_TestResult     GetResult(int i) const { return m_results[i]; }

   //--- T01: OHLC validation ---------------------------------------------
   void T01_OHLCValidation()
     {
      MqlRates rates[];
      ArrayResize(rates,2);
      rates[0] = MakeBar(MakeTime(2026,1,5,10,0), 100,101,99,100.5);   // valid
      rates[1] = MakeBar(MakeTime(2026,1,5,10,1), 100,99,101,100.5);   // invalid: high<low

      CGZDatasetInfo info; info.Clear();
      CGZDataValidator validator(m_logger);
      int invalid = validator.ValidateOHLC(rates, info);

      bool ok = (invalid==1);
      AddResult("T01", ok, StringFormat("expected 1 invalid bar, got %d", invalid));
     }

   //--- T02: Duplicate timestamp -----------------------------------------
   void T02_DuplicateTimestamp()
     {
      MqlRates rates[];
      ArrayResize(rates,3);
      rates[0]=MakeBar(MakeTime(2026,1,5,10,0),100,101,99,100);
      rates[1]=MakeBar(MakeTime(2026,1,5,10,1),100,101,99,100);
      rates[2]=MakeBar(MakeTime(2026,1,5,10,1),100,101,99,100); // duplicate of previous

      CGZDatasetInfo info; info.Clear();
      CGZDataValidator validator(m_logger);
      validator.ValidateTimestamps(rates, GZ_SPACING_M1_SECONDS, info);

      bool ok = (info.duplicate_count==1);
      AddResult("T02", ok, StringFormat("expected 1 duplicate, got %d", info.duplicate_count));
     }

   //--- T03: Timestamp ordering -------------------------------------------
   void T03_TimestampOrdering()
     {
      MqlRates rates[];
      ArrayResize(rates,3);
      rates[0]=MakeBar(MakeTime(2026,1,5,10,2),100,101,99,100);
      rates[1]=MakeBar(MakeTime(2026,1,5,10,1),100,101,99,100); // out of order
      rates[2]=MakeBar(MakeTime(2026,1,5,10,3),100,101,99,100);

      CGZDatasetInfo info; info.Clear();
      CGZDataValidator validator(m_logger);
      validator.ValidateTimestamps(rates, GZ_SPACING_M1_SECONDS, info);

      bool ok = (info.timestamp_error_count==1);
      AddResult("T03", ok, StringFormat("expected 1 ordering error, got %d", info.timestamp_error_count));
     }

   //--- T04: Expected market gap (weekend) --------------------------------
   void T04_ExpectedMarketGap()
     {
      MqlRates rates[];
      ArrayResize(rates,2);
      // Friday 20:55 -> Sunday 22:00 (typical weekend closure), M5 spacing
      rates[0]=MakeBar(MakeTime(2026,1,2,20,55),100,101,99,100); // Friday
      rates[1]=MakeBar(MakeTime(2026,1,4,22,0),100,101,99,100);  // Sunday

      CGZDatasetInfo info; info.Clear();
      CGZDataValidator validator(m_logger);
      validator.ValidateTimestamps(rates, GZ_SPACING_M5_SECONDS, info);

      bool ok = (info.expected_gap_count==1 && info.missing_bar_count==0);
      AddResult("T04", ok, StringFormat("expected_gap=%d missing=%d", info.expected_gap_count, info.missing_bar_count));
     }

   //--- T05: Unexpected gap (weekday) -------------------------------------
   void T05_UnexpectedGap()
     {
      MqlRates rates[];
      ArrayResize(rates,2);
      // Tuesday 10:00 -> Tuesday 14:00, M5 spacing, no weekend in between
      rates[0]=MakeBar(MakeTime(2026,1,6,10,0),100,101,99,100);
      rates[1]=MakeBar(MakeTime(2026,1,6,14,0),100,101,99,100);

      CGZDatasetInfo info; info.Clear();
      CGZDataValidator validator(m_logger);
      validator.ValidateTimestamps(rates, GZ_SPACING_M5_SECONDS, info);

      bool ok = (info.missing_bar_count==1 && info.expected_gap_count==0);
      AddResult("T05", ok, StringFormat("missing=%d expected_gap=%d", info.missing_bar_count, info.expected_gap_count));
     }

   //--- T06: M1/M5 alignment ------------------------------------------------
   void T06_M1M5Alignment()
     {
      MqlRates m5[];
      ArrayResize(m5,3);
      m5[0]=MakeBar(MakeTime(2026,1,5,10,0),100,101,99,100);
      m5[1]=MakeBar(MakeTime(2026,1,5,10,5),100,101,99,100);
      m5[2]=MakeBar(MakeTime(2026,1,5,10,10),100,101,99,100);

      CGZDataValidator validator(m_logger);

      // M1 bar at 10:07 must map to the M5 bar opened at 10:05 (index 1),
      // never to the 10:10 bar even though it is "closer" by later index.
      int idx = validator.FindM5ContextForM1(MakeTime(2026,1,5,10,7), m5);
      bool ok = (idx==1);

      // Edge case: M1 exactly at an M5 open time maps to that same bar.
      int idx2 = validator.FindM5ContextForM1(MakeTime(2026,1,5,10,5), m5);
      ok = ok && (idx2==1);

      // Edge case: M1 before any M5 bar has opened -> -1 (no context yet).
      int idx3 = validator.FindM5ContextForM1(MakeTime(2026,1,5,9,59), m5);
      ok = ok && (idx3==-1);

      AddResult("T06", ok, StringFormat("idx(10:07)=%d idx(10:05)=%d idx(9:59)=%d", idx, idx2, idx3));
     }

   //--- T07: Broker time passthrough ---------------------------------------
   void T07_BrokerTime()
     {
      GZ_TimeConfig cfg; cfg.Default();
      cfg.broker_utc_offset_hours = 2;
      cfg.broker_offset_known = true;

      CGZTimeEngine engine(m_logger);
      engine.Configure(cfg);

      datetime broker_t = MakeTime(2026,1,5,12,0);
      GZ_TimeContext ctx;
      engine.BuildContext(broker_t, ctx);

      bool ok = (ctx.broker_time == broker_t);
      AddResult("T07", ok, StringFormat("broker_time=%s expected=%s", TimeToString(ctx.broker_time), TimeToString(broker_t)));
     }

   //--- T08: UTC conversion --------------------------------------------------
   void T08_UtcConversion()
     {
      GZ_TimeConfig cfg; cfg.Default();
      cfg.broker_utc_offset_hours = 3;
      cfg.broker_offset_known = true;

      CGZTimeEngine engine(m_logger);
      engine.Configure(cfg);

      datetime broker_t = MakeTime(2026,1,5,12,0); // broker = UTC+3
      datetime expected_utc = MakeTime(2026,1,5,9,0);

      GZ_TimeContext ctx;
      engine.BuildContext(broker_t, ctx);

      bool ok = (ctx.utc_time == expected_utc);
      AddResult("T08", ok, StringFormat("utc=%s expected=%s", TimeToString(ctx.utc_time), TimeToString(expected_utc)));
     }

   //--- T09: New York standard time (winter) ---------------------------------
   void T09_NyStandardTime()
     {
      GZ_TimeConfig cfg; cfg.Default();
      cfg.broker_utc_offset_hours = 0; // broker == UTC for this test
      cfg.broker_offset_known = true;
      cfg.dst_mode = GZ_DST_AUTO;

      CGZTimeEngine engine(m_logger);
      engine.Configure(cfg);

      datetime broker_t = MakeTime(2026,1,15,17,0); // mid-January, UTC 17:00
      GZ_TimeContext ctx;
      engine.BuildContext(broker_t, ctx);

      datetime expected_ny = MakeTime(2026,1,15,12,0); // UTC-5
      bool ok = (ctx.ny_time==expected_ny && ctx.dst_state=="EST" && !ctx.ny_is_dst);
      AddResult("T09", ok, StringFormat("ny=%s expected=%s state=%s", TimeToString(ctx.ny_time), TimeToString(expected_ny), ctx.dst_state));
     }

   //--- T10: New York daylight time (summer) ---------------------------------
   void T10_NyDaylightTime()
     {
      GZ_TimeConfig cfg; cfg.Default();
      cfg.broker_utc_offset_hours = 0;
      cfg.broker_offset_known = true;
      cfg.dst_mode = GZ_DST_AUTO;

      CGZTimeEngine engine(m_logger);
      engine.Configure(cfg);

      datetime broker_t = MakeTime(2026,7,15,17,0); // mid-July, UTC 17:00
      GZ_TimeContext ctx;
      engine.BuildContext(broker_t, ctx);

      datetime expected_ny = MakeTime(2026,7,15,13,0); // UTC-4
      bool ok = (ctx.ny_time==expected_ny && ctx.dst_state=="EDT" && ctx.ny_is_dst);
      AddResult("T10", ok, StringFormat("ny=%s expected=%s state=%s", TimeToString(ctx.ny_time), TimeToString(expected_ny), ctx.dst_state));
     }

   //--- T11: DST transition boundaries ----------------------------------------
   void T11_DstTransition()
     {
      CGZDst dst;
      // 2026 second Sunday of March = March 8, transition at 07:00 UTC
      datetime spring = dst.SpringForwardUtc(2026);
      bool before_spring = !dst.IsDaylight(spring - 1);
      bool after_spring  =  dst.IsDaylight(spring);

      // 2026 first Sunday of November = Nov 1, transition at 06:00 UTC
      datetime fall = dst.FallBackUtc(2026);
      bool before_fall =  dst.IsDaylight(fall - 1);
      bool after_fall  = !dst.IsDaylight(fall);

      bool ok = before_spring && after_spring && before_fall && after_fall;
      AddResult("T11", ok, StringFormat("spring=%s fall=%s bSpr=%d aSpr=%d bFall=%d aFall=%d",
                 TimeToString(spring), TimeToString(fall),
                 before_spring, after_spring, before_fall, after_fall));
     }

   //--- T12: Session start boundary (inside) -----------------------------------
   void T12_SessionStartBoundary()
     {
      GZ_SessionProfile profile;
      profile.Set("PROFILE_01","Test",GZ_TIME_BROKER,16,30,20,30,true,true);

      GZ_TimeContext ctx; ctx.Clear();
      ctx.broker_time = MakeTime(2026,1,5,16,30);

      CGZSessionEngine session;
      ENUM_GZ_SESSION_RESULT r = session.Evaluate(ctx, profile);

      bool ok = (r==GZ_SESSION_INSIDE);
      AddResult("T12", ok, "16:30 with window 16:30-20:30 must be INSIDE");
     }

   //--- T13: Session end boundary (outside) ------------------------------------
   void T13_SessionEndBoundary()
     {
      GZ_SessionProfile profile;
      profile.Set("PROFILE_01","Test",GZ_TIME_BROKER,16,30,20,30,true,true);

      GZ_TimeContext ctx; ctx.Clear();
      ctx.broker_time = MakeTime(2026,1,5,20,30);

      CGZSessionEngine session;
      ENUM_GZ_SESSION_RESULT r = session.Evaluate(ctx, profile);

      bool ok = (r==GZ_SESSION_OUTSIDE);
      AddResult("T13", ok, "20:30 with window 16:30-20:30 must be OUTSIDE");
     }

   //--- T14: Session middle (inside) -------------------------------------------
   void T14_SessionMiddle()
     {
      GZ_SessionProfile profile;
      profile.Set("PROFILE_01","Test",GZ_TIME_BROKER,16,30,20,30,true,true);

      GZ_TimeContext ctx; ctx.Clear();
      ctx.broker_time = MakeTime(2026,1,5,18,0);

      CGZSessionEngine session;
      ENUM_GZ_SESSION_RESULT r = session.Evaluate(ctx, profile);

      bool ok = (r==GZ_SESSION_INSIDE);
      AddResult("T14", ok, "18:00 with window 16:30-20:30 must be INSIDE");
     }

   //--- T15: Outside session -----------------------------------------------------
   void T15_OutsideSession()
     {
      GZ_SessionProfile profile;
      profile.Set("PROFILE_01","Test",GZ_TIME_BROKER,16,30,20,30,true,true);

      GZ_TimeContext ctx; ctx.Clear();
      ctx.broker_time = MakeTime(2026,1,5,9,0);

      CGZSessionEngine session;
      ENUM_GZ_SESSION_RESULT r = session.Evaluate(ctx, profile);

      bool ok = (r==GZ_SESSION_OUTSIDE);
      AddResult("T15", ok, "09:00 with window 16:30-20:30 must be OUTSIDE");
     }

   //--- T16: Overnight session ----------------------------------------------------
   void T16_OvernightSession()
     {
      GZ_SessionProfile profile;
      profile.Set("PROFILE_OVERNIGHT","Test Overnight",GZ_TIME_BROKER,22,0,2,0,true,true);

      CGZSessionEngine session;

      GZ_TimeContext ctx1; ctx1.Clear(); ctx1.broker_time = MakeTime(2026,1,5,23,0); // inside (late)
      GZ_TimeContext ctx2; ctx2.Clear(); ctx2.broker_time = MakeTime(2026,1,6,1,0);  // inside (early)
      GZ_TimeContext ctx3; ctx3.Clear(); ctx3.broker_time = MakeTime(2026,1,5,12,0); // outside (midday)
      GZ_TimeContext ctx4; ctx4.Clear(); ctx4.broker_time = MakeTime(2026,1,6,2,0);  // outside (end excl.)

      bool ok = (session.Evaluate(ctx1,profile)==GZ_SESSION_INSIDE) &&
                (session.Evaluate(ctx2,profile)==GZ_SESSION_INSIDE) &&
                (session.Evaluate(ctx3,profile)==GZ_SESSION_OUTSIDE) &&
                (session.Evaluate(ctx4,profile)==GZ_SESSION_OUTSIDE);

      AddResult("T16", ok, "overnight window 22:00-02:00 evaluated at 23:00/01:00/12:00/02:00");
     }

   //--- T17: Date range independence ------------------------------------------------
   void T17_DateRange()
     {
      CGZSessionEngine session;
      datetime range_start = MakeTime(2026,1,1,0,0);
      datetime range_end   = MakeTime(2026,3,31,23,59);

      bool before = session.IsInDateRange(MakeTime(2025,12,31,12,0), range_start, range_end)==false;
      bool inside = session.IsInDateRange(MakeTime(2026,2,15,12,0),  range_start, range_end)==true;
      bool after  = session.IsInDateRange(MakeTime(2026,4,1,0,0),    range_start, range_end)==false;

      bool ok = before && inside && after;
      AddResult("T17", ok, StringFormat("before=%d inside=%d after=%d", before, inside, after));
     }

   //--- T18: Determinism ------------------------------------------------------------
   void T18_Determinism()
     {
      GZ_TimeConfig cfg; cfg.Default();
      cfg.broker_utc_offset_hours = 2;
      cfg.broker_offset_known = true;
      cfg.dst_mode = GZ_DST_AUTO;

      CGZTimeEngine engine(m_logger);
      engine.Configure(cfg);

      datetime broker_t = MakeTime(2026,6,10,15,0);

      GZ_TimeContext ctxA; engine.BuildContext(broker_t, ctxA);
      GZ_TimeContext ctxB; engine.BuildContext(broker_t, ctxB);

      bool ok = (ctxA.broker_time==ctxB.broker_time) &&
                (ctxA.utc_time==ctxB.utc_time) &&
                (ctxA.ny_time==ctxB.ny_time) &&
                (ctxA.dst_state==ctxB.dst_state);

      AddResult("T18", ok, "two identical BuildContext calls must produce identical output");
     }

   //--- helper: bar from explicit high/low, open=close=midpoint (keeps
   //--- OHLC trivially valid: High>=max(o,c), Low<=min(o,c)) -------------
   MqlRates MakeHL(datetime t, double high, double low)
     {
      double mid = (high+low)/2.0;
      return MakeBar(t, mid, high, low, mid);
     }

   //--- T19: Simple pivot HIGH detection (baseline strength=2) -----------
   void T19_SwingHighDetection()
     {
      datetime t0 = MakeTime(2026,1,5,10,0);
      MqlRates rates[];
      ArrayResize(rates,5);
      rates[0]=MakeHL(t0+0*300,   100,90);
      rates[1]=MakeHL(t0+1*300,   103,93);
      rates[2]=MakeHL(t0+2*300,   110,95);  // pivot high
      rates[3]=MakeHL(t0+3*300,   104,94);
      rates[4]=MakeHL(t0+4*300,   101,91);

      CGZSwingEngine engine(m_logger);
      engine.Init(2);
      GZ_Swing swings[];
      int n = engine.DetectAll(rates, swings);

      bool ok = (n==1) && (swings[0].direction==GZ_SWING_HIGH) &&
                (MathAbs(swings[0].price-110)<0.00001) &&
                (swings[0].pivot_time==rates[2].time) &&
                (swings[0].confirmation_time==rates[4].time);
      AddResult("T19", ok, StringFormat("found=%d dir=%s price=%.2f pivot=%s confirm=%s",
                 n, n>0?swings[0].DirectionToString():"-", n>0?swings[0].price:0.0,
                 n>0?TimeToString(swings[0].pivot_time):"-", n>0?TimeToString(swings[0].confirmation_time):"-"));
     }

   //--- T20: Simple pivot LOW detection (baseline strength=2) ------------
   void T20_SwingLowDetection()
     {
      datetime t0 = MakeTime(2026,1,5,11,0);
      MqlRates rates[];
      ArrayResize(rates,5);
      rates[0]=MakeHL(t0+0*300,   110,100);
      rates[1]=MakeHL(t0+1*300,   108,97);
      rates[2]=MakeHL(t0+2*300,   105,90);  // pivot low
      rates[3]=MakeHL(t0+3*300,   107,96);
      rates[4]=MakeHL(t0+4*300,   109,99);

      CGZSwingEngine engine(m_logger);
      engine.Init(2);
      GZ_Swing swings[];
      int n = engine.DetectAll(rates, swings);

      bool ok = (n==1) && (swings[0].direction==GZ_SWING_LOW) &&
                (MathAbs(swings[0].price-90)<0.00001) &&
                (swings[0].pivot_time==rates[2].time) &&
                (swings[0].confirmation_time==rates[4].time);
      AddResult("T20", ok, StringFormat("found=%d dir=%s price=%.2f pivot=%s confirm=%s",
                 n, n>0?swings[0].DirectionToString():"-", n>0?swings[0].price:0.0,
                 n>0?TimeToString(swings[0].pivot_time):"-", n>0?TimeToString(swings[0].confirmation_time):"-"));
     }

   //--- T21: No lookahead - the pivot must not be confirmed before its
   //--- right-side confirmation bar has actually been fed to the engine.
   void T21_NoLookahead()
     {
      datetime t0 = MakeTime(2026,1,5,10,0);
      MqlRates rates[];
      ArrayResize(rates,5);
      rates[0]=MakeHL(t0+0*300,   100,90);
      rates[1]=MakeHL(t0+1*300,   103,93);
      rates[2]=MakeHL(t0+2*300,   110,95);  // pivot high, cannot be known yet
      rates[3]=MakeHL(t0+3*300,   104,94);
      rates[4]=MakeHL(t0+4*300,   101,91);  // 2nd right-side bar -> confirms rates[2]

      CGZSwingEngine engine(m_logger);
      engine.Init(2);

      bool premature_confirm = false;
      GZ_Swing s;
      for(int i=0;i<4;i++)  // feed bars 0..3 - must NOT confirm anything yet
        {
         if(engine.Update(rates[i], s))
            premature_confirm = true;
        }
      bool confirmed_on_time = engine.Update(rates[4], s); // 5th bar -> confirms

      bool ok = (!premature_confirm) && confirmed_on_time &&
                (s.direction==GZ_SWING_HIGH) && (s.pivot_time==rates[2].time) &&
                (s.confirmation_time==rates[4].time);
      AddResult("T21", ok, StringFormat("premature=%s confirmed_on_5th_bar=%s pivot=%s confirm=%s",
                 premature_confirm?"true":"false", confirmed_on_time?"true":"false",
                 TimeToString(s.pivot_time), TimeToString(s.confirmation_time)));
     }

   //--- T22: Pivot strength changes results - architecture supports the
   //--- roadmap's research range (1..5) via configuration, not hard-coding.
   void T22_PivotStrengthVariants()
     {
      datetime t0 = MakeTime(2026,1,5,12,0);
      MqlRates rates[];
      ArrayResize(rates,6);
      double highs[6] = {100,103,101,105,102,100};
      double lows[6]  = {50,49,48,47,46,45}; // strictly decreasing: never a low pivot at any strength here
      for(int i=0;i<6;i++)
         rates[i]=MakeHL(t0+i*300, highs[i], lows[i]);

      CGZSwingEngine e1(m_logger); e1.Init(1);
      GZ_Swing s1[];
      int n1 = e1.DetectAll(rates, s1);

      CGZSwingEngine e2(m_logger); e2.Init(2);
      GZ_Swing s2[];
      int n2 = e2.DetectAll(rates, s2);

      bool ok = (n1==2) && (s1[0].pivot_time==rates[1].time) && (s1[1].pivot_time==rates[3].time) &&
                (n2==1) && (s2[0].pivot_time==rates[3].time);
      AddResult("T22", ok, StringFormat("strength1_count=%d strength2_count=%d (expected 2 then 1)", n1, n2));
     }

   //--- T23: Determinism - identical data/config produces identical swings,
   //--- and the incremental (live-safe) API agrees with the batch API.
   void T23_SwingDeterminism()
     {
      datetime t0 = MakeTime(2026,1,5,13,0);
      MqlRates rates[];
      ArrayResize(rates,5);
      rates[0]=MakeHL(t0+0*300,   100,90);
      rates[1]=MakeHL(t0+1*300,   103,93);
      rates[2]=MakeHL(t0+2*300,   110,95);
      rates[3]=MakeHL(t0+3*300,   104,94);
      rates[4]=MakeHL(t0+4*300,   101,91);

      CGZSwingEngine eA(m_logger); eA.Init(2);
      GZ_Swing swingsA[];
      int nA = eA.DetectAll(rates, swingsA);

      CGZSwingEngine eB(m_logger); eB.Init(2);
      GZ_Swing swingsB[];
      int nB = eB.DetectAll(rates, swingsB);

      bool batch_repeatable = (nA==nB) && (nA==1) &&
                              (swingsA[0].price==swingsB[0].price) &&
                              (swingsA[0].pivot_time==swingsB[0].pivot_time) &&
                              (swingsA[0].confirmation_time==swingsB[0].confirmation_time);

      CGZSwingEngine eC(m_logger); eC.Init(2);
      GZ_Swing incremental_result; incremental_result.Clear(); bool got_incremental=false;
      for(int i=0;i<ArraySize(rates);i++)
        {
         GZ_Swing s;
         if(eC.Update(rates[i], s)) { incremental_result=s; got_incremental=true; }
        }
      bool incremental_matches_batch = got_incremental && batch_repeatable &&
                              (incremental_result.price==swingsA[0].price) &&
                              (incremental_result.pivot_time==swingsA[0].pivot_time) &&
                              (incremental_result.confirmation_time==swingsA[0].confirmation_time);

      bool ok = batch_repeatable && incremental_matches_batch;
      AddResult("T23", ok, StringFormat("batch_repeatable=%s incremental_matches_batch=%s",
                 batch_repeatable?"true":"false", incremental_matches_batch?"true":"false"));
     }

   //--- helper: build a swing fixture directly (Phase 3 tests don't need
   //--- to run the Swing Engine itself - that is already covered by
   //--- T19-T23; here we only need well-formed GZ_Swing inputs). --------
   GZ_Swing MakeSwing(ENUM_GZ_SWING_DIR dir, double price, datetime pivot_t, datetime confirm_t, long id=1)
     {
      GZ_Swing s; s.Clear();
      s.id = id;
      s.direction = dir;
      s.price = price;
      s.pivot_time = pivot_t;
      s.detection_time = pivot_t;
      s.confirmation_time = confirm_t;
      s.pivot_strength = 2;
      return s;
     }

   //--- T24: Leg creation baseline (LAST_SWING variant) - LOW then HIGH
   //--- produces a BULLISH leg with the correct origin/target pair. ------
   void T24_LegCreationBaseline()
     {
      datetime t0 = MakeTime(2026,1,5,10,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,          t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300,    t0+7*300, 2);

      CGZLegEngine engine(m_logger);
      engine.Init(GZ_LEG_VARIANT_LAST_SWING);

      int idx1=-1;
      bool created1 = engine.Update(low1, 0.0, false, idx1);

      int idx2=-1;
      bool created2 = engine.Update(high1, 0.0, false, idx2);

      bool ok = (!created1) && created2 && (idx2>=0);
      if(ok)
        {
         GZ_Leg leg = engine.GetLeg(idx2);
         ok = (leg.direction==GZ_LEG_BULLISH) &&
              (MathAbs(leg.origin_swing.price-90.0)<0.00001) &&
              (MathAbs(leg.target_swing.price-110.0)<0.00001) &&
              (leg.origin_swing.pivot_time==low1.pivot_time) &&
              (leg.target_swing.pivot_time==high1.pivot_time);
        }
      AddResult("T24", ok, StringFormat("created1=%s created2=%s dir=%s", created1?"true":"false", created2?"true":"false",
                (created2 && idx2>=0)?engine.GetLeg(idx2).DirectionToString():"-"));
     }

   //--- T25: Leg direction correctness - HIGH then LOW produces BEARISH. -
   void T25_LegDirectionBearish()
     {
      datetime t0 = MakeTime(2026,1,5,12,0);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 120.0, t0,       t0+2*300, 1);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  100.0, t0+5*300, t0+7*300, 2);

      CGZLegEngine engine(m_logger);
      engine.Init(GZ_LEG_VARIANT_LAST_SWING);

      int idx1=-1; engine.Update(high1, 0.0, false, idx1);
      int idx2=-1; bool created2 = engine.Update(low1, 0.0, false, idx2);

      bool ok = created2 && (idx2>=0);
      if(ok)
        {
         GZ_Leg leg = engine.GetLeg(idx2);
         ok = (leg.direction==GZ_LEG_BEARISH) &&
              (MathAbs(leg.origin_swing.price-120.0)<0.00001) &&
              (MathAbs(leg.target_swing.price-100.0)<0.00001);
        }
      AddResult("T25", ok, StringFormat("created=%s dir=%s", created2?"true":"false",
                (created2 && idx2>=0)?engine.GetLeg(idx2).DirectionToString():"-"));
     }

   //--- T26: No leg created from the very first swing (no opposite swing
   //--- exists yet) - documented, not fabricated. -------------------------
   void T26_NoLegOnFirstSwing()
     {
      datetime t0 = MakeTime(2026,1,5,9,0);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 50.0, t0, t0+2*300, 1);

      CGZLegEngine engine(m_logger);
      engine.Init(GZ_LEG_VARIANT_LAST_SWING);

      int idx=-1;
      bool created = engine.Update(high1, 0.0, false, idx);

      bool ok = (!created) && (idx==-1) && (engine.LegCount()==0);
      AddResult("T26", ok, StringFormat("created=%s legcount=%d", created?"true":"false", engine.LegCount()));
     }

   //--- T27: Extreme tracking - only bars at/after target confirmation
   //--- time count; earlier bars (even with a larger high) must be
   //--- ignored (no lookahead through pre-target bars). -------------------
   void T27_ExtremeTrackingNoLookahead()
     {
      datetime t0 = MakeTime(2026,1,5,10,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1); // origin
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2); // target, confirms at t0+7*300

      CGZLegEngine engine(m_logger);
      engine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int idx1=-1; engine.Update(low1, 0.0, false, idx1);
      int idx2=-1; engine.Update(high1, 0.0, false, idx2);

      // Bar BEFORE target confirmation time, artificially huge high - must
      // be ignored entirely.
      MqlRates preBar = MakeBar(t0+6*300, 150,150,149,150);
      engine.UpdateBar(preBar);

      GZ_Leg afterPre = engine.GetLeg(idx2);
      bool pre_ignored = (MathAbs(afterPre.extreme_price-110.0)<0.00001);

      // Bars AT/AFTER confirmation, increasing highs.
      MqlRates b1 = MakeBar(t0+7*300, 111,112,110,111);
      MqlRates b2 = MakeBar(t0+8*300, 112,116,111,113);
      MqlRates b3 = MakeBar(t0+9*300, 113,114,112,113); // lower high - must not regress extreme
      engine.UpdateBar(b1);
      engine.UpdateBar(b2);
      engine.UpdateBar(b3);

      GZ_Leg final_ = engine.GetLeg(idx2);
      bool tracked_ok = (MathAbs(final_.extreme_price-116.0)<0.00001) && (final_.extreme_time==b2.time);

      bool ok = pre_ignored && tracked_ok;
      AddResult("T27", ok, StringFormat("pre_ignored=%s extreme=%.2f@%s", pre_ignored?"true":"false",
                final_.extreme_price, TimeToString(final_.extreme_time)));
     }

   //--- T28: CLOSE break baseline - a wick above the level with a close
   //--- still below must NOT break; a subsequent close above must. --------
   void T28_CloseBreakBaseline()
     {
      datetime t0 = MakeTime(2026,1,5,10,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);

      CGZLegEngine legEngine(m_logger);
      legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int idx1=-1; legEngine.Update(low1, 0.0, false, idx1);
      int idx2=-1; legEngine.Update(high1, 0.0, false, idx2);
      GZ_Leg leg = legEngine.GetLeg(idx2);

      GZ_BreakConfig cfg; cfg.Default(); cfg.mode = GZ_BREAK_CLOSE; cfg.buffer_atr_mult = 0.0;
      CGZBreakEngine breakEngine(m_logger);
      breakEngine.Configure(cfg);

      MqlRates wickOnly = MakeBar(t0+7*300, 108,115,107,108); // wick above 110, close below
      breakEngine.OnBar(wickOnly);
      bool broke_on_wick = breakEngine.CheckBreak(leg, wickOnly);

      MqlRates closeAbove = MakeBar(t0+8*300, 109,112,108,111); // close above 110
      breakEngine.OnBar(closeAbove);
      bool broke_on_close = breakEngine.CheckBreak(leg, closeAbove);

      bool ok = (!broke_on_wick) && broke_on_close && leg.broken &&
                (leg.break_time==closeAbove.time) && (MathAbs(leg.break_price-111.0)<0.00001);
      AddResult("T28", ok, StringFormat("broke_on_wick=%s broke_on_close=%s break_price=%.2f",
                broke_on_wick?"true":"false", broke_on_close?"true":"false", leg.break_price));
     }

   //--- T29: WICK break variant - a wick above the level is sufficient,
   //--- even though the bar's close stays below. ---------------------------
   void T29_WickBreakVariant()
     {
      datetime t0 = MakeTime(2026,1,5,11,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);

      CGZLegEngine legEngine(m_logger);
      legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int idx1=-1; legEngine.Update(low1, 0.0, false, idx1);
      int idx2=-1; legEngine.Update(high1, 0.0, false, idx2);
      GZ_Leg leg = legEngine.GetLeg(idx2);

      GZ_BreakConfig cfg; cfg.Default(); cfg.mode = GZ_BREAK_WICK; cfg.buffer_atr_mult = 0.0;
      CGZBreakEngine breakEngine(m_logger);
      breakEngine.Configure(cfg);

      MqlRates wickBar = MakeBar(t0+7*300, 108,111,107,108); // high clears 110, close does not
      breakEngine.OnBar(wickBar);
      bool broke = breakEngine.CheckBreak(leg, wickBar);

      bool ok = broke && leg.broken && (MathAbs(leg.break_price-111.0)<0.00001);
      AddResult("T29", ok, StringFormat("broke=%s break_price=%.2f", broke?"true":"false", leg.break_price));
     }

   //--- T30: ATR-scaled break buffer suppresses a break until price clears
   //--- level+buffer, not just level. ---------------------------------------
   void T30_BreakBufferAtr()
     {
      datetime t0 = MakeTime(2026,1,5,12,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2); // level=110

      CGZLegEngine legEngine(m_logger);
      legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int idx1=-1; legEngine.Update(low1, 0.0, false, idx1);
      int idx2=-1; legEngine.Update(high1, 0.0, false, idx2);
      GZ_Leg leg = legEngine.GetLeg(idx2);

      GZ_BreakConfig cfg; cfg.Default(); cfg.mode = GZ_BREAK_CLOSE; cfg.atr_period = 3; cfg.buffer_atr_mult = 1.0;
      CGZBreakEngine breakEngine(m_logger);
      breakEngine.Configure(cfg);

      // Warm up ATR with 3 bars near the target level (108.0-109.5) so True
      // Range stays a clean, gap-free 1.0 each bar -> ATR becomes exactly
      // 1.0 once ready. (An earlier version of this test warmed up ATR at a
      // price far from the target level, which produced a large gap-driven
      // True Range on the very next bar and inflated ATR well past what the
      // test intended - fixed here by keeping every bar's price continuous.)
      MqlRates w1 = MakeBar(t0+7*300,  108.5,109.0,108.0,108.5);
      MqlRates w2 = MakeBar(t0+8*300,  108.5,109.5,108.5,109.0);
      MqlRates w3 = MakeBar(t0+9*300,  109.0,109.5,108.5,109.0);
      breakEngine.OnBar(w1); breakEngine.CheckBreak(leg, w1);
      breakEngine.OnBar(w2); breakEngine.CheckBreak(leg, w2);
      breakEngine.OnBar(w3); breakEngine.CheckBreak(leg, w3);
      bool atr_ready = breakEngine.AtrReady();
      double warmup_atr = breakEngine.CurrentAtr();
      bool atr_correct = MathAbs(warmup_atr-1.0)<0.00001;

      // Close at 110.3: clears the raw level (110) but, with buffer_atr_mult=1
      // and ATR~1.0, stays well below the buffered threshold (~111).
      MqlRates notEnough = MakeBar(t0+10*300, 109.0,110.3,109.0,110.3);
      breakEngine.OnBar(notEnough);
      bool broke_early = breakEngine.CheckBreak(leg, notEnough);

      // Close at 125: clears level+buffer by a wide margin regardless of any
      // gap-driven ATR movement from the bar above, so this assertion does
      // not depend on hand-tracking the buffer through further ring-buffer
      // updates.
      MqlRates enough = MakeBar(t0+11*300, 111,126,110,125);
      breakEngine.OnBar(enough);
      bool broke_late = breakEngine.CheckBreak(leg, enough);

      bool ok = atr_ready && atr_correct && (!broke_early) && broke_late && leg.broken;
      AddResult("T30", ok, StringFormat("atr_ready=%s warmup_atr=%.4f broke_early=%s broke_late=%s",
                atr_ready?"true":"false", warmup_atr, broke_early?"true":"false", broke_late?"true":"false"));
     }

   //--- T31: ATR calculation correctness on a known, hand-computable
   //--- True Range sequence. -----------------------------------------------
   void T31_AtrCorrectness()
     {
      datetime t0 = MakeTime(2026,1,5,13,0);
      // Bar1: no prev close -> TR = high-low = 2
      MqlRates b1 = MakeBar(t0,        100,102,100,101);
      // Bar2: TR = max(high-low, |high-prevclose|, |low-prevclose|)
      //         = max(102-99=3? ...) constructed to give TR = 4 exactly
      MqlRates b2 = MakeBar(t0+300,    101,105,101,103); // high-low=4, |105-101|=4, |101-101|=0 -> TR=4
      // Bar3: TR = 6
      MqlRates b3 = MakeBar(t0+600,    103,109,103,105); // high-low=6, |109-103|=6 -> TR=6

      CGZAtr atr;
      atr.Init(3);
      bool ready_before = atr.IsReady();
      atr.Update(b1);
      atr.Update(b2);
      bool ready_mid = atr.IsReady();
      atr.Update(b3);
      bool ready_after = atr.IsReady();

      double expected = (2.0+4.0+6.0)/3.0; // = 4.0
      bool ok = (!ready_before) && (!ready_mid) && ready_after && (MathAbs(atr.Value()-expected)<0.00001);
      AddResult("T31", ok, StringFormat("ready_after=%s atr=%.4f expected=%.4f", ready_after?"true":"false", atr.Value(), expected));
     }

   //--- T32: Leg variant MIN_DISTANCE picks a different origin than the
   //--- LAST_SWING baseline would, when the last confirmed opposite swing
   //--- is farther in price than an earlier one. ---------------------------
   void T32_LegVariantMinDistance()
     {
      datetime t0 = MakeTime(2026,1,5,14,0);
      GZ_Swing lowA = MakeSwing(GZ_SWING_LOW, 98.0, t0,          t0+2*300, 1);  // older, closer in price
      GZ_Swing lowB = MakeSwing(GZ_SWING_LOW, 70.0, t0+3*300,    t0+5*300, 2);  // last confirmed, farther
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 100.0, t0+8*300, t0+10*300, 3);

      CGZLegEngine baseline(m_logger);
      baseline.Init(GZ_LEG_VARIANT_LAST_SWING);
      int bi1=-1; baseline.Update(lowA, 0.0, false, bi1);
      int bi2=-1; baseline.Update(lowB, 0.0, false, bi2);
      int bi3=-1; baseline.Update(high1, 0.0, false, bi3);
      GZ_Leg baselineLeg = baseline.GetLeg(bi3);

      CGZLegEngine minDist(m_logger);
      minDist.Init(GZ_LEG_VARIANT_MIN_DISTANCE);
      int mi1=-1; minDist.Update(lowA, 0.0, false, mi1);
      int mi2=-1; minDist.Update(lowB, 0.0, false, mi2);
      int mi3=-1; minDist.Update(high1, 0.0, false, mi3);
      GZ_Leg minDistLeg = minDist.GetLeg(mi3);

      bool ok = (MathAbs(baselineLeg.origin_swing.price-70.0)<0.00001) &&
                (MathAbs(minDistLeg.origin_swing.price-98.0)<0.00001);
      AddResult("T32", ok, StringFormat("baseline_origin=%.2f min_distance_origin=%.2f",
                baselineLeg.origin_swing.price, minDistLeg.origin_swing.price));
     }

   //--- T33: Determinism - two identical Leg+Break runs over the same
   //--- swing/bar sequence produce identical Leg records. -------------------
   void T33_LegBreakDeterminism()
     {
      datetime t0 = MakeTime(2026,1,5,15,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);
      MqlRates b1 = MakeBar(t0+7*300, 111,112,110,111);
      MqlRates b2 = MakeBar(t0+8*300, 112,116,111,113);

      GZ_BreakConfig cfg; cfg.Default();

      CGZLegEngine legA(m_logger); legA.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brkA(m_logger); brkA.Configure(cfg);
      int aI1=-1; legA.Update(low1,0.0,false,aI1);
      int aI2=-1; legA.Update(high1,0.0,false,aI2);
      legA.UpdateBar(b1); brkA.OnBar(b1);
      GZ_Leg lA = legA.GetLeg(aI2); brkA.CheckBreak(lA,b1); legA.SetLeg(aI2,lA);
      legA.UpdateBar(b2); brkA.OnBar(b2);
      lA = legA.GetLeg(aI2); brkA.CheckBreak(lA,b2); legA.SetLeg(aI2,lA);

      CGZLegEngine legB(m_logger); legB.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brkB(m_logger); brkB.Configure(cfg);
      int bI1=-1; legB.Update(low1,0.0,false,bI1);
      int bI2=-1; legB.Update(high1,0.0,false,bI2);
      legB.UpdateBar(b1); brkB.OnBar(b1);
      GZ_Leg lB = legB.GetLeg(bI2); brkB.CheckBreak(lB,b1); legB.SetLeg(bI2,lB);
      legB.UpdateBar(b2); brkB.OnBar(b2);
      lB = legB.GetLeg(bI2); brkB.CheckBreak(lB,b2); legB.SetLeg(bI2,lB);

      GZ_Leg finalA = legA.GetLeg(aI2);
      GZ_Leg finalB = legB.GetLeg(bI2);

      bool ok = (finalA.direction==finalB.direction) &&
                (MathAbs(finalA.extreme_price-finalB.extreme_price)<0.00001) &&
                (finalA.extreme_time==finalB.extreme_time) &&
                (finalA.broken==finalB.broken) &&
                (finalA.break_time==finalB.break_time) &&
                (MathAbs(finalA.break_price-finalB.break_price)<0.00001);
      AddResult("T33", ok, StringFormat("brokenA=%s brokenB=%s extremeA=%.2f extremeB=%.2f",
                finalA.broken?"true":"false", finalB.broken?"true":"false", finalA.extreme_price, finalB.extreme_price));
     }

   //--- T34: No lookahead - break must not be confirmed on any bar before
   //--- the actual breaking bar, only on the exact bar that clears it. -----
   void T34_BreakNoLookahead()
     {
      datetime t0 = MakeTime(2026,1,5,16,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);

      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int i1=-1; legEngine.Update(low1,0.0,false,i1);
      int i2=-1; legEngine.Update(high1,0.0,false,i2);
      GZ_Leg leg = legEngine.GetLeg(i2);

      GZ_BreakConfig cfg; cfg.Default();
      CGZBreakEngine breakEngine(m_logger); breakEngine.Configure(cfg);

      MqlRates approach1 = MakeBar(t0+7*300, 105,108,104,106);
      MqlRates approach2 = MakeBar(t0+8*300, 106,109,105,108);
      MqlRates approach3 = MakeBar(t0+9*300, 108,110,107,109); // still not closed above 110
      MqlRates breakBar  = MakeBar(t0+10*300,109,113,108,112); // closes above 110

      bool premature = false;
      breakEngine.OnBar(approach1); if(breakEngine.CheckBreak(leg, approach1)) premature = true;
      breakEngine.OnBar(approach2); if(breakEngine.CheckBreak(leg, approach2)) premature = true;
      breakEngine.OnBar(approach3); if(breakEngine.CheckBreak(leg, approach3)) premature = true;
      breakEngine.OnBar(breakBar);
      bool confirmed_on_time = breakEngine.CheckBreak(leg, breakBar);

      bool ok = (!premature) && confirmed_on_time && leg.broken && (leg.break_time==breakBar.time);
      AddResult("T34", ok, StringFormat("premature=%s confirmed_on_time=%s break_time=%s",
                premature?"true":"false", confirmed_on_time?"true":"false", TimeToString(leg.break_time)));
     }

   //--- T35: Fib price-at-ratio, BULLISH leg (0%=extreme/high, 100%=origin/low)
   void T35_FibPriceBullish()
     {
      GZ_Leg leg; leg.Clear();
      leg.direction = GZ_LEG_BULLISH;
      leg.extreme_price = 110.0;
      leg.origin_swing.price = 90.0;

      double price = CGZFibEngine::PriceAtRatio(leg, 0.618);
      double expected = 110.0 - 0.618*(110.0-90.0); // 97.64

      bool ok = MathAbs(price-expected)<0.0001;
      AddResult("T35", ok, StringFormat("price=%.4f expected=%.4f", price, expected));
     }

   //--- T36: Fib price-at-ratio, BEARISH leg (0%=extreme/low, 100%=origin/high)
   void T36_FibPriceBearish()
     {
      GZ_Leg leg; leg.Clear();
      leg.direction = GZ_LEG_BEARISH;
      leg.extreme_price = 90.0;
      leg.origin_swing.price = 110.0;

      double price = CGZFibEngine::PriceAtRatio(leg, 0.618);
      double expected = 90.0 + 0.618*(110.0-90.0); // 102.36

      bool ok = MathAbs(price-expected)<0.0001;
      AddResult("T36", ok, StringFormat("price=%.4f expected=%.4f", price, expected));
     }

   //--- T37: Zone/bar overlap detection (order-independent, partial overlap
   //--- counts as a touch). -------------------------------------------------
   void T37_FibZoneOverlap()
     {
      GZ_Leg leg; leg.Clear();
      leg.direction = GZ_LEG_BULLISH;
      leg.extreme_price = 110.0;        // ratio 0.30 -> 104.0, ratio 0.90 -> 92.0
      leg.origin_swing.price = 90.0;

      MqlRates inside  = MakeBar(0, 94,95,93,94);     // fully inside [92,104]
      MqlRates below   = MakeBar(0, 90,91,89,90);     // fully below, no overlap
      MqlRates partial = MakeBar(0, 103,105,101,104); // straddles the top edge

      bool touches_inside  = CGZFibEngine::DoesBarTouchZone(leg, 0.30, 0.90, inside);
      bool touches_below   = CGZFibEngine::DoesBarTouchZone(leg, 0.30, 0.90, below);
      bool touches_partial = CGZFibEngine::DoesBarTouchZone(leg, 0.30, 0.90, partial);

      bool ok = touches_inside && (!touches_below) && touches_partial;
      AddResult("T37", ok, StringFormat("inside=%s below=%s partial=%s",
                touches_inside?"true":"false", touches_below?"true":"false", touches_partial?"true":"false"));
     }

   //--- T38: A newly-created leg produces a setup in LEG_DETECTED. ---------
   void T38_SetupCreatedOnLegDetected()
     {
      datetime t0 = MakeTime(2026,1,6,9,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);

      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int i1=-1; legEngine.Update(low1,0.0,false,i1);
      int i2=-1; legEngine.Update(high1,0.0,false,i2);
      GZ_Leg leg = legEngine.GetLeg(i2);

      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      int si = sm.OnLegCreated(leg);
      GZ_Setup setup = sm.GetSetup(si);

      bool ok = (setup.state==GZ_SETUP_LEG_DETECTED) && (setup.leg.id==leg.id) &&
                (setup.detected_time==high1.confirmation_time);
      AddResult("T38", ok, StringFormat("state=%s detected_time=%s", setup.StateToString(), TimeToString(setup.detected_time)));
     }

   //--- T39: A confirmed break locks the setup and activates its fib zone
   //--- (LEG_LOCKED -> FIB_ACTIVE cascade), zone bounds exactly match
   //--- CGZFibEngine at the configured ratios. -----------------------------
   void T39_SetupLocksAndActivatesFib()
     {
      datetime t0 = MakeTime(2026,1,6,10,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);

      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int i1=-1; legEngine.Update(low1,0.0,false,i1);
      int i2=-1; legEngine.Update(high1,0.0,false,i2);
      GZ_Leg leg = legEngine.GetLeg(i2);

      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      int si = sm.OnLegCreated(leg);

      GZ_BreakConfig cfg; cfg.Default(); // CLOSE, buffer=0
      CGZBreakEngine breakEngine(m_logger); breakEngine.Configure(cfg);

      MqlRates breakBar = MakeBar(t0+8*300, 109,112,108,111); // close=111>110, high=112
      legEngine.UpdateBar(breakBar);
      GZ_Leg legAfterExtreme = legEngine.GetLeg(i2); // extreme now 112
      breakEngine.OnBar(breakBar);
      bool broke = breakEngine.CheckBreak(legAfterExtreme, breakBar);
      legEngine.SetLeg(i2, legAfterExtreme);

      sm.OnLegBroken(legAfterExtreme);
      GZ_Setup setup = sm.GetSetup(si);

      // extreme=112, origin=90 -> zone@0.30=112-0.30*22=105.4, zone@0.90=112-0.90*22=92.2
      bool ok = broke && (setup.state==GZ_SETUP_FIB_ACTIVE) && (setup.locked_time==legAfterExtreme.break_time) &&
                (MathAbs(setup.zone_min_price-105.4)<0.0001) && (MathAbs(setup.zone_max_price-92.2)<0.0001);
      AddResult("T39", ok, StringFormat("state=%s zone_min=%.4f zone_max=%.4f", setup.StateToString(), setup.zone_min_price, setup.zone_max_price));
     }

   //--- T40: Once FIB_ACTIVE, a bar whose range touches the fib zone
   //--- advances the setup to WAITING_ENTRY. --------------------------------
   void T40_SetupWaitingEntryOnZoneTouch()
     {
      datetime t0 = MakeTime(2026,1,6,11,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);

      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int i1=-1; legEngine.Update(low1,0.0,false,i1);
      int i2=-1; legEngine.Update(high1,0.0,false,i2);
      GZ_Leg leg = legEngine.GetLeg(i2);

      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      int si = sm.OnLegCreated(leg);

      GZ_BreakConfig cfg; cfg.Default();
      CGZBreakEngine breakEngine(m_logger); breakEngine.Configure(cfg);
      MqlRates breakBar = MakeBar(t0+8*300, 109,112,108,111);
      legEngine.UpdateBar(breakBar);
      GZ_Leg legAfter = legEngine.GetLeg(i2);
      breakEngine.OnBar(breakBar);
      breakEngine.CheckBreak(legAfter, breakBar);
      legEngine.SetLeg(i2, legAfter);
      sm.OnLegBroken(legAfter);

      // zone=[92.2,105.4]; this bar's range (95-100) sits fully inside it.
      MqlRates touchBar = MakeBar(t0+9*300, 98,100,95,99);
      sm.OnBar(touchBar, true, false); // has_session=false -> no session cancellation
      GZ_Setup setup = sm.GetSetup(si);

      bool ok = (setup.state==GZ_SETUP_WAITING_ENTRY) && (setup.waiting_entry_time==touchBar.time);
      AddResult("T40", ok, StringFormat("state=%s waiting_entry_time=%s", setup.StateToString(), TimeToString(setup.waiting_entry_time)));
     }

   //--- T41: A fresh same-direction leg cancels the still-open setup on the
   //--- same side (NEW_VALID_SETUP); a different-direction leg leaves it
   //--- untouched. ------------------------------------------------------------
   void T41_NewValidSetupCancelsOlder()
     {
      datetime t0 = MakeTime(2026,1,6,12,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,          t0+2*300,  1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300,    t0+7*300,  2);
      GZ_Swing low2  = MakeSwing(GZ_SWING_LOW,  95.0,  t0+8*300,    t0+10*300, 3);
      GZ_Swing high2 = MakeSwing(GZ_SWING_HIGH, 115.0, t0+11*300,   t0+13*300, 4);

      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int iLow1=-1;  legEngine.Update(low1,0.0,false,iLow1);
      int iHigh1=-1; legEngine.Update(high1,0.0,false,iHigh1);  // leg1: BULLISH low1->high1
      int iLow2=-1;  legEngine.Update(low2,0.0,false,iLow2);    // legX: BEARISH high1->low2
      int iHigh2=-1; legEngine.Update(high2,0.0,false,iHigh2);  // leg2: BULLISH low2->high2

      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      int s0 = sm.OnLegCreated(legEngine.GetLeg(iHigh1)); // setup0: BULLISH
      int s1 = sm.OnLegCreated(legEngine.GetLeg(iLow2));  // setup1: BEARISH
      int s2 = sm.OnLegCreated(legEngine.GetLeg(iHigh2)); // setup2: BULLISH -> should cancel setup0

      GZ_Setup setup0 = sm.GetSetup(s0);
      GZ_Setup setup1 = sm.GetSetup(s1);
      GZ_Setup setup2 = sm.GetSetup(s2);

      bool ok = (setup0.state==GZ_SETUP_CANCELLED) && (setup0.cancel_reason==GZ_CANCEL_NEW_VALID_SETUP) &&
                (setup1.state==GZ_SETUP_LEG_DETECTED) &&
                (setup2.state==GZ_SETUP_LEG_DETECTED);
      AddResult("T41", ok, StringFormat("setup0=%s/%s setup1=%s setup2=%s",
                setup0.StateToString(), setup0.CancelReasonToString(), setup1.StateToString(), setup2.StateToString()));
     }

   //--- T42: An opposite-direction break cancels the still-open setup on
   //--- the other side (OPPOSITE_BREAK), while locking its own setup. ------
   void T42_OppositeBreakCancels()
     {
      datetime t0 = MakeTime(2026,1,6,13,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300,  1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300,  2);
      GZ_Swing low2  = MakeSwing(GZ_SWING_LOW,  95.0,  t0+8*300, t0+10*300, 3);

      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int iLow1=-1;  legEngine.Update(low1,0.0,false,iLow1);
      int iHigh1=-1; legEngine.Update(high1,0.0,false,iHigh1); // leg1: BULLISH low1->high1
      int iLow2=-1;  legEngine.Update(low2,0.0,false,iLow2);   // legX: BEARISH high1->low2

      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      int s0 = sm.OnLegCreated(legEngine.GetLeg(iHigh1)); // setup0: BULLISH
      int s1 = sm.OnLegCreated(legEngine.GetLeg(iLow2));  // setup1: BEARISH

      GZ_BreakConfig cfg; cfg.Default();
      CGZBreakEngine breakEngine(m_logger); breakEngine.Configure(cfg);
      MqlRates breakBar = MakeBar(t0+11*300, 109,112,108,111); // closes above leg1's target (110)
      legEngine.UpdateBar(breakBar);
      GZ_Leg leg1After = legEngine.GetLeg(iHigh1);
      breakEngine.OnBar(breakBar);
      breakEngine.CheckBreak(leg1After, breakBar);
      legEngine.SetLeg(iHigh1, leg1After);

      sm.OnLegBroken(leg1After);

      GZ_Setup setup0 = sm.GetSetup(s0);
      GZ_Setup setup1 = sm.GetSetup(s1);

      bool ok = (setup0.state==GZ_SETUP_FIB_ACTIVE) &&
                (setup1.state==GZ_SETUP_CANCELLED) && (setup1.cancel_reason==GZ_CANCEL_OPPOSITE_BREAK);
      AddResult("T42", ok, StringFormat("setup0=%s setup1=%s/%s",
                setup0.StateToString(), setup1.StateToString(), setup1.CancelReasonToString()));
     }

   //--- T43: A bar outside the configured session cancels an open setup
   //--- (SESSION_END) only when a session was actually configured. ---------
   void T43_SessionEndCancels()
     {
      datetime t0 = MakeTime(2026,1,6,14,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);

      CGZLegEngine legEngineA(m_logger); legEngineA.Init(GZ_LEG_VARIANT_LAST_SWING);
      int a1=-1; legEngineA.Update(low1,0.0,false,a1);
      int a2=-1; legEngineA.Update(high1,0.0,false,a2);

      CGZSetupStateMachine smA(m_logger); smA.Init(0.30,0.90);
      int saA = smA.OnLegCreated(legEngineA.GetLeg(a2));
      MqlRates bar = MakeBar(t0+8*300, 109,110,108,109);
      smA.OnBar(bar, false, true); // outside session, has_session=true -> cancel
      GZ_Setup setupA = smA.GetSetup(saA);

      CGZLegEngine legEngineB(m_logger); legEngineB.Init(GZ_LEG_VARIANT_LAST_SWING);
      int b1=-1; legEngineB.Update(low1,0.0,false,b1);
      int b2=-1; legEngineB.Update(high1,0.0,false,b2);

      CGZSetupStateMachine smB(m_logger); smB.Init(0.30,0.90);
      int saB = smB.OnLegCreated(legEngineB.GetLeg(b2));
      smB.OnBar(bar, false, false); // has_session=false -> must NOT cancel
      GZ_Setup setupB = smB.GetSetup(saB);

      bool ok = (setupA.state==GZ_SETUP_CANCELLED) && (setupA.cancel_reason==GZ_CANCEL_SESSION_END) &&
                (setupB.state!=GZ_SETUP_CANCELLED);
      AddResult("T43", ok, StringFormat("with_session=%s/%s without_session=%s",
                setupA.StateToString(), setupA.CancelReasonToString(), setupB.StateToString()));
     }

   //--- T44: OnDataEnd cancels every still-open setup (DATA_END), and never
   //--- overrides a setup that already reached a terminal state earlier. ---
   void T44_DataEndCancelsRemaining()
     {
      datetime t0 = MakeTime(2026,1,6,15,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300,  1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300,  2);
      GZ_Swing low2  = MakeSwing(GZ_SWING_LOW,  95.0,  t0+8*300, t0+10*300, 3);

      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int iHigh1=-1; int iLow1=-1; int iLow2=-1;
      legEngine.Update(low1,0.0,false,iLow1);
      legEngine.Update(high1,0.0,false,iHigh1); // setup0: BULLISH - stays open until data end
      legEngine.Update(low2,0.0,false,iLow2);   // setup1: BEARISH - pre-cancelled below

      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      int s0 = sm.OnLegCreated(legEngine.GetLeg(iHigh1));
      int s1 = sm.OnLegCreated(legEngine.GetLeg(iLow2));

      // Pre-cancel setup1 only, via the reserved invalid-data hook, so this
      // test can prove OnDataEnd both (a) cancels a setup that is genuinely
      // still open and (b) never overwrites one that already has a terminal
      // reason.
      GZ_Setup setup1Before = sm.GetSetup(s1);
      datetime invalidTime = t0+9*300;
      sm.CancelForInvalidData(setup1Before.id, invalidTime);

      datetime dataEndTime = t0+20*300;
      sm.OnDataEnd(dataEndTime);

      GZ_Setup final0 = sm.GetSetup(s0);
      GZ_Setup final1 = sm.GetSetup(s1);

      bool ok = (final0.state==GZ_SETUP_CANCELLED) && (final0.cancel_reason==GZ_CANCEL_DATA_END) && (final0.terminal_time==dataEndTime) &&
                (final1.state==GZ_SETUP_CANCELLED) && (final1.cancel_reason==GZ_CANCEL_INVALID_DATA) && (final1.terminal_time==invalidTime);
      AddResult("T44", ok, StringFormat("setup0(was open)=%s/%s setup1(pre-cancelled, must stay unchanged)=%s/%s",
                final0.StateToString(), final0.CancelReasonToString(), final1.StateToString(), final1.CancelReasonToString()));
     }

   //--- T45: Determinism - two identical Leg+Break+Setup runs over the same
   //--- swing/bar sequence produce identical resulting setups. --------------
   void T45_SetupDeterminism()
     {
      datetime t0 = MakeTime(2026,1,6,16,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);
      MqlRates breakBar = MakeBar(t0+8*300, 109,112,108,111);
      MqlRates touchBar = MakeBar(t0+9*300, 98,100,95,99);

      GZ_BreakConfig cfg; cfg.Default();

      CGZLegEngine legA(m_logger); legA.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brkA(m_logger); brkA.Configure(cfg);
      CGZSetupStateMachine smA(m_logger); smA.Init(0.30,0.90);
      int a1=-1; legA.Update(low1,0.0,false,a1);
      int a2=-1; legA.Update(high1,0.0,false,a2);
      int saA = smA.OnLegCreated(legA.GetLeg(a2));
      legA.UpdateBar(breakBar); GZ_Leg lA = legA.GetLeg(a2); brkA.OnBar(breakBar); brkA.CheckBreak(lA,breakBar); legA.SetLeg(a2,lA);
      smA.OnLegBroken(lA);
      smA.OnBar(touchBar, true, false);
      smA.OnDataEnd(touchBar.time);
      GZ_Setup finalA = smA.GetSetup(saA);

      CGZLegEngine legB(m_logger); legB.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brkB(m_logger); brkB.Configure(cfg);
      CGZSetupStateMachine smB(m_logger); smB.Init(0.30,0.90);
      int b1=-1; legB.Update(low1,0.0,false,b1);
      int b2=-1; legB.Update(high1,0.0,false,b2);
      int saB = smB.OnLegCreated(legB.GetLeg(b2));
      legB.UpdateBar(breakBar); GZ_Leg lB = legB.GetLeg(b2); brkB.OnBar(breakBar); brkB.CheckBreak(lB,breakBar); legB.SetLeg(b2,lB);
      smB.OnLegBroken(lB);
      smB.OnBar(touchBar, true, false);
      smB.OnDataEnd(touchBar.time);
      GZ_Setup finalB = smB.GetSetup(saB);

      bool ok = (finalA.state==finalB.state) &&
                (MathAbs(finalA.zone_min_price-finalB.zone_min_price)<0.00001) &&
                (MathAbs(finalA.zone_max_price-finalB.zone_max_price)<0.00001) &&
                (finalA.locked_time==finalB.locked_time) &&
                (finalA.waiting_entry_time==finalB.waiting_entry_time);
      AddResult("T45", ok, StringFormat("stateA=%s stateB=%s", finalA.StateToString(), finalB.StateToString()));
     }

   //--- helper: build a CGZSetupStateMachine with exactly one setup already
   //--- at WAITING_ENTRY, replaying the same fixture as T39/T40 (leg
   //--- origin=90 target=110, break bar drives extreme to 112, zone=
   //--- [92.2,105.4] at ratios [0.30,0.90], WAITING_ENTRY set by a touch
   //--- bar whose range [95,100] sits inside that zone). At the default
   //--- entry_fib_ratio=0.618 the entry level price is 112-0.618*22=98.404.
   //--- Returns the setup id; `out_waiting_time` is the touch bar's time.
   long BuildWaitingEntryFixture(CGZSetupStateMachine &sm, datetime t0, datetime &out_waiting_time)
     {
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);

      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int i1=-1; legEngine.Update(low1,0.0,false,i1);
      int i2=-1; legEngine.Update(high1,0.0,false,i2);

      sm.Init(0.30,0.90);
      int si = sm.OnLegCreated(legEngine.GetLeg(i2));

      GZ_BreakConfig cfg; cfg.Default();
      CGZBreakEngine breakEngine(m_logger); breakEngine.Configure(cfg);
      MqlRates breakBar = MakeBar(t0+8*300, 109,112,108,111);
      legEngine.UpdateBar(breakBar);
      GZ_Leg legAfter = legEngine.GetLeg(i2);
      breakEngine.OnBar(breakBar);
      breakEngine.CheckBreak(legAfter, breakBar);
      legEngine.SetLeg(i2, legAfter);
      sm.OnLegBroken(legAfter);

      MqlRates touchBar = MakeBar(t0+9*300, 98,100,95,99);
      sm.OnBar(touchBar, true, false);

      out_waiting_time = touchBar.time;
      return sm.GetSetup(si).id;
     }

   //--- T46: TOUCH baseline - fires the instant an M1 bar penetrates the
   //--- entry level (penetration=0 -> exact touch suffices), fills at the
   //--- actual observed price (bar.low for a BULLISH setup). ----------------
   void T46_EntryTouchTriggersAndFills()
     {
      datetime t0 = MakeTime(2026,1,7,9,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime;
      long setupId = BuildWaitingEntryFixture(sm, t0, waitTime);

      GZ_EntryConfig cfg; cfg.Default(); // TOUCH, ratio=0.618, penetration=0
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);

      MqlRates m1bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2);
      entryEngine.OnBar(sm, m1bar, true, 0.0, false);

      GZ_Setup s = sm.GetSetup(0);
      double expectedEntryLevel = 98.404; // extreme=112, origin=90, ratio=0.618
      bool ok = (s.state==GZ_SETUP_ENTERED) && (s.terminal_time==m1bar.time) && (entryEngine.TradeCount()==1);
      if(ok)
        {
         GZ_Trade tr = entryEngine.GetTrade(0);
         ok = (tr.setup_id==setupId) && (MathAbs(tr.entry_price-98.0)<0.0001) &&
              (tr.direction==GZ_LEG_BULLISH) && (MathAbs(tr.fib_level-0.618)<0.0001) &&
              (tr.entry_model==GZ_ENTRY_TOUCH) && (MathAbs(tr.slippage_assumption-(expectedEntryLevel-98.0))<0.001);
        }
      AddResult("T46", ok, StringFormat("state=%s trades=%d", s.StateToString(), entryEngine.TradeCount()));
     }

   //--- T47: LIMIT fills exactly at the configured entry level (zero
   //--- slippage by construction); TOUCH fills at the actual touched price
   //--- (non-zero slippage) - same bar, same fixture, two entry models. -----
   void T47_LimitFillsExactlyAtLevelNoSlippage()
     {
      datetime t0 = MakeTime(2026,1,7,10,0);
      CGZSetupStateMachine smTouch(m_logger); datetime wtT; BuildWaitingEntryFixture(smTouch, t0, wtT);
      CGZSetupStateMachine smLimit(m_logger); datetime wtL; BuildWaitingEntryFixture(smLimit, t0+100000, wtL);

      GZ_EntryConfig cfgTouch; cfgTouch.Default(); cfgTouch.model=GZ_ENTRY_TOUCH;
      GZ_EntryConfig cfgLimit; cfgLimit.Default(); cfgLimit.model=GZ_ENTRY_LIMIT;
      CGZEntryEngine eTouch(m_logger); eTouch.Init(cfgTouch);
      CGZEntryEngine eLimit(m_logger); eLimit.Init(cfgLimit);

      MqlRates barTouch = MakeBar(wtT+60, 99.0,99.5,98.0,98.2);
      MqlRates barLimit = MakeBar(wtL+60, 99.0,99.5,98.0,98.2);
      eTouch.OnBar(smTouch, barTouch, true, 0.0, false);
      eLimit.OnBar(smLimit, barLimit, true, 0.0, false);

      bool ok = (eTouch.TradeCount()==1) && (eLimit.TradeCount()==1);
      if(ok)
        {
         GZ_Trade trTouch = eTouch.GetTrade(0);
         GZ_Trade trLimit = eLimit.GetTrade(0);
         ok = (MathAbs(trTouch.entry_price-98.0)<0.0001) && (MathAbs(trLimit.entry_price-98.404)<0.0001) &&
              (trTouch.slippage_assumption>0.0001) && (trLimit.slippage_assumption<0.0001);
        }
      AddResult("T47", ok, "TOUCH fills at the observed price (slippage>0); LIMIT fills exactly at the entry level (slippage=0)");
     }

   //--- T48: penetration buffer (ATR-scaled) - a touch short of the required
   //--- buffer does not trigger; ATR-not-ready with a buffer requested does
   //--- not guess and does not trigger; a touch clearing the buffer triggers
   //--- and fills at the actual observed price. -----------------------------
   void T48_PenetrationBufferRequired()
     {
      datetime t0 = MakeTime(2026,1,7,11,0);
      GZ_EntryConfig cfg; cfg.Default(); cfg.penetration_atr_mult=0.05; // atr=2.0 -> buffer=0.1, threshold=98.404-0.1=98.304

      CGZSetupStateMachine smA(m_logger); datetime wtA; BuildWaitingEntryFixture(smA, t0, wtA);
      CGZEntryEngine eA(m_logger); eA.Init(cfg);
      MqlRates barA = MakeBar(wtA+60, 98.5,98.6,98.35,98.4); // low=98.35 > 98.304 -> below buffer, no entry
      eA.OnBar(smA, barA, true, 2.0, true);
      bool noEntryA = (smA.GetSetup(0).state==GZ_SETUP_WAITING_ENTRY) && (eA.TradeCount()==0);

      CGZSetupStateMachine smB(m_logger); datetime wtB; BuildWaitingEntryFixture(smB, t0+10000, wtB);
      CGZEntryEngine eB(m_logger); eB.Init(cfg);
      MqlRates barB = MakeBar(wtB+60, 91,92,90.5,91); // extreme low, but ATR not ready -> must not guess
      eB.OnBar(smB, barB, true, 0.0, false);
      bool noEntryB = (smB.GetSetup(0).state==GZ_SETUP_WAITING_ENTRY) && (eB.TradeCount()==0);

      CGZSetupStateMachine smC(m_logger); datetime wtC; BuildWaitingEntryFixture(smC, t0+20000, wtC);
      CGZEntryEngine eC(m_logger); eC.Init(cfg);
      MqlRates barC = MakeBar(wtC+60, 98.3,98.35,98.20,98.25); // low=98.20 <= 98.304 -> clears buffer
      eC.OnBar(smC, barC, true, 2.0, true);
      bool enteredC = (smC.GetSetup(0).state==GZ_SETUP_ENTERED) && (eC.TradeCount()==1) &&
                      (MathAbs(eC.GetTrade(0).entry_price-98.20)<0.0001);

      bool ok = noEntryA && noEntryB && enteredC;
      AddResult("T48", ok, StringFormat("subThreshold_blocked=%s atrNotReady_blocked=%s fullBuffer_entered=%s",
                noEntryA?"true":"false", noEntryB?"true":"false", enteredC?"true":"false"));
     }

   //--- T49: CLOSE_CONFIRMATION requires N=2 truly CONSECUTIVE M5 closes
   //--- beyond the entry level; a broken streak resets the counter. ---------
   void T49_CloseConfirmationRequiresConsecutiveCloses()
     {
      datetime t0 = MakeTime(2026,1,7,12,0);
      CGZSetupStateMachine sm(m_logger); datetime waitTime; BuildWaitingEntryFixture(sm, t0, waitTime);

      GZ_EntryConfig cfg; cfg.Default(); cfg.model=GZ_ENTRY_CLOSE_CONFIRMATION; cfg.confirmation_candles=2;
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);

      MqlRates bar1 = MakeBar(waitTime+300,  98.5,99.2,98.4,99.0); // close=99.0>=98.404 -> streak=1
      MqlRates bar2 = MakeBar(waitTime+600,  99.0,99.1,97.8,98.0); // close=98.0<98.404  -> streak resets to 0
      MqlRates bar3 = MakeBar(waitTime+900,  98.0,99.6,97.9,99.5); // close=99.5>=98.404 -> streak=1
      MqlRates bar4 = MakeBar(waitTime+1200, 99.5,99.8,99.4,99.6); // close=99.6>=98.404 -> streak=2 -> ENTER

      entryEngine.OnBar(sm, bar1, false, 0.0, false);
      bool stillWaiting1 = (sm.GetSetup(0).state==GZ_SETUP_WAITING_ENTRY) && (entryEngine.TradeCount()==0);
      entryEngine.OnBar(sm, bar2, false, 0.0, false);
      bool stillWaiting2 = (sm.GetSetup(0).state==GZ_SETUP_WAITING_ENTRY) && (entryEngine.TradeCount()==0);
      entryEngine.OnBar(sm, bar3, false, 0.0, false);
      bool stillWaiting3 = (sm.GetSetup(0).state==GZ_SETUP_WAITING_ENTRY) && (entryEngine.TradeCount()==0);
      entryEngine.OnBar(sm, bar4, false, 0.0, false);
      bool entered = (sm.GetSetup(0).state==GZ_SETUP_ENTERED) && (entryEngine.TradeCount()==1) &&
                     (MathAbs(entryEngine.GetTrade(0).entry_price-99.6)<0.0001);

      bool ok = stillWaiting1 && stillWaiting2 && stillWaiting3 && entered;
      AddResult("T49", ok, StringFormat("afterBar1=%s afterBar2(reset)=%s afterBar3=%s afterBar4(entered)=%s",
                stillWaiting1?"waiting":"?", stillWaiting2?"waiting":"?", stillWaiting3?"waiting":"?", entered?"entered":"?"));
     }

   //--- T50: M1_CONFIRMATION - identical consecutive-close logic to T49,
   //--- but driven by M1 bars (is_m1_bar=true) instead of M5. ---------------
   void T50_M1ConfirmationRequiresConsecutiveM1Closes()
     {
      datetime t0 = MakeTime(2026,1,7,13,0);
      CGZSetupStateMachine sm(m_logger); datetime waitTime; BuildWaitingEntryFixture(sm, t0, waitTime);

      GZ_EntryConfig cfg; cfg.Default(); cfg.model=GZ_ENTRY_M1_CONFIRMATION; cfg.confirmation_candles=2;
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);

      MqlRates bar1 = MakeBar(waitTime+60,  98.5,99.2,98.4,99.0); // confirms -> streak=1
      MqlRates bar2 = MakeBar(waitTime+120, 99.0,99.1,97.8,98.0); // fails    -> streak resets
      MqlRates bar3 = MakeBar(waitTime+180, 98.0,99.6,97.9,99.5); // confirms -> streak=1
      MqlRates bar4 = MakeBar(waitTime+240, 99.5,99.8,99.4,99.6); // confirms -> streak=2 -> ENTER

      entryEngine.OnBar(sm, bar1, true, 0.0, false);
      entryEngine.OnBar(sm, bar2, true, 0.0, false);
      bool stillWaiting = (sm.GetSetup(0).state==GZ_SETUP_WAITING_ENTRY) && (entryEngine.TradeCount()==0);
      entryEngine.OnBar(sm, bar3, true, 0.0, false);
      entryEngine.OnBar(sm, bar4, true, 0.0, false);
      bool entered = (sm.GetSetup(0).state==GZ_SETUP_ENTERED) && (entryEngine.TradeCount()==1) &&
                     (MathAbs(entryEngine.GetTrade(0).entry_price-99.6)<0.0001) &&
                     (entryEngine.GetTrade(0).entry_model==GZ_ENTRY_M1_CONFIRMATION);

      bool ok = stillWaiting && entered;
      AddResult("T50", ok, StringFormat("streak_reset_respected=%s entered=%s", stillWaiting?"true":"false", entered?"true":"false"));
     }

   //--- T51: a bar that fully erases the leg (price reaches the 100% origin
   //--- level) before ever being entered cancels the setup with INVALID_
   //--- PENETRATION and produces no trade. ----------------------------------
   void T51_InvalidPenetrationCancelsSetup()
     {
      datetime t0 = MakeTime(2026,1,7,14,0);
      CGZSetupStateMachine sm(m_logger); datetime waitTime; BuildWaitingEntryFixture(sm, t0, waitTime);

      GZ_EntryConfig cfg; cfg.Default();
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);

      MqlRates m1bar = MakeBar(waitTime+60, 90.5,91.0,89.5,90.0); // low=89.5 <= origin(90.0) -> fully erased
      entryEngine.OnBar(sm, m1bar, true, 0.0, false);

      GZ_Setup s = sm.GetSetup(0);
      bool ok = (s.state==GZ_SETUP_CANCELLED) && (s.cancel_reason==GZ_CANCEL_INVALID_PENETRATION) &&
                (s.terminal_time==m1bar.time) && (entryEngine.TradeCount()==0);
      AddResult("T51", ok, StringFormat("state=%s/%s trades=%d", s.StateToString(), s.CancelReasonToString(), entryEngine.TradeCount()));
     }

   //--- T52: a setup that is FIB_ACTIVE but has NOT yet reached WAITING_ENTRY
   //--- (Phase 4's M5 zone-touch gate never fired) must never be entered,
   //--- even if an M1 bar's price already crosses the entry level. ----------
   void T52_NoEntryBeforeWaitingEntryGate()
     {
      datetime t0 = MakeTime(2026,1,7,14,30);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);

      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int i1=-1; legEngine.Update(low1,0.0,false,i1);
      int i2=-1; legEngine.Update(high1,0.0,false,i2);

      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      int si = sm.OnLegCreated(legEngine.GetLeg(i2));

      GZ_BreakConfig cfg; cfg.Default();
      CGZBreakEngine breakEngine(m_logger); breakEngine.Configure(cfg);
      MqlRates breakBar = MakeBar(t0+8*300, 109,112,108,111);
      legEngine.UpdateBar(breakBar);
      GZ_Leg legAfter = legEngine.GetLeg(i2);
      breakEngine.OnBar(breakBar);
      breakEngine.CheckBreak(legAfter, breakBar);
      legEngine.SetLeg(i2, legAfter);
      sm.OnLegBroken(legAfter); // -> FIB_ACTIVE only, NO touch bar fed -> never reaches WAITING_ENTRY

      GZ_EntryConfig ecfg; ecfg.Default();
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(ecfg);

      MqlRates m1bar = MakeBar(breakBar.time+300+60, 98.5,98.6,98.0,98.2); // low=98.0 crosses the entry level
      entryEngine.OnBar(sm, m1bar, true, 0.0, false);

      GZ_Setup s = sm.GetSetup(si);
      bool ok = (s.state==GZ_SETUP_FIB_ACTIVE) && (entryEngine.TradeCount()==0);
      AddResult("T52", ok, StringFormat("state=%s trades=%d (must stay FIB_ACTIVE)", s.StateToString(), entryEngine.TradeCount()));
     }

   //--- T53: CGZTradeSimulator's M1/M5 ordering - an M1 bar temporally
   //--- inside the M5 candle that itself produces WAITING_ENTRY must NOT be
   //--- able to trigger entry from that same candle's not-yet-closed
   //--- result; the first M1 bar in the FOLLOWING M5 candle's window (after
   //--- that structure update has actually closed) correctly does. ----------
   void T53_SimulatorNoLookaheadAcrossM1M5Boundary()
     {
      datetime t0 = MakeTime(2026,1,7,15,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);
      GZ_Swing swings[]; ArrayResize(swings,2); swings[0]=low1; swings[1]=high1;

      MqlRates m5[]; ArrayResize(m5,5);
      m5[0]=MakeBar(t0+2*300,  90,90.5,89.5,90);
      m5[1]=MakeBar(t0+7*300, 109,110.5,108.5,110);
      m5[2]=MakeBar(t0+8*300, 109,112,108,111);     // break: close=111>110
      m5[3]=MakeBar(t0+9*300, 98,100,95,99);        // T: touches zone [92.2,105.4] -> WAITING_ENTRY
      m5[4]=MakeBar(t0+10*300, 99,100,98,99);       // next M5 candle (neutral)

      datetime T = t0+9*300;
      MqlRates m1[]; ArrayResize(m1,2);
      m1[0]=MakeBar(T+120,    98.5,98.6,98.0,98.2); // inside T's OWN forming candle - must NOT trigger
      m1[1]=MakeBar(T+300+60, 98.5,98.6,98.0,98.2); // inside the NEXT candle - must trigger

      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      GZ_BreakConfig bcfg; bcfg.Default();
      CGZBreakEngine breakEngine(m_logger); breakEngine.Configure(bcfg);
      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      GZ_EntryConfig ecfg; ecfg.Default();
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(ecfg);
      GZ_ExitConfig xcfg; xcfg.Default();
      CGZExitEngine exitEngine(m_logger); exitEngine.Init(xcfg);
      CGZTimeEngine timeEngine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); timeEngine.Configure(tcfg);
      CGZSessionEngine sessionEngine;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);

      CGZJournalEngine journalEngine(m_logger); journalEngine.Init();
      CGZEventLedger   ledger(m_logger);        ledger.Init();
      CGZTradeSimulator sim(m_logger);
      sim.Run(m1, m5, swings, 2, legEngine, breakEngine, sm, entryEngine, exitEngine, journalEngine, ledger, timeEngine, sessionEngine, profile, false, false);

      bool ok = (entryEngine.TradeCount()==1) && (entryEngine.GetTrade(0).entry_time==m1[1].time) &&
                (MathAbs(entryEngine.GetTrade(0).entry_price-98.0)<0.0001);
      AddResult("T53", ok, StringFormat("trades=%d (must be exactly 1, from the post-close M1 bar only)", entryEngine.TradeCount()));
     }

   //--- T54: Determinism - two independent CGZTradeSimulator runs over the
   //--- same M1/M5/swings data and configuration produce identical trades. -
   void T54_SimulatorDeterminism()
     {
      datetime t0 = MakeTime(2026,1,7,16,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);
      GZ_Swing swings[]; ArrayResize(swings,2); swings[0]=low1; swings[1]=high1;

      MqlRates m5[]; ArrayResize(m5,5);
      m5[0]=MakeBar(t0+2*300,  90,90.5,89.5,90);
      m5[1]=MakeBar(t0+7*300, 109,110.5,108.5,110);
      m5[2]=MakeBar(t0+8*300, 109,112,108,111);
      m5[3]=MakeBar(t0+9*300, 98,100,95,99);
      m5[4]=MakeBar(t0+10*300, 99,100,98,99);

      datetime T = t0+9*300;
      MqlRates m1[]; ArrayResize(m1,1);
      m1[0]=MakeBar(T+300+60, 98.5,98.6,98.0,98.2);

      GZ_TimeConfig tcfg; tcfg.Default();
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      GZ_EntryConfig ecfg; ecfg.Default();
      GZ_BreakConfig bcfg; bcfg.Default();

      CGZLegEngine legA(m_logger); legA.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brkA(m_logger); brkA.Configure(bcfg);
      CGZSetupStateMachine smA(m_logger); smA.Init(0.30,0.90);
      CGZEntryEngine entA(m_logger); entA.Init(ecfg);
      GZ_ExitConfig xcfg; xcfg.Default();
      CGZExitEngine extA(m_logger); extA.Init(xcfg);
      CGZTimeEngine timeA(m_logger); timeA.Configure(tcfg);
      CGZSessionEngine sessA;
      CGZJournalEngine journalA(m_logger); journalA.Init();
      CGZEventLedger   ledgerA(m_logger);  ledgerA.Init();
      CGZTradeSimulator simA(m_logger);
      simA.Run(m1, m5, swings, 2, legA, brkA, smA, entA, extA, journalA, ledgerA, timeA, sessA, profile, false, false);

      CGZLegEngine legB(m_logger); legB.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brkB(m_logger); brkB.Configure(bcfg);
      CGZSetupStateMachine smB(m_logger); smB.Init(0.30,0.90);
      CGZEntryEngine entB(m_logger); entB.Init(ecfg);
      CGZExitEngine extB(m_logger); extB.Init(xcfg);
      CGZTimeEngine timeB(m_logger); timeB.Configure(tcfg);
      CGZSessionEngine sessB;
      CGZJournalEngine journalB(m_logger); journalB.Init();
      CGZEventLedger   ledgerB(m_logger);  ledgerB.Init();
      CGZTradeSimulator simB(m_logger);
      simB.Run(m1, m5, swings, 2, legB, brkB, smB, entB, extB, journalB, ledgerB, timeB, sessB, profile, false, false);

      bool ok = (entA.TradeCount()==entB.TradeCount()) && (entA.TradeCount()==1);
      if(ok)
        {
         GZ_Trade a = entA.GetTrade(0);
         GZ_Trade b = entB.GetTrade(0);
         ok = (a.entry_time==b.entry_time) && (MathAbs(a.entry_price-b.entry_price)<0.00001) &&
              (a.setup_id==b.setup_id) && (MathAbs(a.fib_level-b.fib_level)<0.00001) &&
              (MathAbs(a.slippage_assumption-b.slippage_assumption)<0.00001);
        }
      AddResult("T54", ok, StringFormat("tradesA=%d tradesB=%d", entA.TradeCount(), entB.TradeCount()));
     }

   //--- helper: build a GZ_Trade directly (Phase 6 exit tests don't need
   //--- to run the full Setup/Entry pipeline - that is already covered by
   //--- T38-T54; here we only need well-formed GZ_Trade/GZ_Leg inputs). ---
   GZ_Trade MakeTrade(long id, long setup_id, ENUM_GZ_LEG_DIR dir, double entry_price, datetime t, ENUM_GZ_ENTRY_MODEL model=GZ_ENTRY_TOUCH)
     {
      GZ_Trade tr; tr.Clear();
      tr.id = id; tr.setup_id = setup_id; tr.direction = dir; tr.entry_price = entry_price;
      tr.entry_time = t; tr.entry_model = model; tr.fib_level = 0.618;
      return tr;
     }

   GZ_Leg MakeLegForExit(ENUM_GZ_LEG_DIR dir, double origin_price)
     {
      GZ_Leg leg; leg.Clear();
      leg.id = 1; leg.direction = dir; leg.origin_swing.price = origin_price;
      return leg;
     }

   //--- T55: STRUCTURE SL (baseline, zero buffer) = leg origin price exactly;
   //--- TP computed at the configured R-multiple, for BOTH directions. ------
   void T55_ExitStructureSLAndTP()
     {
      GZ_ExitConfig cfg; cfg.Default(); // STRUCTURE, buffer=0, tp=2.0R

      CGZExitEngine eBull(m_logger); eBull.Init(cfg);
      GZ_Trade trBull = MakeTrade(1, 1, GZ_LEG_BULLISH, 98.0, MakeTime(2026,1,8,9,0));
      GZ_Leg legBull = MakeLegForExit(GZ_LEG_BULLISH, 90.0);
      eBull.OnTradeEntered(trBull, legBull, 0.0, false);
      GZ_TradeExit exBull = eBull.GetExit(0);
      // sl=90, initial_risk=8, tp=98+2*8=114
      bool okBull = (MathAbs(exBull.sl_price-90.0)<0.0001) && (MathAbs(exBull.initial_risk-8.0)<0.0001) &&
                    (MathAbs(exBull.tp_price-114.0)<0.0001) && (exBull.sl_model_used==GZ_SL_STRUCTURE);

      CGZExitEngine eBear(m_logger); eBear.Init(cfg);
      GZ_Trade trBear = MakeTrade(2, 2, GZ_LEG_BEARISH, 100.0, MakeTime(2026,1,8,9,0));
      GZ_Leg legBear = MakeLegForExit(GZ_LEG_BEARISH, 110.0);
      eBear.OnTradeEntered(trBear, legBear, 0.0, false);
      GZ_TradeExit exBear = eBear.GetExit(0);
      // sl=110, initial_risk=10, tp=100-2*10=80
      bool okBear = (MathAbs(exBear.sl_price-110.0)<0.0001) && (MathAbs(exBear.initial_risk-10.0)<0.0001) &&
                    (MathAbs(exBear.tp_price-80.0)<0.0001);

      bool ok = okBull && okBear;
      AddResult("T55", ok, StringFormat("bull sl=%.2f tp=%.2f | bear sl=%.2f tp=%.2f",
                exBull.sl_price, exBull.tp_price, exBear.sl_price, exBear.tp_price));
     }

   //--- T56: ATR SL model uses entry price +/- atr_mult*ATR when ATR is
   //--- ready; falls back to STRUCTURE/zero-buffer (documented, not a
   //--- guess) when it is not. ------------------------------------------------
   void T56_ExitAtrSLWithFallback()
     {
      GZ_ExitConfig cfg; cfg.Default(); cfg.sl_model = GZ_SL_ATR; cfg.sl_atr_mult = 1.5;

      CGZExitEngine eReady(m_logger); eReady.Init(cfg);
      GZ_Trade tr1 = MakeTrade(1, 1, GZ_LEG_BULLISH, 100.0, MakeTime(2026,1,8,10,0));
      GZ_Leg leg1 = MakeLegForExit(GZ_LEG_BULLISH, 90.0);
      eReady.OnTradeEntered(tr1, leg1, 2.0, true); // atr=2.0 -> sl=100-1.5*2=97
      GZ_TradeExit ex1 = eReady.GetExit(0);
      bool okReady = (ex1.sl_model_used==GZ_SL_ATR) && (MathAbs(ex1.sl_price-97.0)<0.0001);

      CGZExitEngine eFallback(m_logger); eFallback.Init(cfg);
      GZ_Trade tr2 = MakeTrade(2, 2, GZ_LEG_BULLISH, 100.0, MakeTime(2026,1,8,10,0));
      GZ_Leg leg2 = MakeLegForExit(GZ_LEG_BULLISH, 90.0);
      eFallback.OnTradeEntered(tr2, leg2, 0.0, false); // ATR not ready -> fallback
      GZ_TradeExit ex2 = eFallback.GetExit(0);
      bool okFallback = (ex2.sl_model_used==GZ_SL_STRUCTURE) && (MathAbs(ex2.sl_price-90.0)<0.0001);

      bool ok = okReady && okFallback;
      AddResult("T56", ok, StringFormat("atr_ready_sl=%.2f fallback_sl=%.2f (fallback must equal leg origin=90.00)",
                ex1.sl_price, ex2.sl_price));
     }

   //--- T57: price reaches TP before SL - trade closes TP_HIT at the TP
   //--- price, realized_r matches the configured R-multiple. -----------------
   void T57_TpHitExit()
     {
      GZ_ExitConfig cfg; cfg.Default(); // tp=2.0R
      CGZExitEngine exitEngine(m_logger); exitEngine.Init(cfg);
      GZ_Trade tr = MakeTrade(1, 1, GZ_LEG_BULLISH, 98.0, MakeTime(2026,1,8,11,0));
      GZ_Leg leg = MakeLegForExit(GZ_LEG_BULLISH, 90.0); // sl=90, tp=114
      exitEngine.OnTradeEntered(tr, leg, 0.0, false);

      MqlRates barNoTouch = MakeBar(MakeTime(2026,1,8,11,1), 99,101,97,100);
      exitEngine.OnBar(barNoTouch, true, false);
      bool stillOpen = (exitEngine.GetExit(0).is_open);

      MqlRates barTp = MakeBar(MakeTime(2026,1,8,11,2), 110,115,109,112); // high=115>=114
      exitEngine.OnBar(barTp, true, false);
      GZ_TradeExit ex = exitEngine.GetExit(0);

      bool ok = stillOpen && (!ex.is_open) && (ex.exit_reason==GZ_EXIT_TP_HIT) &&
                (MathAbs(ex.exit_price-114.0)<0.0001) && (MathAbs(ex.realized_r-2.0)<0.0001);
      AddResult("T57", ok, StringFormat("reason=%s exit_price=%.2f R=%.3f", ex.ExitReasonToString(), ex.exit_price, ex.realized_r));
     }

   //--- T58: price reaches SL - trade closes SL_HIT at the SL price,
   //--- realized_r is exactly -1.0 (one full unit of initial risk lost). ----
   void T58_SlHitExit()
     {
      GZ_ExitConfig cfg; cfg.Default();
      CGZExitEngine exitEngine(m_logger); exitEngine.Init(cfg);
      GZ_Trade tr = MakeTrade(1, 1, GZ_LEG_BULLISH, 98.0, MakeTime(2026,1,8,12,0));
      GZ_Leg leg = MakeLegForExit(GZ_LEG_BULLISH, 90.0); // sl=90
      exitEngine.OnTradeEntered(tr, leg, 0.0, false);

      MqlRates barSl = MakeBar(MakeTime(2026,1,8,12,1), 92,93,89,90.5); // low=89<=90
      exitEngine.OnBar(barSl, true, false);
      GZ_TradeExit ex = exitEngine.GetExit(0);

      bool ok = (!ex.is_open) && (ex.exit_reason==GZ_EXIT_SL_HIT) &&
                (MathAbs(ex.exit_price-90.0)<0.0001) && (MathAbs(ex.realized_r-(-1.0))<0.0001);
      AddResult("T58", ok, StringFormat("reason=%s exit_price=%.2f R=%.3f", ex.ExitReasonToString(), ex.exit_price, ex.realized_r));
     }

   //--- T59: break-even arms once price moves be_trigger_r in favor, moving
   //--- the active stop to entry; a later bar returning to that stop closes
   //--- the trade as BREAK_EVEN (not SL_HIT), realized_r ~ 0. -----------------
   void T59_BreakEvenArmThenExit()
     {
      GZ_ExitConfig cfg; cfg.Default(); cfg.be_trigger_r = 1.0; cfg.be_level_mode = GZ_BE_LEVEL_ENTRY;
      CGZExitEngine exitEngine(m_logger); exitEngine.Init(cfg);
      GZ_Trade tr = MakeTrade(1, 1, GZ_LEG_BULLISH, 98.0, MakeTime(2026,1,8,13,0));
      GZ_Leg leg = MakeLegForExit(GZ_LEG_BULLISH, 90.0); // sl=90, initial_risk=8, BE trigger price=98+8=106
      exitEngine.OnTradeEntered(tr, leg, 0.0, false);

      MqlRates barArm = MakeBar(MakeTime(2026,1,8,13,1), 100,107,99,105); // high=107>=106 -> arms BE
      exitEngine.OnBar(barArm, true, false);
      GZ_TradeExit afterArm = exitEngine.GetExit(0);
      bool armed = afterArm.is_open && afterArm.be_triggered && (MathAbs(afterArm.be_new_sl_price-98.0)<0.0001) &&
                   (MathAbs(afterArm.sl_price-98.0)<0.0001);

      MqlRates barReturn = MakeBar(MakeTime(2026,1,8,13,2), 102,103,97,98); // low=97<=98(new sl)
      exitEngine.OnBar(barReturn, true, false);
      GZ_TradeExit ex = exitEngine.GetExit(0);
      bool exited = (!ex.is_open) && (ex.exit_reason==GZ_EXIT_BREAK_EVEN) && (MathAbs(ex.exit_price-98.0)<0.0001) &&
                    (MathAbs(ex.realized_r)<0.0001);

      bool ok = armed && exited;
      AddResult("T59", ok, StringFormat("armed=%s reason=%s R=%.3f", armed?"true":"false", ex.ExitReasonToString(), ex.realized_r));
     }

   //--- T60: a single bar's range touches BOTH SL and TP - intrabar_conflict
   //--- is recorded regardless of policy, and the configured policy actually
   //--- changes which outcome wins (SL_FIRST vs TP_FIRST, same bar). ---------
   void T60_IntrabarConflictPolicy()
     {
      MqlRates wideBar = MakeBar(MakeTime(2026,1,8,14,1), 100,115,89,105); // low=89<=sl(90), high=115>=tp(114)

      GZ_ExitConfig cfgSlFirst; cfgSlFirst.Default(); cfgSlFirst.intrabar_conflict_policy = GZ_CONFLICT_SL_FIRST;
      CGZExitEngine eSl(m_logger); eSl.Init(cfgSlFirst);
      GZ_Trade tr1 = MakeTrade(1, 1, GZ_LEG_BULLISH, 98.0, MakeTime(2026,1,8,14,0));
      GZ_Leg leg1 = MakeLegForExit(GZ_LEG_BULLISH, 90.0);
      eSl.OnTradeEntered(tr1, leg1, 0.0, false);
      eSl.OnBar(wideBar, true, false);
      GZ_TradeExit exSl = eSl.GetExit(0);

      GZ_ExitConfig cfgTpFirst; cfgTpFirst.Default(); cfgTpFirst.intrabar_conflict_policy = GZ_CONFLICT_TP_FIRST;
      CGZExitEngine eTp(m_logger); eTp.Init(cfgTpFirst);
      GZ_Trade tr2 = MakeTrade(2, 2, GZ_LEG_BULLISH, 98.0, MakeTime(2026,1,8,14,0));
      GZ_Leg leg2 = MakeLegForExit(GZ_LEG_BULLISH, 90.0);
      eTp.OnTradeEntered(tr2, leg2, 0.0, false);
      eTp.OnBar(wideBar, true, false);
      GZ_TradeExit exTp = eTp.GetExit(0);

      bool ok = exSl.intrabar_conflict && exTp.intrabar_conflict &&
                (exSl.exit_reason==GZ_EXIT_SL_HIT) && (MathAbs(exSl.exit_price-90.0)<0.0001) &&
                (exTp.exit_reason==GZ_EXIT_TP_HIT) && (MathAbs(exTp.exit_price-114.0)<0.0001);
      AddResult("T60", ok, StringFormat("SL_FIRST->%s@%.2f  TP_FIRST->%s@%.2f (both flagged intrabar_conflict)",
                exSl.ExitReasonToString(), exSl.exit_price, exTp.ExitReasonToString(), exTp.exit_price));
     }

   //--- T61: force_session_exit closes an open trade at the bar's close the
   //--- instant price moves outside the session window (and only then -
   //--- SL/TP still take priority when they also apply, see header). --------
   void T61_SessionExit()
     {
      GZ_ExitConfig cfg; cfg.Default();
      CGZExitEngine exitEngine(m_logger); exitEngine.Init(cfg);
      GZ_Trade tr = MakeTrade(1, 1, GZ_LEG_BULLISH, 98.0, MakeTime(2026,1,8,15,0));
      GZ_Leg leg = MakeLegForExit(GZ_LEG_BULLISH, 90.0); // sl=90, tp=114
      exitEngine.OnTradeEntered(tr, leg, 0.0, false);

      MqlRates bar = MakeBar(MakeTime(2026,1,8,15,1), 99,100,98,99); // touches neither sl nor tp
      exitEngine.OnBar(bar, false, true); // outside session, force_session_exit=true
      GZ_TradeExit ex = exitEngine.GetExit(0);

      bool ok = (!ex.is_open) && (ex.exit_reason==GZ_EXIT_SESSION_EXIT) && (MathAbs(ex.exit_price-99.0)<0.0001);
      AddResult("T61", ok, StringFormat("reason=%s exit_price=%.2f", ex.ExitReasonToString(), ex.exit_price));
     }

   //--- T62: a trade still open when the data range ends is force-closed at
   //--- the given last-known price with reason DATA_END. --------------------
   void T62_DataEndForceClose()
     {
      GZ_ExitConfig cfg; cfg.Default();
      CGZExitEngine exitEngine(m_logger); exitEngine.Init(cfg);
      GZ_Trade tr = MakeTrade(1, 1, GZ_LEG_BULLISH, 98.0, MakeTime(2026,1,8,16,0));
      GZ_Leg leg = MakeLegForExit(GZ_LEG_BULLISH, 90.0);
      exitEngine.OnTradeEntered(tr, leg, 0.0, false);

      datetime endTime = MakeTime(2026,1,8,18,0);
      exitEngine.OnDataEnd(endTime, 101.5);
      GZ_TradeExit ex = exitEngine.GetExit(0);

      bool ok = (!ex.is_open) && (ex.exit_reason==GZ_EXIT_DATA_END) && (ex.exit_time==endTime) &&
                (MathAbs(ex.exit_price-101.5)<0.0001);
      AddResult("T62", ok, StringFormat("reason=%s exit_price=%.2f", ex.ExitReasonToString(), ex.exit_price));
     }

   //--- T63: realized_r sign convention is correct for BOTH directions on
   //--- BOTH outcomes (TP_HIT positive, SL_HIT negative) - not just the
   //--- BULLISH case T57/T58 already covered. --------------------------------
   void T63_InitialRiskAndRealizedRSign()
     {
      GZ_ExitConfig cfg; cfg.Default(); // tp=2.0R

      CGZExitEngine eTp(m_logger); eTp.Init(cfg);
      GZ_Trade trTp = MakeTrade(1, 1, GZ_LEG_BEARISH, 100.0, MakeTime(2026,1,8,17,0));
      GZ_Leg legTp = MakeLegForExit(GZ_LEG_BEARISH, 110.0); // sl=110, initial_risk=10, tp=80
      eTp.OnTradeEntered(trTp, legTp, 0.0, false);
      MqlRates barTp = MakeBar(MakeTime(2026,1,8,17,1), 85,86,79,80); // low=79<=80
      eTp.OnBar(barTp, true, false);
      GZ_TradeExit exTp = eTp.GetExit(0);
      bool okTp = (exTp.exit_reason==GZ_EXIT_TP_HIT) && (MathAbs(exTp.realized_r-2.0)<0.0001);

      CGZExitEngine eSl(m_logger); eSl.Init(cfg);
      GZ_Trade trSl = MakeTrade(2, 2, GZ_LEG_BEARISH, 100.0, MakeTime(2026,1,8,17,0));
      GZ_Leg legSl = MakeLegForExit(GZ_LEG_BEARISH, 110.0);
      eSl.OnTradeEntered(trSl, legSl, 0.0, false);
      MqlRates barSl = MakeBar(MakeTime(2026,1,8,17,1), 105,111,104,110); // high=111>=110
      eSl.OnBar(barSl, true, false);
      GZ_TradeExit exSl = eSl.GetExit(0);
      bool okSl = (exSl.exit_reason==GZ_EXIT_SL_HIT) && (MathAbs(exSl.realized_r-(-1.0))<0.0001);

      bool ok = okTp && okSl;
      AddResult("T63", ok, StringFormat("BEARISH TP_HIT R=%.3f  BEARISH SL_HIT R=%.3f", exTp.realized_r, exSl.realized_r));
     }

   //--- T64: full-pipeline determinism through the Phase 6-updated
   //--- CGZTradeSimulator - two independent runs over identical M1/M5/
   //--- swings data and configuration produce identical trades AND
   //--- identical exits. ------------------------------------------------------
   void T64_ExitDeterminism()
     {
      datetime t0 = MakeTime(2026,1,8,18,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);
      GZ_Swing swings[]; ArrayResize(swings,2); swings[0]=low1; swings[1]=high1;

      MqlRates m5[]; ArrayResize(m5,6);
      m5[0]=MakeBar(t0+2*300,  90,90.5,89.5,90);
      m5[1]=MakeBar(t0+7*300, 109,110.5,108.5,110);
      m5[2]=MakeBar(t0+8*300, 109,112,108,111);     // break: close=111>110
      m5[3]=MakeBar(t0+9*300, 98,100,95,99);        // T: touches zone [92.2,105.4] -> WAITING_ENTRY
      m5[4]=MakeBar(t0+10*300, 99,100,98,99);       // next M5 candle (neutral)
      m5[5]=MakeBar(t0+11*300, 99,100,98,99);       // trailing neutral candle

      datetime T = t0+9*300;
      MqlRates m1[]; ArrayResize(m1,2);
      m1[0]=MakeBar(T+300+60,  98.5,98.6,98.0,98.2); // triggers TOUCH entry, low=98.0<=entry(98.404)
      m1[1]=MakeBar(T+600+60, 115.0,116.0,114.5,115.5); // well past TP (leg origin=90 -> sl=90, tp per config)

      GZ_TimeConfig tcfg; tcfg.Default();
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      GZ_EntryConfig ecfg; ecfg.Default();
      GZ_BreakConfig bcfg; bcfg.Default();
      GZ_ExitConfig xcfg; xcfg.Default(); // sl=structure(origin=90), tp=2.0R

      CGZLegEngine legA(m_logger); legA.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brkA(m_logger); brkA.Configure(bcfg);
      CGZSetupStateMachine smA(m_logger); smA.Init(0.30,0.90);
      CGZEntryEngine entA(m_logger); entA.Init(ecfg);
      CGZExitEngine extA(m_logger); extA.Init(xcfg);
      CGZTimeEngine timeA(m_logger); timeA.Configure(tcfg);
      CGZSessionEngine sessA;
      CGZJournalEngine journalA(m_logger); journalA.Init();
      CGZEventLedger   ledgerA(m_logger);  ledgerA.Init();
      CGZTradeSimulator simA(m_logger);
      simA.Run(m1, m5, swings, 2, legA, brkA, smA, entA, extA, journalA, ledgerA, timeA, sessA, profile, false, false);

      CGZLegEngine legB(m_logger); legB.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brkB(m_logger); brkB.Configure(bcfg);
      CGZSetupStateMachine smB(m_logger); smB.Init(0.30,0.90);
      CGZEntryEngine entB(m_logger); entB.Init(ecfg);
      CGZExitEngine extB(m_logger); extB.Init(xcfg);
      CGZTimeEngine timeB(m_logger); timeB.Configure(tcfg);
      CGZSessionEngine sessB;
      CGZJournalEngine journalB(m_logger); journalB.Init();
      CGZEventLedger   ledgerB(m_logger);  ledgerB.Init();
      CGZTradeSimulator simB(m_logger);
      simB.Run(m1, m5, swings, 2, legB, brkB, smB, entB, extB, journalB, ledgerB, timeB, sessB, profile, false, false);

      bool ok = (extA.ExitCount()==extB.ExitCount()) && (extA.ExitCount()==1) && (entA.TradeCount()==entB.TradeCount());
      if(ok)
        {
         GZ_TradeExit a = extA.GetExit(0);
         GZ_TradeExit b = extB.GetExit(0);
         ok = (a.exit_time==b.exit_time) && (a.exit_reason==b.exit_reason) &&
              (MathAbs(a.exit_price-b.exit_price)<0.00001) && (MathAbs(a.realized_r-b.realized_r)<0.00001) &&
              (MathAbs(a.sl_price-b.sl_price)<0.00001) && (MathAbs(a.tp_price-b.tp_price)<0.00001);
        }
      // Also verify the EXITED propagation (GZ_SetupStateMachine::MarkExited(),
      // wired up via CGZTradeSimulator's final pass - see its Run() header).
      if(ok)
        {
         int n = smA.SetupCount();
         bool foundExited = false;
         for(int i=0;i<n;i++)
            if(smA.GetSetup(i).id==extA.GetExit(0).setup_id && smA.GetSetup(i).state==GZ_SETUP_EXITED)
               foundExited = true;
         ok = foundExited;
        }
      AddResult("T64", ok, StringFormat("exitsA=%d exitsB=%d", extA.ExitCount(), extB.ExitCount()));
     }

   //=====================================================================
   //  PHASE 7: MAE/MFE + R-Path + Event Ledger  (T65-T74)
   //=====================================================================

   //--- T65: MAE/MFE tracking for BOTH directions - running best/worst
   //--- excursion in R, updated only when a bar actually improves it. ------
   void T65_JournalMaeMfeTracking()
     {
      CGZJournalEngine jBull(m_logger); jBull.Init();
      GZ_Trade trBull = MakeTrade(1, 1, GZ_LEG_BULLISH, 100.0, MakeTime(2026,1,9,9,0));
      jBull.OnTradeEntered(trBull, 5.0); // initial_risk=5 (sl=95)

      jBull.OnBar(MakeBar(MakeTime(2026,1,9,9,1), 100,103,99,102));  // fav=3(0.6R) adv=1(0.2R) - both new extremes
      jBull.OnBar(MakeBar(MakeTime(2026,1,9,9,2), 102,104,94,95));   // fav=4(0.8R) adv=6(1.2R) - both new extremes
      jBull.OnBar(MakeBar(MakeTime(2026,1,9,9,3), 96,108,96,107));   // fav=8(1.6R) new MFE; adv=4(0.8R) NOT a new MAE (1.2R stands)

      GZ_TradeJournal jb = jBull.GetJournal(0);
      bool okBull = (MathAbs(jb.mae_r-1.2)<0.0001) && (jb.time_to_mae==MakeTime(2026,1,9,9,2)) &&
                    (MathAbs(jb.mfe_r-1.6)<0.0001) && (jb.time_to_mfe==MakeTime(2026,1,9,9,3));

      CGZJournalEngine jBear(m_logger); jBear.Init();
      GZ_Trade trBear = MakeTrade(2, 2, GZ_LEG_BEARISH, 100.0, MakeTime(2026,1,9,10,0));
      jBear.OnTradeEntered(trBear, 5.0); // initial_risk=5 (sl=105)

      jBear.OnBar(MakeBar(MakeTime(2026,1,9,10,1), 100,101,97,98));  // fav=3(0.6R) adv=1(0.2R) - both new extremes
      jBear.OnBar(MakeBar(MakeTime(2026,1,9,10,2), 98,106,96,97));   // fav=4(0.8R) adv=6(1.2R) - both new extremes
      jBear.OnBar(MakeBar(MakeTime(2026,1,9,10,3), 97,97,92,93));    // fav=8(1.6R) new MFE; adv=-3 NOT a new MAE (1.2R stands)

      GZ_TradeJournal je = jBear.GetJournal(0);
      bool okBear = (MathAbs(je.mae_r-1.2)<0.0001) && (je.time_to_mae==MakeTime(2026,1,9,10,2)) &&
                    (MathAbs(je.mfe_r-1.6)<0.0001) && (je.time_to_mfe==MakeTime(2026,1,9,10,3));

      bool ok = okBull && okBear;
      AddResult("T65", ok, StringFormat("bull mae=%.2fR mfe=%.2fR | bear mae=%.2fR mfe=%.2fR",
                jb.mae_r, jb.mfe_r, je.mae_r, je.mfe_r));
     }

   //--- T66: Reach Matrix - multiple levels crossed on one bar are all
   //--- marked with THAT bar's time; a level already reached keeps its
   //--- original reach_time on later bars (first-time-only). --------------
   void T66_JournalReachMatrixTiming()
     {
      CGZJournalEngine j(m_logger); j.Init();
      GZ_Trade tr = MakeTrade(1, 1, GZ_LEG_BULLISH, 100.0, MakeTime(2026,1,9,11,0));
      j.OnTradeEntered(tr, 10.0); // sl=90, 1R=10

      datetime t1 = MakeTime(2026,1,9,11,1);
      j.OnBar(MakeBar(t1, 100,115,99,110)); // fav=15 -> 1.5R: 0.5,1.0,1.5 all reached at t1

      GZ_TradeJournal after1 = j.GetJournal(0);
      bool step1 = after1.reach_hit[0] && after1.reach_hit[1] && after1.reach_hit[2] && !after1.reach_hit[3] &&
                   (after1.reach_time[0]==t1) && (after1.reach_time[1]==t1) && (after1.reach_time[2]==t1);

      datetime t2 = MakeTime(2026,1,9,11,2);
      j.OnBar(MakeBar(t2, 110,125,109,120)); // fav=25 -> 2.5R: 2.0,2.5 newly reached at t2

      GZ_TradeJournal after2 = j.GetJournal(0);
      bool step2 = after2.reach_hit[3] && after2.reach_hit[4] && (after2.reach_time[3]==t2) && (after2.reach_time[4]==t2) &&
                   (after2.reach_time[0]==t1) && (after2.reach_time[1]==t1) && (after2.reach_time[2]==t1); // unchanged

      bool ok = step1 && step2;
      AddResult("T66", ok, StringFormat("highest_reach=%.2fR (expect 2.50)", after2.HighestReachHit()));
     }

   //--- T67: Once OnTradeClosed() has been called, further OnBar() calls
   //--- must not change MAE/MFE/Reach Matrix (no leakage past the exit). --
   void T67_JournalStopsAfterClose()
     {
      CGZJournalEngine j(m_logger); j.Init();
      GZ_Trade tr = MakeTrade(1, 1, GZ_LEG_BULLISH, 100.0, MakeTime(2026,1,9,12,0));
      j.OnTradeEntered(tr, 5.0);
      j.OnBar(MakeBar(MakeTime(2026,1,9,12,1), 100,103,99,102)); // mfe=0.6R

      j.OnTradeClosed(1, MakeTime(2026,1,9,12,2), 102.0, 0.4);
      GZ_TradeJournal beforeExtra = j.GetJournal(0);

      // A huge move AFTER close must not move mae/mfe, and a second
      // OnTradeClosed() with different values must not overwrite either.
      j.OnBar(MakeBar(MakeTime(2026,1,9,12,3), 102,150,50,140));
      j.OnTradeClosed(1, MakeTime(2026,1,9,12,4), 999.0, 99.0);
      GZ_TradeJournal afterExtra = j.GetJournal(0);

      bool ok = (!afterExtra.is_open) &&
                (MathAbs(afterExtra.mfe_r-beforeExtra.mfe_r)<0.0001) &&
                (MathAbs(afterExtra.mae_r-beforeExtra.mae_r)<0.0001) &&
                (afterExtra.exit_time==beforeExtra.exit_time) &&
                (MathAbs(afterExtra.exit_price-beforeExtra.exit_price)<0.0001) &&
                (MathAbs(afterExtra.final_r-beforeExtra.final_r)<0.0001);
      AddResult("T67", ok, StringFormat("mfe_before=%.3f mfe_after=%.3f exit_price_after=%.2f (must equal 102.00, not 999)",
                beforeExtra.mfe_r, afterExtra.mfe_r, afterExtra.exit_price));
     }

   //--- T68: initial_risk<=0 guard keeps mae_r/mfe_r at 0.0 (mirrors
   //--- CGZExitEngine::ComputeRealizedR's own defensive check); duration
   //--- and final_r are still set correctly on close, and a second
   //--- OnTradeClosed() call for the same id is a safe no-op. -------------
   void T68_JournalZeroRiskGuardAndFinalize()
     {
      CGZJournalEngine j(m_logger); j.Init();
      GZ_Trade tr = MakeTrade(1, 1, GZ_LEG_BULLISH, 100.0, MakeTime(2026,1,9,13,0));
      j.OnTradeEntered(tr, 0.0); // no risk known - defensive path

      j.OnBar(MakeBar(MakeTime(2026,1,9,13,1), 100,110,90,105));
      GZ_TradeJournal mid = j.GetJournal(0);
      bool guardOk = (MathAbs(mid.mae_r)<0.0001) && (MathAbs(mid.mfe_r)<0.0001);

      j.OnTradeClosed(1, MakeTime(2026,1,9,13,10), 105.0, 0.0);
      j.OnTradeClosed(1, MakeTime(2026,1,9,13,20), 999.0, 99.0); // idempotent - must not overwrite
      GZ_TradeJournal fin = j.GetJournal(0);

      bool finalizeOk = (!fin.is_open) && (fin.duration_seconds==600) &&
                        (MathAbs(fin.exit_price-105.0)<0.0001) && (MathAbs(fin.final_r)<0.0001);

      bool ok = guardOk && finalizeOk;
      AddResult("T68", ok, StringFormat("mae_r=%.3f mfe_r=%.3f duration=%ds exit_price=%.2f (must be 105.00)",
                mid.mae_r, mid.mfe_r, fin.duration_seconds, fin.exit_price));
     }

   //--- T69: a setup reaching FIB_ACTIVE produces exactly one
   //--- GZ_LEDGER_SETUP_VALID event, timestamped at fib_active_time. ------
   void T69_LedgerValidSetupRecordedOnce()
     {
      datetime t0 = MakeTime(2026,1,9,14,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);

      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      int i1=-1; legEngine.Update(low1,0.0,false,i1);
      int i2=-1; legEngine.Update(high1,0.0,false,i2);
      GZ_Leg leg = legEngine.GetLeg(i2);

      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      sm.OnLegCreated(leg);

      GZ_BreakConfig bcfg; bcfg.Default();
      CGZBreakEngine breakEngine(m_logger); breakEngine.Configure(bcfg);

      MqlRates breakBar = MakeBar(t0+8*300, 109,112,108,111);
      legEngine.UpdateBar(breakBar);
      GZ_Leg legAfterExtreme = legEngine.GetLeg(i2);
      breakEngine.OnBar(breakBar);
      bool broke = breakEngine.CheckBreak(legAfterExtreme, breakBar); // sets .broken/.break_time in place
      legEngine.SetLeg(i2, legAfterExtreme);
      sm.OnLegBroken(legAfterExtreme); // -> FIB_ACTIVE

      GZ_EntryConfig ecfg; ecfg.Default();
      CGZEntryEngine emptyEntry(m_logger); emptyEntry.Init(ecfg);
      GZ_ExitConfig xcfg; xcfg.Default();
      CGZExitEngine emptyExit(m_logger); emptyExit.Init(xcfg);

      CGZEventLedger ledger(m_logger); ledger.Init();
      ledger.BuildFromFinalState(sm, emptyEntry, emptyExit);

      GZ_Setup s = sm.GetSetup(0);
      bool ok = broke && (ledger.CountByType(GZ_LEDGER_SETUP_VALID)==1) && (ledger.EventCount()==1);
      if(ok)
        {
         GZ_LedgerEvent ev = ledger.GetEvent(0);
         ok = (ev.setup_id==s.id) && (ev.time==s.fib_active_time);
        }
      AddResult("T69", ok, StringFormat("valid_events=%d total_events=%d", ledger.CountByType(GZ_LEDGER_SETUP_VALID), ledger.EventCount()));
     }

   //--- T70: an ordinary cancellation (DATA_END) is classified
   //--- SETUP_CANCELLED; an INVALID_PENETRATION cancellation is
   //--- classified SETUP_INVALIDATED (and, having reached FIB_ACTIVE
   //--- first, ALSO produces its own separate SETUP_VALID row). -----------
   void T70_LedgerCancelledVsInvalidatedClassification()
     {
      datetime t0 = MakeTime(2026,1,9,15,0);

      // Single shared leg engine for BOTH setups (mirrors real usage - one
      // CGZLegEngine per replay - see GZ_TradeSimulator.mqh). Using two
      // separate engines here previously caused legA.id and legB.id to
      // collide (each engine's id counter starts at 1 independently),
      // which made OnLegBroken()'s FindByLegId() match the wrong (already
      // terminal) setup and silently skip the FIB_ACTIVE cascade for
      // Setup B - a test-construction bug, not an CGZEventLedger one.
      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      GZ_BreakConfig bcfg; bcfg.Default();
      CGZBreakEngine breakEngine(m_logger); breakEngine.Configure(bcfg);
      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);

      // Setup A: LEG_DETECTED only, never locked. A same-direction Setup B
      // created afterwards cancels it with the ordinary NEW_VALID_SETUP
      // reason (not one of the two INVALID_* reasons) - this is the
      // "ordinary cancellation" case the classification must bucket as
      // SETUP_CANCELLED, whichever ordinary reason actually fires.
      GZ_Swing lowA = MakeSwing(GZ_SWING_LOW, 50.0, t0, t0+2*300, 101);
      int ia=-1; legEngine.Update(lowA,0.0,false,ia);
      GZ_Swing highA = MakeSwing(GZ_SWING_HIGH, 60.0, t0+5*300, t0+7*300, 102);
      int ia2=-1; legEngine.Update(highA,0.0,false,ia2);
      GZ_Leg legA = legEngine.GetLeg(ia2);
      sm.OnLegCreated(legA); // Setup #1, LEG_DETECTED (bullish)

      // Setup B: LEG_DETECTED -> broken -> FIB_ACTIVE -> invalidated. Also
      // bullish, so creating it below cancels Setup A (NEW_VALID_SETUP).
      GZ_Swing lowB  = MakeSwing(GZ_SWING_LOW,  90.0,  t0+10*300, t0+12*300, 201);
      GZ_Swing highB = MakeSwing(GZ_SWING_HIGH, 110.0, t0+15*300, t0+17*300, 202);
      int ib=-1; legEngine.Update(lowB,0.0,false,ib);
      int ib2=-1; legEngine.Update(highB,0.0,false,ib2);
      GZ_Leg legB = legEngine.GetLeg(ib2);
      int siB = sm.OnLegCreated(legB); // Setup #2

      MqlRates breakBarB = MakeBar(t0+18*300, 109,112,108,111);
      legEngine.UpdateBar(breakBarB);
      GZ_Leg legBAfterExtreme = legEngine.GetLeg(ib2);
      breakEngine.OnBar(breakBarB);
      bool brokeB = breakEngine.CheckBreak(legBAfterExtreme, breakBarB); // sets .broken/.break_time in place
      legEngine.SetLeg(ib2, legBAfterExtreme);
      sm.OnLegBroken(legBAfterExtreme); // -> FIB_ACTIVE (legB.id is now unique, so FindByLegId matches Setup B)
      GZ_Setup setupB = sm.GetSetup(siB);
      sm.CancelForInvalidPenetration(setupB.id, t0+19*300);

      sm.OnDataEnd(t0+20*300); // no-op here - both setups are already terminal by this point

      GZ_EntryConfig ecfg; ecfg.Default();
      CGZEntryEngine emptyEntry(m_logger); emptyEntry.Init(ecfg);
      GZ_ExitConfig xcfg; xcfg.Default();
      CGZExitEngine emptyExit(m_logger); emptyExit.Init(xcfg);

      CGZEventLedger ledger(m_logger); ledger.Init();
      ledger.BuildFromFinalState(sm, emptyEntry, emptyExit);

      bool ok = brokeB && (ledger.CountByType(GZ_LEDGER_SETUP_CANCELLED)==1) &&
                (ledger.CountByType(GZ_LEDGER_SETUP_INVALIDATED)==1) &&
                (ledger.CountByType(GZ_LEDGER_SETUP_VALID)==1); // only Setup B ever reached FIB_ACTIVE
      AddResult("T70", ok, StringFormat("cancelled=%d invalidated=%d valid=%d",
                ledger.CountByType(GZ_LEDGER_SETUP_CANCELLED), ledger.CountByType(GZ_LEDGER_SETUP_INVALIDATED),
                ledger.CountByType(GZ_LEDGER_SETUP_VALID)));
     }

   //--- helper: build the minimal full-pipeline scenario shared by
   //--- T71/T72/T73/T74 (bullish leg -> break -> zone touch -> TOUCH
   //--- entry -> TP_HIT exit), mirroring T64's own fixture. ---------------
   void BuildPhase7Scenario(GZ_Swing &swings[], MqlRates &m5[], MqlRates &m1[])
     {
      datetime t0 = MakeTime(2026,1,9,18,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);
      ArrayResize(swings,2); swings[0]=low1; swings[1]=high1;

      ArrayResize(m5,6);
      m5[0]=MakeBar(t0+2*300,  90,90.5,89.5,90);
      m5[1]=MakeBar(t0+7*300, 109,110.5,108.5,110);
      m5[2]=MakeBar(t0+8*300, 109,112,108,111);     // break: close=111>110
      m5[3]=MakeBar(t0+9*300, 98,100,95,99);        // touches zone [92.2,105.4] -> WAITING_ENTRY
      m5[4]=MakeBar(t0+10*300, 99,100,98,99);
      m5[5]=MakeBar(t0+11*300, 99,100,98,99);

      datetime T = t0+9*300;
      ArrayResize(m1,2);
      m1[0]=MakeBar(T+300+60,  98.5,98.6,98.0,98.2);    // triggers TOUCH entry
      m1[1]=MakeBar(T+600+60, 115.0,116.0,114.5,115.5); // well past TP (sl=90 (origin), tp=2R)
     }

   //--- T71: exactly one ENTRY event and one EXIT event are produced by a
   //--- full CGZTradeSimulator.Run(), matching the real trade/exit's own
   //--- id/time/price fields exactly. --------------------------------------
   void T71_LedgerEntryExitFromFullRun()
     {
      GZ_Swing swings[]; MqlRates m5[]; MqlRates m1[];
      BuildPhase7Scenario(swings, m5, m1);

      GZ_TimeConfig tcfg; tcfg.Default();
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      GZ_EntryConfig ecfg; ecfg.Default();
      GZ_BreakConfig bcfg; bcfg.Default();
      GZ_ExitConfig xcfg; xcfg.Default();

      CGZLegEngine leg(m_logger); leg.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brk(m_logger); brk.Configure(bcfg);
      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      CGZEntryEngine ent(m_logger); ent.Init(ecfg);
      CGZExitEngine ext(m_logger); ext.Init(xcfg);
      CGZTimeEngine time_engine(m_logger); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      CGZJournalEngine journal(m_logger); journal.Init();
      CGZEventLedger ledger(m_logger); ledger.Init();
      CGZTradeSimulator sim(m_logger);
      sim.Run(m1, m5, swings, 2, leg, brk, sm, ent, ext, journal, ledger, time_engine, sess, profile, false, false);

      bool ok = (ent.TradeCount()==1) && (ext.ExitCount()==1) &&
                (ledger.CountByType(GZ_LEDGER_ENTRY)==1) && (ledger.CountByType(GZ_LEDGER_EXIT)==1);
      if(ok)
        {
         GZ_Trade tr = ent.GetTrade(0);
         GZ_TradeExit ex = ext.GetExit(0);
         GZ_LedgerEvent entryEv; entryEv.Clear();
         GZ_LedgerEvent exitEv;  exitEv.Clear();
         for(int i=0;i<ledger.EventCount();i++)
           {
            GZ_LedgerEvent e = ledger.GetEvent(i);
            if(e.event_type==GZ_LEDGER_ENTRY) entryEv = e;
            if(e.event_type==GZ_LEDGER_EXIT)  exitEv  = e;
           }
         ok = (entryEv.trade_id==tr.id) && (entryEv.setup_id==tr.setup_id) && (entryEv.time==tr.entry_time) &&
              (MathAbs(entryEv.price-tr.entry_price)<0.0001) &&
              (exitEv.trade_id==ex.trade_id) && (exitEv.time==ex.exit_time) &&
              (MathAbs(exitEv.price-ex.exit_price)<0.0001) && (exitEv.reason==ex.ExitReasonToString());
        }
      AddResult("T71", ok, StringFormat("trades=%d exits=%d entry_events=%d exit_events=%d",
                ent.TradeCount(), ext.ExitCount(), ledger.CountByType(GZ_LEDGER_ENTRY), ledger.CountByType(GZ_LEDGER_EXIT)));
     }

   //--- T72: a BARE CGZEventLedger::BuildFromFinalState() replay (no
   //--- Phase 10 filter pass on top) never emits Rejection/FilterResult -
   //--- those are constructed only by the SEPARATE Phase 10 pass a caller
   //--- runs afterward (see GoldenZoneSTR_Research.mq5's Phase 10 block
   //--- and T97-T106), never by BuildFromFinalState() itself. --------------
   void T72_LedgerReservedTypesNeverEmitted()
     {
      GZ_Swing swings[]; MqlRates m5[]; MqlRates m1[];
      BuildPhase7Scenario(swings, m5, m1);

      GZ_TimeConfig tcfg; tcfg.Default();
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      GZ_EntryConfig ecfg; ecfg.Default();
      GZ_BreakConfig bcfg; bcfg.Default();
      GZ_ExitConfig xcfg; xcfg.Default();

      CGZLegEngine leg(m_logger); leg.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brk(m_logger); brk.Configure(bcfg);
      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      CGZEntryEngine ent(m_logger); ent.Init(ecfg);
      CGZExitEngine ext(m_logger); ext.Init(xcfg);
      CGZTimeEngine time_engine(m_logger); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      CGZJournalEngine journal(m_logger); journal.Init();
      CGZEventLedger ledger(m_logger); ledger.Init();
      CGZTradeSimulator sim(m_logger);
      sim.Run(m1, m5, swings, 2, leg, brk, sm, ent, ext, journal, ledger, time_engine, sess, profile, false, false);

      bool ok = (ledger.EventCount()>0) &&
                (ledger.CountByType(GZ_LEDGER_REJECTION)==0) &&
                (ledger.CountByType(GZ_LEDGER_FILTER_RESULT)==0);
      AddResult("T72", ok, StringFormat("total_events=%d rejection=%d filter_result=%d",
                ledger.EventCount(), ledger.CountByType(GZ_LEDGER_REJECTION), ledger.CountByType(GZ_LEDGER_FILTER_RESULT)));
     }

   //--- T73: no-lookahead sanity - the resulting trade's journal never
   //--- records an MAE/MFE/reach time before entry_time or after
   //--- exit_time (every excursion timestamp is causally within the
   //--- trade's own open lifetime). -----------------------------------------
   void T73_JournalNoLookaheadTiming()
     {
      GZ_Swing swings[]; MqlRates m5[]; MqlRates m1[];
      BuildPhase7Scenario(swings, m5, m1);

      GZ_TimeConfig tcfg; tcfg.Default();
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      GZ_EntryConfig ecfg; ecfg.Default();
      GZ_BreakConfig bcfg; bcfg.Default();
      GZ_ExitConfig xcfg; xcfg.Default();

      CGZLegEngine leg(m_logger); leg.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brk(m_logger); brk.Configure(bcfg);
      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      CGZEntryEngine ent(m_logger); ent.Init(ecfg);
      CGZExitEngine ext(m_logger); ext.Init(xcfg);
      CGZTimeEngine time_engine(m_logger); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      CGZJournalEngine journal(m_logger); journal.Init();
      CGZEventLedger ledger(m_logger); ledger.Init();
      CGZTradeSimulator sim(m_logger);
      sim.Run(m1, m5, swings, 2, leg, brk, sm, ent, ext, journal, ledger, time_engine, sess, profile, false, false);

      bool ok = (journal.JournalCount()==1);
      if(ok)
        {
         GZ_TradeJournal j = journal.GetJournal(0);
         ok = (!j.is_open) &&
              (j.time_to_mae>=j.entry_time) && (j.time_to_mae<=j.exit_time) &&
              (j.time_to_mfe>=j.entry_time) && (j.time_to_mfe<=j.exit_time);
         for(int i=0;i<GZ_REACH_LEVEL_COUNT && ok;i++)
            if(j.reach_hit[i])
               ok = (j.reach_time[i]>=j.entry_time) && (j.reach_time[i]<=j.exit_time);
        }
      AddResult("T73", ok, "mae/mfe/reach timestamps all within [entry_time, exit_time]");
     }

   //--- T74: full-pipeline determinism through the Phase 7-updated
   //--- CGZTradeSimulator - two independent runs over identical data and
   //--- configuration produce identical journals AND identical ledgers. ---
   void T74_JournalAndLedgerDeterminism()
     {
      GZ_Swing swings[]; MqlRates m5[]; MqlRates m1[];
      BuildPhase7Scenario(swings, m5, m1);

      GZ_TimeConfig tcfg; tcfg.Default();
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      GZ_EntryConfig ecfg; ecfg.Default();
      GZ_BreakConfig bcfg; bcfg.Default();
      GZ_ExitConfig xcfg; xcfg.Default();

      CGZLegEngine legA(m_logger); legA.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brkA(m_logger); brkA.Configure(bcfg);
      CGZSetupStateMachine smA(m_logger); smA.Init(0.30,0.90);
      CGZEntryEngine entA(m_logger); entA.Init(ecfg);
      CGZExitEngine extA(m_logger); extA.Init(xcfg);
      CGZTimeEngine timeA(m_logger); timeA.Configure(tcfg);
      CGZSessionEngine sessA;
      CGZJournalEngine journalA(m_logger); journalA.Init();
      CGZEventLedger ledgerA(m_logger); ledgerA.Init();
      CGZTradeSimulator simA(m_logger);
      simA.Run(m1, m5, swings, 2, legA, brkA, smA, entA, extA, journalA, ledgerA, timeA, sessA, profile, false, false);

      CGZLegEngine legB(m_logger); legB.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brkB(m_logger); brkB.Configure(bcfg);
      CGZSetupStateMachine smB(m_logger); smB.Init(0.30,0.90);
      CGZEntryEngine entB(m_logger); entB.Init(ecfg);
      CGZExitEngine extB(m_logger); extB.Init(xcfg);
      CGZTimeEngine timeB(m_logger); timeB.Configure(tcfg);
      CGZSessionEngine sessB;
      CGZJournalEngine journalB(m_logger); journalB.Init();
      CGZEventLedger ledgerB(m_logger); ledgerB.Init();
      CGZTradeSimulator simB(m_logger);
      simB.Run(m1, m5, swings, 2, legB, brkB, smB, entB, extB, journalB, ledgerB, timeB, sessB, profile, false, false);

      bool ok = (journalA.JournalCount()==journalB.JournalCount()) && (journalA.JournalCount()==1) &&
                (ledgerA.EventCount()==ledgerB.EventCount()) && (ledgerA.EventCount()>0);
      if(ok)
        {
         GZ_TradeJournal ja = journalA.GetJournal(0);
         GZ_TradeJournal jb = journalB.GetJournal(0);
         ok = (ja.time_to_mae==jb.time_to_mae) && (MathAbs(ja.mae_r-jb.mae_r)<0.00001) &&
              (ja.time_to_mfe==jb.time_to_mfe) && (MathAbs(ja.mfe_r-jb.mfe_r)<0.00001) &&
              (ja.duration_seconds==jb.duration_seconds) && (MathAbs(ja.final_r-jb.final_r)<0.00001);
         for(int i=0;i<GZ_REACH_LEVEL_COUNT && ok;i++)
            ok = (ja.reach_hit[i]==jb.reach_hit[i]) && (ja.reach_time[i]==jb.reach_time[i]);
        }
      if(ok)
        {
         for(int i=0;i<ledgerA.EventCount() && ok;i++)
           {
            GZ_LedgerEvent ea = ledgerA.GetEvent(i);
            GZ_LedgerEvent eb = ledgerB.GetEvent(i);
            ok = (ea.event_type==eb.event_type) && (ea.time==eb.time) && (ea.setup_id==eb.setup_id) &&
                 (ea.trade_id==eb.trade_id) && (ea.reason==eb.reason) && (MathAbs(ea.price-eb.price)<0.00001);
           }
        }
      AddResult("T74", ok, StringFormat("journalsA=%d journalsB=%d eventsA=%d eventsB=%d",
                journalA.JournalCount(), journalB.JournalCount(), ledgerA.EventCount(), ledgerB.EventCount()));
     }

   //=====================================================================
   //  PHASE 8: METRICS + REPORTING  (T75-T86)
   //=====================================================================

   //--- helper: push one already-CLOSED synthetic trade into a
   //--- CGZJournalEngine. realized_r is passed directly to
   //--- OnTradeClosed() (its own documented parameter - see
   //--- GZ_JournalEngine.mqh) so tests can target an EXACT R outcome
   //--- without needing to reverse-engineer bar prices that would
   //--- produce it. mae_bar/mfe_bar are OPTIONAL extra OnBar() calls a
   //--- test can use to also control mae_r/mfe_r precisely; when NULL,
   //--- the trade closes with its Phase 7 default (mae_r=mfe_r=0.0,
   //--- same as OnTradeEntered() leaves it - see GZ_JournalEngine.mqh).
   void AddClosedJournalTrade(CGZJournalEngine &j, long id, ENUM_GZ_LEG_DIR dir,
                               datetime entry_t, datetime exit_t, double realized_r,
                               double initial_risk=1.0)
     {
      GZ_Trade tr = MakeTrade(id, id, dir, 100.0, entry_t);
      j.OnTradeEntered(tr, initial_risk);
      j.OnTradeClosed(id, exit_t, 100.0, realized_r);
     }

   //--- T75: Trade Metrics baseline - 3 winners/2 losers/1 breakeven,
   //--- exact win_rate/avg_win/avg_loss/profit_factor/net_r/avg_r/
   //--- expectancy (expectancy must equal avg_r exactly - design note 3,
   //--- GZ_MetricsTypes.mqh). ------------------------------------------
   void T75_MetricsTradeStatsBaseline()
     {
      CGZJournalEngine j(m_logger); j.Init();
      datetime t0 = MakeTime(2026,2,2,9,0); // Monday
      AddClosedJournalTrade(j, 1, GZ_LEG_BULLISH, t0,           t0+60,  1.0);
      AddClosedJournalTrade(j, 2, GZ_LEG_BULLISH, t0+2*3600,    t0+2*3600+60, 2.0);
      AddClosedJournalTrade(j, 3, GZ_LEG_BULLISH, t0+4*3600,    t0+4*3600+60, 0.5);
      AddClosedJournalTrade(j, 4, GZ_LEG_BEARISH, t0+6*3600,    t0+6*3600+60, -1.0);
      AddClosedJournalTrade(j, 5, GZ_LEG_BEARISH, t0+8*3600,    t0+8*3600+60, -0.5);
      AddClosedJournalTrade(j, 6, GZ_LEG_BEARISH, t0+10*3600,   t0+10*3600+60, 0.0);

      CGZTimeEngine time_engine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);

      CGZMetricsEngine metrics(m_logger);
      GZ_MetricsSummary sum;
      metrics.Compute(j, time_engine, sess, profile, sum);

      bool ok = (sum.trade.trade_count==6) && (sum.trade.winners==3) && (sum.trade.losers==2) &&
                (MathAbs(sum.trade.win_rate-(3.0/6.0))<0.0001) &&
                (MathAbs(sum.trade.avg_win_r-((1.0+2.0+0.5)/3.0))<0.0001) &&
                (MathAbs(sum.trade.avg_loss_r-((1.0+0.5)/2.0))<0.0001) &&
                (MathAbs(sum.trade.net_r-2.0)<0.0001) &&
                (MathAbs(sum.trade.avg_r-(2.0/6.0))<0.0001) &&
                (MathAbs(sum.trade.expectancy-sum.trade.avg_r)<0.00001) &&
                (!sum.trade.profit_factor_undefined) &&
                (MathAbs(sum.trade.profit_factor-(3.5/1.5))<0.0001);
      AddResult("T75", ok, StringFormat("trades=%d win_rate=%.3f avg_win=%.3f avg_loss=%.3f pf=%.3f net_r=%.3f avg_r=%.3f",
                sum.trade.trade_count, sum.trade.win_rate, sum.trade.avg_win_r, sum.trade.avg_loss_r,
                sum.trade.profit_factor, sum.trade.net_r, sum.trade.avg_r));
     }

   //--- T76: Profit Factor edge cases - winners-with-no-losers is flagged
   //--- UNDEFINED (mathematically infinite - design note 4), never
   //--- silently reported as some finite number; losers-with-no-winners
   //--- reports a plain, DEFINED 0.0 (there is a real denominator; the
   //--- numerator is legitimately zero). -----------------------------------
   void T76_MetricsProfitFactorUndefined()
     {
      CGZTimeEngine time_engine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      CGZMetricsEngine metrics(m_logger);

      CGZJournalEngine jWin(m_logger); jWin.Init();
      datetime t0 = MakeTime(2026,2,3,9,0);
      AddClosedJournalTrade(jWin, 1, GZ_LEG_BULLISH, t0,        t0+60,        1.0);
      AddClosedJournalTrade(jWin, 2, GZ_LEG_BULLISH, t0+3600,   t0+3600+60,   2.0);
      GZ_MetricsSummary sumWin; metrics.Compute(jWin, time_engine, sess, profile, sumWin);
      bool winOk = sumWin.trade.profit_factor_undefined && (MathAbs(sumWin.trade.profit_factor)<0.00001);

      CGZJournalEngine jLoss(m_logger); jLoss.Init();
      AddClosedJournalTrade(jLoss, 1, GZ_LEG_BULLISH, t0,        t0+60,        -1.0);
      AddClosedJournalTrade(jLoss, 2, GZ_LEG_BULLISH, t0+3600,   t0+3600+60,   -2.0);
      GZ_MetricsSummary sumLoss; metrics.Compute(jLoss, time_engine, sess, profile, sumLoss);
      bool lossOk = (!sumLoss.trade.profit_factor_undefined) && (MathAbs(sumLoss.trade.profit_factor)<0.00001);

      bool ok = winOk && lossOk;
      AddResult("T76", ok, StringFormat("winners_only: undefined=%s pf=%.3f | losers_only: undefined=%s pf=%.3f",
                sumWin.trade.profit_factor_undefined?"true":"false", sumWin.trade.profit_factor,
                sumLoss.trade.profit_factor_undefined?"true":"false", sumLoss.trade.profit_factor));
     }

   //--- T77: Risk - Max Drawdown (depth+duration in trades) on a known
   //--- R sequence: +1,+1 (peak=2) / -0.5,-0.5,-0.5 (trough=0.5, dd=1.5,
   //--- len=3) / +2 (new peak=2.5, episode closes). Exactly one drawdown
   //--- episode -> avg_drawdown_r == max_drawdown_r. -----------------------
   void T77_MetricsMaxDrawdown()
     {
      CGZJournalEngine j(m_logger); j.Init();
      datetime t0 = MakeTime(2026,2,4,9,0);
      double rs[6] = {1.0, 1.0, -0.5, -0.5, -0.5, 2.0};
      for(int i=0;i<6;i++)
         AddClosedJournalTrade(j, i+1, GZ_LEG_BULLISH, t0+i*3600, t0+i*3600+60, rs[i]);

      CGZTimeEngine time_engine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      CGZMetricsEngine metrics(m_logger);
      GZ_MetricsSummary sum; metrics.Compute(j, time_engine, sess, profile, sum);

      bool ok = (MathAbs(sum.risk.max_drawdown_r-1.5)<0.0001) &&
                (sum.risk.max_drawdown_duration_trades==3) &&
                (MathAbs(sum.risk.avg_drawdown_r-1.5)<0.0001);
      AddResult("T77", ok, StringFormat("max_dd=%.3fR dd_len=%d avg_dd=%.3fR",
                sum.risk.max_drawdown_r, sum.risk.max_drawdown_duration_trades, sum.risk.avg_drawdown_r));
     }

   //--- T78: Risk - winning/losing streaks; a breakeven (R==0.0) trade
   //--- breaks BOTH streak counters (documented - GZ_MetricsEngine.mqh). ---
   void T78_MetricsWinLoseStreaks()
     {
      CGZJournalEngine j(m_logger); j.Init();
      datetime t0 = MakeTime(2026,2,5,9,0);
      double rs[10] = {1.0,1.0,1.0, -1.0,-1.0, 0.0, 1.0,1.0,1.0,1.0};
      for(int i=0;i<10;i++)
         AddClosedJournalTrade(j, i+1, GZ_LEG_BULLISH, t0+i*3600, t0+i*3600+60, rs[i]);

      CGZTimeEngine time_engine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      CGZMetricsEngine metrics(m_logger);
      GZ_MetricsSummary sum; metrics.Compute(j, time_engine, sess, profile, sum);

      bool ok = (sum.risk.max_winning_streak==4) && (sum.risk.max_losing_streak==2);
      AddResult("T78", ok, StringFormat("max_win_streak=%d (expect 4) max_lose_streak=%d (expect 2)",
                sum.risk.max_winning_streak, sum.risk.max_losing_streak));
     }

   //--- T79: Behavior - avg MAE/MFE (from real OnBar() excursions, not
   //--- realized_r), avg duration, avg time-to-MAE/MFE, across 2 trades. ---
   void T79_MetricsBehaviorAverages()
     {
      CGZJournalEngine j(m_logger); j.Init();
      datetime t0 = MakeTime(2026,2,6,9,0);

      GZ_Trade tr1 = MakeTrade(1, 1, GZ_LEG_BULLISH, 100.0, t0);
      j.OnTradeEntered(tr1, 10.0); // 1R=10
      j.OnBar(MakeBar(t0+60,  100,115,95,110)); // mfe=15->1.5R@t0+60 ; mae=5->0.5R@t0+60
      j.OnTradeClosed(1, t0+120, 110.0, 1.0);

      datetime t1 = t0+3600;
      GZ_Trade tr2 = MakeTrade(2, 2, GZ_LEG_BULLISH, 100.0, t1);
      j.OnTradeEntered(tr2, 10.0);
      j.OnBar(MakeBar(t1+60, 100,105,90,95)); // mfe=5->0.5R@t1+60 ; mae=10->1.0R@t1+60
      j.OnTradeClosed(2, t1+600, 95.0, -1.0);

      CGZTimeEngine time_engine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      CGZMetricsEngine metrics(m_logger);
      GZ_MetricsSummary sum; metrics.Compute(j, time_engine, sess, profile, sum);

      bool ok = (MathAbs(sum.behavior.avg_mae_r-((0.5+1.0)/2.0))<0.0001) &&
                (MathAbs(sum.behavior.avg_mfe_r-((1.5+0.5)/2.0))<0.0001) &&
                (MathAbs(sum.behavior.avg_duration_seconds-((120.0+600.0)/2.0))<0.0001) &&
                (MathAbs(sum.behavior.avg_time_to_mae_seconds-60.0)<0.0001) &&
                (MathAbs(sum.behavior.avg_time_to_mfe_seconds-60.0)<0.0001);
      AddResult("T79", ok, StringFormat("avg_mae=%.3fR avg_mfe=%.3fR avg_dur=%.1fs avg_ttmae=%.1fs avg_ttmfe=%.1fs",
                sum.behavior.avg_mae_r, sum.behavior.avg_mfe_r, sum.behavior.avg_duration_seconds,
                sum.behavior.avg_time_to_mae_seconds, sum.behavior.avg_time_to_mfe_seconds));
     }

   //--- T80: Breakdown by direction - 2 bullish winners, 1 bearish loser,
   //--- each bucket must see ONLY its own trades. --------------------------
   void T80_MetricsBreakdownByDirection()
     {
      CGZJournalEngine j(m_logger); j.Init();
      datetime t0 = MakeTime(2026,2,7,9,0);
      AddClosedJournalTrade(j, 1, GZ_LEG_BULLISH, t0,        t0+60,      1.0);
      AddClosedJournalTrade(j, 2, GZ_LEG_BULLISH, t0+3600,   t0+3660,    2.0);
      AddClosedJournalTrade(j, 3, GZ_LEG_BEARISH, t0+7200,   t0+7260,   -1.0);

      CGZTimeEngine time_engine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      CGZMetricsEngine metrics(m_logger);
      GZ_MetricsSummary sum; metrics.Compute(j, time_engine, sess, profile, sum);

      bool ok = (sum.by_direction[0].label=="LONG") && (sum.by_direction[0].stats.trade_count==2) &&
                (MathAbs(sum.by_direction[0].stats.net_r-3.0)<0.0001) &&
                (sum.by_direction[1].label=="SHORT") && (sum.by_direction[1].stats.trade_count==1) &&
                (MathAbs(sum.by_direction[1].stats.net_r-(-1.0))<0.0001);
      AddResult("T80", ok, StringFormat("LONG n=%d net_r=%.2f | SHORT n=%d net_r=%.2f",
                sum.by_direction[0].stats.trade_count, sum.by_direction[0].stats.net_r,
                sum.by_direction[1].stats.trade_count, sum.by_direction[1].stats.net_r));
     }

   //--- T81: Breakdown by session - one entry inside the configured
   //--- 16:30-20:30 broker-time window, one outside; must land in the
   //--- correct bucket using the SAME CGZSessionEngine::Evaluate() the
   //--- live pipeline evaluates trades against. ----------------------------
   void T81_MetricsBreakdownBySession()
     {
      CGZJournalEngine j(m_logger); j.Init();
      datetime tInside  = MakeTime(2026,2,9,18,0);  // Monday 18:00 - inside 16:30-20:30
      datetime tOutside = MakeTime(2026,2,9,9,0);   // Monday 09:00 - outside
      AddClosedJournalTrade(j, 1, GZ_LEG_BULLISH, tInside,  tInside+60,  1.0);
      AddClosedJournalTrade(j, 2, GZ_LEG_BULLISH, tOutside, tOutside+60, -1.0);

      CGZTimeEngine time_engine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      GZ_SessionProfile profile; profile.Set("PROFILE_01","Session",GZ_TIME_BROKER,16,30,20,30,true,true);
      CGZMetricsEngine metrics(m_logger);
      GZ_MetricsSummary sum; metrics.Compute(j, time_engine, sess, profile, sum);

      bool ok = (sum.by_session[0].label=="INSIDE")  && (sum.by_session[0].stats.trade_count==1) &&
                (MathAbs(sum.by_session[0].stats.net_r-1.0)<0.0001) &&
                (sum.by_session[1].label=="OUTSIDE") && (sum.by_session[1].stats.trade_count==1) &&
                (MathAbs(sum.by_session[1].stats.net_r-(-1.0))<0.0001);
      AddResult("T81", ok, StringFormat("INSIDE n=%d net_r=%.2f | OUTSIDE n=%d net_r=%.2f",
                sum.by_session[0].stats.trade_count, sum.by_session[0].stats.net_r,
                sum.by_session[1].stats.trade_count, sum.by_session[1].stats.net_r));
     }

   //--- T82: Breakdown by hour/day-of-week/month - derives its OWN
   //--- expected bucket indices from the same entry_time via
   //--- TimeToStruct() (self-consistent, no hand-guessed weekday - same
   //--- style already used by T04's Saturday-presence heuristic). ---------
   void T82_MetricsBreakdownByHourDowMonth()
     {
      CGZJournalEngine j(m_logger); j.Init();
      datetime t0 = MakeTime(2026,3,11,14,0); // Wednesday, March
      AddClosedJournalTrade(j, 1, GZ_LEG_BULLISH, t0, t0+60, 1.0);

      MqlDateTime dt; TimeToStruct(t0, dt);

      CGZTimeEngine time_engine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      CGZMetricsEngine metrics(m_logger);
      GZ_MetricsSummary sum; metrics.Compute(j, time_engine, sess, profile, sum);

      bool ok = (sum.by_hour[dt.hour].stats.trade_count==1) &&
                (sum.by_dow[dt.day_of_week].stats.trade_count==1) &&
                (sum.by_month[dt.mon-1].stats.trade_count==1);
      // Every OTHER bucket in each dimension must stay at zero.
      for(int i=0;i<GZ_BREAKDOWN_HOUR_COUNT && ok;i++)
         if(i!=dt.hour) ok = (sum.by_hour[i].stats.trade_count==0);
      for(int i=0;i<GZ_BREAKDOWN_DOW_COUNT && ok;i++)
         if(i!=dt.day_of_week) ok = (sum.by_dow[i].stats.trade_count==0);
      for(int i=0;i<GZ_BREAKDOWN_MONTH_COUNT && ok;i++)
         if(i!=dt.mon-1) ok = (sum.by_month[i].stats.trade_count==0);

      AddResult("T82", ok, StringFormat("hour[%d]=%d dow[%d]=%d month[%d]=%d (each expect 1, all others 0)",
                dt.hour, sum.by_hour[dt.hour].stats.trade_count,
                dt.day_of_week, sum.by_dow[dt.day_of_week].stats.trade_count,
                dt.mon-1, sum.by_month[dt.mon-1].stats.trade_count));
     }

   //--- T83: Population = CLOSED trades only (design note 1) - a trade
   //--- still open (never OnTradeClosed()) must be excluded from EVERY
   //--- total/bucket, not just silently counted as a 0.0-R trade. ---------
   void T83_MetricsOpenTradesExcluded()
     {
      CGZJournalEngine j(m_logger); j.Init();
      datetime t0 = MakeTime(2026,2,10,9,0);
      AddClosedJournalTrade(j, 1, GZ_LEG_BULLISH, t0, t0+60, 1.0);

      GZ_Trade trOpen = MakeTrade(2, 2, GZ_LEG_BULLISH, 100.0, t0+3600);
      j.OnTradeEntered(trOpen, 10.0); // never closed

      CGZTimeEngine time_engine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      CGZMetricsEngine metrics(m_logger);
      GZ_MetricsSummary sum; metrics.Compute(j, time_engine, sess, profile, sum);

      bool ok = (j.JournalCount()==2) && (sum.trade.trade_count==1) && (sum.closed_trade_count==1) &&
                (MathAbs(sum.trade.net_r-1.0)<0.0001);
      AddResult("T83", ok, StringFormat("journals=%d(open+closed) counted_trades=%d net_r=%.3f",
                j.JournalCount(), sum.trade.trade_count, sum.trade.net_r));
     }

   //--- T84: a BARE CGZMetricsEngine::Compute() call (Phase 8, unfiltered)
   //--- never populates .filters with anything but its zero/false default -
   //--- that struct is only filled by a CALLER diffing Compute() against
   //--- ComputeFiltered() (Phase 10 - see T106 and GoldenZoneSTR_Research
   //--- .mq5's Phase 10 block), never by Compute() itself. ------------------
   void T84_MetricsFilterDiagnosticsReservedStub()
     {
      CGZJournalEngine j(m_logger); j.Init();
      datetime t0 = MakeTime(2026,2,11,9,0);
      AddClosedJournalTrade(j, 1, GZ_LEG_BULLISH, t0, t0+60, 1.0);

      CGZTimeEngine time_engine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      CGZMetricsEngine metrics(m_logger);
      GZ_MetricsSummary sum; metrics.Compute(j, time_engine, sess, profile, sum);

      bool ok = (!sum.filters.available) && (sum.filters.setups_before==0) && (sum.filters.setups_after==0) &&
                (sum.filters.trades_before==0) && (sum.filters.trades_after==0) && (sum.filters.rejections==0) &&
                (MathAbs(sum.filters.win_rate_delta)<0.00001) && (MathAbs(sum.filters.profit_factor_delta)<0.00001) &&
                (MathAbs(sum.filters.expectancy_delta)<0.00001) && (MathAbs(sum.filters.max_drawdown_delta)<0.00001) &&
                (sum.filters.trade_count_delta==0);
      AddResult("T84", ok, "A bare Compute() call leaves .filters at its zero/false default (available=false) - only ComputeFiltered()+diff (Phase 10, see T106) populates it");
     }

   //--- T85: Date range span - range_start/range_end must equal the
   //--- earliest entry_time / latest exit_time across the closed
   //--- population (design note 6 - "Date range" is reported, not
   //--- re-bucketed; Phase 9's Experiment Runner owns arbitrary slicing). --
   void T85_MetricsDateRangeSpan()
     {
      CGZJournalEngine j(m_logger); j.Init();
      datetime tA_entry = MakeTime(2026,2,12,9,0);
      datetime tA_exit  = tA_entry+120;
      datetime tB_entry = MakeTime(2026,2,13,10,0); // later entry
      datetime tB_exit  = tB_entry+7200;             // latest exit overall
      AddClosedJournalTrade(j, 1, GZ_LEG_BULLISH, tA_entry, tA_exit, 1.0);
      AddClosedJournalTrade(j, 2, GZ_LEG_BULLISH, tB_entry, tB_exit, -1.0);

      CGZTimeEngine time_engine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); time_engine.Configure(tcfg);
      CGZSessionEngine sess;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      CGZMetricsEngine metrics(m_logger);
      GZ_MetricsSummary sum; metrics.Compute(j, time_engine, sess, profile, sum);

      bool ok = (sum.range_start==tA_entry) && (sum.range_end==tB_exit);
      AddResult("T85", ok, StringFormat("range_start=%s (expect %s) range_end=%s (expect %s)",
                TimeToString(sum.range_start), TimeToString(tA_entry),
                TimeToString(sum.range_end), TimeToString(tB_exit)));
     }

   //--- T86: Determinism - two independent full-pipeline runs (Phase 5's
   //--- own BuildPhase7Scenario fixture, reused - see T74) over identical
   //--- data/configuration must produce byte-for-byte identical Phase 8
   //--- summaries. ----------------------------------------------------------
   void T86_MetricsDeterminism()
     {
      GZ_Swing swings[]; MqlRates m5[]; MqlRates m1[];
      BuildPhase7Scenario(swings, m5, m1);

      GZ_TimeConfig tcfg; tcfg.Default();
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      GZ_EntryConfig ecfg; ecfg.Default();
      GZ_BreakConfig bcfg; bcfg.Default();
      GZ_ExitConfig xcfg; xcfg.Default();

      CGZLegEngine legA(m_logger); legA.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brkA(m_logger); brkA.Configure(bcfg);
      CGZSetupStateMachine smA(m_logger); smA.Init(0.30,0.90);
      CGZEntryEngine entA(m_logger); entA.Init(ecfg);
      CGZExitEngine extA(m_logger); extA.Init(xcfg);
      CGZTimeEngine timeA(m_logger); timeA.Configure(tcfg);
      CGZSessionEngine sessA;
      CGZJournalEngine journalA(m_logger); journalA.Init();
      CGZEventLedger ledgerA(m_logger); ledgerA.Init();
      CGZTradeSimulator simA(m_logger);
      simA.Run(m1, m5, swings, 2, legA, brkA, smA, entA, extA, journalA, ledgerA, timeA, sessA, profile, false, false);
      CGZMetricsEngine metricsA(m_logger);
      GZ_MetricsSummary sumA; metricsA.Compute(journalA, timeA, sessA, profile, sumA);

      CGZLegEngine legB(m_logger); legB.Init(GZ_LEG_VARIANT_LAST_SWING);
      CGZBreakEngine brkB(m_logger); brkB.Configure(bcfg);
      CGZSetupStateMachine smB(m_logger); smB.Init(0.30,0.90);
      CGZEntryEngine entB(m_logger); entB.Init(ecfg);
      CGZExitEngine extB(m_logger); extB.Init(xcfg);
      CGZTimeEngine timeB(m_logger); timeB.Configure(tcfg);
      CGZSessionEngine sessB;
      CGZJournalEngine journalB(m_logger); journalB.Init();
      CGZEventLedger ledgerB(m_logger); ledgerB.Init();
      CGZTradeSimulator simB(m_logger);
      simB.Run(m1, m5, swings, 2, legB, brkB, smB, entB, extB, journalB, ledgerB, timeB, sessB, profile, false, false);
      CGZMetricsEngine metricsB(m_logger);
      GZ_MetricsSummary sumB; metricsB.Compute(journalB, timeB, sessB, profile, sumB);

      bool ok = (sumA.trade.trade_count==sumB.trade.trade_count) && (sumA.trade.trade_count==1) &&
                (MathAbs(sumA.trade.net_r-sumB.trade.net_r)<0.00001) &&
                (MathAbs(sumA.trade.win_rate-sumB.trade.win_rate)<0.00001) &&
                (MathAbs(sumA.risk.max_drawdown_r-sumB.risk.max_drawdown_r)<0.00001) &&
                (sumA.risk.max_winning_streak==sumB.risk.max_winning_streak) &&
                (sumA.risk.max_losing_streak==sumB.risk.max_losing_streak) &&
                (sumA.range_start==sumB.range_start) && (sumA.range_end==sumB.range_end);
      if(ok)
         for(int i=0;i<GZ_BREAKDOWN_DIRECTION_COUNT && ok;i++)
            ok = (sumA.by_direction[i].stats.trade_count==sumB.by_direction[i].stats.trade_count) &&
                 (MathAbs(sumA.by_direction[i].stats.net_r-sumB.by_direction[i].stats.net_r)<0.00001);
      AddResult("T86", ok, StringFormat("tradesA=%d tradesB=%d net_rA=%.3f net_rB=%.3f",
                sumA.trade.trade_count, sumB.trade.trade_count, sumA.trade.net_r, sumB.trade.net_r));
     }

   //=====================================================================
   //  PHASE 9: EXPERIMENT CONFIGURATION + RUNNER  (T87-T96)
   //=====================================================================

   //--- Shared fixture for T88-T96: a real, contiguous 13-bar M5 series
   //--- (NOT hand-injected GZ_Swing records like BuildPhase7Scenario -
   //--- CGZExperimentRunner detects swings itself via CGZSwingEngine, so
   //--- this must be genuine raw OHLC with real pivot windows) that,
   //--- under the baseline pivot_strength=2, produces EXACTLY two
   //--- confirmed swings - LOW=80 (pivot idx2, confirmed idx4) and
   //--- HIGH=140 (pivot idx6, confirmed idx8) - which the baseline
   //--- LAST_SWING Leg Engine turns into one bullish leg, broken on the
   //--- very next bar (idx9, CLOSE=141>140), which dips back into the
   //--- fib zone on the bar after that (idx10). idx11/idx12 are TRAILING
   //--- FILLER bars, present ONLY so CGZTradeSimulator has a "next M5
   //--- candle" for M1 bars anchored after idx10 to belong to - it
   //--- deliberately never evaluates M1 bars at/after the LAST M5 bar's
   //--- close time (no lookahead - see GZ_TradeSimulator.mqh), the exact
   //--- same reason BuildPhase7Scenario's own m5[] carries two bars past
   //--- its own zone-touch bar. idx11's H=145/L=90 are deliberately WIDE
   //--- (not tight filler values) so that, once idx9/idx10 each gain a
   //--- FULL pivot-strength=2 window (2 bars on both sides) from these
   //--- additions, neither accidentally starts qualifying as its OWN
   //--- spurious pivot (idx9 would otherwise beat idx10/idx11 as a new
   //--- HIGH; idx10 would otherwise beat idx11/idx12 as a new LOW) -
   //--- verified by hand, see the fixture's own design notes in
   //--- GZ_ExperimentRunner.mqh. Every bar besides idx2/idx6 stays a
   //--- non-pivot at strength>=2, so this fixture is exactly two swings,
   //--- no more, at the baseline strength.
   //---
   //--- IMPORTANT (extreme-price freeze): CGZLegEngine.UpdateBar() stops
   //--- extending a leg's extreme_price the instant leg.broken==true
   //--- (`if(m_legs[i].broken) continue;`). idx9 itself still runs
   //--- BEFORE break_engine.CheckBreak() sets broken=true that same
   //--- iteration, so idx9's own H=142 DOES extend extreme_price from
   //--- 140 to 142 first - the fib zone/entry level below are therefore
   //--- computed off 142 (the leg's true post-break extreme), NOT the
   //--- original 140 pivot price. idx11/idx12 run AFTER the leg is
   //--- already broken, so their H/L never move it further no matter how
   //--- wide they are.
   void BuildPhase9M5Series(MqlRates &m5[])
     {
      datetime t0 = MakeTime(2026,3,2,9,0);
      ArrayResize(m5,13);
      m5[0]  = MakeHL(t0+0*300,  105,100);
      m5[1]  = MakeHL(t0+1*300,  103,98);
      m5[2]  = MakeHL(t0+2*300,  102,80);   // pivot LOW candidate (L=80)
      m5[3]  = MakeHL(t0+3*300,  104,95);
      m5[4]  = MakeHL(t0+4*300,  106,97);   // LOW confirmed here (t0+4*300)
      m5[5]  = MakeHL(t0+5*300,  108,99);
      m5[6]  = MakeHL(t0+6*300,  140,100);  // pivot HIGH candidate (H=140)
      m5[7]  = MakeHL(t0+7*300,  115,101);
      m5[8]  = MakeHL(t0+8*300,  112,98);   // HIGH confirmed here (t0+8*300), close=105<140, no break yet
      m5[9]  = MakeBar(t0+9*300, 112,142,110,141); // BREAK bar: close=141>140 (baseline CLOSE break); extreme_price -> 142 (see note above)
      m5[10] = MakeHL(t0+10*300, 139,95);   // zone-touch bar: overlaps the (extreme=142-based) fib zone
      m5[11] = MakeHL(t0+11*300, 145,90);   // trailing filler: wide H/L so idx9/idx10 stay non-pivots once their window completes (see note above)
      m5[12] = MakeHL(t0+12*300, 100,95);   // trailing filler: gives m1[1] (exit bar) somewhere to belong
     }

   //--- M1 bars that, layered on BuildPhase9M5Series()'s zone-touch bar
   //--- (m5[10], time T), trigger a baseline TOUCH entry at the default
   //--- entry_fib_ratio=0.618. Entry level uses the leg's POST-BREAK
   //--- extreme_price=142 (see BuildPhase9M5Series design note), not the
   //--- original pivot 140: 142-0.618*(142-80)=103.684, inside m1[0]'s
   //--- [102,104.5] range. m1[0] falls within idx11's forming M5 candle
   //--- (T+300 <= m1[0].time < T+600), so it is evaluated using structure
   //--- state as of idx10 (already WAITING_ENTRY) - no lookahead. m1[1]
   //--- falls within idx12's forming candle and delivers a comfortable
   //--- TP_HIT (baseline STRUCTURE SL=leg origin=80, TP=2R - m1[1]
   //--- clears any realistic TP regardless of the exact entry fill
   //--- price).
   void BuildPhase9M1Series(MqlRates &m1[], datetime m5_touch_time)
     {
      datetime T = m5_touch_time;
      ArrayResize(m1,2);
      m1[0] = MakeBar(T+300+60, 104,104.5,102,102.5);   // crosses 103.684 -> TOUCH entry
      m1[1] = MakeBar(T+600+60, 155,160,154,158);        // well past TP
     }

   //--- T87: Experiment ID format/sequencing - "GZ_%06d", starting at 1,
   //--- incrementing once per Execute() call regardless of outcome. -------
   void T87_ExperimentIdSequencing()
     {
      CGZExperimentRunner runner(m_logger);
      bool okBefore = (runner.NextSequence()==1);

      GZ_ExperimentConfig cfg; cfg.Default();
      MqlRates emptyM1[], emptyM5[];
      GZ_ExperimentResult r1, r2;
      runner.RunSingle(cfg, emptyM1, emptyM5, "DS1", GZ_VAL_VALID, GZ_VAL_VALID, r1); // no M5 - still consumes an id
      runner.RunSingle(cfg, emptyM1, emptyM5, "DS1", GZ_VAL_VALID, GZ_VAL_VALID, r2);

      bool ok = okBefore && (r1.id=="GZ_000001") && (r2.id=="GZ_000002") && (runner.NextSequence()==3);
      AddResult("T87", ok, StringFormat("id1=%s id2=%s next_seq=%d", r1.id, r2.id, (int)runner.NextSequence()));
     }

   //--- T88: no M5 data - NO_M5_DATA warning, zero-everything, but the
   //--- result's own bookkeeping (id/dataset_id/config copy/strategy
   //--- version/validation status) is still fully populated - a rejected
   //--- experiment is still a COMPLETE, well-formed record, not a half-
   //--- filled one. -----------------------------------------------------
   void T88_ExperimentNoM5DataWarning()
     {
      CGZExperimentRunner runner(m_logger);
      GZ_ExperimentConfig cfg; cfg.Default();
      cfg.symbol = "XAUUSD";
      cfg.pivot_strength = 3; // arbitrary non-default, to prove config copies through
      MqlRates emptyM1[], emptyM5[];
      GZ_ExperimentResult r;
      runner.RunSingle(cfg, emptyM1, emptyM5, "DS_EMPTY", GZ_VAL_VALID_WITH_WARNINGS, GZ_VAL_INVALID, r);

      bool ok = (r.id=="GZ_000001") && (r.dataset_id=="DS_EMPTY") && (r.config.pivot_strength==3) &&
                (r.strategy_version==GZ_STRATEGY_VERSION) &&
                (r.m1_validation_status==GZ_VAL_VALID_WITH_WARNINGS) && (r.m5_validation_status==GZ_VAL_INVALID) &&
                (r.HasWarning("NO_M5_DATA")) && (r.trade_count==0) && (r.swing_count==0) &&
                (MathAbs(r.metrics.trade.net_r)<0.00001);
      AddResult("T88", ok, StringFormat("warnings=%d has_NO_M5_DATA=%s trade_count=%d",
                r.warning_count, r.HasWarning("NO_M5_DATA")?"true":"false", r.trade_count));
     }

   //--- T89: full pipeline from RAW M1/M5 data, through real swing
   //--- detection (Phase 2), leg/break (Phase 3), setup (Phase 4), entry
   //--- (Phase 5), exit (Phase 6), journal (Phase 7) and metrics (Phase
   //--- 8) - proving CGZExperimentRunner actually wires every phase
   //--- together, not just Phase 5-8 in isolation (see T71/T86, which
   //--- start from hand-injected swings). -------------------------------
   void T89_ExperimentFullPipelineFromRawData()
     {
      MqlRates m5[]; BuildPhase9M5Series(m5);
      MqlRates m1[]; BuildPhase9M1Series(m1, m5[10].time);

      CGZExperimentRunner runner(m_logger);
      GZ_ExperimentConfig cfg; cfg.Default();
      cfg.time_config.broker_offset_known = true; // avoid the (expected, harmless) BROKER_OFFSET_UNKNOWN warning here

      GZ_ExperimentResult r;
      runner.RunSingle(cfg, m1, m5, "DS_RAW", GZ_VAL_VALID, GZ_VAL_VALID, r);

      bool ok = (r.swing_count==2) && (r.leg_count==1) && (r.setup_count==1) &&
                (r.trade_count>=1) && (r.exit_count==r.trade_count) &&
                (!r.HasWarning("NO_TRADES_PRODUCED")) && (!r.HasWarning("NO_SWINGS_DETECTED")) &&
                (r.metrics.trade.trade_count==r.trade_count) &&
                (r.range_start==m5[0].time) && (r.range_end==m5[ArraySize(m5)-1].time);
      AddResult("T89", ok, StringFormat("swings=%d legs=%d setups=%d trades=%d exits=%d net_r=%.3f warnings=%d",
                r.swing_count, r.leg_count, r.setup_count, r.trade_count, r.exit_count, r.metrics.trade.net_r, r.warning_count));
     }

   //--- T90: same raw M5 fixture (reaches WAITING_ENTRY - swings/legs/
   //--- setups all still form normally) but with NO M1 data supplied -
   //--- the baseline TOUCH model can only ever fire on an M1 bar, so
   //--- entries are impossible here by construction. Proves
   //--- NO_TRADES_PRODUCED means specifically "no ENTRY", not "the whole
   //--- pipeline produced nothing". --------------------------------------
   void T90_ExperimentNoTradesProducedWarning()
     {
      MqlRates m5[]; BuildPhase9M5Series(m5);
      MqlRates emptyM1[];

      CGZExperimentRunner runner(m_logger);
      GZ_ExperimentConfig cfg; cfg.Default();
      cfg.time_config.broker_offset_known = true;

      GZ_ExperimentResult r;
      runner.RunSingle(cfg, emptyM1, m5, "DS_NOENTRY", GZ_VAL_VALID, GZ_VAL_VALID, r);

      bool ok = (r.swing_count==2) && (r.leg_count==1) && (r.setup_count==1) &&
                (r.trade_count==0) && (r.exit_count==0) && (r.HasWarning("NO_TRADES_PRODUCED")) &&
                (!r.HasWarning("NO_SWINGS_DETECTED")) && (MathAbs(r.metrics.trade.net_r)<0.00001);
      AddResult("T90", ok, StringFormat("swings=%d legs=%d setups=%d trades=%d has_NO_TRADES_PRODUCED=%s",
                r.swing_count, r.leg_count, r.setup_count, r.trade_count, r.HasWarning("NO_TRADES_PRODUCED")?"true":"false"));
     }

   //--- T91: RunBatch as a SWEEP - two configs varying ONLY
   //--- pivot_strength (1 vs 2) over the IDENTICAL raw M5 series must
   //--- produce two INDEPENDENT results whose own config/swing_count
   //--- differ exactly as expected - proving each experiment in a batch
   //--- gets its own config (not a shared/aliased/last-write-wins one)
   //--- and its own fresh engines (see header). ---------------------------
   void T91_ExperimentSweepByPivotStrength()
     {
      MqlRates m5[]; BuildPhase9M5Series(m5);
      MqlRates emptyM1[];

      GZ_ExperimentConfig base; base.Default();
      base.time_config.broker_offset_known = true;

      GZ_ExperimentConfig configs[];
      ArrayResize(configs,2);
      configs[0] = base; configs[0].pivot_strength = 1;
      configs[1] = base; configs[1].pivot_strength = 2;

      CGZExperimentRunner runner(m_logger);
      GZ_ExperimentResult results[];
      ENUM_GZ_BATCH_STATUS status = runner.RunBatch(configs, 2, GZ_EXPERIMENT_SWEEP, emptyM1, m5, "DS_SWEEP",
                                                      GZ_VAL_VALID, GZ_VAL_VALID, results);

      bool ok = (status==GZ_BATCH_OK) && (ArraySize(results)==2) &&
                (results[0].id=="GZ_000001") && (results[1].id=="GZ_000002") &&
                (results[0].config.pivot_strength==1) && (results[1].config.pivot_strength==2) &&
                (results[0].swing_count>results[1].swing_count) && (results[1].swing_count==2);
      AddResult("T91", ok, StringFormat("strength1_swings=%d strength2_swings=%d (expect 1st > 2nd, 2nd==2)",
                results[0].swing_count, results[1].swing_count));
     }

   //--- T92: RunBatch rejects an oversized batch OUTRIGHT (Roadmap:
   //--- "don't run one huge Grid at once") - zero results, zero
   //--- experiments actually executed (m_next_seq/NextSequence()
   //--- untouched), never a silent truncation to the cap. ------------------
   void T92_ExperimentBatchSizeCapRejection()
     {
      MqlRates m5[]; BuildPhase9M5Series(m5);
      MqlRates emptyM1[];

      GZ_ExperimentConfig base; base.Default();
      GZ_ExperimentConfig configs[];
      ArrayResize(configs,5);
      for(int i=0;i<5;i++) configs[i] = base;

      CGZExperimentRunner runner(m_logger);
      runner.SetMaxBatchSize(3);
      long seqBefore = runner.NextSequence();

      GZ_ExperimentResult results[];
      ENUM_GZ_BATCH_STATUS status = runner.RunBatch(configs, 5, GZ_EXPERIMENT_GRID, emptyM1, m5, "DS_TOO_BIG",
                                                      GZ_VAL_VALID, GZ_VAL_VALID, results);

      bool ok = (status==GZ_BATCH_REJECTED_TOO_LARGE) && (ArraySize(results)==0) && (runner.NextSequence()==seqBefore);
      AddResult("T92", ok, StringFormat("status=%s results=%d seq_before=%d seq_after=%d",
                EnumToString(status), ArraySize(results), (int)seqBefore, (int)runner.NextSequence()));
     }

   //--- T93: RunBatch within the cap succeeds normally - N configs in, N
   //--- results out, sequential ids. Also covers the empty-batch
   //--- rejection (count=0) as its own, distinct outcome. -----------------
   void T93_ExperimentBatchWithinCapAndEmptyBatch()
     {
      MqlRates m5[]; BuildPhase9M5Series(m5);
      MqlRates emptyM1[];

      GZ_ExperimentConfig base; base.Default();
      GZ_ExperimentConfig configs[];
      ArrayResize(configs,3);
      for(int i=0;i<3;i++) configs[i] = base;

      CGZExperimentRunner runner(m_logger);
      GZ_ExperimentResult results[];
      ENUM_GZ_BATCH_STATUS status = runner.RunBatch(configs, 3, GZ_EXPERIMENT_BATCH, emptyM1, m5, "DS_OK",
                                                      GZ_VAL_VALID, GZ_VAL_VALID, results);
      bool batchOk = (status==GZ_BATCH_OK) && (ArraySize(results)==3) &&
                     (results[0].id=="GZ_000001") && (results[1].id=="GZ_000002") && (results[2].id=="GZ_000003");

      GZ_ExperimentConfig emptyConfigs[];
      GZ_ExperimentResult emptyResults[];
      ENUM_GZ_BATCH_STATUS emptyStatus = runner.RunBatch(emptyConfigs, 0, GZ_EXPERIMENT_BATCH, emptyM1, m5, "DS_OK",
                                                           GZ_VAL_VALID, GZ_VAL_VALID, emptyResults);
      bool emptyOk = (emptyStatus==GZ_BATCH_REJECTED_EMPTY) && (ArraySize(emptyResults)==0);

      bool ok = batchOk && emptyOk;
      AddResult("T93", ok, StringFormat("batch_status=%s results=%d | empty_status=%s",
                EnumToString(status), ArraySize(results), EnumToString(emptyStatus)));
     }

   //--- T94: Determinism - two INDEPENDENT CGZExperimentRunner instances
   //--- over identical config+data produce identical results (both start
   //--- their own id sequence at GZ_000001, so full equality - including
   //--- id - is the correct expectation here, unlike a shared-runner
   //--- SWEEP where ids intentionally differ per experiment). -------------
   void T94_ExperimentDeterminism()
     {
      MqlRates m5[]; BuildPhase9M5Series(m5);
      MqlRates m1[]; BuildPhase9M1Series(m1, m5[10].time);

      GZ_ExperimentConfig cfg; cfg.Default();
      cfg.time_config.broker_offset_known = true;

      CGZExperimentRunner runnerA(m_logger);
      GZ_ExperimentResult a;
      runnerA.RunSingle(cfg, m1, m5, "DS_DET", GZ_VAL_VALID, GZ_VAL_VALID, a);

      CGZExperimentRunner runnerB(m_logger);
      GZ_ExperimentResult b;
      runnerB.RunSingle(cfg, m1, m5, "DS_DET", GZ_VAL_VALID, GZ_VAL_VALID, b);

      bool ok = (a.id==b.id) && (a.swing_count==b.swing_count) && (a.leg_count==b.leg_count) &&
                (a.setup_count==b.setup_count) && (a.trade_count==b.trade_count) && (a.exit_count==b.exit_count) &&
                (a.trade_count==b.trade_count) && (MathAbs(a.metrics.trade.net_r-b.metrics.trade.net_r)<0.00001) &&
                (MathAbs(a.metrics.trade.win_rate-b.metrics.trade.win_rate)<0.00001) &&
                (a.warning_count==b.warning_count) && (a.range_start==b.range_start) && (a.range_end==b.range_end);
      AddResult("T94", ok, StringFormat("tradesA=%d tradesB=%d net_rA=%.3f net_rB=%.3f",
                a.trade_count, b.trade_count, a.metrics.trade.net_r, b.metrics.trade.net_r));
     }

   //--- T95: Dataset ID / Strategy version / Data validation status are
   //--- carried through into the result EXACTLY as the caller supplied
   //--- them (design note 4, GZ_ExperimentTypes.mqh) - never recomputed,
   //--- never silently altered. --------------------------------------------
   void T95_ExperimentCallerSuppliedFieldsPassThrough()
     {
      MqlRates m5[]; BuildPhase9M5Series(m5);
      MqlRates emptyM1[];

      CGZExperimentRunner runner(m_logger);
      GZ_ExperimentConfig cfg; cfg.Default();
      GZ_ExperimentResult r;
      runner.RunSingle(cfg, emptyM1, m5, "XAUUSD_M1M5_2026.01.01_2026.06.13", GZ_VAL_VALID_WITH_WARNINGS, GZ_VAL_VALID, r);

      bool ok = (r.dataset_id=="XAUUSD_M1M5_2026.01.01_2026.06.13") &&
                (r.strategy_version==GZ_STRATEGY_VERSION) &&
                (r.m1_validation_status==GZ_VAL_VALID_WITH_WARNINGS) &&
                (r.m5_validation_status==GZ_VAL_VALID);
      AddResult("T95", ok, StringFormat("dataset_id=%s strategy_version=%s m1_status=%d m5_status=%d",
                r.dataset_id, r.strategy_version, (int)r.m1_validation_status, (int)r.m5_validation_status));
     }

   //--- T96: GZ_ExperimentConfig round-trips through GZ_ExperimentResult
   //--- byte-for-byte (Roadmap "Full configuration" Result field) - every
   //--- field the caller set is exactly what comes back out, across
   //--- several representative fields from every embedded sub-config. -----
   void T96_ExperimentFullConfigRoundTrip()
     {
      MqlRates m5[]; BuildPhase9M5Series(m5);
      MqlRates emptyM1[];

      GZ_ExperimentConfig cfg; cfg.Default();
      cfg.symbol                       = "EURUSD";
      cfg.pivot_strength                = 4;
      cfg.leg_variant                   = GZ_LEG_VARIANT_MIN_ATR_DISTANCE;
      cfg.break_config.buffer_atr_mult  = 0.25;
      cfg.fib_zone_min_ratio            = 0.35;
      cfg.fib_zone_max_ratio            = 0.85;
      cfg.entry_config.model            = GZ_ENTRY_LIMIT;
      cfg.entry_config.entry_fib_ratio  = 0.5;
      cfg.exit_config.tp_r_multiple     = 3.5;
      cfg.exit_config.be_trigger_r      = 1.0;
      cfg.apply_session_filter          = true;

      CGZExperimentRunner runner(m_logger);
      GZ_ExperimentResult r;
      runner.RunSingle(cfg, emptyM1, m5, "DS_ROUNDTRIP", GZ_VAL_VALID, GZ_VAL_VALID, r);

      bool ok = (r.config.symbol==cfg.symbol) && (r.config.pivot_strength==cfg.pivot_strength) &&
                (r.config.leg_variant==cfg.leg_variant) &&
                (MathAbs(r.config.break_config.buffer_atr_mult-cfg.break_config.buffer_atr_mult)<0.00001) &&
                (MathAbs(r.config.fib_zone_min_ratio-cfg.fib_zone_min_ratio)<0.00001) &&
                (MathAbs(r.config.fib_zone_max_ratio-cfg.fib_zone_max_ratio)<0.00001) &&
                (r.config.entry_config.model==cfg.entry_config.model) &&
                (MathAbs(r.config.entry_config.entry_fib_ratio-cfg.entry_config.entry_fib_ratio)<0.00001) &&
                (MathAbs(r.config.exit_config.tp_r_multiple-cfg.exit_config.tp_r_multiple)<0.00001) &&
                (MathAbs(r.config.exit_config.be_trigger_r-cfg.exit_config.be_trigger_r)<0.00001) &&
                (r.config.apply_session_filter==cfg.apply_session_filter);
      AddResult("T96", ok, "GZ_ExperimentConfig round-trips into GZ_ExperimentResult.config unchanged, field-for-field");
     }

   //=====================================================================
   //  PHASE 10: FILTER ENGINE  (T97-T106)
   //=====================================================================

   //--- helper: build a Setup with a BROKEN leg carrying exactly the
   //--- origin/target/break facts a filter test needs to control. Other
   //--- Setup fields (state/zone/etc.) are irrelevant to CGZFilterEngine
   //--- (design note 5, GZ_FilterTypes.mqh - it reads leg.broken/
   //--- break_time/break_price/target_swing/LegSize() and detected_time
   //--- only), so they are left at harmless defaults. ---------------------
   GZ_Setup MakeBrokenSetup(long id, ENUM_GZ_LEG_DIR dir, double origin_price, double target_price,
                             double extreme_price, double break_price, datetime break_time)
     {
      GZ_Setup s; s.Clear();
      s.id = id;
      s.leg.Clear();
      s.leg.id = id;
      s.leg.direction = dir;
      s.leg.origin_swing = MakeSwing(dir==GZ_LEG_BULLISH?GZ_SWING_LOW:GZ_SWING_HIGH, origin_price, break_time-3600, break_time-3600, id*10+1);
      s.leg.target_swing = MakeSwing(dir==GZ_LEG_BULLISH?GZ_SWING_HIGH:GZ_SWING_LOW, target_price, break_time-1800, break_time-1800, id*10+2);
      s.leg.extreme_price = extreme_price;
      s.leg.extreme_time  = break_time;
      s.leg.broken        = true;
      s.leg.break_time    = break_time;
      s.leg.break_price   = break_price;
      s.detected_time      = break_time-3600;
      s.state              = GZ_SETUP_BREAK_CONFIRMED;
      return s;
     }

   //--- helper: build an UNBROKEN setup (leg.broken==false) - Break/Leg/
   //--- Volume/Volatility all have nothing to measure for it and must
   //--- report NOT_AVAILABLE (design note 5). -----------------------------
   GZ_Setup MakeUnbrokenSetup(long id, ENUM_GZ_LEG_DIR dir, datetime detected_t)
     {
      GZ_Setup s; s.Clear();
      s.id = id;
      s.leg.Clear();
      s.leg.id = id;
      s.leg.direction = dir;
      s.leg.broken = false;
      s.detected_time = detected_t;
      s.state = GZ_SETUP_LEG_DETECTED;
      return s;
     }

   //--- helper: N flat bars (open==close==100, spaced 300s apart) whose
   //--- true range is EXACTLY high-low every bar (prev close is always
   //--- 100, so hc==lc==half-range - see T102's derivation note below),
   //--- letting a test pick an exact ATR by choosing high/low per bar. --
   void MakeFlatBars(MqlRates &r[], datetime t0, int count, double half_range, long vol=100)
     {
      ArrayResize(r, count);
      for(int i=0;i<count;i++)
         r[i] = MakeBar(t0+i*300, 100.0, 100.0+half_range, 100.0-half_range, 100.0, vol);
     }

   //--- T97: every filter OFF (Default()) -> overall_pass is ALWAYS true,
   //--- even for a setup whose leg never broke (every measurable filter
   //--- therefore NOT_AVAILABLE) - an OFF filter never gates anything. ---
   void T97_FilterOffNeverGates()
     {
      MqlRates bars[]; MakeFlatBars(bars, MakeTime(2026,3,2,10,0), 3, 1.0);
      GZ_Setup s = MakeUnbrokenSetup(1, GZ_LEG_BULLISH, bars[2].time);

      GZ_FilterSetConfig cfg; cfg.Default(); // every mode == GZ_FILTER_OFF
      CGZTimeEngine te(m_logger); GZ_TimeConfig tc; tc.Default(); te.Configure(tc);
      CGZSessionEngine se;
      CGZFilterEngine fe(m_logger);
      GZ_SetupFilterOutcome out;
      fe.Evaluate(s, bars, cfg, te, se, out);

      bool all_not_available = true;
      for(int i=0;i<GZ_FILTER_COUNT;i++)
         if(out.results[i].result!=GZ_FILTER_NOT_AVAILABLE) all_not_available=false;

      bool ok = out.overall_pass && all_not_available;
      AddResult("T97", ok, StringFormat("overall_pass=%s all_not_available=%s (every filter OFF by default)",
                out.overall_pass?"true":"false", all_not_available?"true":"false"));
     }

   //--- T98: Break Quality, INCLUDE mode. 6 flat bars (half_range=1.0 ->
   //--- ATR=2.0 for every period<=5, see MakeFlatBars derivation), break
   //--- at bar[5] with |break_price-target_price|=0.5 -> metric=0.25.
   //--- threshold=0.20 -> PASS -> overall_pass true; threshold=0.30 ->
   //--- FAIL -> overall_pass false. ---------------------------------------
   void T98_BreakQualityIncludePassFail()
     {
      MqlRates bars[]; MakeFlatBars(bars, MakeTime(2026,3,2,10,0), 6, 1.0);
      GZ_Setup s = MakeBrokenSetup(1, GZ_LEG_BULLISH, 90.0, 100.0, 102.0, 100.5, bars[5].time);

      CGZTimeEngine te(m_logger); GZ_TimeConfig tc; tc.Default(); te.Configure(tc);
      CGZSessionEngine se;
      CGZFilterEngine fe(m_logger);

      GZ_FilterSetConfig cfgPass; cfgPass.Default();
      cfgPass.mode[GZ_FILTER_BREAK_QUALITY] = GZ_FILTER_INCLUDE;
      cfgPass.atr_period = 5;
      cfgPass.break_quality_min_atr_mult = 0.20;
      GZ_SetupFilterOutcome outPass;
      fe.Evaluate(s, bars, cfgPass, te, se, outPass);

      GZ_FilterSetConfig cfgFail = cfgPass;
      cfgFail.break_quality_min_atr_mult = 0.30;
      GZ_SetupFilterOutcome outFail;
      fe.Evaluate(s, bars, cfgFail, te, se, outFail);

      bool ok = outPass.overall_pass && !outFail.overall_pass &&
                MathAbs(outPass.results[GZ_FILTER_BREAK_QUALITY].metric_value-0.25)<0.0001;
      AddResult("T98", ok, StringFormat("metric=%.4f pass_at_0.20=%s pass_at_0.30=%s",
                outPass.results[GZ_FILTER_BREAK_QUALITY].metric_value,
                outPass.overall_pass?"true":"false", outFail.overall_pass?"true":"false"));
     }

   //--- T99: NOT_AVAILABLE must never silently become PASS (explicit
   //--- Roadmap requirement) - with only 2 bars fed, ATR(period=5) is not
   //--- ready (idx<period), so Break Quality reports NOT_AVAILABLE; with
   //--- the filter enabled (either INCLUDE or EXCLUDE) the setup must be
   //--- rejected, never waved through. -----------------------------------
   void T99_NotAvailableNeverAutoPasses()
     {
      MqlRates bars[]; MakeFlatBars(bars, MakeTime(2026,3,2,10,0), 2, 1.0);
      GZ_Setup s = MakeBrokenSetup(1, GZ_LEG_BULLISH, 90.0, 100.0, 102.0, 100.5, bars[1].time);

      CGZTimeEngine te(m_logger); GZ_TimeConfig tc; tc.Default(); te.Configure(tc);
      CGZSessionEngine se;
      CGZFilterEngine fe(m_logger);

      GZ_FilterSetConfig cfgInc; cfgInc.Default();
      cfgInc.atr_period = 5;
      cfgInc.mode[GZ_FILTER_BREAK_QUALITY] = GZ_FILTER_INCLUDE;
      GZ_SetupFilterOutcome outInc;
      fe.Evaluate(s, bars, cfgInc, te, se, outInc);

      GZ_FilterSetConfig cfgExc = cfgInc;
      cfgExc.mode[GZ_FILTER_BREAK_QUALITY] = GZ_FILTER_EXCLUDE;
      GZ_SetupFilterOutcome outExc;
      fe.Evaluate(s, bars, cfgExc, te, se, outExc);

      bool ok = (outInc.results[GZ_FILTER_BREAK_QUALITY].result==GZ_FILTER_NOT_AVAILABLE) &&
                (outExc.results[GZ_FILTER_BREAK_QUALITY].result==GZ_FILTER_NOT_AVAILABLE) &&
                !outInc.overall_pass && !outExc.overall_pass;
      AddResult("T99", ok, StringFormat("result=%s include_pass=%s exclude_pass=%s (both must be false)",
                GZFilterResultToString(outInc.results[GZ_FILTER_BREAK_QUALITY].result),
                outInc.overall_pass?"true":"false", outExc.overall_pass?"true":"false"));
     }

   //--- T100: EXCLUDE mode inverts INCLUDE - same setup/bars as T98
   //--- (underlying result PASS at threshold 0.20): EXCLUDE keeps only
   //--- setups whose result is FAIL, so overall_pass must be FALSE at
   //--- 0.20 and TRUE at 0.30 (mirror image of T98's INCLUDE results). --
   void T100_ExcludeModeInverts()
     {
      MqlRates bars[]; MakeFlatBars(bars, MakeTime(2026,3,2,10,0), 6, 1.0);
      GZ_Setup s = MakeBrokenSetup(1, GZ_LEG_BULLISH, 90.0, 100.0, 102.0, 100.5, bars[5].time);

      CGZTimeEngine te(m_logger); GZ_TimeConfig tc; tc.Default(); te.Configure(tc);
      CGZSessionEngine se;
      CGZFilterEngine fe(m_logger);

      GZ_FilterSetConfig cfg020; cfg020.Default();
      cfg020.atr_period = 5;
      cfg020.mode[GZ_FILTER_BREAK_QUALITY] = GZ_FILTER_EXCLUDE;
      cfg020.break_quality_min_atr_mult = 0.20; // underlying PASS (metric 0.25>=0.20)
      GZ_SetupFilterOutcome out020;
      fe.Evaluate(s, bars, cfg020, te, se, out020);

      GZ_FilterSetConfig cfg030 = cfg020;
      cfg030.break_quality_min_atr_mult = 0.30; // underlying FAIL (metric 0.25<0.30)
      GZ_SetupFilterOutcome out030;
      fe.Evaluate(s, bars, cfg030, te, se, out030);

      bool ok = !out020.overall_pass && out030.overall_pass;
      AddResult("T100", ok, StringFormat("exclude_at_0.20(underlying PASS)=%s exclude_at_0.30(underlying FAIL)=%s",
                out020.overall_pass?"true":"false", out030.overall_pass?"true":"false"));
     }

   //--- T101: Volume filter - trailing-average threshold, using a 5-bar
   //--- lookback so the arithmetic is exact by hand (see design note in
   //--- header comment above MakeFlatBars): bars[1..4]=100 tick_volume,
   //--- break bar[5]=300 -> window[1..5] avg=(4*100+300)/5=140 ->
   //--- metric=300/140=2.142857 -> PASS at mult=2.0, FAIL at mult=2.5. --
   void T101_VolumeThreshold()
     {
      MqlRates bars[]; MakeFlatBars(bars, MakeTime(2026,3,2,10,0), 6, 1.0, 100);
      bars[5].tick_volume = 300;
      GZ_Setup s = MakeBrokenSetup(1, GZ_LEG_BULLISH, 90.0, 100.0, 102.0, 100.5, bars[5].time);

      CGZTimeEngine te(m_logger); GZ_TimeConfig tc; tc.Default(); te.Configure(tc);
      CGZSessionEngine se;
      CGZFilterEngine fe(m_logger);

      GZ_FilterSetConfig cfgPass; cfgPass.Default();
      cfgPass.volume_lookback = 5;
      cfgPass.mode[GZ_FILTER_VOLUME] = GZ_FILTER_INCLUDE;
      cfgPass.volume_min_mult = 2.0;
      GZ_SetupFilterOutcome outPass;
      fe.Evaluate(s, bars, cfgPass, te, se, outPass);

      GZ_FilterSetConfig cfgFail = cfgPass;
      cfgFail.volume_min_mult = 2.5;
      GZ_SetupFilterOutcome outFail;
      fe.Evaluate(s, bars, cfgFail, te, se, outFail);

      bool ok = outPass.overall_pass && !outFail.overall_pass &&
                MathAbs(outPass.results[GZ_FILTER_VOLUME].metric_value-(300.0/140.0))<0.0001;
      AddResult("T101", ok, StringFormat("metric=%.4f pass_at_2.0=%s pass_at_2.5=%s",
                outPass.results[GZ_FILTER_VOLUME].metric_value,
                outPass.overall_pass?"true":"false", outFail.overall_pass?"true":"false"));
     }

   //--- T102: Volatility filter - current ATR(period=3) vs baseline
   //--- ATR(lookback=6). bars[1..3] half_range=2 (TR=4), bars[4..6]
   //--- half_range=1 (TR=2): baseline avg over [1..6]=(4+4+4+2+2+2)/6=3.0,
   //--- current avg over [4..6]=(2+2+2)/3=2.0 -> ratio=0.6667 -> PASS in
   //--- [0.5,0.8], FAIL when min raised to 0.7 (too quiet vs baseline). --
   void T102_VolatilityBand()
     {
      MqlRates bars[]; ArrayResize(bars,7);
      datetime t0 = MakeTime(2026,3,2,10,0);
      bars[0] = MakeBar(t0+0*300, 100,102,98,100);    // half_range=2, excluded from both windows
      bars[1] = MakeBar(t0+1*300, 100,102,98,100);    // half_range=2
      bars[2] = MakeBar(t0+2*300, 100,102,98,100);    // half_range=2
      bars[3] = MakeBar(t0+3*300, 100,102,98,100);    // half_range=2
      bars[4] = MakeBar(t0+4*300, 100,101,99,100);    // half_range=1
      bars[5] = MakeBar(t0+5*300, 100,101,99,100);    // half_range=1
      bars[6] = MakeBar(t0+6*300, 100,101,99,100);    // half_range=1 (break bar, idx=6)
      GZ_Setup s = MakeBrokenSetup(1, GZ_LEG_BULLISH, 90.0, 100.0, 102.0, 100.5, bars[6].time);

      CGZTimeEngine te(m_logger); GZ_TimeConfig tc; tc.Default(); te.Configure(tc);
      CGZSessionEngine se;
      CGZFilterEngine fe(m_logger);

      GZ_FilterSetConfig cfgPass; cfgPass.Default();
      cfgPass.atr_period = 3;
      cfgPass.volatility_lookback = 6;
      cfgPass.mode[GZ_FILTER_VOLATILITY] = GZ_FILTER_INCLUDE;
      cfgPass.volatility_min_mult = 0.5;
      cfgPass.volatility_max_mult = 0.8;
      GZ_SetupFilterOutcome outPass;
      fe.Evaluate(s, bars, cfgPass, te, se, outPass);

      GZ_FilterSetConfig cfgFail = cfgPass;
      cfgFail.volatility_min_mult = 0.7; // 0.667 < 0.7 -> too quiet
      GZ_SetupFilterOutcome outFail;
      fe.Evaluate(s, bars, cfgFail, te, se, outFail);

      double expected = 2.0/3.0;
      bool ok = outPass.overall_pass && !outFail.overall_pass &&
                MathAbs(outPass.results[GZ_FILTER_VOLATILITY].metric_value-expected)<0.0001;
      AddResult("T102", ok, StringFormat("metric=%.4f (expected %.4f) pass_in_band=%s fail_out_of_band=%s",
                outPass.results[GZ_FILTER_VOLATILITY].metric_value, expected,
                outPass.overall_pass?"true":"false", outFail.overall_pass?"true":"false"));
     }

   //--- T103: Session filter reuses the SAME CGZTimeEngine/CGZSessionEngine
   //--- machinery every other phase uses (GZ_Session.mqh) - break inside
   //--- [16:30,20:30) BROKER -> PASS; break outside -> FAIL. --------------
   void T103_SessionFilterInsideOutside()
     {
      MqlRates barsIn[]; MakeFlatBars(barsIn, MakeTime(2026,3,2,17,0), 3, 1.0);   // 17:00 - inside
      MqlRates barsOut[]; MakeFlatBars(barsOut, MakeTime(2026,3,2,10,0), 3, 1.0); // 10:00 - outside
      GZ_Setup sIn  = MakeBrokenSetup(1, GZ_LEG_BULLISH, 90.0, 100.0, 102.0, 100.5, barsIn[2].time);
      GZ_Setup sOut = MakeBrokenSetup(2, GZ_LEG_BULLISH, 90.0, 100.0, 102.0, 100.5, barsOut[2].time);

      CGZTimeEngine te(m_logger);
      GZ_TimeConfig tc; tc.Default(); tc.broker_offset_known=true; te.Configure(tc);
      CGZSessionEngine se;
      CGZFilterEngine fe(m_logger);

      GZ_FilterSetConfig cfg; cfg.Default();
      cfg.mode[GZ_FILTER_SESSION] = GZ_FILTER_INCLUDE;
      cfg.session_profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,16,30,20,30,true,true);

      GZ_SetupFilterOutcome outIn, outOut;
      fe.Evaluate(sIn,  barsIn,  cfg, te, se, outIn);
      fe.Evaluate(sOut, barsOut, cfg, te, se, outOut);

      bool ok = outIn.overall_pass && !outOut.overall_pass &&
                (outIn.results[GZ_FILTER_SESSION].result==GZ_FILTER_PASS) &&
                (outOut.results[GZ_FILTER_SESSION].result==GZ_FILTER_FAIL);
      AddResult("T103", ok, StringFormat("inside=%s(%s) outside=%s(%s)",
                GZFilterResultToString(outIn.results[GZ_FILTER_SESSION].result), outIn.overall_pass?"pass":"reject",
                GZFilterResultToString(outOut.results[GZ_FILTER_SESSION].result), outOut.overall_pass?"pass":"reject"));
     }

   //--- T104: VWAP / M15 Context / News are RESERVED - always
   //--- NOT_AVAILABLE for ANY setup (design note 1, GZ_FilterTypes.mqh),
   //--- harmless while OFF (default) but rejecting (never fabricating a
   //--- PASS) the instant any one of them is turned INCLUDE/EXCLUDE. ----
   void T104_ReservedFiltersAlwaysNotAvailable()
     {
      MqlRates bars[]; MakeFlatBars(bars, MakeTime(2026,3,2,17,0), 6, 1.0);
      GZ_Setup s = MakeBrokenSetup(1, GZ_LEG_BULLISH, 90.0, 100.0, 102.0, 100.5, bars[5].time);

      CGZTimeEngine te(m_logger); GZ_TimeConfig tc; tc.Default(); tc.broker_offset_known=true; te.Configure(tc);
      CGZSessionEngine se;
      CGZFilterEngine fe(m_logger);

      GZ_FilterSetConfig cfgOff; cfgOff.Default(); // VWAP/M15/News all OFF
      GZ_SetupFilterOutcome outOff;
      fe.Evaluate(s, bars, cfgOff, te, se, outOff);

      GZ_FilterSetConfig cfgOn = cfgOff;
      cfgOn.mode[GZ_FILTER_VWAP] = GZ_FILTER_INCLUDE;
      GZ_SetupFilterOutcome outOn;
      fe.Evaluate(s, bars, cfgOn, te, se, outOn);

      bool reserved_na = (outOff.results[GZ_FILTER_VWAP].result==GZ_FILTER_NOT_AVAILABLE) &&
                          (outOff.results[GZ_FILTER_M15_CONTEXT].result==GZ_FILTER_NOT_AVAILABLE) &&
                          (outOff.results[GZ_FILTER_NEWS].result==GZ_FILTER_NOT_AVAILABLE);
      bool ok = reserved_na && outOff.overall_pass && !outOn.overall_pass;
      AddResult("T104", ok, StringFormat("reserved_always_NA=%s off_harmless=%s on_rejects=%s",
                reserved_na?"true":"false", outOff.overall_pass?"true":"false", (!outOn.overall_pass)?"true":"false"));
     }

   //--- T105: Determinism - identical setup+bars+cfg, evaluated twice,
   //--- produce field-for-field identical outcomes (every metric_value,
   //--- every result, overall_pass). --------------------------------------
   void T105_FilterEngineDeterminism()
     {
      MqlRates bars[]; MakeFlatBars(bars, MakeTime(2026,3,2,17,0), 6, 1.0);
      bars[5].tick_volume = 250;
      GZ_Setup s = MakeBrokenSetup(1, GZ_LEG_BULLISH, 90.0, 100.0, 102.0, 100.5, bars[5].time);

      CGZTimeEngine te(m_logger); GZ_TimeConfig tc; tc.Default(); tc.broker_offset_known=true; te.Configure(tc);
      CGZSessionEngine se;
      CGZFilterEngine fe(m_logger);

      GZ_FilterSetConfig cfg; cfg.Default();
      cfg.mode[GZ_FILTER_BREAK_QUALITY] = GZ_FILTER_INCLUDE;
      cfg.mode[GZ_FILTER_VOLUME]        = GZ_FILTER_INCLUDE;
      cfg.mode[GZ_FILTER_SESSION]       = GZ_FILTER_EXCLUDE;
      cfg.session_profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,16,30,20,30,true,true);

      GZ_SetupFilterOutcome outA, outB;
      fe.Evaluate(s, bars, cfg, te, se, outA);
      fe.Evaluate(s, bars, cfg, te, se, outB);

      bool ok = (outA.overall_pass==outB.overall_pass);
      for(int i=0;i<GZ_FILTER_COUNT && ok;i++)
         ok = (outA.results[i].result==outB.results[i].result) &&
              (MathAbs(outA.results[i].metric_value-outB.results[i].metric_value)<0.00001);
      AddResult("T105", ok, StringFormat("passA=%s passB=%s", outA.overall_pass?"true":"false", outB.overall_pass?"true":"false"));
     }

   //--- T106: CGZMetricsEngine::ComputeFiltered() - a WITH/WITHOUT
   //--- population diff. 4 closed trades (setup_id==trade_id, via
   //--- AddClosedJournalTrade), realized_r = 1,-1,2,-2. Mask keeps
   //--- setups #1 and #3 only (both winners: net_r=3, trade_count=2),
   //--- excludes #2/#4 (both losers). Unfiltered stays 4 trades net_r=0;
   //--- filtered must be exactly the #1/#3 subset - proving the mask is
   //--- honored per-entry and the unfiltered Compute() is unaffected. ---
   void T106_MetricsComputeFilteredDiff()
     {
      CGZJournalEngine j(m_logger); j.Init();
      datetime t0 = MakeTime(2026,3,3,9,0);
      AddClosedJournalTrade(j, 1, GZ_LEG_BULLISH, t0,          t0+60,          1.0);
      AddClosedJournalTrade(j, 2, GZ_LEG_BULLISH, t0+3600,     t0+3600+60,    -1.0);
      AddClosedJournalTrade(j, 3, GZ_LEG_BULLISH, t0+7200,     t0+7200+60,     2.0);
      AddClosedJournalTrade(j, 4, GZ_LEG_BULLISH, t0+10800,    t0+10800+60,   -2.0);

      CGZTimeEngine te(m_logger); GZ_TimeConfig tc; tc.Default(); te.Configure(tc);
      CGZSessionEngine se;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,23,59,true,true);
      CGZMetricsEngine metrics(m_logger);

      GZ_MetricsSummary before;
      metrics.Compute(j, te, se, profile, before);

      bool mask[4] = {true, false, true, false};
      GZ_MetricsSummary after;
      metrics.ComputeFiltered(j, te, se, profile, mask, after);

      GZ_FilterDiagnostics diag; diag.Clear();
      diag.available     = true;
      diag.trades_before  = before.trade.trade_count;
      diag.trades_after   = after.trade.trade_count;
      diag.trade_count_delta = after.trade.trade_count - before.trade.trade_count;

      bool ok = (before.trade.trade_count==4) && (MathAbs(before.trade.net_r-0.0)<0.0001) &&
                (after.trade.trade_count==2) && (MathAbs(after.trade.net_r-3.0)<0.0001) &&
                (after.trade.winners==2) && (after.trade.losers==0) &&
                (diag.trades_before==4) && (diag.trades_after==2) && (diag.trade_count_delta==-2);
      AddResult("T106", ok, StringFormat("before: n=%d net_r=%.3f | after(masked): n=%d net_r=%.3f winners=%d",
                before.trade.trade_count, before.trade.net_r, after.trade.trade_count, after.trade.net_r, after.trade.winners));
     }

   //--- Run everything ----------------------------------------------------------------
   void RunAll()
     {
      ArrayResize(m_results,0);
      T01_OHLCValidation();
      T02_DuplicateTimestamp();
      T03_TimestampOrdering();
      T04_ExpectedMarketGap();
      T05_UnexpectedGap();
      T06_M1M5Alignment();
      T07_BrokerTime();
      T08_UtcConversion();
      T09_NyStandardTime();
      T10_NyDaylightTime();
      T11_DstTransition();
      T12_SessionStartBoundary();
      T13_SessionEndBoundary();
      T14_SessionMiddle();
      T15_OutsideSession();
      T16_OvernightSession();
      T17_DateRange();
      T18_Determinism();
      T19_SwingHighDetection();
      T20_SwingLowDetection();
      T21_NoLookahead();
      T22_PivotStrengthVariants();
      T23_SwingDeterminism();
      T24_LegCreationBaseline();
      T25_LegDirectionBearish();
      T26_NoLegOnFirstSwing();
      T27_ExtremeTrackingNoLookahead();
      T28_CloseBreakBaseline();
      T29_WickBreakVariant();
      T30_BreakBufferAtr();
      T31_AtrCorrectness();
      T32_LegVariantMinDistance();
      T33_LegBreakDeterminism();
      T34_BreakNoLookahead();
      T35_FibPriceBullish();
      T36_FibPriceBearish();
      T37_FibZoneOverlap();
      T38_SetupCreatedOnLegDetected();
      T39_SetupLocksAndActivatesFib();
      T40_SetupWaitingEntryOnZoneTouch();
      T41_NewValidSetupCancelsOlder();
      T42_OppositeBreakCancels();
      T43_SessionEndCancels();
      T44_DataEndCancelsRemaining();
      T45_SetupDeterminism();
      T46_EntryTouchTriggersAndFills();
      T47_LimitFillsExactlyAtLevelNoSlippage();
      T48_PenetrationBufferRequired();
      T49_CloseConfirmationRequiresConsecutiveCloses();
      T50_M1ConfirmationRequiresConsecutiveM1Closes();
      T51_InvalidPenetrationCancelsSetup();
      T52_NoEntryBeforeWaitingEntryGate();
      T53_SimulatorNoLookaheadAcrossM1M5Boundary();
      T54_SimulatorDeterminism();
      T55_ExitStructureSLAndTP();
      T56_ExitAtrSLWithFallback();
      T57_TpHitExit();
      T58_SlHitExit();
      T59_BreakEvenArmThenExit();
      T60_IntrabarConflictPolicy();
      T61_SessionExit();
      T62_DataEndForceClose();
      T63_InitialRiskAndRealizedRSign();
      T64_ExitDeterminism();
      T65_JournalMaeMfeTracking();
      T66_JournalReachMatrixTiming();
      T67_JournalStopsAfterClose();
      T68_JournalZeroRiskGuardAndFinalize();
      T69_LedgerValidSetupRecordedOnce();
      T70_LedgerCancelledVsInvalidatedClassification();
      T71_LedgerEntryExitFromFullRun();
      T72_LedgerReservedTypesNeverEmitted();
      T73_JournalNoLookaheadTiming();
      T74_JournalAndLedgerDeterminism();
      T75_MetricsTradeStatsBaseline();
      T76_MetricsProfitFactorUndefined();
      T77_MetricsMaxDrawdown();
      T78_MetricsWinLoseStreaks();
      T79_MetricsBehaviorAverages();
      T80_MetricsBreakdownByDirection();
      T81_MetricsBreakdownBySession();
      T82_MetricsBreakdownByHourDowMonth();
      T83_MetricsOpenTradesExcluded();
      T84_MetricsFilterDiagnosticsReservedStub();
      T85_MetricsDateRangeSpan();
      T86_MetricsDeterminism();
      T87_ExperimentIdSequencing();
      T88_ExperimentNoM5DataWarning();
      T89_ExperimentFullPipelineFromRawData();
      T90_ExperimentNoTradesProducedWarning();
      T91_ExperimentSweepByPivotStrength();
      T92_ExperimentBatchSizeCapRejection();
      T93_ExperimentBatchWithinCapAndEmptyBatch();
      T94_ExperimentDeterminism();
      T95_ExperimentCallerSuppliedFieldsPassThrough();
      T96_ExperimentFullConfigRoundTrip();
      T97_FilterOffNeverGates();
      T98_BreakQualityIncludePassFail();
      T99_NotAvailableNeverAutoPasses();
      T100_ExcludeModeInverts();
      T101_VolumeThreshold();
      T102_VolatilityBand();
      T103_SessionFilterInsideOutside();
      T104_ReservedFiltersAlwaysNotAvailable();
      T105_FilterEngineDeterminism();
      T106_MetricsComputeFilteredDiff();
     }

   int               PassCount() const
     {
      int c=0;
      for(int i=0;i<ArraySize(m_results);i++) if(m_results[i].passed) c++;
      return c;
     }

   int               FailCount() const { return ResultCount()-PassCount(); }
  };

#endif // __GZ_TESTHARNESS_MQH__
