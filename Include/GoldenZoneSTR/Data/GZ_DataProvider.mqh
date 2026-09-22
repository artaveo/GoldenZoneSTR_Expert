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

   //--- readable timeframe label, e.g. PERIOD_M1 -> "M1" ------------------
   string TfLabel(ENUM_TIMEFRAMES tf) const
     {
      string s = EnumToString(tf);
      if(StringFind(s,"PERIOD_")==0)
         return StringSubstr(s,7);
      return s;
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
         Print("[GZ][DataProvider][ERROR] Empty symbol supplied");
         return 0;
        }
      if(end!=0 && start!=0 && end<start)
        {
         if(m_logger!=NULL) m_logger.Error("DataProvider","end < start in requested range");
         Print("[GZ][DataProvider][ERROR] end < start in requested range");
         return 0;
        }

      string tf_name    = TfLabel(tf);
      string start_str  = TimeToString(start, TIME_DATE|TIME_MINUTES);
      string end_str    = TimeToString(end,   TIME_DATE|TIME_MINUTES);

      int copied = CopyRates(symbol, tf, start, end, rates);

      // Capture the error code IMMEDIATELY after CopyRates() - before any
      // other API call (SeriesInfoInteger included) can overwrite it.
      int last_error = GetLastError();

      if(copied<=0)
        {
         // Standard-MQL5 series diagnostics. Their own possible internal
         // errors are irrelevant here - the real last_error was already
         // captured above, before these ran.
         long     series_bars     = SeriesInfoInteger(symbol, tf, SERIES_BARS_COUNT);
         datetime series_first    = (datetime)SeriesInfoInteger(symbol, tf, SERIES_FIRSTDATE);
         datetime terminal_first  = (datetime)SeriesInfoInteger(symbol, tf, SERIES_TERMINAL_FIRSTDATE);
         bool     series_synced   = (bool)SeriesInfoInteger(symbol, tf, SERIES_SYNCHRONIZED);

         // (A) GUARANTEED-VISIBLE diagnostic: raw Print(), one field per
         // line, called unconditionally. This does NOT go through
         // CGZLogger at all, so it cannot be lost to a NULL logger
         // pointer, a min-level filter, or any future logger change.
         Print("[GZ][DataProvider][CopyRates FAILED]");
         Print("Symbol=", symbol);
         Print("Timeframe=", tf_name);
         Print("Start=", start_str);
         Print("End=", end_str);
         Print("CopyRatesResult=", copied);
         Print("LastError=", last_error);
         Print("SeriesBarsInTerminal=", series_bars);
         Print("SeriesFirstDate=", TimeToString(series_first, TIME_DATE|TIME_MINUTES));
         Print("TerminalFirstDate=", TimeToString(terminal_first, TIME_DATE|TIME_MINUTES));
         Print("SeriesSynchronized=", (series_synced ? "true" : "false"));

         // (B) Same information again through the structured logger, kept
         // ONLY as a secondary/formatted copy for consistency with the
         // rest of the system's log style - (A) above is the one this
         // diagnostic actually depends on.
         if(m_logger!=NULL)
           {
            string diag = StringFormat(
               "CopyRates FAILED | Symbol=%s Timeframe=%s Start=%s End=%s "+
               "CopyRatesResult=%d LastError=%d SeriesBarsInTerminal=%d "+
               "SeriesFirstDate=%s TerminalFirstDate=%s SeriesSynchronized=%s",
               symbol, tf_name, start_str, end_str, copied, last_error,
               series_bars,
               TimeToString(series_first,TIME_DATE|TIME_MINUTES),
               TimeToString(terminal_first,TIME_DATE|TIME_MINUTES),
               series_synced?"true":"false");
            m_logger.Warning("DataProvider", diag);
           }

         return 0;
        }

      EnsureChronological(rates);

      // Symmetric success diagnostic - same guaranteed-visible pattern as
      // the failure case above, so a successful timeframe (e.g. M5) and a
      // failing one (e.g. M1) produce directly comparable log blocks.
      Print("[GZ][DataProvider][CopyRates OK]");
      Print("Symbol=", symbol);
      Print("Timeframe=", tf_name);
      Print("Bars=", copied);
      Print("First=", TimeToString(rates[0].time, TIME_DATE|TIME_MINUTES));
      Print("Last=", TimeToString(rates[copied-1].time, TIME_DATE|TIME_MINUTES));

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
