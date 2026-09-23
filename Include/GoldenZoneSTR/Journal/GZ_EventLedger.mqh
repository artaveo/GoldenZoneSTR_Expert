//+------------------------------------------------------------------+
//| GZ_EventLedger.mqh                                                |
//| GoldenZone STR - Phase 7 - Event Ledger                          |
//|                                                                    |
//| Records the full set of Setup/Entry/Exit facts the Roadmap's      |
//| Event Ledger asks for (see GZ_LedgerTypes.mqh design note). NO    |
//| MAE/MFE logic lives here (see GZ_JournalEngine.mqh).              |
//|                                                                    |
//| CONSTRUCTION MODEL (documented architectural choice, not Roadmap- |
//| specified): unlike CGZJournalEngine, which MUST stream bar-by-bar |
//| because MAE/MFE cannot be reconstructed after the fact, every     |
//| Event Ledger row is fully determined by a GZ_Setup's, GZ_Trade's  |
//| or GZ_TradeExit's OWN final, already-recorded fields (state,      |
//| cancel_reason, fib_active_time, entry/exit time and price, etc.)  |
//| - none of it needs a live bar-by-bar hook. BuildFromFinalState()  |
//| is therefore a deterministic, one-shot POST-HOC pass over the     |
//| already-finished Setup/Entry/Exit engines, called once at the end |
//| of CGZTradeSimulator::Run() - the exact same pattern that file    |
//| already uses for its own "final pass" (GZ_SetupStateMachine::     |
//| MarkExited() propagation, see GZ_TradeSimulator.mqh). This keeps  |
//| the ledger fully testable in isolation (feed it hand-built        |
//| Setup/Entry/Exit state, no bar loop required - see T69-T72) and   |
//| avoids scattering ledger-write calls through Phase 3-6's already- |
//| frozen internals.                                                  |
//+------------------------------------------------------------------+
#ifndef __GZ_EVENT_LEDGER_MQH__
#define __GZ_EVENT_LEDGER_MQH__

#include "GZ_LedgerTypes.mqh"
#include "..\Setup\GZ_SetupTypes.mqh"
#include "..\Setup\GZ_SetupStateMachine.mqh"
#include "..\Entry\GZ_EntryTypes.mqh"
#include "..\Entry\GZ_EntryEngine.mqh"
#include "..\Exit\GZ_ExitTypes.mqh"
#include "..\Exit\GZ_ExitEngine.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZEventLedger
  {
private:
   CGZLogger        *m_logger;
   GZ_LedgerEvent    m_events[];
   long              m_next_id;

   void Add(ENUM_GZ_LEDGER_EVENT_TYPE type, datetime t, long setup_id, long trade_id,
            ENUM_GZ_LEG_DIR dir, string reason, double price)
     {
      GZ_LedgerEvent e; e.Clear();
      e.id         = m_next_id++;
      e.event_type = type;
      e.time       = t;
      e.setup_id   = setup_id;
      e.trade_id   = trade_id;
      e.direction  = dir;
      e.reason     = reason;
      e.price      = price;

      int n = ArraySize(m_events);
      ArrayResize(m_events, n+1);
      m_events[n] = e;

      if(m_logger!=NULL)
         m_logger.Debug("Ledger", StringFormat("Event #%d %s setup=#%d trade=#%d (%s) reason=%s price=%.5f at=%s",
                        (int)e.id, e.EventTypeToString(), (int)setup_id, (int)trade_id,
                        e.DirectionToString(), reason, price, TimeToString(t)));
     }

public:
                     CGZEventLedger(CGZLogger *logger=NULL) { m_logger=logger; m_next_id=1; }

   void              Init()
     {
      m_next_id = 1;
      ArrayResize(m_events, 0);
     }

   int               EventCount() const { return ArraySize(m_events); }
   GZ_LedgerEvent    GetEvent(int i) const { return m_events[i]; }

   int               CountByType(ENUM_GZ_LEDGER_EVENT_TYPE t) const
     {
      int c=0, n=ArraySize(m_events);
      for(int i=0;i<n;i++) if(m_events[i].event_type==t) c++;
      return c;
     }

   void              RecordSetupValid(const GZ_Setup &s)
     {
      Add(GZ_LEDGER_SETUP_VALID, s.fib_active_time, s.id, 0, s.leg.direction, "", 0.0);
     }

   void              RecordSetupCancelled(const GZ_Setup &s)
     {
      Add(GZ_LEDGER_SETUP_CANCELLED, s.terminal_time, s.id, 0, s.leg.direction, s.CancelReasonToString(), 0.0);
     }

   void              RecordSetupInvalidated(const GZ_Setup &s)
     {
      Add(GZ_LEDGER_SETUP_INVALIDATED, s.terminal_time, s.id, 0, s.leg.direction, s.CancelReasonToString(), 0.0);
     }

   void              RecordEntry(const GZ_Trade &tr)
     {
      Add(GZ_LEDGER_ENTRY, tr.entry_time, tr.setup_id, tr.id, tr.direction, "", tr.entry_price);
     }

   void              RecordExit(const GZ_TradeExit &ex)
     {
      Add(GZ_LEDGER_EXIT, ex.exit_time, ex.setup_id, ex.trade_id, ex.direction, ex.ExitReasonToString(), ex.exit_price);
     }

   //--- RESERVED for Phase 10 (Filter Engine) - see GZ_LedgerTypes.mqh
   //--- design note. Never called anywhere in this build (T72 asserts
   //--- CountByType() for both stays 0 after a full run); present now
   //--- only so Phase 10 does not need to change the Event Ledger's
   //--- shape or add a new event-type enum member later.
   void              RecordRejection(long setup_id, datetime t, ENUM_GZ_LEG_DIR dir, string reason)
     {
      Add(GZ_LEDGER_REJECTION, t, setup_id, 0, dir, reason, 0.0);
     }

   void              RecordFilterResult(long setup_id, datetime t, ENUM_GZ_LEG_DIR dir, string filter_name_and_result)
     {
      Add(GZ_LEDGER_FILTER_RESULT, t, setup_id, 0, dir, filter_name_and_result, 0.0);
     }

   //--- Deterministic post-hoc builder - see header. Call once, after
   //--- the full Setup/Entry/Exit replay has finished (CGZTradeSimulator
   //--- ::Run() does this automatically - see that file).
   void              BuildFromFinalState(CGZSetupStateMachine &setup_sm, CGZEntryEngine &entry_engine, CGZExitEngine &exit_engine)
     {
      int ns = setup_sm.SetupCount();
      for(int i=0;i<ns;i++)
        {
         GZ_Setup s = setup_sm.GetSetup(i);

         if(s.fib_active_time!=0)
            RecordSetupValid(s);

         if(s.state==GZ_SETUP_CANCELLED)
           {
            if(s.cancel_reason==GZ_CANCEL_INVALID_PENETRATION || s.cancel_reason==GZ_CANCEL_INVALID_DATA)
               RecordSetupInvalidated(s);
            else
               RecordSetupCancelled(s);
           }
        }

      int nt = entry_engine.TradeCount();
      for(int i=0;i<nt;i++)
         RecordEntry(entry_engine.GetTrade(i));

      int ne = exit_engine.ExitCount();
      for(int i=0;i<ne;i++)
        {
         GZ_TradeExit ex = exit_engine.GetExit(i);
         if(!ex.is_open)
            RecordExit(ex);
        }
     }
  };

#endif // __GZ_EVENT_LEDGER_MQH__
