//+------------------------------------------------------------------+
//| GZ_LegEngine.mqh                                                  |
//| GoldenZone STR - Phase 3 - Leg Engine                             |
//|                                                                    |
//| Consumes CONFIRMED swings (as produced by CGZSwingEngine, Phase   |
//| 2) and produces Leg candidates - see GZ_LegTypes.mqh for the      |
//| exact origin/target/direction definition. Also tracks each open   |
//| leg's running price extreme bar-by-bar. NO break/fib/setup/entry  |
//| logic lives here (Phase 3 Break Engine / Phase 4+).                |
//|                                                                    |
//| DESIGN (mirrors Phase 2's Shared-Strategy-Core intent): the same  |
//| instance must work for both historical research (fed swings/bars  |
//| in bulk via convenience wrappers) and a future live Execution     |
//| Adapter (fed one confirmed swing / one closed bar at a time via   |
//| Update()/UpdateBar()). It never inspects data beyond what it has  |
//| been given, and extreme tracking for a leg only ever consumes    |
//| bars at or after that leg's target_swing confirmation time.       |
//+------------------------------------------------------------------+
#ifndef __GZ_LEG_ENGINE_MQH__
#define __GZ_LEG_ENGINE_MQH__

#include "GZ_LegTypes.mqh"
#include "GZ_ATR.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZLegEngine
  {
private:
   ENUM_GZ_LEG_VARIANT m_variant;
   GZ_Swing          m_highs[];   // history of confirmed swing highs, chronological
   GZ_Swing          m_lows[];    // history of confirmed swing lows, chronological
   GZ_Leg            m_legs[];    // all legs created so far, chronological
   long              m_next_id;
   CGZLogger        *m_logger;

   //--- Pick the opposite-direction origin swing for a newly-confirmed
   //--- target swing S, according to the configured variant. `opposite`
   //--- is m_lows if S is a HIGH, m_highs if S is a LOW. Only ever looks
   //--- at swings already confirmed before S - no lookahead.
   bool PickOrigin(const GZ_Swing &opposite[], const GZ_Swing &S, double current_atr, bool atr_ready, GZ_Swing &origin_out)
     {
      int n = ArraySize(opposite);
      if(n==0)
         return false;

      if(m_variant==GZ_LEG_VARIANT_LAST_SWING)
        {
         origin_out = opposite[n-1];
         return true;
        }

      if(m_variant==GZ_LEG_VARIANT_MIN_DISTANCE)
        {
         int best = 0;
         double bestDist = MathAbs(S.price - opposite[0].price);
         for(int i=1;i<n;i++)
           {
            double d = MathAbs(S.price - opposite[i].price);
            if(d<bestDist) { bestDist = d; best = i; }
           }
         origin_out = opposite[best];
         return true;
        }

      // GZ_LEG_VARIANT_MIN_ATR_DISTANCE: normalize distance by ATR at the
      // time of selection. If ATR is not yet ready, fall back to raw
      // minimum price distance (documented fallback, logged once) rather
      // than fabricating an ATR value.
      if(!atr_ready || current_atr<=0.0)
        {
         if(m_logger!=NULL)
            m_logger.Warning("Leg", "MIN_ATR_DISTANCE requested but ATR not ready yet - falling back to raw price distance for this leg.");
         int best2 = 0;
         double bestDist2 = MathAbs(S.price - opposite[0].price);
         for(int i=1;i<n;i++)
           {
            double d = MathAbs(S.price - opposite[i].price);
            if(d<bestDist2) { bestDist2 = d; best2 = i; }
           }
         origin_out = opposite[best2];
         return true;
        }

      int best3 = 0;
      double bestDist3 = MathAbs(S.price - opposite[0].price) / current_atr;
      for(int i=1;i<n;i++)
        {
         double d = MathAbs(S.price - opposite[i].price) / current_atr;
         if(d<bestDist3) { bestDist3 = d; best3 = i; }
        }
      origin_out = opposite[best3];
      return true;
     }

public:
                     CGZLegEngine(CGZLogger *logger=NULL) { m_logger=logger; m_variant=GZ_LEG_VARIANT_LAST_SWING; m_next_id=1; }

   void              Init(ENUM_GZ_LEG_VARIANT variant)
     {
      m_variant = variant;
      m_next_id = 1;
      ArrayResize(m_highs, 0);
      ArrayResize(m_lows, 0);
      ArrayResize(m_legs, 0);
     }

   ENUM_GZ_LEG_VARIANT Variant() const { return m_variant; }
   int               LegCount() const { return ArraySize(m_legs); }
   GZ_Leg            GetLeg(int i) const { return m_legs[i]; }
   void              SetLeg(int i, const GZ_Leg &leg) { m_legs[i] = leg; }

   //--- Feed one newly-confirmed swing (in confirmation order). Returns
   //--- true and fills `out_index` with the new leg's index in this
   //--- engine's history if a leg was created (an opposite swing already
   //--- existed); returns false if this is the first swing of its kind
   //--- seen so far (no opposite swing to pair it with yet - documented,
   //--- not fabricated).
   bool              Update(const GZ_Swing &S, double current_atr, bool atr_ready, int &out_index)
     {
      bool created = false;
      GZ_Swing origin;

      if(S.direction==GZ_SWING_HIGH)
        {
         if(PickOrigin(m_lows, S, current_atr, atr_ready, origin))
           {
            GZ_Leg leg; leg.Clear();
            leg.id             = m_next_id++;
            leg.direction      = GZ_LEG_BULLISH;
            leg.origin_swing   = origin;
            leg.target_swing   = S;
            leg.variant_used   = m_variant;
            leg.extreme_price  = S.price;
            leg.extreme_time   = S.pivot_time;
            int n = ArraySize(m_legs);
            ArrayResize(m_legs, n+1);
            m_legs[n] = leg;
            out_index = n;
            created = true;
            if(m_logger!=NULL)
               m_logger.Info("Leg", StringFormat("BULLISH leg #%d created origin(LOW)=%.5f@%s target(HIGH)=%.5f@%s",
                             (int)leg.id, origin.price, TimeToString(origin.pivot_time), S.price, TimeToString(S.pivot_time)));
           }
         int nh = ArraySize(m_highs);
         ArrayResize(m_highs, nh+1);
         m_highs[nh] = S;
        }
      else // GZ_SWING_LOW
        {
         if(PickOrigin(m_highs, S, current_atr, atr_ready, origin))
           {
            GZ_Leg leg; leg.Clear();
            leg.id             = m_next_id++;
            leg.direction      = GZ_LEG_BEARISH;
            leg.origin_swing   = origin;
            leg.target_swing   = S;
            leg.variant_used   = m_variant;
            leg.extreme_price  = S.price;
            leg.extreme_time   = S.pivot_time;
            int n = ArraySize(m_legs);
            ArrayResize(m_legs, n+1);
            m_legs[n] = leg;
            out_index = n;
            created = true;
            if(m_logger!=NULL)
               m_logger.Info("Leg", StringFormat("BEARISH leg #%d created origin(HIGH)=%.5f@%s target(LOW)=%.5f@%s",
                             (int)leg.id, origin.price, TimeToString(origin.pivot_time), S.price, TimeToString(S.pivot_time)));
           }
         int nl = ArraySize(m_lows);
         ArrayResize(m_lows, nl+1);
         m_lows[nl] = S;
        }

      if(!created)
         out_index = -1;
      return created;
     }

   //--- Feed one CLOSED bar (M5, same series the swings were built from).
   //--- Updates the running extreme of every still-open leg whose
   //--- target_swing has already confirmed by this bar's time. Skips
   //--- broken legs (frozen) - no lookahead, no post-break mutation.
   void              UpdateBar(const MqlRates &bar)
     {
      int n = ArraySize(m_legs);
      for(int i=0;i<n;i++)
        {
         if(m_legs[i].broken)
            continue;
         if(bar.time < m_legs[i].target_swing.confirmation_time)
            continue;

         if(m_legs[i].direction==GZ_LEG_BULLISH)
           {
            if(bar.high>m_legs[i].extreme_price)
              {
               m_legs[i].extreme_price = bar.high;
               m_legs[i].extreme_time  = bar.time;
              }
           }
         else // BEARISH
           {
            if(bar.low<m_legs[i].extreme_price)
              {
               m_legs[i].extreme_price = bar.low;
               m_legs[i].extreme_time  = bar.time;
              }
           }
        }
     }
  };

#endif // __GZ_LEG_ENGINE_MQH__
