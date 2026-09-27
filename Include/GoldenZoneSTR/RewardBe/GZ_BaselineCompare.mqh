//+------------------------------------------------------------------+
//| GZ_BaselineCompare.mqh                                            |
//| GoldenZone STR - Phase "Cost Unification + R-Symmetry Fix"        |
//| Sub-phase E - single source of truth for the InpP155Ref* baseline |
//| comparison (spec Bug 5).                                          |
//|                                                                    |
//| BEFORE this file: the same MathAbs(...)<=tolerance PASS/FAIL logic|
//| against the six InpP155Ref* EA inputs was hand-copied in THREE     |
//| independent places (Phase 15.7's R07 in the main .mq5,             |
//| GZ_RewardBeEngine.mqh's V03, and Phase 15.8's own regression        |
//| section, which is the same R07 call reused - see Phase157PostRun). |
//| None of the three knew about the others, and none of them checked |
//| whether the ACTIVE run configuration was even the one InpP155Ref*  |
//| describes (TP=2R, BE off, every FCIS/concurrency/cost switch OFF/  |
//| unconfigured) - so a run under today's realistic-cost defaults     |
//| would legitimately mismatch and print as an unexplained            |
//| contradiction ("one section says 412, another shows a different    |
//| number") that looked exactly like a bug.                           |
//|                                                                    |
//| This file keeps the six InpP155Ref* EA inputs exactly as they are  |
//| (user-facing "what do we expect" values, per spec Section 8 - NOT  |
//| auto-recomputed here) but gives every comparison ONE shared         |
//| formula and ONE shared, unmistakable third verdict for "the active |
//| configuration does not match the baseline this constant describes" |
//| - textually distinct from both PASS and FAIL, per spec Section 8.  |
//+------------------------------------------------------------------+
#ifndef __GZ_BASELINE_COMPARE_MQH__
#define __GZ_BASELINE_COMPARE_MQH__

enum ENUM_GZ_BASELINE_VERDICT
  {
   GZ_BASELINE_PASS = 0,
   GZ_BASELINE_FAIL,
   GZ_BASELINE_NOT_APPLICABLE   // active config != what InpP155Ref* describes - NOT a regression signal
  };

string GZBaselineVerdictToString(ENUM_GZ_BASELINE_VERDICT v)
  {
   if(v==GZ_BASELINE_PASS) return "PASS";
   if(v==GZ_BASELINE_FAIL) return "FAIL";
   return "BASELINE_NOT_APPLICABLE_THIS_CONFIG";
  }

//--- Every switch that can make a run diverge from the ORIGINAL
//--- 412-trade/50.7%-win/0.5218R-expectancy/2.059-PF/215R-net/6R-maxDD
//--- baseline (established before FCIS/Concurrency/realistic-cost-
//--- defaults existed at all - see spec Section 2 evidence). A run only
//--- "matches the baseline's own configuration" when every one of these
//--- is at the value that baseline was captured under.
struct GZ_BaselineActiveConfig
  {
   double   tp_r_multiple;
   double   be_trigger_r;
   bool     use_session_hour_gate;
   bool     use_real_spread_fills;
   bool     use_min_risk_gate;
   bool     allow_concurrent_same_direction_setups;
   bool     allow_survive_opposite_break;
   bool     use_daily_loss_limit;
   bool     costs_configured;

   void Clear()
     {
      tp_r_multiple = 0.0; be_trigger_r = 0.0;
      use_session_hour_gate = false; use_real_spread_fills = false; use_min_risk_gate = false;
      allow_concurrent_same_direction_setups = false; allow_survive_opposite_break = false;
      use_daily_loss_limit = false; costs_configured = false;
     }

   bool MatchesOriginalBaselineConfig() const
     {
      return (MathAbs(tp_r_multiple-2.0)<0.000001) && (be_trigger_r<=0.0) &&
             !use_session_hour_gate && !use_real_spread_fills && !use_min_risk_gate &&
             !allow_concurrent_same_direction_setups && !allow_survive_opposite_break &&
             !use_daily_loss_limit && !costs_configured;
     }

   string ToString() const
     {
      return StringFormat(
         "TP=%.2fR BE=%s | SessionHourGate=%s RealSpreadFills=%s MinRiskGate=%s | "+
         "ConcurrentSameDir=%s SurviveOppositeBreak=%s DailyLossLimit=%s CostsConfigured=%s",
         tp_r_multiple, (be_trigger_r>0.0)?DoubleToString(be_trigger_r,2)+"R":"OFF",
         use_session_hour_gate?"ON":"OFF", use_real_spread_fills?"ON":"OFF", use_min_risk_gate?"ON":"OFF",
         allow_concurrent_same_direction_setups?"ON":"OFF", allow_survive_opposite_break?"ON":"OFF",
         use_daily_loss_limit?"ON":"OFF", costs_configured?"ON":"OFF");
     }
  };

//--- THE single shared comparison. `ref_trades<=0` skips the exact trade-
//--- count check (mirrors the pre-existing V03 "ext_trades<=0" allowance).
//--- Tolerances are the same ones every pre-this-phase call site already
//--- used (rounding of the printed baseline figures; trade count exact).
//--- `detail` always includes, on the SAME line as the verdict, the exact
//--- active configuration that was actually running - so a mismatch reads
//--- immediately as "these InpP155Ref* values describe a different
//--- configuration" rather than as an unexplained contradiction.
ENUM_GZ_BASELINE_VERDICT GZBaselineCompare(int trades, double win, double exp, double pf, double net, double dd,
                                            int ref_trades, double ref_win, double ref_exp, double ref_pf,
                                            double ref_net, double ref_dd,
                                            const GZ_BaselineActiveConfig &active, string &detail)
  {
   double dw = MathAbs(win-ref_win), de = MathAbs(exp-ref_exp), dp = MathAbs(pf-ref_pf),
          dn = MathAbs(net-ref_net), dd_diff = MathAbs(dd-ref_dd);
   bool trades_ok  = (ref_trades<=0) || (trades==ref_trades);
   bool numeric_ok = trades_ok && (dw<=0.0006) && (de<=0.0002) && (dp<=0.0015) && (dn<=0.6) && (dd_diff<=0.05);

   bool config_matches = active.MatchesOriginalBaselineConfig();
   ENUM_GZ_BASELINE_VERDICT verdict = !config_matches ? GZ_BASELINE_NOT_APPLICABLE
                                                       : (numeric_ok ? GZ_BASELINE_PASS : GZ_BASELINE_FAIL);

   string tail = "";
   if(verdict==GZ_BASELINE_NOT_APPLICABLE)
      tail = " (InpP155Ref* describe a different configuration than the one just run - NOT a regression signal; see active config above)";
   else if(verdict==GZ_BASELINE_FAIL)
      tail = " REGRESSION - the active configuration matches the InpP155Ref* baseline's own configuration but produced a different result.";

   detail = StringFormat(
      "verdict=%s | active config: %s | observed: trades=%d win=%.4f exp=%.4f pf=%.3f net_r=%.3f max_dd=%.2f | "+
      "InpP155Ref*: trades=%d win=%.4f exp=%.4f pf=%.3f net_r=%.1f max_dd=%.2f | "+
      "|diff| win=%.5f exp=%.5f pf=%.4f net_r=%.3f max_dd=%.3f%s",
      GZBaselineVerdictToString(verdict), active.ToString(),
      trades, win, exp, pf, net, dd,
      ref_trades, ref_win, ref_exp, ref_pf, ref_net, ref_dd,
      dw, de, dp, dn, dd_diff, tail);

   return verdict;
  }

#endif // __GZ_BASELINE_COMPARE_MQH__
