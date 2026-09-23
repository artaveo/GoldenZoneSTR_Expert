//+------------------------------------------------------------------+
//| GZ_ExperimentTypes.mqh                                            |
//| GoldenZone STR - Phase 9 - Experiment Configuration + Runner -    |
//| Types                                                              |
//|                                                                    |
//| Shared structs for the Experiment Runner. This file contains NO   |
//| execution logic (see GZ_ExperimentRunner.mqh). Types only.        |
//|                                                                    |
//| DESIGN NOTES (documented per spec Section 26 - the Roadmap        |
//| describes Phase 9 at a feature level, same situation as every     |
//| phase since Phase 3):                                              |
//|                                                                    |
//| 1) GZ_ExperimentConfig EMBEDS Phase 2-6's own already-frozen       |
//|    config structs (GZ_BreakConfig, GZ_EntryConfig, GZ_ExitConfig,  |
//|    GZ_TimeConfig, GZ_SessionProfile) wholesale rather than         |
//|    re-flattening their fields into new ones - this repo's already |
//|    established discipline (see GZ_ExitTypes.mqh's own design note |
//|    1: an earlier phase's frozen type is reused, not duplicated).   |
//|    Together with pivot_strength/leg_variant/fib zone ratios/       |
//|    apply_session_filter/force_session_exit (the remaining knobs    |
//|    Phases 2-6 expose as EA inputs, not yet captured in any single  |
//|    struct), this IS the Roadmap's "Full configuration" Result      |
//|    field - one struct that can fully reconstruct a run.            |
//|                                                                    |
//| 2) Modes are a LABEL, not a different code path. The Roadmap lists |
//|    SINGLE/SWEEP/GRID/BATCH as four Experiment modes, but does not  |
//|    specify a parameter/config DSL, and MQL5 has no generics or     |
//|    pointer-to-member - there is no safe way to generically address |
//|    "vary field X of GZ_ExperimentConfig" without hardcoding every  |
//|    possible field. All four modes therefore reduce to the SAME     |
//|    execution primitive - run N already-built GZ_ExperimentConfig   |
//|    records, get N GZ_ExperimentResult records back - and differ    |
//|    ONLY in how the CALLER assembled that N-length array: one       |
//|    dimension varied = SWEEP, a Cartesian product of dimensions =   |
//|    GRID, an arbitrary hand-picked list = BATCH, a single config =  |
//|    SINGLE. ENUM_GZ_EXPERIMENT_MODE exists so a result can RECORD   |
//|    which the caller intended (for the Roadmap's own reporting      |
//|    vocabulary), not to select different runner behavior.           |
//|                                                                    |
//| 3) Experiment ID format. The Roadmap gives exactly one example,    |
//|    "GZ_000001" - CGZExperimentRunner reproduces that literal       |
//|    format (GZ_%06d) via a simple per-instance sequential counter.  |
//|    No global/cross-session persistence is implemented (nothing in  |
//|    Phases 1-8 persists any state across EA re-attachments either)  |
//|    - a fresh CGZExperimentRunner always restarts at GZ_000001,     |
//|    documented, not a silently invented numbering scheme.           |
//|                                                                    |
//| 4) Dataset ID and Data Validation Status are CALLER-SUPPLIED, not  |
//|    computed here. The underlying M1/M5 series (and therefore its   |
//|    own OHLC/timestamp validation - Phase 1's job) does not change  |
//|    across the many experiments a single SWEEP/GRID/BATCH runs      |
//|    against it; only the strategy-layer config changes per          |
//|    experiment. Re-running Phase 1's validator once per experiment  |
//|    would be redundant, wasted work - the caller (which already ran |
//|    Phase 1 validation exactly once) passes its result straight     |
//|    through into every GZ_ExperimentResult instead.                  |
//|                                                                    |
//| 5) Warnings use a FIXED-SIZE array with a count (GZ_TradeJournal's |
//|    own reach_hit[]/reach_time[] pattern - see GZ_JournalTypes.mqh),|
//|    not a dynamic array. GZ_ExperimentResult is copied by value      |
//|    into a results[] array throughout this engine (exactly the same |
//|    pattern GZ_TradeJournal already uses inside CGZJournalEngine's   |
//|    m_journals[]); a dynamic array NESTED inside a struct that is    |
//|    itself stored in another dynamic array is a documented MQL5      |
//|    trouble spot this repo avoids everywhere else, so Phase 9 does   |
//|    not introduce it either.                                         |
//+------------------------------------------------------------------+
#ifndef __GZ_EXPERIMENT_TYPES_MQH__
#define __GZ_EXPERIMENT_TYPES_MQH__

#include "..\Core\GZ_Types.mqh"
#include "..\Core\GZ_Config.mqh"
#include "..\Core\GZ_Constants.mqh"
#include "..\Leg\GZ_LegTypes.mqh"
#include "..\Entry\GZ_EntryTypes.mqh"
#include "..\Exit\GZ_ExitTypes.mqh"
#include "..\Metrics\GZ_MetricsTypes.mqh"

#define GZ_MAX_EXPERIMENT_WARNINGS  8

//--- Experiment mode (Roadmap Phase 9 "Modes" list) - a label only,
//--- see design note 2.
enum ENUM_GZ_EXPERIMENT_MODE
  {
   GZ_EXPERIMENT_SINGLE = 0,
   GZ_EXPERIMENT_SWEEP,
   GZ_EXPERIMENT_GRID,
   GZ_EXPERIMENT_BATCH
  };

