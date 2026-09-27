//+------------------------------------------------------------------+
//| GZ_ConcurrencyTests.mqh                                          |
//| GoldenZone STR - Phase "Concurrent Same-Direction Setups +       |
//| Opposite-Break Survival" (+ its Daily Loss Limit / Max Concurrent |
//| Open Trades follow-up) - T250-T263                                 |
//|                                                                    |
//| Synthetic data only, same discipline as GZ_FcisTests.mqh /        |
//| GZ_PartitionTests.mqh (own local MakeLeg/MakeSwing/MakeBar/        |
//| MakeTime helpers, AddResult, hooked into GZ_TestHarness.mqh's      |
//| RunAll() - each test suite class in this repo is self-contained   |
//| by convention).                                                    |
//|                                                                    |
//| T250-T256 cover Switch A (allow_concurrent_same_direction) and    |
//| Switch B (allow_survive_opposite_break) on CGZSetupStateMachine,  |
//| both independently and in combination, plus the peak-concurrency  |
//| diagnostics on CGZSetupStateMachine and CGZExitEngine - legs are  |
//| built by hand (GZ_Leg is a plain struct) since only OnLegCreated()/|
//| OnLegBroken() themselves are under test there.                     |
//|                                                                    |
//| T257-T263 cover the follow-up Daily Loss Limit / Max Concurrent    |
//| Open Trades gates on CGZEntryEngine/CGZTradeSimulator. T257-T261  |
//| test CGZEntryEngine's own gating in isolation (hand-built legs,   |
//| caller-computed booleans passed straight into OnBar()); T262-T263 |
//| test CGZTradeSimulator's day-rollover/realized-R bookkeeping      |
//| end-to-end through a real Run() call, so those two DO run legs    |
//| through the real CGZLegEngine/CGZBreakEngine pipeline (via         |
//| MakeSwing, mirroring GZ_FcisTests.mqh's own T236-style fixtures)  |
//| rather than hand-built GZ_Leg structs - no swing/leg-formation     |
//| math is changed by this phase, only exercised as a realistic       |
//| carrier for the new bar-count/day-boundary bookkeeping under test.|
//+------------------------------------------------------------------+
#ifndef __GZ_CONCURRENCY_TESTS_MQH__
#define __GZ_CONCURRENCY_TESTS_MQH__

