//+------------------------------------------------------------------+
//| GZ_ConcurrencyTests.mqh                                          |
//| GoldenZone STR - Phase "Concurrent Same-Direction Setups +       |
//| Opposite-Break Survival" - T250-T256                              |
//|                                                                    |
//| Synthetic data only, same discipline as GZ_FcisTests.mqh /        |
//| GZ_PartitionTests.mqh (own local MakeLeg/MakeBar/MakeTime helpers,|
//| AddResult, hooked into GZ_TestHarness.mqh's RunAll() - each test  |
//| suite class in this repo is self-contained by convention).        |
//|                                                                    |
//| Covers Switch A (allow_concurrent_same_direction) and Switch B    |
//| (allow_survive_opposite_break) on CGZSetupStateMachine, both      |
//| independently and in combination, plus the peak-concurrency       |
//| diagnostics on CGZSetupStateMachine and CGZExitEngine. Legs are   |
//| built by hand (GZ_Leg is a plain struct) rather than run through  |
//| CGZLegEngine, since only OnLegCreated()/OnLegBroken() themselves  |
//| are under test here - no swing/leg-formation math is exercised or |
//| touched by this phase (see phase prompt's own restriction).       |
//+------------------------------------------------------------------+
#ifndef __GZ_CONCURRENCY_TESTS_MQH__
#define __GZ_CONCURRENCY_TESTS_MQH__

#include "GZ_SetupStateMachine.mqh"
#include "..\Exit\GZ_ExitEngine.mqh"
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
     }
  };

#endif // __GZ_CONCURRENCY_TESTS_MQH__
