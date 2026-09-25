//+------------------------------------------------------------------+
//| GZ_PartitionTests.mqh                                             |
//| GoldenZone STR - Phase 15.8 - deterministic tests T210-T235       |
//|                                                                    |
//| Synthetic data only. T210-T224 = P158-01..15 (partition), T225-    |
//| T228 = P158-16..19 (net-of-cost layer), T229 = quiet/skip proof,   |
//| T230-T235 = research gate, accepted-hole regression, net metrics   |
//| through the existing metrics engine, spread statistics, progress   |
//| text, warm-up floor.                                                |
//+------------------------------------------------------------------+
#ifndef __GZ_PARTITION_TESTS_MQH__
#define __GZ_PARTITION_TESTS_MQH__

#include "GZ_Partition.mqh"
#include "GZ_HistoricalDataset.mqh"
#include "..\Cost\GZ_CostEngine.mqh"
#include "..\Core\GZ_Progress.mqh"
#include "..\RewardBe\GZ_RewardBeTypes.mqh"
#include "..\RewardBe\GZ_RunDetail.mqh"
#include "..\RewardBe\GZ_RewardBeEngine.mqh"
#include "..\Experiment\GZ_ExperimentTypes.mqh"
#include "..\Experiment\GZ_ExperimentRunner.mqh"
#include "..\Data\GZ_DataValidator.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZPartitionTests
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
   datetime T(int y, int mo, int d, int h=0, int mi=0) const { return GZMakeTime(y,mo,d,h,mi,0); }

   MqlRates MakeBar(datetime t, double o, double h, double l, double c)
     {
      MqlRates r;
      r.time=t; r.open=o; r.high=h; r.low=l; r.close=c;
      r.tick_volume=100; r.spread=1; r.real_volume=0;
      return r;
     }
   MqlRates MakeHL(datetime t, double high, double low)
     { double mid=(high+low)/2.0; return MakeBar(t, mid, high, low, mid); }

   //--- Phase 15.5 single-setup fixture (one TOUCH trade, TP 2R hit) anchored at t0.
   //--- second_offset = seconds after the entry bar for the TP bar (60 = original fixture).
   void AppendScenario(datetime t0, int second_offset, MqlRates &m1[], MqlRates &m5[])
     {
      int o5 = ArraySize(m5), o1 = ArraySize(m1);
      ArrayResize(m5, o5+13);
      m5[o5+0]  = MakeHL(t0+0*300,  105,100);
      m5[o5+1]  = MakeHL(t0+1*300,  103,98);
      m5[o5+2]  = MakeHL(t0+2*300,  102,80);
      m5[o5+3]  = MakeHL(t0+3*300,  104,95);
      m5[o5+4]  = MakeHL(t0+4*300,  106,97);
      m5[o5+5]  = MakeHL(t0+5*300,  108,99);
      m5[o5+6]  = MakeHL(t0+6*300,  140,100);
      m5[o5+7]  = MakeHL(t0+7*300,  115,101);
      m5[o5+8]  = MakeHL(t0+8*300,  112,98);
      m5[o5+9]  = MakeBar(t0+9*300, 112,142,110,141);
      m5[o5+10] = MakeHL(t0+10*300, 139,95);
      m5[o5+11] = MakeHL(t0+11*300, 145,90);
      m5[o5+12] = MakeHL(t0+12*300, 100,95);
      datetime b = m5[o5+10].time + 360;
      ArrayResize(m1, o1+2);
      m1[o1+0] = MakeBar(b,                 104,104.5,102,102.5);
      m1[o1+1] = MakeBar(b+second_offset,   155,160,154,158);
     }

   void RunPipeline(const MqlRates &m1[], const MqlRates &m5[], double tp, double trig, datetime measure_from,
                    GZ_ExperimentResult &res, CGZRunDetail *d, CGZLogger *lg)
     {
      CGZExperimentRunner runner(lg);
      GZ_ExperimentConfig cfg; cfg.Default();
      cfg.time_config.broker_offset_known = true;
      cfg.exit_config.tp_r_multiple = tp;
      cfg.exit_config.be_trigger_r  = trig;
      cfg.measure_from = measure_from;
      runner.RunSingleDetailed(cfg, m1, m5, "DS_P158", GZ_VAL_VALID, GZ_VAL_VALID, res, d);
     }

   bool SameDetail(CGZRunDetail *a, CGZRunDetail *b) const
     {
      if(a.count!=b.count) return false;
      for(int i=0;i<a.count;i++)
        {
         if(a.trade_id[i]!=b.trade_id[i] || a.entry_time[i]!=b.entry_time[i] || a.exit_time[i]!=b.exit_time[i] ||
            a.exit_reason[i]!=b.exit_reason[i] || a.direction[i]!=b.direction[i]) return false;
         if(MathAbs(a.entry_price[i]-b.entry_price[i])>0.000000001 || MathAbs(a.realized_r[i]-b.realized_r[i])>0.000000001 ||
            MathAbs(a.mae_r[i]-b.mae_r[i])>0.000000001 || MathAbs(a.mfe_r[i]-b.mfe_r[i])>0.000000001) return false;
        }
      return true;
     }

   bool SameBars(const MqlRates &a[], const MqlRates &b[]) const
     {
      int n = ArraySize(a);
      if(n!=ArraySize(b)) return false;
      for(int i=0;i<n;i++)
         if(a[i].time!=b[i].time || a[i].open!=b[i].open || a[i].high!=b[i].high || a[i].low!=b[i].low ||
            a[i].close!=b[i].close || a[i].tick_volume!=b[i].tick_volume || a[i].spread!=b[i].spread) return false;
      return true;
     }

   void DefPart(GZ_Partition &p)
     {
      p.Set(T(2020,7,1), T(2026,9,25), T(2020,7,1), T(2025,1,1), T(2025,1,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      GZPartitionValidate(p);
     }

   ENUM_GZ_PART_CLASS Cls(const GZ_Partition &p, datetime s, datetime e) { return GZPartitionClassify(p, s, e); }

   //--- T210-T217 : partition configuration -------------------------------------
   void T210_ValidHistorical()
     {
      GZ_Partition p; DefPart(p);
      bool ok = p.valid && (p.error_code==GZ_PERR_NONE) && (p.dev_start==p.hist_start) && (p.leg_end==p.hist_end) &&
                (p.dev_end==p.oos_start) && (p.oos_end==p.leg_start) && (StringLen(p.warning)==0);
      AddResult("T210", ok, "P158-01 valid historical range: default partition valid, Development+FinalOOS+Legacy exactly tile the Historical range, no warning. valid=" + (p.valid?"true":"false") + " err=" + p.error);
     }

   void T211_NonOverlap()
     {
      GZ_Partition p; DefPart(p);
      bool ok = (p.dev_end <= p.oos_start) && (Cls(p, T(2024,12,31,23,59), T(2025,1,1,0,0))==GZ_PC_DEVELOPMENT) &&
                (Cls(p, T(2025,1,1,0,0), T(2025,1,1,0,1))==GZ_PC_FINAL_OOS) && (Cls(p, T(2024,12,31,23,59), T(2025,1,1,0,1))==GZ_PC_CROSSES_BOUNDARY);
      AddResult("T211", ok, "P158-02 Development and Final OOS do not overlap: the last Development minute and the first OOS minute classify on their own side; a range holding both CROSSES");
     }

   void T212_Contiguous()
     {
      GZ_Partition p; DefPart(p);
      GZ_Partition g; g.Set(T(2020,7,1), T(2026,9,25), T(2020,7,1), T(2025,1,1), T(2025,1,1,0,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      bool gv = GZPartitionValidate(g);
      bool ok = p.valid && (p.dev_end==p.oos_start) && (p.oos_end==p.leg_start) && !gv && (g.error_code==GZ_PERR_GAP);
      AddResult("T212", ok, "P158-03 contiguous boundary: dev_end==oos_start and oos_end==leg_start; a one-minute gap is rejected as GAP. " + g.error);
     }

   void T213_OverlapRejected()
     {
      GZ_Partition a; a.Set(T(2020,7,1), T(2026,9,25), T(2020,7,1), T(2025,1,1), T(2024,12,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      GZ_Partition b; b.Set(T(2020,7,1), T(2026,9,25), T(2020,7,1), T(2025,1,1), T(2025,1,1), T(2026,2,1), T(2026,1,1), T(2026,9,25));
      bool va = GZPartitionValidate(a), vb = GZPartitionValidate(b);
      bool ok = !va && (a.error_code==GZ_PERR_OVERLAP) && !vb && (b.error_code==GZ_PERR_OVERLAP) && (StringFind(a.error,"OVERLAP")>=0);
      AddResult("T213", ok, "P158-04 overlapping partitions rejected (OOS before Development end; Legacy before OOS end). " + a.error);
     }

   void T214_ReversedRejected()
     {
      GZ_Partition a; a.Set(T(2020,7,1), T(2026,9,25), T(2025,1,1), T(2020,7,1), T(2025,1,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      GZ_Partition b; b.Set(T(2020,7,1), T(2026,9,25), T(2020,7,1), T(2025,1,1), T(2025,1,1), T(2025,1,1), T(2025,1,1), T(2026,9,25));
      GZ_Partition c; c.Set(T(2026,9,25), T(2020,7,1), T(2020,7,1), T(2025,1,1), T(2025,1,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      bool ok = !GZPartitionValidate(a) && (a.error_code==GZ_PERR_REVERSED_OR_EMPTY) && !GZPartitionValidate(b) && (b.error_code==GZ_PERR_REVERSED_OR_EMPTY) &&
                !GZPartitionValidate(c) && (c.error_code==GZ_PERR_REVERSED_OR_EMPTY);
      AddResult("T214", ok, "P158-05 reversed/empty range rejected (Development reversed, Final OOS empty, Historical reversed)");
     }

   void T215_OosOutside()
     {
      GZ_Partition a; a.Set(T(2020,7,1), T(2026,9,25), T(2020,7,1), T(2025,1,1), T(2025,1,1), T(2027,1,1), T(2027,1,1), T(2027,6,1));
      GZ_Partition b; b.Set(T(2020,7,1), T(2026,9,25), T(2020,7,1), T(2025,1,1), T(2025,1,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      b.oos_start = T(2019,1,1); b.dev_end = T(2019,1,1);
      bool ok = !GZPartitionValidate(a) && (a.error_code==GZ_PERR_OUTSIDE_HISTORICAL) && !GZPartitionValidate(b) && (b.error_code==GZ_PERR_OUTSIDE_HISTORICAL || b.error_code==GZ_PERR_REVERSED_OR_EMPTY);
      AddResult("T215", ok, "P158-06 a Final OOS partition outside the Historical range is rejected. " + a.error);
     }

   void T216_HistStartByInput()
     {
      GZ_Partition early; early.Set(T(2018,1,1), T(2026,9,25), T(2020,7,1), T(2025,1,1), T(2025,1,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      GZ_Partition late;  late.Set(T(2021,1,1), T(2026,9,25), T(2020,7,1), T(2025,1,1), T(2025,1,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      bool ve = GZPartitionValidate(early), vl = GZPartitionValidate(late);
      bool ok = ve && (StringFind(early.warning,"UNASSIGNED")>=0) && (Cls(early, T(2019,3,1), T(2019,4,1))==GZ_PC_UNASSIGNED) && !vl && (late.error_code==GZ_PERR_OUTSIDE_HISTORICAL);
      AddResult("T216", ok, "P158-07 only the historical START input changed: earlier start accepted (head UNASSIGNED, warned); a later start that cuts into Development rejected clearly. " + late.error);
     }

   void T217_HistEndByInput()
     {
      datetime he_late = GZHistEndExclusive(T(2026,12,31,23,59));
      datetime he_early= GZHistEndExclusive(T(2026,6,30,23,59));
      GZ_Partition later; later.Set(T(2020,7,1), he_late, T(2020,7,1), T(2025,1,1), T(2025,1,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      GZ_Partition earlier; earlier.Set(T(2020,7,1), he_early, T(2020,7,1), T(2025,1,1), T(2025,1,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      bool vl = GZPartitionValidate(later), ve = GZPartitionValidate(earlier);
      bool ok = vl && (StringFind(later.warning,"UNASSIGNED")>=0) && (Cls(later, T(2026,10,1), T(2026,11,1))==GZ_PC_UNASSIGNED) && !ve && (earlier.error_code==GZ_PERR_OUTSIDE_HISTORICAL) &&
                (he_late==T(2027,1,1));
      AddResult("T217", ok, "P158-08 only the historical END input changed: later end accepted (tail UNASSIGNED, warned); an end before the Legacy end rejected. inclusive 2026-12-31 23:59 -> exclusive 2027-01-01");
     }

   //--- T218-T224 -----------------------------------------------------------------
   void T218_WarmupNeverMeasured()
     {
      datetime t0 = T(2026,3,2,9,0);
      MqlRates m1[], m5[];
      AppendScenario(t0, 60, m1, m5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(m1, m5, "SYN", T(2026,3,1,0,0), T(2026,3,3,23,59), GetPointer(val));
      datetime mstart = t0 + 3600;
      int actual = 0;
      datetime ws = ds.WarmupStart(mstart, 12, 0, actual);
      GZ_ResearchRange r; GZRangeCustom(ws, (datetime)((long)t0 + 3899), r);
      MqlRates s1[], s5[];
      ds.Slice(r, s1, s5);

      GZ_ExperimentResult w, c; CGZRunDetail dw, dc;
      RunPipeline(s1, s5, 2.0, 0.0, mstart, w, GetPointer(dw), m_logger);   // entry 09:56 lies BEFORE measure start
      RunPipeline(s1, s5, 2.0, 0.0, t0,     c, GetPointer(dc), m_logger);   // control: everything measured
      bool warm_ok = (ws==t0) && (actual==12) && (dw.count==0) && (w.metrics.trade.trade_count==0) && (w.trade_count==1) && (dc.count==1) && (c.metrics.trade.trade_count==1);

      GZ_ExperimentResult n0, n1; CGZRunDetail d0, d1;
      RunPipeline(s1, s5, 2.0, 0.0, 0,  n0, GetPointer(d0), m_logger);       // warm-up 0 = cold start, no mask
      RunPipeline(s1, s5, 2.0, 0.0, t0, n1, GetPointer(d1), m_logger);       // mask that includes every trade
      bool cold_ok = SameDetail(GetPointer(d0), GetPointer(d1)) && Near(n0.metrics.trade.net_r, n1.metrics.trade.net_r) && (n0.metrics.trade.trade_count==n1.metrics.trade.trade_count);
      AddResult("T218", warm_ok && cold_ok, StringFormat("P158-09 warm-up %d bars (start %s): the warm-up setup's trade (engine trades=%d) is NOT measured (measured=%d); with measure start at the fixture start it IS (measured=%d); warm-up 0 == cold start / all-inclusive mask identical=%s",
                actual, TimeToString(ws), w.trade_count, dw.count, dc.count, cold_ok?"true":"false"));
     }

   void T219_NoFutureOosInDevelopment()
     {
      GZ_Partition p; DefPart(p);
      MqlRates a1[], a5[], b1[], b5[];
      AppendScenario(T(2024,12,2,9,0), 60, a1, a5);
      AppendScenario(T(2025,2,3,9,0), 60, a1, a5);
      AppendScenario(T(2024,12,2,9,0), 60, b1, b5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset da(m_logger), db(m_logger);
      da.Attach(a1, a5, "SYN", T(2024,11,1), T(2025,3,31,23,59), GetPointer(val));
      db.Attach(b1, b5, "SYN", T(2024,11,1), T(2025,3,31,23,59), GetPointer(val));
      GZ_ResearchRange r; GZRangeFromPartitionPart(GZ_RANGE_DEVELOPMENT, "DEVELOPMENT", p.dev_start, p.dev_end, r);
      MqlRates x1[], x5[], y1[], y5[];
      da.Slice(r, x1, x5); db.Slice(r, y1, y5);
      GZ_ExperimentResult ra, rb; CGZRunDetail dA, dB;
      RunPipeline(x1, x5, 2.0, 0.0, 0, ra, GetPointer(dA), m_logger);
      RunPipeline(y1, y5, 2.0, 0.0, 0, rb, GetPointer(dB), m_logger);
      bool ok = SameBars(x1,y1) && SameBars(x5,y5) && SameDetail(GetPointer(dA), GetPointer(dB)) && (ArraySize(x5)>0) &&
                (x5[ArraySize(x5)-1].time < p.oos_start) && (dA.count==1) && Near(ra.metrics.trade.net_r, rb.metrics.trade.net_r);
      AddResult("T219", ok, StringFormat("P158-10 Development slice/result identical with and without OOS bars in the dataset: bars M1 %d/%d M5 %d/%d, trades %d/%d, last Development bar < OOS start", ArraySize(x1), ArraySize(y1), ArraySize(x5), ArraySize(y5), dA.count, dB.count));
     }

   void T220_BoundaryTrades()
     {
      GZ_Partition p; DefPart(p);
      GZ_ResearchRange rd, ro;
      GZRangeFromPartitionPart(GZ_RANGE_DEVELOPMENT, "DEVELOPMENT", p.dev_start, p.dev_end, rd);
      GZRangeFromPartitionPart(GZ_RANGE_NEW_FINAL_OOS, "NEWFINALOOS", p.oos_start, p.oos_end, ro);
      CGZDataValidator val(m_logger);

      //--- Case A: entry inside Development (23:56), TP bar in the OOS partition (00:00)
      MqlRates a1[], a5[];
      AppendScenario(T(2024,12,31,23,0), 240, a1, a5);
      CGZHistoricalDataset dsA(m_logger);
      dsA.Attach(a1, a5, "SYN", T(2024,12,1), T(2025,1,31,23,59), GetPointer(val));
      MqlRates d1[], d5[], f1[], f5[];
      dsA.Slice(rd, d1, d5);
      GZ_ResearchRange rall; GZRangeCustom(T(2024,12,31,23,0), T(2025,1,1,0,4), rall);
      dsA.Slice(rall, f1, f5);
      GZ_ExperimentResult rdv, rfull; CGZRunDetail dd, df;
      RunPipeline(d1, d5, 2.0, 0.0, 0, rdv, GetPointer(dd), m_logger);
      RunPipeline(f1, f5, 2.0, 0.0, 0, rfull, GetPointer(df), m_logger);
      bool a_ok = (dd.count==1) && (dd.exit_reason[0]==(int)GZ_EXIT_DATA_END) && (dd.exit_time[0]<=rd.eff_end) && (dd.entry_time[0]<p.dev_end) &&
                  (df.count==1) && (df.exit_reason[0]==(int)GZ_EXIT_TP_HIT);

      //--- Case B: structure before the OOS start, entry after it (00:26). No setup survives a partition start.
      MqlRates b1[], b5[];
      AppendScenario(T(2024,12,31,23,30), 60, b1, b5);
      CGZHistoricalDataset dsB(m_logger);
      dsB.Attach(b1, b5, "SYN", T(2024,12,1), T(2025,1,31,23,59), GetPointer(val));
      GZ_ResearchRange rbf; GZRangeCustom(T(2024,12,31,23,30), T(2025,1,1,0,34), rbf);
      MqlRates g1[], g5[], o1[], o5[], e1[], e5[];
      dsB.Slice(rbf, g1, g5); dsB.Slice(ro, o1, o5); dsB.Slice(rd, e1, e5);
      GZ_ExperimentResult rg, rob, rdb; CGZRunDetail dg, dob, ddb;
      RunPipeline(g1, g5, 2.0, 0.0, 0, rg, GetPointer(dg), m_logger);
      RunPipeline(o1, o5, 2.0, 0.0, 0, rob, GetPointer(dob), m_logger);
      RunPipeline(e1, e5, 2.0, 0.0, 0, rdb, GetPointer(ddb), m_logger);
      bool b_ok = (dg.count==1) && (dg.entry_time[0]>=p.oos_start) && (ddb.count==0);
      for(int i=0;i<dob.count;i++) if(dob.entry_time[i]==dg.entry_time[0]) b_ok = false;

      //--- Case D: no trade is open at the boundary in either partition run
      bool d_ok = true;
      for(int i=0;i<dd.count;i++) if(dd.exit_time[i] >= p.oos_start) d_ok = false;
      for(int i=0;i<dob.count;i++) if(dob.entry_time[i] < p.oos_start) d_ok = false;
      AddResult("T220", a_ok && b_ok && d_ok, StringFormat("P158-11 boundary trades: A(entry in Dev, exit after) Development run closes it by DATA_END inside Development (%s), full range TP_HIT (%s); B(setup before OOS start, entry after) trades full=%d, Development=%d, none in the cold-start OOS slice at that entry (%s); D(no trade open at the boundary)=%s",
                a_ok?"ok":"BAD", (df.count==1)?"seen":"n/a", dg.count, ddb.count, b_ok?"ok":"BAD", d_ok?"true":"false"));
     }

   void T221_IdenticalTwice()
     {
      GZ_Partition p; DefPart(p);
      MqlRates m1[], m5[];
      AppendScenario(T(2024,12,2,9,0), 60, m1, m5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(m1, m5, "SYN", T(2024,11,1), T(2025,3,31,23,59), GetPointer(val));
      GZ_ResearchRange r; GZRangeFromPartitionPart(GZ_RANGE_DEVELOPMENT, "DEVELOPMENT", p.dev_start, p.dev_end, r);
      MqlRates a1[], a5[], b1[], b5[];
      ds.Slice(r, a1, a5); ds.Slice(r, b1, b5);
      GZ_ExperimentResult x, y; CGZRunDetail dx, dy;
      RunPipeline(a1, a5, 2.0, 0.0, 0, x, GetPointer(dx), m_logger);
      RunPipeline(b1, b5, 2.0, 0.0, 0, y, GetPointer(dy), m_logger);
      bool ok = SameBars(a1,b1) && SameBars(a5,b5) && SameDetail(GetPointer(dx), GetPointer(dy)) && Near(x.metrics.trade.net_r, y.metrics.trade.net_r);
      AddResult("T221", ok, StringFormat("P158-12 identical partition twice -> identical slices and results (trades %d/%d)", dx.count, dy.count));
     }

   void T222_LegacyNotCleanOos()
     {
      GZ_Partition p; DefPart(p);
      GZ_ResearchRange leg, mar, y25;
      GZRangeLegacyDev(T(2026,1,1), T(2026,6,13), leg); GZRangeMonth(2026,3,mar); GZRangeYear(2025,y25);
      GZ_ResearchGate gl, gm, gy;
      GZPartitionGate(p, leg, gl); GZPartitionGate(p, mar, gm); GZPartitionGate(p, y25, gy);
      bool ok = (gl.part_class==GZ_PC_LEGACY_TOUCHED) && (gm.part_class==GZ_PC_LEGACY_TOUCHED) && (gm.part_class!=GZ_PC_FINAL_OOS) && !gm.allowed &&
                (gy.part_class==GZ_PC_FINAL_OOS) && !gy.allowed;
      AddResult("T222", ok, "P158-13 2026 data is LEGACY_TOUCHED, never FINAL_OOS: legacy range=" + gl.label + ", 2026-03=" + gm.label + " (refused), 2025=" + gy.label + " (refused)");
     }

   void T223_CurrentRange()
     {
      datetime he = GZHistEndExclusive(T(2026,9,24,23,59));
      GZ_Partition p; p.Set(T(2020,7,1), he, T(2020,7,1), T(2025,1,1), T(2025,1,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      bool ok = GZPartitionValidate(p) && (he==T(2026,9,25)) && (StringLen(p.warning)==0);
      AddResult("T223", ok, "P158-14 current range 2020-07-01 -> 2026-09-25 (half-open; input end 2026-09-24 23:59 inclusive) accepted with no warning");
     }

   void T224_EarlierStart()
     {
      GZ_Partition a; a.Set(T(2018,1,1), T(2026,9,25), T(2020,7,1), T(2025,1,1), T(2025,1,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      GZ_Partition b; b.Set(T(2018,1,1), T(2026,9,25), T(2018,1,1), T(2025,1,1), T(2025,1,1), T(2026,1,1), T(2026,1,1), T(2026,9,25));
      bool ok = GZPartitionValidate(a) && GZPartitionValidate(b) && (Cls(b, T(2018,6,1), T(2018,7,1))==GZ_PC_DEVELOPMENT) && (Cls(a, T(2018,6,1), T(2018,7,1))==GZ_PC_UNASSIGNED) && (StringLen(b.warning)==0);
      AddResult("T224", ok, "P158-15 an earlier start (2018-01-01) is NOT rejected by the partition layer: alone -> UNASSIGNED head (warning); with the Development start moved too -> DEVELOPMENT, no code change");
     }

   //--- net-of-cost helpers -------------------------------------------------------
   void MakeCost(GZ_CostConfig &cc, bool configured, ENUM_GZ_COST_SPREAD_MODE sm, double fixed_sp, double pct, double slip)
     {
      cc.Default();
      cc.configured = configured; cc.spread_mode = sm; cc.fixed_spread_pts = fixed_sp;
      cc.commission_mode = GZ_COST_COMM_PERCENT; cc.commission_percent = pct; cc.slippage_pts = slip;
      cc.contract_size = 100.0; cc.point = 0.01;
     }

   void ConfigureEngine(CGZCostEngine &ce, const GZ_CostConfig &cc)
     {
      GZ_TimeConfig tc; tc.Default(); tc.broker_offset_known = true;
      GZ_SessionProfile sp; sp.Set("PROFILE_01", "Session", GZ_TIME_BROKER, 16, 30, 20, 30, true, true);
      ce.Configure(cc, tc, sp);
     }

   void T225_ZeroCostsEqualGross()
     {
      MqlRates c1[], c5[];
      AppendScenario(T(2026,3,2,9,0), 60, c1, c5);
      AppendScenario(T(2026,5,4,9,0), 60, c1, c5);
      GZ_ExperimentConfig cfg; cfg.Default(); cfg.time_config.broker_offset_known = true;
      GZ_RewardBeBaselineRef bref; bref.Clear();
      CGZCostEngine ce; GZ_CostConfig cc; MakeCost(cc, true, GZ_COST_SPREAD_FIXED, 0.0, 0.0, 0.0); ConfigureEngine(ce, cc);
      CGZRewardBeEngine eng(m_logger);
      eng.SetCostEngine(GetPointer(ce));
      datetime first = c5[0].time, last = c5[ArraySize(c5)-1].time;
      eng.Run(cfg, c1, c5, "DS_COST0", GZ_VAL_VALID, GZ_VAL_VALID, (datetime)(first-86400), (datetime)(last+86400), (datetime)(last+2*86400), true, bref);
      int avail = 0; bool ok = (eng.RowCount()>0);
      for(int i=0;i<eng.RowCount();i++)
        {
         GZ_RewardBeRow r = eng.GetRow(i);
         if(r.trades<=0) continue;
         if(!r.net.available) { ok = false; continue; }
         avail++;
         if(!Near(r.net.net_r, r.net_r) || !Near(r.net.expectancy, r.expectancy) || !Near(r.net.max_dd_r, r.max_dd_r) ||
            !Near(r.net.win_rate, r.win_rate) || !r.net.net_equals_gross || !Near(r.net.avg_cost_r, 0.0)) ok = false;
         if(!r.net.pf_undefined && !Near(r.net.profit_factor, r.profit_factor)) ok = false;
        }
      AddResult("T225", ok && avail>0, StringFormat("P158-16 costs zero -> net equals gross exactly for every matrix row with trades (%d rows checked of %d)", avail, eng.RowCount()));
     }

   void T226_KnownTradeExact()
     {
      datetime t = T(2026,3,2,9,56);
      MqlRates m1[]; ArrayResize(m1, 1); m1[0] = MakeBar(t, 4000, 4001, 3999, 4000); m1[0].spread = 25;
      CGZRunDetail d; d.AddTrade(1, t, 4000.0, (int)GZ_LEG_BULLISH, t+60, (int)GZ_EXIT_TP_HIT, 2.0, 22.0, false, false, false, false, 0.5, 2.0);
      GZ_CostConfig cc; MakeCost(cc, true, GZ_COST_SPREAD_RECORDED, 0.0, 0.0016, 10.0);
      CGZCostEngine ce; ConfigureEngine(ce, cc);
      GZ_NetSummary q; ce.Evaluate(GetPointer(d), m1, q);
      double exp1 = 2.0 - (25*0.01 + 2*10*0.01 + 4000.0*0.0016/100.0)/22.0;      // 1.97663636...
      GZ_CostConfig c2 = cc; c2.commission_mode = GZ_COST_COMM_FIXED; c2.commission_percent = 0.0; c2.commission_per_lot = 7.0;
      CGZCostEngine ce2; ConfigureEngine(ce2, c2);
      GZ_NetSummary q2; ce2.Evaluate(GetPointer(d), m1, q2);
      double exp2 = 2.0 - (25*0.01 + 2*10*0.01 + 7.0/100.0)/22.0;                // 1.97636363...
      bool ok = Near(q.net_r, exp1) && Near(exp1, 1.9766363636) && Near(q2.net_r, exp2) && Near(exp2, 1.9763636364) && !q.net_equals_gross &&
                Near(q.avg_cost_r, 0.514/22.0) && Near(q.sens[0].net_r, 2.0 - 0.314/22.0) && Near(q.sens[2].net_r, 2.0 - (0.25+1.0+0.064)/22.0);
      AddResult("T226", ok, StringFormat("P158-17 known trade (risk 22, spread 25 pts, slippage 10 pts/side, commission 0.0016%% of 4000): net R %.10f (hand 1.9766363636); FIXED $7/lot/100oz: %.10f (hand 1.9763636364); slippage sensitivity 0/50 pts: %.6f / %.6f", q.net_r, q2.net_r, q.sens[0].net_r, q.sens[2].net_r));
     }

   void T227_SpreadFromEntryBar()
     {
      datetime t = T(2026,3,2,9,56);
      MqlRates m1[]; ArrayResize(m1, 3);
      m1[0] = MakeBar(t-60, 100,101,99,100); m1[0].spread = 5;
      m1[1] = MakeBar(t,    100,101,99,100); m1[1].spread = 30;
      m1[2] = MakeBar(t+60, 100,101,99,100); m1[2].spread = 80;
      GZ_CostConfig cc; MakeCost(cc, true, GZ_COST_SPREAD_RECORDED, 0.0, 0.0, 0.0);
      CGZCostEngine ce; ConfigureEngine(ce, cc);
      CGZRunDetail d1, d2, d3;
      d1.AddTrade(1, t,     100.0, (int)GZ_LEG_BULLISH, t+120, (int)GZ_EXIT_TP_HIT, 1.0, 10.0, false,false,false,false, 0,1);
      d2.AddTrade(2, t+30,  100.0, (int)GZ_LEG_BULLISH, t+120, (int)GZ_EXIT_TP_HIT, 1.0, 10.0, false,false,false,false, 0,1);
      d3.AddTrade(3, t-3600,100.0, (int)GZ_LEG_BULLISH, t+120, (int)GZ_EXIT_TP_HIT, 1.0, 10.0, false,false,false,false, 0,1);
      GZ_NetSummary q1, q2, q3;
      ce.Evaluate(GetPointer(d1), m1, q1); ce.Evaluate(GetPointer(d2), m1, q2); ce.Evaluate(GetPointer(d3), m1, q3);
      bool ok = Near(q1.avg_spread_pts, 30.0) && Near(q1.avg_cost_r, 0.03) && Near(q2.avg_spread_pts, 30.0) && (q3.spread_missing==1) && Near(q3.avg_cost_r, 0.0);
      AddResult("T227", ok, StringFormat("P158-18 RECORDED spread comes from the ENTRY bar (neighbours 5 and 80 ignored): charged %.1f pts (expect 30), cost %.4fR (expect 0.03); entry between bars uses the bar at/before it (%.1f); no M1 bar -> flagged missing (%d)", q1.avg_spread_pts, q1.avg_cost_r, q2.avg_spread_pts, q3.spread_missing));
     }

   void T228_UnsetFlagged()
     {
      datetime t = T(2026,3,2,9,56);
      MqlRates m1[]; ArrayResize(m1, 1); m1[0] = MakeBar(t, 100,101,99,100); m1[0].spread = 40;
      CGZRunDetail d; d.AddTrade(1, t, 100.0, (int)GZ_LEG_BULLISH, t+60, (int)GZ_EXIT_TP_HIT, 2.0, 10.0, false,false,false,false, 0,2);
      GZ_CostConfig c1, c2, c3;
      MakeCost(c1, false, GZ_COST_SPREAD_RECORDED, 0.0, 0.0016, 20.0);
      MakeCost(c2, true,  GZ_COST_SPREAD_FIXED, 0.0, 0.0, 0.0);
      MakeCost(c3, true,  GZ_COST_SPREAD_RECORDED, 0.0, 0.0, 0.0);
      CGZCostEngine e1, e2, e3; ConfigureEngine(e1, c1); ConfigureEngine(e2, c2); ConfigureEngine(e3, c3);
      GZ_NetSummary q1, q2, q3;
      e1.Evaluate(GetPointer(d), m1, q1); e2.Evaluate(GetPointer(d), m1, q2); e3.Evaluate(GetPointer(d), m1, q3);
      bool ok = q1.net_equals_gross && Near(q1.net_r, 2.0) && q2.net_equals_gross && Near(q2.net_r, 2.0) && !q3.net_equals_gross && (q3.net_r < 2.0);
      AddResult("T228", ok, "P158-19 unset costs (configured=false) and all-zero costs are flagged NET = GROSS with net == gross; RECORDED spread with configured=true is NOT flagged and charges a cost");
     }

   void T229_QuietAndSkipIdentical()
     {
      MqlRates c1[], c5[];
      AppendScenario(T(2026,3,2,9,0), 60, c1, c5);
      AppendScenario(T(2026,5,4,9,0), 60, c1, c5);
      CGZLogger loud, quiet; quiet.SetMinLevel(GZ_SEV_WARNING);
      GZ_ExperimentResult ra, rb; CGZRunDetail da, db;
      RunPipeline(c1, c5, 2.0, 0.0, 0, ra, GetPointer(da), GetPointer(loud));
      RunPipeline(c1, c5, 2.0, 0.0, 0, rb, GetPointer(db), GetPointer(quiet));
      bool quiet_ok = SameDetail(GetPointer(da), GetPointer(db)) && Near(ra.metrics.trade.net_r, rb.metrics.trade.net_r) && (ra.trade_count==rb.trade_count);

      GZ_ExperimentConfig cfg; cfg.Default(); cfg.time_config.broker_offset_known = true;
      datetime first = c5[0].time, last = c5[ArraySize(c5)-1].time;
      GZ_RewardBeBaselineRef skip; skip.Clear(); skip.main_skipped = true;
      GZ_RewardBeBaselineRef keep; keep.Clear();
      CGZRewardBeEngine e1(m_logger), e2(m_logger);
      e1.Run(cfg, c1, c5, "DS_SKIP", GZ_VAL_VALID, GZ_VAL_VALID, (datetime)(first-86400), (datetime)(last+86400), (datetime)(last+2*86400), true, skip);
      e2.Run(cfg, c1, c5, "DS_KEEP", GZ_VAL_VALID, GZ_VAL_VALID, (datetime)(first-86400), (datetime)(last+86400), (datetime)(last+2*86400), true, keep);
      bool row_ok = false, rows_same = (e1.RowCount()==e2.RowCount());
      for(int i=0;i<e1.RowCount();i++)
        {
         GZ_RewardBeRow r = e1.GetRow(i);
         if(r.kind==GZ_RB_OFF && Near(r.tp_r, 2.0)) row_ok = (r.trades==da.count) && Near(r.net_r, ra.metrics.trade.net_r);
         GZ_RewardBeRow s = e2.GetRow(i);
         if(r.trades!=s.trades || !Near(r.net_r, s.net_r)) rows_same = false;
        }
      bool v02_skip = false, v02_keep = false;
      for(int i=0;i<e1.ValidationCount();i++) if(StringFind(e1.GetValidation(i).id, "V02")==0) v02_skip = true;
      for(int i=0;i<e2.ValidationCount();i++) if(StringFind(e2.GetValidation(i).id, "V02")==0) v02_keep = true;
      AddResult("T229", quiet_ok && row_ok && rows_same && !v02_skip && v02_keep, StringFormat("quiet logger vs INFO logger: identical gross results=%s; TP2R/BE-off matrix row equals the main run (trades %d, net R %.3f)=%s; skip flag on/off -> identical matrix rows=%s; V02 not recorded when skipped=%s, recorded otherwise=%s (the real 412-trade check is R07)",
                quiet_ok?"true":"false", da.count, ra.metrics.trade.net_r, row_ok?"true":"false", rows_same?"true":"false", !v02_skip?"true":"false", v02_keep?"true":"false"));
     }

   void T230_ResearchGate()
     {
      GZ_Partition p; DefPart(p);
      GZ_ResearchRange y22, y25, y26, m2612, m2603, leg, cus, fds, kdev, koos, kleg;
      GZRangeYear(2022, y22); GZRangeYear(2025, y25); GZRangeYear(2026, y26); GZRangeMonth(2024,12,m2612); GZRangeMonth(2026,3,m2603);
      GZRangeLegacyDev(T(2026,1,1), T(2026,6,13), leg); GZRangeCustom(T(2024,12,30), T(2025,1,2,23,59), cus); GZRangeFullDataset(T(2020,7,1), T(2026,9,24,23,59), fds);
      GZRangeFromPartitionPart(GZ_RANGE_DEVELOPMENT, "DEVELOPMENT", p.dev_start, p.dev_end, kdev);
      GZRangeFromPartitionPart(GZ_RANGE_NEW_FINAL_OOS, "NEWFINALOOS", p.oos_start, p.oos_end, koos);
      GZRangeFromPartitionPart(GZ_RANGE_LEGACY_TOUCHED, "LEGACYTOUCHED", p.leg_start, p.leg_end, kleg);
      GZ_ResearchGate g1, g2, g3, g4, g5, g6, g7, g8, g9, g10, g11;
      GZPartitionGate(p, y22, g1); GZPartitionGate(p, y25, g2); GZPartitionGate(p, y26, g3); GZPartitionGate(p, m2612, g4); GZPartitionGate(p, m2603, g5);
      GZPartitionGate(p, leg, g6); GZPartitionGate(p, cus, g7); GZPartitionGate(p, fds, g8); GZPartitionGate(p, kdev, g9); GZPartitionGate(p, koos, g10); GZPartitionGate(p, kleg, g11);
      GZ_Partition bad; bad.Clear(); GZ_ResearchGate gb; GZPartitionGate(bad, y22, gb);
      bool ok = g1.allowed && (g1.label=="DEVELOPMENT") && !g2.allowed && (g2.part_class==GZ_PC_FINAL_OOS) && !g3.allowed && (g3.part_class==GZ_PC_OUTSIDE_HISTORICAL) &&
                g4.allowed && !g5.allowed && g6.allowed && (g6.label=="REGRESSION_ONLY_LEGACY") && !g7.allowed && (g7.part_class==GZ_PC_CROSSES_BOUNDARY) && !g8.allowed &&
                g9.allowed && !g10.allowed && !g11.allowed && !gb.allowed && (gb.label=="PARTITION_INVALID") &&
                (kdev.eff_start==T(2020,7,1)) && (kdev.eff_end==T(2024,12,31,23,59)) && (koos.eff_start==T(2025,1,1)) && (koos.eff_end==T(2025,12,31,23,59)) &&
                (kleg.eff_start==T(2026,1,1)) && (kleg.eff_end==T(2026,9,24,23,59));
      AddResult("T230", ok, "research gate: Development ranges allowed; FINAL_OOS, LEGACY_TOUCHED (non-LEGACY_DEV), boundary-crossing, full-dataset and invalid-partition ranges refused with a reason; LEGACY_DEV over 2026 allowed ONLY as REGRESSION_ONLY_LEGACY; partition range builders give the exact inclusive ends");
     }

   void T231_AcceptedHoleRegression()
     {
      MqlRates m1[], m5[];
      datetime none = 0;
      // 2022-08-22 .. 2022-09-17, weekdays only, with the real accepted hole and a SECOND >= 4 day hole
      MqlRates a1[], a5[];
      BuildDenseLocal(T(2022,8,22), T(2022,9,17), 60, T(2022,9,1,0,0), T(2022,9,5,1,0), T(2022,9,12,0,0), T(2022,9,16,12,0), a1);
      BuildDenseLocal(T(2022,8,22), T(2022,9,17), 300, T(2022,9,1,0,0), T(2022,9,5,1,0), T(2022,9,12,0,0), T(2022,9,16,12,0), a5);
      MqlRates b1[], b5[];
      BuildDenseLocal(T(2022,8,22), T(2022,9,17), 60, T(2022,9,1,0,0), T(2022,9,5,1,0), none, none, b1);
      BuildDenseLocal(T(2022,8,22), T(2022,9,17), 300, T(2022,9,1,0,0), T(2022,9,5,1,0), none, none, b5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset d2(m_logger), d1(m_logger);
      d2.Attach(a1, a5, "SYN", T(2022,8,22), T(2022,9,16,23,59), GetPointer(val));
      d1.Attach(b1, b5, "SYN", T(2022,8,22), T(2022,9,16,23,59), GetPointer(val));
      int u2 = d2.Coverage().MissingRangesNotAccepted(GZ_P157_ACCEPTED_HOLE_FROM, GZ_P157_ACCEPTED_HOLE_TO);
      int u1 = d1.Coverage().MissingRangesNotAccepted(GZ_P157_ACCEPTED_HOLE_FROM, GZ_P157_ACCEPTED_HOLE_TO);
      int t2 = d2.Coverage().MissingRangeTotal(), t1 = d1.Coverage().MissingRangeTotal();
      bool ok = (t1==1) && (u1==0) && (t2==2) && (u2==1) && (StringLen(GZAcceptedHoleNote(T(2022,8,1), T(2022,10,1)))>0) && (StringLen(GZAcceptedHoleNote(T(2021,1,1), T(2021,2,1)))==0);
      AddResult("T231", ok, StringFormat("existing accepted-hole exception (2022-08-31 23:59 -> 2022-09-05 01:00): only that hole present -> missing=%d unexplained=%d (0 required); plus a second >= 4 day hole -> missing=%d unexplained=%d (1: it still fails R02); hole note printed only for ranges containing it", t1, u1, t2, u2));
     }

   //--- weekdays-only dense bars in [from,to_excl) with up to two holes [h1a,h1b) and [h2a,h2b) (0 = none)
   void BuildDenseLocal(datetime from, datetime to_excl, int step, datetime h1a, datetime h1b, datetime h2a, datetime h2b, MqlRates &a[])
     {
      int cnt = 0;
      for(int pass=0; pass<2; pass++)
        {
         int k = 0;
         for(long t=(long)from; t<(long)to_excl; t+=step)
           {
            long dow = ((t / GZ_SECONDS_PER_DAY) + 4) % 7;
            if(dow<1 || dow>5) continue;
            if(h1a>0 && t>=(long)h1a && t<(long)h1b) continue;
            if(h2a>0 && t>=(long)h2a && t<(long)h2b) continue;
            if(pass==1) { a[k] = MakeBar((datetime)t, 1000.0, 1001.0, 999.0, 1000.0 + (k%5)); }
            k++;
           }
         if(pass==0) { cnt = k; ArrayResize(a, cnt); }
        }
     }

   void T232_NetMetricsExistingEngine()
     {
      double gross[5] = {1.0, -1.0, 2.0, -1.0, -1.0};
      CGZRunDetail d;
      for(int i=0;i<5;i++)
         d.AddTrade(i+1, T(2026,3,2,9,0)+i*3600, 1000.0, (int)GZ_LEG_BULLISH, T(2026,3,2,9,30)+i*3600, (int)GZ_EXIT_TP_HIT, gross[i], 10.0, false,false,false,false, 0.5, 1.0);
      GZ_CostConfig cc; MakeCost(cc, true, GZ_COST_SPREAD_FIXED, 100.0, 0.0, 0.0);   // 100 pts x 0.01 = 1.0 price -> 0.1R at risk 10
      CGZCostEngine ce; ConfigureEngine(ce, cc);
      MqlRates m1[]; ArrayResize(m1, 0);
      GZ_NetSummary q; ce.Evaluate(GetPointer(d), m1, q);
      bool ok = (q.trades==5) && Near(q.net_r, -0.5) && Near(q.expectancy, -0.1) && Near(q.win_rate, 0.4) && Near(q.profit_factor, 2.8/3.3) && Near(q.max_dd_r, 2.2) &&
                (q.max_lose_streak==2) && Near(q.gross_net_r, 0.0) && Near(q.avg_cost_r, 0.1);
      AddResult("T232", ok, StringFormat("net metrics through the EXISTING metrics engine: gross [+1,-1,+2,-1,-1] minus 0.1R each -> net R %.3f (hand -0.5), expectancy %.3f (-0.1), win rate %.2f (0.40), PF %.4f (0.8485), max DD %.3f (2.2; gross would be 2.0), max losing streak %d (2)", q.net_r, q.expectancy, q.win_rate, q.profit_factor, q.max_dd_r, q.max_lose_streak));
     }

   void T233_SpreadStats()
     {
      double sp[6]  = {10, 20, 30, 0, 40, 50};
      int    yr[6]  = {2021, 2021, 2021, 2021, 2022, 2022};
      MqlRates m1[]; ArrayResize(m1, 6);
      CGZRunDetail d;
      for(int i=0;i<6;i++)
        {
         datetime t = T(yr[i], 3, 1+i, 10, 0);
         m1[i] = MakeBar(t, 100,101,99,100); m1[i].spread = (int)sp[i];
         d.AddTrade(i+1, t, 100.0, (int)GZ_LEG_BULLISH, t+60, (int)GZ_EXIT_TP_HIT, 1.0, 10.0, false,false,false,false, 0, 1);
        }
      // bars must be ascending: 2021 dates 1..4 Mar then 2022 dates 5..6 Mar -> ascending overall
      GZ_CostConfig cc; MakeCost(cc, true, GZ_COST_SPREAD_RECORDED, 0.0, 0.0, 0.0);
      CGZCostEngine ce; ConfigureEngine(ce, cc);
      GZ_SpreadStatsTotals tot;
      string txt = ce.BuildSpreadStats(GetPointer(d), m1, tot);
      // mostly-zero population -> implausible flag
      MqlRates z1[]; ArrayResize(z1, 3);
      CGZRunDetail dz;
      for(int i=0;i<3;i++)
        {
         datetime t2 = T(2026,3,2+i,10,0);
         z1[i] = MakeBar(t2, 100,101,99,100); z1[i].spread = 0;
         dz.AddTrade(i+1, t2, 100.0, (int)GZ_LEG_BULLISH, t2+60, (int)GZ_EXIT_TP_HIT, 1.0, 10.0, false,false,false,false, 0, 1);
        }
      GZ_SpreadStatsTotals tz;
      ce.BuildSpreadStats(GetPointer(dz), z1, tz);
      bool ok = (tot.n==6) && Near(tot.avg, 25.0) && Near(tot.median, 25.0) && Near(tot.p95, 50.0) && Near(tot.zero_share, 1.0/6.0) && !tot.implausible &&
                (StringFind(txt,"2021")>=0) && (StringFind(txt,"2022")>=0) && (StringFind(txt,"ALL")>=0) && tz.implausible && Near(tz.zero_share, 1.0);
      AddResult("T233", ok, StringFormat("recorded entry-bar spread statistics: n=%d avg %.1f median %.1f p95 %.1f zero share %.3f (hand 6 / 25 / 25 / 50 / 0.167), per-year rows present; an all-zero population is flagged implausible=%s", tot.n, tot.avg, tot.median, tot.p95, tot.zero_share, tz.implausible?"true":"false"));
     }

   void T234_ProgressText()
     {
      string l1 = GZProgressLine(1, 29, 0, "TP=0.50R BE=OFF");
      string l3 = GZProgressLine(3, 29, 120000, "TP=1.00R BE=OFF");
      bool ok = (GZFormatDurationMs(3723000)=="1h 02m 03s") && (GZFormatDurationMs(245000)=="4m 05s") && (GZFormatDurationMs(12000)=="12s") &&
                (GZEstimateRemainingMs(2, 29, 120000)==1620000) && (GZEstimateRemainingMs(0, 29, 5000)==0) && Near(GZProgressPercent(29,29), 100.0) &&
                (StringFind(l1,"run 1/29")>=0) && (StringFind(l1,"n/a")>=0) && (StringFind(l3,"run 3/29")>=0) && (StringFind(l3,"6.9% completed")>=0) && (StringFind(l3,"27m 00s")>=0);
      AddResult("T234", ok, "progress/ETA text: durations formatted, remaining time = mean completed-run time x runs left (2 done in 2 min of 29 -> 27m 00s), run 1 prints n/a. " + l3);
     }

   void T235_WarmupFloor()
     {
      GZ_Partition p; DefPart(p);
      MqlRates s[];
      int n = 3*288;   // 3 days of M5 bars from 2024-12-30 00:00
      ArrayResize(s, n);
      for(int i=0;i<n;i++) s[i] = MakeBar((datetime)((long)T(2024,12,30) + (long)i*300), 1000, 1001, 999, 1000);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(s, s, "SYN", T(2024,12,30), T(2025,1,1,23,59), GetPointer(val));
      datetime floor_oos = GZPartitionPartStart(p, GZ_PC_FINAL_OOS);
      datetime floor_leg = GZPartitionPartStart(p, GZ_PC_LEGACY_TOUCHED);
      int a1 = -1, a2 = -1, a3 = -1, a4 = -1;
      datetime w1 = ds.WarmupStart(T(2025,1,1,0,0), 500, floor_oos, a1);   // right at the floor: nothing before it may be read
      datetime w2 = ds.WarmupStart(T(2025,1,1,1,0), 500, floor_oos, a2);   // 12 bars available inside the partition
      datetime w3 = ds.WarmupStart(T(2025,1,1,1,0), 500, 0, a3);           // no floor: 500 real M5 bars
      datetime w4 = ds.WarmupStart(T(2025,1,1,1,0), 0, floor_oos, a4);     // 0 = cold start
      bool ok = (w1==T(2025,1,1,0,0)) && (a1==0) && (w2==T(2025,1,1,0,0)) && (a2==12) && (a3==500) && (w3<T(2025,1,1,0,0)) && (w4==T(2025,1,1,1,0)) && (a4==0) &&
                (floor_leg==T(2026,1,1)) && (GZPartitionPartStart(p, GZ_PC_DEVELOPMENT)==p.dev_start);
      AddResult("T235", ok, StringFormat("warm-up never reads outside the partition of the measured range: at the floor %d bars, 1h after it %d bars (clamped), unfloored %d bars, warm-up 0 -> cold start (%d)", a1, a2, a3, a4));
     }

public:
                     CGZPartitionTests(CGZLogger *logger=NULL) { m_logger = logger; }

   int               ResultCount() const { return ArraySize(m_results); }
   GZ_TestResult     GetResult(int i) const { return m_results[i]; }

   void              RunAll()
     {
      ArrayResize(m_results, 0);
      T210_ValidHistorical(); T211_NonOverlap(); T212_Contiguous(); T213_OverlapRejected(); T214_ReversedRejected();
      T215_OosOutside(); T216_HistStartByInput(); T217_HistEndByInput(); T218_WarmupNeverMeasured(); T219_NoFutureOosInDevelopment();
      T220_BoundaryTrades(); T221_IdenticalTwice(); T222_LegacyNotCleanOos(); T223_CurrentRange(); T224_EarlierStart();
      T225_ZeroCostsEqualGross(); T226_KnownTradeExact(); T227_SpreadFromEntryBar(); T228_UnsetFlagged(); T229_QuietAndSkipIdentical();
      T230_ResearchGate(); T231_AcceptedHoleRegression(); T232_NetMetricsExistingEngine(); T233_SpreadStats(); T234_ProgressText(); T235_WarmupFloor();
     }
  };

#endif // __GZ_PARTITION_TESTS_MQH__
