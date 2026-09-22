//+------------------------------------------------------------------+
//| GZ_DataValidator.mqh                                              |
//| GoldenZone STR - Phase 1 - Data Validator                         |
//|                                                                    |
//| Validates OHLC integrity and timestamp behavior. Distinguishes   |
//| expected gaps (weekend/known closures) from unexpected gaps.     |
//| Does NOT repair or fabricate data - only reports.                 |
//+------------------------------------------------------------------+
#ifndef __GZ_DATAVALIDATOR_MQH__
#define __GZ_DATAVALIDATOR_MQH__

#include "GZ_DatasetInfo.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZDataValidator
  {
private:
   CGZLogger        *m_logger;

   //--- true if [from,to] interval contains a Saturday (broker weekend) -
   bool ContainsSaturday(datetime from, datetime to) const
     {
      if(to<=from) return false;
      datetime cursor = from;
      // step day by day (bounded loop - date ranges in research are finite,
      // but guard against pathological input)
      int guard = 0;
      while(cursor < to && guard < 40)
        {
         MqlDateTime dt;
         TimeToStruct(cursor, dt);
         if(dt.day_of_week == 6) // Saturday
            return true;
         cursor += GZ_SECONDS_PER_DAY;
         guard++;
        }
      // also check the day 'to' itself lands on, in case cursor stepping
      // skipped past it within the same day due to time-of-day offset
      MqlDateTime dt_to;
      TimeToStruct(to, dt_to);
      if(dt_to.day_of_week == 6)
         return true;
      return false;
     }

public:
                     CGZDataValidator(CGZLogger *logger=NULL) { m_logger=logger; }

   //--- OHLC validation: returns count of invalid bars -------------------
   int ValidateOHLC(const MqlRates &rates[], CGZDatasetInfo &info)
     {
      int n = ArraySize(rates);
      int invalid = 0;
      for(int i=0;i<n;i++)
        {
         bool ok = true;
         double o=rates[i].open, h=rates[i].high, l=rates[i].low, c=rates[i].close;

         if(!MathIsValidNumber(o) || !MathIsValidNumber(h) ||
            !MathIsValidNumber(l) || !MathIsValidNumber(c))
            ok = false;
         else
           {
            if(h < MathMax(o,c)) ok=false;
            if(l > MathMin(o,c)) ok=false;
            if(h < l)            ok=false;
            if(o<=0.0 || h<=0.0 || l<=0.0 || c<=0.0) ok=false;
           }

         if(!ok)
           {
            invalid++;
            info.AddError(StringFormat("Invalid OHLC at %s (O=%.5f H=%.5f L=%.5f C=%.5f)",
                           TimeToString(rates[i].time,TIME_DATE|TIME_MINUTES), o,h,l,c));
           }
        }
      info.invalid_ohlc_count = invalid;
      if(m_logger!=NULL)
         m_logger.Info("Validator", StringFormat("OHLC validation: %d invalid bar(s) out of %d", invalid, n));
      return invalid;
     }

   //--- Timestamp validation: ordering, duplicates, gaps ------------------
   void ValidateTimestamps(const MqlRates &rates[], int spacing_seconds, CGZDatasetInfo &info)
     {
      int n = ArraySize(rates);
      int duplicates = 0;
      int ordering_errors = 0;
      int unexpected_gaps = 0;
      int expected_gaps = 0;

      for(int i=1;i<n;i++)
        {
         datetime prev = rates[i-1].time;
         datetime curr = rates[i].time;

         if(curr < prev)
           {
            ordering_errors++;
            info.AddError(StringFormat("Out-of-order timestamp at index %d: %s after %s",
                           i, TimeToString(curr), TimeToString(prev)));
            continue;
           }

         if(curr == prev)
           {
            duplicates++;
            info.AddWarning(StringFormat("Duplicate timestamp at index %d: %s", i, TimeToString(curr)));
            continue;
           }

         long gap = (long)(curr - prev);
         if(gap > spacing_seconds)
           {
            if(ContainsSaturday(prev,curr))
              {
               expected_gaps++;
              }
            else
              {
               unexpected_gaps++;
               info.AddWarning(StringFormat("Unexpected gap: %s -> %s (%d sec, expected %d)",
                              TimeToString(prev), TimeToString(curr), gap, spacing_seconds));
              }
           }
        }

      info.duplicate_count       = duplicates;
      info.timestamp_error_count = ordering_errors;
      info.missing_bar_count     = unexpected_gaps;
      info.expected_gap_count    = expected_gaps;

      if(m_logger!=NULL)
         m_logger.Info("Validator", StringFormat(
            "Timestamp validation: %d ordering error(s), %d duplicate(s), %d unexpected gap(s), %d expected gap(s)",
            ordering_errors, duplicates, unexpected_gaps, expected_gaps));
     }

   //--- M1/M5 synchronization: find the M5 bar whose window contains t1 --
   // Returns index into m5 array, or -1 if not found.
   // Uses timestamps only - never assumes matching array indices, and
   // never returns a future M5 bar (M5 open time must be <= m1 time).
   int FindM5ContextForM1(datetime m1_time, const MqlRates &m5[]) const
     {
      int n = ArraySize(m5);
      int result = -1;
      for(int i=0;i<n;i++)
        {
         if(m5[i].time <= m1_time)
            result = i;          // candidate: latest M5 bar that has opened
         else
            break;                // m5 is chronological; no need to scan further
        }
      return result;
     }
  };

#endif // __GZ_DATAVALIDATOR_MQH__
