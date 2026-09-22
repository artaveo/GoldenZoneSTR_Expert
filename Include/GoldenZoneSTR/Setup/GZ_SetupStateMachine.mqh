//+------------------------------------------------------------------+
//| GZ_SetupStateMachine.mqh                                          |
//| GoldenZone STR - Phase 4 - Setup State Machine                   |
//|                                                                    |
//| Drives GZ_Setup lifecycle from Leg/Break Engine (Phase 3) events  |
//| and bar/session data. Owns cancellation among the multiple         |
//| simultaneously-open legs that Phase 3 explicitly left unresolved  |
//| (see GZ_LegTypes.mqh's design note): this is exactly that          |
//| resolution - at most one non-terminal setup per direction is ever |
//| left standing after OnLegCreated() runs (a fresher same-direction |
//| leg cancels the older one; an opposite-direction break cancels    |
//| whatever is still open on the other side).                        |
//|                                                                    |
//| NO entry/exit/simulation logic lives here (Phase 5+) - a setup    |
//| that reaches WAITING_ENTRY simply stays there until cancelled or  |
//| the data range ends.                                               |
//|                                                                    |
//| Call order per bar (see Expert file), mirroring Phase 3's         |
//| Leg/Break call order:                                              |
//|   1. leg_engine.Update(swing,...)   -> if a new leg is created,   |
//|      call OnLegCreated(leg) here                                  |
//|   2. leg_engine.UpdateBar(bar); break_engine.OnBar(bar)           |
//|   3. break_engine.CheckBreak(leg,bar) -> if it returns true,      |
//|      call OnLegBroken(leg) here                                   |
//|   4. this.OnBar(bar, inside_session, has_session) for every bar,  |
//|      regardless of whether anything broke on it                  |
//|   5. after the last bar: this.OnDataEnd(last_bar_time)            |
//| This ordering means a setup can be created, locked (via a break   |
//| on the very next opposite swing's target) and enter WAITING_ENTRY |
//| within the same OnBar() call that produced the triggering event - |
//| a deliberate, documented cascade (see GZ_SetupTypes.mqh), not an  |
//| accident of call order.                                            |
//+------------------------------------------------------------------+
#ifndef __GZ_SETUP_STATE_MACHINE_MQH__
#define __GZ_SETUP_STATE_MACHINE_MQH__

