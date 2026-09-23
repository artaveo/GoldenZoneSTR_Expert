//+------------------------------------------------------------------+
//| GZ_FilterComboTypes.mqh                                           |
//| GoldenZone STR - Phase 11 - Filter Combination Research - Types   |
//|                                                                    |
//| Shared enums/structs for the Filter Combination engine. This file |
//| contains NO evaluation/sweep logic (see GZ_FilterComboEngine.mqh).|
//| Types only - same split every other phase in this repo already    |
//| uses (GZ_FilterTypes.mqh/GZ_FilterEngine.mqh,                     |
//| GZ_ExperimentTypes.mqh/GZ_ExperimentRunner.mqh, etc.).             |
//|                                                                    |
//| DESIGN NOTES (documented per spec Section 26 - the Roadmap        |
//| describes Phase 11 at a feature level - "R11-A Single Filter",    |
//| "R11-B Two-Filter: <named pairs> و ترکیبات قابل توجیه دیگر",       |
//| "R11-C Multi-Filter محدود، فقط بر اساس نتایج مراحل قبلی",          |
//| "تمام Configurationها باید قابل بازسازی باشند" - not a             |
//| field-by-field spec, same situation as every phase since Phase 3):|
//|                                                                    |
//| 1) Phase 11 is a SWEEP over Phase 10's own CGZFilterEngine, not a |
//|    new evaluation mechanism. A "combination" is nothing more than |
//|    one more GZ_FilterSetConfig (Phase 10's own type - see          |
//|    GZ_FilterTypes.mqh) with a chosen subset of filters turned      |
//|    INCLUDE and the rest left OFF, evaluated with the EXACT SAME    |
//|    per-setup CGZFilterEngine::Evaluate() -> journal-index-aligned  |
//|    mask -> CGZMetricsEngine::ComputeFiltered() pipeline             |
//|    GoldenZoneSTR_Research.mq5's Phase 10 block already uses (see   |
//|    GZ_FilterComboEngine.mqh). This mirrors GZ_ExperimentTypes.mqh's|
//|    own design note 2 ("modes are a label, not a different code     |
//|    path") - R11-A/B/C are three ways of BUILDING the list of       |
//|    GZ_FilterSetConfig requests to run, not three execution engines.|
//|                                                                    |
//| 2) Re-running the full Phase 2-9 pipeline per combination would be |
//|    wasted, incorrect-by-design work: filters are POST-HOC masks    |
//|    over an already-final setup/trade population (Phase 10's own    |
//|    header note) - the underlying swings/legs/setups/trades never   |
//|    change across a filter sweep, only which of them are counted.   |
//|    GZ_FilterComboResult therefore stores metrics for the FILTERED  |
//|    population only (metrics_with) plus a WITH/WITHOUT diff         |
//|    (diagnostics, reusing Phase 8's own GZ_FilterDiagnostics shape  |
//|    unchanged) against a single caller-supplied unfiltered baseline -|
//|    not a second full metrics summary; the unfiltered baseline is   |
//|    identical for every combination in one sweep and is computed    |
//|    exactly once by the caller (mirrors GZ_ExperimentTypes.mqh      |
//|    design note 4's "computed once, passed through" convention for  |
//|    Phase 1 validation across a SWEEP/GRID/BATCH).                  |
//|                                                                    |
//| 3) Reconstructability (Roadmap: "تمام Configurationها باید          |
//|    بازسازی باشند"). GZ_FilterComboResult.config is the FULL         |
//|    GZ_FilterSetConfig actually evaluated (every mode[]/threshold),  |
//|    copied by value - the same "Full configuration" field pattern   |
//|    GZ_ExperimentResult.config already established (Phase 9 design  |
//|    note 1). filter_ids[]/filter_count is a redundant, convenience  |
//|    summary of exactly which filters config.mode[] has turned on -  |
//|    it never needs to be trusted on its own; config is authoritative|
//|    and can always be re-evaluated byte-for-byte via                |
//|    CGZFilterEngine::Evaluate() (see T114/T116, GZ_TestHarness.mqh).|
//|                                                                    |
//| 4) Reserved filters (VWAP/M15 Context/News) are DEFERRED, not       |
//|    fabricated (GZ_FilterTypes.mqh design note 1). Roadmap R11-B's   |
//|    own example list names VWAP/M15-involving pairs ("Break Quality |
//|    x VWAP", "Volume x VWAP", "VWAP x M15") - the combination        |
//|    BUILDER (GZ_FilterComboEngine.mqh) still knows how to construct  |
//|    those requests (architecture stays extensible per spec Section  |
//|    3), but never RUNS one by default (include_reserved defaults    |
//|    false everywhere) because a reserved filter is always            |
//|    NOT_AVAILABLE and NOT_AVAILABLE never silently auto-passes        |
//|    (Phase 10 design note 2) - enabling one deterministically         |
//|    rejects every setup, which is a documented, not a discovered,    |
//|    fact about this build and would only waste a batch slot on a     |
//|    result that carries zero research information until a later      |
//|    phase supplies real VWAP/M15/news data. reserved_filter_used     |
//|    and the RESERVED_FILTER_ALWAYS_REJECTS warning flag any combo    |
//|    that DOES enable one (e.g. via include_reserved=true) so this    |
//|    is diagnosable, never silently misreported as a real result.     |
//|                                                                    |
//| 5) R11-C "محدود" (limited) selection rule. The Roadmap gives no      |
//|    formula for which filters graduate into a multi-filter combo -   |
//|    only that the choice must come "فقط بر اساس نتایج مراحل قبلی"     |
//|    (only from previous stages' results). GZ_FilterComboEngine.mqh's |
//|    BuildR11CMultiFilterRequests() therefore ranks R11-A's own        |
//|    single-filter results (implemented filters only - design note 4  |
//|    applies here too: a reserved filter's single-filter result is a  |
//|    trivial all-reject and is excluded from ranking, not treated as  |
//|    a winner) by expectancy_delta descending, ties broken by         |
//|    ENUM_GZ_FILTER_ID ascending for full determinism (T115), and      |
//|    builds ONE combo per size from 3 up to top_n (bounded, default    |
//|    top_n=4 -> at most 2 combos: top-3 and top-4) - "based only on     |
//|    previous results", deterministic, and explicitly capped rather    |
//|    than a combinatorial explosion (mirrors the Roadmap's own Phase   |
//|    9 rule "از Grid عظیم همزمان استفاده نشود").                        |
//+------------------------------------------------------------------+
#ifndef __GZ_FILTER_COMBO_TYPES_MQH__
#define __GZ_FILTER_COMBO_TYPES_MQH__