#include "GZ_SetupStateMachine.mqh"
#include "..\Exit\GZ_ExitEngine.mqh"
#include "..\Entry\GZ_TradeSimulator.mqh"
#include "..\Leg\GZ_LegEngine.mqh"
#include "..\Leg\GZ_BreakEngine.mqh"
#include "..\Time\GZ_TimeEngine.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZConcurrencyTests
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

   MqlRates MakeBar(datetime t, double o, double h, double l, double c, int spread=1, long vol=100)
     {
      MqlRates r;
      r.time=t; r.open=o; r.high=h; r.low=l; r.close=c;
      r.tick_volume=vol; r.spread=spread; r.real_volume=0;
      return r;
     }

   //--- Used only by T262/T263 (which run legs through the real
   //--- CGZLegEngine/CGZBreakEngine pipeline) - mirrors GZ_FcisTests.mqh's
   //--- own MakeSwing() exactly.
   GZ_Swing MakeSwing(ENUM_GZ_SWING_DIR dir, double price, datetime pivot_t, datetime confirm_t, long id=1)
     {
      GZ_Swing s; s.Clear();
      s.id = id; s.direction = dir; s.price = price;
      s.pivot_time = pivot_t; s.detection_time = pivot_t; s.confirmation_time = confirm_t;
      s.pivot_strength = 2;
      return s;
     }

   //--- A hand-built, already-formed leg - no swing/leg-formation math
   //--- involved (out of scope for this phase - see header). Bullish:
   //--- origin=90 (low), extreme=110 (high). Bearish: origin=110 (high),
   //--- extreme=90 (low). Both directions therefore share the exact
   //--- same [90,110] price range, so fib-zone bars/prices used across
   //--- tests below apply to either direction unmodified.
   GZ_Leg MakeLeg(ENUM_GZ_LEG_DIR dir, long id, datetime confirm_time)
     {
      GZ_Leg leg; leg.Clear();
      leg.id                            = id;
      leg.direction                     = dir;
      leg.target_swing.confirmation_time= confirm_time;
      if(dir==GZ_LEG_BULLISH)
        {
         leg.origin_swing.price = 90.0;
         leg.extreme_price      = 110.0;
        }
      else
        {
         leg.origin_swing.price = 110.0;
         leg.extreme_price      = 90.0;
        }
      return leg;
     }

   //--- Same leg, now carrying break info (id must match the setup's
   //--- leg.id to update that setup - GZ_SetupStateMachine::OnLegBroken
   //--- looks it up via FindByLegId(); use an id with no matching setup
   //--- to exercise ONLY the opposite-direction cancellation loop, in
   //--- isolation from the "update the matching setup" branch).
   GZ_Leg MakeBrokenLeg(ENUM_GZ_LEG_DIR dir, long id, datetime break_time)
     {
      GZ_Leg leg = MakeLeg(dir, id, break_time-300);
      leg.broken     = true;
      leg.break_time = break_time;
      leg.break_price= (dir==GZ_LEG_BULLISH) ? leg.extreme_price : leg.extreme_price;
      return leg;
     }

   void T250_BothOffSameDirectionRegression()
     {
      datetime t0 = MakeTime(2026,2,1,10,0,0);
      CGZSetupStateMachine sm(m_logger);
      sm.Init(0.30,0.90); // both switches default OFF

      GZ_Leg leg1 = MakeLeg(GZ_LEG_BULLISH, 1, t0+300);
      int i1 = sm.OnLegCreated(leg1);
      GZ_Leg leg2 = MakeLeg(GZ_LEG_BULLISH, 2, t0+600);
      int i2 = sm.OnLegCreated(leg2);

      bool ok = (sm.SetupCount()==2) &&
                (sm.GetSetup(i1).state==GZ_SETUP_CANCELLED) && (sm.GetSetup(i1).cancel_reason==GZ_CANCEL_NEW_VALID_SETUP) &&
                (sm.GetSetup(i2).state==GZ_SETUP_LEG_DETECTED) &&
                (sm.WouldHaveCancelledSameDirectionCount()==0) &&
                (sm.PeakNonTerminalSetups()==1);
      AddResult("T250", ok, StringFormat(
         "REGRESSION both switches OFF: two same-direction legs -> setup#1 state=%s reason=%s, setup#2 state=%s, would_have_cancelled=%d, peak=%d (must be CANCELLED/NEW_VALID_SETUP, LEG_DETECTED, 0, 1)",
         sm.GetSetup(i1).StateToString(), sm.GetSetup(i1).CancelReasonToString(), sm.GetSetup(i2).StateToString(),
         (int)sm.WouldHaveCancelledSameDirectionCount(), sm.PeakNonTerminalSetups()));
     }

   void T251_SwitchAOnConcurrentSameDirection()
     {
      datetime t0 = MakeTime(2026,2,1,10,30,0);
      CGZSetupStateMachine sm(m_logger);
      sm.Init(0.30,0.90,true,false); // Switch A ON, Switch B OFF

      GZ_Leg leg1 = MakeLeg(GZ_LEG_BULLISH, 1, t0+300);
      int i1 = sm.OnLegCreated(leg1);
      GZ_Leg leg2 = MakeLeg(GZ_LEG_BULLISH, 2, t0+600);
      int i2 = sm.OnLegCreated(leg2);

      bool ok = (sm.SetupCount()==2) &&
                (sm.GetSetup(i1).state==GZ_SETUP_LEG_DETECTED) &&
                (sm.GetSetup(i2).state==GZ_SETUP_LEG_DETECTED) &&
                (sm.WouldHaveCancelledSameDirectionCount()==1) &&
                (sm.PeakNonTerminalSetups()==2);
      AddResult("T251", ok, StringFormat(
         "Switch A ON only: two same-direction legs -> BOTH survive concurrently, setup#1 state=%s setup#2 state=%s, would_have_cancelled=%d, peak=%d (must be LEG_DETECTED, LEG_DETECTED, 1, 2)",
         sm.GetSetup(i1).StateToString(), sm.GetSetup(i2).StateToString(),
         (int)sm.WouldHaveCancelledSameDirectionCount(), sm.PeakNonTerminalSetups()));
     }

   void T252_SwitchAIndependentOfOppositeBreak()
     {
      datetime t0 = MakeTime(2026,2,1,11,0,0);
      CGZSetupStateMachine sm(m_logger);
      sm.Init(0.30,0.90,true,false); // Switch A ON, Switch B OFF

      GZ_Leg leg1 = MakeLeg(GZ_LEG_BULLISH, 1, t0+300);
      int i1 = sm.OnLegCreated(leg1);
      GZ_Leg leg2 = MakeLeg(GZ_LEG_BEARISH, 2, t0+600); // opposite direction - same-direction rule (Switch A) never touches this
      int i2 = sm.OnLegCreated(leg2);
      bool bothSurviveCreation = (sm.SetupCount()==2) &&
                (sm.GetSetup(i1).state==GZ_SETUP_LEG_DETECTED) && (sm.GetSetup(i2).state==GZ_SETUP_LEG_DETECTED);

      GZ_Leg brokenLeg2 = MakeBrokenLeg(GZ_LEG_BEARISH, 2, t0+900); // leg2 itself breaks
      sm.OnLegBroken(brokenLeg2);

      // leg1 (bullish) is OPPOSITE of the bearish break -> must still be
      // cancelled (OPPOSITE_BREAK is governed ONLY by Switch B, which is
      // OFF here) - proving Switch A has zero effect on this mechanism.
      bool ok = bothSurviveCreation &&
                (sm.GetSetup(i1).state==GZ_SETUP_CANCELLED) && (sm.GetSetup(i1).cancel_reason==GZ_CANCEL_OPPOSITE_BREAK) &&
                (sm.GetSetup(i2).state==GZ_SETUP_FIB_ACTIVE); // leg2's own setup progresses via the normal break cascade
      AddResult("T252", ok, StringFormat(
         "Switch A ON, Switch B OFF: opposite-direction leg creation unaffected by A (both formed), then leg2's break still cancels leg1 via OPPOSITE_BREAK -> setup#1 state=%s reason=%s, setup#2 state=%s",
         sm.GetSetup(i1).StateToString(), sm.GetSetup(i1).CancelReasonToString(), sm.GetSetup(i2).StateToString()));
     }

   void T253_SwitchBOffOppositeBreakRegression()
     {
      datetime t0 = MakeTime(2026,2,1,11,30,0);
      CGZSetupStateMachine sm(m_logger);
      sm.Init(0.30,0.90); // both switches default OFF

      GZ_Leg leg1 = MakeLeg(GZ_LEG_BULLISH, 1, t0+300);
      int i1 = sm.OnLegCreated(leg1);

      GZ_Leg brokenOpp = MakeBrokenLeg(GZ_LEG_BEARISH, 999, t0+600); // no matching setup - isolates the opposite-cancel loop
      sm.OnLegBroken(brokenOpp);

      bool ok = (sm.GetSetup(i1).state==GZ_SETUP_CANCELLED) && (sm.GetSetup(i1).cancel_reason==GZ_CANCEL_OPPOSITE_BREAK) &&
                (sm.WouldHaveCancelledOppositeBreakCount()==0);
      AddResult("T253", ok, StringFormat(
         "REGRESSION Switch B OFF: opposite-direction break -> setup state=%s reason=%s would_have_cancelled=%d (must be CANCELLED/OPPOSITE_BREAK/0)",
         sm.GetSetup(i1).StateToString(), sm.GetSetup(i1).CancelReasonToString(), (int)sm.WouldHaveCancelledOppositeBreakCount()));
     }

   void T254_SwitchBOnSurvivesOppositeBreak()
     {
      datetime t0 = MakeTime(2026,2,1,12,0,0);
      CGZSetupStateMachine sm(m_logger);
      sm.Init(0.30,0.90,false,true); // Switch B ON

      GZ_Leg leg1 = MakeLeg(GZ_LEG_BULLISH, 1, t0+300);
      int i1 = sm.OnLegCreated(leg1);

      GZ_Leg brokenOpp = MakeBrokenLeg(GZ_LEG_BEARISH, 999, t0+600); // no matching setup
      sm.OnLegBroken(brokenOpp);
      bool survivedBreak = (sm.GetSetup(i1).state==GZ_SETUP_LEG_DETECTED) && (sm.WouldHaveCancelledOppositeBreakCount()==1);

      // "still progressing normally afterward (can still reach entry)":
      // break leg1's OWN leg next -> normal BREAK_CONFIRMED->LEG_LOCKED->
      // FIB_ACTIVE cascade, then a bar touching the zone -> WAITING_ENTRY.
      GZ_Leg brokenLeg1 = MakeBrokenLeg(GZ_LEG_BULLISH, 1, t0+900);
      sm.OnLegBroken(brokenLeg1);
      bool reachedFibActive = (sm.GetSetup(i1).state==GZ_SETUP_FIB_ACTIVE);

      MqlRates touchBar = MakeBar(t0+1200, 99,100,95,99); // inside [90,110] zone at 0.30-0.90 ratios
      sm.OnBar(touchBar, true, false);
      bool reachedWaitingEntry = (sm.GetSetup(i1).state==GZ_SETUP_WAITING_ENTRY);

      bool ok = survivedBreak && reachedFibActive && reachedWaitingEntry;
      AddResult("T254", ok, StringFormat(
         "Switch B ON only: opposite-direction break does NOT cancel (would_have_cancelled=%d), setup keeps progressing to state=%s after its own break, then =%s after zone touch (must be 1, FIB_ACTIVE, WAITING_ENTRY)",
         (int)sm.WouldHaveCancelledOppositeBreakCount(), sm.GetSetup(i1).StateToString(), sm.GetSetup(i1).StateToString()));
     }

   void T255_BothOnNoInteraction()
     {
      datetime t0 = MakeTime(2026,2,1,12,30,0);
      CGZSetupStateMachine sm(m_logger);
      sm.Init(0.30,0.90,true,true); // both switches ON

      GZ_Leg leg1 = MakeLeg(GZ_LEG_BULLISH, 1, t0+300);
      int i1 = sm.OnLegCreated(leg1);
      GZ_Leg leg2 = MakeLeg(GZ_LEG_BULLISH, 2, t0+600); // same direction -> Switch A keeps both
      int i2 = sm.OnLegCreated(leg2);
      bool sameDirSurvived = (sm.GetSetup(i1).state==GZ_SETUP_LEG_DETECTED) && (sm.GetSetup(i2).state==GZ_SETUP_LEG_DETECTED) &&
                             (sm.WouldHaveCancelledSameDirectionCount()==1);

      GZ_Leg brokenOpp = MakeBrokenLeg(GZ_LEG_BEARISH, 999, t0+900); // opposite of both -> Switch B keeps both
      sm.OnLegBroken(brokenOpp);
      bool oppositeSurvived = (sm.GetSetup(i1).state==GZ_SETUP_LEG_DETECTED) && (sm.GetSetup(i2).state==GZ_SETUP_LEG_DETECTED) &&
                              (sm.WouldHaveCancelledOppositeBreakCount()==2);

      bool ok = (sm.SetupCount()==2) && sameDirSurvived && oppositeSurvived;
      AddResult("T255", ok, StringFormat(
         "Both switches ON: same-direction pair both survive (would_have_cancelled_same=%d), then an opposite-direction break survives both (would_have_cancelled_opp=%d), setups=%d, no cross-interaction/regression (must be 1, 2, 2)",
         (int)sm.WouldHaveCancelledSameDirectionCount(), (int)sm.WouldHaveCancelledOppositeBreakCount(), sm.SetupCount()));
     }

   //--- Used only by T257-T261 (isolated CGZEntryEngine gating tests) -
   //--- builds a setup at exactly WAITING_ENTRY via the REAL Leg/Break
   //--- pipeline. Mirrors GZ_FcisTests.mqh's own BuildWaitingEntryFixture()
   //--- exactly (each test suite in this repo keeps its own private copy
   //--- of shared fixtures by convention - see this file's header).
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

   void T256_ExitEnginePeakOpenTradesDiagnostic()
     {
      GZ_ExitConfig cfg; cfg.Default();
      CGZExitEngine exitEngine(m_logger);
      exitEngine.Init(cfg);

      GZ_Leg legLong = MakeLeg(GZ_LEG_BULLISH, 1, MakeTime(2026,2,1,13,0,0));
      GZ_Trade trLong; trLong.Clear();
      trLong.id=1; trLong.setup_id=1; trLong.direction=GZ_LEG_BULLISH; trLong.entry_price=100.0;
      trLong.entry_time=MakeTime(2026,2,1,13,1,0); trLong.entry_model=GZ_ENTRY_TOUCH; trLong.fib_level=0.618;
      exitEngine.OnTradeEntered(trLong, legLong, 0.0, false);
      bool peakAfterFirst = (exitEngine.PeakOpenTrades()==1);

      GZ_Leg legShort = MakeLeg(GZ_LEG_BEARISH, 2, MakeTime(2026,2,1,13,5,0));
      GZ_Trade trShort; trShort.Clear();
      trShort.id=2; trShort.setup_id=2; trShort.direction=GZ_LEG_BEARISH; trShort.entry_price=100.0;
      trShort.entry_time=MakeTime(2026,2,1,13,6,0); trShort.entry_model=GZ_ENTRY_TOUCH; trShort.fib_level=0.618;
      exitEngine.OnTradeEntered(trShort, legShort, 0.0, false);
      bool peakAfterSecond = (exitEngine.PeakOpenTrades()==2);

      // close the LONG trade (SL hit) - peak must NOT decrease
      MqlRates slBar = MakeBar(MakeTime(2026,2,1,13,10,0), 89,90,85,89);
      exitEngine.OnBar(slBar, true, false);
      bool peakHoldsAfterClose = (exitEngine.PeakOpenTrades()==2) && (exitEngine.OpenCount()==1);

      bool ok = peakAfterFirst && peakAfterSecond && peakHoldsAfterClose;
      AddResult("T256", ok, StringFormat(
         "PeakOpenTrades diagnostic: 1 after first entry, 2 after second entry, stays 2 after one closes (open_count now=%d) (must be true,true,true)",
         exitEngine.OpenCount()));
     }

   //--- Follow-up switches (T257-T262): Daily Loss Limit + Max Concurrent
   //--- Open Trades, on top of the two switches above. Both live on
   //--- CGZEntryEngine ("skip the trigger this bar", same semantics as
   //--- allow_entry_this_bar / the Session Hour Gate - see that file's
   //--- OnBar() header). T257-T261 test CGZEntryEngine's own gating in
   //--- isolation (the caller-computed booleans passed straight in);
   //--- T262 tests CGZTradeSimulator's own day-rollover/realized-R
   //--- bookkeeping end-to-end through a real Run() call.

   void T257_MaxConcurrentOffRegression()
     {
      datetime t0 = MakeTime(2026,2,2,10,0,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime=0;
      BuildWaitingEntryFixture(sm, t0, waitTime);
      GZ_EntryConfig cfg; cfg.Default(); // use_max_concurrent_trades default false
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);
      MqlRates bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2, 1);
      // current_open_trades_count deliberately huge - must have zero effect while the gate is OFF
      entryEngine.OnBar(sm, bar, true, 0.0, false, true, false, 999);
      bool ok = (entryEngine.TradeCount()==1) && (entryEngine.BlockedByMaxConcurrentCount()==0);
      AddResult("T257", ok, StringFormat(
         "REGRESSION use_max_concurrent_trades=false (default): current_open_trades_count=999 has no effect -> trades=%d blocked=%d (must be 1, 0)",
         entryEngine.TradeCount(), (int)entryEngine.BlockedByMaxConcurrentCount()));
     }

   void T258_MaxConcurrentBlocksAtCap()
     {
      datetime t0 = MakeTime(2026,2,2,10,30,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime=0;
      BuildWaitingEntryFixture(sm, t0, waitTime);
      GZ_EntryConfig cfg; cfg.Default();
      cfg.use_max_concurrent_trades = true;
      cfg.max_concurrent_trades     = 3;
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);
      MqlRates bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2, 1);
      entryEngine.OnBar(sm, bar, true, 0.0, false, true, false, 3); // already AT the cap
      GZ_Setup s = sm.GetSetup(0);
      bool ok = (entryEngine.TradeCount()==0) && (entryEngine.BlockedByMaxConcurrentCount()==1) && (s.state==GZ_SETUP_WAITING_ENTRY);
      AddResult("T258", ok, StringFormat(
         "max_concurrent_trades=3, current_open_trades_count=3 (at cap) -> trigger suppressed: trades=%d blocked=%d setup state=%s (must be 0, 1, WAITING_ENTRY)",
         entryEngine.TradeCount(), (int)entryEngine.BlockedByMaxConcurrentCount(), s.StateToString()));
     }

   void T259_MaxConcurrentAllowsBelowCap()
     {
      datetime t0 = MakeTime(2026,2,2,11,0,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime=0;
      BuildWaitingEntryFixture(sm, t0, waitTime);
      GZ_EntryConfig cfg; cfg.Default();
      cfg.use_max_concurrent_trades = true;
      cfg.max_concurrent_trades     = 3;
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);
      MqlRates bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2, 1);
      entryEngine.OnBar(sm, bar, true, 0.0, false, true, false, 2); // one below the cap
      bool ok = (entryEngine.TradeCount()==1) && (entryEngine.BlockedByMaxConcurrentCount()==0);
      AddResult("T259", ok, StringFormat(
         "max_concurrent_trades=3, current_open_trades_count=2 (below cap) -> entry allowed: trades=%d blocked=%d (must be 1, 0)",
         entryEngine.TradeCount(), (int)entryEngine.BlockedByMaxConcurrentCount()));
     }

   void T260_DailyLossLimitBlocksWhenActive()
     {
      datetime t0 = MakeTime(2026,2,2,11,30,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime=0;
      BuildWaitingEntryFixture(sm, t0, waitTime);
      GZ_EntryConfig cfg; cfg.Default();
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);
      MqlRates bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2, 1);
      entryEngine.OnBar(sm, bar, true, 0.0, false, true, true, 0); // daily_loss_limit_active=true
      GZ_Setup s = sm.GetSetup(0);
      bool ok = (entryEngine.TradeCount()==0) && (entryEngine.BlockedByDailyLossLimitCount()==1) && (s.state==GZ_SETUP_WAITING_ENTRY);
      AddResult("T260", ok, StringFormat(
         "daily_loss_limit_active=true -> trigger suppressed: trades=%d blocked=%d setup state=%s (must be 0, 1, WAITING_ENTRY)",
         entryEngine.TradeCount(), (int)entryEngine.BlockedByDailyLossLimitCount(), s.StateToString()));
     }

   void T261_DailyLossLimitOffRegression()
     {
      datetime t0 = MakeTime(2026,2,2,12,0,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime=0;
      BuildWaitingEntryFixture(sm, t0, waitTime);
      GZ_EntryConfig cfg; cfg.Default();
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);
      MqlRates bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2, 1);
      entryEngine.OnBar(sm, bar, true, 0.0, false, true, false, 0); // daily_loss_limit_active=false (default)
      bool ok = (entryEngine.TradeCount()==1) && (entryEngine.BlockedByDailyLossLimitCount()==0);
      AddResult("T261", ok, StringFormat(
         "REGRESSION daily_loss_limit_active=false: trades=%d blocked=%d (must be 1, 0)",
         entryEngine.TradeCount(), (int)entryEngine.BlockedByDailyLossLimitCount()));
     }

   //--- End-to-end: CGZTradeSimulator's own day-rollover + running daily
   //--- realized-R bookkeeping, through a real Run() call. Two small,
   //--- independent fixtures (T262 same-day block, T263 day-rollover
   //--- reset) rather than one large one, to keep each easy to verify by
   //--- hand. Both use two real bullish legs (low->high, prices 90/110 -
   //--- the exact same shape as GZ_FcisTests.mqh's own BuildWaitingEntry
   //--- Fixture / T236, already proven to work in this repo) built via
   //--- the REAL CGZLegEngine/CGZBreakEngine/CGZSetupStateMachine
   //--- pipeline (not hand-built GZ_Leg structs), because only a full
   //--- Run() call exercises CGZTradeSimulator's own bookkeeping.
   //---
   //--- Bar-construction trick used throughout: the SAME M5 bar that
   //--- confirms a leg's target swing can ALSO break it (close on that
   //--- bar > the target level, since CGZBreakEngine::CheckBreak() only
   //--- forbids a bar STRICTLY BEFORE confirmation time - same time is
   //--- allowed) AND touch the fib zone [92,104] in one shot (a wide-
   //--- range bar, low below 104 / high above the break level) - this
   //--- collapses LEG_DETECTED->BREAK_CONFIRMED->LEG_LOCKED->FIB_ACTIVE->
   //--- WAITING_ENTRY onto one bar (the exact same cascade documented in
   //--- GZ_SetupStateMachine.mqh's own header), so only ONE later M1 bar
   //--- (in the NEXT M5 candle's window) is then needed to trigger TOUCH
   //--- entry. An intermediate BEARISH leg (previous swing -> this leg's
   //--- own origin swing) is unavoidably created by the continuous zigzag
   //--- leg-formation logic between the two bullish legs - left un-broken
   //--- and harmless (it only ever reaches DATA_END, never interacts with
   //--- the bullish setups under test, since direction differs and no
   //--- bullish setup is ever non-terminal at the moment it could break).

   void T262_TradeSimulatorDailyLossLimitBlocksSameDay()
     {
      datetime day1 = MakeTime(2026,2,5,0,0,0);

      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  day1+1*300, day1+2*300,  1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, day1+6*300, day1+7*300,  2); // break+touch on this same bar
      GZ_Swing low2  = MakeSwing(GZ_SWING_LOW,  90.0,  day1+9*300, day1+10*300, 3); // forms an intermediate bearish leg (high1->low2), harmless
      GZ_Swing high2 = MakeSwing(GZ_SWING_HIGH, 110.0, day1+14*300,day1+15*300, 4); // leg2 (low2->high2) - break+touch on this same bar

      GZ_Swing swings[]; ArrayResize(swings,4);
      swings[0]=low1; swings[1]=high1; swings[2]=low2; swings[3]=high2;

      MqlRates m5[]; ArrayResize(m5,5);
      m5[0] = MakeBar(day1+2*300,  90,90.5,89.5,90);        // low1 confirms
      m5[1] = MakeBar(day1+7*300,  95,111,94,110.5);        // high1 confirms+breaks(close 110.5>110)+touches zone[92,104] (low 94)
      m5[2] = MakeBar(day1+10*300, 90,90.5,89.5,90);        // low2 confirms
      m5[3] = MakeBar(day1+15*300, 95,111,94,110.5);        // high2 confirms+breaks+touches zone (same shape as bar1)
      m5[4] = MakeBar(day1+16*300, 110,110.5,109.5,110);    // trailing bar so leg2's entry-attempt M1 bar below has a closed M5 to attach to

      MqlRates m1[]; ArrayResize(m1,3);
      m1[0] = MakeBar(day1+8*300+60,  97,98,96,97, 1);      // leg1 TOUCH entry (low=96 <= level~97.64)
      m1[1] = MakeBar(day1+8*300+120, 89,90,85,89, 1);      // leg1 SL-hit (low=85 <= sl=90) -> realized -1.0R
      m1[2] = MakeBar(day1+16*300+60, 97,98,96,97, 1);      // leg2's own TOUCH condition met - MUST be blocked (daily total already -1.0R)

      CGZLegEngine legEngine(m_logger); legEngine.Init(GZ_LEG_VARIANT_LAST_SWING);
      GZ_BreakConfig bcfg; bcfg.Default();
      CGZBreakEngine breakEngine(m_logger); breakEngine.Configure(bcfg);
      CGZSetupStateMachine sm(m_logger); sm.Init(0.30,0.90);
      GZ_EntryConfig ecfg; ecfg.Default();
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(ecfg);
      GZ_ExitConfig xcfg; xcfg.Default(); // SL_STRUCTURE, zero buffer -> SL=leg.origin_swing.price=90
      CGZExitEngine exitEngine(m_logger); exitEngine.Init(xcfg);
      CGZTimeEngine timeEngine(m_logger); GZ_TimeConfig tcfg; tcfg.Default(); timeEngine.Configure(tcfg);
      CGZSessionEngine sessionEngine;
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,0,0,true,false); // has_session=false
      CGZJournalEngine journalEngine(m_logger); journalEngine.Init();
      CGZEventLedger   ledger(m_logger);        ledger.Init();
      CGZTradeSimulator sim(m_logger);

      sim.Run(m1, m5, swings, 4, legEngine, breakEngine, sm, entryEngine, exitEngine, journalEngine, ledger,
              timeEngine, sessionEngine, profile, false, false, false, true, 1.0); // use_daily_loss_limit=true, r=1.0

      bool leg1EnteredAndSlHit = (entryEngine.TradeCount()==1) && (exitEngine.ExitCount()==1) && !exitEngine.GetExit(0).is_open &&
                                 (exitEngine.GetExit(0).exit_reason==GZ_EXIT_SL_HIT) && (MathAbs(exitEngine.GetExit(0).realized_r-(-1.0))<0.0001);
      bool leg2Blocked = (entryEngine.TradeCount()==1) && (entryEngine.BlockedByDailyLossLimitCount()>=1);

      bool ok = leg1EnteredAndSlHit && leg2Blocked;
      AddResult("T262", ok, StringFormat(
         "TradeSimulator Daily Loss Limit (r=1.0), SAME day: leg1 enters+SL-hits realized_r=%.3f, leg2's own entry condition met later same day but blocked_count=%d -> total trades=%d (must be -1.000, >=1, 1)",
         exitEngine.ExitCount()>0?exitEngine.GetExit(0).realized_r:0.0, (int)entryEngine.BlockedByDailyLossLimitCount(), entryEngine.TradeCount()));
     }

   void T263_TradeSimulatorDailyLossLimitResetsNextDay()
     {
      datetime day1 = MakeTime(2026,2,6,0,0,0);
      datetime day2 = MakeTime(2026,2,7,0,0,0);

      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  day1+1*300, day1+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, day1+6*300, day1+7*300, 2); // day 1: break+touch on this bar
      GZ_Swing low2  = MakeSwing(GZ_SWING_LOW,  90.0,  day2+1*300, day2+2*300, 3); // intermediate bearish leg, harmless
      GZ_Swing high2 = MakeSwing(GZ_SWING_HIGH, 110.0, day2+6*300, day2+7*300, 4); // day 2: break+touch on this bar

      GZ_Swing swings[]; ArrayResize(swings,4);
      swings[0]=low1; swings[1]=high1; swings[2]=low2; swings[3]=high2;

      MqlRates m5[]; ArrayResize(m5,5);
      m5[0] = MakeBar(day1+2*300, 90,90.5,89.5,90);
      m5[1] = MakeBar(day1+7*300, 95,111,94,110.5);
      m5[2] = MakeBar(day2+2*300, 90,90.5,89.5,90);
      m5[3] = MakeBar(day2+7*300, 95,111,94,110.5);
      m5[4] = MakeBar(day2+8*300, 110,110.5,109.5,110); // trailing bar for leg2's entry M1 bar below

      MqlRates m1[]; ArrayResize(m1,3);
      m1[0] = MakeBar(day1+8*300+60,  97,98,96,97, 1);   // leg1 TOUCH entry
      m1[1] = MakeBar(day1+8*300+120, 89,90,85,89, 1);   // leg1 SL-hit -> day1 total = -1.0R
      m1[2] = MakeBar(day2+8*300+60,  97,98,96,97, 1);   // leg2 TOUCH entry, NEW broker day -> must be ALLOWED

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
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,0,0,0,0,true,false);
      CGZJournalEngine journalEngine(m_logger); journalEngine.Init();
      CGZEventLedger   ledger(m_logger);        ledger.Init();
      CGZTradeSimulator sim(m_logger);

      sim.Run(m1, m5, swings, 4, legEngine, breakEngine, sm, entryEngine, exitEngine, journalEngine, ledger,
              timeEngine, sessionEngine, profile, false, false, false, true, 1.0);

      bool ok = (entryEngine.TradeCount()==2) && (entryEngine.BlockedByDailyLossLimitCount()==0);
      AddResult("T263", ok, StringFormat(
         "TradeSimulator Daily Loss Limit (r=1.0), NEXT day: day1 total reaches -1.0R (leg1 SL-hit), leg2 on day2 is UNAFFECTED (total reset) -> trades=%d blocked=%d (must be 2, 0)",
         entryEngine.TradeCount(), (int)entryEngine.BlockedByDailyLossLimitCount()));
     }

   //--- Regression guard for a REAL bug found from a live MT5 run (peak
   //--- open trades reached 11 against a configured cap of 3): the old
   //--- Max Concurrent Open Trades check compared every setup in one
   //--- OnBar() call against the SAME pre-bar snapshot, so several setups
   //--- whose trigger all fired on the SAME bar could each pass the "not
   //--- yet at cap" check and enter together. Fixed with a running counter
   //--- (see GZ_EntryEngine.mqh::OnBar()'s own comment). Three same-
   //--- direction setups (Switch A ON to let them coexist), all reaching
   //--- WAITING_ENTRY on the SAME bar, all sharing the SAME trigger price -
   //--- with cap=2, exactly 2 must enter and the 3rd must be blocked, ALL
   //--- within this one call.
   void T265_MaxConcurrentEnforcedWithinSameBar()
     {
      datetime t0 = MakeTime(2026,2,9,0,0,0);
      CGZSetupStateMachine sm(m_logger);
      sm.Init(0.30,0.90,true,false); // Switch A ON so all three same-direction setups survive creation

      GZ_Leg leg1 = MakeLeg(GZ_LEG_BULLISH, 1, t0+300);  sm.OnLegCreated(leg1);
      sm.OnLegBroken(MakeBrokenLeg(GZ_LEG_BULLISH, 1, t0+600));   // -> setup1 FIB_ACTIVE
      GZ_Leg leg2 = MakeLeg(GZ_LEG_BULLISH, 2, t0+900);  sm.OnLegCreated(leg2);
      sm.OnLegBroken(MakeBrokenLeg(GZ_LEG_BULLISH, 2, t0+1200));  // -> setup2 FIB_ACTIVE
      GZ_Leg leg3 = MakeLeg(GZ_LEG_BULLISH, 3, t0+1500); sm.OnLegCreated(leg3);
      sm.OnLegBroken(MakeBrokenLeg(GZ_LEG_BULLISH, 3, t0+1800));  // -> setup3 FIB_ACTIVE

      // one shared bar promotes ALL THREE to WAITING_ENTRY at once (same zone [92,104])
      MqlRates touchBar = MakeBar(t0+2000, 99,100,95,99);
      sm.OnBar(touchBar, true, false);

      GZ_EntryConfig cfg; cfg.Default();
      cfg.use_max_concurrent_trades = true;
      cfg.max_concurrent_trades     = 2;
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);

      // one shared bar triggers ALL THREE setups' identical TOUCH level at once
      MqlRates entryBar = MakeBar(t0+2000+60, 97,98,96,97, 1);
      entryEngine.OnBar(sm, entryBar, true, 0.0, false, true, false, 0); // current_open_trades_count=0 (nothing open before this bar)

      bool ok = (entryEngine.TradeCount()==2) && (entryEngine.BlockedByMaxConcurrentCount()==1);
      AddResult("T265", ok, StringFormat(
         "Max Concurrent (cap=2), THREE setups trigger on the SAME bar -> trades=%d blocked=%d (must be 2, 1 - the 3rd is blocked WITHIN this same bar, not just on a later one)",
         entryEngine.TradeCount(), (int)entryEngine.BlockedByMaxConcurrentCount()));
     }

   //--- Max Concurrent Setups (FIFO cap, direction-agnostic) follow-up:
   //--- T266-T268. Unlike every other switch in this phase, this one
   //--- defaults ON (5) - see GZ_SetupStateMachine.mqh's Init() comment -
   //--- so T266 (the regression case) explicitly passes false to prove
   //--- the mechanism CAN be turned off, not to represent the shipped
   //--- default.

   void T266_MaxConcurrentSetupsOffRegression()
     {
      datetime t0 = MakeTime(2026,2,10,0,0,0);
      CGZSetupStateMachine sm(m_logger);
      sm.Init(0.30,0.90,true,false,false,5); // Switch A ON (so same-direction survive), cap mechanism OFF

      for(int k=1;k<=6;k++)
         sm.OnLegCreated(MakeLeg(GZ_LEG_BULLISH, k, t0+k*300));

      int nonTerminal = 0;
      for(int k=0;k<sm.SetupCount();k++)
         if(!sm.GetSetup(k).IsTerminal())
            nonTerminal++;

      bool ok = (sm.SetupCount()==6) && (nonTerminal==6) && (sm.EvictedByMaxConcurrentSetupsCount()==0);
      AddResult("T266", ok, StringFormat(
         "REGRESSION use_max_concurrent_setups=false: 6 same-direction legs (Switch A on) -> all 6 survive, none evicted -> setups=%d non_terminal=%d evicted=%d (must be 6, 6, 0)",
         sm.SetupCount(), nonTerminal, (int)sm.EvictedByMaxConcurrentSetupsCount()));
     }

   void T267_MaxConcurrentSetupsEvictsOldest()
     {
      datetime t0 = MakeTime(2026,2,10,1,0,0);
      CGZSetupStateMachine sm(m_logger);
      sm.Init(0.30,0.90,true,false,true,5); // Switch A ON, cap ON at 5

      for(int k=1;k<=6;k++) // the 6th push evicts the oldest
         sm.OnLegCreated(MakeLeg(GZ_LEG_BULLISH, k, t0+k*300));

      GZ_Setup s0 = sm.GetSetup(0); // oldest (setup #1) - must be evicted
      bool restIntact = true;
      for(int k=1;k<6;k++)
         if(sm.GetSetup(k).IsTerminal())
            restIntact = false;

      bool ok = (sm.SetupCount()==6) && (s0.state==GZ_SETUP_CANCELLED) && (s0.cancel_reason==GZ_CANCEL_MAX_CONCURRENT_SETUPS) &&
                restIntact && (sm.EvictedByMaxConcurrentSetupsCount()==1);
      AddResult("T267", ok, StringFormat(
         "cap=5, Switch A ON: 6th same-direction leg -> OLDEST (setup#1) evicted state=%s reason=%s, setups 2-6 all intact, evicted_count=%d (must be CANCELLED, MAX_CONCURRENT_SETUPS, 1)",
         s0.StateToString(), s0.CancelReasonToString(), (int)sm.EvictedByMaxConcurrentSetupsCount()));
     }

   void T268_MaxConcurrentSetupsIsDirectionAgnostic()
     {
      datetime t0 = MakeTime(2026,2,10,2,0,0);
      CGZSetupStateMachine sm(m_logger);
      sm.Init(0.30,0.90,true,true,true,5); // Switch A+B ON (no direction-based cancellation at all), cap ON at 5

      sm.OnLegCreated(MakeLeg(GZ_LEG_BULLISH, 1, t0+1*300)); // oldest - bullish
      sm.OnLegCreated(MakeLeg(GZ_LEG_BEARISH, 2, t0+2*300)); // 2nd oldest - bearish
      sm.OnLegCreated(MakeLeg(GZ_LEG_BULLISH, 3, t0+3*300));
      sm.OnLegCreated(MakeLeg(GZ_LEG_BULLISH, 4, t0+4*300));
      sm.OnLegCreated(MakeLeg(GZ_LEG_BULLISH, 5, t0+5*300)); // at cap (5), none evicted yet
      bool noneEvictedYet = (sm.EvictedByMaxConcurrentSetupsCount()==0);

      // 6th leg is BEARISH - opposite direction from setup #1 (the one that must be evicted).
      // A direction-based rule (same-direction cancel, or opposite-direction break) would never
      // pick setup #1 for THIS reason; only a direction-agnostic FIFO cap would.
      sm.OnLegCreated(MakeLeg(GZ_LEG_BEARISH, 6, t0+6*300));

      GZ_Setup s0 = sm.GetSetup(0); // bullish, oldest overall - must be evicted despite the new leg being bearish
      GZ_Setup s1 = sm.GetSetup(1); // bearish, 2nd oldest - must survive

      bool ok = noneEvictedYet && (s0.state==GZ_SETUP_CANCELLED) && (s0.cancel_reason==GZ_CANCEL_MAX_CONCURRENT_SETUPS) &&
                (!s1.IsTerminal()) && (sm.EvictedByMaxConcurrentSetupsCount()==1);
      AddResult("T268", ok, StringFormat(
         "Direction-agnostic FIFO: oldest overall (setup#1, BULLISH) evicted by a NEW BEARISH leg (opposite direction) -> state=%s reason=%s, 2nd-oldest (BEARISH, setup#2) survives (must be CANCELLED, MAX_CONCURRENT_SETUPS, non-terminal)",
         s0.StateToString(), s0.CancelReasonToString()));
     }

