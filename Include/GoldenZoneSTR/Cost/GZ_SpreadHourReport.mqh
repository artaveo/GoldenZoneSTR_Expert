//+------------------------------------------------------------------+
//| GZ_SpreadHourReport.mqh                                           |
//| GoldenZone STR - Phase "First_Change_In_Structure" - Step 1       |
//|                                                                    |
//| Diagnostic-only (produces a printable table + a PROPOSAL, never a |
//| decision): per broker-hour (00-23, raw M1 timestamp, independent  |
//| of Step 0's UTC/NY conversion - see spec Section 4) spread stats  |
//| (count, avg, median, p95, zero%) over whichever M1 slice the      |
//| caller passes in. Reuses GZCostMedian/GZCostPercentile/GZCostPadL/|
//| GZCostPadR from GZ_CostEngine.mqh (Phase 15.8) rather than         |
//| reimplementing them - per the spec's own "do not copy" rule.      |
//|                                                                    |
//| STOP RULE (spec Section 4, mandatory): after this report is shown |
//| to the user, Step 3 (Elevated Spread Gate) must NOT be coded until|
//| the user confirms/edits InpNormalSpreadPts, InpElevatedSpreadPts  |
//| and the ATR override ratio. This file only ever prints a          |
//| PROPOSAL for those three numbers - it never sets them.            |
//+------------------------------------------------------------------+
#ifndef __GZ_SPREAD_HOUR_REPORT_MQH__
#define __GZ_SPREAD_HOUR_REPORT_MQH__

#include "GZ_CostEngine.mqh"

struct GZ_HourBucket
  {
   double vals[];
  };

class CGZSpreadHourReport
  {
public:
   //--- `label` is printed as-is (e.g. "DEVELOPMENT 2020-07-01..2024-12-31"
   //--- or "LEGACY_TOUCHED 2026") so the report is unambiguous about which
   //--- M1 slice it covers - this function itself does no date-range
   //--- slicing; the caller passes the already-sliced M1 array.
   string Build(const MqlRates &m1[], string label) const
     {
      int n = ArraySize(m1);
      string s = StringFormat("Step 1 - Hourly spread diagnostic [%s] (%d M1 bars, raw broker-hour, spread field in points)\n", label, n);
      if(n==0)
        {
         s += "  (no bars in this slice - nothing to report)\n";
         return s;
        }

      int counts[24];
      ArrayInitialize(counts, 0);
      for(int i=0;i<n;i++)
        {
         MqlDateTime dt;
         TimeToStruct(m1[i].time, dt);
         counts[dt.hour]++;
        }

      GZ_HourBucket buckets[24];
      for(int h=0;h<24;h++)
         ArrayResize(buckets[h].vals, counts[h]);

      int fillptr[24];
      ArrayInitialize(fillptr, 0);
      for(int i=0;i<n;i++)
        {
         MqlDateTime dt;
         TimeToStruct(m1[i].time, dt);
         int h = dt.hour;
         buckets[h].vals[fillptr[h]] = (double)m1[i].spread;
         fillptr[h]++;
        }

      s += GZCostPadR("HOUR",6) + GZCostPadL("n",10) + GZCostPadL("avg",9) + GZCostPadL("median",9) + GZCostPadL("p95",9) + GZCostPadL("zero%",8) + "\n";

      double all_medians[];
      ArrayResize(all_medians, 0);
      for(int h=0; h<24; h++)
        {
         int c = ArraySize(buckets[h].vals);
         if(c==0)
           {
            s += StringFormat("%s%s\n", GZCostPadR(IntegerToString(h),6), GZCostPadL("(no data)",44));
            continue;
           }
         double sum=0.0; int zeros=0;
         for(int k=0;k<c;k++) { sum += buckets[h].vals[k]; if(buckets[h].vals[k]<=0.0) zeros++; }
         double avg = sum/(double)c;
         double med = GZCostMedian(buckets[h].vals);
         double p95 = GZCostPercentile(buckets[h].vals, 95.0);
         s += GZCostPadR(IntegerToString(h),6) + GZCostPadL(IntegerToString(c),10) + GZCostPadL(DoubleToString(avg,1),9)
              + GZCostPadL(DoubleToString(med,1),9) + GZCostPadL(DoubleToString(p95,1),9)
              + GZCostPadL(DoubleToString(100.0*(double)zeros/(double)c,1),8) + "\n";
         int k2 = ArraySize(all_medians);
         ArrayResize(all_medians, k2+1);
         all_medians[k2] = med;
        }

      if(ArraySize(all_medians)>0)
        {
         double suggested_normal   = GZCostMedian(all_medians);
         double suggested_elevated = GZCostPercentile(all_medians, 90.0);
         s += "\nPROPOSAL ONLY (spec Section 4) - Step 3 is NOT coded until you confirm/edit these three numbers:\n";
         s += StringFormat("  InpNormalSpreadPts   proposal ~ %.1f  (median of the 24 per-hour medians above)\n", suggested_normal);
         s += StringFormat("  InpElevatedSpreadPts proposal ~ %.1f  (90th percentile of the 24 per-hour medians above)\n", suggested_elevated);
         s += "  ATR override ratio   proposal = 2.0  (spec's own suggested default in Section 6.1)\n";
        }
      return s;
     }
  };

#endif // __GZ_SPREAD_HOUR_REPORT_MQH__
