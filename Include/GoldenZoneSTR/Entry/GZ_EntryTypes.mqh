//+------------------------------------------------------------------+
//| GZ_EntryTypes.mqh                                                 |
//| GoldenZone STR - Phase 5 - Entry Engine + Trade Simulator - Types |
//|                                                                    |
//| Shared enums/structs for entry triggering and trade records. This |
//| file contains NO entry-decision logic and NO exit/SL/TP/BE logic  |
//| (Phase 6+). Types only.                                            |
//|                                                                    |
//| DESIGN NOTES (documented per spec Section 26 - the Roadmap        |
//| describes Phase 5 at a feature level, not a field-by-field spec,  |
//| same situation as Phases 3/4):                                     |
//|                                                                    |
//| 1) Entry Fib Ratio. The Roadmap's Trade Record includes a "Fib    |
//|    level" field, which implies the actual entry trigger sits at a |
//|    single specific fib ratio, not the whole watched zone that     |
//|    Phase 4 already tracks (zone_min_ratio/zone_max_ratio, e.g.    |
//|    [0.30,0.90]). GZ_EntryConfig.entry_fib_ratio is that single    |
//|    ratio - a new, explicit, EA-configurable input. It is not      |
//|    clamped to [zone_min_ratio,zone_max_ratio] here (consistent    |
//|    with CGZFibEngine::PriceAtRatio not validating its ratio       |
//|    either) - the caller is responsible for configuring a sensible |
//|    value; the Entry Engine only ever acts on a setup once Phase   |
//|    4 has already confirmed WAITING_ENTRY (price touched the       |
//|    broader zone), so an entry_fib_ratio outside the zone simply   |
//|    means the entry trigger sits deeper/shallower than the zone    |
//|    that gated WAITING_ENTRY - a valid research configuration, not |
//|    an error.                                                       |
//|                                                                    |
//| 2) Initial risk. The Roadmap's Trade Record also lists "Initial   |
//|    risk", which conventionally needs a stop-loss price. SL is     |
//|    explicitly Phase 6 scope (Exit Engine) and is OUT OF SCOPE     |
//|    here (spec Section "OUT OF SCOPE": SL/TP). GZ_Trade.           |
//|    initial_risk is therefore a reserved 0.0 placeholder - DEFERRED|
//|    TO PHASE 6, not fabricated from a guessed stop.                |
//|                                                                    |
//| 3) Spread assumption. Modeled as the historical bar's own spread  |
//|    (MqlRates.spread, in points) observed on the bar that produced |
//|    the fill - i.e. "the spread the dataset actually recorded at   |
//|    entry time", not a separate configurable spread model. A       |
//|    configurable fixed/variable spread model is not requested by   |
//|    the Roadmap for Phase 5 and is left for a later phase if ever  |
//|    needed - documented, not silently added.                       |
//|                                                                    |
//| 4) Slippage assumption. Computed uniformly for every entry model  |
//|    as |fill_price - entry_price| (the configured fib-ratio price).|
//|    This naturally comes out to exactly 0.0 for GZ_ENTRY_LIMIT     |
//|    (a resting limit order fills AT the requested price by         |
//|    definition) without any model-specific special case, and       |
//|    non-zero for the other models where fill_price is the actual   |
//|    observed market price (touched wick / confirming bar's close). |
//+------------------------------------------------------------------+
#ifndef __GZ_ENTRY_TYPES_MQH__
#define __GZ_ENTRY_TYPES_MQH__

#include "..\Leg\GZ_LegTypes.mqh"

//--- Entry trigger model (Roadmap Phase 5) --------------------------------
enum ENUM_GZ_ENTRY_MODEL
  {
   GZ_ENTRY_TOUCH = 0,          // baseline: fire the instant price touches/penetrates the entry level
   GZ_ENTRY_LIMIT,               // resting limit order at the entry level - fills exactly at that price
   GZ_ENTRY_CLOSE_CONFIRMATION,  // N consecutive M5 closes beyond the entry level required
   GZ_ENTRY_M1_CONFIRMATION      // N consecutive M1 closes beyond the entry level required
  };

//+------------------------------------------------------------------+
//| Entry Engine configuration.                                      |
//| confirmation_candles: Roadmap research range 1-3, used only by   |
//|   GZ_ENTRY_CLOSE_CONFIRMATION / GZ_ENTRY_M1_CONFIRMATION.        |
//| penetration_atr_mult: Roadmap research grid 0/0.02/0.05/0.10/0.15|
//|   ATR multiples. 0 = exact touch is sufficient (no buffer).      |
//|   Applied uniformly to every model as "how far beyond the entry  |
//|   level price must move before the model's own trigger condition |
//|   is allowed to fire" (see GZ_EntryEngine.mqh). The ATR value    |
//|   itself is NOT owned here - the Entry Engine is fed the shared  |
//|   ATR already maintained by the Break Engine (Phase 3), the same |
//|   way CGZLegEngine::Update() already consumes it - no duplicate  |
//|   ATR series, one shared deterministic source.                   |
//+------------------------------------------------------------------+
struct GZ_EntryConfig
  {
   ENUM_GZ_ENTRY_MODEL model;
   double              entry_fib_ratio;
   int                 confirmation_candles;
   double              penetration_atr_mult;

   void Default()
     {
      model                 = GZ_ENTRY_TOUCH;
      entry_fib_ratio       = 0.618;
      confirmation_candles  = 1;
      penetration_atr_mult  = 0.0;
     }
  };

//+------------------------------------------------------------------+
//| A single Trade record (Roadmap "Trade Record" fields). Produced  |
//| exactly once per setup that reaches ENTERED (Phase 5's own job   |
//| is only to decide/record ENTRY - no exit/SL/TP/BE fields here,   |
//| see design note 2 above for initial_risk specifically).           |
//+------------------------------------------------------------------+
struct GZ_Trade
  {
   long                 id;
   long                 setup_id;
   datetime             entry_time;
   double               entry_price;       // actual fill price (see design note 4)
   ENUM_GZ_LEG_DIR      direction;
   double               fib_level;         // entry_fib_ratio used for this trade
   ENUM_GZ_ENTRY_MODEL  entry_model;
   double               spread_assumption;   // points, from the historical fill bar (design note 3)
   double               slippage_assumption; // |fill_price - configured entry level price|
   double               initial_risk;        // reserved 0.0 - DEFERRED TO PHASE 6 (design note 2)

   void Clear()
     {
      id                  = 0;
      setup_id            = 0;
      entry_time          = 0;
      entry_price         = 0.0;
      direction           = GZ_LEG_BULLISH;
      fib_level           = 0.0;
      entry_model         = GZ_ENTRY_TOUCH;
      spread_assumption   = 0.0;
      slippage_assumption = 0.0;
      initial_risk        = 0.0;
     }

   string DirectionToString() const { return (direction==GZ_LEG_BULLISH) ? "BULLISH" : "BEARISH"; }

   string EntryModelToString() const
     {
      switch(entry_model)
        {
         case GZ_ENTRY_TOUCH:              return "TOUCH";
         case GZ_ENTRY_LIMIT:              return "LIMIT";
         case GZ_ENTRY_CLOSE_CONFIRMATION: return "CLOSE_CONFIRMATION";
         case GZ_ENTRY_M1_CONFIRMATION:    return "M1_CONFIRMATION";
        }
      return "UNKNOWN";
     }
  };

#endif // __GZ_ENTRY_TYPES_MQH__
