//+------------------------------------------------------------------+
//| GZ_FilterTypes.mqh                                                |
//| GoldenZone STR - Phase 10 - Filter Engine - Types                 |
//|                                                                    |
//| Shared enums/structs for the Filter Engine. This file contains   |
//| NO evaluation logic (see GZ_FilterEngine.mqh) and NO filter        |
//| COMBINATION research (Roadmap Phase 11 - single/two/multi-filter  |
//| sweeps). Types only.                                               |
//|                                                                    |
//| DESIGN NOTES (documented per spec Section 26 - the Roadmap        |
//| describes Phase 10 at a feature level - "هر Filter: PASS/FAIL/    |
//| NOT_AVAILABLE ... NOT_AVAILABLE نباید خودکار PASS شود" / "هر        |
//| Filter: OFF/INCLUDE/EXCLUDE" - not a field-by-field spec, same     |
//| situation as every phase since Phase 3):                          |
//|                                                                    |
//| 1) The 8 filters (Roadmap list: Break Quality, Leg Quality,       |
//|    Volume, Volatility, VWAP, M15 Context, Session, News) fall     |
//|    into two groups given what earlier phases actually built:      |
//|      IMPLEMENTED (real, data-backed evaluation - see               |
//|      GZ_FilterEngine.mqh): Break Quality, Leg Quality, Volume,     |
//|      Volatility, Session.                                          |
//|      RESERVED (always NOT_AVAILABLE - no producer exists anywhere  |
//|      in Phases 1-9): VWAP, M15 Context, News. Each was explicitly  |
//|      listed OUT OF SCOPE in the Phase 1 spec's Section 2 and never |
//|      built by any later phase (M15 structure logic is DEFERRED,   |
//|      no VWAP engine or news/economic-calendar data source exists). |
//|      Per spec Section 3 ("create only the minimal interface/stub  |
//|      required by architecture. Do not implement the later phase   |
//|      itself"), these three are wired into the SAME OFF/INCLUDE/   |
//|      EXCLUDE machinery as the real filters (so no further shape   |
//|      change is needed once a later phase supplies real data), but |
//|      CGZFilterEngine never produces anything but NOT_AVAILABLE    |
//|      for them - DEFERRED, not fabricated from nothing.             |
//|                                                                    |
//| 2) NOT_AVAILABLE must never silently become PASS (explicit Roadmap |
//|    requirement). The combination rule (see GZ_FilterEngine.mqh     |
//|    ::Evaluate()) therefore treats a NOT_AVAILABLE result on any    |
//|    ENABLED (non-OFF) filter as NOT allowing the setup through -    |
//|    it is reported distinctly (never relabeled PASS or FAIL) but    |
//|    gates exactly like a FAIL would. A filter left OFF never gates  |
//|    anything, available or not - this is how the 3 reserved         |
//|    filters stay harmless by default (see EA InpFilter*Mode         |
//|    defaults, all OFF).                                              |
//|                                                                    |
//| 3) INCLUDE/EXCLUDE semantics mirror the SAME convention Phase 1's  |
//|    GZ_SessionProfile.include already uses (see GZ_Config.mqh):     |
//|    INCLUDE keeps a setup only when the filter's underlying         |
//|    condition is met (result==PASS); EXCLUDE keeps a setup only     |
//|    when it is NOT met (result==FAIL) - i.e. EXCLUDE rejects        |
//|    exactly the setups an INCLUDE of the same filter would have     |
//|    kept. One generic OFF/INCLUDE/EXCLUDE mechanism, reused for      |
//|    every filter, rather than a bespoke boolean per filter.          |
//|                                                                    |
//| 4) Thresholds are expressed in ATR multiples (Break Quality, Leg   |
//|    Quality, Volatility) or rolling-average multiples (Volume) -    |
//|    the same "scale with volatility rather than a fixed price/     |
//|    count offset" choice Phase 3's GZ_BreakConfig.buffer_atr_mult   |
//|    already documents. No Roadmap baseline is stated for any of     |
//|    these numbers; defaults are conservative/permissive (documented |
//|    in Default() below), fully overridable via EA input - the same  |
//|    "documented default, not a silently assumed one" pattern used   |
//|    throughout this repo (e.g. GZ_BreakConfig.atr_period=14).       |
//|                                                                    |
//| 5) Evaluation reference time. Break Quality/Leg Quality/Volume/    |
//|    Volatility all measure the setup's Leg at its BREAK_CONFIRMED   |
//|    moment (GZ_Leg.break_time/break_price) - the earliest point a   |
//|    setup's own structural facts are frozen (see GZ_LegTypes.mqh).  |
//|    A setup that never reaches a confirmed break (leg.broken==      |
//|    false) has nothing to measure for those four filters - they     |
//|    report NOT_AVAILABLE for it, same reserved-stub treatment as    |
//|    VWAP/M15/News (design note 1), not a fabricated PASS/FAIL.      |
//|    Session instead uses break_time when available, falling back    |
//|    to the setup's own detected_time otherwise (a session window    |
//|    can always be evaluated once ANY timestamp exists).             |
//+------------------------------------------------------------------+
#ifndef __GZ_FILTER_TYPES_MQH__
#define __GZ_FILTER_TYPES_MQH__

