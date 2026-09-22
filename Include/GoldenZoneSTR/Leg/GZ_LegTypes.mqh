//+------------------------------------------------------------------+
//| GZ_LegTypes.mqh                                                   |
//| GoldenZone STR - Phase 3 - Leg Engine + Break Engine - Types     |
//|                                                                   |
//| Shared enums/structs for leg and break detection. This file      |
//| contains NO detection logic and NO fibonacci/setup-state/entry/  |
//| exit logic (Phase 4+). Types only.                                |
//|                                                                    |
//| DESIGN NOTE (documented per spec Section 26 - "if the             |
//| implementation requires an architectural decision not defined     |
//| here, STOP and ask" - this decision IS documented rather than     |
//| silently assumed, since the Roadmap describes Phase 3 at a        |
//| feature level, not a field-by-field spec like Phase 1):           |
//|                                                                    |
//| A Leg is defined by a pair of consecutive, opposite-direction     |
//| confirmed swings:                                                 |
//|   origin_swing  = the earlier swing (the extreme the move is      |
//|                    away from)                                     |
//|   target_swing  = the later, opposite-direction confirmed swing   |
//|                    (the structural level that must be broken)     |
//| direction:                                                        |
//|   origin=LOW,  target=HIGH -> GZ_LEG_BULLISH (expects a break     |
//|                                above target_swing.price)          |
//|   origin=HIGH, target=LOW  -> GZ_LEG_BEARISH (expects a break     |
//|                                below target_swing.price)          |
//| extreme_price/time: the running furthest excursion in the leg's   |
//|   direction (highest high for BULLISH, lowest low for BEARISH),   |
//|   tracked bar-by-bar from target_swing's confirmation time        |
//|   onward, and frozen the instant the leg is broken.                |
//| leg_size:  |extreme_price - origin_swing.price|                   |
//| duration:  (broken ? break_time : extreme_time) -                 |
//|            origin_swing.confirmation_time                         |
//|                                                                    |
//| Cancellation / selection among multiple simultaneously-open legs  |
//| is explicitly OUT OF SCOPE here - DEFERRED TO PHASE 4 (Setup      |
//| State Machine), which owns setup lifecycle/cancellation reasons.  |
//| Phase 3 only produces candidate Leg records and their break       |
//| state; it does not decide which one is "the" active setup.        |
//+------------------------------------------------------------------+
#ifndef __GZ_LEG_TYPES_MQH__
#define __GZ_LEG_TYPES_MQH__

#include "..\Structure\GZ_StructureTypes.mqh"

//--- Leg direction -------------------------------------------------------
enum ENUM_GZ_LEG_DIR
  {
   GZ_LEG_BULLISH = 0,
   GZ_LEG_BEARISH = 1
  };

//--- Leg Engine origin-selection variant (Roadmap Phase 3) ---------------
enum ENUM_GZ_LEG_VARIANT
  {
   GZ_LEG_VARIANT_LAST_SWING = 0,   // baseline: last confirmed opposite swing
   GZ_LEG_VARIANT_MIN_DISTANCE,     // opposite swing with minimum |price| distance
   GZ_LEG_VARIANT_MIN_ATR_DISTANCE  // opposite swing with minimum ATR-normalized distance
  };

//--- Break Engine mode (Roadmap Phase 3) ----------------------------------
enum ENUM_GZ_BREAK_MODE
  {
   GZ_BREAK_CLOSE = 0,   // baseline: bar close must clear the level
   GZ_BREAK_WICK  = 1    // research variant: bar high/low clearing the level is enough
  };

//+------------------------------------------------------------------+
//| Break Engine configuration.                                      |
//| Buffer is expressed in ATR multiples (Roadmap research grid:     |
//| 0, 0.05, 0.10, 0.15, 0.20, 0.30, 0.50) so it scales with          |
//| volatility rather than being a fixed price offset.                |
//| ATR period is independently configurable (Roadmap research grid: |
//| 5, 10, 14, 20, 30). No baseline ATR period is stated in the       |
//| Roadmap; 14 is used as the conventional default and is fully     |
//| configurable - documented here rather than silently assumed.     |
//+------------------------------------------------------------------+
struct GZ_BreakConfig
  {
   ENUM_GZ_BREAK_MODE mode;
   double             buffer_atr_mult;   // 0 = no buffer
   int                atr_period;

   void Default()
     {
      mode             = GZ_BREAK_CLOSE;
      buffer_atr_mult  = 0.0;
      atr_period       = 14;
     }
  };

//+------------------------------------------------------------------+
//| A single Leg record (Roadmap "Leg Record" fields).                |
//+------------------------------------------------------------------+
struct GZ_Leg
  {
   long              id;
   ENUM_GZ_LEG_DIR   direction;
   GZ_Swing          origin_swing;
   GZ_Swing          target_swing;
   ENUM_GZ_LEG_VARIANT variant_used;

   double            extreme_price;
   datetime          extreme_time;

   bool              broken;
   datetime          break_time;
   double            break_price;
   ENUM_GZ_BREAK_MODE break_mode_used;

   void Clear()
     {
      id               = 0;
      direction        = GZ_LEG_BULLISH;
      origin_swing.Clear();
      target_swing.Clear();
      variant_used     = GZ_LEG_VARIANT_LAST_SWING;
      extreme_price    = 0.0;
      extreme_time     = 0;
      broken           = false;
      break_time       = 0;
      break_price      = 0.0;
      break_mode_used  = GZ_BREAK_CLOSE;
     }

   string DirectionToString() const { return (direction==GZ_LEG_BULLISH) ? "BULLISH" : "BEARISH"; }

   double LegSize() const { return MathAbs(extreme_price - origin_swing.price); }

   long DurationSeconds() const
     {
      datetime endt = broken ? break_time : extreme_time;
      return (long)(endt - origin_swing.confirmation_time);
     }
  };

#endif // __GZ_LEG_TYPES_MQH__