#include "GZ_FilterTypes.mqh"
#include "..\Metrics\GZ_MetricsTypes.mqh"

#define GZ_FILTER_COMBO_MAX_FILTERS   GZ_FILTER_COUNT   // a combo can name at most every filter (8)
#define GZ_FILTER_COMBO_MAX_WARNINGS  4

//--- Which Roadmap research stage produced a given combo - a LABEL only,
//--- see design note 1: every stage runs through the identical execution
//--- primitive, exactly like ENUM_GZ_EXPERIMENT_MODE (GZ_ExperimentTypes.mqh
//--- design note 2).
enum ENUM_GZ_FILTER_COMBO_STAGE
  {
   GZ_COMBO_R11A_SINGLE = 0,
   GZ_COMBO_R11B_TWO,
   GZ_COMBO_R11C_MULTI
  };

string GZFilterComboStageToString(ENUM_GZ_FILTER_COMBO_STAGE s)
  {
   switch(s)
     {
      case GZ_COMBO_R11A_SINGLE: return "R11-A_SINGLE";
      case GZ_COMBO_R11B_TWO:    return "R11-B_TWO";
      case GZ_COMBO_R11C_MULTI:  return "R11-C_MULTI";
     }
   return "UNKNOWN";
  }

//--- Outcome of a RunBatch() call - mirrors ENUM_GZ_BATCH_STATUS
//--- (GZ_ExperimentTypes.mqh) exactly, kept as its OWN enum rather than a
//--- shared one so the Filter module does not need to depend on the
//--- Experiment module (this repo's existing layering: Filter/ already
//--- stands alone from Experiment/ - see GZ_FilterEngine.mqh's own
//--- include list, which never reaches into Experiment/).
enum ENUM_GZ_FILTER_COMBO_BATCH_STATUS
  {
   GZ_COMBO_BATCH_OK = 0,
   GZ_COMBO_BATCH_REJECTED_EMPTY,
   GZ_COMBO_BATCH_REJECTED_TOO_LARGE
  };

