//+------------------------------------------------------------------+
//| GZ_DataProvider.mqh                                               |
//| GoldenZone STR - Phase 1 - Data Provider                          |
//|                                                                    |
//| Pure data-access abstraction. NO trading / strategy logic.        |
//| Wraps CopyRates and exposes chronological MqlRates arrays.        |
//+------------------------------------------------------------------+
#ifndef __GZ_DATAPROVIDER_MQH__
#define __GZ_DATAPROVIDER_MQH__

#include "..\Diagnostics\GZ_Logger.mqh"

class CGZDataProvider
  {
private:
   CGZLogger        *m_logger;

   //--- ensure chronological (ascending time) ordering -----------------
   void EnsureChronological(MqlRates &rates[])
     {
      int n=ArraySize(rates);
      if(n<2) return;
      if(rates[0].time <= rates[n-1].time)
         return; // already ascending
      // CopyRates from most terminals returns ascending already;
      // if descending, reverse in place.
      int i=0, j=n-1;
      while(i<j)
        {
         MqlRates tmp = rates[i];
         rates[i] = rates[j];
         rates[j] = tmp;
         i++; j--;
        }
      if(m_logger!=NULL)
         m_logger.Debug("DataProvider","Reversed array to enforce chronological order");
     }

public:
                     CGZDataProvider(CGZLogger *logger=NULL) { m_logger=logger; }

   //--- Load bars for [start,end] inclusive, chronological order -------
   int Load(string symbol, ENUM_TIMEFRAMES tf, datetime start, datetime end, MqlRates &rates[])
     {
      ArrayResize(rates,0);
      if(symbol=="" )
        {
         if(m_logger!=NULL) m_logger.Error("DataProvider","Empty symbol supplied");
         return 0;
        }
      if(end!=0 && start!=0 && end<start)
        {
         if(m_logger!=NULL) m_logger.Error("DataProvider","end < start in requested range");
         return 0;
        }

      int copied = CopyRates(symbol, tf, start, end, rates);
      if(copied<=0)
        {
         if(m_logger!=NULL)
            m_logger.Warning("DataProvider",
               StringFormat("CopyRates returned %d bars for %s (start=%s end=%s). Data may be unavailable.",
                             copied, symbol, TimeToString(start), TimeToString(end)));
         return 0;
        }

      EnsureChronological(rates);

      if(m_logger!=NULL)
         m_logger.Info("DataProvider", StringFormat("Loaded %d bars for %s [%s .. %s]",
                        copied, symbol, TimeToString(rates[0].time), TimeToString(rates[copied-1].time)));
      return copied;
     }

   int LoadM1(string symbol, datetime start, datetime end, MqlRates &rates[])
     { return Load(symbol, PERIOD_M1, start, end, rates); }

   int LoadM5(string symbol, datetime start, datetime end, MqlRates &rates[])
     { return Load(symbol, PERIOD_M5, start, end, rates); }

   int LoadM15(string symbol, datetime start, datetime end, MqlRates &rates[])
     { return Load(symbol, PERIOD_M15, start, end, rates); }

   //--- Availability helpers --------------------------------------------
   ENUM_GZ_AVAILABILITY SpreadAvailability(const MqlRates &rates[]) const
     {
      int n=ArraySize(rates);
      if(n==0) return GZ_AVAIL_UNKNOWN;
      for(int i=0;i<n;i++)
         if(rates[i].spread>0) return GZ_AVAIL_AVAILABLE;
      return GZ_AVAIL_NOT_AVAILABLE;
     }

   ENUM_GZ_AVAILABILITY TickVolumeAvailability(const MqlRates &rates[]) const
     {
      int n=ArraySize(rates);
      if(n==0) return GZ_AVAIL_UNKNOWN;
      for(int i=0;i<n;i++)
         if(rates[i].tick_volume>0) return GZ_AVAIL_AVAILABLE;
      return GZ_AVAIL_NOT_AVAILABLE;
     }

   ENUM_GZ_AVAILABILITY RealVolumeAvailability(const MqlRates &rates[]) const
     {
      int n=ArraySize(rates);
      if(n==0) return GZ_AVAIL_UNKNOWN;
      for(int i=0;i<n;i++)
         if(rates[i].real_volume>0) return GZ_AVAIL_AVAILABLE;
      return GZ_AVAIL_NOT_AVAILABLE;
     }
  };

#endif // __GZ_DATAPROVIDER_MQH__
