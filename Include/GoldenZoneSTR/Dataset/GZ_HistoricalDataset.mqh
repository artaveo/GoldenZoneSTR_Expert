//+------------------------------------------------------------------+
//| GZ_HistoricalDataset.mqh                                          |
//| GoldenZone STR - Phase 15.7 - Historical Data Expansion           |
//|                                                                    |
//| Load ONCE -> validate ONCE (Phase 1 validator, unchanged) ->       |
//| coverage tables -> serve any number of time slices.               |
//|                                                                    |
//| NO strategy logic. NO data is fabricated, repaired or dropped:     |
//| a missing stretch stays visible as a MISSING / PARTIAL month and   |
//| as a missing range. Slicing copies bars by TIME (binary search),   |
//| never by index, so M1 and M5 stay aligned by timestamp.            |
//|                                                                    |
//| DESIGN NOTES                                                       |
//| 1) Gap classification re-uses the Phase 1 rule EXACTLY: a gap      |
//|    larger than the bar spacing that contains a Saturday is         |
//|    EXPECTED (weekend/closure); any other gap is UNEXPECTED. One    |
//|    extra, separate flag is added: any gap >= 4 days (weekend or    |
//|    not) is a LONG_GAP, because the Saturday rule alone would hide |
//|    a whole missing trading week.                                   |
//| 2) M1/M5 compatibility per month: the number of distinct M5        |
//|    windows spanned by the month's M1 bars must equal the month's   |
//|    M5 bar count. A difference is reported as MISMATCH.             |
//| 3) Slice = COLD START. The slice is handed to the existing Phase   |
//|    2-15.5 engines exactly like a directly loaded range: swings,    |
//|    ATR, legs and setups all start empty at the slice start. No     |
//|    state from before the slice can leak in; nothing after the      |
//|    slice end can leak out.                                         |
//+------------------------------------------------------------------+
#ifndef __GZ_HISTORICAL_DATASET_MQH__
#define __GZ_HISTORICAL_DATASET_MQH__

#include "..\Core\GZ_Constants.mqh"
#include "..\Data\GZ_DatasetInfo.mqh"
#include "..\Data\GZ_DataProvider.mqh"
#include "..\Data\GZ_DataValidator.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"
#include "GZ_ResearchRange.mqh"

#define GZ_COV_LONG_GAP_SECONDS  345600   // 4 days
#define GZ_COV_MAX_MISSING_LIST  100

enum ENUM_GZ_COV_STATUS
  {
   GZ_COV_OK = 0,
   GZ_COV_OK_GAPS,     // minor unexpected gaps only (each < 4 days)
   GZ_COV_MISMATCH,    // M1 windows != M5 bars
   GZ_COV_PARTIAL,     // month begins/ends late inside the requested window, holds a >= 4 day gap, or is SPARSE (< 50% of the median month's M1 bars)
   GZ_COV_MISSING      // no bars at all
  };

string GZCovStatusToString(int s)
  {
   switch(s)
     {
      case GZ_COV_OK:       return "OK";
      case GZ_COV_OK_GAPS:  return "OK_GAPS";
      case GZ_COV_MISMATCH: return "MISMATCH";
      case GZ_COV_PARTIAL:  return "PARTIAL";
      case GZ_COV_MISSING:  return "MISSING";
     }
   return "UNKNOWN";
  }

string GZPadL(string s, int w) { while(StringLen(s)<w) s = " " + s; return s; }
string GZPadR(string s, int w) { while(StringLen(s)<w) s += " "; return s; }

//--- first index with a[i].time >= t (0..n). Array must be ascending.
int GZLowerBoundTime(const MqlRates &a[], datetime t)
  {
   int lo = 0, hi = ArraySize(a);
   while(lo<hi)
     {
      int mid = lo + (hi-lo)/2;
      if(a[mid].time < t) lo = mid+1; else hi = mid;
     }
   return lo;
  }

//--- first index with a[i].time > t (0..n)
int GZUpperBoundTime(const MqlRates &a[], datetime t)
  {
   int lo = 0, hi = ArraySize(a);
   while(lo<hi)
     {
      int mid = lo + (hi-lo)/2;
      if(a[mid].time <= t) lo = mid+1; else hi = mid;
     }
   return lo;
  }

//--- copy every bar with s <= time <= e (both inclusive) into out[]; returns the count.
int GZSliceRates(const MqlRates &src[], datetime s, datetime e, MqlRates &out[])
  {
   ArrayResize(out, 0);
   if(e < s || ArraySize(src)==0) return 0;
   int i0 = GZLowerBoundTime(src, s);
   int i1 = GZUpperBoundTime(src, e);
   int cnt = i1 - i0;
   if(cnt<=0) return 0;
   ArrayResize(out, cnt);
   ArrayCopy(out, src, 0, i0, cnt);
   return cnt;
  }