#include "..\Core\GZ_Config.mqh"
#include "..\Setup\GZ_SetupTypes.mqh"

//--- Per-filter mode (Roadmap: "هر Filter: OFF / INCLUDE / EXCLUDE") ---
enum ENUM_GZ_FILTER_MODE
  {
   GZ_FILTER_OFF = 0,
   GZ_FILTER_INCLUDE,
   GZ_FILTER_EXCLUDE
  };

//--- Per-filter outcome (Roadmap: "هر Filter: PASS/FAIL/NOT_AVAILABLE") -
enum ENUM_GZ_FILTER_RESULT
  {
   GZ_FILTER_PASS = 0,
   GZ_FILTER_FAIL,
   GZ_FILTER_NOT_AVAILABLE
  };

//--- The 8 filters, Roadmap Phase 10 order (design note 1) -------------
enum ENUM_GZ_FILTER_ID
  {
   GZ_FILTER_BREAK_QUALITY = 0,
   GZ_FILTER_LEG_QUALITY,
   GZ_FILTER_VOLUME,
   GZ_FILTER_VOLATILITY,
   GZ_FILTER_VWAP,          // reserved - design note 1
   GZ_FILTER_M15_CONTEXT,   // reserved - design note 1
   GZ_FILTER_SESSION,
   GZ_FILTER_NEWS           // reserved - design note 1
  };
#define GZ_FILTER_COUNT 8

string GZFilterIdToString(ENUM_GZ_FILTER_ID id)
  {
   switch(id)
     {
      case GZ_FILTER_BREAK_QUALITY: return "BREAK_QUALITY";
      case GZ_FILTER_LEG_QUALITY:   return "LEG_QUALITY";
      case GZ_FILTER_VOLUME:        return "VOLUME";
      case GZ_FILTER_VOLATILITY:    return "VOLATILITY";
      case GZ_FILTER_VWAP:          return "VWAP";
      case GZ_FILTER_M15_CONTEXT:   return "M15_CONTEXT";
      case GZ_FILTER_SESSION:       return "SESSION";
      case GZ_FILTER_NEWS:          return "NEWS";
     }
   return "UNKNOWN";
  }

string GZFilterResultToString(ENUM_GZ_FILTER_RESULT r)
  {
   switch(r)
     {
      case GZ_FILTER_PASS:          return "PASS";
      case GZ_FILTER_FAIL:          return "FAIL";
      case GZ_FILTER_NOT_AVAILABLE: return "NOT_AVAILABLE";
     }
   return "UNKNOWN";
  }

