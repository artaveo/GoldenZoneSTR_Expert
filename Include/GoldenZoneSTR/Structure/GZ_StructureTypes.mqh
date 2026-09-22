//+------------------------------------------------------------------+
//| GZ_StructureTypes.mqh                                            |
//| GoldenZone STR - Phase 2 - M5 Structure Engine - Types           |
//|                                                                   |
//| Shared enums/structs for swing (pivot) detection. This file      |
//| contains NO detection logic and NO leg/break/fib/entry/exit      |
//| logic (Phase 3+). Types only.                                    |
//+------------------------------------------------------------------+
#ifndef __GZ_STRUCTURE_TYPES_MQH__
#define __GZ_STRUCTURE_TYPES_MQH__

//--- Swing direction ---------------------------------------------------
enum ENUM_GZ_SWING_DIR
  {
   GZ_SWING_HIGH = 0,
   GZ_SWING_LOW  = 1
  };

//+------------------------------------------------------------------+
//| A single CONFIRMED swing point.                                  |
//|                                                                   |
//| A swing is only ever produced by the engine once it is           |
//| confirmable, i.e. once `pivot_strength` bars have closed on both |
//| sides of the pivot candle. `detection_time` (when the pivot      |
//| candle itself formed) and `confirmation_time` (when the swing    |
//| became knowable, given no lookahead) are kept distinct on        |
//| purpose - later phases must be able to tell the two apart.       |
//+------------------------------------------------------------------+
struct GZ_Swing
  {
   long              id;                 // sequential id, per engine instance
   ENUM_GZ_SWING_DIR direction;
   double            price;              // pivot high or low price
   datetime          pivot_time;         // bar time (open time) of the pivot candle
   int               pivot_bar_index;    // 0-based index of the pivot candle in the
                                          // sequence of bars fed to the engine
   datetime          detection_time;     // == pivot_time (kept separate for clarity/future use)
   datetime          confirmation_time;  // bar time of the last right-side confirming bar
   int               pivot_strength;     // strength used to confirm this swing

   void Clear()
     {
      id                = 0;
      direction         = GZ_SWING_HIGH;
      price             = 0.0;
      pivot_time        = 0;
      pivot_bar_index    = -1;
      detection_time    = 0;
      confirmation_time = 0;
      pivot_strength    = 0;
     }

   string DirectionToString() const { return (direction==GZ_SWING_HIGH) ? "HIGH" : "LOW"; }
  };

#endif // __GZ_STRUCTURE_TYPES_MQH__
