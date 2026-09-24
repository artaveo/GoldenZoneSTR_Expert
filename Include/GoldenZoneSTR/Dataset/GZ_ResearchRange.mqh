//+------------------------------------------------------------------+
//| GZ_ResearchRange.mqh                                              |
//| GoldenZone STR - Phase 15.7 - Historical Data Expansion           |
//| Research date-range abstraction                                    |
//|                                                                    |
//| Every selection (full dataset / year / month / day / week /        |
//| custom / the legacy Development range) resolves to ONE plain       |
//| struct: [eff_start, eff_end], both ends INCLUSIVE bar-open times.  |
//| There is no year- or month-specific code path anywhere else.       |
//|                                                                    |
//| DESIGN NOTES                                                       |
//| 1) INCLUSIVE ends, same as CopyRates(start,stop): a bar belongs to |
//|    the range when start <= bar.time <= end.                        |
//| 2) M5 ALIGNMENT (no boundary leakage). For every kind except       |
//|    LEGACY_DEV the effective start is rounded UP to an M5 window    |
//|    boundary and the effective end is rounded DOWN to the last M1   |
//|    minute of a COMPLETE M5 window (..:x4 / ..:x9). So the slice    |
//|    never contains an M5 bar whose OHLC was built partly from M1    |
//|    minutes after the range end, and never an M1 minute whose M5    |
//|    window opened before the range start. Requested and effective   |
//|    values are both stored and both reported.                       |
//| 3) LEGACY_DEV is the exact InpRangeStart..InpRangeEnd range of     |
//|    Phases 1-15.5, NOT aligned, so it reproduces the old direct     |
//|    CopyRates arrays bar for bar (regression requirement).          |
//| 4) PARTITION. The Development / Final-OOS boundary of Phase 15     |
//|    (InpOosStart, 2026.06.13 00:00) is preserved. A range whose end |
//|    is beyond that boundary is NOT development-eligible: the data   |
//|    stays sliceable and reportable, but research execution refuses  |
//|    it (never shifted, never silently clipped).                     |
//+------------------------------------------------------------------+
#ifndef __GZ_RESEARCH_RANGE_MQH__
#define __GZ_RESEARCH_RANGE_MQH__

#include "..\Core\GZ_Constants.mqh"

#define GZ_M5_SECONDS 300

enum ENUM_GZ_RANGE_KIND
  {
   GZ_RANGE_LEGACY_DEV = 0,   // LEGACY_DEV: InpRangeStart..InpRangeEnd exactly as Phases 1-15.5
   GZ_RANGE_FULL_DEV,         // FULL_DEV: InpHistStart up to the legacy Development/OOS boundary
   GZ_RANGE_FULL_DATASET,     // FULL_DATASET: InpHistStart..InpHistEnd (coverage/slicing; research refuses it)
   GZ_RANGE_YEAR,             // YEAR: InpResYear
   GZ_RANGE_MONTH,            // MONTH: InpResYear + InpResMonth
   GZ_RANGE_DAY,              // DAY: InpResYear + InpResMonth + InpResDay
   GZ_RANGE_WEEK,             // WEEK: 7 days starting at the date of InpResCustomStart
   GZ_RANGE_CUSTOM            // CUSTOM: InpResCustomStart..InpResCustomEnd (end inclusive)
  };

enum ENUM_GZ_RSTATUS
  {
   GZ_RSTATUS_OK = 0,
   GZ_RSTATUS_INVALID_INPUT,
   GZ_RSTATUS_INVALID_ORDER
  };

enum ENUM_GZ_PARTITION
  {
   GZ_PART_DEVELOPMENT_ELIGIBLE = 0,  // eff_end <= legacy OOS start
   GZ_PART_CROSSES_LEGACY_OOS,        // starts before the boundary, ends after it
   GZ_PART_LEGACY_OOS_ONLY            // starts at/after the boundary
  };

string GZRangeKindToString(ENUM_GZ_RANGE_KIND k)
  {
   switch(k)
     {
      case GZ_RANGE_LEGACY_DEV:   return "LEGACY_DEV";
      case GZ_RANGE_FULL_DEV:     return "FULL_DEV";
      case GZ_RANGE_FULL_DATASET: return "FULL_DATASET";
      case GZ_RANGE_YEAR:         return "YEAR";
      case GZ_RANGE_MONTH:        return "MONTH";
      case GZ_RANGE_DAY:          return "DAY";
      case GZ_RANGE_WEEK:         return "WEEK";
      case GZ_RANGE_CUSTOM:       return "CUSTOM";
     }
   return "UNKNOWN";
  }