string GZFilterModeToString(ENUM_GZ_FILTER_MODE m)
  {
   switch(m)
     {
      case GZ_FILTER_OFF:     return "OFF";
      case GZ_FILTER_INCLUDE: return "INCLUDE";
      case GZ_FILTER_EXCLUDE: return "EXCLUDE";
     }
   return "UNKNOWN";
  }

//+------------------------------------------------------------------+
//| Full Filter Engine configuration - one mode per filter plus the   |
//| thresholds the 5 implemented filters need (design note 4). The    |
//| Session filter reuses the SAME GZ_SessionProfile shape Phase 1     |
//| already defined (GZ_Config.mqh) rather than inventing a second     |
//| session concept - the caller decides whether to point it at the    |
//| same window already used for entry/exit or a different one.        |
//+------------------------------------------------------------------+
struct GZ_FilterSetConfig
  {
   ENUM_GZ_FILTER_MODE mode[GZ_FILTER_COUNT];

   int                 atr_period;                  // shared by Break Quality/Leg Quality/Volatility "current" ATR
   double              break_quality_min_atr_mult;   // break distance beyond level, in ATR multiples
   double              leg_quality_min_atr_mult;     // leg size, in ATR multiples

   int                 volume_lookback;              // bars in the trailing tick-volume average
   double              volume_min_mult;               // break bar's tick_volume >= mult * trailing average

   int                 volatility_lookback;           // bars in the trailing ("baseline") ATR average
   double              volatility_min_mult;            // current ATR / baseline ATR must be >= this
   double              volatility_max_mult;            // ... and <= this

   GZ_SessionProfile   session_profile;               // Session filter's own window (design note above)

   void Default()
     {
      for(int i=0;i<GZ_FILTER_COUNT;i++)
         mode[i] = GZ_FILTER_OFF;   // safe default: no filter gates anything until explicitly enabled

      atr_period                  = 14;
      break_quality_min_atr_mult  = 0.10;
      leg_quality_min_atr_mult    = 1.00;

      volume_lookback             = 20;
      volume_min_mult             = 1.00;

      volatility_lookback         = 50;
      volatility_min_mult         = 0.50;
      volatility_max_mult         = 2.00;

      session_profile.Set("FILTER_SESSION","FilterSession",GZ_TIME_BROKER,0,0,23,59,true,true);
     }
  };

//+------------------------------------------------------------------+
//| One filter's evaluated outcome for one setup.                     |
//+------------------------------------------------------------------+
struct GZ_FilterResult
  {
   ENUM_GZ_FILTER_ID     id;
   ENUM_GZ_FILTER_RESULT result;
   double                metric_value;   // the raw measured value (0.0 if NOT_AVAILABLE)

   void Clear()
     {
      id           = GZ_FILTER_BREAK_QUALITY;
      result       = GZ_FILTER_NOT_AVAILABLE;
      metric_value = 0.0;
     }
  };

//+------------------------------------------------------------------+
//| All 8 filters' outcomes for one setup, plus the combined decision |
//| (design notes 2/3 - AND across every ENABLED filter; NOT_AVAILABLE|
//| never auto-passes; OFF filters are skipped entirely).             |
//+------------------------------------------------------------------+
struct GZ_SetupFilterOutcome
  {
   long             setup_id;
   GZ_FilterResult  results[GZ_FILTER_COUNT];
   bool             overall_pass;

   void Clear()
     {
      setup_id = 0;
      for(int i=0;i<GZ_FILTER_COUNT;i++)
         results[i].Clear();
      overall_pass = true; // vacuously true with every filter OFF
     }

   string Summary() const
     {
      string s = "";
      for(int i=0;i<GZ_FILTER_COUNT;i++)
        {
         if(i>0) s += " ";
         s += StringFormat("%s=%s(%.4f)", GZFilterIdToString(results[i].id),
                            GZFilterResultToString(results[i].result), results[i].metric_value);
        }
      s += StringFormat(" OVERALL=%s", overall_pass ? "PASS" : "REJECT");
      return s;
     }
  };

#endif // __GZ_FILTER_TYPES_MQH__