//+------------------------------------------------------------------+
//| One combination REQUEST - a (stage, human label, full filter       |
//| config) tuple. Builders (BuildR11A.../BuildR11B.../BuildR11C...,   |
//| see GZ_FilterComboEngine.mqh) fill an array of these; RunBatch()    |
//| executes each one into a GZ_FilterComboResult. Kept as a separate  |
//| lightweight struct (not GZ_FilterComboResult itself) so a caller    |
//| can inspect/filter/reorder the planned batch before spending any    |
//| computation on it.                                                  |
//+------------------------------------------------------------------+
struct GZ_FilterComboRequest
  {
   ENUM_GZ_FILTER_COMBO_STAGE stage;
   string                     label;
   GZ_FilterSetConfig         config;

   void Clear()
     {
      stage = GZ_COMBO_R11A_SINGLE;
      label = "";
      config.Default();
     }
  };

//+------------------------------------------------------------------+
//| One combination's full result (design notes 1-4). "تمام             |
//| Configurationها باید قابل بازسازی باشند" (Roadmap) - config is the   |
//| authoritative, reconstructable record; everything else is a          |
//| convenience summary derived from it plus the WITH-filter population. |
//+------------------------------------------------------------------+
struct GZ_FilterComboResult
  {
   string                       id;               // "R11_000001" (mirrors GZ_ExperimentResult.id format/design note 3, GZ_ExperimentTypes.mqh)
   ENUM_GZ_FILTER_COMBO_STAGE   stage;
   string                       label;             // e.g. "BREAK_QUALITY" or "BREAK_QUALITY+VOLUME"
   GZ_FilterSetConfig           config;            // full, reconstructable filter configuration (design note 3)

   int                          filter_count;      // number of ENABLED (non-OFF) filters in config
   ENUM_GZ_FILTER_ID            filter_ids[GZ_FILTER_COMBO_MAX_FILTERS]; // which filters are enabled, ascending id order

   GZ_FilterDiagnostics         diagnostics;       // WITH/WITHOUT diff vs the caller-supplied unfiltered baseline (design note 2)
   GZ_MetricsSummary            metrics_with;      // full filtered-population metrics summary (design note 2)

   bool                         reserved_filter_used; // true if a RESERVED filter (VWAP/M15/News) is enabled (design note 4)
   string                       warnings[GZ_FILTER_COMBO_MAX_WARNINGS];
   int                          warning_count;

   void Clear()
     {
      id                   = "";
      stage                = GZ_COMBO_R11A_SINGLE;
      label                = "";
      config.Default();
      filter_count         = 0;
      for(int i=0;i<GZ_FILTER_COMBO_MAX_FILTERS;i++)
         filter_ids[i] = GZ_FILTER_BREAK_QUALITY;
      diagnostics.Clear();
      metrics_with.Clear();
      reserved_filter_used = false;
      for(int i=0;i<GZ_FILTER_COMBO_MAX_WARNINGS;i++)
         warnings[i] = "";
      warning_count = 0;
     }

   //--- Bounded append - same documented-capacity philosophy as
   //--- GZ_ExperimentResult::AddWarning() (GZ_ExperimentTypes.mqh);
   //--- this build never emits more than 2 distinct combo-level
   //--- warnings at once, so the cap is not expected to bind.
   void AddWarning(string w)
     {
      if(warning_count<GZ_FILTER_COMBO_MAX_WARNINGS)
        {
         warnings[warning_count] = w;
         warning_count++;
        }
     }
  };

#endif // __GZ_FILTER_COMBO_TYPES_MQH__
