//+------------------------------------------------------------------+
//| GZ_SetupTypes.mqh                                                 |
//| GoldenZone STR - Phase 4 - Setup State Machine - Types            |
//|                                                                    |
//| Shared enums/structs for setup lifecycle tracking. This file     |
//| contains NO state-transition logic and NO entry/exit/simulation  |
//| logic (Phase 5+). Types only.                                    |
//|                                                                    |
//| DESIGN NOTE (documented per spec Section 26, same as Phase 3's    |
//| GZ_LegTypes.mqh note - the Roadmap describes Phase 4 at a         |
//| feature level, not a field-by-field spec):                        |
//|                                                                    |
//| The Roadmap's state list is NO_SETUP -> LEG_DETECTED ->           |
//| BREAK_CONFIRMED -> LEG_LOCKED -> FIB_ACTIVE -> WAITING_ENTRY ->    |
//| ENTERED -> EXITED. NO_SETUP describes the absence of a setup, not |
//| a state a GZ_Setup object itself occupies (a GZ_Setup only exists |
//| once a leg has been detected), so it is not one of the object's   |
//| states below. The Roadmap's cancellation list needs a terminal    |
//| state to land in that isn't ENTERED or EXITED (those mean a trade |
//| was actually taken); GZ_SETUP_CANCELLED is added for that -       |
//| documented here as a necessary, explicit addition, not an         |
//| unstated assumption.                                               |
//|                                                                    |
//| ENTERED and EXITED are defined here because the Roadmap lists     |
//| them as part of the lifecycle, but Phase 4 never assigns them -   |
//| deciding when a setup is actually entered is the Entry Engine's   |
//| job (Phase 5), and exit is the Exit Engine's job (Phase 6). A     |
//| setup that reaches WAITING_ENTRY simply stays there until it is   |
//| cancelled or the data range ends - stub states only, per spec     |
//| Section 3 ("create only the minimal interface/stub required").   |
//|                                                                    |
//| Cancellation reasons implemented in Phase 4: OPPOSITE_BREAK,      |
//| NEW_VALID_SETUP, SESSION_END, DATA_END, INVALID_DATA.             |
//| INVALID_PENETRATION is defined but never assigned here - it       |
//| depends on the Entry Engine's penetration parameter (Phase 5),    |
//| DEFERRED TO PHASE 5.                                               |
//+------------------------------------------------------------------+
#ifndef __GZ_SETUP_TYPES_MQH__
#define __GZ_SETUP_TYPES_MQH__

#include "..\Leg\GZ_LegTypes.mqh"

//--- Setup lifecycle state (per-object; NO_SETUP is not a member -
//--- see design note above) ------------------------------------------
enum ENUM_GZ_SETUP_STATE
  {
   GZ_SETUP_LEG_DETECTED = 0,
   GZ_SETUP_BREAK_CONFIRMED,
   GZ_SETUP_LEG_LOCKED,
   GZ_SETUP_FIB_ACTIVE,
   GZ_SETUP_WAITING_ENTRY,
   GZ_SETUP_ENTERED,     // stub - never assigned before Phase 5 (Entry Engine)
   GZ_SETUP_EXITED,      // stub - never assigned before Phase 6 (Exit Engine)
   GZ_SETUP_CANCELLED    // added terminal state - see design note above
  };

//--- Terminal cancellation reason (Roadmap Phase 4 list) --------------
enum ENUM_GZ_SETUP_CANCEL_REASON
  {
   GZ_CANCEL_NONE = 0,
   GZ_CANCEL_OPPOSITE_BREAK,
   GZ_CANCEL_NEW_VALID_SETUP,
   GZ_CANCEL_SESSION_END,
   GZ_CANCEL_INVALID_PENETRATION,  // reserved; DEFERRED TO PHASE 5, never assigned here
   GZ_CANCEL_DATA_END,
   GZ_CANCEL_INVALID_DATA
  };

//+------------------------------------------------------------------+
//| A single Setup record - one per Leg the state machine has seen.   |
//| Deliberately holds no dynamic-array members (e.g. a precomputed   |
//| fib-level table): the fib grid (ratios) is shared EA-wide          |
//| configuration, not per-setup state, so CGZFibEngine computes a    |
//| level's price on demand from `leg` rather than this struct        |
//| storing a redundant copy of it.                                    |
//+------------------------------------------------------------------+
struct GZ_Setup
  {
   long                       id;
   GZ_Leg                     leg;             // frozen copy of the underlying leg (final once locked)
   ENUM_GZ_SETUP_STATE        state;
   ENUM_GZ_SETUP_CANCEL_REASON cancel_reason;

   double                     zone_min_price;  // price at the configured min fib ratio, once FIB_ACTIVE
   double                     zone_max_price;  // price at the configured max fib ratio, once FIB_ACTIVE

   datetime                   detected_time;   // == leg creation time (LEG_DETECTED)
   datetime                   locked_time;     // LEG_LOCKED reached (0 if not yet)
   datetime                   fib_active_time; // FIB_ACTIVE reached (0 if not yet)
   datetime                   waiting_entry_time; // WAITING_ENTRY reached (0 if never)
   datetime                   terminal_time;   // terminal state reached (0 if still active)

   void Clear()
     {
      id                 = 0;
      leg.Clear();
      state              = GZ_SETUP_LEG_DETECTED;
      cancel_reason       = GZ_CANCEL_NONE;
      zone_min_price      = 0.0;
      zone_max_price      = 0.0;
      detected_time       = 0;
      locked_time         = 0;
      fib_active_time     = 0;
      waiting_entry_time  = 0;
      terminal_time       = 0;
     }

   bool IsTerminal() const
     {
      return state==GZ_SETUP_CANCELLED || state==GZ_SETUP_ENTERED || state==GZ_SETUP_EXITED;
     }

   string StateToString() const
     {
      switch(state)
        {
         case GZ_SETUP_LEG_DETECTED:    return "LEG_DETECTED";
         case GZ_SETUP_BREAK_CONFIRMED: return "BREAK_CONFIRMED";
         case GZ_SETUP_LEG_LOCKED:      return "LEG_LOCKED";
         case GZ_SETUP_FIB_ACTIVE:      return "FIB_ACTIVE";
         case GZ_SETUP_WAITING_ENTRY:   return "WAITING_ENTRY";
         case GZ_SETUP_ENTERED:         return "ENTERED";
         case GZ_SETUP_EXITED:          return "EXITED";
         case GZ_SETUP_CANCELLED:       return "CANCELLED";
        }
      return "UNKNOWN";
     }

   string CancelReasonToString() const
     {
      switch(cancel_reason)
        {
         case GZ_CANCEL_NONE:                return "NONE";
         case GZ_CANCEL_OPPOSITE_BREAK:       return "OPPOSITE_BREAK";
         case GZ_CANCEL_NEW_VALID_SETUP:      return "NEW_VALID_SETUP";
         case GZ_CANCEL_SESSION_END:          return "SESSION_END";
         case GZ_CANCEL_INVALID_PENETRATION:  return "INVALID_PENETRATION";
         case GZ_CANCEL_DATA_END:             return "DATA_END";
         case GZ_CANCEL_INVALID_DATA:         return "INVALID_DATA";
        }
      return "UNKNOWN";
     }
  };

#endif // __GZ_SETUP_TYPES_MQH__
