//+------------------------------------------------------------------+
//| GZ_Constants.mqh                                                  |
//| GoldenZone STR - Phase 1 - Constants                              |
//+------------------------------------------------------------------+
#ifndef __GZ_CONSTANTS_MQH__
#define __GZ_CONSTANTS_MQH__

#define GZ_SECONDS_PER_MINUTE   60
#define GZ_SECONDS_PER_HOUR     3600
#define GZ_SECONDS_PER_DAY      86400

#define GZ_SPACING_M1_SECONDS   60
#define GZ_SPACING_M5_SECONDS   300
#define GZ_SPACING_M15_SECONDS  900

// New York standard/daylight UTC offsets (hours). Negative = behind UTC.
#define GZ_NY_STD_OFFSET_HOURS  (-5)
#define GZ_NY_DST_OFFSET_HOURS  (-4)

// US DST transition anchor: 2:00 AM local wall-clock time.
#define GZ_DST_TRANSITION_HOUR  2

#define GZ_PROJECT_VERSION      "GZ-P1-SPEC v1.0"

// Phase 2 - M5 Structure Engine: baseline pivot strength per roadmap.
// Research variants (1..5) are exposed as an EA input, not hard-coded.
#define GZ_DEFAULT_PIVOT_STRENGTH  2
#define GZ_PROJECT_VERSION_P2      "GZ-P2-ROADMAP v1.0"

// Phase 3 - Leg Engine + Break Engine.
// Baseline break mode = CLOSE (roadmap); WICK is the research variant.
// Break buffer baseline = 0 ATR; research grid: 0.05/0.10/0.15/0.20/0.30/0.50.
// ATR period: no explicit baseline stated in the roadmap - 14 used as the
// conventional default (documented, not silently assumed); research grid:
// 5/10/14/20/30, exposed as EA inputs, not hard-coded.
#define GZ_DEFAULT_BREAK_BUFFER_ATR  0.0
#define GZ_DEFAULT_ATR_PERIOD        14
#define GZ_PROJECT_VERSION_P3        "GZ-P3-ROADMAP v1.0"

// Phase 4 - Fibonacci Engine + Setup State Machine.
// Research levels: 0.30-0.90 grid, including 0.78, architecture extensible
// to 0.01 increments (Roadmap). The watched "zone" for WAITING_ENTRY is the
// price interval spanned by [min,max] of that grid; no single baseline
// ratio is stated in the Roadmap for the zone bounds themselves, so the
// grid's own min/max are used directly - documented, not silently assumed.
#define GZ_DEFAULT_FIB_ZONE_MIN_RATIO  0.30
#define GZ_DEFAULT_FIB_ZONE_MAX_RATIO  0.90
#define GZ_PROJECT_VERSION_P4          "GZ-P4-ROADMAP v1.0"

// Phase 5 - Entry Engine + Historical Trade Simulator.
// Baseline entry model = TOUCH (roadmap). entry_fib_ratio: no explicit
// roadmap baseline stated for the single trigger level within the watched
// zone - 0.618 used as the conventional default (documented, not silently
// assumed; see GZ_EntryTypes.mqh design note 1), fully configurable.
// Confirmation candles: research range 1-3 (roadmap). Penetration baseline
// = 0 ATR; research grid: 0.02/0.05/0.10/0.15 (roadmap).
#define GZ_DEFAULT_ENTRY_FIB_RATIO         0.618
#define GZ_DEFAULT_CONFIRMATION_CANDLES    1
#define GZ_DEFAULT_ENTRY_PENETRATION_ATR   0.0
#define GZ_PROJECT_VERSION_P5              "GZ-P5-ROADMAP v1.0"

#endif // __GZ_CONSTANTS_MQH__
