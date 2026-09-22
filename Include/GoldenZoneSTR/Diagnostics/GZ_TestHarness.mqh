//+------------------------------------------------------------------+
//| GZ_TestHarness.mqh                                                 |
//| GoldenZone STR - Automated Test Harness                           |
//| Phase 1 (T01-T18): Data Layer + Validator + Time Engine           |
//| Phase 2 (T19-T23): M5 Structure Engine (swing detection)          |
//| Phase 3 (T24-T34): Leg Engine + Break Engine                      |
//| Phase 4 (T35-T45): Fibonacci Engine + Setup State Machine         |
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
