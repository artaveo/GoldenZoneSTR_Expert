//+------------------------------------------------------------------+
//| GZ_LedgerTypes.mqh                                                |
//| GoldenZone STR - Phase 7 - Event Ledger - Types                   |
//|                                                                    |
//| Shared enum/struct for the Event Ledger. This file contains NO    |
//| event-construction logic (see GZ_EventLedger.mqh). Types only.    |
//|                                                                    |
//| DESIGN NOTE (documented per spec Section 26, same situation as     |
//| every phase since Phase 3 - the Roadmap's Phase 7 Event Ledger     |
//| list is a feature-level bullet list, not a field-by-field spec):   |
//|                                                                    |
//| Roadmap list: "Valid setups, Cancelled setups, Invalidated         |
//| setups, Entries, Exits, Rejection reasons, Filter results".        |
//|                                                                    |
//| - GZ_LEDGER_SETUP_VALID: recorded the instant a setup reaches      |
//|   GZ_SETUP_FIB_ACTIVE (locked leg + active fib zone) - the         |
//|   earliest point Phase 4 itself calls the setup "valid" enough to  |
//|   watch for entries (see GZ_SetupStateMachine.mqh's own log line   |
//|   at that transition). A setup that never gets past LEG_DETECTED/  |
//|   BREAK_CONFIRMED never becomes an entry candidate and is not      |
//|   "valid" in the sense the Roadmap's Event Ledger cares about.     |
//| - GZ_LEDGER_SETUP_CANCELLED vs GZ_LEDGER_SETUP_INVALIDATED: the    |
//|   Roadmap lists these as two DIFFERENT ledger categories, but      |
//|   Phase 4's own GZ_SETUP_CANCELLED is a single terminal state with |
//|   several distinct cancel_reason values (see GZ_SetupTypes.mqh).   |
//|   This file's split is: GZ_CANCEL_INVALID_PENETRATION and          |
//|   GZ_CANCEL_INVALID_DATA (both already named "INVALID_..." by      |
//|   Phase 4/5) -> GZ_LEDGER_SETUP_INVALIDATED; every other reason    |
//|   (OPPOSITE_BREAK, NEW_VALID_SETUP, SESSION_END, DATA_END) ->      |
//|   GZ_LEDGER_SETUP_CANCELLED - an ordinary, non-error termination.  |
//| - GZ_LEDGER_ENTRY / GZ_LEDGER_EXIT: one event per GZ_Trade (Phase  |
//|   5) / per closed GZ_TradeExit (Phase 6).                          |
//| - GZ_LEDGER_REJECTION / GZ_LEDGER_FILTER_RESULT: RESERVED. Neither |
//|   "a rejection" nor "a filter result" has any producer anywhere in |
//|   Phases 1-6 - the Filter Engine that would generate PASS/FAIL/    |
//|   NOT_AVAILABLE filter outcomes (and therefore filter-driven       |
//|   rejections) is explicitly Phase 10 (Roadmap). Per spec Section 3 |
//|   ("create only the minimal interface/stub required by             |
//|    architecture. Do not implement the later phase itself"), these  |
//|   two members exist so the Event Ledger's shape does not need to   |
//|   change again in Phase 10, but CGZEventLedger never constructs    |
//|   either in this build (see T72) - DEFERRED TO PHASE 10, not       |
//|   fabricated from nothing.                                         |
//+------------------------------------------------------------------+
#ifndef __GZ_LEDGER_TYPES_MQH__
#define __GZ_LEDGER_TYPES_MQH__

#include "..\Leg\GZ_LegTypes.mqh"

enum ENUM_GZ_LEDGER_EVENT_TYPE
  {
   GZ_LEDGER_SETUP_VALID = 0,
   GZ_LEDGER_SETUP_CANCELLED,
   GZ_LEDGER_SETUP_INVALIDATED,
   GZ_LEDGER_ENTRY,
   GZ_LEDGER_EXIT,
   GZ_LEDGER_REJECTION,      // reserved; DEFERRED TO PHASE 10 (Filter Engine) - never emitted in this build
   GZ_LEDGER_FILTER_RESULT   // reserved; DEFERRED TO PHASE 10 (Filter Engine) - never emitted in this build
  };

//+------------------------------------------------------------------+
//| One ledger row. `reason` carries the setup cancel reason / exit   |
//| reason string where applicable (empty for ENTRY, which has no     |
//| reason concept). `price` is the most relevant single price for    |
//| the event (fib-zone activation midpoint / entry fill / exit fill  |
//| / 0.0 where not applicable) - kept as a single scalar rather than  |
//| duplicating the full GZ_Setup/GZ_Trade/GZ_TradeExit record, since  |
//| every event already carries setup_id/trade_id to join back to the |
//| full record if needed.                                            |
//+------------------------------------------------------------------+
struct GZ_LedgerEvent
  {
   long                       id;
   ENUM_GZ_LEDGER_EVENT_TYPE  event_type;
   datetime                   time;
   long                       setup_id;
   long                       trade_id;   // 0 if not applicable (e.g. SETUP_VALID/CANCELLED before any entry)
   ENUM_GZ_LEG_DIR            direction;
   string                     reason;     // cancel/exit reason string, or "" where not applicable
   double                     price;      // 0.0 if not applicable

   void Clear()
     {
      id         = 0;
      event_type = GZ_LEDGER_SETUP_VALID;
      time       = 0;
      setup_id   = 0;
      trade_id   = 0;
      direction  = GZ_LEG_BULLISH;
      reason     = "";
      price      = 0.0;
     }

   string DirectionToString() const { return (direction==GZ_LEG_BULLISH) ? "BULLISH" : "BEARISH"; }

   string EventTypeToString() const
     {
      switch(event_type)
        {
         case GZ_LEDGER_SETUP_VALID:       return "SETUP_VALID";
         case GZ_LEDGER_SETUP_CANCELLED:   return "SETUP_CANCELLED";
         case GZ_LEDGER_SETUP_INVALIDATED: return "SETUP_INVALIDATED";
         case GZ_LEDGER_ENTRY:             return "ENTRY";
         case GZ_LEDGER_EXIT:              return "EXIT";
         case GZ_LEDGER_REJECTION:         return "REJECTION";
         case GZ_LEDGER_FILTER_RESULT:     return "FILTER_RESULT";
        }
      return "UNKNOWN";
     }
  };

#endif // __GZ_LEDGER_TYPES_MQH__
