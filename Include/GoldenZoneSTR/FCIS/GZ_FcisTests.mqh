//+------------------------------------------------------------------+
//| GZ_FcisTests.mqh                                                  |
//| GoldenZone STR - Phase "First_Change_In_Structure" - T236-T249   |
//|                                                                    |
//| Synthetic data only, same discipline as GZ_PartitionTests.mqh /   |
//| GZ_DatasetTests.mqh / GZ_RewardBeTests.mqh (own local MakeBar/     |
//| MakeTime/MakeSwing/BuildWaitingEntryFixture helpers, mirroring     |
//| GZ_TestHarness.mqh's own private ones - each test suite class in  |
//| this repo is self-contained by convention).                       |
//|                                                                    |
//| Covers: Step 0.5 (Session Hour Gate - setup formation + entry     |
//| trigger blocking), Step 2 (real bid/ask fills - entry AND exit),  |
//| Step 4 (Minimum Risk Gate). Step 3 (Elevated Spread Gate) is NOT  |
//| tested here because it is not yet coded - see spec Section 4.     |
//| Broker DST behavior is the pre-existing InpDstMode /               |
//| InpBrokerUtcOffsetHrs mechanism (already covered by T07-T11) and  |
//| is untouched by this phase - no new tests needed for it here.     |
//+------------------------------------------------------------------+
#ifndef __GZ_FCIS_TESTS_MQH__
#define __GZ_FCIS_TESTS_MQH__