public:
                     CGZConcurrencyTests(CGZLogger *logger=NULL) { m_logger=logger; }

   int               ResultCount() const { return ArraySize(m_results); }
   GZ_TestResult     GetResult(int i) const { return m_results[i]; }

   void RunAll()
     {
      ArrayResize(m_results,0);
      T250_BothOffSameDirectionRegression();
      T251_SwitchAOnConcurrentSameDirection();
      T252_SwitchAIndependentOfOppositeBreak();
      T253_SwitchBOffOppositeBreakRegression();
      T254_SwitchBOnSurvivesOppositeBreak();
      T255_BothOnNoInteraction();
      T256_ExitEnginePeakOpenTradesDiagnostic();
      T257_MaxConcurrentOffRegression();
      T258_MaxConcurrentBlocksAtCap();
      T259_MaxConcurrentAllowsBelowCap();
      T260_DailyLossLimitBlocksWhenActive();
      T261_DailyLossLimitOffRegression();
      T262_TradeSimulatorDailyLossLimitBlocksSameDay();
      T263_TradeSimulatorDailyLossLimitResetsNextDay();
      T265_MaxConcurrentEnforcedWithinSameBar();
      T266_MaxConcurrentSetupsOffRegression();
      T267_MaxConcurrentSetupsEvictsOldest();
      T268_MaxConcurrentSetupsIsDirectionAgnostic();
     }
  };

#endif // __GZ_CONCURRENCY_TESTS_MQH__
