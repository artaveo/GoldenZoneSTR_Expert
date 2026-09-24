//+------------------------------------------------------------------+
//| GZ_DatasetTests.mqh                                               |
//| GoldenZone STR - Phase 15.7 - deterministic tests T188-T209       |
//|                                                                    |
//| Synthetic data only (never real market data, never OOS data).     |
//| T188-T202 are the fifteen required date-slicing tests (the         |
//| prompt's T01-T15); T203-T208 cover the range builders, the         |
//| Development/OOS partition, coverage classification and M5          |
//| alignment.                                                         |
//|                                                                    |
//| Pipeline tests reuse the Phase 15.5 single-setup fixture (kind 0 - |
//| one TOUCH trade, TP 2R hit) TWICE, nine weeks apart, so a          |
//| combined dataset holds two independent, individually known         |
//| populations. Assertions are invariants (entry inside range, equal  |
//| results, identical schema), never guessed counts on the combined   |
//| run.                                                               |
//+------------------------------------------------------------------+
#ifndef __GZ_DATASET_TESTS_MQH__
#define __GZ_DATASET_TESTS_MQH__

#include "GZ_ResearchRange.mqh"
#include "GZ_HistoricalDataset.mqh"
#include "..\RewardBe\GZ_RewardBeTypes.mqh"
#include "..\RewardBe\GZ_RunDetail.mqh"
#include "..\RewardBe\GZ_RewardBeEngine.mqh"
#include "..\Experiment\GZ_ExperimentTypes.mqh"
#include "..\Experiment\GZ_ExperimentRunner.mqh"
#include "..\Data\GZ_DataValidator.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZDatasetTests
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
     {
      double mid = (high+low)/2.0;
      return MakeBar(t, mid, high, low, mid);
     }

   //--- n bars, `step` seconds apart, ascending, valid OHLC
   void BuildStep(datetime from, int n, int step, MqlRates &a[])
     {
      ArrayResize(a, n);
      for(int i=0;i<n;i++)
         a[i] = MakeBar((datetime)((long)from + (long)i*step), 1000.0, 1001.0, 999.0, 1000.0 + (i%7));
     }

   bool IsWeekday(datetime t) const
     {
      long dn = (long)t / GZ_SECONDS_PER_DAY;
      long dow = (dn + 4) % 7;   // 0=Sunday
      return (dow>=1 && dow<=5);
     }

   //--- bars every `step` seconds in [from, to_excl); optionally Mon-Fri only; optional hole [hole_from, hole_to)
   void BuildDense(datetime from, datetime to_excl, int step, bool weekdays_only, datetime hole_from, datetime hole_to, MqlRates &a[])
     {
      int cnt = 0;
      for(long t=(long)from; t<(long)to_excl; t+=step)
        {
         if(weekdays_only && !IsWeekday((datetime)t)) continue;
         if(t>=(long)hole_from && t<(long)hole_to) continue;
         cnt++;
        }
      ArrayResize(a, cnt);
      int k = 0;
      for(long t=(long)from; t<(long)to_excl; t+=step)
        {
         if(weekdays_only && !IsWeekday((datetime)t)) continue;
         if(t>=(long)hole_from && t<(long)hole_to) continue;
         a[k] = MakeBar((datetime)t, 1000.0, 1001.0, 999.0, 1000.0 + (k%5));
         k++;
        }
     }

   int NaiveCount(const MqlRates &a[], datetime s, datetime e) const
     {
      int c = 0, n = ArraySize(a);
      for(int i=0;i<n;i++) if(a[i].time>=s && a[i].time<=e) c++;
      return c;
     }

   //--- slice + compare against the naive linear count; also checks bounds and order
   bool CheckSlice(const MqlRates &a[], const GZ_ResearchRange &r, int expected_count, string &why)
     {
      MqlRates out[];
      int cnt = GZSliceRates(a, r.eff_start, r.eff_end, out);
      int naive = NaiveCount(a, r.eff_start, r.eff_end);
      bool ok = (r.status==GZ_RSTATUS_OK) && (cnt==naive) && (cnt==expected_count);
      if(cnt>0)
        {
         ok = ok && (out[0].time>=r.eff_start) && (out[cnt-1].time<=r.eff_end);
         for(int i=1;i<cnt;i++) if(out[i].time<=out[i-1].time) { ok = false; break; }
        }
      why = StringFormat("range=%s [%s .. %s] slice=%d naive=%d expected=%d", r.label,
                         TimeToString(r.eff_start, TIME_DATE|TIME_MINUTES), TimeToString(r.eff_end, TIME_DATE|TIME_MINUTES), cnt, naive, expected_count);
      return ok;
     }

   //--- Phase 15.5 single-setup fixture (kind 0), anchored at t0 (t0 + 9 weeks keeps weekday and time of day)
   void AppendScenario(datetime t0, MqlRates &m1[], MqlRates &m5[])
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
      m1[o1+0] = MakeBar(b,    104,104.5,102,102.5);
      m1[o1+1] = MakeBar(b+60, 155,160,154,158);
     }

   void BuildScenarioA(MqlRates &m1[], MqlRates &m5[])
     { ArrayResize(m1,0); ArrayResize(m5,0); AppendScenario(T(2026,3,2,9,0), m1, m5); }

   void BuildCombined(MqlRates &m1[], MqlRates &m5[])
     {
      ArrayResize(m1,0); ArrayResize(m5,0);
      AppendScenario(T(2026,3,2,9,0), m1, m5);
      AppendScenario(T(2026,5,4,9,0), m1, m5);
     }

   void RunPipeline(const MqlRates &m1[], const MqlRates &m5[], double tp, double trig, GZ_ExperimentResult &res, CGZRunDetail *d)
     {
      CGZExperimentRunner runner(m_logger);
      GZ_ExperimentConfig cfg; cfg.Default();
      cfg.time_config.broker_offset_known = true;
      cfg.exit_config.tp_r_multiple = tp;
      cfg.exit_config.be_trigger_r  = trig;
      runner.RunSingleDetailed(cfg, m1, m5, "DS_P157", GZ_VAL_VALID, GZ_VAL_VALID, res, d);
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

   //--- "--- X." section header lines of a report, joined by '|'
   string SectionHeaders(string report) const
     {
      string lines[];
      int n = StringSplit(report, '\n', lines);
      string h = "";
      for(int i=0;i<n;i++)
         if(StringFind(lines[i], "--- ")==0) h += lines[i] + "|";
      return h;
     }

   string FirstLine(string csv) const
     {
      int p = StringFind(csv, "\n");
      if(p<0) return csv;
      return StringSubstr(csv, 0, p);
     }

   int LineCount(string csv) const
     {
      string lines[];
      return StringSplit(csv, '\n', lines);
     }

   //--- reduced grid, as text: "tp:trig,trig;"
   string GridText()
     {
      double tps[], trigs[];
      GZRewardBeTpGrid(tps);
      string s = "";
      for(int t=0;t<ArraySize(tps);t++)
        {
         s += DoubleToString(tps[t],1) + ":";
         int n = GZRewardBeTriggersForTp(tps[t], trigs);
         for(int g=0; g<n; g++) s += DoubleToString(trigs[g],2) + (g+1<n ? "," : "");
         s += ";";
        }
      return s;
     }

   //--- T188-T195 : slicing ---------------------------------------------------
   MqlRates          m_series[];   // hourly, 2019-12-23 00:00 .. 2021-01-10 23:00 (9240 bars)

   void T188_FullRange()
     {
      GZ_ResearchRange r;
      datetime last = m_series[ArraySize(m_series)-1].time;
      GZRangeFullDataset(m_series[0].time, (datetime)((long)last + 240), r);
      string why;
      bool ok = CheckSlice(m_series, r, ArraySize(m_series), why);
      AddResult("T188", ok, "T01 full available range: " + why);
     }

   void T189_Year()
     {
      GZ_ResearchRange r; GZRangeYear(2020, r);
      string why; bool ok = CheckSlice(m_series, r, 366*24, why);
      AddResult("T189", ok, "T02 single year (2020, leap): " + why);
     }

   void T190_Month()
     {
      GZ_ResearchRange r; GZRangeMonth(2020, 2, r);
      string why; bool ok = CheckSlice(m_series, r, 29*24, why);
      ok = ok && (r.eff_end == T(2020,2,29,23,59));
      AddResult("T190", ok, "T03 single month (2020-02, leap): " + why);
     }

   void T191_Week()
     {
      GZ_ResearchRange r; GZRangeWeek(T(2020,3,2,15,45), r);
      string why; bool ok = CheckSlice(m_series, r, 7*24, why);
      ok = ok && (r.eff_start == T(2020,3,2,0,0)) && (r.eff_end == T(2020,3,8,23,59));
      AddResult("T191", ok, "T04 single week (starting date 2020-03-02): " + why);
     }

   void T192_Day()
     {
      GZ_ResearchRange r; GZRangeDay(2020, 6, 15, r);
      string why; bool ok = CheckSlice(m_series, r, 24, why);
      AddResult("T192", ok, "T05 single day (2020-06-15): " + why);
     }

   void T193_Custom()
     {
      GZ_ResearchRange r; GZRangeCustom(T(2020,7,15,8,0), T(2020,8,27,17,30), r);
      string why; bool ok = CheckSlice(m_series, r, 1042, why);
      ok = ok && (r.eff_start == T(2020,7,15,8,0)) && (r.eff_end == T(2020,8,27,17,29));
      AddResult("T193", ok, "T06 custom range 2020-07-15 08:00 -> 2020-08-27 17:30 (end aligned down to 17:29, 17:30 M5 window incomplete): " + why);
     }

   void T194_MonthYearBoundary()
     {
      GZ_ResearchRange rd, rj, rboth;
      GZRangeMonth(2020, 12, rd); GZRangeMonth(2021, 1, rj);
      GZRangeCustom(T(2020,12,1,0,0), T(2021,1,31,23,59), rboth);
      MqlRates od[], oj[], ob[];
      int cd = GZSliceRates(m_series, rd.eff_start, rd.eff_end, od);
      int cj = GZSliceRates(m_series, rj.eff_start, rj.eff_end, oj);
      int cb = GZSliceRates(m_series, rboth.eff_start, rboth.eff_end, ob);
      bool ok = (cd==31*24) && (cj==10*24) && (cb==cd+cj) &&
                (od[cd-1].time==T(2020,12,31,23,0)) && (oj[0].time==T(2021,1,1,0,0)) &&
                (od[cd-1].time < oj[0].time) && (ob[cd-1].time==od[cd-1].time) && (ob[cd].time==oj[0].time);
      AddResult("T194", ok, StringFormat("T07 month/year boundary: Dec=%d Jan=%d (data ends Jan 10) union=%d; last Dec bar %s, first Jan bar %s, no bar in both",
                cd, cj, cb, cd>0?TimeToString(od[cd-1].time):"-", cj>0?TimeToString(oj[0].time):"-"));
     }

   void T195_IncompleteCoverage()
     {
      MqlRates b[];
      BuildStep(T(2020,1,10,0,0), 71*24, 3600, b);   // 2020-01-10 00:00 .. 2020-03-20 23:00
      GZ_ResearchRange rj, rm, rf, ry19, rall;
      GZRangeMonth(2020,1,rj); GZRangeMonth(2020,2,rf); GZRangeMonth(2020,3,rm); GZRangeYear(2019,ry19);
      GZRangeCustom(T(2019,1,1,0,0), T(2021,12,31,23,59), rall);
      string w1, w2, w3, w4, w5;
      bool ok = CheckSlice(b, rj, 22*24, w1) && CheckSlice(b, rf, 29*24, w2) && CheckSlice(b, rm, 20*24, w3) &&
                CheckSlice(b, ry19, 0, w4) && CheckSlice(b, rall, 71*24, w5);
      AddResult("T195", ok, "T08 incomplete beginning/end coverage (data 2020-01-10..2020-03-20): Jan[" + w1 + "] Feb[" + w2 + "] Mar[" + w3 + "] 2019[" + w4 + "] wide[" + w5 + "]");
     }

   //--- T196-T199, T202 : pipeline over slices ----------------------------------
   void T196_NoTradesOutsideRange()
     {
      MqlRates c1[], c5[];
      BuildCombined(c1, c5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(c1, c5, "SYN", T(2026,3,1,0,0), T(2026,5,31,23,59), GetPointer(val));

      GZ_ResearchRange ra, rb, rgap, rfull;
      GZRangeDay(2026,3,2,ra); GZRangeDay(2026,5,4,rb); GZRangeDay(2026,4,1,rgap);
      GZRangeCustom(T(2026,3,1,0,0), T(2026,5,31,23,59), rfull);

      GZ_ResearchRange rs[4]; rs[0]=ra; rs[1]=rb; rs[2]=rgap; rs[3]=rfull;
      int expect_min[4] = {1,1,0,1};
      bool ok = true;
      string detail = "";
      for(int i=0;i<4;i++)
        {
         MqlRates s1[], s5[];
         ds.Slice(rs[i], s1, s5);
         GZ_ExperimentResult res; CGZRunDetail d;
         RunPipeline(s1, s5, 2.0, 0.0, res, GetPointer(d));
         int outside = 0;
         for(int k=0;k<d.count;k++)
            if(d.entry_time[k] < rs[i].eff_start || d.entry_time[k] > rs[i].eff_end) outside++;
         bool this_ok = (outside==0) && (d.count>=expect_min[i]) && (i==3 || d.count==expect_min[i]);
         ok = ok && this_ok;
         detail += StringFormat("%s: trades=%d outside=%d %s; ", rs[i].label, d.count, outside, this_ok?"ok":"BAD");
        }
      AddResult("T196", ok, "T09 no trade outside the selected range enters the population (cold start: population = entries inside the slice): " + detail);
     }

   void T197_SameResultTwice()
     {
      MqlRates c1[], c5[];
      BuildCombined(c1, c5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(c1, c5, "SYN", T(2026,3,1,0,0), T(2026,5,31,23,59), GetPointer(val));
      GZ_ResearchRange rb, rfull;
      GZRangeDay(2026,5,4,rb); GZRangeCustom(T(2026,3,1,0,0), T(2026,5,31,23,59), rfull);

      bool ok = true;
      string detail = "";
      for(int i=0;i<2;i++)
        {
         GZ_ResearchRange r;
         if(i==0) r = rb; else r = rfull;
         MqlRates a1[], a5[], b1[], b5[];
         ds.Slice(r, a1, a5); ds.Slice(r, b1, b5);
         GZ_ExperimentResult x, y; CGZRunDetail dx, dy;
         RunPipeline(a1, a5, 2.0, 0.0, x, GetPointer(dx));
         RunPipeline(b1, b5, 2.0, 0.0, y, GetPointer(dy));
         bool same = SameBars(a1,b1) && SameBars(a5,b5) && SameDetail(GetPointer(dx), GetPointer(dy)) &&
                     (x.trade_count==y.trade_count) && Near(x.metrics.trade.net_r, y.metrics.trade.net_r) &&
                     Near(x.metrics.behavior.avg_mae_r, y.metrics.behavior.avg_mae_r) && Near(x.metrics.behavior.avg_mfe_r, y.metrics.behavior.avg_mfe_r);
         ok = ok && same;
         detail += StringFormat("%s: trades %d/%d net_r %.4f/%.4f identical=%s; ", r.label, x.trade_count, y.trade_count,
                                x.metrics.trade.net_r, y.metrics.trade.net_r, same?"true":"false");
        }
      AddResult("T197", ok, "T10 same configuration + same range twice -> identical slice and identical result: " + detail);
     }

   void T198_NoCrossRunContamination()
     {
      MqlRates c1[], c5[];
      BuildCombined(c1, c5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(c1, c5, "SYN", T(2026,3,1,0,0), T(2026,5,31,23,59), GetPointer(val));
      GZ_ResearchRange rb, rfull;
      GZRangeDay(2026,5,4,rb); GZRangeCustom(T(2026,3,1,0,0), T(2026,5,31,23,59), rfull);

      double sum0 = ds.Checksum();
      MqlRates f1[], f5[];
      ds.Slice(rfull, f1, f5);
      GZ_ExperimentResult first; CGZRunDetail d_first;
      RunPipeline(f1, f5, 2.0, 0.0, first, GetPointer(d_first));

      MqlRates s1[], s5[];
      ds.Slice(rb, s1, s5);
      s5[0].close += 1000.0;                 // vandalise the COPY
      GZ_ExperimentResult sub; CGZRunDetail d_sub;
      RunPipeline(s1, s5, 2.0, 0.0, sub, GetPointer(d_sub));
      double sum1 = ds.Checksum();

      MqlRates g1[], g5[];
      ds.Slice(rfull, g1, g5);
      GZ_ExperimentResult second; CGZRunDetail d_second;
      RunPipeline(g1, g5, 2.0, 0.0, second, GetPointer(d_second));

      bool ok = Near(sum0, sum1) && SameBars(f1,g1) && SameBars(f5,g5) && SameDetail(GetPointer(d_first), GetPointer(d_second)) &&
                (first.trade_count==second.trade_count) && Near(first.metrics.trade.net_r, second.metrics.trade.net_r);
      AddResult("T198", ok, StringFormat("T11 full-range result unaffected by a sub-range run in between (dataset checksum %.6f -> %.6f, slices/results identical: full trades %d/%d, sub-range trades %d)",
                sum0, sum1, first.trade_count, second.trade_count, sub.trade_count));
     }

   void T199_SchemaIdentical()
     {
      MqlRates c1[], c5[];
      BuildCombined(c1, c5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(c1, c5, "SYN", T(2026,3,1,0,0), T(2026,5,31,23,59), GetPointer(val));
      GZ_ResearchRange ra, rfull;
      GZRangeDay(2026,3,2,ra); GZRangeCustom(T(2026,3,1,0,0), T(2026,5,31,23,59), rfull);

      GZ_ExperimentConfig cfg; cfg.Default();
      cfg.time_config.broker_offset_known = true;
      GZ_RewardBeBaselineRef bref; bref.Clear();

      MqlRates a1[], a5[], f1[], f5[];
      ds.Slice(ra, a1, a5); ds.Slice(rfull, f1, f5);

      CGZRewardBeEngine ea(m_logger);
      CGZRewardBeEngine ef(m_logger);
      datetime fa = a5[0].time, la = a5[ArraySize(a5)-1].time;
      datetime ff = f5[0].time, lf = f5[ArraySize(f5)-1].time;
      ea.Run(cfg, a1, a5, "DS_RANGE_A", GZ_VAL_VALID, GZ_VAL_VALID, (datetime)(fa-86400), (datetime)(la+86400), (datetime)(la+2*86400), true, bref);
      ef.Run(cfg, f1, f5, "DS_RANGE_F", GZ_VAL_VALID, GZ_VAL_VALID, (datetime)(ff-86400), (datetime)(lf+86400), (datetime)(lf+2*86400), true, bref);

      bool ok = (ea.Status()==GZ_RB_STATUS_OK) && (ef.Status()==GZ_RB_STATUS_OK) && (ea.RowCount()==ef.RowCount()) && (ea.RowCount()>0) &&
                (ea.ExperimentCount()==ef.ExperimentCount()) && (ea.ValidationCount()==ef.ValidationCount());
      for(int i=0; ok && i<ea.RowCount(); i++)
        {
         GZ_RewardBeRow x = ea.GetRow(i), y = ef.GetRow(i);
         if(x.kind!=y.kind || !Near(x.tp_r,y.tp_r) || !Near(x.be_trigger_r,y.be_trigger_r)) ok = false;
        }
      string rep_a = ea.BuildReport("ctx", "", 0, 0);
      string rep_f = ef.BuildReport("ctx", "", 0, 0);
      string hdr_a = SectionHeaders(rep_a), hdr_f = SectionHeaders(rep_f);
      bool same_headers = (StringLen(hdr_a)>0) && (hdr_a==hdr_f);
      bool same_csv = (FirstLine(ea.BuildMatrixCsv())==FirstLine(ef.BuildMatrixCsv())) &&
                      (LineCount(ea.BuildMatrixCsv())==LineCount(ef.BuildMatrixCsv())) &&
                      (FirstLine(ea.BuildPairCsv())==FirstLine(ef.BuildPairCsv())) &&
                      (LineCount(ea.BuildPairCsv())==LineCount(ef.BuildPairCsv()));
      ok = ok && same_headers && same_csv;
      AddResult("T199", ok, StringFormat("T12 TP x BE output schema identical for a 1-day and a 3-month range: rows %d/%d, experiments %d/%d, report section headers identical=%s, CSV header+line counts identical=%s",
                ea.RowCount(), ef.RowCount(), ea.ExperimentCount(), ef.ExperimentCount(), same_headers?"true":"false", same_csv?"true":"false"));
     }

   void T200_BeGridPreserved()
     {
      string expect = "0.5:;1.0:0.50;1.5:1.00;2.0:1.00;2.5:1.00,2.00;3.0:1.00,2.00;3.5:1.00,2.00,3.00;4.0:1.00,2.00,3.00;4.5:1.00,2.00,3.00,4.00;";
      string got = GridText();
      int off = 0, act = 0;
      CGZRewardBeEngine::CountGrid(off, act);
      double tps[]; GZRewardBeTpGrid(tps);
      bool ok = (got==expect) && (ArraySize(tps)==9) && Near(tps[0],0.5) && Near(tps[8],4.5) && (off==9) && (act==17);
      AddResult("T200", ok, StringFormat("T13 reduced grid preserved exactly: %s | BE-off runs=%d BE-active runs=%d (expect 9 / 17 = 26 main configs)", got, off, act));
     }

   void T201_RemovedValuesAbsent()
     {
      double removed[12] = {0.25,0.75,1.25,1.5,1.75,2.25,2.5,2.75,3.25,3.5,3.75,4.25};
      double tps[], trigs[];
      GZRewardBeTpGrid(tps);
      int violations = 0;
      string first_bad = "";
      for(int t=0;t<ArraySize(tps);t++)
        {
         int n = GZRewardBeTriggersForTp(tps[t], trigs);
         for(int g=0; g<n; g++)
           {
            for(int r=0;r<12;r++)
               if(Near(trigs[g], removed[r])) { violations++; first_bad = StringFormat("TP%.1f BE%.2f", tps[t], trigs[g]); }
            if(!(trigs[g] < tps[t]-0.000001)) { violations++; first_bad = StringFormat("TP%.1f BE%.2f >= TP", tps[t], trigs[g]); }
            if(tps[t]>=2.0-0.000001 && MathAbs(trigs[g]-MathRound(trigs[g]))>0.000001) { violations++; first_bad = StringFormat("TP%.1f non-whole BE%.2f", tps[t], trigs[g]); }
           }
        }
      bool no_tp5 = true;
      for(int t=0;t<ArraySize(tps);t++) if(Near(tps[t],5.0)) no_tp5 = false;
      AddResult("T201", (violations==0) && no_tp5, StringFormat("T14 removed BE values (0.25/0.75/1.25/1.5/1.75/... and any trigger >= TP or fractional at TP>=2R) never produced; TP 5.0R absent=%s; violations=%d %s",
                no_tp5?"true":"false", violations, first_bad));
     }

   void T202_BaselineUnchanged()
     {
      MqlRates a1[], a5[], c1[], c5[];
      BuildScenarioA(a1, a5);
      BuildCombined(c1, c5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(c1, c5, "SYN", T(2026,3,1,0,0), T(2026,5,31,23,59), GetPointer(val));

      GZ_ResearchRange leg;
      GZRangeLegacyDev(a5[0].time, a5[ArraySize(a5)-1].time, leg);   // raw, unaligned: legacy semantic
      MqlRates s1[], s5[];
      ds.Slice(leg, s1, s5);
      bool same_arrays = SameBars(s1, a1) && SameBars(s5, a5);

      GZ_ExperimentResult direct, viaslice; CGZRunDetail dd, ds_d;
      RunPipeline(a1, a5, 2.0, 0.0, direct, GetPointer(dd));
      RunPipeline(s1, s5, 2.0, 0.0, viaslice, GetPointer(ds_d));
      bool ok = same_arrays && (leg.eff_start==leg.req_start) && (leg.eff_end==leg.req_end) && !leg.m5_aligned &&
                (direct.trade_count==1) && (viaslice.trade_count==1) && Near(direct.metrics.trade.net_r, 2.0) && Near(viaslice.metrics.trade.net_r, 2.0) &&
                SameDetail(GetPointer(dd), GetPointer(ds_d)) && (viaslice.metrics.trade.winners==1);
      AddResult("T202", ok, StringFormat("T15 TP=2R/BE-off baseline unchanged (legacy range = unaligned CopyRates-compatible slice): slice arrays identical to the direct arrays=%s; direct trades=%d net_r=%.4f | via slice trades=%d net_r=%.4f (Phase 15.5 fixture: 1 trade, +2R). The real 412-trade regression on live data is runtime check R07 in the Phase 15.7 report.",
                same_arrays?"true":"false", direct.trade_count, direct.metrics.trade.net_r, viaslice.trade_count, viaslice.metrics.trade.net_r));
     }

   //--- T203-T208 ---------------------------------------------------------------
   void T203_RangeBuilders()
     {
      GZ_ResearchRange y, m1, m2, m12, d, w, c, bad_order, bad_day, snap, fdev, leg, fds;
      GZRangeYear(2020, y); GZRangeMonth(2020,2,m1); GZRangeMonth(2021,2,m2); GZRangeMonth(2020,12,m12);
      GZRangeDay(2020,6,15,d); GZRangeWeek(T(2024,3,4,8,30), w);
      GZRangeCustom(T(2024,6,12,0,0), T(2024,6,19,23,59), c);
      GZRangeCustom(T(2024,6,19,0,0), T(2024,6,12,0,0), bad_order);
      GZRangeDay(2021,2,30,bad_day);
      GZRangeCustom(T(2020,6,15,12,2), T(2020,6,15,12,32), snap);
      GZRangeFullDev(T(2019,12,23,0,0), T(2026,6,13,0,0), fdev);
      GZRangeLegacyDev(T(2026,1,1,0,0), T(2026,6,13,0,0), leg);
      GZRangeFullDataset(T(2019,12,23,0,0), T(2026,9,24,23,59), fds);
      bool ok = (y.eff_start==T(2020,1,1,0,0)) && (y.eff_end==T(2020,12,31,23,59)) &&
                (m1.eff_end==T(2020,2,29,23,59)) && (m2.eff_end==T(2021,2,28,23,59)) && (m12.eff_end==T(2020,12,31,23,59)) && (m12.eff_start==T(2020,12,1,0,0)) &&
                (d.eff_start==T(2020,6,15,0,0)) && (d.eff_end==T(2020,6,15,23,59)) &&
                (w.eff_start==T(2024,3,4,0,0)) && (w.eff_end==T(2024,3,10,23,59)) &&
                (c.status==GZ_RSTATUS_OK) && (c.eff_start==T(2024,6,12,0,0)) && (c.eff_end==T(2024,6,19,23,59)) &&
                (bad_order.status==GZ_RSTATUS_INVALID_ORDER) && (bad_day.status==GZ_RSTATUS_INVALID_INPUT) &&
                (snap.eff_start==T(2020,6,15,12,5)) && (snap.eff_end==T(2020,6,15,12,29)) &&
                (fdev.eff_end==T(2026,6,12,23,59)) && (fdev.m5_aligned) &&
                (leg.eff_start==leg.req_start) && (leg.eff_end==T(2026,6,13,0,0)) && !leg.m5_aligned &&
                (fds.eff_start==T(2019,12,23,0,0)) && (fds.eff_end==T(2026,9,24,23,59));
      AddResult("T203", ok, "range builders: year/month(leap, Dec->Jan rollover)/day/week/custom resolve to inclusive [start,end]; invalid order/day rejected; custom 12:02-12:32 aligned to 12:05-12:29; FULL_DEV stops before the boundary bar; LEGACY_DEV unaligned");
     }

   void T204_PartitionBoundary()
     {
      datetime B = T(2026,6,13,0,0);
      GZ_ResearchRange leg, may, jun, d13, d12, jul, fds, fdev;
      GZRangeLegacyDev(T(2026,1,1,0,0), T(2026,6,13,0,0), leg);
      GZRangeMonth(2026,5,may); GZRangeMonth(2026,6,jun); GZRangeDay(2026,6,13,d13); GZRangeDay(2026,6,12,d12);
      GZRangeMonth(2026,7,jul); GZRangeFullDataset(T(2019,12,23,0,0), T(2026,9,24,23,59), fds); GZRangeFullDev(T(2019,12,23,0,0), B, fdev);
      bool ok = (GZClassifyPartition(leg.eff_start, leg.eff_end, B)==GZ_PART_DEVELOPMENT_ELIGIBLE) &&
                (GZClassifyPartition(may.eff_start, may.eff_end, B)==GZ_PART_DEVELOPMENT_ELIGIBLE) &&
                (GZClassifyPartition(jun.eff_start, jun.eff_end, B)==GZ_PART_CROSSES_LEGACY_OOS) &&
                (GZClassifyPartition(d13.eff_start, d13.eff_end, B)==GZ_PART_LEGACY_OOS_ONLY) &&
                (GZClassifyPartition(d12.eff_start, d12.eff_end, B)==GZ_PART_DEVELOPMENT_ELIGIBLE) &&
                (GZClassifyPartition(jul.eff_start, jul.eff_end, B)==GZ_PART_LEGACY_OOS_ONLY) &&
                (GZClassifyPartition(fds.eff_start, fds.eff_end, B)==GZ_PART_CROSSES_LEGACY_OOS) &&
                (GZClassifyPartition(fdev.eff_start, fdev.eff_end, B)==GZ_PART_DEVELOPMENT_ELIGIBLE);

      //--- the dataset itself keeps AND serves data on both sides of the boundary
      MqlRates s[];
      BuildStep(T(2026,6,10,0,0), 10*24, 3600, s);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(s, s, "SYN", T(2026,6,10,0,0), T(2026,6,19,23,59), GetPointer(val));
      MqlRates o1[], o5[], p1[], p5[];
      ds.Slice(d12, o1, o5); ds.Slice(d13, p1, p5);
      bool both = (ArraySize(o1)==24) && (ArraySize(p1)==24) && (o1[23].time < B) && (p1[0].time == B);
      AddResult("T204", ok && both, StringFormat("Development/OOS boundary %s preserved: legacy+May+Jun12+FULL_DEV eligible, Jun crosses, Jun13/Jul OOS-only, FULL_DATASET crosses (research refuses those); dataset still slices both sides (day before boundary=%d bars, boundary day=%d bars)",
                TimeToString(B, TIME_DATE|TIME_MINUTES), ArraySize(o1), ArraySize(p1)));
     }

   //--- shared fixture for T205/T206
   void BuildCoverageFixture(MqlRates &m1[], MqlRates &m5[])
     {
      MqlRates a[], b[], c[], d[], e[], x[], y[], z[];
      datetime nohole = 0;
      // M1
      BuildDense(T(2021,1,4,0,0), T(2021,1,9,0,0), 60, true, nohole, nohole, a);                       // Jan: five days only
      BuildDense(T(2021,2,1,0,0), T(2021,3,1,0,0), 60, true, T(2021,2,10,10,0), T(2021,2,10,12,0), b); // Feb: 2h weekday hole
      BuildDense(T(2021,4,1,0,0), T(2021,5,1,0,0), 60, true, nohole, nohole, c);                       // Apr: complete
      BuildDense(T(2021,5,1,0,0), T(2021,6,1,0,0), 60, true, nohole, nohole, d);                       // May: complete
      int n = ArraySize(a)+ArraySize(b)+ArraySize(c)+ArraySize(d);
      ArrayResize(m1, n);
      int k = 0;
      for(int i=0;i<ArraySize(a);i++) m1[k++] = a[i];
      for(int i=0;i<ArraySize(b);i++) m1[k++] = b[i];
      for(int i=0;i<ArraySize(c);i++) m1[k++] = c[i];
      for(int i=0;i<ArraySize(d);i++) m1[k++] = d[i];
      // M5 (April loses the 2021-04-14 12:00 window)
      BuildDense(T(2021,1,4,0,0), T(2021,1,9,0,0), 300, true, nohole, nohole, x);
      BuildDense(T(2021,2,1,0,0), T(2021,3,1,0,0), 300, true, T(2021,2,10,10,0), T(2021,2,10,12,0), y);
      BuildDense(T(2021,4,1,0,0), T(2021,5,1,0,0), 300, true, T(2021,4,14,12,0), T(2021,4,14,12,5), z);
      BuildDense(T(2021,5,1,0,0), T(2021,6,1,0,0), 300, true, nohole, nohole, e);
      int n5 = ArraySize(x)+ArraySize(y)+ArraySize(z)+ArraySize(e);
      ArrayResize(m5, n5);
      k = 0;
      for(int i=0;i<ArraySize(x);i++) m5[k++] = x[i];
      for(int i=0;i<ArraySize(y);i++) m5[k++] = y[i];
      for(int i=0;i<ArraySize(z);i++) m5[k++] = z[i];
      for(int i=0;i<ArraySize(e);i++) m5[k++] = e[i];
     }

   void T205_CoverageMonths()
     {
      MqlRates m1[], m5[];
      BuildCoverageFixture(m1, m5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(m1, m5, "SYN", T(2021,1,1,0,0), T(2021,5,31,23,59), GetPointer(val));
      CGZCoverage *cv = ds.Coverage();
      bool ok = (cv.MonthCount()==5) &&
                (cv.MonthStatus(0)==GZ_COV_PARTIAL) &&     // Jan: 5 days of data
                (cv.MonthStatus(1)==GZ_COV_OK_GAPS) &&     // Feb: complete except a 2h weekday hole
                (cv.MonthStatus(2)==GZ_COV_MISSING) &&     // Mar: nothing
                (cv.MonthStatus(3)==GZ_COV_MISMATCH) &&    // Apr: one M5 window missing while its M1 minutes exist
                (cv.MonthStatus(4)==GZ_COV_OK) &&          // May: complete
                (cv.MissingRangeTotal()==2) &&             // Jan->Feb and Feb->Apr internal holes (>= 4 days)
                (cv.MonthKey(0)==202101) && (cv.MonthKey(4)==202105) &&
                (cv.MissingRangesNotAccepted(T(2021,1,8,23,59), T(2021,2,1,0,0))==1) &&   // one hole accepted -> the other stays unexplained
                (cv.MissingRangesNotAccepted(T(2019,1,1,0,0), T(2019,1,2,0,0))==2);       // an unrelated accepted window explains nothing
      AddResult("T205", ok, StringFormat("coverage months (Jan..May 2021) = %s/%s/%s/%s/%s (expect PARTIAL/OK_GAPS/MISSING/MISMATCH/OK), missing ranges=%d (expect 2), M5 windows Apr=%d vs M5 bars Apr=%d",
                GZCovStatusToString(cv.MonthStatus(0)), GZCovStatusToString(cv.MonthStatus(1)), GZCovStatusToString(cv.MonthStatus(2)),
                GZCovStatusToString(cv.MonthStatus(3)), GZCovStatusToString(cv.MonthStatus(4)), cv.MissingRangeTotal(), cv.MonthM5Windows(3), cv.MonthM5(3)));
     }

   void T206_GapClassificationMatchesValidator()
     {
      MqlRates m1[], m5[];
      BuildCoverageFixture(m1, m5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(m1, m5, "SYN", T(2021,1,1,0,0), T(2021,5,31,23,59), GetPointer(val));
      CGZCoverage *cv = ds.Coverage();

      CGZDatasetInfo i1, i5;
      i1.Clear(); i5.Clear();
      val.ValidateTimestamps(m1, GZ_SPACING_M1_SECONDS, i1);
      val.ValidateTimestamps(m5, GZ_SPACING_M5_SECONDS, i5);
      bool ok = ((long)i1.missing_bar_count==cv.TotalUnexpectedM1()) && ((long)i1.expected_gap_count==cv.TotalExpectedM1()) &&
                ((long)i5.missing_bar_count==cv.TotalUnexpectedM5()) && ((long)i5.expected_gap_count==cv.TotalExpectedM5()) &&
                (cv.TotalM1()==(long)ArraySize(m1)) && (cv.TotalM5()==(long)ArraySize(m5)) &&
                (i1.missing_bar_count>=1) && (i1.expected_gap_count>=1);
      AddResult("T206", ok, StringFormat("coverage gap classification == Phase 1 validator: M1 unexpected %d/%d expected %d/%d | M5 unexpected %d/%d expected %d/%d | bar totals %d/%d (M1) %d/%d (M5); weekend gaps stay EXPECTED, the 2h weekday hole stays UNEXPECTED",
                (int)cv.TotalUnexpectedM1(), i1.missing_bar_count, (int)cv.TotalExpectedM1(), i1.expected_gap_count,
                (int)cv.TotalUnexpectedM5(), i5.missing_bar_count, (int)cv.TotalExpectedM5(), i5.expected_gap_count,
                (int)cv.TotalM1(), ArraySize(m1), (int)cv.TotalM5(), ArraySize(m5)));
     }

   void T207_M5AlignmentNoLeak()
     {
      MqlRates m1[], m5[];
      datetime nohole = 0;
      BuildDense(T(2020,6,15,11,0), T(2020,6,15,14,0), 60, false, nohole, nohole, m1);
      BuildDense(T(2020,6,15,11,0), T(2020,6,15,14,0), 300, false, nohole, nohole, m5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(m1, m5, "SYN", T(2020,6,15,11,0), T(2020,6,15,13,59), GetPointer(val));
      GZ_ResearchRange r; GZRangeCustom(T(2020,6,15,12,2), T(2020,6,15,12,32), r);
      MqlRates s1[], s5[];
      ds.Slice(r, s1, s5);
      int n1 = ArraySize(s1), n5 = ArraySize(s5);
      bool ok = (n1==25) && (n5==5) && (s1[0].time==T(2020,6,15,12,5)) && (s1[n1-1].time==T(2020,6,15,12,29)) &&
                (s5[0].time==T(2020,6,15,12,5)) && (s5[n5-1].time==T(2020,6,15,12,25)) && (n1==5*n5) &&
                ((long)s5[n5-1].time + 240 <= (long)r.eff_end);
      AddResult("T207", ok, StringFormat("M5 alignment: custom 12:02-12:32 -> M1 %d bars [%s..%s], M5 %d bars [%s..%s]; every M5 window fully covered by M1 (M1 = 5 x M5) and no M5 bar built from minutes after the range end",
                n1, n1>0?TimeToString(s1[0].time):"-", n1>0?TimeToString(s1[n1-1].time):"-", n5, n5>0?TimeToString(s5[0].time):"-", n5>0?TimeToString(s5[n5-1].time):"-"));
     }

   void T208_ReleaseKeepsCoverage()
     {
      MqlRates m1[], m5[];
      BuildCoverageFixture(m1, m5);
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(m1, m5, "SYN", T(2021,1,1,0,0), T(2021,5,31,23,59), GetPointer(val));
      int worst_before = ds.Coverage().WorstStatus();
      GZ_ResearchRange r; GZRangeMonth(2021,5,r);
      MqlRates a1[], a5[], b1[], b5[];
      int c_before = ds.Slice(r, a1, a5);
      ds.ReleaseBars();
      int c_after = ds.Slice(r, b1, b5);
      bool ok = (c_before>0) && (c_after==0) && ds.BarsReleased() && (ds.Coverage().WorstStatus()==worst_before) && (ds.M1Count()==ArraySize(m1));
      AddResult("T208", ok, StringFormat("releasing the raw bars (memory) keeps coverage/validation but refuses further slices instead of returning stale data: slice before=%d after=%d", c_before, c_after));
     }

   void T209_SparseMonthDetected()
     {
      // Jan: hourly bars only (no single gap reaches 4 days); Feb, Mar: full 1-minute weekdays
      MqlRates m1[], m5[], a[], b[], c[], x[], y[], z[];
      datetime nohole = 0;
      BuildDense(T(2021,1,4,0,0), T(2021,2,1,0,0), 3600, true, nohole, nohole, a);
      BuildDense(T(2021,2,1,0,0), T(2021,3,1,0,0), 60, true, nohole, nohole, b);
      BuildDense(T(2021,3,1,0,0), T(2021,4,1,0,0), 60, true, nohole, nohole, c);
      BuildDense(T(2021,1,4,0,0), T(2021,2,1,0,0), 3600, true, nohole, nohole, x);
      BuildDense(T(2021,2,1,0,0), T(2021,3,1,0,0), 300, true, nohole, nohole, y);
      BuildDense(T(2021,3,1,0,0), T(2021,4,1,0,0), 300, true, nohole, nohole, z);
      int n1 = ArraySize(a)+ArraySize(b)+ArraySize(c);
      int n5 = ArraySize(x)+ArraySize(y)+ArraySize(z);
      ArrayResize(m1, n1); ArrayResize(m5, n5);
      int k = 0;
      for(int i=0;i<ArraySize(a);i++) m1[k++] = a[i];
      for(int i=0;i<ArraySize(b);i++) m1[k++] = b[i];
      for(int i=0;i<ArraySize(c);i++) m1[k++] = c[i];
      k = 0;
      for(int i=0;i<ArraySize(x);i++) m5[k++] = x[i];
      for(int i=0;i<ArraySize(y);i++) m5[k++] = y[i];
      for(int i=0;i<ArraySize(z);i++) m5[k++] = z[i];
      CGZDataValidator val(m_logger);
      CGZHistoricalDataset ds(m_logger);
      ds.Attach(m1, m5, "SYN", T(2021,1,1,0,0), T(2021,3,31,23,59), GetPointer(val));
      CGZCoverage *cv = ds.Coverage();
      bool ok = (cv.MonthCount()==3) && (cv.MonthStatus(0)==GZ_COV_PARTIAL) && (cv.MonthStatus(1)==GZ_COV_OK) && (cv.MonthStatus(2)==GZ_COV_OK) &&
                (cv.MonthLongGapsM1(0)==0);
      AddResult("T209", ok, StringFormat("sparse month detected: Jan holds hourly bars only (M1=%d, no gap >= 4 days) -> %s (expect PARTIAL); Feb=%s Mar=%s (expect OK)",
                cv.MonthM1(0), GZCovStatusToString(cv.MonthStatus(0)), GZCovStatusToString(cv.MonthStatus(1)), GZCovStatusToString(cv.MonthStatus(2))));
     }

public:
                     CGZDatasetTests(CGZLogger *logger=NULL) { m_logger = logger; }

   int               ResultCount() const { return ArraySize(m_results); }
   GZ_TestResult     GetResult(int i) const { return m_results[i]; }

   void              RunAll()
     {
      ArrayResize(m_results, 0);
      BuildStep(T(2019,12,23,0,0), 385*24, 3600, m_series);   // 2019-12-23 00:00 .. 2021-01-10 23:00

      T188_FullRange();
      T189_Year();
      T190_Month();
      T191_Week();
      T192_Day();
      T193_Custom();
      T194_MonthYearBoundary();
      T195_IncompleteCoverage();
      T196_NoTradesOutsideRange();
      T197_SameResultTwice();
      T198_NoCrossRunContamination();
      T199_SchemaIdentical();
      T200_BeGridPreserved();
      T201_RemovedValuesAbsent();
      T202_BaselineUnchanged();
      T203_RangeBuilders();
      T204_PartitionBoundary();
      T205_CoverageMonths();
      T206_GapClassificationMatchesValidator();
      T207_M5AlignmentNoLeak();
      T208_ReleaseKeepsCoverage();
      T209_SparseMonthDetected();
     }
  };

#endif // __GZ_DATASET_TESTS_MQH__