#include "..\Core\GZ_Types.mqh"
#include "..\Structure\GZ_StructureTypes.mqh"
#include "..\Leg\GZ_LegEngine.mqh"
#include "..\Leg\GZ_BreakEngine.mqh"
#include "..\Setup\GZ_SetupStateMachine.mqh"
#include "..\Entry\GZ_EntryEngine.mqh"
#include "..\Entry\GZ_TradeSimulator.mqh"
#include "..\Exit\GZ_ExitEngine.mqh"
#include "..\Journal\GZ_JournalEngine.mqh"
#include "..\Journal\GZ_EventLedger.mqh"
#include "..\Time\GZ_TimeEngine.mqh"
#include "..\Cost\GZ_CostTypes.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZFcisTests
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

   GZ_Swing MakeSwing(ENUM_GZ_SWING_DIR dir, double price, datetime pivot_t, datetime confirm_t, long id=1)
     {
      GZ_Swing s; s.Clear();
      s.id = id; s.direction = dir; s.price = price;
      s.pivot_time = pivot_t; s.detection_time = pivot_t; s.confirmation_time = confirm_t;
      s.pivot_strength = 2;
      return s;
     }

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

   GZ_Trade MakeTrade(long id, long setup_id, ENUM_GZ_LEG_DIR dir, double entry_price, datetime t)
     {
      GZ_Trade tr; tr.Clear();
      tr.id=id; tr.setup_id=setup_id; tr.direction=dir; tr.entry_price=entry_price;
      tr.entry_time=t; tr.entry_model=GZ_ENTRY_TOUCH; tr.fib_level=0.618;
      return tr;
     }

   GZ_Leg MakeLegForExit(ENUM_GZ_LEG_DIR dir, double origin_price)
     {
      GZ_Leg leg; leg.Clear();
      leg.id = 1; leg.direction = dir; leg.origin_swing.price = origin_price;
      return leg;
     }

   void T236_SessionHourGateBlocksSetupFormation()
     {
      datetime t0 = MakeTime(2026,1,7,19,50,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);
      GZ_Swing swings[]; ArrayResize(swings,2); swings[0]=low1; swings[1]=high1;

      MqlRates m5[]; ArrayResize(m5,2);
      m5[0] = MakeBar(t0+2*300, 90,90.5,89.5,90);
      m5[1] = MakeBar(t0+7*300, 109,110.5,108.5,110);
      MqlRates m1[]; ArrayResize(m1,0);

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
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,8,0,16,0,true,true);
      CGZJournalEngine journalEngine(m_logger); journalEngine.Init();
      CGZEventLedger   ledger(m_logger);        ledger.Init();
      CGZTradeSimulator sim(m_logger);
      sim.Run(m1, m5, swings, 2, legEngine, breakEngine, sm, entryEngine, exitEngine, journalEngine, ledger,
              timeEngine, sessionEngine, profile, false, false, true);

      bool ok = (sm.SetupCount()==1) && (sm.GetSetup(0).state==GZ_SETUP_CANCELLED) &&
                (sm.GetSetup(0).cancel_reason==GZ_CANCEL_OUTSIDE_SESSION_HOURS);
      AddResult("T236", ok, StringFormat("leg formed at 20:25 (outside 08:00-16:00), gate ON -> setup state=%s reason=%s",
                sm.GetSetup(0).StateToString(), sm.GetSetup(0).CancelReasonToString()));
     }

   void T237_SessionHourGateOffLeavesSetupFormed()
     {
      datetime t0 = MakeTime(2026,1,8,19,50,0);
      GZ_Swing low1  = MakeSwing(GZ_SWING_LOW,  90.0,  t0,       t0+2*300, 1);
      GZ_Swing high1 = MakeSwing(GZ_SWING_HIGH, 110.0, t0+5*300, t0+7*300, 2);
      GZ_Swing swings[]; ArrayResize(swings,2); swings[0]=low1; swings[1]=high1;

      MqlRates m5[]; ArrayResize(m5,2);
      m5[0] = MakeBar(t0+2*300, 90,90.5,89.5,90);
      m5[1] = MakeBar(t0+7*300, 109,110.5,108.5,110);
      MqlRates m1[]; ArrayResize(m1,0);

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
      GZ_SessionProfile profile; profile.Set("PROFILE_TEST","Test",GZ_TIME_BROKER,8,0,16,0,true,true);
      CGZJournalEngine journalEngine(m_logger); journalEngine.Init();
      CGZEventLedger   ledger(m_logger);        ledger.Init();
      CGZTradeSimulator sim(m_logger);
      sim.Run(m1, m5, swings, 2, legEngine, breakEngine, sm, entryEngine, exitEngine, journalEngine, ledger,
              timeEngine, sessionEngine, profile, false, false);

      bool ok = (sm.SetupCount()==1) && (sm.GetSetup(0).state==GZ_SETUP_CANCELLED) &&
                (sm.GetSetup(0).cancel_reason==GZ_CANCEL_DATA_END);
      AddResult("T237", ok, StringFormat("same fixture, gate OFF (default) -> setup reason=%s (must be DATA_END - the fixture's own 2-bar end, NOT OUTSIDE_SESSION_HOURS - proving the gate did not fire)", sm.GetSetup(0).CancelReasonToString()));
     }

   void T238_SessionHourGateBlocksEntryTrigger()
     {
      datetime t0 = MakeTime(2026,1,7,7,0,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime;
      BuildWaitingEntryFixture(sm, t0, waitTime);

      GZ_EntryConfig cfg; cfg.Default();
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);

      MqlRates barOutside = MakeBar(waitTime+60,  99.0,99.5,98.0,98.2);
      MqlRates barInside  = MakeBar(waitTime+120, 99.0,99.5,98.0,98.2);

      entryEngine.OnBar(sm, barOutside, true, 0.0, false, false);
      bool noEntryYet = (entryEngine.TradeCount()==0) && (sm.GetSetup(0).state==GZ_SETUP_WAITING_ENTRY);

      entryEngine.OnBar(sm, barInside, true, 0.0, false, true);
      bool enteredNow = (entryEngine.TradeCount()==1) && (entryEngine.GetTrade(0).entry_time==barInside.time);

      bool ok = noEntryYet && enteredNow;
      AddResult("T238", ok, StringFormat("gate-blocked bar -> trades=0, setup stays WAITING_ENTRY; next bar with gate open -> trades=%d entry_time_matches=%s",
                entryEngine.TradeCount(), enteredNow?"true":"false"));
     }

   void T239_EntryGateDefaultTruePreservesBaseline()
     {
      datetime t0 = MakeTime(2026,1,7,7,30,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime;
      BuildWaitingEntryFixture(sm, t0, waitTime);
      GZ_EntryConfig cfg; cfg.Default();
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);
      MqlRates bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2);
      entryEngine.OnBar(sm, bar, true, 0.0, false);
      bool ok = (entryEngine.TradeCount()==1) && (MathAbs(entryEngine.GetTrade(0).entry_price-98.0)<0.0001);
      AddResult("T239", ok, "OnBar() called with no allow_entry_this_bar arg -> exact pre-FCIS behavior (default true)");
     }

   void T240_RealSpreadFillLongEntry()
     {
      datetime t0 = MakeTime(2026,1,7,8,0,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime;
      BuildWaitingEntryFixture(sm, t0, waitTime);

      GZ_EntryConfig cfg; cfg.Default();
      cfg.use_real_spread_fills = true;
      cfg.point = 0.01;
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);

      MqlRates bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2, 25);
      entryEngine.OnBar(sm, bar, true, 0.0, false);

      bool ok = (entryEngine.TradeCount()==1);
      double expected = 98.0 + 25.0*0.01;
      if(ok)
         ok = MathAbs(entryEngine.GetTrade(0).entry_price-expected)<0.00001;
      AddResult("T240", ok, StringFormat("Long TOUCH real-spread fill: entry=%.5f expected=%.5f (raw bid touch 98.00000 + 25pts*0.01)",
                ok?entryEngine.GetTrade(0).entry_price:0.0, expected));
     }

   void T241_RealSpreadFillOffRegression()
     {
      datetime t0 = MakeTime(2026,1,7,9,0,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime;
      BuildWaitingEntryFixture(sm, t0, waitTime);
      GZ_EntryConfig cfg; cfg.Default();
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);
      MqlRates bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2, 25);
      entryEngine.OnBar(sm, bar, true, 0.0, false);
      bool ok = (entryEngine.TradeCount()==1) && (MathAbs(entryEngine.GetTrade(0).entry_price-98.0)<0.00001);
      AddResult("T241", ok, "use_real_spread_fills=false (default) -> entry fills exactly as pre-FCIS regardless of bar.spread");
     }

   void T242_RealSpreadFillShortExitUsesAsk()
     {
      GZ_ExitConfig cfg; cfg.Default();
      cfg.use_real_spread_fills = true;
      cfg.point = 0.01;
      CGZExitEngine exitEngine(m_logger); exitEngine.Init(cfg);

      GZ_Leg leg = MakeLegForExit(GZ_LEG_BEARISH, 105.0);
      GZ_Trade tr = MakeTrade(1,1,GZ_LEG_BEARISH,100.0, MakeTime(2026,1,7,10,0,0));
      exitEngine.OnTradeEntered(tr, leg, 0.0, false);

      MqlRates bar = MakeBar(MakeTime(2026,1,7,10,1,0), 103,104,102,103, 120);
      exitEngine.OnBar(bar, true, false);

      GZ_TradeExit ex = exitEngine.GetExit(0);
      bool ok = !ex.is_open && (ex.exit_reason==GZ_EXIT_SL_HIT) && MathAbs(ex.exit_price-106.20)<0.00001;
      AddResult("T242", ok, StringFormat("Short SL: raw bid high=104.00 (does not reach sl=105.00) but ask (high+120pts*0.01=105.20) touches -> fill=%.5f expected=106.20",
                ex.exit_price));
     }

   void T243_RealSpreadFillLongExitUnaffected()
     {
      GZ_ExitConfig cfg; cfg.Default();
      cfg.use_real_spread_fills = true;
      cfg.point = 0.01;
      CGZExitEngine exitEngine(m_logger); exitEngine.Init(cfg);

      GZ_Leg leg = MakeLegForExit(GZ_LEG_BULLISH, 95.0);
      GZ_Trade tr = MakeTrade(1,1,GZ_LEG_BULLISH,100.0, MakeTime(2026,1,7,11,0,0));
      exitEngine.OnTradeEntered(tr, leg, 0.0, false);

      MqlRates bar = MakeBar(MakeTime(2026,1,7,11,1,0), 96,97,94,95, 50);
      exitEngine.OnBar(bar, true, false);

      GZ_TradeExit ex = exitEngine.GetExit(0);
      bool ok = !ex.is_open && (ex.exit_reason==GZ_EXIT_SL_HIT) && MathAbs(ex.exit_price-95.0)<0.00001;
      AddResult("T243", ok, StringFormat("Long SL touch with spread=50pts: exit=%.5f expected=95.00000 (bid unchanged, unaffected)", ex.exit_price));
     }

   void T244_ExitRealSpreadFillOffRegression()
     {
      GZ_ExitConfig cfg; cfg.Default();
      CGZExitEngine exitEngine(m_logger); exitEngine.Init(cfg);
      GZ_Leg leg = MakeLegForExit(GZ_LEG_BEARISH, 105.0);
      GZ_Trade tr = MakeTrade(1,1,GZ_LEG_BEARISH,100.0, MakeTime(2026,1,7,12,0,0));
      exitEngine.OnTradeEntered(tr, leg, 0.0, false);
      MqlRates bar = MakeBar(MakeTime(2026,1,7,12,1,0), 103,104,102,103, 120);
      exitEngine.OnBar(bar, true, false);
      GZ_TradeExit ex = exitEngine.GetExit(0);
      bool ok = ex.is_open;
      AddResult("T244", ok, "use_real_spread_fills=false (default) -> Short SL/TP touch stays on raw bid HL exactly as pre-FCIS (still open)");
     }

   void T245_MinRiskGateBlocksTooTight()
     {
      datetime t0 = MakeTime(2026,1,7,13,0,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime;
      BuildWaitingEntryFixture(sm, t0, waitTime);

      GZ_EntryConfig cfg; cfg.Default();
      cfg.use_min_risk_gate = true;
      cfg.max_cost_fraction_of_r = 0.05;
      cfg.gate_sl_model = GZ_SL_ATR;
      cfg.gate_sl_atr_mult = 0.5;
      cfg.cost_cfg_for_gate.Default();
      cfg.cost_cfg_for_gate.configured = true;
      cfg.cost_cfg_for_gate.point = 0.01;
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);

      MqlRates bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2, 1000);
      entryEngine.OnBar(sm, bar, true, 1.0, true);

      GZ_Setup s = sm.GetSetup(0);
      bool ok = (entryEngine.TradeCount()==0) && (s.state==GZ_SETUP_CANCELLED) && (s.cancel_reason==GZ_CANCEL_RISK_TOO_TIGHT);
      AddResult("T245", ok, StringFormat("structural risk 0.5 vs required 200 (cost 10.0/0.05) -> setup state=%s reason=%s trades=%d",
                s.StateToString(), s.CancelReasonToString(), entryEngine.TradeCount()));
     }

   void T246_MinRiskGateAllowsNormalRisk()
     {
      datetime t0 = MakeTime(2026,1,7,13,30,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime;
      BuildWaitingEntryFixture(sm, t0, waitTime);

      GZ_EntryConfig cfg; cfg.Default();
      cfg.use_min_risk_gate = true;
      cfg.max_cost_fraction_of_r = 0.05;
      cfg.gate_sl_model = GZ_SL_ATR;
      cfg.gate_sl_atr_mult = 0.5;
      cfg.cost_cfg_for_gate.Default();
      cfg.cost_cfg_for_gate.configured = true;
      cfg.cost_cfg_for_gate.point = 0.01;
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);

      MqlRates bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2, 1);
      entryEngine.OnBar(sm, bar, true, 1.0, true);

      bool ok = (entryEngine.TradeCount()==1);
      AddResult("T246", ok, StringFormat("structural risk 0.5 vs required 0.2 (cost 0.01/0.05) -> gate does not block, trades=%d", entryEngine.TradeCount()));
     }

   void T247_MinRiskGateOffRegression()
     {
      datetime t0 = MakeTime(2026,1,7,14,0,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime;
      BuildWaitingEntryFixture(sm, t0, waitTime);
      GZ_EntryConfig cfg; cfg.Default();
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);
      MqlRates bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2, 1000);
      entryEngine.OnBar(sm, bar, true, 1.0, true);
      bool ok = (entryEngine.TradeCount()==1);
      AddResult("T247", ok, "use_min_risk_gate=false (default) -> huge spread has no effect on the entry decision, exactly pre-FCIS");
     }

   void T248_MinRiskGateAtrNotReadyDoesNotGuess()
     {
      datetime t0 = MakeTime(2026,1,7,15,0,0);
      CGZSetupStateMachine sm(m_logger);
      datetime waitTime;
      BuildWaitingEntryFixture(sm, t0, waitTime);
      GZ_EntryConfig cfg; cfg.Default();
      cfg.use_min_risk_gate = true;
      cfg.gate_sl_model = GZ_SL_ATR;
      cfg.gate_sl_atr_mult = 0.5;
      cfg.cost_cfg_for_gate.Default();
      cfg.cost_cfg_for_gate.configured = true;
      cfg.cost_cfg_for_gate.point = 0.01;
      CGZEntryEngine entryEngine(m_logger); entryEngine.Init(cfg);
      MqlRates bar = MakeBar(waitTime+60, 99.0,99.5,98.0,98.2, 1000);
      entryEngine.OnBar(sm, bar, true, 0.0, false);
      GZ_Setup s = sm.GetSetup(0);
      bool ok = (entryEngine.TradeCount()==0) && (s.state==GZ_SETUP_WAITING_ENTRY);
      AddResult("T248", ok, StringFormat("ATR gate requested but not ready -> bar skipped (no guess/no block/no entry), setup state=%s", s.StateToString()));
     }

   void T249_FcisDeterminism()
     {
      datetime t0 = MakeTime(2026,1,7,16,0,0);

      CGZSetupStateMachine smA(m_logger); datetime wtA; BuildWaitingEntryFixture(smA, t0, wtA);
      GZ_EntryConfig cfgA; cfgA.Default();
      cfgA.use_min_risk_gate = true; cfgA.max_cost_fraction_of_r = 0.05;
      cfgA.gate_sl_model = GZ_SL_ATR; cfgA.gate_sl_atr_mult = 0.5;
      cfgA.cost_cfg_for_gate.Default(); cfgA.cost_cfg_for_gate.configured=true; cfgA.cost_cfg_for_gate.point=0.01;
      CGZEntryEngine entA(m_logger); entA.Init(cfgA);
      MqlRates barA = MakeBar(wtA+60, 99.0,99.5,98.0,98.2, 1000);
      entA.OnBar(smA, barA, true, 1.0, true);

      CGZSetupStateMachine smB(m_logger); datetime wtB; BuildWaitingEntryFixture(smB, t0, wtB);
      GZ_EntryConfig cfgB = cfgA;
      CGZEntryEngine entB(m_logger); entB.Init(cfgB);
      MqlRates barB = MakeBar(wtB+60, 99.0,99.5,98.0,98.2, 1000);
      entB.OnBar(smB, barB, true, 1.0, true);

      bool ok = (entA.TradeCount()==entB.TradeCount()) && (entA.TradeCount()==0) &&
                (smA.GetSetup(0).cancel_reason==smB.GetSetup(0).cancel_reason) &&
                (smA.GetSetup(0).cancel_reason==GZ_CANCEL_RISK_TOO_TIGHT);
      AddResult("T249", ok, StringFormat("two independent runs of the same Min-Risk-Gate fixture -> identical outcome (tradesA=%d tradesB=%d, both CANCELLED/RISK_TOO_TIGHT)",
                entA.TradeCount(), entB.TradeCount()));
     }

public:
                     CGZFcisTests(CGZLogger *logger=NULL) { m_logger=logger; }

   int               ResultCount() const { return ArraySize(m_results); }
   GZ_TestResult     GetResult(int i) const { return m_results[i]; }

   void RunAll()
     {
      ArrayResize(m_results,0);
      T236_SessionHourGateBlocksSetupFormation();
      T237_SessionHourGateOffLeavesSetupFormed();
      T238_SessionHourGateBlocksEntryTrigger();
      T239_EntryGateDefaultTruePreservesBaseline();
      T240_RealSpreadFillLongEntry();
      T241_RealSpreadFillOffRegression();
      T242_RealSpreadFillShortExitUsesAsk();
      T243_RealSpreadFillLongExitUnaffected();
      T244_ExitRealSpreadFillOffRegression();
      T245_MinRiskGateBlocksTooTight();
      T246_MinRiskGateAllowsNormalRisk();
      T247_MinRiskGateOffRegression();
      T248_MinRiskGateAtrNotReadyDoesNotGuess();
      T249_FcisDeterminism();
     }
  };

#endif // __GZ_FCIS_TESTS_MQH__