bool GZIsSaturdayDay(long day_number) { return (((day_number + 4) % 7) == 6); }

//--- Phase 1 rule (see CGZDataValidator::ContainsSaturday), reproduced so classification is identical.
bool GZGapContainsSaturday(datetime from, datetime to)
  {
   if(to <= from) return false;
   datetime cursor = from;
   int guard = 0;
   while(cursor < to && guard < 40)
     {
      if(GZIsSaturdayDay((long)cursor / GZ_SECONDS_PER_DAY)) return true;
      cursor += GZ_SECONDS_PER_DAY;
      guard++;
     }
   if(GZIsSaturdayDay((long)to / GZ_SECONDS_PER_DAY)) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Coverage tables by calendar month (years are rolled up on demand) |
//+------------------------------------------------------------------+
class CGZCoverage
  {
private:
   int       m_n;
   int       m_cache;
   datetime  m_req_start, m_req_end;

   int       m_key[];      // yyyymm
   datetime  m_ms[];       // first second of the month
   datetime  m_me[];       // last second of the month
   int       m_c1[];       // M1 bars
   int       m_c5[];       // M5 bars
   int       m_w1[];       // distinct M5 windows spanned by the month's M1 bars
   int       m_u1[];       // unexpected gaps, M1 (Phase 1 rule)
   int       m_u5[];       // unexpected gaps, M5
   int       m_k1[];       // expected (weekend/closure) gaps, M1
   int       m_k5[];       // expected gaps, M5
   int       m_lg1[];      // LONG gaps (>= 4 days, any kind), M1
   int       m_lg5[];      // LONG gaps, M5
   long      m_mg1[];      // largest unexpected gap in seconds, M1
   long      m_mg5[];      // largest unexpected gap in seconds, M5
   int       m_sp[];       // M1 bars with spread > 0
   int       m_tv[];       // M1 bars with tick volume > 0
   datetime  m_first1[];
   datetime  m_last1[];
   int       m_st[];

   datetime  m_miss_from[];
   datetime  m_miss_to[];
   string    m_miss_kind[];
   int       m_miss_total;

   int FindMonth(datetime t)
     {
      if(m_n==0) return -1;
      if(t < m_ms[0] || t > m_me[m_n-1]) return -1;
      if(m_cache>=0 && m_cache<m_n && t>=m_ms[m_cache] && t<=m_me[m_cache]) return m_cache;
      if(m_cache>=0 && m_cache+1<m_n && t>=m_ms[m_cache+1] && t<=m_me[m_cache+1]) { m_cache++; return m_cache; }
      int lo = 0, hi = m_n-1;
      while(lo<=hi)
        {
         int mid = (lo+hi)/2;
         if(t < m_ms[mid]) hi = mid-1;
         else if(t > m_me[mid]) lo = mid+1;
         else { m_cache = mid; return mid; }
        }
      return -1;
     }

   //--- same_month: both bars lie in month k. A LONG gap is charged to a month only when it lies
   //--- INSIDE that month; a gap spanning several months is already visible as MISSING months and as
   //--- late-start / early-end PARTIAL months, and charging it to the month that merely follows the
   //--- hole would mislabel a complete month.
   void ClassifyGap(datetime prev, datetime curr, long gap, int k, bool is_m1, bool same_month)
     {
      if(gap >= GZ_COV_LONG_GAP_SECONDS && same_month)
        {
         if(is_m1) m_lg1[k]++; else m_lg5[k]++;
        }
      if(GZGapContainsSaturday(prev, curr))
        {
         if(is_m1) m_k1[k]++; else m_k5[k]++;
        }
      else
        {
         if(is_m1) { m_u1[k]++; if(gap>m_mg1[k]) m_mg1[k] = gap; }
         else      { m_u5[k]++; if(gap>m_mg5[k]) m_mg5[k] = gap; }
        }
     }

   void AddMissing(datetime from, datetime to, string kind)
     {
      m_miss_total++;
      int n = ArraySize(m_miss_from);
      if(n >= GZ_COV_MAX_MISSING_LIST) return;
      ArrayResize(m_miss_from, n+1); ArrayResize(m_miss_to, n+1); ArrayResize(m_miss_kind, n+1);
      m_miss_from[n] = from; m_miss_to[n] = to; m_miss_kind[n] = kind;
     }

public:
                     CGZCoverage() { m_n = 0; m_cache = -1; m_req_start = 0; m_req_end = 0; m_miss_total = 0; }

   int               MonthCount() const { return m_n; }
   int               MissingRangeTotal() const { return m_miss_total; }

   void              Init(datetime req_start, datetime req_end)
     {
      m_req_start = req_start; m_req_end = req_end; m_n = 0; m_cache = -1; m_miss_total = 0;
      ArrayResize(m_miss_from,0); ArrayResize(m_miss_to,0); ArrayResize(m_miss_kind,0);
      if(req_start<=0 || req_end<req_start) return;

      MqlDateTime a; TimeToStruct(req_start, a);
      int y = a.year, m = a.mon;
      int count = 0;
      while(GZMakeTime(y,m,1,0,0,0) <= req_end && count < 2000)
        {
         count++;
         m++; if(m>12) { m = 1; y++; }
        }
      m_n = count;
      ArrayResize(m_key,m_n); ArrayResize(m_ms,m_n); ArrayResize(m_me,m_n);
      ArrayResize(m_c1,m_n); ArrayResize(m_c5,m_n); ArrayResize(m_w1,m_n);
      ArrayResize(m_u1,m_n); ArrayResize(m_u5,m_n); ArrayResize(m_k1,m_n); ArrayResize(m_k5,m_n);
      ArrayResize(m_lg1,m_n); ArrayResize(m_lg5,m_n); ArrayResize(m_mg1,m_n); ArrayResize(m_mg5,m_n);
      ArrayResize(m_sp,m_n); ArrayResize(m_tv,m_n);
      ArrayResize(m_first1,m_n); ArrayResize(m_last1,m_n); ArrayResize(m_st,m_n);

      TimeToStruct(req_start, a);
      y = a.year; m = a.mon;
      for(int i=0;i<m_n;i++)
        {
         m_key[i] = y*100 + m;
         m_ms[i]  = GZMakeTime(y,m,1,0,0,0);
         int ny = (m==12) ? y+1 : y;
         int nm = (m==12) ? 1 : m+1;
         m_me[i]  = (datetime)((long)GZMakeTime(ny,nm,1,0,0,0) - 1);
         m_c1[i]=0; m_c5[i]=0; m_w1[i]=0; m_u1[i]=0; m_u5[i]=0; m_k1[i]=0; m_k5[i]=0;
         m_lg1[i]=0; m_lg5[i]=0; m_mg1[i]=0; m_mg5[i]=0; m_sp[i]=0; m_tv[i]=0;
         m_first1[i]=0; m_last1[i]=0; m_st[i]=GZ_COV_OK;
         m = m+1; if(m>12) { m = 1; y++; }
        }
     }

   void              ScanM1(const MqlRates &a[])
     {
      int n = ArraySize(a);
      long last_window = -1;
      datetime prev = 0;
      int prev_k = -1;
      for(int i=0;i<n;i++)
        {
         datetime t = a[i].time;
         int k = FindMonth(t);
         if(k>=0)
           {
            m_c1[k]++;
            if(a[i].spread>0) m_sp[k]++;
            if(a[i].tick_volume>0) m_tv[k]++;
            if(m_first1[k]==0) m_first1[k] = t;
            m_last1[k] = t;
            long w = (long)t / GZ_M5_SECONDS;
            if(w != last_window) { m_w1[k]++; last_window = w; }
            if(i>0)
              {
               long gap = (long)(t - prev);
               if(gap > GZ_SPACING_M1_SECONDS) ClassifyGap(prev, t, gap, k, true, (prev_k==k));
              }
           }
         prev = t;
         prev_k = k;
        }
     }

   void              ScanM5(const MqlRates &a[])
     {
      int n = ArraySize(a);
      datetime prev = 0;
      int prev_k = -1;
      for(int i=0;i<n;i++)
        {
         datetime t = a[i].time;
         int k = FindMonth(t);
         if(k>=0)
           {
            m_c5[k]++;
            if(i>0)
              {
               long gap = (long)(t - prev);
               if(gap > GZ_SPACING_M5_SECONDS) ClassifyGap(prev, t, gap, k, false, (prev_k==k));
              }
           }
         prev = t;
         prev_k = k;
        }
     }

   //--- head / tail / internal missing ranges (M1 timeline; gaps >= 4 days) --
   void              ScanMissing(const MqlRates &m1[])
     {
      int n = ArraySize(m1);
      m_miss_total = 0;
      ArrayResize(m_miss_from,0); ArrayResize(m_miss_to,0); ArrayResize(m_miss_kind,0);
      if(n==0) { AddMissing(m_req_start, m_req_end, "ALL"); return; }
      if((long)(m1[0].time - m_req_start) >= GZ_COV_LONG_GAP_SECONDS) AddMissing(m_req_start, m1[0].time, "HEAD");
      for(int i=1;i<n;i++)
         if((long)(m1[i].time - m1[i-1].time) >= GZ_COV_LONG_GAP_SECONDS)
            AddMissing(m1[i-1].time, m1[i].time, "INTERNAL");
      if((long)(m_req_end - m1[n-1].time) >= GZ_COV_LONG_GAP_SECONDS) AddMissing(m1[n-1].time, m_req_end, "TAIL");
     }

   //--- statuses (call once after both scans) ----------------------------
   void              Finalize()
     {
      long tol = GZ_COV_LONG_GAP_SECONDS;

      //--- DENSITY reference: median M1 bar count of the months that hold any bars. A month whose M1 count is
      //--- below 50% of that median (scaled by the fraction of the month inside the requested range) is SPARSE
      //--- and reported PARTIAL, even when no single gap reaches 4 days (e.g. a history that only holds
      //--- hourly-like bars for that period). Without this rule such a month would look like OK_GAPS.
      double median = 0.0;
      {
       int tmp[];
       int cnt = 0;
       for(int i=0;i<m_n;i++) if(m_c1[i]>0) cnt++;
       if(cnt>0)
         {
          ArrayResize(tmp, cnt);
          int k = 0;
          for(int i=0;i<m_n;i++) if(m_c1[i]>0) { tmp[k] = m_c1[i]; k++; }
          ArraySort(tmp);
          if(cnt%2==1) median = (double)tmp[cnt/2];
          else         median = 0.5*((double)tmp[cnt/2-1] + (double)tmp[cnt/2]);
         }
      }

      for(int i=0;i<m_n;i++)
        {
         datetime ws = (m_ms[i] > m_req_start) ? m_ms[i] : m_req_start;
         datetime we = (m_me[i] < m_req_end)   ? m_me[i] : m_req_end;
         int st;
         if(m_c1[i]==0 && m_c5[i]==0)
            st = GZ_COV_MISSING;
         else if(m_w1[i] != m_c5[i])
            st = GZ_COV_MISMATCH;
         else if(m_c1[i]==0 ||
                 (long)(m_first1[i]-ws) >= tol || (long)(we-m_last1[i]) >= tol ||
                 m_lg1[i]>0 || m_lg5[i]>0 ||
                 (double)m_c1[i] < 0.5*median*((double)((long)(we-ws)+1)/(double)((long)(m_me[i]-m_ms[i])+1)))
            st = GZ_COV_PARTIAL;
         else if(m_u1[i]>0 || m_u5[i]>0)
            st = GZ_COV_OK_GAPS;
         else
            st = GZ_COV_OK;
         m_st[i] = st;
        }
     }

   //--- accessors --------------------------------------------------------
   int               MonthKey(int i) const { return m_key[i]; }
   int               MonthStatus(int i) const { return m_st[i]; }
   int               MonthM1(int i) const { return m_c1[i]; }
   int               MonthM5(int i) const { return m_c5[i]; }
   int               MonthM5Windows(int i) const { return m_w1[i]; }
   int               MonthUnexpectedM1(int i) const { return m_u1[i]; }
   int               MonthUnexpectedM5(int i) const { return m_u5[i]; }
   int               MonthExpectedM1(int i) const { return m_k1[i]; }
   int               MonthExpectedM5(int i) const { return m_k5[i]; }
   int               MonthLongGapsM1(int i) const { return m_lg1[i]; }

   int               CountStatus(int status) const
     {
      int c = 0;
      for(int i=0;i<m_n;i++) if(m_st[i]==status) c++;
      return c;
     }

   int               WorstStatus() const
     {
      int w = GZ_COV_OK;
      for(int i=0;i<m_n;i++) if(m_st[i]>w) w = m_st[i];
      return w;
     }

   long              TotalM1() const { long s=0; for(int i=0;i<m_n;i++) s += m_c1[i]; return s; }
   long              TotalM5() const { long s=0; for(int i=0;i<m_n;i++) s += m_c5[i]; return s; }
   long              TotalUnexpectedM1() const { long s=0; for(int i=0;i<m_n;i++) s += m_u1[i]; return s; }
   long              TotalUnexpectedM5() const { long s=0; for(int i=0;i<m_n;i++) s += m_u5[i]; return s; }
   long              TotalExpectedM1() const { long s=0; for(int i=0;i<m_n;i++) s += m_k1[i]; return s; }
   long              TotalExpectedM5() const { long s=0; for(int i=0;i<m_n;i++) s += m_k5[i]; return s; }
   long              TotalLongGapsM1() const { long s=0; for(int i=0;i<m_n;i++) s += m_lg1[i]; return s; }

   //--- Number of missing ranges NOT explained by ONE user-accepted, documented hole [acc_from, acc_to]
   //--- (a range counts as accepted when it lies inside that window, +/- 1 hour). Ranges beyond the
   //--- stored list cap are counted as unexplained (conservative).
   int               MissingRangesNotAccepted(datetime acc_from, datetime acc_to) const
     {
      int accepted = 0;
      int n = ArraySize(m_miss_from);
      for(int i=0;i<n;i++)
         if(m_miss_kind[i]=="INTERNAL" && (long)m_miss_from[i] >= (long)acc_from-3600 && (long)m_miss_to[i] <= (long)acc_to+3600)
            accepted++;
      int unexplained = m_miss_total - accepted;
      if(unexplained<0) unexplained = 0;
      return unexplained;
     }

   string            MissingRangesText() const
     {
      string s = "";
      int n = ArraySize(m_miss_from);
      for(int i=0;i<n;i++)
         s += StringFormat("  %s: %s -> %s (%.1f days)\n", m_miss_kind[i],
                           TimeToString(m_miss_from[i], TIME_DATE|TIME_MINUTES), TimeToString(m_miss_to[i], TIME_DATE|TIME_MINUTES),
                           (double)((long)(m_miss_to[i]-m_miss_from[i]))/86400.0);
      if(m_miss_total > n) s += StringFormat("  ... %d more not listed\n", m_miss_total-n);
      if(m_miss_total==0) s = "  none (no gap >= 4 days, no missing head/tail)\n";
      return s;
     }

   //--- Yearly rollup ------------------------------------------------------
   string            BuildYearTable() const
     {
      string s = GZPadR("YEAR",6)+GZPadL("M1",10)+GZPadL("M5",9)+GZPadL("months",7)+GZPadL("OK",4)+GZPadL("GAPS",5)+GZPadL("MISM",5)+GZPadL("PART",5)+GZPadL("MISS",5)
                 +GZPadL("unexpM1",8)+GZPadL("expM1",7)+"  STATUS\n";
      int i = 0;
      while(i<m_n)
        {
         int y = m_key[i]/100;
         long c1=0, c5=0, u1=0, k1=0;
         int months=0, nok=0, ngap=0, nmis=0, npar=0, nmiss=0, worst=GZ_COV_OK;
         while(i<m_n && m_key[i]/100==y)
           {
            c1 += m_c1[i]; c5 += m_c5[i]; u1 += m_u1[i]; k1 += m_k1[i];
            months++;
            switch(m_st[i])
              {
               case GZ_COV_OK: nok++; break;
               case GZ_COV_OK_GAPS: ngap++; break;
               case GZ_COV_MISMATCH: nmis++; break;
               case GZ_COV_PARTIAL: npar++; break;
               case GZ_COV_MISSING: nmiss++; break;
              }
            if(m_st[i]>worst) worst = m_st[i];
            i++;
           }
         s += GZPadR(IntegerToString(y),6)+GZPadL(IntegerToString((int)c1),10)+GZPadL(IntegerToString((int)c5),9)+GZPadL(IntegerToString(months),7)
              +GZPadL(IntegerToString(nok),4)+GZPadL(IntegerToString(ngap),5)+GZPadL(IntegerToString(nmis),5)+GZPadL(IntegerToString(npar),5)+GZPadL(IntegerToString(nmiss),5)
              +GZPadL(IntegerToString((int)u1),8)+GZPadL(IntegerToString((int)k1),7)+"  "+GZCovStatusToString(worst)+"\n";
        }
      return s;
     }

   //--- Monthly table -------------------------------------------------------
   string            BuildMonthTable() const
     {
      string s = GZPadR("MONTH",9)+GZPadL("M1",9)+GZPadL("M5",8)+GZPadL("M5win",8)+GZPadL("unexpM1",8)+GZPadL("unexpM5",8)+GZPadL("expM1",6)
                 +GZPadL("long",5)+GZPadL("maxGap_h",9)+GZPadL("spread%",8)+GZPadL("tickvol%",9)+"  STATUS\n";
      for(int i=0;i<m_n;i++)
        {
         double sp = (m_c1[i]>0) ? 100.0*m_sp[i]/m_c1[i] : 0.0;
         double tv = (m_c1[i]>0) ? 100.0*m_tv[i]/m_c1[i] : 0.0;
         s += GZPadR(StringFormat("%04d-%02d", m_key[i]/100, m_key[i]%100),9)+GZPadL(IntegerToString(m_c1[i]),9)+GZPadL(IntegerToString(m_c5[i]),8)
              +GZPadL(IntegerToString(m_w1[i]),8)+GZPadL(IntegerToString(m_u1[i]),8)+GZPadL(IntegerToString(m_u5[i]),8)+GZPadL(IntegerToString(m_k1[i]),6)
              +GZPadL(IntegerToString(m_lg1[i]),5)+GZPadL(DoubleToString((double)m_mg1[i]/3600.0,1),9)+GZPadL(DoubleToString(sp,1),8)+GZPadL(DoubleToString(tv,1),9)
              +"  "+GZCovStatusToString(m_st[i])+"\n";
        }
      return s;
     }

   string            BuildCsv() const
     {
      string s = "month,m1_bars,m5_bars,m5_windows_from_m1,unexpected_gaps_m1,unexpected_gaps_m5,expected_gaps_m1,expected_gaps_m5,long_gaps_m1,long_gaps_m5,max_unexpected_gap_m1_sec,max_unexpected_gap_m5_sec,m1_spread_bars,m1_tickvol_bars,status\n";
      for(int i=0;i<m_n;i++)
         s += StringFormat("%04d-%02d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s\n", m_key[i]/100, m_key[i]%100, m_c1[i], m_c5[i], m_w1[i],
                           m_u1[i], m_u5[i], m_k1[i], m_k5[i], m_lg1[i], m_lg5[i], (int)m_mg1[i], (int)m_mg5[i], m_sp[i], m_tv[i], GZCovStatusToString(m_st[i]));
      return s;
     }
  };

//+------------------------------------------------------------------+
//| The reusable historical dataset                                   |
//+------------------------------------------------------------------+
class CGZHistoricalDataset
  {
private:
   CGZLogger      *m_logger;
   string          m_symbol;
   MqlRates        m_m1[];
   MqlRates        m_m5[];
   int             m_n1, m_n5;
   datetime        m_req_start, m_req_end;
   CGZDatasetInfo  m_info1;
   CGZDatasetInfo  m_info5;
   CGZCoverage     m_cov;
   bool            m_loaded;
   bool            m_released;
   datetime        m_term_first_m1, m_term_first_m5;
   int             m_slices_served;

   void Process(CGZDataProvider *provider, CGZDataValidator *validator, int broker_off, bool off_known)
     {
      //--- M1 --------------------------------------------------------------
      m_info1.Clear();
      m_info1.symbol = m_symbol; m_info1.execution_timeframe = PERIOD_M1;
      m_info1.start_timestamp = m_req_start; m_info1.end_timestamp = m_req_end;
      m_info1.broker_utc_offset_hours = broker_off;
      m_info1.broker_tz_status = off_known ? GZ_TZ_KNOWN : GZ_TZ_UNKNOWN;
      m_info1.total_bars = m_n1;
      if(m_n1>0)
        {
         m_info1.first_bar_time = m_m1[0].time; m_info1.last_bar_time = m_m1[m_n1-1].time;
         validator.ValidateOHLC(m_m1, m_info1);
         validator.ValidateTimestamps(m_m1, GZ_SPACING_M1_SECONDS, m_info1);
         if(provider!=NULL)
           {
            m_info1.spread_availability      = provider.SpreadAvailability(m_m1);
            m_info1.tick_volume_availability = provider.TickVolumeAvailability(m_m1);
            m_info1.real_volume_availability = provider.RealVolumeAvailability(m_m1);
           }
        }
      else
         m_info1.AddError("No M1 data returned for the requested historical range.");
      m_info1.Finalize();

      //--- M5 --------------------------------------------------------------
      m_info5.Clear();
      m_info5.symbol = m_symbol; m_info5.structure_timeframe = PERIOD_M5;
      m_info5.start_timestamp = m_req_start; m_info5.end_timestamp = m_req_end;
      m_info5.broker_utc_offset_hours = broker_off;
      m_info5.broker_tz_status = off_known ? GZ_TZ_KNOWN : GZ_TZ_UNKNOWN;
      m_info5.total_bars = m_n5;
      if(m_n5>0)
        {
         m_info5.first_bar_time = m_m5[0].time; m_info5.last_bar_time = m_m5[m_n5-1].time;
         validator.ValidateOHLC(m_m5, m_info5);
         validator.ValidateTimestamps(m_m5, GZ_SPACING_M5_SECONDS, m_info5);
         if(provider!=NULL)
           {
            m_info5.spread_availability      = provider.SpreadAvailability(m_m5);
            m_info5.tick_volume_availability = provider.TickVolumeAvailability(m_m5);
            m_info5.real_volume_availability = provider.RealVolumeAvailability(m_m5);
           }
        }
      else
         m_info5.AddError("No M5 data returned for the requested historical range.");
      m_info5.Finalize();

      //--- coverage (one pass per timeframe) --------------------------------
      m_cov.Init(m_req_start, m_req_end);
      m_cov.ScanM1(m_m1);
      m_cov.ScanM5(m_m5);
      m_cov.ScanMissing(m_m1);
      m_cov.Finalize();

      m_loaded = (m_n1>0 && m_n5>0);
      m_released = false;
     }

public:
                     CGZHistoricalDataset(CGZLogger *logger=NULL)
     {
      m_logger = logger; m_symbol = ""; m_n1 = 0; m_n5 = 0; m_req_start = 0; m_req_end = 0;
      m_loaded = false; m_released = false; m_term_first_m1 = 0; m_term_first_m5 = 0; m_slices_served = 0;
     }

   bool              IsLoaded() const { return m_loaded; }
   bool              BarsReleased() const { return m_released; }
   int               M1Count() const { return m_n1; }
   int               M5Count() const { return m_n5; }
   datetime          RequestedStart() const { return m_req_start; }
   datetime          RequestedEnd() const { return m_req_end; }
   datetime          AvailableStart() const { return (m_n1>0) ? m_info1.first_bar_time : 0; }
   datetime          AvailableEnd() const { return (m_n1>0) ? m_info1.last_bar_time : 0; }
   datetime          AvailableStartM5() const { return (m_n5>0) ? m_info5.first_bar_time : 0; }
   datetime          AvailableEndM5() const { return (m_n5>0) ? m_info5.last_bar_time : 0; }
   ENUM_GZ_VALIDATION_STATUS M1Status() const { return m_info1.validation_status; }
   ENUM_GZ_VALIDATION_STATUS M5Status() const { return m_info5.validation_status; }
   int               SlicesServed() const { return m_slices_served; }
   CGZCoverage      *Coverage() { return GetPointer(m_cov); }

   //--- Production path: ONE CopyRates per timeframe for the whole requested range.
   bool              Load(CGZDataProvider *provider, CGZDataValidator *validator, string symbol,
                          datetime req_start, datetime req_end, int broker_off, bool off_known)
     {
      m_symbol = symbol; m_req_start = req_start; m_req_end = req_end;
      m_n1 = provider.LoadM1(symbol, req_start, req_end, m_m1);
      m_n5 = provider.LoadM5(symbol, req_start, req_end, m_m5);
      m_term_first_m1 = (datetime)SeriesInfoInteger(symbol, PERIOD_M1, SERIES_TERMINAL_FIRSTDATE);
      m_term_first_m5 = (datetime)SeriesInfoInteger(symbol, PERIOD_M5, SERIES_TERMINAL_FIRSTDATE);
      Process(provider, validator, broker_off, off_known);
      if(m_logger!=NULL)
         m_logger.Info("Dataset", StringFormat("Historical dataset loaded once: M1=%d M5=%d bars, validation M1=%s M5=%s, coverage worst status=%s",
                       m_n1, m_n5, m_info1.StatusToString(), m_info5.StatusToString(), GZCovStatusToString(m_cov.WorstStatus())));
      return m_loaded;
     }

   //--- Test path: same processing, arrays supplied by the caller (no CopyRates).
   bool              Attach(const MqlRates &m1[], const MqlRates &m5[], string symbol,
                            datetime req_start, datetime req_end, CGZDataValidator *validator)
     {
      m_symbol = symbol; m_req_start = req_start; m_req_end = req_end;
      m_n1 = ArraySize(m1); m_n5 = ArraySize(m5);
      ArrayResize(m_m1, 0); ArrayResize(m_m5, 0);
      if(m_n1>0) ArrayCopy(m_m1, m1);
      if(m_n5>0) ArrayCopy(m_m5, m5);
      m_term_first_m1 = 0; m_term_first_m5 = 0;
      Process(NULL, validator, 0, false);
      return m_loaded;
     }

   //--- The ONLY way research data leaves the dataset: a time slice (cold start, see header note 3).
   //--- Copies; the dataset's own arrays are never modified. Returns the M5 bar count.
   int               Slice(const GZ_ResearchRange &r, MqlRates &m1[], MqlRates &m5[])
     {
      ArrayResize(m1, 0); ArrayResize(m5, 0);
      if(!m_loaded || m_released || r.status!=GZ_RSTATUS_OK) return 0;
      GZSliceRates(m_m1, r.eff_start, r.eff_end, m1);
      int c5 = GZSliceRates(m_m5, r.eff_start, r.eff_end, m5);
      m_slices_served++;
      return c5;
     }

   //--- Free the bar arrays once every slice needed has been taken (coverage/validation stay).
   void              ReleaseBars()
     {
      ArrayFree(m_m1); ArrayFree(m_m5);
      m_released = true;
     }

   //--- read-only checksum of the stored bars (tests: "slicing never mutates the dataset")
   double            Checksum() const
     {
      double s = 0.0;
      for(int i=0;i<m_n1;i++) s += (double)m_m1[i].time*0.000001 + m_m1[i].close;
      for(int i=0;i<m_n5;i++) s += (double)m_m5[i].time*0.000001 + m_m5[i].close;
      return s;
     }

   //--- Requested / Available / Validated / Missing ---------------------------------
   string            BuildRangeSummary() const
     {
      string s = "";
      s += StringFormat("Symbol: %s\n", m_symbol);
      s += StringFormat("REQUESTED range : %s -> %s\n", TimeToString(m_req_start, TIME_DATE|TIME_MINUTES), TimeToString(m_req_end, TIME_DATE|TIME_MINUTES));
      if(m_n1>0)
         s += StringFormat("AVAILABLE range : M1 %s -> %s | M5 %s -> %s\n",
                           TimeToString(m_info1.first_bar_time, TIME_DATE|TIME_MINUTES), TimeToString(m_info1.last_bar_time, TIME_DATE|TIME_MINUTES),
                           (m_n5>0)?TimeToString(m_info5.first_bar_time, TIME_DATE|TIME_MINUTES):"none", (m_n5>0)?TimeToString(m_info5.last_bar_time, TIME_DATE|TIME_MINUTES):"none");
      else
         s += "AVAILABLE range : NONE (no M1 bars returned)\n";
      bool invalid = (m_info1.validation_status==GZ_VAL_INVALID) || (m_info5.validation_status==GZ_VAL_INVALID);
      if(!m_loaded)
         s += "VALIDATED range : NONE (dataset not loaded)\n";
      else if(invalid)
         s += "VALIDATED range : NONE (Phase 1 validation returned INVALID - see errors)\n";
      else
         s += StringFormat("VALIDATED range : %s -> %s (%s)\n", TimeToString(m_info1.first_bar_time, TIME_DATE|TIME_MINUTES), TimeToString(m_info1.last_bar_time, TIME_DATE|TIME_MINUTES),
                           (m_info1.validation_status==GZ_VAL_VALID && m_info5.validation_status==GZ_VAL_VALID) ? "VALID" : "VALID_WITH_WARNINGS");
      s += "MISSING ranges (head/tail beyond tolerance, or an internal gap >= 4 days):\n" + m_cov.MissingRangesText();
      s += StringFormat("Terminal reports first available bar (SERIES_TERMINAL_FIRSTDATE): M1 %s | M5 %s\n",
                        TimeToString(m_term_first_m1, TIME_DATE|TIME_MINUTES), TimeToString(m_term_first_m5, TIME_DATE|TIME_MINUTES));
      return s;
     }

   string            BuildInfoLine(bool is_m1)
     {
      CGZDatasetInfo *ip = GetPointer(m_info5);
      if(is_m1) ip = GetPointer(m_info1);
      return StringFormat("%s: bars=%d first=%s last=%s | unexpected_gaps=%d expected_gaps=%d duplicates=%d invalid_ohlc=%d ordering_errors=%d | spread=%s tick_volume=%s real_volume=%s | status=%s (warnings=%d errors=%d)",
                          is_m1?"M1":"M5", ip.total_bars, TimeToString(ip.first_bar_time, TIME_DATE|TIME_MINUTES), TimeToString(ip.last_bar_time, TIME_DATE|TIME_MINUTES),
                          ip.missing_bar_count, ip.expected_gap_count, ip.duplicate_count, ip.invalid_ohlc_count, ip.timestamp_error_count,
                          GZAvailToString(ip.spread_availability), GZAvailToString(ip.tick_volume_availability), GZAvailToString(ip.real_volume_availability),
                          ip.StatusToString(), ArraySize(ip.warnings), ArraySize(ip.errors));
     }

   string            GZAvailToString(ENUM_GZ_AVAILABILITY a) const
     {
      if(a==GZ_AVAIL_AVAILABLE) return "AVAILABLE";
      if(a==GZ_AVAIL_NOT_AVAILABLE) return "NOT_AVAILABLE";
      return "UNKNOWN";
     }
  };

#endif // __GZ_HISTORICAL_DATASET_MQH__
