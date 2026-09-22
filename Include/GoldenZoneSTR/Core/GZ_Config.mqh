//+------------------------------------------------------------------+
//| GZ_Config.mqh                                                     |
//| GoldenZone STR - Phase 1 - Configuration structures               |
//+------------------------------------------------------------------+
#ifndef __GZ_CONFIG_MQH__
#define __GZ_CONFIG_MQH__

#include "GZ_Types.mqh"

//+------------------------------------------------------------------+
//| A single session window definition.                              |
//| Boundary convention: [start, end)  -> start included, end excl.  |
//| If end < start the window is treated as an overnight window that |
//| wraps past midnight.                                             |
//+------------------------------------------------------------------+
struct GZ_SessionProfile
  {
   string            id;            // e.g. "PROFILE_01"
   string            name;          // human readable
   ENUM_GZ_TIME_MODE time_mode;     // domain the start/end are defined in
   int               start_hour;
   int               start_minute;
   int               end_hour;
   int               end_minute;
   bool              include;       // true = INCLUDE window, false = EXCLUDE
   bool              enabled;

   void Set(string p_id,string p_name,ENUM_GZ_TIME_MODE p_mode,
            int sh,int sm,int eh,int em,bool p_include,bool p_enabled)
     {
      id          = p_id;
      name        = p_name;
      time_mode   = p_mode;
      start_hour  = sh;
      start_minute= sm;
      end_hour    = eh;
      end_minute  = em;
      include     = p_include;
      enabled     = p_enabled;
     }

   int StartMinutesOfDay() const { return start_hour*60+start_minute; }
   int EndMinutesOfDay()   const { return end_hour*60+end_minute; }
   bool IsOvernight()      const { return EndMinutesOfDay() <= StartMinutesOfDay(); }
  };

//+------------------------------------------------------------------+
//| Time Engine configuration.                                       |
//+------------------------------------------------------------------+
struct GZ_TimeConfig
  {
   ENUM_GZ_DST_MODE  dst_mode;
   int               fixed_ny_offset_hours;   // used only when dst_mode == GZ_DST_FIXED
   int               broker_utc_offset_hours; // assumed broker/server offset from UTC
   bool              broker_offset_known;     // false -> TIMEZONE_STATUS = UNKNOWN

   void Default()
     {
      dst_mode                = GZ_DST_AUTO;
      fixed_ny_offset_hours   = -5;
      broker_utc_offset_hours = 0;
      broker_offset_known     = false;
     }
  };

#endif // __GZ_CONFIG_MQH__
