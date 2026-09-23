//+------------------------------------------------------------------+
//| GZ_RewardBeTests.mqh                                              |
//| GoldenZone STR - Phase 15.5 - deterministic unit tests T167-T180  |
//|                                                                    |
//| Synthetic fixtures only (never real market data, never OOS data). |
//| Every scenario reuses the Phase 9 raw-M5 fixture (T89) whose      |
//| single setup produces exactly ONE baseline TOUCH trade:            |
//|   entry fill = M1[0].low = 102, STRUCTURE SL = leg origin = 80,    |
//|   initial risk = 22, TP 2R = 146, TP 3R = 168, BE 0.5R trigger=113 |
//| and varies only the M1 path AFTER entry, so each test isolates one |
//| exit behavior. The suite keeps its own result list; the main test  |
//| harness copies it into its own list (see CGZTestHarness::RunAll).  |
//+------------------------------------------------------------------+
#ifndef __GZ_REWARDBE_TESTS_MQH__
#define __GZ_REWARDBE_TESTS_MQH__

#include "GZ_RewardBeTypes.mqh"
#include "GZ_RunDetail.mqh"
#include "GZ_RewardBeEngine.mqh"
#include "..\Experiment\GZ_ExperimentTypes.mqh"
#include "..\Experiment\GZ_ExperimentRunner.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZRewardBeTests
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

   bool Near(double a, double b) const { return MathAbs(a-b)<0.000001; }

   MqlRates MakeBar(datetime t, double o, double h, double l, double c)
     {
      MqlRates r;
      r.time=t; r.open=o; r.high=h; r.low=l; r.close=c;
      r.tick_volume=100; r.spread=1; r.real_volume=0;
      return r;
     }

   MqlRates MakeHL(datetime t, double high, double low)
     {
      double mid = (high+low)/2.0;
      return MakeBar(t, mid, high, low, mid);
     }

   datetime MakeTime(int y,int mo,int d,int h,int mi) const
     {
      MqlDateTime dt;
      dt.year=y; dt.mon=mo; dt.day=d; dt.hour=h; dt.min=mi; dt.sec=0;
      return StructToTime(dt);
     }

   //--- Scenario kinds (M1 path after/around the single baseline entry):
   //---  0 C   TP straight (one bar past TP2)          4 PEAK3 peak +3R then fade, TP2/TP3 hit, TP5 not
   //---  1 A   +0.6R, retrace through entry, then SL    5 RETRACE BE arms on a candle that also reaches the new stop
   //---  2 B   +0.6R, retrace through entry, then TP    6 EB_ARM BE arms on the ENTRY candle
   //---  3 D   SL straight                              7 EB_TP  TP touched on the ENTRY candle
   //---  8 CENSOR TP2 hit early (+2.2R), price only later reaches +3R
   void BuildScenario(int kind, MqlRates &m1[], MqlRates &m5[])
     {
      datetime t0 = MakeTime(2026,3,2,9,0);
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

      datetime b = m5[10].time + 360;   // same first-M1 offset the Phase 9 fixture uses
      MqlRates k0 = MakeBar(b, 104,104.5,102,102.5);   // default entry candle: crosses 103.684, fills at low=102
      switch(kind)
        {
         case 0:
            ArrayResize(m1,2);
            m1[0]=k0; m1[1]=MakeBar(b+60, 155,160,154,158);
            break;
         case 1:
            ArrayResize(m1,4);
            m1[0]=k0;
            m1[1]=MakeBar(b+60,  108,115,105,110);
            m1[2]=MakeBar(b+120, 110,112,100,101);
            m1[3]=MakeBar(b+180, 101,102,79,80);
            break;
         case 2:
            ArrayResize(m1,4);
            m1[0]=k0;
            m1[1]=MakeBar(b+60,  108,115,105,110);
            m1[2]=MakeBar(b+120, 110,112,100,101);
            m1[3]=MakeBar(b+180, 101,160,96,150);
            break;
         case 3:
            ArrayResize(m1,2);
            m1[0]=k0; m1[1]=MakeBar(b+60, 100,101,79,80);
            break;
         case 4:
            ArrayResize(m1,3);
            m1[0]=k0;
            m1[1]=MakeBar(b+60,  150,168,140,160);
            m1[2]=MakeBar(b+120, 160,161,150,155);
            break;
         case 5:
            ArrayResize(m1,3);
            m1[0]=k0;
            m1[1]=MakeBar(b+60,  108,115,101,110);
            m1[2]=MakeBar(b+120, 110,112,105,111);
            break;
         case 6:
            ArrayResize(m1,2);
            m1[0]=MakeBar(b, 104,113.5,102,113);
            m1[1]=MakeBar(b+60, 112,113,100,101);
            break;
         case 7:
            ArrayResize(m1,2);
            m1[0]=MakeBar(b, 104,150,102,140);
            m1[1]=MakeBar(b+60, 140,141,139,140);
            break;
         default: // 8
            ArrayResize(m1,3);
            m1[0]=k0;
            m1[1]=MakeBar(b+60,  120,150,118,148);
            m1[2]=MakeBar(b+120, 148,168,147,160);
            break;
        }
     }

   void RunScenario(int kind, double tp, double trig, GZ_ExperimentResult &res, CGZRunDetail *d)
     {
      MqlRates m1[], m5[];
      BuildScenario(kind, m1, m5);
      CGZExperimentRunner runner(m_logger);
      GZ_ExperimentConfig cfg; cfg.Default();
      cfg.time_config.broker_offset_known = true;
      cfg.exit_config.tp_r_multiple = tp;
      cfg.exit_config.be_trigger_r  = trig;
      runner.RunSingleDetailed(cfg, m1, m5, "DS_P155", GZ_VAL_VALID, GZ_VAL_VALID, res, d);
     }

   //--- T167 -------------------------------------------------------------
   void T167_DetailCaptureBaseline()
     {
      GZ_ExperimentResult r; CGZRunDetail d;
      RunScenario(0, 2.0, 0.0, r, GetPointer(d));
      bool ok = (r.trade_count==1) && (d.count==1) && (d.exit_reason[0]==(int)GZ_EXIT_TP_HIT) &&
                Near(d.realized_r[0],2.0) && Near(d.initial_risk[0],22.0) && Near(d.entry_price[0],102.0) &&
                (r.metrics.trade.trade_count==1) && (r.metrics.trade.winners==1) && Near(r.metrics.trade.net_r,2.0) &&
                Near(d.NetR(), r.metrics.trade.net_r);
      AddResult("T167", ok, StringFormat("trades=%d detail=%d reason=%d R=%.4f risk=%.2f entry=%.2f metrics_net_r=%.4f (expect 1 trade, TP_HIT, 2R, risk 22, entry 102)",
                r.trade_count, d.count, d.count>0?d.exit_reason[0]:-1, d.count>0?d.realized_r[0]:0.0,
                d.count>0?d.initial_risk[0]:0.0, d.count>0?d.entry_price[0]:0.0, r.metrics.trade.net_r));
     }

   //--- T168 -------------------------------------------------------------
   void T168_TpSweepChangesBehavior()
     {
      GZ_ExperimentResult r2, r3, r5; CGZRunDetail d2, d3, d5;
      RunScenario(4, 2.0, 0.0, r2, GetPointer(d2));
      RunScenario(4, 3.0, 0.0, r3, GetPointer(d3));
      RunScenario(4, 5.0, 0.0, r5, GetPointer(d5));
      double expect_dataend_r = (155.0-102.0)/22.0;
      bool ok = (d2.count==1 && d3.count==1 && d5.count==1) &&
                (d2.exit_reason[0]==(int)GZ_EXIT_TP_HIT) && Near(d2.realized_r[0],2.0) &&
                (d3.exit_reason[0]==(int)GZ_EXIT_TP_HIT) && Near(d3.realized_r[0],3.0) &&
                (d5.exit_reason[0]==(int)GZ_EXIT_DATA_END) && Near(d5.realized_r[0],expect_dataend_r) &&
                Near(d2.entry_price[0],d3.entry_price[0]) && Near(d3.entry_price[0],d5.entry_price[0]) &&
                (d2.entry_time[0]==d3.entry_time[0]) && (d3.entry_time[0]==d5.entry_time[0]);
      AddResult("T168", ok, StringFormat("TP2 reason=%d R=%.3f | TP3 reason=%d R=%.3f | TP5 reason=%d R=%.3f (entry identical across TPs)",
                d2.count>0?d2.exit_reason[0]:-1, d2.count>0?d2.realized_r[0]:0.0,
                d3.count>0?d3.exit_reason[0]:-1, d3.count>0?d3.realized_r[0]:0.0,
                d5.count>0?d5.exit_reason[0]:-1, d5.count>0?d5.realized_r[0]:0.0));
     }

   //--- T169 -------------------------------------------------------------
   void T169_BeProtectsFromSl()
     {
      GZ_ExperimentResult roff, ron; CGZRunDetail doff, don;
      RunScenario(1, 2.0, 0.0, roff, GetPointer(doff));
      RunScenario(1, 2.0, 0.5, ron,  GetPointer(don));
      CGZRewardBeEngine eng(m_logger);
      GZ_PairStats ps;
      eng.TestComparePairs(GetPointer(doff), GetPointer(don), ps);
      bool ok = (doff.count==1 && don.count==1) &&
                (doff.exit_reason[0]==(int)GZ_EXIT_SL_HIT) && Near(doff.realized_r[0],-1.0) &&
                (don.exit_reason[0]==(int)GZ_EXIT_BREAK_EVEN) && Near(don.realized_r[0],0.0) && don.be_triggered[0] &&
                (ps.matched==1) && (ps.cat_a==1) && (ps.cat_b==0) && (ps.entry_mismatch==0) && Near(ps.dr_a,1.0);
      AddResult("T169", ok, StringFormat("off reason=%d R=%.3f | on reason=%d R=%.3f | A=%d B=%d dR_A=%.3f",
                doff.count>0?doff.exit_reason[0]:-1, doff.count>0?doff.realized_r[0]:0.0,
                don.count>0?don.exit_reason[0]:-1, don.count>0?don.realized_r[0]:0.0, ps.cat_a, ps.cat_b, ps.dr_a));
     }

   //--- T170 -------------------------------------------------------------
   void T170_BePrematureExit()
     {
      GZ_ExperimentResult roff, ron; CGZRunDetail doff, don;
      RunScenario(2, 2.0, 0.0, roff, GetPointer(doff));
      RunScenario(2, 2.0, 0.5, ron,  GetPointer(don));
      CGZRewardBeEngine eng(m_logger);
      GZ_PairStats ps;
      eng.TestComparePairs(GetPointer(doff), GetPointer(don), ps);
      bool ok = (doff.count==1 && don.count==1) &&
                (doff.exit_reason[0]==(int)GZ_EXIT_TP_HIT) && Near(doff.realized_r[0],2.0) &&
                (don.exit_reason[0]==(int)GZ_EXIT_BREAK_EVEN) && Near(don.realized_r[0],0.0) &&
                (ps.cat_b==1) && (ps.cat_a==0) && (ps.entry_mismatch==0) && Near(ps.dr_b,-2.0);
      AddResult("T170", ok, StringFormat("off reason=%d R=%.3f | on reason=%d R=%.3f | A=%d B=%d dR_B=%.3f",
                doff.count>0?doff.exit_reason[0]:-1, doff.count>0?doff.realized_r[0]:0.0,
                don.count>0?don.exit_reason[0]:-1, don.count>0?don.realized_r[0]:0.0, ps.cat_a, ps.cat_b, ps.dr_b));
     }

   //--- T171 -------------------------------------------------------------
   void T171_NoChangeCategories()
     {
      CGZRewardBeEngine eng(m_logger);
      GZ_ExperimentResult ra, rb, rc, rd; CGZRunDetail c_off, c_on, d_off, d_on;
      RunScenario(0, 2.0, 0.0, ra, GetPointer(c_off));
      RunScenario(0, 2.0, 0.5, rb, GetPointer(c_on));
      RunScenario(3, 2.0, 0.0, rc, GetPointer(d_off));
      RunScenario(3, 2.0, 0.5, rd, GetPointer(d_on));
      GZ_PairStats pc, pd;
      eng.TestComparePairs(GetPointer(c_off), GetPointer(c_on), pc);
      eng.TestComparePairs(GetPointer(d_off), GetPointer(d_on), pd);
      bool ok = (pc.cat_c==1) && (pc.no_change==1) && (pc.cat_e==0) &&
                (pd.cat_d==1) && (pd.no_change==1) && (pd.be_armed_total==0) && (pd.cat_e==0);
      AddResult("T171", ok, StringFormat("TP-straight: C=%d nochg=%d | SL-straight: D=%d nochg=%d armed=%d", pc.cat_c, pc.no_change, pd.cat_d, pd.no_change, pd.be_armed_total));
     }

   //--- T172: classification edge cases on hand-built populations ------------
   void T172_PairClassificationEdgeCases()
     {
      CGZRunDetail off, on;
      int SL=(int)GZ_EXIT_SL_HIT, TP=(int)GZ_EXIT_TP_HIT, BE=(int)GZ_EXIT_BREAK_EVEN, DE=(int)GZ_EXIT_DATA_END, SE=(int)GZ_EXIT_SESSION_EXIT;
      // id, entry_time, entry_price, dir, exit_time, reason, R, risk, be_trig, conflict, be_entry_bar, retrace, mae, mfe
      off.AddTrade(1,1001,100.0,0,2001,SL,-1.0,10.0,false,false,false,false,1.0,0.2);
      off.AddTrade(2,1002,100.0,0,2002,TP, 2.0,10.0,false,false,false,false,0.3,2.1);
      off.AddTrade(3,1003,100.0,0,2003,DE, 0.5,10.0,false,false,false,false,0.1,0.6);
      off.AddTrade(4,1004,100.0,0,2004,DE, 0.7,10.0,false,false,false,false,0.1,0.8);
      off.AddTrade(5,1005,100.0,0,2005,SE, 0.2,10.0,false,false,false,false,0.1,0.3);
      off.AddTrade(6,1006,100.0,0,2006,SL,-1.0,10.0,false,false,false,false,1.0,0.1);
      off.AddTrade(7,1007,100.0,0,2007,TP, 2.0,10.0,false,false,false,false,0.1,2.0);   // absent from ON
      on.AddTrade(1,1001,100.0,0,2001,BE, 0.0,10.0,true, false,false,false,1.0,0.7);
      on.AddTrade(2,1002,100.0,0,2002,BE, 0.0,10.0,true, false,false,false,0.3,0.7);
      on.AddTrade(3,1003,100.0,0,2003,BE, 0.0,10.0,true, false,false,false,0.1,0.6);
      on.AddTrade(4,1004,100.0,0,2004,DE, 0.7,10.0,false,false,false,false,0.1,0.8);
      on.AddTrade(5,1005,100.0,0,2005,TP, 2.0,10.0,false,false,false,false,0.1,2.0);   // SESSION_EXIT -> TP: not a BE-only difference
      on.AddTrade(6,1006,100.0,0,2006,SL,-1.0,10.0,false,false,false,false,1.0,0.1);
      on.AddTrade(99,1099,100.0,0,2099,SL,-1.0,10.0,false,false,false,false,1.0,0.1);  // absent from OFF

      CGZRewardBeEngine eng(m_logger);
      GZ_PairStats ps;
      eng.TestComparePairs(GetPointer(off), GetPointer(on), ps);
      bool ok = (ps.matched==6) && (ps.unmatched_on==1) && (ps.unmatched_off==1) &&
                (ps.cat_a==1) && (ps.cat_b==1) && (ps.cat_c==0) && (ps.cat_d==1) && (ps.cat_e==3) &&
                (ps.e_be_from_other==1) && (ps.e_same_other==1) && (ps.e_anomaly==1) &&
                (ps.cat_a+ps.cat_b+ps.cat_c+ps.cat_d+ps.cat_e==ps.matched) &&
                (ps.no_change==2) && (ps.be_armed_total==3) && (ps.be_armed_no_change==0) &&
                Near(ps.dr_a,1.0) && Near(ps.dr_b,-2.0);
      AddResult("T172", ok, StringFormat("matched=%d unm_on=%d unm_off=%d A=%d B=%d C=%d D=%d E=%d (be_from_other=%d same=%d anomaly=%d) nochg=%d armed=%d",
                ps.matched, ps.unmatched_on, ps.unmatched_off, ps.cat_a, ps.cat_b, ps.cat_c, ps.cat_d, ps.cat_e,
                ps.e_be_from_other, ps.e_same_other, ps.e_anomaly, ps.no_change, ps.be_armed_total));
     }

   //--- T173: BE trigger >= TP is mechanically identical to BE off ---------------
   void T173_BeInactiveEquivalent()
     {
      CGZRewardBeEngine eng(m_logger);
      GZ_ExperimentResult r0, r1, r2; CGZRunDetail d0, d1, d2;
      RunScenario(2, 2.0, 0.0, r0, GetPointer(d0));
      RunScenario(2, 2.0, 2.0, r1, GetPointer(d1));   // trigger == TP
      RunScenario(2, 2.0, 3.0, r2, GetPointer(d2));   // trigger  > TP
      GZ_PairStats p1, p2;
      eng.TestComparePairs(GetPointer(d0), GetPointer(d1), p1);
      eng.TestComparePairs(GetPointer(d0), GetPointer(d2), p2);
      bool ok = (p1.cat_c==1 && p1.no_change==1 && p1.cat_e==0 && p1.cat_a==0 && p1.cat_b==0) &&
                (p2.cat_c==1 && p2.no_change==1 && p2.cat_e==0 && p2.cat_a==0 && p2.cat_b==0) &&
                Near(r0.metrics.trade.net_r,r1.metrics.trade.net_r) && Near(r0.metrics.trade.net_r,r2.metrics.trade.net_r);
      AddResult("T173", ok, StringFormat("trigger==TP: C=%d nochg=%d | trigger>TP: C=%d nochg=%d | net_r %.3f/%.3f/%.3f",
                p1.cat_c, p1.no_change, p2.cat_c, p2.no_change, r0.metrics.trade.net_r, r1.metrics.trade.net_r, r2.metrics.trade.net_r));
     }

   //--- T174: the two intrabar diagnostics (counters only - behavior asserted unchanged) --
   void T174_IntrabarDiagnostics()
     {
      // (a) BE armed on the ENTRY candle; that candle's own range also reaches the new stop (entry=stop level)
      GZ_ExperimentResult ra; CGZRunDetail da;
      RunScenario(6, 2.0, 0.5, ra, GetPointer(da));
      bool ok_a = (da.count==1) && da.be_triggered[0] && da.be_on_entry_bar[0] && da.be_arm_retrace[0] &&
                  (da.exit_reason[0]==(int)GZ_EXIT_BREAK_EVEN) && Near(da.realized_r[0],0.0) &&
                  (da.CountBeOnEntryBar()==1) && (da.CountRetrace()==1) && (da.CountRetraceNonEntryBar()==0);

      // (b) BE armed on a LATER candle whose own range also reaches the new stop; the engine still applies the
      //     new stop only from the NEXT candle (baseline unchanged): the trade is NOT stopped on the arming candle.
      GZ_ExperimentResult rb; CGZRunDetail db;
      RunScenario(5, 2.0, 0.5, rb, GetPointer(db));
      bool ok_b = (db.count==1) && db.be_triggered[0] && !db.be_on_entry_bar[0] && db.be_arm_retrace[0] &&
                  (db.exit_reason[0]==(int)GZ_EXIT_DATA_END) && (db.CountRetraceNonEntryBar()==1);

      // (c) TP touched on the entry candle itself (baseline behavior kept, now counted)
      GZ_ExperimentResult rc; CGZRunDetail dc;
      RunScenario(7, 2.0, 0.0, rc, GetPointer(dc));
      bool ok_c = (dc.count==1) && (dc.exit_reason[0]==(int)GZ_EXIT_TP_HIT) && (dc.exit_time[0]==dc.entry_time[0]) &&
                  (dc.CountEntryBarExits(-1)==1) && (dc.CountEntryBarExits((int)GZ_EXIT_TP_HIT)==1) && (dc.CountEntryBarExits((int)GZ_EXIT_SL_HIT)==0);

      // (d) a normal trade is not counted as an entry-candle exit
      GZ_ExperimentResult rd; CGZRunDetail dd;
      RunScenario(0, 2.0, 0.0, rd, GetPointer(dd));
      bool ok_d = (dd.count==1) && (dd.CountEntryBarExits(-1)==0) && (dd.CountConflict()==0);

      AddResult("T174", (ok_a && ok_b && ok_c && ok_d),
                StringFormat("entry-candle BE arm=%s | later-candle arm w/ retrace, no early stop=%s | entry-candle TP exit counted=%s | normal trade not counted=%s",
                             ok_a?"ok":"FAIL", ok_b?"ok":"FAIL", ok_c?"ok":"FAIL", ok_d?"ok":"FAIL"));
     }

   //--- T175 -------------------------------------------------------------
   void T175_Determinism()
     {
      GZ_ExperimentResult r1, r2; CGZRunDetail d1, d2;
      RunScenario(1, 2.0, 0.5, r1, GetPointer(d1));
      RunScenario(1, 2.0, 0.5, r2, GetPointer(d2));
      bool ok = (d1.count==d2.count) && (d1.count==1) && (d1.exit_reason[0]==d2.exit_reason[0]) &&
                Near(d1.realized_r[0],d2.realized_r[0]) && (d1.exit_time[0]==d2.exit_time[0]) &&
                Near(d1.mae_r[0],d2.mae_r[0]) && Near(d1.mfe_r[0],d2.mfe_r[0]) &&
                Near(r1.metrics.trade.net_r,r2.metrics.trade.net_r);
      AddResult("T175", ok, StringFormat("run1 reason=%d R=%.4f mfe=%.4f | run2 reason=%d R=%.4f mfe=%.4f",
                d1.count>0?d1.exit_reason[0]:-1, d1.count>0?d1.realized_r[0]:0.0, d1.count>0?d1.mfe_r[0]:0.0,
                d2.count>0?d2.exit_reason[0]:-1, d2.count>0?d2.realized_r[0]:0.0, d2.count>0?d2.mfe_r[0]:0.0));
     }

   //--- T176: grids -------------------------------------------------------
   void T176_GridDefinitions()
     {
      double tps[], trigs[];
      GZRewardBeTpGrid(tps);
      GZRewardBeTriggerGrid(trigs);
      int off_n, act_n, eq_n;
      CGZRewardBeEngine::CountGrid(off_n, act_n, eq_n);
      bool ok = (ArraySize(tps)==10) && Near(tps[0],0.5) && Near(tps[9],5.0) && Near(tps[3],2.0) &&
                (ArraySize(trigs)==12) && Near(trigs[0],0.25) && Near(trigs[11],5.0) && Near(trigs[7],2.0) &&
                (off_n==10) && (act_n==75) && (eq_n==45) && ((act_n+eq_n)==ArraySize(tps)*ArraySize(trigs));
      AddResult("T176", ok, StringFormat("TP levels=%d BE triggers=%d | BE-off runs=%d BE-active=%d trigger>=TP=%d", ArraySize(tps), ArraySize(trigs), off_n, act_n, eq_n));
     }

   //--- T177: Reach is exit-censored in a normal run; the TP=1000R reference run is not ---
   void T177_UncensoredReachReference()
     {
      GZ_ExperimentResult rn, rr; CGZRunDetail dn, dr;
      RunScenario(8, 2.0, 0.0, rn, GetPointer(dn));
      RunScenario(8, GZ_RB_REFERENCE_TP_R, 0.0, rr, GetPointer(dr));
      int L2 = 3, L3 = 5;   // GZ_REACH_LEVELS index of 2.0R and 3.0R
      bool ok = (dn.count==1 && dr.count==1) &&
                (dn.exit_reason[0]==(int)GZ_EXIT_TP_HIT) && dn.reach[L2] && !dn.reach[L3] &&
                (dr.exit_reason[0]==(int)GZ_EXIT_DATA_END) && (dr.CountReason((int)GZ_EXIT_TP_HIT)==0) && dr.reach[L2] && dr.reach[L3] &&
                (dr.ReachCount(L3)==1) && (dn.ReachCount(L3)==0);
      AddResult("T177", ok, StringFormat("TP=2R run: reason=%d reach>=2R=%s reach>=3R=%s | TP=1000R reference: reason=%d TP_HIT=%d reach>=3R=%s (censoring is real; reach never converted into win rate)",
                dn.count>0?dn.exit_reason[0]:-1, dn.count>0&&dn.reach[L2]?"y":"n", dn.count>0&&dn.reach[L3]?"y":"n",
                dr.count>0?dr.exit_reason[0]:-1, dr.CountReason((int)GZ_EXIT_TP_HIT), dr.count>0&&dr.reach[L3]?"y":"n"));
     }

   //--- T178: engine guards ----------------------------------------------------
   void T178_EngineGuards()
     {
      MqlRates m1[], m5[];
      BuildScenario(2, m1, m5);
      GZ_ExperimentConfig cfg; cfg.Default(); cfg.time_config.broker_offset_known = true;
      GZ_RewardBeBaselineRef bref; bref.Clear();
      datetime first = m5[0].time, last = m5[ArraySize(m5)-1].time;

      CGZRewardBeEngine e1(m_logger);
      // development range END after the protected OOS start -> rejected, nothing executed
      ENUM_GZ_RB_STATUS s1 = e1.Run(cfg, m1, m5, "DS", GZ_VAL_VALID, GZ_VAL_VALID, true, first, (datetime)(last + 86400), last, true, bref);
      bool ok1 = (s1==GZ_RB_STATUS_REJECTED_OOS_OVERLAP) && (e1.ExperimentCount()==0) && (e1.RowCount()==0);

      CGZRewardBeEngine e2(m_logger);
      MqlRates empty1[], empty5[];
      ENUM_GZ_RB_STATUS s2 = e2.Run(cfg, empty1, empty5, "DS", GZ_VAL_VALID, GZ_VAL_VALID, true, first, last, (datetime)(last + 86400), true, bref);
      bool ok2 = (s2==GZ_RB_STATUS_NO_DATA) && (e2.ExperimentCount()==0);
      AddResult("T178", (ok1 && ok2), StringFormat("dev_end>oos_start -> status=%d runs=%d rows=%d | no data -> status=%d runs=%d", (int)s1, e1.ExperimentCount(), e1.RowCount(), (int)s2, e2.ExperimentCount()));
     }

   //--- T179 / T180: full engine on the synthetic fixture ---------------------------
   void T179_T180_EngineFullRunSmoke()
     {
      MqlRates m1[], m5[];
      BuildScenario(2, m1, m5);
      GZ_ExperimentConfig cfg; cfg.Default(); cfg.time_config.broker_offset_known = true;
      GZ_RewardBeBaselineRef bref; bref.Clear();
      datetime first = m5[0].time, last = m5[ArraySize(m5)-1].time;

      CGZRewardBeEngine eng(m_logger);
      ENUM_GZ_RB_STATUS st = eng.Run(cfg, m1, m5, "DS_SMOKE", GZ_VAL_VALID, GZ_VAL_VALID, true,
                                       (datetime)(first - 86400), (datetime)(last + 86400), (datetime)(last + 2*86400), true, bref);

      bool counts_ok = (st==GZ_RB_STATUS_OK) && (eng.RowCount()==131) && (eng.ExperimentCount()==133) &&
                       (eng.CountKind(GZ_RB_OFF)==10) && (eng.CountKind(GZ_RB_BE_ACTIVE)==75) &&
                       (eng.CountKind(GZ_RB_BE_INACTIVE_EQUIVALENT)==45) && (eng.CountKind(GZ_RB_REFERENCE_ONLY)==1);

      string must_pass[] = {"V01_TP_SWEEP_CHANGES_BEHAVIOR","V04_BE_INACTIVE_EQUIVALENT_EQUALS_OFF","V05_BE_SETTINGS_CHANGE_EXITS",
                            "V06_ENTRY_LOGIC_UNCHANGED","V07_DATASET_BOUNDARY","V08_FINAL_OOS_NOT_ACCESSED","V09_DETERMINISM_REPEAT",
                            "V10_REACH_IS_NOT_WIN_RATE","V11_DETAIL_MATCHES_METRICS","V12_PAIR_CATEGORIES_PARTITION"};
      int good = 0;
      string bad_ids = "";
      for(int k=0;k<ArraySize(must_pass);k++)
        {
         bool found = false, pass = false;
         for(int v=0; v<eng.ValidationCount(); v++)
           {
            GZ_TestResult t = eng.GetValidation(v);
            if(t.id==must_pass[k]) { found = true; pass = (t.passed && !t.blocked); break; }
           }
         if(found && pass) good++;
         else bad_ids += must_pass[k] + " ";
        }
      bool v_ok = (good==ArraySize(must_pass));
      // V02/V03 must be BLOCKED (no reference supplied), never silently passed
      int blocked = eng.ValidationBlockedCount();
      bool blocked_ok = (blocked==2) && (eng.ValidationFailCount()==0);

      AddResult("T179", (counts_ok && v_ok && blocked_ok),
                StringFormat("status=%d rows=%d (expect 131) experiments=%d (expect 133 = 131 + 2 determinism repeats) | runtime validations passing=%d/%d %s| blocked=%d (expect 2: V02,V03) failed=%d",
                             (int)st, eng.RowCount(), eng.ExperimentCount(), good, ArraySize(must_pass), bad_ids, blocked, eng.ValidationFailCount()));

      string report = eng.BuildReport("", "", 0, 0);
      string csv    = eng.BuildMatrixCsv();
      string pcsv   = eng.BuildPairCsv();
      int csv_lines = 0, pcsv_lines = 0;
      for(int i=0;i<StringLen(csv);i++)  if(StringGetCharacter(csv,i)=='\n')  csv_lines++;
      for(int i=0;i<StringLen(pcsv);i++) if(StringGetCharacter(pcsv,i)=='\n') pcsv_lines++;
      bool rep_ok = (StringFind(report, "REFERENCE_ONLY / UNCENSORED_REACH")>=0 || StringFind(report, "REFERENCE_ONLY/UNCENSORED_REACH")>=0) &&
                    (StringFind(report, "C. BE effect")>=0) && (StringFind(report, "E. Reach matrix")>=0) &&
                    (StringFind(report, "F. Intrabar diagnostic")>=0) && (StringFind(report, "PHASE 15.5 BLOCKED")>=0);
      // matrix CSV: header + 131 rows; pair CSV: header + 120 BE-on runs (75 active + 45 equivalent)
      bool csv_ok = (csv_lines==132) && (pcsv_lines==121);
      AddResult("T180", (rep_ok && csv_ok), StringFormat("report sections present=%s | matrix csv lines=%d (expect 132) pair csv lines=%d (expect 121)",
                rep_ok?"yes":"NO", csv_lines, pcsv_lines));
     }

public:
                     CGZRewardBeTests(CGZLogger *logger=NULL) { m_logger = logger; }

   int               ResultCount() const { return ArraySize(m_results); }
   GZ_TestResult     GetResult(int i) const { return m_results[i]; }

   void              RunAll()
     {
      ArrayResize(m_results, 0);
      T167_DetailCaptureBaseline();
      T168_TpSweepChangesBehavior();
      T169_BeProtectsFromSl();
      T170_BePrematureExit();
      T171_NoChangeCategories();
      T172_PairClassificationEdgeCases();
      T173_BeInactiveEquivalent();
      T174_IntrabarDiagnostics();
      T175_Determinism();
      T176_GridDefinitions();
      T177_UncensoredReachReference();
      T178_EngineGuards();
      T179_T180_EngineFullRunSmoke();
     }
  };

#endif // __GZ_REWARDBE_TESTS_MQH__