//--- Outcome of a RunBatch() call - see GZ_ExperimentRunner.mqh design
//--- note (Roadmap: "do not run a huge Grid at once; research should
//--- be staged").
enum ENUM_GZ_BATCH_STATUS
  {
   GZ_BATCH_OK = 0,
   GZ_BATCH_REJECTED_EMPTY,
   GZ_BATCH_REJECTED_TOO_LARGE
  };

//+------------------------------------------------------------------+
//| Full, reconstructable configuration for one experiment - the      |
//| Roadmap Result's "Full configuration" field (design note 1).      |
//+------------------------------------------------------------------+
struct GZ_ExperimentConfig
  {
   string               symbol;
   datetime             range_start;   // requested research date range (Roadmap Section 19:
   datetime             range_end;     // date range is independent from the session window)

   GZ_TimeConfig        time_config;
   GZ_SessionProfile    session_profile;
   bool                 apply_session_filter;  // Phase 4: pre-entry setup cancellation on session end
   bool                 force_session_exit;    // Phase 6: open-trade force-close on session end

   int                  pivot_strength;        // Phase 2

   ENUM_GZ_LEG_VARIANT  leg_variant;           // Phase 3
   GZ_BreakConfig       break_config;          // Phase 3

   double               fib_zone_min_ratio;    // Phase 4
   double               fib_zone_max_ratio;    // Phase 4

   GZ_EntryConfig       entry_config;          // Phase 5
   GZ_ExitConfig        exit_config;           // Phase 6

   void Default()
     {
      symbol               = "XAUUSD";
      range_start          = 0;
      range_end            = 0;
      time_config.Default();
      session_profile.Set("PROFILE_01", "Session", GZ_TIME_BROKER, 16, 30, 20, 30, true, true);
      apply_session_filter = false;
      force_session_exit   = false;
      pivot_strength       = GZ_DEFAULT_PIVOT_STRENGTH;
      leg_variant          = GZ_LEG_VARIANT_LAST_SWING;
      break_config.Default();
      fib_zone_min_ratio   = GZ_DEFAULT_FIB_ZONE_MIN_RATIO;
      fib_zone_max_ratio   = GZ_DEFAULT_FIB_ZONE_MAX_RATIO;
      entry_config.Default();
      exit_config.Default();
     }
  };

//+------------------------------------------------------------------+
//| One experiment's full result (Roadmap Phase 9 "هر Result باید     |
//| شامل" list: Experiment ID, Dataset ID, Full configuration,        |
//| Strategy version, Date range, Metrics, Warnings, Data validation   |
//| status). Produced exactly once per config by                      |
//| CGZExperimentRunner::RunSingle()/RunBatch() - see                  |
//| GZ_ExperimentRunner.mqh.                                           |
//+------------------------------------------------------------------+
struct GZ_ExperimentResult
  {
   string                     id;                  // "GZ_000001" (design note 3)
   string                     dataset_id;           // caller-supplied (design note 4)
   GZ_ExperimentConfig        config;               // full copy (design note 1)
   string                     strategy_version;     // GZ_STRATEGY_VERSION at compute time

   datetime                   range_start;          // ACTUAL data range covered (first/last bar), not
   datetime                   range_end;             // merely the requested config.range_start/range_end

   GZ_MetricsSummary          metrics;              // Phase 8 summary for this experiment's own trades

   string                     warnings[GZ_MAX_EXPERIMENT_WARNINGS]; // design note 5
   int                        warning_count;

   ENUM_GZ_VALIDATION_STATUS  m1_validation_status; // caller-supplied (design note 4)
   ENUM_GZ_VALIDATION_STATUS  m5_validation_status;

   //--- Extra diagnostic bridging - already-existing Phase 2-6 outputs
   //--- simply surfaced here, not new metrics (helps distinguish e.g.
   //--- "no swings detected at all" from "swings/legs/setups formed but
   //--- no entry ever fired" when trade_count==0 - see NO_TRADES_PRODUCED
   //--- vs NO_SWINGS_DETECTED warnings in GZ_ExperimentRunner.mqh).
   int                        swing_count;
   int                        leg_count;
   int                        setup_count;
   int                        trade_count;
   int                        exit_count;

   void Clear()
     {
      id                   = "";
      dataset_id           = "";
      config.Default();
      strategy_version     = "";
      range_start          = 0;
      range_end            = 0;
      metrics.Clear();
      for(int i=0;i<GZ_MAX_EXPERIMENT_WARNINGS;i++)
         warnings[i] = "";
      warning_count        = 0;
      m1_validation_status = GZ_VAL_UNKNOWN;
      m5_validation_status = GZ_VAL_UNKNOWN;
      swing_count          = 0;
      leg_count            = 0;
      setup_count          = 0;
      trade_count          = 0;
      exit_count           = 0;
     }

   //--- Bounded append - a warning beyond GZ_MAX_EXPERIMENT_WARNINGS is
   //--- silently dropped (documented capacity, same bounded-checkpoint
   //--- philosophy as the Reach Matrix - GZ_JournalTypes.mqh design note
   //--- 1); this build never emits more than a handful of distinct
   //--- warnings per experiment, so the cap is not expected to bind.
   void AddWarning(string w)
     {
      if(warning_count<GZ_MAX_EXPERIMENT_WARNINGS)
        {
         warnings[warning_count] = w;
         warning_count++;
        }
     }

   bool HasWarning(string w) const
     {
      for(int i=0;i<warning_count;i++)
         if(warnings[i]==w)
            return true;
      return false;
     }
  };

#endif // __GZ_EXPERIMENT_TYPES_MQH__