#include "GZ_SetupTypes.mqh"
#include "GZ_FibEngine.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZSetupStateMachine
  {
private:
   GZ_Setup          m_setups[];
   long              m_next_id;
   double            m_zone_min_ratio;
   double            m_zone_max_ratio;
   CGZLogger        *m_logger;

   int FindByLegId(long leg_id) const
     {
      int n = ArraySize(m_setups);
      for(int i=0;i<n;i++)
         if(m_setups[i].leg.id==leg_id)
            return i;
      return -1;
     }

   void CancelSetup(int idx, ENUM_GZ_SETUP_CANCEL_REASON reason, datetime t)
     {
      if(idx<0 || idx>=ArraySize(m_setups))
         return;
      if(m_setups[idx].IsTerminal())
         return; // never override an existing terminal outcome
      m_setups[idx].state         = GZ_SETUP_CANCELLED;
      m_setups[idx].cancel_reason = reason;
      m_setups[idx].terminal_time = t;
      if(m_logger!=NULL)
         m_logger.Info("Setup", StringFormat("Setup #%d (%s) CANCELLED reason=%s at=%s",
                       (int)m_setups[idx].id, m_setups[idx].leg.DirectionToString(),
                       m_setups[idx].CancelReasonToString(), TimeToString(t)));
     }

public:
                     CGZSetupStateMachine(CGZLogger *logger=NULL)
     { m_logger=logger; m_next_id=1; m_zone_min_ratio=0.30; m_zone_max_ratio=0.90; }

   void              Init(double zone_min_ratio, double zone_max_ratio)
     {
      m_next_id        = 1;
      m_zone_min_ratio = zone_min_ratio;
      m_zone_max_ratio = zone_max_ratio;
      ArrayResize(m_setups, 0);
     }

   int               SetupCount() const { return ArraySize(m_setups); }
   GZ_Setup          GetSetup(int i) const { return m_setups[i]; }

   int               CountByState(ENUM_GZ_SETUP_STATE st) const
     {
      int c=0, n=ArraySize(m_setups);
      for(int i=0;i<n;i++) if(m_setups[i].state==st) c++;
      return c;
     }

   int               CountTerminalByReason(ENUM_GZ_SETUP_CANCEL_REASON reason) const
     {
      int c=0, n=ArraySize(m_setups);
      for(int i=0;i<n;i++) if(m_setups[i].state==GZ_SETUP_CANCELLED && m_setups[i].cancel_reason==reason) c++;
      return c;
     }

   //--- Feed a newly-created Leg (from CGZLegEngine.Update()). Cancels
   //--- any still-open setup sharing the same direction (NEW_VALID_
   //--- SETUP), then creates a new setup in LEG_DETECTED. Returns the
   //--- new setup's index.
   int               OnLegCreated(const GZ_Leg &leg)
     {
      int n = ArraySize(m_setups);
      for(int i=0;i<n;i++)
        {
         if(m_setups[i].IsTerminal())
            continue;
         if(m_setups[i].leg.direction==leg.direction)
            CancelSetup(i, GZ_CANCEL_NEW_VALID_SETUP, leg.target_swing.confirmation_time);
        }

      GZ_Setup s; s.Clear();
      s.id            = m_next_id++;
      s.leg           = leg;
      s.state         = GZ_SETUP_LEG_DETECTED;
      s.detected_time = leg.target_swing.confirmation_time;

      ArrayResize(m_setups, n+1);
      m_setups[n] = s;
      if(m_logger!=NULL)
         m_logger.Debug("Setup", StringFormat("Setup #%d (%s) LEG_DETECTED at=%s",
                        (int)s.id, s.leg.DirectionToString(), TimeToString(s.detected_time)));
      return n;
     }

   //--- Feed a Leg the instant CGZBreakEngine.CheckBreak() confirms its
   //--- break. Locks the matching setup and activates its fib zone in
   //--- one same-bar cascade (see header note), then cancels any still-
   //--- open opposite-direction setup (OPPOSITE_BREAK).
   void              OnLegBroken(const GZ_Leg &broken_leg)
     {
      int idx = FindByLegId(broken_leg.id);
      if(idx>=0 && !m_setups[idx].IsTerminal())
        {
         m_setups[idx].leg = broken_leg;

         m_setups[idx].state = GZ_SETUP_BREAK_CONFIRMED;
         if(m_logger!=NULL)
            m_logger.Debug("Setup", StringFormat("Setup #%d BREAK_CONFIRMED at=%s",
                           (int)m_setups[idx].id, TimeToString(broken_leg.break_time)));

         m_setups[idx].state       = GZ_SETUP_LEG_LOCKED;
         m_setups[idx].locked_time = broken_leg.break_time;

         m_setups[idx].zone_min_price = CGZFibEngine::PriceAtRatio(broken_leg, m_zone_min_ratio);
         m_setups[idx].zone_max_price = CGZFibEngine::PriceAtRatio(broken_leg, m_zone_max_ratio);

         m_setups[idx].state           = GZ_SETUP_FIB_ACTIVE;
         m_setups[idx].fib_active_time = broken_leg.break_time;
         if(m_logger!=NULL)
            m_logger.Info("Setup", StringFormat("Setup #%d (%s) LEG_LOCKED->FIB_ACTIVE zone=[%.5f,%.5f] at=%s",
                          (int)m_setups[idx].id, m_setups[idx].leg.DirectionToString(),
                          MathMin(m_setups[idx].zone_min_price,m_setups[idx].zone_max_price),
                          MathMax(m_setups[idx].zone_min_price,m_setups[idx].zone_max_price),
                          TimeToString(broken_leg.break_time)));
        }

      int n = ArraySize(m_setups);
      for(int i=0;i<n;i++)
        {
         if(m_setups[i].IsTerminal())
            continue;
         if(m_setups[i].leg.direction!=broken_leg.direction)
            CancelSetup(i, GZ_CANCEL_OPPOSITE_BREAK, broken_leg.break_time);
        }
     }

   //--- Feed one bar, in chronological order, after leg/break
   //--- processing for that bar. `has_session` = a session profile was
   //--- configured at all; if false, SESSION_END never fires. Advances
   //--- FIB_ACTIVE setups to WAITING_ENTRY the first time price touches
   //--- the configured zone.
   void              OnBar(const MqlRates &bar, bool inside_session, bool has_session)
     {
      int n = ArraySize(m_setups);
      for(int i=0;i<n;i++)
        {
         if(m_setups[i].IsTerminal())
            continue;

         if(m_setups[i].state==GZ_SETUP_FIB_ACTIVE)
           {
            if(CGZFibEngine::DoesBarTouchZone(m_setups[i].leg, m_zone_min_ratio, m_zone_max_ratio, bar))
              {
               m_setups[i].state              = GZ_SETUP_WAITING_ENTRY;
               m_setups[i].waiting_entry_time = bar.time;
               if(m_logger!=NULL)
                  m_logger.Info("Setup", StringFormat("Setup #%d (%s) FIB_ACTIVE->WAITING_ENTRY at=%s",
                                (int)m_setups[i].id, m_setups[i].leg.DirectionToString(), TimeToString(bar.time)));
              }
           }

         if(has_session && !inside_session)
            CancelSetup(i, GZ_CANCEL_SESSION_END, bar.time);
        }
     }

   //--- Cancel every still-open setup once the loaded data range ends. ---
   void              OnDataEnd(datetime last_time)
     {
      int n = ArraySize(m_setups);
      for(int i=0;i<n;i++)
         if(!m_setups[i].IsTerminal())
            CancelSetup(i, GZ_CANCEL_DATA_END, last_time);
     }

   //--- Reserved hook for a caller that detects a bar touching an
   //--- active setup is itself invalid. Not invoked anywhere in this
   //--- diagnostic build, since Phase 1's Data Validator already
   //--- filters malformed bars upstream of this whole pipeline - kept
   //--- as an explicit interface point rather than silently omitted.
   void              CancelForInvalidData(long setup_id, datetime t)
     {
      int n = ArraySize(m_setups);
      for(int i=0;i<n;i++)
         if(m_setups[i].id==setup_id)
           {
            CancelSetup(i, GZ_CANCEL_INVALID_DATA, t);
            return;
           }
     }
  };

#endif // __GZ_SETUP_STATE_MACHINE_MQH__
