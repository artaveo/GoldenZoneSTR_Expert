//+------------------------------------------------------------------+
//| GZ_TimeEngine.mqh                                                  |
//| GoldenZone STR - Phase 1 - Time Engine                            |
//|                                                                    |
//| Converts a broker timestamp into Broker/UTC/New-York time and     |
//| DST state. Completely independent of Strategy Logic - later      |
//| phases consume GZ_TimeContext without knowing how DST works.      |
//+------------------------------------------------------------------+
#ifndef __GZ_TIMEENGINE_MQH__
#define __GZ_TIMEENGINE_MQH__

#include "GZ_DST.mqh"
#include "..\Core\GZ_Config.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZTimeEngine
  {
private:
   GZ_TimeConfig     m_config;
   CGZDst            m_dst;
   CGZLogger        *m_logger;

public:
                     CGZTimeEngine(CGZLogger *logger=NULL)
     {
      m_logger = logger;
      m_config.Default();
     }

   void              Configure(const GZ_TimeConfig &cfg)
     {
      m_config = cfg;
      if(m_logger!=NULL)
         m_logger.Info("TimeEngine", StringFormat(
            "Configured: DST mode=%d broker_offset=%d known=%s",
            (int)m_config.dst_mode, m_config.broker_utc_offset_hours,
            m_config.broker_offset_known ? "true" : "false"));
     }

   GZ_TimeConfig     GetConfig() const { return m_config; }

   //--- Build a full TimeContext from a broker timestamp -----------------
   void BuildContext(datetime broker_time, GZ_TimeContext &ctx) const
     {
      ctx.Clear();
      ctx.broker_time = broker_time;

      ctx.broker_tz_status = m_config.broker_offset_known ? GZ_TZ_KNOWN : GZ_TZ_UNKNOWN;

      // Broker time -> UTC. If offset unknown, UTC is reported as UNKNOWN
      // (represented here as broker_time unchanged) but flagged.
      datetime utc = broker_time - m_config.broker_utc_offset_hours * GZ_SECONDS_PER_HOUR;
      ctx.utc_time = utc;

      int ny_offset = m_dst.GetNyOffsetHours(utc, m_config.dst_mode, m_config.fixed_ny_offset_hours);
      ctx.ny_time   = utc + ny_offset * GZ_SECONDS_PER_HOUR;
      ctx.ny_is_dst = (m_config.dst_mode==GZ_DST_AUTO) ? m_dst.IsDaylight(utc) : false;
      ctx.dst_state = m_dst.GetNyStateLabel(utc, m_config.dst_mode);
     }

   //--- Convenience direct converters (do not require a full context) ---
   datetime          BrokerToUtc(datetime broker_time) const
     { return broker_time - m_config.broker_utc_offset_hours * GZ_SECONDS_PER_HOUR; }

   datetime          UtcToNewYork(datetime utc_time) const
     {
      int offset = m_dst.GetNyOffsetHours(utc_time, m_config.dst_mode, m_config.fixed_ny_offset_hours);
      return utc_time + offset * GZ_SECONDS_PER_HOUR;
     }
  };

#endif // __GZ_TIMEENGINE_MQH__
