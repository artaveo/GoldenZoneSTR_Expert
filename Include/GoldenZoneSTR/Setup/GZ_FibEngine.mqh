//+------------------------------------------------------------------+
//| GZ_FibEngine.mqh                                                  |
//| GoldenZone STR - Phase 4 - Fibonacci Engine                      |
//|                                                                    |
//| Bullish: 0% = Leg High (leg.extreme_price), 100% = Leg Origin Low |
//|          (leg.origin_swing.price).                                 |
//| Bearish: 0% = Leg Low (leg.extreme_price), 100% = Leg Origin High |
//|          (leg.origin_swing.price).                                 |
//| (Matches the Roadmap's Fibonacci section exactly - Phase 3's      |
//| GZ_Leg already names these the same way: extreme_price is the     |
//| leg's own high/low, origin_swing.price is the Leg Origin.)         |
//|                                                                    |
//| A Fibonacci level is computed on demand from a (locked) Leg,      |
//| rather than precomputed and stored, because the set of ratios to  |
//| compute (Roadmap: 0.30-0.90 grid, including 0.78, extensible to   |
//| 0.01 increments) is shared EA-wide research configuration, not    |
//| per-setup state - see GZ_SetupTypes.mqh's design note.             |
//|                                                                    |
//| Stateless by design: no instance state, so these are declared     |
//| static and any instance may be used interchangeably - consistent  |
//| with "Strategy Core reusable by Research and future Execution     |
//| Adapters" (Roadmap Phase 17).                                      |
//+------------------------------------------------------------------+
#ifndef __GZ_FIB_ENGINE_MQH__
#define __GZ_FIB_ENGINE_MQH__

#include "..\Leg\GZ_LegTypes.mqh"

class CGZFibEngine
  {
public:
   //--- Price at a given fib ratio for a (locked) leg. `ratio` is not
   //--- restricted to [0,1] - callers may pass values outside that
   //--- range for future extension levels; this function does not
   //--- validate or clamp, it only computes.
   static double PriceAtRatio(const GZ_Leg &leg, double ratio)
     {
      if(leg.direction==GZ_LEG_BULLISH)
         return leg.extreme_price - ratio*(leg.extreme_price - leg.origin_swing.price);
      else // GZ_LEG_BEARISH
         return leg.extreme_price + ratio*(leg.origin_swing.price - leg.extreme_price);
     }

   //--- True if `price` lies within the CLOSED price interval spanned
   //--- by [min_ratio, max_ratio] (order-independent w.r.t. which ratio
   //--- is numerically larger - handles both leg directions correctly).
   static bool IsPriceInZone(const GZ_Leg &leg, double min_ratio, double max_ratio, double price)
     {
      double pA = PriceAtRatio(leg, min_ratio);
      double pB = PriceAtRatio(leg, max_ratio);
      double lo = MathMin(pA, pB);
      double hi = MathMax(pA, pB);
      return (price>=lo && price<=hi);
     }

   //--- True if the bar's [low,high] range overlaps the zone at all
   //--- (standard interval-overlap test) - used to detect "price has
   //--- entered the watched zone on this bar" without requiring the
   //--- bar's close specifically to be inside it.
   static bool DoesBarTouchZone(const GZ_Leg &leg, double min_ratio, double max_ratio, const MqlRates &bar)
     {
      double pA = PriceAtRatio(leg, min_ratio);
      double pB = PriceAtRatio(leg, max_ratio);
      double lo = MathMin(pA, pB);
      double hi = MathMax(pA, pB);
      return (bar.low<=hi && bar.high>=lo);
     }
  };

#endif // __GZ_FIB_ENGINE_MQH__