string GZPartitionToString(ENUM_GZ_PARTITION p)
  {
   switch(p)
     {
      case GZ_PART_DEVELOPMENT_ELIGIBLE: return "DEVELOPMENT_ELIGIBLE";
      case GZ_PART_CROSSES_LEGACY_OOS:   return "CROSSES_LEGACY_OOS_BOUNDARY";
      case GZ_PART_LEGACY_OOS_ONLY:      return "LEGACY_OOS_ONLY";
     }
   return "UNKNOWN";
  }

string GZRStatusToString(ENUM_GZ_RSTATUS s)
  {
   switch(s)
     {
      case GZ_RSTATUS_OK:            return "OK";
      case GZ_RSTATUS_INVALID_INPUT: return "INVALID_INPUT";
      case GZ_RSTATUS_INVALID_ORDER: return "INVALID_ORDER";
     }
   return "UNKNOWN";
  }

//--- calendar helpers (pure integer math; no machine-local timezone) -----
bool GZIsLeapYear(int y) { return ((y%4==0 && y%100!=0) || (y%400==0)); }

int GZDaysInMonth(int y, int m)
  {
   switch(m)
     {
      case 1: case 3: case 5: case 7: case 8: case 10: case 12: return 31;
      case 4: case 6: case 9: case 11: return 30;
      case 2: return GZIsLeapYear(y) ? 29 : 28;
     }
   return 0;
  }

datetime GZMakeTime(int y, int mo, int d, int h, int mi, int s)
  {
   MqlDateTime dt;
   dt.year = y; dt.mon = mo; dt.day = d; dt.hour = h; dt.min = mi; dt.sec = s;
   dt.day_of_week = 0; dt.day_of_year = 0;
   return StructToTime(dt);
  }

//--- round UP to the next M5 window boundary (identity if already aligned)
datetime GZSnapStartUp(datetime t)
  {
   long s = (long)t;
   long r = s % GZ_M5_SECONDS;
   if(r==0) return t;
   return (datetime)(s + GZ_M5_SECONDS - r);
  }

//--- round DOWN to the last M1 minute of a COMPLETE M5 window at or before t
//--- (window = 5 minutes; its last minute is open+240s).
datetime GZSnapEndDown(datetime t)
  {
   long s = (long)t;
   long w = (s + 60) / GZ_M5_SECONDS;
   return (datetime)(w*GZ_M5_SECONDS - 60);
  }

struct GZ_ResearchRange
  {
   ENUM_GZ_RANGE_KIND kind;
   string             label;
   datetime           req_start;
   datetime           req_end;
   datetime           eff_start;
   datetime           eff_end;
   bool               m5_aligned;
   ENUM_GZ_RSTATUS    status;
   string             note;

   void Clear()
     {
      kind = GZ_RANGE_CUSTOM; label = ""; req_start = 0; req_end = 0; eff_start = 0; eff_end = 0;
      m5_aligned = false; status = GZ_RSTATUS_INVALID_INPUT; note = "";
     }
  };

//--- common finisher: validates order, applies (or skips) M5 alignment.
void GZRangeFinalize(GZ_ResearchRange &r, bool align)
  {
   r.m5_aligned = align;
   if(r.req_start<=0 || r.req_end<=0)
     {
      r.status = GZ_RSTATUS_INVALID_INPUT;
      r.note = "start/end not set or not a valid date";
      r.eff_start = 0; r.eff_end = 0;
      return;
     }
   if(r.req_end < r.req_start)
     {
      r.status = GZ_RSTATUS_INVALID_ORDER;
      r.note = "end is before start";
      r.eff_start = 0; r.eff_end = 0;
      return;
     }
   if(align)
     {
      r.eff_start = GZSnapStartUp(r.req_start);
      r.eff_end   = GZSnapEndDown(r.req_end);
     }
   else
     {
      r.eff_start = r.req_start;
      r.eff_end   = r.req_end;
     }
   if(r.eff_end < r.eff_start)
     {
      r.status = GZ_RSTATUS_INVALID_ORDER;
      r.note = "range holds no complete M5 window after alignment";
      return;
     }
   r.status = GZ_RSTATUS_OK;
   r.note = "";
  }

void GZRangeLegacyDev(datetime start, datetime end, GZ_ResearchRange &r)
  {
   r.Clear();
   r.kind = GZ_RANGE_LEGACY_DEV;
   r.label = "LEGACYDEV";
   r.req_start = start; r.req_end = end;
   GZRangeFinalize(r, false);
  }

void GZRangeCustom(datetime start, datetime end, GZ_ResearchRange &r)
  {
   r.Clear();
   r.kind = GZ_RANGE_CUSTOM;
   r.req_start = start; r.req_end = end;
   r.label = StringFormat("CUSTOM_%s_%s", TimeToString(start, TIME_DATE), TimeToString(end, TIME_DATE));
   GZRangeFinalize(r, true);
  }

