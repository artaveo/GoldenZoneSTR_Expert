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

   //--- T72: the RESERVED ledger event types (Rejection/FilterResult -
   //--- DEFERRED TO PHASE 10) are never emitted anywhere in this build,
   //--- even after a full pipeline run that produces real setups/trades/
   //--- exits. --------------------------------------------------------------
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
