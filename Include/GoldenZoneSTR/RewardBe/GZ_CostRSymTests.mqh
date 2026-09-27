//+------------------------------------------------------------------+
//| GZ_CostRSymTests.mqh                                              |
//| GoldenZone STR - Phase "Cost Unification + R-Symmetry Fix" -      |
//| T269-T277                                                          |
//|                                                                    |
//| Synthetic data only, same discipline as GZ_FcisTests.mqh /        |
//| GZ_ConcurrencyTests.mqh (own local MakeBar/MakeHL/MakeTime         |
//| helpers, AddResult, hooked into GZ_TestHarness.mqh's RunAll() -    |
//| each test suite class in this repo is self-contained by            |
//| convention, so the small M5/M1 fixture used by T272-T274 below is  |
//| a deliberate, deliberately-minimal DUPLICATE of the well-known     |
//| BuildPhase9M5Series()/BuildPhase9M1Series() fixture already        |
//| proven in GZ_TestHarness.mqh (T89: 2 swings, 1 leg, 1 setup, 1     |
//| trade, TP_HIT, gross net_r=2.000) rather than a new invention -    |
//| see that file for the fixture's own detailed pivot/break/zone      |
//| design notes, not repeated here.                                    |
//|                                                                    |
//| T269-T271 (spec Sub-phase A, Bug 1): CGZExitEngine::OnTradeEntered |
//| / OnBar() directly, hand-built GZ_Trade/GZ_Leg records - only the  |
//| R-symmetry fix itself is under test, not the whole pipeline.       |
//| T272-T274 (Sub-phase B, Bug 2) and T275 (Sub-phase C, Bug 3): the  |
//| full CGZExperimentRunner::Execute() path (and, for T274, one       |
//| downstream consumer of it - CGZRobustnessEngine::RunSweep()) via   |
//| the fixture above. T276-T277 (Sub-phase E, Bug 5): the shared      |
//| GZBaselineCompare() function directly, no pipeline involved.       |
//+------------------------------------------------------------------+
#ifndef __GZ_COST_RSYM_TESTS_MQH__
#define __GZ_COST_RSYM_TESTS_MQH__

