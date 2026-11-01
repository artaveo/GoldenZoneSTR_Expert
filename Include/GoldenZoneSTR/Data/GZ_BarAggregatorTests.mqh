//+------------------------------------------------------------------+
//| GZ_BarAggregatorTests.mqh - Execution Timeframe aggregation       |
//| T285-T288, synthetic M1 bars only (same self-contained-suite       |
//| convention as GZ_CostRSymTests.mqh / GZ_HtfBiasTests.mqh).         |
//+------------------------------------------------------------------+
#ifndef __GZ_BAR_AGGREGATOR_TESTS_MQH__
#define __GZ_BAR_AGGREGATOR_TESTS_MQH__

#include "GZ_BarAggregator.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZBarAggregatorTests
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

   datetime MakeTime(int h,int mi) const
     {
      MqlDateTime dt;
      dt.year=2026; dt.mon=3; dt.day=2; dt.hour=h; dt.min=mi; dt.sec=0;
      return StructToTime(dt);
     }

   MqlRates Bar(datetime t, double o, double h, double l, double c, int spread, long vol=10) const
     {
      MqlRates r;
      r.time=t; r.open=o; r.high=h; r.low=l; r.close=c;
      r.tick_volume=vol; r.spread=spread; r.real_volume=0;
      return r;
     }

   bool Near(double a, double b) const { return MathAbs(a-b)<0.0000001; }

   //--- T285: two full M5 buckets, hand-computed OHLC / volume / max spread
   void T285_M5HandComputed()
     {
      MqlRates m1[]; ArrayResize(m1,10);
      m1[0]=Bar(MakeTime(9,0),100.0,101.0, 99.5,100.5,20);
      m1[1]=Bar(MakeTime(9,1),100.5,103.0,100.0,102.0,25);
      m1[2]=Bar(MakeTime(9,2),102.0,102.0, 99.0,100.5,22);
      m1[3]=Bar(MakeTime(9,3),100.5,102.5,100.0,101.0,30);
      m1[4]=Bar(MakeTime(9,4),101.0,101.5,100.2,101.0,21);
      m1[5]=Bar(MakeTime(9,5),101.0,104.0,101.0,103.0,18);
      m1[6]=Bar(MakeTime(9,6),103.0,103.5, 98.0, 99.0,40);
      m1[7]=Bar(MakeTime(9,7), 99.0,100.0, 98.5, 99.5,19);
      m1[8]=Bar(MakeTime(9,8), 99.5,101.0, 99.0,100.0,23);
      m1[9]=Bar(MakeTime(9,9),100.0,100.5, 99.5,100.2,24);
      MqlRates m5[]; int n = GZAggregateBars(m1, 5, m5);
      bool ok = (n==2) &&
                (m5[0].time==MakeTime(9,0)) && Near(m5[0].open,100.0) && Near(m5[0].high,103.0) && Near(m5[0].low,99.0) &&
                Near(m5[0].close,101.0) && (m5[0].spread==30) && (m5[0].tick_volume==50) &&
                (m5[1].time==MakeTime(9,5)) && Near(m5[1].open,101.0) && Near(m5[1].high,104.0) && Near(m5[1].low,98.0) &&
                Near(m5[1].close,100.2) && (m5[1].spread==40) && (m5[1].tick_volume==50);
      AddResult("T285", ok, StringFormat("10 M1 -> %d M5 | bar0 O=%.1f H=%.1f L=%.1f C=%.1f spr=%d vol=%d | bar1 O=%.1f H=%.1f L=%.1f C=%.1f spr=%d vol=%d (expect 2 bars: 100/103/99/101/30/50 and 101/104/98/100.2/40/50)",
                n, m5[0].open,m5[0].high,m5[0].low,m5[0].close,m5[0].spread,(int)m5[0].tick_volume,
                m5[1].open,m5[1].high,m5[1].low,m5[1].close,m5[1].spread,(int)m5[1].tick_volume));
     }

   //--- T286: M15 with missing minutes - bucket-start time, never fabricated
   void T286_M15GapsNeverFabricated()
     {
      MqlRates m1[]; ArrayResize(m1,4);
      m1[0]=Bar(MakeTime(10,0), 50.0,51.0,49.0,50.5,10);
      m1[1]=Bar(MakeTime(10,1), 50.5,52.0,50.0,51.5,12);
      m1[2]=Bar(MakeTime(10,14),51.5,51.8,50.9,51.0,11);
      m1[3]=Bar(MakeTime(10,20),60.0,61.0,59.0,60.5,15);   // next bucket starts 10:15, first minute present is 10:20
      MqlRates m15[]; int n = GZAggregateBars(m1, 15, m15);
      bool ok = (n==2) && (m15[0].time==MakeTime(10,0)) && Near(m15[0].open,50.0) && Near(m15[0].high,52.0) &&
                Near(m15[0].low,49.0) && Near(m15[0].close,51.0) && (m15[0].spread==12) &&
                (m15[1].time==MakeTime(10,15)) && Near(m15[1].open,60.0) && Near(m15[1].close,60.5);
      AddResult("T286", ok, StringFormat("4 M1 (gap 10:15-10:19 missing) -> %d M15: bar0 time=%s C=%.1f | bar1 time=%s O=%.1f (expect 2 bars, bucket-start times 10:00 and 10:15, no fabricated minutes)",
                n, TimeToString(m15[0].time,TIME_MINUTES), m15[0].close, TimeToString(m15[1].time,TIME_MINUTES), m15[1].open));
     }

   //--- T287: period 1 is an exact copy (default setting = old behavior)
   void T287_M1IsIdentityCopy()
     {
      MqlRates m1[]; ArrayResize(m1,5);
      for(int i=0;i<5;i++)
         m1[i]=Bar(MakeTime(11,i), 70.0+i, 71.0+i, 69.0+i, 70.5+i, 20+i, 100+i);
      MqlRates cp[]; int n = GZAggregateBars(m1, 1, cp);
      bool ok = (n==5);
      for(int i=0;i<5 && ok;i++)
         ok = (cp[i].time==m1[i].time) && Near(cp[i].open,m1[i].open) && Near(cp[i].high,m1[i].high) &&
              Near(cp[i].low,m1[i].low) && Near(cp[i].close,m1[i].close) && (cp[i].spread==m1[i].spread) &&
              (cp[i].tick_volume==m1[i].tick_volume);
      AddResult("T287", ok, StringFormat("period=1 -> %d bars, every field identical to the source (expect exact copy)", n));
     }

   //--- T288: determinism, alignment, conservation and hierarchy: M1->M5->M15
   //--- must equal M1->M15 directly (OHLC, volume, max spread).
   void T288_DeterminismAlignmentHierarchy()
     {
      int N = 480;                                   // 8 hours of M1
      MqlRates m1[]; ArrayResize(m1,N);
      datetime t0 = MakeTime(0,0);
      for(int i=0;i<N;i++)
        {
         double b = 100.0 + MathSin(i*0.37)*3.0 + (i%7)*0.1;
         m1[i]=Bar(t0+i*60, b, b+0.4+(i%5)*0.05, b-0.4-(i%3)*0.05, b+0.1, 15+(i*7)%40, 5+(i%9));
        }
      MqlRates a5[], b5[], m15d[], m15h[];
      int na = GZAggregateBars(m1, 5, a5);
      int nb = GZAggregateBars(m1, 5, b5);
      int nd = GZAggregateBars(m1, 15, m15d);
      // hierarchical: aggregate the M5 result again to M15 (M5 bars are 5-minute bars, so bucket them by 15)
      int nh = GZAggregateBars(a5, 15, m15h);

      bool ok = (na==nb) && (na==N/5) && (nd==N/15) && (nh==nd);
      long vol1=0, volA=0, volD=0;
      for(int i=0;i<N;i++) vol1 += m1[i].tick_volume;
      for(int i=0;i<na && ok;i++)
        {
         volA += a5[i].tick_volume;
         ok = (a5[i].time==b5[i].time) && Near(a5[i].open,b5[i].open) && Near(a5[i].high,b5[i].high) &&
              Near(a5[i].low,b5[i].low) && Near(a5[i].close,b5[i].close) && (a5[i].spread==b5[i].spread) &&
              (((long)a5[i].time % 300)==0) && (i==0 || a5[i].time>a5[i-1].time);
        }
      for(int i=0;i<nd && ok;i++)
        {
         volD += m15d[i].tick_volume;
         ok = (((long)m15d[i].time % 900)==0) && Near(m15d[i].open,m15h[i].open) && Near(m15d[i].high,m15h[i].high) &&
              Near(m15d[i].low,m15h[i].low) && Near(m15d[i].close,m15h[i].close) &&
              (m15d[i].spread==m15h[i].spread) && (m15d[i].tick_volume==m15h[i].tick_volume);
        }
      ok = ok && (vol1==volA) && (vol1==volD);
      AddResult("T288", ok, StringFormat("480 M1 -> M5=%d M15=%d | two runs identical, bucket-aligned times, volume conserved (%d/%d/%d), M1->M5->M15 == M1->M15 (expect 96 / 32, all true)",
                na, nd, (int)vol1, (int)volA, (int)volD));
     }

public:
                     CGZBarAggregatorTests(CGZLogger *logger=NULL) { m_logger=logger; }

   int               ResultCount() const { return ArraySize(m_results); }
   GZ_TestResult     GetResult(int i) const { return m_results[i]; }

   void              RunAll()
     {
      T285_M5HandComputed();
      T286_M15GapsNeverFabricated();
      T287_M1IsIdentityCopy();
      T288_DeterminismAlignmentHierarchy();
     }
  };

#endif // __GZ_BAR_AGGREGATOR_TESTS_MQH__
