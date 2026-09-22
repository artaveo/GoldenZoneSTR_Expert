//+------------------------------------------------------------------+
//| GZ_DatasetInfo.mqh                                                |
//| GoldenZone STR - Phase 1 - Dataset Metadata                       |
//+------------------------------------------------------------------+
#ifndef __GZ_DATASETINFO_MQH__
#define __GZ_DATASETINFO_MQH__

#include "..\Core\GZ_Types.mqh"

//+------------------------------------------------------------------+
//| Holds everything known about one loaded dataset (one symbol/tf). |
//+------------------------------------------------------------------+
class CGZDatasetInfo
  {
public:
   string            symbol;
   ENUM_TIMEFRAMES   execution_timeframe;   // e.g. PERIOD_M1
   ENUM_TIMEFRAMES   structure_timeframe;   // e.g. PERIOD_M5
   ENUM_TIMEFRAMES   context_timeframe;     // optional, e.g. PERIOD_M15 (WRONG_VALUE if unused)
   bool              context_timeframe_used;

   datetime          start_timestamp;
   datetime          end_timestamp;

   int               broker_utc_offset_hours;
   ENUM_GZ_TZ_STATUS broker_tz_status;

   int               total_bars;
   datetime          first_bar_time;
   datetime          last_bar_time;

   int               missing_bar_count;      // unexpected gaps only
   int               expected_gap_count;      // weekend / known closures
   int               duplicate_count;
   int               invalid_ohlc_count;
   int               timestamp_error_count;

   ENUM_GZ_AVAILABILITY spread_availability;
   ENUM_GZ_AVAILABILITY tick_volume_availability;
   ENUM_GZ_AVAILABILITY real_volume_availability;

   ENUM_GZ_VALIDATION_STATUS validation_status;

   string            warnings[];
   string            errors[];

   void Clear()
     {
      symbol                   = "";
      execution_timeframe      = PERIOD_M1;
      structure_timeframe      = PERIOD_M5;
      context_timeframe        = PERIOD_M15;
      context_timeframe_used   = false;
      start_timestamp          = 0;
      end_timestamp            = 0;
      broker_utc_offset_hours  = 0;
      broker_tz_status         = GZ_TZ_UNKNOWN;
      total_bars               = 0;
      first_bar_time           = 0;
      last_bar_time            = 0;
      missing_bar_count        = 0;
      expected_gap_count       = 0;
      duplicate_count          = 0;
      invalid_ohlc_count       = 0;
      timestamp_error_count    = 0;
      spread_availability      = GZ_AVAIL_UNKNOWN;
      tick_volume_availability = GZ_AVAIL_UNKNOWN;
      real_volume_availability = GZ_AVAIL_UNKNOWN;
      validation_status        = GZ_VAL_UNKNOWN;
      ArrayResize(warnings,0);
      ArrayResize(errors,0);
     }

   void AddWarning(string msg)
     {
      int n=ArraySize(warnings);
      ArrayResize(warnings,n+1);
      warnings[n]=msg;
     }

   void AddError(string msg)
     {
      int n=ArraySize(errors);
      ArrayResize(errors,n+1);
      errors[n]=msg;
     }

   //--- Determine final status from accumulated counters --------------
   void Finalize()
     {
      if(invalid_ohlc_count>0 || timestamp_error_count>0 || ArraySize(errors)>0)
         validation_status = GZ_VAL_INVALID;
      else if(duplicate_count>0 || missing_bar_count>0 || ArraySize(warnings)>0)
         validation_status = GZ_VAL_VALID_WITH_WARNINGS;
      else
         validation_status = GZ_VAL_VALID;
     }

   string StatusToString() const
     {
      switch(validation_status)
        {
         case GZ_VAL_VALID:               return "VALID";
         case GZ_VAL_VALID_WITH_WARNINGS: return "VALID_WITH_WARNINGS";
         case GZ_VAL_INVALID:             return "INVALID";
        }
      return "UNKNOWN";
     }
  };

#endif // __GZ_DATASETINFO_MQH__
