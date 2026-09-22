//+------------------------------------------------------------------+
//| GZ_Session.mqh                                                     |
//| GoldenZone STR - Phase 1 - Session Engine                         |
//|                                                                    |
//| Boundary convention: [start, end) -> start included, end excluded.|
//| Date range and session window are evaluated independently:        |
//| callers must check IsInDateRange() separately from Evaluate().    |
//+------------------------------------------------------------------+
#ifndef __GZ_SESSION_MQH__
#define __GZ_SESSION_MQH__

#include "..\Core\GZ_Config.mqh"
#include "..\Core\GZ_Types.mqh"

class CGZSessionEngine
  {
private:
   //--- pick the correct time-domain value out of a TimeContext ---------
   datetime SelectDomainTime(const GZ_TimeContext &ctx, ENUM_GZ_TIME_MODE mode) const
     {
      switch(mode)
        {
         case GZ_TIME_UTC:       return ctx.utc_time;
         case GZ_TIME_NEW_YORK:  return ctx.ny_time;
         case GZ_TIME_BROKER:
         default:                return ctx.broker_time;
        }
     }

   int MinutesOfDay(datetime t) const
     {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      return dt.hour*60 + dt.min;
     }

public:
   //--- Date range check: independent from session-window evaluation ----
   bool IsInDateRange(datetime t, datetime range_start, datetime range_end) const
     {
      if(range_start!=0 && t < range_start) return false;
      if(range_end!=0   && t > range_end)   return false;
      return true;
     }

   //--- Evaluate whether ctx falls inside the given session profile -----
   ENUM_GZ_SESSION_RESULT Evaluate(const GZ_TimeContext &ctx, const GZ_SessionProfile &profile) const
     {
      if(!profile.enabled)
         return GZ_SESSION_OUTSIDE;

      datetime domain_time = SelectDomainTime(ctx, profile.time_mode);
      int mod = MinutesOfDay(domain_time);

      int start_m = profile.StartMinutesOfDay();
      int end_m   = profile.EndMinutesOfDay();

      bool inside;
      if(!profile.IsOvernight())
        {
         // Normal same-day window: [start,end)
         inside = (mod >= start_m && mod < end_m);
        }
      else
        {
         // Overnight window wraps past midnight: [start,1440) U [0,end)
         inside = (mod >= start_m || mod < end_m);
        }

      bool result_inside = profile.include ? inside : !inside;
      return result_inside ? GZ_SESSION_INSIDE : GZ_SESSION_OUTSIDE;
     }
  };

#endif // __GZ_SESSION_MQH__
