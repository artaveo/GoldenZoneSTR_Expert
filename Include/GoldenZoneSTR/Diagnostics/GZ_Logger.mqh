//+------------------------------------------------------------------+
//| GZ_Logger.mqh                                                     |
//| GoldenZone STR - Phase 1 - Diagnostic Logger                     |
//|                                                                    |
//| Lightweight logging wrapper. Supports INFO/WARNING/ERROR/DEBUG.  |
//| Detailed per-bar logging is opt-in via EnableVerbose().          |
//+------------------------------------------------------------------+
#ifndef __GZ_LOGGER_MQH__
#define __GZ_LOGGER_MQH__

#include "..\Core\GZ_Types.mqh"

class CGZLogger
  {
private:
   bool              m_verbose;     // enable DEBUG / per-bar logging
   ENUM_GZ_SEVERITY  m_min_level;   // minimum severity that gets printed

   string SeverityToString(ENUM_GZ_SEVERITY sev) const
     {
      switch(sev)
        {
         case GZ_SEV_INFO:    return "INFO";
         case GZ_SEV_WARNING: return "WARNING";
         case GZ_SEV_ERROR:   return "ERROR";
         case GZ_SEV_FATAL:   return "FATAL";
         case GZ_SEV_DEBUG:   return "DEBUG";
        }
      return "UNKNOWN";
     }

public:
                     CGZLogger() { m_verbose=false; m_min_level=GZ_SEV_INFO; }

   void              EnableVerbose(bool enable) { m_verbose = enable; }
   void              SetMinLevel(ENUM_GZ_SEVERITY lvl) { m_min_level = lvl; }

   void              Log(ENUM_GZ_SEVERITY sev,string tag,string msg)
     {
      if(sev==GZ_SEV_DEBUG && !m_verbose)
         return;
      if((int)sev < (int)m_min_level && sev!=GZ_SEV_DEBUG)
         return;
      PrintFormat("[GZ][%s][%s] %s", SeverityToString(sev), tag, msg);
     }

   void              Info(string tag,string msg)    { Log(GZ_SEV_INFO,tag,msg); }
   void              Warning(string tag,string msg)  { Log(GZ_SEV_WARNING,tag,msg); }
   void              Error(string tag,string msg)    { Log(GZ_SEV_ERROR,tag,msg); }
   void              Fatal(string tag,string msg)    { Log(GZ_SEV_FATAL,tag,msg); }
   void              Debug(string tag,string msg)    { Log(GZ_SEV_DEBUG,tag,msg); }
  };

#endif // __GZ_LOGGER_MQH__
