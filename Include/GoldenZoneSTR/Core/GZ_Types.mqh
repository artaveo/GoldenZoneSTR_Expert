//+------------------------------------------------------------------+
//| GZ_Types.mqh                                                     |
//| GoldenZone STR - Phase 1 - Core Types                            |
//|                                                                   |
//| Shared enums and lightweight structures used across the Data    |
//| Layer, Validator, Time Engine and Session Engine.                |
//| This file contains NO strategy logic (Phase 2+).                 |
//+------------------------------------------------------------------+
#ifndef __GZ_TYPES_MQH__
#define __GZ_TYPES_MQH__

//--- Dataset validation status --------------------------------------
enum ENUM_GZ_VALIDATION_STATUS
  {
   GZ_VAL_UNKNOWN = 0,
   GZ_VAL_VALID,
   GZ_VAL_VALID_WITH_WARNINGS,
   GZ_VAL_INVALID
  };

//--- Time interpretation mode ----------------------------------------
enum ENUM_GZ_TIME_MODE
  {
   GZ_TIME_BROKER = 0,
   GZ_TIME_UTC,
   GZ_TIME_NEW_YORK
  };

//--- DST handling mode ------------------------------------------------
enum ENUM_GZ_DST_MODE
  {
   GZ_DST_AUTO = 0,
   GZ_DST_FIXED,
   GZ_DST_DISABLED
  };

//--- Session evaluation result ---------------------------------------
enum ENUM_GZ_SESSION_RESULT
  {
   GZ_SESSION_OUTSIDE = 0,
   GZ_SESSION_INSIDE
  };

//--- Diagnostic severity ----------------------------------------------
enum ENUM_GZ_SEVERITY
  {
   GZ_SEV_INFO = 0,
   GZ_SEV_WARNING,
   GZ_SEV_ERROR,
   GZ_SEV_FATAL,
   GZ_SEV_DEBUG
  };

//--- Broker timezone reliability ---------------------------------------
enum ENUM_GZ_TZ_STATUS
  {
   GZ_TZ_KNOWN = 0,
   GZ_TZ_UNKNOWN
  };

//--- Availability tri-state (data columns may be missing) -------------
enum ENUM_GZ_AVAILABILITY
  {
   GZ_AVAIL_NOT_AVAILABLE = 0,
   GZ_AVAIL_AVAILABLE,
   GZ_AVAIL_UNKNOWN
  };

//--- Gap classification -------------------------------------------------
enum ENUM_GZ_GAP_TYPE
  {
   GZ_GAP_NONE = 0,
   GZ_GAP_EXPECTED,     // weekend / known closure
   GZ_GAP_UNEXPECTED    // possible missing / corrupted data
  };

//+------------------------------------------------------------------+
//| Reusable time context passed to later phases.                    |
//| Populated exclusively by the Time Engine.                        |
//+------------------------------------------------------------------+
struct GZ_TimeContext
  {
   datetime          broker_time;
   datetime          utc_time;
   datetime          ny_time;
   bool              ny_is_dst;        // true = EDT, false = EST
   string            dst_state;        // "EST" / "EDT" / "DISABLED" / "FIXED"
   string            session_id;
   ENUM_GZ_SESSION_RESULT session_result;
   bool              inside_session;
   ENUM_GZ_TZ_STATUS broker_tz_status;

   void Clear()
     {
      broker_time     = 0;
      utc_time        = 0;
      ny_time         = 0;
      ny_is_dst       = false;
      dst_state       = "UNKNOWN";
      session_id      = "";
      session_result  = GZ_SESSION_OUTSIDE;
      inside_session  = false;
      broker_tz_status= GZ_TZ_UNKNOWN;
     }
  };

//+------------------------------------------------------------------+
//| Simple result record used by the test harness.                  |
//+------------------------------------------------------------------+
struct GZ_TestResult
  {
   string   id;
   bool     passed;
   bool     blocked;      // requires user / cannot run automatically
   string   detail;
  };

#endif // __GZ_TYPES_MQH__
