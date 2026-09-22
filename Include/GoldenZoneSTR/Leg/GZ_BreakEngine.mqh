//+------------------------------------------------------------------+
//| GZ_BreakEngine.mqh                                                |
//| GoldenZone STR - Phase 3 - Break Engine                          |
//|                                                                    |
//| Detects when a Leg's target_swing level is broken, using only    |
//| the bar currently being fed and bars fed earlier (no lookahead).  |
//| Owns its own ATR calculation (used only to size the break buffer  |
//| - never exposed as an entry filter; that is Phase 4+ scope).      |
//|                                                                    |
//| Call order per bar (see Expert file):                             |
//|   1. leg_engine.UpdateBar(bar)      - extend open legs' extremes  |
//|   2. break_engine.OnBar(bar)        - advance the shared ATR      |
//|   3. break_engine.CheckBreak(leg,bar) for each still-open leg     |
//| This ordering means the breaking bar's own wick/close already     |
//| contributed to the leg's extreme before the break is evaluated -  |
//| a deliberate, documented choice, not an accident of call order.   |
//+------------------------------------------------------------------+
#ifndef __GZ_BREAK_ENGINE_MQH__
#define __GZ_BREAK_ENGINE_MQH__

#include "GZ_LegTypes.mqh"
#include "GZ_ATR.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZBreakEngine
  {
private:
   GZ_BreakConfig    m_cfg;
   CGZAtr            m_atr;
   CGZLogger        *m_logger;

public:
                     CGZBreakEngine(CGZLogger *logger=NULL) { m_logger=logger; m_cfg.Default(); }

   void              Configure(const GZ_BreakConfig &cfg)
     {
      m_cfg = cfg;
      m_atr.Init(m_cfg.atr_period);
     }

   double            CurrentAtr()  const { return m_atr.Value(); }
   bool              AtrReady()    const { return m_atr.IsReady(); }

   //--- Advance the shared ATR calculation by exactly one closed bar.
   //--- Must be called once per bar, in order, before CheckBreak() for
   //--- that same bar.
   void              OnBar(const MqlRates &bar)
     {
      m_atr.Update(bar);
     }

   //--- Evaluate `leg` against `bar`. Mutates `leg` (sets broken/
   //--- break_time/break_price) if the break condition is met on this
   //--- bar. Returns true iff this call is the one that confirmed the
   //--- break (false on every earlier bar, and false on every bar after
   //--- the leg is already broken - no re-evaluation, no lookahead).
   bool              CheckBreak(GZ_Leg &leg, const MqlRates &bar)
     {
      if(leg.broken)
         return false;
      if(bar.time < leg.target_swing.confirmation_time)
         return false; // level cannot be "broken" before it even existed

      double buffer_price = 0.0;
      if(m_cfg.buffer_atr_mult>0.0)
        {
         if(!m_atr.IsReady())
            return false; // buffer requested but not yet computable - do not guess
         buffer_price = m_cfg.buffer_atr_mult * m_atr.Value();
        }

      double level = leg.target_swing.price;
      bool   confirmed = false;
      double touch_price = 0.0;

      if(leg.direction==GZ_LEG_BULLISH)
        {
         double threshold = level + buffer_price;
         touch_price = (m_cfg.mode==GZ_BREAK_CLOSE) ? bar.close : bar.high;
         confirmed = (touch_price>threshold);
        }
      else // BEARISH
        {
         double threshold = level - buffer_price;
         touch_price = (m_cfg.mode==GZ_BREAK_CLOSE) ? bar.close : bar.low;
         confirmed = (touch_price<threshold);
        }

      if(!confirmed)
         return false;

      leg.broken          = true;
      leg.break_time       = bar.time;
      leg.break_price      = touch_price;
      leg.break_mode_used  = m_cfg.mode;

      if(m_logger!=NULL)
         m_logger.Info("Break", StringFormat("Leg #%d (%s) BROKEN mode=%s buffer_atr_mult=%.2f level=%.5f at=%.5f time=%s",
                       (int)leg.id, leg.DirectionToString(),
                       (m_cfg.mode==GZ_BREAK_CLOSE)?"CLOSE":"WICK", m_cfg.buffer_atr_mult,
                       level, touch_price, TimeToString(bar.time)));
      return true;
     }
  };

#endif // __GZ_BREAK_ENGINE_MQH__
