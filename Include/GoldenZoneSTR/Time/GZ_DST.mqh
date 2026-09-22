//+------------------------------------------------------------------+
//| GZ_DST.mqh                                                         |
//| GoldenZone STR - Phase 1 - US DST Rules for New York               |
//|                                                                    |
//| Implements the current US rule (effective since 2007):            |
//|   DST starts: 2nd Sunday of March, 02:00 local standard time      |
//|               (07:00 UTC)                                         |
//|   DST ends:   1st Sunday of November, 02:00 local daylight time   |
//|               (06:00 UTC)                                         |
//|                                                                    |
//| All transition instants are computed directly in UTC so no        |
//| ambiguity around the local clock jump is introduced.               |
//+------------------------------------------------------------------+
#ifndef __GZ_DST_MQH__
#define __GZ_DST_MQH__

#include "..\Core\GZ_Constants.mqh"

class CGZDst
  {
private:
   //--- Find the UTC datetime of the Nth weekday occurrence in a month --
   // weekday: 0=Sunday .. 6=Saturday (matches MqlDateTime.day_of_week)
   // n=1 -> first occurrence, n=2 -> second occurrence, etc.
   datetime NthWeekdayOfMonth(int year, int month, int weekday, int n) const
     {
      MqlDateTime dt;
      dt.year=year; dt.mon=month; dt.day=1; dt.hour=0; dt.min=0; dt.sec=0;
      datetime first_of_month = StructToTime(dt);

      MqlDateTime first_dt;
      TimeToStruct(first_of_month, first_dt);
      int first_weekday = first_dt.day_of_week;

      int day_offset = (weekday - first_weekday + 7) % 7;
      int day_of_month = 1 + day_offset + (n-1)*7;

      dt.day = day_of_month;
      return StructToTime(dt);
     }

public:
   //--- UTC instant when DST begins (spring forward) for a given year ---
   datetime SpringForwardUtc(int year) const
     {
      // 2nd Sunday of March, 02:00 EST (UTC-5) == 07:00 UTC
      datetime second_sunday_midnight = NthWeekdayOfMonth(year, 3, 0, 2);
      return second_sunday_midnight + 7*GZ_SECONDS_PER_HOUR;
     }

   //--- UTC instant when DST ends (fall back) for a given year -----------
   datetime FallBackUtc(int year) const
     {
      // 1st Sunday of November, 02:00 EDT (UTC-4) == 06:00 UTC
      datetime first_sunday_midnight = NthWeekdayOfMonth(year, 11, 0, 1);
      return first_sunday_midnight + 6*GZ_SECONDS_PER_HOUR;
     }

   //--- Is New York observing daylight time at this UTC instant? ---------
   bool IsDaylight(datetime utc_time) const
     {
      MqlDateTime dt;
      TimeToStruct(utc_time, dt);
      int year = dt.year;

      datetime spring = SpringForwardUtc(year);
      datetime fall    = FallBackUtc(year);

      return (utc_time >= spring && utc_time < fall);
     }

   //--- Applicable NY offset (hours) for a given UTC instant + mode ------
   int GetNyOffsetHours(datetime utc_time, ENUM_GZ_DST_MODE mode, int fixed_offset_hours) const
     {
      switch(mode)
        {
         case GZ_DST_FIXED:
            return fixed_offset_hours;
         case GZ_DST_DISABLED:
            return GZ_NY_STD_OFFSET_HOURS; // no auto-adjustment, use standard
         case GZ_DST_AUTO:
         default:
            return IsDaylight(utc_time) ? GZ_NY_DST_OFFSET_HOURS : GZ_NY_STD_OFFSET_HOURS;
        }
     }

   string GetNyStateLabel(datetime utc_time, ENUM_GZ_DST_MODE mode) const
     {
      if(mode==GZ_DST_DISABLED) return "DISABLED";
      if(mode==GZ_DST_FIXED)    return "FIXED";
      return IsDaylight(utc_time) ? "EDT" : "EST";
     }
  };

#endif // __GZ_DST_MQH__