void GZRangeFullDataset(datetime hist_start, datetime hist_end, GZ_ResearchRange &r)
  {
   r.Clear();
   r.kind = GZ_RANGE_FULL_DATASET;
   r.label = "FULLDATASET";
   r.req_start = hist_start; r.req_end = hist_end;
   GZRangeFinalize(r, true);
  }

//--- development side of the legacy boundary: hist_start .. (boundary - 1 second), so the
//--- bar stamped exactly at the boundary (which belongs to the old OOS side) is excluded.
void GZRangeFullDev(datetime hist_start, datetime legacy_oos_start, GZ_ResearchRange &r)
  {
   r.Clear();
   r.kind = GZ_RANGE_FULL_DEV;
   r.label = "FULLDEV";
   r.req_start = hist_start;
   r.req_end   = (datetime)((long)legacy_oos_start - 1);
   GZRangeFinalize(r, true);
  }

void GZRangeYear(int y, GZ_ResearchRange &r)
  {
   r.Clear();
   r.kind = GZ_RANGE_YEAR;
   if(y<1971 || y>2100) { r.status = GZ_RSTATUS_INVALID_INPUT; r.note = "year out of range"; r.label = "YEAR_INVALID"; return; }
   r.label = StringFormat("Y%04d", y);
   r.req_start = GZMakeTime(y,1,1,0,0,0);
   r.req_end   = (datetime)((long)GZMakeTime(y+1,1,1,0,0,0) - 1);
   GZRangeFinalize(r, true);
  }

void GZRangeMonth(int y, int m, GZ_ResearchRange &r)
  {
   r.Clear();
   r.kind = GZ_RANGE_MONTH;
   if(y<1971 || y>2100 || m<1 || m>12) { r.status = GZ_RSTATUS_INVALID_INPUT; r.note = "year/month out of range"; r.label = "MONTH_INVALID"; return; }
   r.label = StringFormat("M%04d-%02d", y, m);
   r.req_start = GZMakeTime(y,m,1,0,0,0);
   int ny = (m==12) ? y+1 : y;
   int nm = (m==12) ? 1 : m+1;
   r.req_end = (datetime)((long)GZMakeTime(ny,nm,1,0,0,0) - 1);
   GZRangeFinalize(r, true);
  }

void GZRangeDay(int y, int m, int d, GZ_ResearchRange &r)
  {
   r.Clear();
   r.kind = GZ_RANGE_DAY;
   if(y<1971 || y>2100 || m<1 || m>12 || d<1 || d>GZDaysInMonth(y,m))
     { r.status = GZ_RSTATUS_INVALID_INPUT; r.note = "year/month/day out of range"; r.label = "DAY_INVALID"; return; }
   r.label = StringFormat("D%04d-%02d-%02d", y, m, d);
   r.req_start = GZMakeTime(y,m,d,0,0,0);
   r.req_end   = (datetime)((long)r.req_start + GZ_SECONDS_PER_DAY - 1);
   GZRangeFinalize(r, true);
  }

//--- 7 calendar days starting at the DATE of `any_time_in_first_day` (e.g. 2024-03-04 -> 2024-03-10 23:59:59)
void GZRangeWeek(datetime any_time_in_first_day, GZ_ResearchRange &r)
  {
   r.Clear();
   r.kind = GZ_RANGE_WEEK;
   if(any_time_in_first_day<=0) { r.status = GZ_RSTATUS_INVALID_INPUT; r.note = "start not set"; r.label = "WEEK_INVALID"; return; }
   long day0 = ((long)any_time_in_first_day / GZ_SECONDS_PER_DAY) * GZ_SECONDS_PER_DAY;
   r.req_start = (datetime)day0;
   r.req_end   = (datetime)(day0 + 7*GZ_SECONDS_PER_DAY - 1);
   r.label = StringFormat("W%s", TimeToString(r.req_start, TIME_DATE));
   GZRangeFinalize(r, true);
  }

//--- Partition of an EFFECTIVE range relative to the preserved Development / Final-OOS boundary.
ENUM_GZ_PARTITION GZClassifyPartition(datetime eff_start, datetime eff_end, datetime legacy_oos_start)
  {
   if(eff_start >= legacy_oos_start) return GZ_PART_LEGACY_OOS_ONLY;
   if(eff_end   >  legacy_oos_start) return GZ_PART_CROSSES_LEGACY_OOS;
   return GZ_PART_DEVELOPMENT_ELIGIBLE;
  }

#endif // __GZ_RESEARCH_RANGE_MQH__