#include "..\Exit\GZ_ExitEngine.mqh"
#include "..\Exit\GZ_ExitTypes.mqh"
#include "..\Entry\GZ_EntryTypes.mqh"
#include "..\Leg\GZ_LegTypes.mqh"
#include "..\Experiment\GZ_ExperimentRunner.mqh"
#include "..\Experiment\GZ_ExperimentTypes.mqh"
#include "..\Cost\GZ_CostTypes.mqh"
#include "..\Cost\GZ_CostEngine.mqh"
#include "..\Robustness\GZ_RobustnessEngine.mqh"
#include "GZ_RunDetail.mqh"
#include "GZ_BaselineCompare.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZCostRSymTests
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

   MqlRates MakeHL(datetime t, double high, double low, int spread=1)
     {
      double mid = (high+low)/2.0;
      return MakeBar(t, mid, high, low, mid, spread);
     }

   //--- Minimal GZ_Leg for the direct-CGZExitEngine tests (T269-T271):
   //--- only origin_swing.price/extreme_price/direction matter for
   //--- GZ_SL_STRUCTURE with sl_buffer_atr_mult=0.
   GZ_Leg MakeLeg(ENUM_GZ_LEG_DIR dir, double origin_price, double extreme_price) const
     {
      GZ_Leg leg; leg.Clear();
      leg.id = 1; leg.direction = dir;
      leg.origin_swing.price = origin_price;
      leg.extreme_price      = extreme_price;
      return leg;
     }

   GZ_Trade MakeTrade(ENUM_GZ_LEG_DIR dir, double entry_price, double spread_assumption_pts, datetime t) const
     {
      GZ_Trade tr; tr.Clear();
      tr.id = 1; tr.setup_id = 1; tr.entry_time = t; tr.entry_price = entry_price;
      tr.direction = dir; tr.spread_assumption = spread_assumption_pts;
      return tr;
     }

   //--- Duplicate of GZ_TestHarness.mqh's BuildPhase9M5Series() - see that
   //--- file for full design notes (pivot windows, break bar, zone touch).
   //--- Produces exactly 2 swings -> 1 bullish leg (origin=80, broken at
   //--- close=141, post-break extreme=142) -> 1 setup reaching WAITING_ENTRY.
   void BuildM5Fixture(MqlRates &m5[])
     {
      datetime t0 = MakeTime(2026,5,4,9,0);
      ArrayResize(m5,13);
      m5[0]  = MakeHL(t0+0*300,  105,100);
      m5[1]  = MakeHL(t0+1*300,  103,98);
      m5[2]  = MakeHL(t0+2*300,  102,80);
      m5[3]  = MakeHL(t0+3*300,  104,95);
      m5[4]  = MakeHL(t0+4*300,  106,97);
      m5[5]  = MakeHL(t0+5*300,  108,99);
      m5[6]  = MakeHL(t0+6*300,  140,100);
      m5[7]  = MakeHL(t0+7*300,  115,101);
      m5[8]  = MakeHL(t0+8*300,  112,98);
      m5[9]  = MakeBar(t0+9*300, 112,142,110,141);
      m5[10] = MakeHL(t0+10*300, 139,95);
      m5[11] = MakeHL(t0+11*300, 145,90);
      m5[12] = MakeHL(t0+12*300, 100,95);
     }

   //--- Duplicate of GZ_TestHarness.mqh's BuildPhase9M1Series() - m1[0]
   //--- triggers a baseline TOUCH entry (fill=bar.low=102), m1[1] delivers
   //--- a comfortable TP_HIT regardless of the exact fill price.
   //--- `entry_spread_pts` sets the ENTRY bar's OWN spread (default pre-
   //--- existing fixture used spread=1 everywhere) so cost tests can charge
   //--- a known, distinctive RECORDED spread.
   void BuildM1Fixture(MqlRates &m1[], datetime m5_touch_time, int entry_spread_pts=1)
     {
      datetime T = m5_touch_time;
      ArrayResize(m1,2);
      m1[0] = MakeBar(T+300+60, 104,104.5,102,102.5, entry_spread_pts);
      m1[1] = MakeBar(T+600+60, 155,160,154,158, 1);
     }

   //=====================================================================
   //  T269-T271: R-Symmetry Fix (Sub-phase A, spec Bug 1)
   //=====================================================================

   //--- T-R-SYM-01: matched Long/Short pair, identical structural distance
   //--- (D=10) and identical spread (S=0.10, i.e. 10 pts @ point=0.01),
   //--- both SL-hit, use_real_spread_fills=true: both realized_r==-1.000.
   void T269_RSymSlBothExactMinusOne()
     {
      GZ_ExitConfig cfg; cfg.Default();
      cfg.sl_model = GZ_SL_STRUCTURE; cfg.sl_buffer_atr_mult = 0.0; cfg.tp_r_multiple = 2.0;
      cfg.use_real_spread_fills = true; cfg.point = 0.01;

      // LONG: raw bid=100.00, entry (ask) = 100.10 (S=0.10), origin=90.00 (D=10 from raw bid)
      CGZExitEngine exL; exL.Init(cfg);
      GZ_Trade trL = MakeTrade(GZ_LEG_BULLISH, 100.10, 10.0, MakeTime(2026,5,4,10,0));
      GZ_Leg legL  = MakeLeg(GZ_LEG_BULLISH, 90.00, 90.00);
      exL.OnTradeEntered(trL, legL, 0.0, true);
      MqlRates barL = MakeBar(MakeTime(2026,5,4,10,1), 90,95,88,90, 10);
      exL.OnBar(barL, true, false);
      GZ_TradeExit exitL = exL.GetExit(0);

      // SHORT: raw bid=100.00 (unadjusted entry), origin=110.00 (D=10 from raw bid)
      CGZExitEngine exS; exS.Init(cfg);
      GZ_Trade trS = MakeTrade(GZ_LEG_BEARISH, 100.00, 10.0, MakeTime(2026,5,4,10,0));
      GZ_Leg legS  = MakeLeg(GZ_LEG_BEARISH, 110.00, 110.00);
      exS.OnTradeEntered(trS, legS, 0.0, true);
      MqlRates barS = MakeBar(MakeTime(2026,5,4,10,1), 105,110,100,105, 10);
      exS.OnBar(barS, true, false);
      GZ_TradeExit exitS = exS.GetExit(0);

      bool ok = (!exitL.is_open) && (!exitS.is_open) &&
                (exitL.exit_reason==GZ_EXIT_SL_HIT) && (exitS.exit_reason==GZ_EXIT_SL_HIT) &&
                (MathAbs(exitL.realized_r-(-1.0))<0.0005) && (MathAbs(exitS.realized_r-(-1.0))<0.0005);
      AddResult("T269", ok, StringFormat(
         "SL-hit, use_real_spread_fills=true: LONG realized_r=%.5f (risk=%.4f) SHORT realized_r=%.5f (risk=%.4f) - both must be -1.000",
         exitL.realized_r, exitL.initial_risk, exitS.realized_r, exitS.initial_risk));
     }

   //--- T-R-SYM-02: same matched pair, use_real_spread_fills=false -
   //--- regression guard: initial_risk/tp_price must be byte-identical to
   //--- the pre-this-phase RAW formula (no spread anticipation at all) for
   //--- BOTH directions, since AnticipatedSlPriceIfShort()/
   //--- AnticipatedTpLevelIfShort() must return their input unchanged here.
   void T270_RSymRegressionFlagOff()
     {
      GZ_ExitConfig cfg; cfg.Default();
      cfg.sl_model = GZ_SL_STRUCTURE; cfg.sl_buffer_atr_mult = 0.0; cfg.tp_r_multiple = 2.0;
      cfg.use_real_spread_fills = false; cfg.point = 0.01; // <-- flag OFF

      // Both directions use RAW entry=100.00 here (pre-FCIS entry was always raw
      // bid regardless of direction when the flag is off).
      CGZExitEngine exL; exL.Init(cfg);
      GZ_Trade trL = MakeTrade(GZ_LEG_BULLISH, 100.00, 10.0, MakeTime(2026,5,4,10,0));
      GZ_Leg legL  = MakeLeg(GZ_LEG_BULLISH, 90.00, 90.00);
      exL.OnTradeEntered(trL, legL, 0.0, true);
      GZ_TradeExit exitL = exL.GetExit(0);

      CGZExitEngine exS; exS.Init(cfg);
      GZ_Trade trS = MakeTrade(GZ_LEG_BEARISH, 100.00, 10.0, MakeTime(2026,5,4,10,0));
      GZ_Leg legS  = MakeLeg(GZ_LEG_BEARISH, 110.00, 110.00);
      exS.OnTradeEntered(trS, legS, 0.0, true);
      GZ_TradeExit exitS = exS.GetExit(0);

      // Pre-this-phase RAW values: initial_risk=10.00 exactly for BOTH
      // (no spread contamination), tp_price=120.00 (long) / 80.00 (short).
      bool ok = (MathAbs(exitL.initial_risk-10.0)<0.00001) && (MathAbs(exitS.initial_risk-10.0)<0.00001) &&
                (MathAbs(exitL.tp_price-120.0)<0.00001) && (MathAbs(exitS.tp_price-80.0)<0.00001);
      AddResult("T270", ok, StringFormat(
         "use_real_spread_fills=false regression: LONG risk=%.4f tp=%.4f | SHORT risk=%.4f tp=%.4f - all must equal the RAW pre-this-phase values (10.00/120.00/10.00/80.00)",
         exitL.initial_risk, exitL.tp_price, exitS.initial_risk, exitS.tp_price));
     }

   //--- T-R-SYM-03: same matched pair, both TP-hit at tp_r_multiple=2.0,
   //--- use_real_spread_fills=true: both realized_r==2.000 exactly.
   void T271_RSymTpBothExactMultiple()
     {
      GZ_ExitConfig cfg; cfg.Default();
      cfg.sl_model = GZ_SL_STRUCTURE; cfg.sl_buffer_atr_mult = 0.0; cfg.tp_r_multiple = 2.0;
      cfg.use_real_spread_fills = true; cfg.point = 0.01;

      CGZExitEngine exL; exL.Init(cfg);
      GZ_Trade trL = MakeTrade(GZ_LEG_BULLISH, 100.10, 10.0, MakeTime(2026,5,4,10,0));
      GZ_Leg legL  = MakeLeg(GZ_LEG_BULLISH, 90.00, 90.00);
      exL.OnTradeEntered(trL, legL, 0.0, true);
      MqlRates barL = MakeBar(MakeTime(2026,5,4,10,1), 118,121,115,118, 10); // high=121 >= tp(120.30)
      exL.OnBar(barL, true, false);
      GZ_TradeExit exitL = exL.GetExit(0);

      CGZExitEngine exS; exS.Init(cfg);
      GZ_Trade trS = MakeTrade(GZ_LEG_BEARISH, 100.00, 10.0, MakeTime(2026,5,4,10,0));
      GZ_Leg legS  = MakeLeg(GZ_LEG_BEARISH, 110.00, 110.00);
      exS.OnTradeEntered(trS, legS, 0.0, true);
      MqlRates barS = MakeBar(MakeTime(2026,5,4,10,1), 85,90,79.60,85, 10); // low=79.60 -> eval_low=79.70=tp
      exS.OnBar(barS, true, false);
      GZ_TradeExit exitS = exS.GetExit(0);

      bool ok = (!exitL.is_open) && (!exitS.is_open) &&
                (exitL.exit_reason==GZ_EXIT_TP_HIT) && (exitS.exit_reason==GZ_EXIT_TP_HIT) &&
                (MathAbs(exitL.realized_r-2.0)<0.0005) && (MathAbs(exitS.realized_r-2.0)<0.0005);
      AddResult("T271", ok, StringFormat(
         "TP-hit, use_real_spread_fills=true: LONG realized_r=%.5f SHORT realized_r=%.5f - both must be +2.000 (tp_r_multiple)",
         exitL.realized_r, exitS.realized_r));
     }

   //=====================================================================
   //  T272-T274: Cost Engine Unification (Sub-phase B, spec Bug 2)
   //=====================================================================

   //--- T-COST-WIRE-01: cost_config.configured=true, non-zero commission
   //--- and slippage, run through CGZExperimentRunner::Execute() (via
   //--- RunSingleDetailed, NOT through GZ_RewardBeEngine.mqh) - the
   //--- resulting GZ_ExperimentResult.net_metrics must differ from
   //--- .metrics by exactly the CostPrice formula's own expected amount.
   void T272_CostWireConfiguredDiffersFromGross()
     {
      MqlRates m5[]; BuildM5Fixture(m5);
      MqlRates m1[]; BuildM1Fixture(m1, m5[10].time, 50); // entry bar spread = 50 pts

      GZ_ExperimentConfig cfg; cfg.Default();
      cfg.time_config.broker_offset_known = true;
      cfg.cost_config.configured        = true;
      cfg.cost_config.spread_mode       = GZ_COST_SPREAD_RECORDED;
      cfg.cost_config.commission_mode   = GZ_COST_COMM_PERCENT;
      cfg.cost_config.commission_percent= 0.1;
      cfg.cost_config.slippage_pts      = 20.0;
      cfg.cost_config.point             = 0.01;

      CGZExperimentRunner runner(m_logger);
      GZ_ExperimentResult r;
      CGZRunDetail detail;
      runner.RunSingleDetailed(cfg, m1, m5, "DS_COSTWIRE01", GZ_VAL_VALID, GZ_VAL_VALID, r, GetPointer(detail));

      bool have_trade = (r.trade_count==1) && (detail.count==1) && r.net_metrics.available;
      double expected_net_r = 0.0, observed_net_r = 0.0;
      bool close = false;
      if(have_trade)
        {
         double cost_price = GZCost_ComputeCostPrice(detail.entry_price[0], 50.0, cfg.cost_config.slippage_pts, cfg.cost_config, false);
         double cost_r = (detail.initial_risk[0]>0.0) ? cost_price/detail.initial_risk[0] : 0.0;
         expected_net_r = detail.realized_r[0] - cost_r;
         observed_net_r = r.net_metrics.net_r;
         close = MathAbs(expected_net_r-observed_net_r)<0.0005;
        }
      bool ok = have_trade && close && !r.net_metrics.net_equals_gross &&
                MathAbs(r.net_metrics.net_r-r.metrics.trade.net_r)>0.0001; // must actually DIFFER from gross
      AddResult("T272", ok, StringFormat(
         "configured cost via Execute(): trades=%d gross_net_r=%.4f net_metrics.net_r=%.4f expected=%.4f (from detail: entry=%.4f risk=%.4f realized_r=%.4f)",
         r.trade_count, r.metrics.trade.net_r, observed_net_r, expected_net_r,
         have_trade?detail.entry_price[0]:0.0, have_trade?detail.initial_risk[0]:0.0, have_trade?detail.realized_r[0]:0.0));
     }

   //--- T-COST-WIRE-02: cost_config.configured=false -> net metrics equal
   //--- gross metrics EXACTLY (the NET=GROSS sentinel).
   void T273_CostWireUnconfiguredEqualsGross()
     {
      MqlRates m5[]; BuildM5Fixture(m5);
      MqlRates m1[]; BuildM1Fixture(m1, m5[10].time, 50);

      GZ_ExperimentConfig cfg; cfg.Default(); // cost_config.configured=false by default
      cfg.time_config.broker_offset_known = true;

      CGZExperimentRunner runner(m_logger);
      GZ_ExperimentResult r;
      runner.RunSingle(cfg, m1, m5, "DS_COSTWIRE02", GZ_VAL_VALID, GZ_VAL_VALID, r);

      bool ok = (r.trade_count==1) && r.net_metrics.net_equals_gross &&
                (MathAbs(r.net_metrics.net_r-r.metrics.trade.net_r)<0.00001) &&
                (MathAbs(r.net_metrics.expectancy-r.metrics.trade.expectancy)<0.00001);
      AddResult("T273", ok, StringFormat(
         "cost_config.configured=false via Execute(): gross net_r=%.4f net_metrics.net_r=%.4f (must be exactly equal) net_equals_gross=%s",
         r.metrics.trade.net_r, r.net_metrics.net_r, r.net_metrics.net_equals_gross?"true":"false"));
     }

   //--- T-COST-WIRE-03: the SAME cost-configured GZ_ExperimentConfig, run
   //--- through a DOWNSTREAM consumer of CGZExperimentRunner::Execute()
   //--- (CGZRobustnessEngine::RunSweep(), which copies GZ_ExperimentConfig
   //--- wholesale per point - see GZ_RobustnessEngine.mqh::ExecutePoints())
   //--- rather than a direct RunSingle() call - proves the wiring reaches
   //--- Robustness (and, by the identical `cfg = req.base_config` /
   //--- `dcfg = ...` copy pattern verified by inspection, Walk-Forward and
   //--- Final OOS too - see this phase's completion report).
   void T274_CostWireReachesRobustness()
     {
      MqlRates m5[]; BuildM5Fixture(m5);
      MqlRates m1[]; BuildM1Fixture(m1, m5[10].time, 50);

      GZ_RobustnessSweepRequest req; req.Clear();
      req.param = GZ_ROBUST_TP_R_MULTIPLE;
      req.base_config.Default();
      req.base_config.time_config.broker_offset_known = true;
      req.base_config.cost_config.configured         = true;
      req.base_config.cost_config.spread_mode         = GZ_COST_SPREAD_RECORDED;
      req.base_config.cost_config.commission_mode     = GZ_COST_COMM_PERCENT;
      req.base_config.cost_config.commission_percent  = 0.1;
      req.base_config.cost_config.slippage_pts        = 20.0;
      req.base_config.cost_config.point               = 0.01;
      req.values[0] = 2.0; // same as baseline - one point is enough to prove the wiring
      req.value_count = 1;

      CGZRobustnessEngine eng(m_logger);
      GZ_RobustnessSweepResult out;
      eng.RunSweep(req, m1, m5, "DS_COSTWIRE03", GZ_VAL_VALID, GZ_VAL_VALID, out);

      bool ok = (out.point_count==1) && (out.points[0].result.trade_count==1) &&
                out.points[0].result.net_metrics.available &&
                !out.points[0].result.net_metrics.net_equals_gross &&
                (MathAbs(out.points[0].result.net_metrics.net_r-out.points[0].result.metrics.trade.net_r)>0.0001);
      AddResult("T274", ok, StringFormat(
         "cost_config reaches CGZRobustnessEngine::RunSweep(): points=%d trades=%d gross_net_r=%.4f net_metrics.net_r=%.4f (must differ)",
         out.point_count, out.point_count>0?out.points[0].result.trade_count:0,
         out.point_count>0?out.points[0].result.metrics.trade.net_r:0.0,
         out.point_count>0?out.points[0].result.net_metrics.net_r:0.0));
     }

   //=====================================================================
   //  T275: Double-spread-charging guard (Sub-phase C, spec Bug 3)
   //=====================================================================

   //--- T-COST-DBL-01: use_real_spread_fills=true AND spread_mode=RECORDED
   //--- AND a non-zero recorded spread -> the computed net cost for a
   //--- trade must EXCLUDE any spread contribution (commission/slippage
   //--- still charged normally).
   void T275_CostDoubleChargeGuardExcludesSpread()
     {
      GZ_CostConfig cc; cc.Default();
      cc.configured        = true;
      cc.spread_mode        = GZ_COST_SPREAD_RECORDED;
      cc.commission_mode    = GZ_COST_COMM_PERCENT;
      cc.commission_percent = 0.1;
      cc.slippage_pts       = 20.0;
      cc.point              = 0.01;

      double open_price = 100.0;
      double recorded_spread_pts = 50.0; // non-zero - would double-charge if not guarded

      double cost_guarded   = GZCost_ComputeCostPrice(open_price, recorded_spread_pts, cc.slippage_pts, cc, true);  // real_spread_fills_active=true
      double cost_unguarded = GZCost_ComputeCostPrice(open_price, recorded_spread_pts, cc.slippage_pts, cc, false); // pre-this-phase behavior

      double commission_only = GZCost_CommissionPrice(open_price, cc);
      double expected_guarded = 0.0*cc.point + 2.0*cc.slippage_pts*cc.point + commission_only; // spread term forced to 0
      double spread_component = recorded_spread_pts*cc.point;

      bool ok = (MathAbs(cost_guarded-expected_guarded)<0.00001) &&
                (MathAbs(cost_unguarded-(expected_guarded+spread_component))<0.00001) &&
                (cost_guarded < cost_unguarded); // the guard must actually remove something non-zero
      AddResult("T275", ok, StringFormat(
         "real_spread_fills_active=true excludes spread from cost: guarded=%.6f unguarded=%.6f expected_guarded=%.6f (spread component=%.6f, commission=%.6f, slippage=%.6f)",
         cost_guarded, cost_unguarded, expected_guarded, spread_component, commission_only, 2.0*cc.slippage_pts*cc.point));
     }

   //=====================================================================
   //  T276-T277: Baseline single source of truth (Sub-phase E, spec Bug 5)
   //=====================================================================

   //--- T-BASELINE-01: the shared function returns PASS for the historical
   //--- all-off/no-cost configuration exactly reproducing its own baseline
   //--- (the regression itself still holds).
   void T276_BaselinePassOnOriginalConfig()
     {
      GZ_BaselineActiveConfig active; active.Clear();
      active.tp_r_multiple = 2.0; active.be_trigger_r = 0.0; // every switch OFF/unconfigured (Clear()'s own defaults)

      string detail;
      ENUM_GZ_BASELINE_VERDICT v = GZBaselineCompare(
         412, 0.507, 0.5218, 2.059, 215.0, 6.0,      // observed == the reference exactly
         412, 0.507, 0.5218, 2.059, 215.0, 6.0,      // InpP155Ref* values
         active, detail);

      bool ok = (v==GZ_BASELINE_PASS);
      AddResult("T276", ok, StringFormat("all-off/no-cost config, observed==reference exactly: verdict=%s | %s",
                GZBaselineVerdictToString(v), detail));
     }

   //--- T-BASELINE-02: the same function returns
   //--- BASELINE_NOT_APPLICABLE_THIS_CONFIG (NOT FAIL) when run with
   //--- today's actual defaults (TP=1R, costs on, gates on) - even though
   //--- the observed figures are given as numerically IDENTICAL to the
   //--- reference, proving the verdict is driven by the CONFIG mismatch,
   //--- not by the numbers.
   void T277_BaselineNotApplicableOnCurrentDefaults()
     {
      GZ_BaselineActiveConfig active; active.Clear();
      active.tp_r_multiple = 1.0;             // today's actual default (spec Section 2, Bug 5 evidence)
      active.be_trigger_r  = 0.0;
      active.use_real_spread_fills = true;    // today's actual default
      active.costs_configured      = true;    // today's actual default
      active.use_daily_loss_limit  = true;    // today's actual default

      string detail;
      ENUM_GZ_BASELINE_VERDICT v = GZBaselineCompare(
         412, 0.507, 0.5218, 2.059, 215.0, 6.0,
         412, 0.507, 0.5218, 2.059, 215.0, 6.0,
         active, detail);

      bool ok = (v==GZ_BASELINE_NOT_APPLICABLE) && (v!=GZ_BASELINE_FAIL);
      AddResult("T277", ok, StringFormat("today's actual defaults (TP=1R, costs on, gates on), numerically identical to reference: verdict=%s (must be NOT_APPLICABLE, never FAIL) | %s",
                GZBaselineVerdictToString(v), detail));
     }

public:
                     CGZCostRSymTests(CGZLogger *logger=NULL) { m_logger=logger; }

   int               ResultCount() const { return ArraySize(m_results); }
   GZ_TestResult     GetResult(int i) const { return m_results[i]; }

   void              RunAll()
     {
      T269_RSymSlBothExactMinusOne();
      T270_RSymRegressionFlagOff();
      T271_RSymTpBothExactMultiple();
      T272_CostWireConfiguredDiffersFromGross();
      T273_CostWireUnconfiguredEqualsGross();
      T274_CostWireReachesRobustness();
      T275_CostDoubleChargeGuardExcludesSpread();
      T276_BaselinePassOnOriginalConfig();
      T277_BaselineNotApplicableOnCurrentDefaults();
     }
  };

#endif // __GZ_COST_RSYM_TESTS_MQH__
