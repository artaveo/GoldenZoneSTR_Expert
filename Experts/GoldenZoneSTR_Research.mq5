//+------------------------------------------------------------------+
//|                                    GoldenZoneSTR_Research.mq5    |
//|                                                                    |
//| GoldenZone STR - Phase 1+2+3+4+5+6+7+8+9+10+11+12+13+14+15 Research EA     |
//| Phase 1: Data Layer + Data Validator + Time Engine                |
//| Phase 2: M5 Structure Engine (swing/pivot detection)               |
//| Phase 3: Leg Engine + Break Engine                                 |
//| Phase 4: Fibonacci Engine + Setup State Machine                    |
//| Phase 5: Entry Engine + Historical Trade Simulator                 |
//| Phase 6: Exit Engine (SL/TP/BE)                                    |
//| Phase 7: MAE/MFE + R-Path + Event Ledger                          |
//| Phase 8: Metrics + Reporting                                       |
//| Phase 9: Experiment Configuration + Runner                         |
//| Phase 10: Filter Engine (Break/Leg Quality, Volume, Volatility,    |
//|           Session real; VWAP/M15 Context/News reserved stubs)      |
//| Phase 11: Filter Combination Research (R11-A single / R11-B two /  |
//|           R11-C limited multi-filter sweeps over Phase 10's own    |
//|           CGZFilterEngine)                                          |
//| Phase 12: Robustness + Sensitivity Research (axis-neighborhood       |
//|           sweeps via Phase 9's own CGZExperimentRunner, flagging     |
//|           Narrow Peak / Flat Region / Unstable Zone / Parameter      |
//|           Sensitive)                                                  |
//| Phase 15: Final OOS (ONE frozen configuration run on the Development   |
//|           range and on a separately loaded range that starts at/after   |
//|           the Development end; reported and compared, never tuned on)   |
//| Phase 14: Monte Carlo Research (seeded trade-order permutation and    |
//|           return-sequence bootstrap of the closed-trade R series:     |
//|           drawdown / losing-streak / net-R distributions, equity-path  |
//|           percentile bands, historical rank; original ledger untouched)|
//| Phase 13: Walk-Forward Research (rolling Train -> Validate windows;  |
//|           per-window selection of ONE Phase 12 axis value on the     |
//|           training slice only, validated out-of-sample, pooled OOS   |
//|           result + parameter-stability / efficiency flags)           |
//|                                                                    |
//| SCOPE: This EA implements ONLY Phase 1 (Data/Validator/Time/      |
//| Session/Diagnostics/TestHarness), Phase 2 (M5 swing/pivot         |
//| detection), Phase 3 (Leg Engine + Break Engine), Phase 4           |
//| (Fibonacci Engine + Setup State Machine), Phase 5 (Entry Engine + |
//| Historical Trade Simulator), Phase 6 (Exit Engine: SL/TP/BE),     |
//| Phase 7 (MAE/MFE + R-Path + Event Ledger), Phase 8 (Metrics +      |
//| Reporting), Phase 9 (Experiment Configuration + Runner), Phase 10  |
//| (Filter Engine), Phase 11 (Filter Combination Research) and Phase  |
//| 12 (Robustness + Sensitivity Research) and Phase 13 (Walk-Forward  |
//| Research). It places NO live orders.                                |
//| On init it loads historical M1+M5 data, runs validation, runs      |
//| swing detection, replays the M1/M5 data through the Leg/Break/     |
//| Setup/Entry/Exit/Journal/Ledger engines directly via                |
//| CGZTradeSimulator (full requested range), computes the Phase 8     |
//| Metrics summary via CGZMetricsEngine, evaluates Phase 10's          |
//| CGZFilterEngine against every setup and diffs a WITH/WITHOUT-      |
//| filter population into GZ_FilterDiagnostics, then runs Phase 11's  |
//| CGZFilterComboEngine (R11-A single-filter sweep, R11-B two-filter   |
//| sweep, R11-C limited multi-filter sweep ranked off R11-A's own      |
//| results) over that SAME already-final setup/trade population (no   |
//| pipeline re-simulation - filters are post-hoc masks, see            |
//| GZ_FilterComboTypes.mqh), then demonstrates Phase 9's               |
//| CGZExperimentRunner as one SINGLE-mode GZ_ExperimentResult over a  |
//| recent window of the SAME already-loaded/validated data (see       |
//| BuildAndEmitReport()'s Phase 9 section for why a window, not the   |
//| full range, is used there), then runs Phase 12's                    |
//| CGZRobustnessEngine over that SAME recent window - sweeping         |
//| InpRobustnessAxis1/2's own neighborhood through a FULL Phase 2-8    |
//| re-simulation PER swept value (unlike Phase 11's post-hoc masking - |
//| see GZ_RobustnessTypes.mqh design note 1) and flagging Narrow Peak/ |
//| Flat Region/Unstable Zone/Parameter Sensitive so no single highest  |
//| historical value is ever presented as a safe final choice on its    |
//| own, then runs Phase 13's CGZWalkForwardEngine over the FULL loaded |
//| range (rolling train/validate windows, one axis value selected per  |
//| window from the TRAINING slice only and validated out-of-sample -   |
//| see GZ_WalkForwardTypes.mqh) - runs the deterministic T01-T142 test |
//| harness, and prints a completion report. Then it stops - it does    |
//| not trade and does not proceed to Phase 14 (Monte Carlo Research)   |
//| logic.                                                              |
//+------------------------------------------------------------------+
#property copyright "GoldenZone STR"
#property version   "1.150"
#property description "Phase 1+2+3+4+5+6+7+8+9+10+11+12+13+14+15: Data/Validator/Time Engine + M5 Structure Engine + Leg/Break Engine + Fibonacci/Setup State Machine + Entry Engine/Trade Simulator + Exit Engine SL/TP/BE + MAE/MFE/R-Path/Event Ledger + Metrics/Reporting + Experiment Configuration/Runner + Filter Engine + Filter Combination Research + Robustness/Sensitivity Research + Walk-Forward Research + Monte Carlo Research + Final OOS (research/diagnostic only, no trading)"

#include <GoldenZoneSTR\Core\GZ_Types.mqh>
#include <GoldenZoneSTR\Core\GZ_Config.mqh>
#include <GoldenZoneSTR\Core\GZ_Constants.mqh>
#include <GoldenZoneSTR\Data\GZ_DataProvider.mqh>
#include <GoldenZoneSTR\Data\GZ_DataValidator.mqh>
#include <GoldenZoneSTR\Data\GZ_DatasetInfo.mqh>
#include <GoldenZoneSTR\Time\GZ_TimeEngine.mqh>
#include <GoldenZoneSTR\Time\GZ_Session.mqh>
#include <GoldenZoneSTR\Structure\GZ_StructureTypes.mqh>
#include <GoldenZoneSTR\Structure\GZ_SwingEngine.mqh>
#include <GoldenZoneSTR\Leg\GZ_LegTypes.mqh>
#include <GoldenZoneSTR\Leg\GZ_ATR.mqh>
#include <GoldenZoneSTR\Leg\GZ_LegEngine.mqh>
#include <GoldenZoneSTR\Leg\GZ_BreakEngine.mqh>
#include <GoldenZoneSTR\Setup\GZ_SetupTypes.mqh>
#include <GoldenZoneSTR\Setup\GZ_FibEngine.mqh>
#include <GoldenZoneSTR\Setup\GZ_SetupStateMachine.mqh>
#include <GoldenZoneSTR\Entry\GZ_EntryTypes.mqh>
#include <GoldenZoneSTR\Entry\GZ_EntryEngine.mqh>
#include <GoldenZoneSTR\Entry\GZ_TradeSimulator.mqh>
#include <GoldenZoneSTR\Exit\GZ_ExitTypes.mqh>
#include <GoldenZoneSTR\Exit\GZ_ExitEngine.mqh>
#include <GoldenZoneSTR\Journal\GZ_JournalTypes.mqh>
#include <GoldenZoneSTR\Journal\GZ_JournalEngine.mqh>
#include <GoldenZoneSTR\Journal\GZ_LedgerTypes.mqh>
#include <GoldenZoneSTR\Journal\GZ_EventLedger.mqh>
#include <GoldenZoneSTR\Metrics\GZ_MetricsTypes.mqh>
#include <GoldenZoneSTR\Metrics\GZ_MetricsEngine.mqh>
#include <GoldenZoneSTR\Experiment\GZ_ExperimentTypes.mqh>
#include <GoldenZoneSTR\Experiment\GZ_ExperimentRunner.mqh>
#include <GoldenZoneSTR\Filter\GZ_FilterTypes.mqh>
#include <GoldenZoneSTR\Filter\GZ_FilterEngine.mqh>
#include <GoldenZoneSTR\Filter\GZ_FilterComboTypes.mqh>
#include <GoldenZoneSTR\Filter\GZ_FilterComboEngine.mqh>
#include <GoldenZoneSTR\Robustness\GZ_RobustnessTypes.mqh>
#include <GoldenZoneSTR\Robustness\GZ_RobustnessEngine.mqh>
#include <GoldenZoneSTR\WalkForward\GZ_WalkForwardTypes.mqh>
#include <GoldenZoneSTR\WalkForward\GZ_WalkForwardEngine.mqh>
#include <GoldenZoneSTR\MonteCarlo\GZ_MonteCarloTypes.mqh>
#include <GoldenZoneSTR\MonteCarlo\GZ_MonteCarloEngine.mqh>
#include <GoldenZoneSTR\FinalOOS\GZ_FinalOosTypes.mqh>
#include <GoldenZoneSTR\FinalOOS\GZ_FinalOosEngine.mqh>
#include <GoldenZoneSTR\RewardBe\GZ_RewardBeTypes.mqh>
#include <GoldenZoneSTR\RewardBe\GZ_RunDetail.mqh>
#include <GoldenZoneSTR\RewardBe\GZ_RewardBeEngine.mqh>
#include <GoldenZoneSTR\Diagnostics\GZ_Logger.mqh>
#include <GoldenZoneSTR\Diagnostics\GZ_TestHarness.mqh>

//--- Inputs -----------------------------------------------------------------
input string             InpSymbol            = "XAUUSD";
input datetime            InpRangeStart         = D'2026.01.01 00:00';
input datetime            InpRangeEnd            = D'2026.06.13 00:00';

input ENUM_GZ_TIME_MODE  InpTimeMode          = GZ_TIME_BROKER;
input ENUM_GZ_DST_MODE   InpDstMode           = GZ_DST_AUTO;
input int                InpFixedNyOffsetHrs  = -5;      // used only if InpDstMode == GZ_DST_FIXED
input int                InpBrokerUtcOffsetHrs= 0;       // assumed broker/server offset from UTC
input bool                InpBrokerOffsetKnown  = false;   // set true only if you have verified the broker offset

input int                 InpSessionStartHour   = 16;
input int                 InpSessionStartMinute = 30;
input int                 InpSessionEndHour     = 20;
input int                 InpSessionEndMinute   = 30;
input bool                InpSessionInclude     = true;

input bool                InpVerboseLogging     = false;
input bool                InpLoadM15            = false;

//--- Phase 2: M5 Structure Engine ---------------------------------------------
input int                 InpPivotStrength      = 2;      // baseline=2 per roadmap; research range 1-5

//--- Phase 3: Leg Engine + Break Engine ---------------------------------------
input ENUM_GZ_LEG_VARIANT InpLegVariant         = GZ_LEG_VARIANT_LAST_SWING;  // baseline; research: min-distance / min-ATR-distance
input ENUM_GZ_BREAK_MODE  InpBreakMode          = GZ_BREAK_CLOSE;             // baseline=CLOSE; research variant=WICK
input double               InpBreakBufferAtrMult = 0.0;    // research grid: 0/0.05/0.10/0.15/0.20/0.30/0.50
input int                 InpAtrPeriod          = 14;      // research grid: 5/10/14/20/30 (no roadmap baseline stated)

//--- Phase 4: Fibonacci Engine + Setup State Machine --------------------------
input double               InpFibZoneMinRatio    = 0.30;   // research grid 0.30-0.90; architecture extensible to 0.01 steps
input double               InpFibZoneMaxRatio    = 0.90;
input bool                 InpApplySessionFilter = false;  // if true, a setup is cancelled (SESSION_END) once price moves
                                                             // outside the Phase 1 session window (InpSession*) before entry

//--- Phase 5: Entry Engine + Historical Trade Simulator -----------------------
input ENUM_GZ_ENTRY_MODEL InpEntryModel         = GZ_ENTRY_TOUCH; // baseline=TOUCH; research: LIMIT/CLOSE_CONFIRMATION/M1_CONFIRMATION
input double               InpEntryFibRatio      = 0.618;  // single fib ratio the Entry Engine targets (see GZ_EntryTypes.mqh design note 1)
input int                  InpConfirmationCandles= 1;       // research range 1-3; used only by CLOSE_CONFIRMATION / M1_CONFIRMATION
input double               InpEntryPenetrationAtrMult = 0.0; // research grid: 0/0.02/0.05/0.10/0.15 ATR

//--- Phase 6: Exit Engine (SL/TP/BE) -------------------------------------------
input ENUM_GZ_SL_MODEL    InpSlModel            = GZ_SL_STRUCTURE; // baseline=STRUCTURE (Leg Origin +/- buffer); research: ATR
input double               InpSlBufferAtrMult    = 0.0;   // STRUCTURE model only; ATR multiples beyond the leg origin
input double               InpSlAtrMult          = 1.5;   // ATR model only; SL distance from entry, in ATR multiples
input double               InpTpRMultiple        = 2.0;   // research grid 0.5R-5R, extensible above
input double               InpBeTriggerR         = 0.0;   // 0.0 = OFF; research grid 0.25R-5R
input ENUM_GZ_BE_LEVEL_MODE InpBeLevelMode       = GZ_BE_LEVEL_ENTRY; // ENTRY or ENTRY_OFFSET
input double               InpBeLevelOffsetR     = 0.0;   // used only when InpBeLevelMode==ENTRY_OFFSET
input ENUM_GZ_INTRABAR_CONFLICT_POLICY InpIntrabarConflictPolicy = GZ_CONFLICT_SL_FIRST; // baseline=SL_FIRST (conservative)
input bool                 InpForceSessionExit   = false;  // if true, open trades are force-closed (SESSION_EXIT) once
                                                             // price moves outside the session window (independent of
                                                             // InpApplySessionFilter, which only governs Phase 4 setup
                                                             // cancellation before entry - see GZ_ExitEngine.mqh)

//--- Phase 9: Experiment Configuration + Runner --------------------------------
input int                  InpExperimentWindowM5Bars = 1000; // recent-window size (M5 bars) for the live Phase 9
                                                              // CGZExperimentRunner demonstration - see
                                                              // BuildAndEmitReport()'s Phase 9 section for why a
                                                              // window, not the full requested range, is used here
input int                  InpExperimentMaxBatchSize = GZ_DEFAULT_MAX_EXPERIMENT_BATCH_SIZE; // Roadmap "stage
                                                              // research, don't run one huge Grid at once" cap

//--- Phase 10: Filter Engine ----------------------------------------------------
//--- Every mode defaults to OFF: a fresh Phase 10 run changes nothing about the
//--- Phase 1-9 trade population until a filter is explicitly enabled here (see
//--- GZ_FilterTypes.mqh design note 2 - NOT_AVAILABLE must never auto-pass, so
//--- turning on VWAP/M15 Context/News - permanently NOT_AVAILABLE, reserved
//--- stubs - would reject every setup; left OFF by default for that reason).
input ENUM_GZ_FILTER_MODE InpFilterBreakQualityMode = GZ_FILTER_OFF;
input ENUM_GZ_FILTER_MODE InpFilterLegQualityMode   = GZ_FILTER_OFF;
input ENUM_GZ_FILTER_MODE InpFilterVolumeMode       = GZ_FILTER_OFF;
input ENUM_GZ_FILTER_MODE InpFilterVolatilityMode   = GZ_FILTER_OFF;
input ENUM_GZ_FILTER_MODE InpFilterVwapMode         = GZ_FILTER_OFF;        // reserved - always NOT_AVAILABLE
input ENUM_GZ_FILTER_MODE InpFilterM15ContextMode   = GZ_FILTER_OFF;        // reserved - always NOT_AVAILABLE
input ENUM_GZ_FILTER_MODE InpFilterSessionMode      = GZ_FILTER_OFF;
input ENUM_GZ_FILTER_MODE InpFilterNewsMode         = GZ_FILTER_OFF;        // reserved - always NOT_AVAILABLE

input double               InpFilterBreakQualityMinAtrMult = 0.10;  // break distance beyond level, in ATR multiples
input double               InpFilterLegQualityMinAtrMult   = 1.00;  // leg size, in ATR multiples
input int                  InpFilterVolumeLookback         = 20;    // bars in the trailing tick-volume average
input double               InpFilterVolumeMinMult          = 1.00;  // break bar tick_volume >= mult * trailing average
input int                  InpFilterVolatilityLookback     = 50;    // bars in the trailing ("baseline") ATR average
input double               InpFilterVolatilityMinMult      = 0.50;  // current ATR / baseline ATR must be in [min,max]
input double               InpFilterVolatilityMaxMult      = 2.00;

//--- Phase 11: Filter Combination Research --------------------------------------
//--- Runs R11-A (single filter) / R11-B (two-filter) / R11-C (limited multi-
//--- filter, ranked off R11-A) sweeps of Phase 10's own CGZFilterEngine over the
//--- SAME already-final setup/trade population the direct pipeline above already
//--- produced - no pipeline re-simulation (see GZ_FilterComboTypes.mqh design
//--- note 2). Thresholds/session window reuse the SAME InpFilter* values already
//--- configured above (Phase 10 section) as every combo's shared baseline -
//--- Phase 11 only varies WHICH filters are turned on, never their thresholds
//--- (a threshold sweep is a different, not-yet-specified research question).
input bool                 InpRunPhase11                 = true;   // set false to skip Phase 11 entirely (Phase 1-10 unaffected either way)
input bool                 InpFilterComboIncludeReserved = false;  // if true, ALSO builds/runs combos naming VWAP/M15 Context/News -
                                                                    // documented to deterministically reject every setup in this build
                                                                    // (design note 4, GZ_FilterComboTypes.mqh); OFF by default
input int                  InpFilterComboR11CTopN        = 4;      // R11-C: builds one combo per size from 3 up to this many top-ranked
                                                                    // R11-A filters (clamped to however many are actually eligible)
input int                  InpFilterComboMaxBatchSize    = GZ_DEFAULT_MAX_FILTER_COMBO_BATCH_SIZE; // Roadmap "stage research,
                                                                    // don't run one huge Grid at once" cap, reapplied to Phase 11

//--- Phase 12: Robustness + Sensitivity Research --------------------------------
//--- UNLIKE Phase 11 (a post-hoc mask, no re-simulation), each swept value here
//--- changes the underlying Leg/Break/Setup/Trade population itself and needs its
//--- own FULL Phase 2-8 re-simulation via CGZExperimentRunner - so, exactly like
//--- Phase 9's own live demonstration above (see BuildAndEmitReport()'s Phase 9
//--- section), this runs over a RECENT WINDOW of the data (the SAME window/config
//--- Phase 9 already built just above), not the full requested range - re-running
//--- the full multi-month pipeline many times over (one per swept value, per axis)
//--- would multiply this EA's already-real Phase 9 runtime cost for no new
//--- information about Phase 12's own axis-sweep/sensitivity-analysis logic itself.
//--- Two axes are demonstrated by default, reproducing the Roadmap's OWN worked
//--- example ("مثال برای 1.50 ATR"): break-buffer ATR multiple and SL ATR multiple.
input bool                  InpRunPhase12                 = true;   // set false to skip Phase 12 entirely (Phase 1-11 unaffected either way)
input ENUM_GZ_ROBUSTNESS_PARAM InpRobustnessAxis1          = GZ_ROBUST_BREAK_BUFFER_ATR; // first axis to sweep (do not select the GZ_ROBUST_PARAM_COUNT sentinel)
input ENUM_GZ_ROBUSTNESS_PARAM InpRobustnessAxis2          = GZ_ROBUST_SL_ATR_MULT;       // second axis to sweep (do not select the GZ_ROBUST_PARAM_COUNT sentinel)
input int                   InpRobustnessMaxBatchSize     = GZ_DEFAULT_MAX_ROBUSTNESS_BATCH_SIZE; // Roadmap "stage research,
                                                                    // don't run one huge Grid at once" cap, reapplied to Phase 12 (axes/call)

//--- Phase 13: Walk-Forward Research --------------------------------------------
//--- Rolling Train -> Validate windows over the FULL loaded M1/M5 range (unlike
//--- Phase 9/12's recent-window demos, walk-forward needs several consecutive
//--- windows, so it uses everything that was loaded). Per training window ONE
//--- axis (InpWfAxis) is swept over the SAME default neighborhood Phase 12 uses,
//--- one value is selected using ONLY that window's training bars, and that value
//--- (plus the fixed baseline, for comparison) is then run on the following
//--- validation window. See GZ_WalkForwardTypes.mqh design notes 1-7.
//--- Window lengths are CALENDAR days (weekends included). The Roadmap gives no
//--- numeric defaults - the values below are documented conventional defaults.
input bool                  InpRunPhase13                 = true;   // set false to skip Phase 13 entirely (Phase 1-12 unaffected either way)
input ENUM_GZ_ROBUSTNESS_PARAM InpWfAxis                  = GZ_ROBUST_BREAK_BUFFER_ATR; // axis whose value is selected per window (do not select the GZ_ROBUST_PARAM_COUNT sentinel)
input int                   InpWfTrainDays                = GZ_DEFAULT_WF_TRAIN_DAYS;    // training window length
input int                   InpWfValidateDays             = GZ_DEFAULT_WF_VALIDATE_DAYS; // validation window length
input int                   InpWfStepDays                 = GZ_DEFAULT_WF_STEP_DAYS;     // how far the window slides each step (< validate days -> overlapping validation, flagged)
input int                   InpWfMinTrades                = GZ_DEFAULT_WF_MIN_TRADES;    // a TRAINING candidate needs at least this many trades to be selectable
input int                   InpWfMinValidationTrades      = GZ_DEFAULT_WF_MIN_VALIDATION_TRADES; // validated windows below this are flagged LOW_VALIDATION_TRADES
input bool                  InpWfRequireSafeSelection     = true;   // true = an unsafe best (narrow peak / unstable zone, per Phase 12) is NOT taken: falls back to the baseline value

//--- Phase 14: Monte Carlo Research ---------------------------------------------
//--- Runs BOTH modes (trade-order permutation and return-sequence bootstrap) over
//--- the realized-R series of the main pipeline's CLOSED trades (the same
//--- population as the Phase 8 metrics). Own seeded generator (not MathRand), so the
//--- same seed always reproduces the same numbers; simulation k depends only on
//--- (seed, k). The historical ledger is never modified. See GZ_MonteCarloTypes.mqh
//--- design notes 1-7. The Roadmap gives no numeric defaults - conventional ones below.
input bool                  InpRunPhase14                 = true;   // set false to skip Phase 14 entirely (Phase 1-13 unaffected either way)
input int                   InpMcSimulations              = GZ_DEFAULT_MC_SIMULATIONS;     // simulations per mode
input uint                  InpMcSeed                     = GZ_DEFAULT_MC_SEED;            // reproducibility seed (recorded in the report)
input int                   InpMcMaxSimulations           = GZ_DEFAULT_MC_MAX_SIMULATIONS; // cap: a larger InpMcSimulations is REJECTED, never truncated

//--- Phase 15: Final OOS ---------------------------------------------------------
//--- The Development range is InpRangeStart..InpRangeEnd (the ONLY data Phases 1-14
//--- ever load). The Final OOS range below is loaded ONLY here, must START AT OR
//--- AFTER InpRangeEnd (an earlier start is REJECTED, never shifted), and is never
//--- used to choose or tune anything: the EA's current inputs are run once, frozen,
//--- on both ranges and compared. Changing parameters after looking at the OOS result
//--- contaminates it - the Roadmap's answer is Phase 16 (new version + NEW OOS data).
//--- Default: everything after the Development end up to InpOosEnd (a fixed date, never
//--- the wall clock, so results stay reproducible).
input bool                  InpRunPhase15                 = true;   // set false to skip Phase 15 entirely
input datetime              InpOosStart                   = D'2026.06.13 00:00'; // must be >= InpRangeEnd
input datetime              InpOosEnd                     = D'2026.09.24 00:00';
input int                   InpOosMinTrades               = GZ_DEFAULT_OOS_MIN_TRADES; // fewer OOS trades -> LOW_OOS_TRADES flag

//--- Phase 15.5: Reward / TP x Risk-Free (BE) Research Matrix ------------------------------
//--- RESEARCH + MEASUREMENT ONLY, on the DEVELOPMENT range (InpRangeStart..InpRangeEnd) ONLY.
//--- While InpRunPhase155=true, Phase 15 (which loads the Final OOS) is ALWAYS skipped, so the
//--- Final OOS is never loaded or inspected. Nothing is selected, ranked or frozen.
input bool                  InpRunPhase155                = true;   // run the Phase 15.5 matrix (also forces Phase 15 / Final OOS OFF)
input bool                  InpPhase155Only               = true;   // true = also skip the heavy Phase 11-14 studies during this run (unrelated to 15.5)
input bool                  InpP155IncludeInactiveEquivalent = true; // run trigger>=TP combinations too (validation only; 45 extra runs)
input double                InpP155RefWinRate             = 0.507;  // Phase 15 Development baseline AS REPORTED (TP 2R, BE off): win rate (fraction)
input double                InpP155RefExpectancy          = 0.5218; //   ... expectancy (R)
input double                InpP155RefPF                  = 2.059;  //   ... profit factor
input double                InpP155RefNetR                = 215.0;  //   ... net R

//--- Globals ------------------------------------------------------------------
CGZLogger         g_logger;
CGZDataProvider   g_provider(GetPointer(g_logger));
CGZDataValidator  g_validator(GetPointer(g_logger));
CGZTimeEngine     g_time_engine(GetPointer(g_logger));
CGZSessionEngine  g_session_engine;
CGZTestHarness    g_harness(GetPointer(g_logger));
CGZSwingEngine    g_swing_engine(GetPointer(g_logger));
CGZLegEngine      g_leg_engine(GetPointer(g_logger));
CGZBreakEngine    g_break_engine(GetPointer(g_logger));
CGZSetupStateMachine g_setup_sm(GetPointer(g_logger));
CGZEntryEngine    g_entry_engine(GetPointer(g_logger));
CGZExitEngine     g_exit_engine(GetPointer(g_logger));
CGZJournalEngine  g_journal_engine(GetPointer(g_logger));
CGZEventLedger    g_event_ledger(GetPointer(g_logger));
CGZTradeSimulator g_trade_simulator(GetPointer(g_logger));
CGZMetricsEngine  g_metrics_engine(GetPointer(g_logger));
CGZExperimentRunner g_experiment_runner(GetPointer(g_logger));
CGZFilterEngine   g_filter_engine(GetPointer(g_logger));
CGZFilterComboEngine g_filter_combo_engine(GetPointer(g_logger));
CGZRobustnessEngine  g_robustness_engine(GetPointer(g_logger));
CGZWalkForwardEngine g_walkforward_engine(GetPointer(g_logger));
CGZMonteCarloEngine  g_montecarlo_engine(GetPointer(g_logger));
CGZFinalOosEngine    g_oos_engine(GetPointer(g_logger));
CGZRewardBeEngine    g_rewardbe_engine(GetPointer(g_logger));

CGZDatasetInfo    g_info_m1;
CGZDatasetInfo    g_info_m5;

//--- Phase 2 diagnostic results (M5 swing detection over the loaded range) ----
GZ_Swing          g_swings[];
int               g_swing_count = 0;

//--- Phase 3 diagnostic results (leg/break detection over the loaded range) ---
int               g_leg_count = 0;
int               g_broken_leg_count = 0;

//--- Phase 4 diagnostic results (setup lifecycle over the loaded range) -------
int               g_setup_count = 0;

//--- Phase 5 diagnostic results (entry/trade generation over the loaded range)
int               g_trade_count = 0;

//--- Phase 6 diagnostic results (exit management over the loaded range) -------
int               g_exit_count = 0;

//--- Phase 7 diagnostic results (journal/ledger over the loaded range) --------
int               g_journal_count = 0;
int               g_ledger_event_count = 0;

//--- Phase 8 diagnostic result (metrics summary over the loaded range) --------
GZ_MetricsSummary g_metrics;

//--- Phase 9 diagnostic result (one SINGLE-mode demonstration experiment) -----
GZ_ExperimentResult g_experiment_result;
bool                 g_experiment_ran = false;

//--- Phase 10 diagnostic results (filter evaluation over the loaded range) ----
int                  g_filter_setups_after = 0;   // setups whose combined filter decision == pass
int                  g_filter_rejections   = 0;   // closed trades whose setup's combined decision rejected them
GZ_MetricsSummary    g_filter_metrics_after;       // WITH-filter population (see BuildAndEmitReport() Phase 10)

//--- Phase 11 diagnostic results (filter combination sweeps over the same setups)
bool                 g_phase11_ran = false;
GZ_FilterComboResult g_r11a_results[];  // R11-A: single filter
GZ_FilterComboResult g_r11b_results[];  // R11-B: two-filter
GZ_FilterComboResult g_r11c_results[];  // R11-C: limited multi-filter (ranked off R11-A)
int                  g_r11a_best_idx = -1; // index into g_r11a_results with the highest expectancy_delta (trades_after>0)
int                  g_r11b_best_idx = -1;
int                  g_r11c_best_idx = -1;

//--- Phase 12 diagnostic results (robustness/sensitivity sweeps over the SAME
//--- recent window Phase 9 uses - see the Phase 12 input block above for why)
bool                     g_phase12_ran = false;
GZ_RobustnessSweepResult g_robustness_results[]; // one per swept axis (InpRobustnessAxis1/2)

//--- Phase 13 diagnostic result (one walk-forward run over the FULL loaded range)
bool                     g_phase13_ran = false;
GZ_WalkForwardResult     g_wf_result;

//--- Phase 14 diagnostic results (one Monte Carlo run per mode, over the main pipeline's closed-trade R series)
bool                     g_phase14_ran = false;
GZ_McResult              g_mc_order;      // TRADE_ORDER
GZ_McResult              g_mc_bootstrap;  // RETURN_SEQUENCE

//--- Phase 15.5 result (TP x BE research matrix over the Development range only)
bool                     g_phase155_ran = false;
bool                     g_p155_only    = false;   // InpRunPhase155 && InpPhase155Only -> Phases 11-14 skipped
string                   g_p155_dataset_id = "";

//--- Phase 15 result (frozen config: Development range vs separately loaded Final OOS range)
bool                     g_phase15_ran = false;
GZ_FinalOosResult        g_oos_result;
int                      g_oos_m1_bars = 0;
int                      g_oos_m5_bars_loaded = 0;

//+------------------------------------------------------------------+
//| Phase 11 helper: index of the combo with the highest                |
//| expectancy_delta among those that still produced at least one       |
//| closed trade (a combo that zeroed the population - e.g. a reserved  |
//| filter - carries no comparable expectancy and is excluded). Report/ |
//| log summary only - NEVER used to auto-select a "winning" config;    |
//| picking the single best historical number is explicitly what        |
//| Roadmap Phase 12 (Robustness/Sensitivity) warns against.             |
//+------------------------------------------------------------------+
int BestFilterComboIndex(const GZ_FilterComboResult &results[])
  {
   int best = -1;
   double best_score = 0.0;
   for(int i=0;i<ArraySize(results);i++)
     {
      if(results[i].diagnostics.trades_after<=0)
         continue;
      if(best==-1 || results[i].diagnostics.expectancy_delta>best_score)
        {
         best = i;
         best_score = results[i].diagnostics.expectancy_delta;
        }
     }
   return best;
  }

//+------------------------------------------------------------------+
//| Print a long report to the Experts log in newline-aligned chunks.  |
//| A single Print() of the whole report is silently truncated by the   |
//| terminal once it grows past its per-message length limit (that is   |
//| why the Phase 12 log cut off before the test results/Final Status). |
//| The saved report FILE is unaffected either way - this only makes    |
//| the Experts-log copy complete too.                                   |
//+------------------------------------------------------------------+
void PrintReportChunked(const string text)
  {
   int len = StringLen(text);
   int pos = 0;
   int chunk = 6000;
   while(pos<len)
     {
      int take = (len-pos<chunk) ? (len-pos) : chunk;
      if(pos+take<len)
        {
         string piece = StringSubstr(text, pos, take);
         int nl = -1;
         for(int k=take-1; k>0; k--)
           {
            if(StringGetCharacter(piece, k)==10)
              {
               nl = k;
               break;
              }
           }
         if(nl>0)
            take = nl+1;
        }
      Print(StringSubstr(text, pos, take));
      pos += take;
     }
  }

//+------------------------------------------------------------------+
//| Build and print/save the Phase 1 completion report                |
//+------------------------------------------------------------------+
void BuildAndEmitReport()
  {
   string report = "";
   report += "===================================================\n";
   report += " GoldenZone STR - PHASE 1 + PHASE 2 + PHASE 3 + PHASE 4 + PHASE 5 + PHASE 6 + PHASE 7 + PHASE 8 + PHASE 9 + PHASE 10 + PHASE 11 + PHASE 12 + PHASE 13 + PHASE 14 + PHASE 15 COMPLETION REPORT\n";
   report += " Spec version: " + GZ_PROJECT_VERSION + " | " + GZ_PROJECT_VERSION_P2 + " | " + GZ_PROJECT_VERSION_P3 + " | " + GZ_PROJECT_VERSION_P4 + " | " + GZ_PROJECT_VERSION_P5 + " | " + GZ_PROJECT_VERSION_P6 + " | " + GZ_PROJECT_VERSION_P7 + " | " + GZ_PROJECT_VERSION_P8 + " | " + GZ_PROJECT_VERSION_P9 + " | " + GZ_PROJECT_VERSION_P10 + " | " + GZ_PROJECT_VERSION_P11 + " | " + GZ_PROJECT_VERSION_P12 + " | " + GZ_PROJECT_VERSION_P13 + " | " + GZ_PROJECT_VERSION_P14 + " | " + GZ_PROJECT_VERSION_P15 + "\n";
   report += " Generated (terminal local time, diagnostic only): " + TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS) + "\n";
   report += "===================================================\n\n";

   report += "--- Implementation ---\n";
   report += "Phase 1 files: GZ_Types, GZ_Config, GZ_Constants, GZ_DataProvider, GZ_DataValidator,\n";
   report += "       GZ_DatasetInfo, GZ_TimeEngine, GZ_DST, GZ_Session, GZ_Logger, GZ_TestHarness\n";
   report += "Phase 2 files: GZ_StructureTypes, GZ_SwingEngine\n";
   report += "Phase 3 files: GZ_LegTypes, GZ_ATR, GZ_LegEngine, GZ_BreakEngine\n";
   report += "Phase 4 files: GZ_SetupTypes, GZ_FibEngine, GZ_SetupStateMachine\n";
   report += "Phase 5 files: GZ_EntryTypes, GZ_EntryEngine, GZ_TradeSimulator\n";
   report += "Phase 6 files: GZ_ExitTypes, GZ_ExitEngine\n";
   report += "Phase 7 files: GZ_JournalTypes, GZ_JournalEngine, GZ_LedgerTypes, GZ_EventLedger\n";
   report += "Phase 8 files: GZ_MetricsTypes, GZ_MetricsEngine\n";
   report += "Phase 9 files: GZ_ExperimentTypes, GZ_ExperimentRunner\n";
   report += "Phase 10 files: GZ_FilterTypes, GZ_FilterEngine\n";
   report += "Phase 11 files: GZ_FilterComboTypes, GZ_FilterComboEngine\n";
   report += "Phase 12 files: GZ_RobustnessTypes, GZ_RobustnessEngine\n";
   report += "Phase 13 files: GZ_WalkForwardTypes, GZ_WalkForwardEngine\n";
   report += "Phase 14 files: GZ_MonteCarloTypes, GZ_MonteCarloEngine\n";
   report += "Phase 15 files: GZ_FinalOosTypes, GZ_FinalOosEngine\n";
   report += "Interfaces: GZ_TimeContext, CGZDatasetInfo (Phase 1), GZ_Swing / CGZSwingEngine (Phase 2),\n";
   report += "            GZ_Leg / CGZLegEngine / CGZBreakEngine (Phase 3), GZ_Setup / CGZFibEngine /\n";
   report += "            CGZSetupStateMachine (Phase 4), GZ_Trade / CGZEntryEngine / CGZTradeSimulator\n";
   report += "            (Phase 5), GZ_TradeExit / CGZExitEngine (Phase 6), GZ_TradeJournal /\n";
   report += "            CGZJournalEngine / GZ_LedgerEvent / CGZEventLedger (Phase 7), GZ_MetricsSummary /\n";
   report += "            CGZMetricsEngine (Phase 8), GZ_ExperimentConfig / GZ_ExperimentResult /\n";
   report += "            CGZExperimentRunner (Phase 9), GZ_FilterSetConfig / GZ_SetupFilterOutcome /\n";
   report += "            CGZFilterEngine (Phase 10), GZ_FilterComboRequest / GZ_FilterComboResult /\n";
   report += "            CGZFilterComboEngine (Phase 11), GZ_RobustnessSweepRequest /\n";
   report += "            GZ_RobustnessSweepResult / CGZRobustnessEngine (Phase 12), GZ_WalkForwardConfig /\n";
   report += "            GZ_WalkForwardWindow / GZ_WalkForwardResult / CGZWalkForwardEngine (Phase 13) - all consumed by later\n";
   report += "            phases; Update()/UpdateBar()/OnBar()/CheckBreak()/OnLegCreated()/OnLegBroken()/\n";
   report += "            MarkEntered()/CancelForInvalidPenetration()/OnTradeEntered() are live-safe,\n";
   report += "            DetectAll()/CGZTradeSimulator.Run()/BuildFromFinalState()/CGZMetricsEngine.Compute()/\n";
   report += "            CGZExperimentRunner.RunSingle()/RunBatch()/CGZFilterEngine.Evaluate()/\n";
   report += "            CGZFilterComboEngine.RunBatch()/CGZRobustnessEngine.RunSweep()/RunSweepBatch()/\n";
   report += "            Analyze()/CGZWalkForwardEngine.RunWalkForward()/BuildWindows()/SelectFromSweep()/\n";
   report += "            Aggregate() are research-batch\n\n";

   report += "--- Data Validation: M1 ---\n";
   report += StringFormat("Symbol=%s Bars=%d First=%s Last=%s\n",
              g_info_m1.symbol, g_info_m1.total_bars,
              TimeToString(g_info_m1.first_bar_time), TimeToString(g_info_m1.last_bar_time));
   report += StringFormat("Missing(unexpected)=%d ExpectedGaps=%d Duplicates=%d InvalidOHLC=%d TimestampErrors=%d\n",
              g_info_m1.missing_bar_count, g_info_m1.expected_gap_count, g_info_m1.duplicate_count,
              g_info_m1.invalid_ohlc_count, g_info_m1.timestamp_error_count);
   report += "Status: " + g_info_m1.StatusToString() + "\n\n";

   report += "--- Data Validation: M5 ---\n";
   report += StringFormat("Symbol=%s Bars=%d First=%s Last=%s\n",
              g_info_m5.symbol, g_info_m5.total_bars,
              TimeToString(g_info_m5.first_bar_time), TimeToString(g_info_m5.last_bar_time));
   report += StringFormat("Missing(unexpected)=%d ExpectedGaps=%d Duplicates=%d InvalidOHLC=%d TimestampErrors=%d\n",
              g_info_m5.missing_bar_count, g_info_m5.expected_gap_count, g_info_m5.duplicate_count,
              g_info_m5.invalid_ohlc_count, g_info_m5.timestamp_error_count);
   report += "Status: " + g_info_m5.StatusToString() + "\n\n";

   report += "--- Time / DST / Session Configuration ---\n";
   report += StringFormat("TimeMode=%d DstMode=%d BrokerOffsetKnown=%s BrokerOffsetHrs=%d\n",
              (int)InpTimeMode, (int)InpDstMode, InpBrokerOffsetKnown?"true":"false", InpBrokerUtcOffsetHrs);
   report += StringFormat("Session: %02d:%02d - %02d:%02d (%s, [start,end) rule)\n\n",
              InpSessionStartHour, InpSessionStartMinute, InpSessionEndHour, InpSessionEndMinute,
              InpSessionInclude?"INCLUDE":"EXCLUDE");

   report += "--- Phase 2: M5 Structure Engine (Swing Detection) ---\n";
   report += StringFormat("PivotStrength=%d (baseline=2; research range 1-5 supported via input)\n",
              InpPivotStrength);
   report += StringFormat("M5 bars scanned=%d  Swings confirmed=%d\n", g_info_m5.total_bars, g_swing_count);
   report += "No lookahead: each swing is only ever produced after PivotStrength bars have\n";
   report += "closed on its right side (see T21). Consumed by Phase 3 below.\n\n";

   report += "--- Phase 3: Leg Engine + Break Engine ---\n";
   report += StringFormat("LegVariant=%s BreakMode=%s BreakBufferAtrMult=%.2f AtrPeriod=%d\n",
              EnumToString(InpLegVariant), EnumToString(InpBreakMode), InpBreakBufferAtrMult, InpAtrPeriod);
   report += StringFormat("Legs created=%d  Legs broken=%d  Legs still open=%d\n",
              g_leg_count, g_broken_leg_count, g_leg_count-g_broken_leg_count);
   report += "No lookahead: a leg's extreme only ever consumes bars at/after its target swing's\n";
   report += "confirmation time (see T27), and a break is only ever confirmed on the exact bar\n";
   report += "that clears the configured level+buffer (see T34). Consumed by Phase 4 below.\n\n";

   report += "--- Phase 4: Fibonacci Engine + Setup State Machine ---\n";
   report += StringFormat("FibZone ratio=[%.2f,%.2f] SessionFilter=%s\n",
              InpFibZoneMinRatio, InpFibZoneMaxRatio, InpApplySessionFilter?"true":"false");
   report += StringFormat("Setups=%d  LEG_DETECTED=%d  FIB_ACTIVE=%d  WAITING_ENTRY=%d  ENTERED=%d  EXITED=%d  CANCELLED=%d\n",
              g_setup_count, g_setup_sm.CountByState(GZ_SETUP_LEG_DETECTED), g_setup_sm.CountByState(GZ_SETUP_FIB_ACTIVE),
              g_setup_sm.CountByState(GZ_SETUP_WAITING_ENTRY), g_setup_sm.CountByState(GZ_SETUP_ENTERED),
              g_setup_sm.CountByState(GZ_SETUP_EXITED), g_setup_sm.CountByState(GZ_SETUP_CANCELLED));
   report += StringFormat("Cancel reasons: OPPOSITE_BREAK=%d NEW_VALID_SETUP=%d SESSION_END=%d DATA_END=%d\n",
              g_setup_sm.CountTerminalByReason(GZ_CANCEL_OPPOSITE_BREAK), g_setup_sm.CountTerminalByReason(GZ_CANCEL_NEW_VALID_SETUP),
              g_setup_sm.CountTerminalByReason(GZ_CANCEL_SESSION_END), g_setup_sm.CountTerminalByReason(GZ_CANCEL_DATA_END));
   report += "At most one non-terminal setup per direction is ever left standing after a new leg\n";
   report += "is created (see T41); an opposite-direction break cancels whatever is still open on\n";
   report += "the other side (see T42). ENTERED is assigned by Phase 5's Entry Engine; EXITED is now\n";
   report += "assigned by Phase 6's Exit Engine (see below) whenever a trade closes.\n\n";

   report += "--- Phase 5: Entry Engine + Historical Trade Simulator ---\n";
   report += StringFormat("EntryModel=%s FibRatio=%.3f ConfirmationCandles=%d PenetrationAtrMult=%.2f\n",
              EnumToString(InpEntryModel), InpEntryFibRatio, InpConfirmationCandles, InpEntryPenetrationAtrMult);
   report += StringFormat("Trades=%d  Setups ENTERED=%d  Setups CANCELLED(INVALID_PENETRATION)=%d\n",
              g_trade_count, g_setup_sm.CountByState(GZ_SETUP_ENTERED),
              g_setup_sm.CountTerminalByReason(GZ_CANCEL_INVALID_PENETRATION));
   report += "Granularity: TOUCH/LIMIT/M1_CONFIRMATION evaluate at M1 (execution) granularity;\n";
   report += "CLOSE_CONFIRMATION evaluates at M5 (structure) granularity - see GZ_EntryEngine.mqh.\n";
   report += "No lookahead: CGZTradeSimulator only ever lets an M1 bar see structure state as of the\n";
   report += "PREVIOUS closed M5 bar, never the still-forming one it temporally belongs to (see T53).\n";
   report += "initial_risk is a reserved 0.0 placeholder - it requires a stop-loss price, which is\n";
   report += "explicitly Phase 6 (Exit Engine) scope (see GZ_EntryTypes.mqh design note 2).\n\n";

   report += "--- Phase 6: Exit Engine (SL/TP/BE) ---\n";
   report += StringFormat("SlModel=%s SlBufferAtrMult=%.2f SlAtrMult=%.2f TpRMultiple=%.2fR BeTriggerR=%.2fR BeLevelMode=%s BeLevelOffsetR=%.2f ConflictPolicy=%s ForceSessionExit=%s\n",
              EnumToString(InpSlModel), InpSlBufferAtrMult, InpSlAtrMult, InpTpRMultiple, InpBeTriggerR,
              EnumToString(InpBeLevelMode), InpBeLevelOffsetR, EnumToString(InpIntrabarConflictPolicy), InpForceSessionExit?"true":"false");
   report += StringFormat("Exits=%d  Still open=%d  TP_HIT=%d  SL_HIT=%d  BREAK_EVEN=%d  SESSION_EXIT=%d  DATA_END=%d\n",
              g_exit_count, g_exit_engine.OpenCount(), g_exit_engine.CountByReason(GZ_EXIT_TP_HIT),
              g_exit_engine.CountByReason(GZ_EXIT_SL_HIT), g_exit_engine.CountByReason(GZ_EXIT_BREAK_EVEN),
              g_exit_engine.CountByReason(GZ_EXIT_SESSION_EXIT), g_exit_engine.CountByReason(GZ_EXIT_DATA_END));
   report += "Granularity: exit management (SL/TP/BE) runs at M1 (execution) granularity for every\n";
   report += "trade regardless of its entry model's own granularity (see GZ_ExitEngine.mqh).\n";
   report += "Same-bar ordering (documented, not Roadmap-specified): SL/TP hit checked before BE\n";
   report += "arming, BE arming before SESSION_EXIT, on any one bar (see T57-T61 and header notes).\n";
   report += "Intrabar SL/TP conflict (both touched on one bar) is always recorded (intrabar_conflict)\n";
   report += "regardless of which policy resolves it (see T60). ENTERED->EXITED is now wired up on\n";
   report += "every closed trade (see T64). realized_r is the trade's terminal R-multiple only - the\n";
   report += "full R-multiple path / running MAE/MFE is Phase 7 scope, implemented below.\n\n";

   report += "--- Phase 7: MAE/MFE + R-Path + Event Ledger ---\n";
   report += StringFormat("Journals=%d  Still open=%d  AvgMAE=%.3fR  AvgMFE=%.3fR  Reach>=1R=%d  Reach>=2R=%d  Reach>=3R=%d\n",
              g_journal_count, g_journal_engine.OpenCount(), g_journal_engine.AverageMae(), g_journal_engine.AverageMfe(),
              g_journal_engine.ReachCountAtIndex(1), g_journal_engine.ReachCountAtIndex(3), g_journal_engine.ReachCountAtIndex(5));
   report += StringFormat("Ledger events=%d  SETUP_VALID=%d  SETUP_CANCELLED=%d  SETUP_INVALIDATED=%d  ENTRY=%d  EXIT=%d  REJECTION=%d  FILTER_RESULT=%d\n",
              g_ledger_event_count, g_event_ledger.CountByType(GZ_LEDGER_SETUP_VALID), g_event_ledger.CountByType(GZ_LEDGER_SETUP_CANCELLED),
              g_event_ledger.CountByType(GZ_LEDGER_SETUP_INVALIDATED), g_event_ledger.CountByType(GZ_LEDGER_ENTRY),
              g_event_ledger.CountByType(GZ_LEDGER_EXIT), g_event_ledger.CountByType(GZ_LEDGER_REJECTION),
              g_event_ledger.CountByType(GZ_LEDGER_FILTER_RESULT));
   report += "Granularity: MAE/MFE tracking runs at M1 (execution) granularity, same choice already\n";
   report += "made by Phase 6's Exit Engine (see GZ_JournalEngine.mqh). Reach Matrix (0.5R-5R, 10\n";
   report += "levels) records the first time each favorable R-level was reached, regardless of the\n";
   report += "trade's eventual outcome (see T66). MAE/MFE stop updating the instant a trade closes -\n";
   report += "no leakage from bars after exit (see T67). The 'R-multiple path' Roadmap item is\n";
   report += "satisfied as a bounded Reach-Matrix + MAE/MFE + final-R summary rather than a stored\n";
   report += "continuous per-bar curve (see GZ_JournalTypes.mqh design note 1 - a documented scope\n";
   report += "interpretation, not a silently dropped feature). The Event Ledger is built once,\n";
   report += "deterministically, from already-final Setup/Entry/Exit state at the end of each replay\n";
   report += "(no bar-by-bar hook needed for it - see GZ_EventLedger.mqh); REJECTION/FILTER_RESULT were\n";
   report += "reserved event types with no producer through Phase 9 (T72 still asserts a BARE\n";
   report += "BuildFromFinalState() replay never emits either). Phase 10's Filter Engine is now that\n";
   report += "producer - see below.\n\n";

   report += "--- Phase 8: Metrics + Reporting ---\n";
   report += StringFormat("ClosedTrades=%d  Winners=%d  Losers=%d  WinRate=%.1f%%  NetR=%.3f  AvgR/Expectancy=%.3f  ProfitFactor=%s\n",
              g_metrics.trade.trade_count, g_metrics.trade.winners, g_metrics.trade.losers, g_metrics.trade.win_rate*100.0,
              g_metrics.trade.net_r, g_metrics.trade.avg_r,
              g_metrics.trade.profit_factor_undefined ? "UNDEFINED(inf)" : DoubleToString(g_metrics.trade.profit_factor,3));
   report += StringFormat("AvgWinR=%.3f  AvgLossR=%.3f  MaxDD=%.3fR  AvgDD=%.3fR  MaxDDLen=%d trades  MaxWinStreak=%d  MaxLoseStreak=%d\n",
              g_metrics.trade.avg_win_r, g_metrics.trade.avg_loss_r, g_metrics.risk.max_drawdown_r, g_metrics.risk.avg_drawdown_r,
              g_metrics.risk.max_drawdown_duration_trades, g_metrics.risk.max_winning_streak, g_metrics.risk.max_losing_streak);
   report += StringFormat("Behavior: AvgMAE=%.3fR  AvgMFE=%.3fR  AvgDuration=%.0fs  AvgTimeToMAE=%.0fs  AvgTimeToMFE=%.0fs\n",
              g_metrics.behavior.avg_mae_r, g_metrics.behavior.avg_mfe_r, g_metrics.behavior.avg_duration_seconds,
              g_metrics.behavior.avg_time_to_mae_seconds, g_metrics.behavior.avg_time_to_mfe_seconds);
   report += StringFormat("Range covered: %s .. %s\n",
              TimeToString(g_metrics.range_start), TimeToString(g_metrics.range_end));
   report += StringFormat("By direction: LONG n=%d net_r=%.3f win_rate=%.1f%%  |  SHORT n=%d net_r=%.3f win_rate=%.1f%%\n",
              g_metrics.by_direction[0].stats.trade_count, g_metrics.by_direction[0].stats.net_r, g_metrics.by_direction[0].stats.win_rate*100.0,
              g_metrics.by_direction[1].stats.trade_count, g_metrics.by_direction[1].stats.net_r, g_metrics.by_direction[1].stats.win_rate*100.0);
   report += StringFormat("By session:   INSIDE n=%d net_r=%.3f win_rate=%.1f%%  |  OUTSIDE n=%d net_r=%.3f win_rate=%.1f%%\n",
              g_metrics.by_session[0].stats.trade_count, g_metrics.by_session[0].stats.net_r, g_metrics.by_session[0].stats.win_rate*100.0,
              g_metrics.by_session[1].stats.trade_count, g_metrics.by_session[1].stats.net_r, g_metrics.by_session[1].stats.win_rate*100.0);
   report += "Population: CLOSED trades only (an open trade contributes to no total/bucket - see\n";
   report += "GZ_MetricsTypes.mqh design note 1). All metrics are R-based, not account currency (no\n";
   report += "position-sizing/leverage model exists anywhere in Phases 1-7 - design note 2). Expectancy\n";
   report += "and Average R are intentionally identical (design note 3). Profit Factor is flagged\n";
   report += "UNDEFINED, never a fabricated finite number, when winners exist with zero losing R\n";
   report += "(design note 4, see T76). Drawdown/streaks run over the closed-trade R equity curve in\n";
   report += "exit-chronological order; Max Drawdown Duration is in TRADE COUNT, not wall-clock time\n";
   report += "(design note 5, see T77/T78). Hour/Day-of-week/Month/Direction/Session breakdowns use the\n";
   report += "same formulas as the overall total, applied per bucket (design note 6, see T80-T82);\n";
   report += "'Date range' is reported as the population's own [range_start,range_end] span rather than\n";
   report += "re-implemented as arbitrary slicing, which is Phase 9's Experiment Runner job (see T85).\n";
   report += "Filter Diagnostics (Setups/Trades before-after, Rejections, metric deltas) is now populated\n";
   report += "by diffing an unfiltered vs. Phase-10-filtered population (design note 7, see T106) - see\n";
   report += "the Phase 10 section below for this run's actual numbers.\n\n";

   report += "--- Phase 9: Experiment Configuration + Runner ---\n";
   if(g_experiment_ran)
     {
      report += StringFormat("Experiment %s  Dataset=%s  StrategyVersion=%s\n",
                 g_experiment_result.id, g_experiment_result.dataset_id, g_experiment_result.strategy_version);
      report += StringFormat("Window covered: %s .. %s (recent-window demo, see design note below)\n",
                 TimeToString(g_experiment_result.range_start), TimeToString(g_experiment_result.range_end));
      report += StringFormat("Swings=%d  Legs=%d  Setups=%d  Trades=%d  Exits=%d  NetR=%.3f  WinRate=%.1f%%\n",
                 g_experiment_result.swing_count, g_experiment_result.leg_count, g_experiment_result.setup_count,
                 g_experiment_result.trade_count, g_experiment_result.exit_count,
                 g_experiment_result.metrics.trade.net_r, g_experiment_result.metrics.trade.win_rate*100.0);
      report += StringFormat("M1 validation=%d  M5 validation=%d  Warnings=%d",
                 (int)g_experiment_result.m1_validation_status, (int)g_experiment_result.m5_validation_status,
                 g_experiment_result.warning_count);
      if(g_experiment_result.warning_count>0)
        {
         report += " (";
         for(int w=0; w<g_experiment_result.warning_count; w++)
            report += (w>0 ? ", " : "") + g_experiment_result.warnings[w];
         report += ")";
        }
      report += "\n";
     }
   else
      report += "Skipped (no M5 data loaded).\n";
   report += "Modes (Roadmap SINGLE/SWEEP/GRID/BATCH) are one execution primitive - CGZExperimentRunner.RunSingle()\n";
   report += "/.RunBatch() run N already-built GZ_ExperimentConfig records and return N GZ_ExperimentResult\n";
   report += "records; the mode only records how the caller assembled that list (design note 2,\n";
   report += "GZ_ExperimentTypes.mqh). RunBatch() enforces the Roadmap's own 'stage research, do not run one\n";
   report += StringFormat("huge Grid at once' rule as an actual cap (InpExperimentMaxBatchSize, default %d) -\n", GZ_DEFAULT_MAX_EXPERIMENT_BATCH_SIZE);
   report += "an oversized batch is REJECTED outright (see T92), never silently truncated. The single experiment\n";
   report += "above reuses the SAME configuration the direct Phase 2-8 pipeline used above, over a recent\n";
   report += "InpExperimentWindowM5Bars-bar window (default 1000) of the SAME already-loaded/validated data\n";
   report += "rather than the full requested range - Phase 2-8's correctness already ran (and was tested,\n";
   report += "T01-T86) on the full range above, so re-running the whole multi-month pipeline a second time here\n";
   report += "would only double this EA's runtime for no new information (see T87-T96 for full-pipeline and\n";
   report += "sweep/batch coverage on synthetic, deterministic data instead).\n\n";

   report += "--- Phase 10: Filter Engine ---\n";
   report += StringFormat("Modes: BreakQuality=%s LegQuality=%s Volume=%s Volatility=%s VWAP=%s M15Context=%s Session=%s News=%s\n",
              GZFilterModeToString(InpFilterBreakQualityMode), GZFilterModeToString(InpFilterLegQualityMode),
              GZFilterModeToString(InpFilterVolumeMode), GZFilterModeToString(InpFilterVolatilityMode),
              GZFilterModeToString(InpFilterVwapMode), GZFilterModeToString(InpFilterM15ContextMode),
              GZFilterModeToString(InpFilterSessionMode), GZFilterModeToString(InpFilterNewsMode));
   report += StringFormat("SetupsBefore=%d  SetupsAfter=%d  TradesBefore=%d  TradesAfter=%d  Rejections=%d\n",
              g_metrics.filters.setups_before, g_metrics.filters.setups_after,
              g_metrics.filters.trades_before, g_metrics.filters.trades_after, g_metrics.filters.rejections);
   report += StringFormat("Deltas (filtered-unfiltered): WinRate=%.4f  ProfitFactor=%.4f  Expectancy=%.4f  MaxDD=%.4fR  TradeCount=%d\n",
              g_metrics.filters.win_rate_delta, g_metrics.filters.profit_factor_delta,
              g_metrics.filters.expectancy_delta, g_metrics.filters.max_drawdown_delta, g_metrics.filters.trade_count_delta);
   report += "Every filter mode defaults to OFF, so with the default inputs above SetupsAfter==SetupsBefore\n";
   report += "and every delta is exactly 0 (T97, and see T106 for the ComputeFiltered() diff mechanism in\n";
   report += "isolation) - Phase 10 changes nothing about the Phase 1-9 trade population until a filter is\n";
   report += "explicitly enabled via EA input. 5 filters are REAL/data-backed (Break Quality, Leg Quality,\n";
   report += "Volume, Volatility - all ATR/rolling-average thresholds measured at the setup's own\n";
   report += "BREAK_CONFIRMED moment, no lookahead; Session - reuses the same Time/Session Engine every\n";
   report += "other phase already uses). 3 are RESERVED stubs that always report NOT_AVAILABLE (VWAP, M15\n";
   report += "Context, News) - each was explicitly OUT OF SCOPE in the Phase 1 spec and never built by any\n";
   report += "later phase (see GZ_FilterTypes.mqh design note 1); NOT_AVAILABLE never silently becomes PASS\n";
   report += "for ANY enabled filter (explicit Roadmap requirement, see T99/T104) - enabling one of the 3\n";
   report += "reserved filters therefore rejects every setup until a later phase supplies real data for it.\n";
   report += "EXCLUDE mode is the mirror image of INCLUDE (keeps FAIL instead of PASS, see T100); an OFF\n";
   report += "filter never gates anything regardless of its own result (see T97). The Event Ledger now\n";
   report += "carries one FILTER_RESULT row per evaluated setup and one REJECTION row per closed trade whose\n";
   report += "setup's combined decision rejected it (see Phase 7 section above for the updated counts).\n\n";

   report += "--- Phase 11: Filter Combination Research ---\n";
   if(g_phase11_ran)
     {
      report += StringFormat("R11-A (single filter): %d combos run  |  R11-B (two-filter): %d combos run  |  R11-C (limited multi-filter): %d combos run\n",
                 ArraySize(g_r11a_results), ArraySize(g_r11b_results), ArraySize(g_r11c_results));
      report += "R11-A results (setups_after/trades_after vs unfiltered, deltas = filtered-unfiltered):\n";
      for(int ra=0; ra<ArraySize(g_r11a_results); ra++)
        {
         GZ_FilterComboResult r = g_r11a_results[ra];
         report += StringFormat("  %s %s setups=%d/%d trades=%d/%d net_r=%.3f exp_delta=%.4f pf_delta=%.4f dd_delta=%.4f%s\n",
                    r.id, r.label, r.diagnostics.setups_after, r.diagnostics.setups_before,
                    r.diagnostics.trades_after, r.diagnostics.trades_before, r.metrics_with.trade.net_r,
                    r.diagnostics.expectancy_delta, r.diagnostics.profit_factor_delta, r.diagnostics.max_drawdown_delta,
                    r.reserved_filter_used ? "  [RESERVED-ALWAYS-REJECTS]" : "");
        }
      report += "R11-B results:\n";
      for(int rb=0; rb<ArraySize(g_r11b_results); rb++)
        {
         GZ_FilterComboResult r = g_r11b_results[rb];
         report += StringFormat("  %s %s setups=%d/%d trades=%d/%d net_r=%.3f exp_delta=%.4f pf_delta=%.4f dd_delta=%.4f%s\n",
                    r.id, r.label, r.diagnostics.setups_after, r.diagnostics.setups_before,
                    r.diagnostics.trades_after, r.diagnostics.trades_before, r.metrics_with.trade.net_r,
                    r.diagnostics.expectancy_delta, r.diagnostics.profit_factor_delta, r.diagnostics.max_drawdown_delta,
                    r.reserved_filter_used ? "  [RESERVED-ALWAYS-REJECTS]" : "");
        }
      if(ArraySize(g_r11c_results)>0)
        {
         report += "R11-C results (limited multi-filter, filters chosen only from R11-A's own ranking):\n";
         for(int rc=0; rc<ArraySize(g_r11c_results); rc++)
           {
            GZ_FilterComboResult r = g_r11c_results[rc];
            report += StringFormat("  %s %s setups=%d/%d trades=%d/%d net_r=%.3f exp_delta=%.4f pf_delta=%.4f dd_delta=%.4f\n",
                       r.id, r.label, r.diagnostics.setups_after, r.diagnostics.setups_before,
                       r.diagnostics.trades_after, r.diagnostics.trades_before, r.metrics_with.trade.net_r,
                       r.diagnostics.expectancy_delta, r.diagnostics.profit_factor_delta, r.diagnostics.max_drawdown_delta);
           }
        }
      else
         report += "R11-C: no combo built (fewer than 3 eligible non-reserved R11-A candidates - a \"multi\" combo needs at least 3).\n";
      report += StringFormat("Best (highest expectancy_delta, trades_after>0): R11-A=%s  R11-B=%s  R11-C=%s\n",
                 (g_r11a_best_idx>=0)?g_r11a_results[g_r11a_best_idx].label:"n/a",
                 (g_r11b_best_idx>=0)?g_r11b_results[g_r11b_best_idx].label:"n/a",
                 (g_r11c_best_idx>=0)?g_r11c_results[g_r11c_best_idx].label:"n/a");
      report += "\"Best\" above is a report convenience ONLY - it is never auto-selected as a chosen strategy;\n";
      report += "picking a single best historical number without checking its neighborhood is exactly what\n";
      report += "Roadmap Phase 12 (Robustness/Sensitivity) exists to catch. Filters are POST-HOC masks over\n";
      report += "the SAME Phase 2-9 setup/trade population every combo in this sweep shares - no pipeline\n";
      report += "re-simulation per combo (design note 2, GZ_FilterComboTypes.mqh); every combo's config is\n";
      report += "fully reconstructable from its own stored GZ_FilterSetConfig (design note 3, see T116).\n";
     }
   else
      report += "Skipped (InpRunPhase11=false).\n";
   report += StringFormat("InpFilterComboIncludeReserved=%s (VWAP/M15 Context/News combos %s; see T110 - a reserved\n",
              InpFilterComboIncludeReserved?"true":"false", InpFilterComboIncludeReserved?"WERE attempted and deterministically rejected every setup":"were NOT attempted");
   report += "filter is always NOT_AVAILABLE and never silently auto-passes). InpFilterComboR11CTopN=";
   report += StringFormat("%d (R11-C builds one combo per size from 3 up to this many top-ranked R11-A filters,\n", InpFilterComboR11CTopN);
   report += StringFormat("clamped to however many are eligible). InpFilterComboMaxBatchSize=%d enforces the\n", InpFilterComboMaxBatchSize);
   report += "Roadmap's own \"stage research, don't run one huge Grid at once\" rule (see T113).\n\n";

   report += "--- Phase 12: Robustness + Sensitivity Research ---\n";
   if(g_phase12_ran)
     {
      report += StringFormat("%d axis-sweep(s) run over the SAME recent window Phase 9 used (window=[%s .. %s]):\n",
                 ArraySize(g_robustness_results), TimeToString(g_experiment_result.range_start), TimeToString(g_experiment_result.range_end));
      for(int rr=0; rr<ArraySize(g_robustness_results); rr++)
        {
         GZ_RobustnessSweepResult res = g_robustness_results[rr];
         report += StringFormat("  %s axis=%s baseline=%.4f points=%d/%d run:\n",
                    res.id, res.param_label, res.baseline_value, res.point_count, res.point_count);
         for(int pi=0; pi<res.point_count; pi++)
            report += StringFormat("    %s=%.4f -> trades=%d net_r=%.3f expectancy=%.4f%s\n",
                       res.param_label, res.points[pi].param_value, res.points[pi].result.trade_count,
                       res.points[pi].result.metrics.trade.net_r, res.points[pi].result.metrics.trade.expectancy,
                       (pi==res.best_idx)?"  <-- best (see flags below before adopting)":"");
         report += StringFormat("  Flags: narrow_peak=%s flat_region=%s unstable_zone=%s parameter_sensitive=%s | safe_to_adopt_best=%s\n",
                    res.narrow_peak?"true":"false", res.flat_region?"true":"false", res.unstable_zone?"true":"false",
                    res.parameter_sensitive?"true":"false", res.safe_to_adopt_best?"true":"false");
         for(int ni=0; ni<res.note_count; ni++)
            report += StringFormat("    note: %s\n", res.notes[ni]);
        }
      report += "safe_to_adopt_best=false means the Roadmap's own warning applies here: \"the single highest\n";
      report += "historical value must NOT be accepted alone as the final choice\" - see narrow_peak/\n";
      report += "unstable_zone above. Each point above is a FULL, independent Phase 2-8 re-simulation\n";
      report += "(NOT a post-hoc mask like Phase 11 - see GZ_RobustnessTypes.mqh design note 1); an\n";
      report += "out-of-domain requested value is skipped and noted, never silently clamped or run anyway.\n";
     }
   else
      report += "Skipped (InpRunPhase12=false).\n";
   report += StringFormat("InpRobustnessAxis1=%s InpRobustnessAxis2=%s InpRobustnessMaxBatchSize=%d.\n\n",
              EnumToString(InpRobustnessAxis1), EnumToString(InpRobustnessAxis2), InpRobustnessMaxBatchSize);

   report += "--- Phase 13: Walk-Forward Research ---\n";
   if(g_phase13_ran)
     {
      GZ_WalkForwardResult wf = g_wf_result;
      string cand = "";
      for(int ci=0; ci<wf.config.candidate_count; ci++)
         cand += ((ci>0)?", ":"") + DoubleToString(wf.config.candidates[ci], 4);
      report += StringFormat("%s axis=%s baseline=%.4f dataset=%s\n", wf.id, wf.axis_label, wf.baseline_value, wf.dataset_id);
      report += StringFormat("candidates=[%s] (values outside the axis's domain are skipped per window, never clamped)\n", cand);
      report += StringFormat("train=%dd validate=%dd step=%dd (calendar days) min_trades=%d min_validation_trades=%d require_safe_selection=%s\n",
                 wf.config.train_days, wf.config.validate_days, wf.config.step_days, wf.config.min_trades,
                 wf.config.min_validation_trades, wf.config.require_safe_selection?"true":"false");
      report += StringFormat("windows=%d%s selected=%d validated=%d low_validation_trades=%d positive_windows=%d\n",
                 wf.window_count, wf.windows_capped?" (CAPPED)":"", wf.windows_selected, wf.windows_validated,
                 wf.windows_low_validation_trades, wf.positive_windows);
      for(int wi=0; wi<wf.window_count; wi++)
        {
         GZ_WalkForwardWindow ww = wf.windows[wi];
         report += StringFormat("  W%d train=[%s .. %s) validate=[%s .. %s) M5 bars train=%d validate=%d\n",
                    wi, TimeToString(ww.train_start), TimeToString(ww.train_end),
                    TimeToString(ww.validate_start), TimeToString(ww.validate_end), ww.train_m5_bars, ww.validate_m5_bars);
         report += StringFormat("     status=%s candidates run=%d eligible=%d raw_best=%s narrow_peak=%s unstable_zone=%s safe_to_adopt=%s\n",
                    GZWfSelectionStatusToString(ww.status), ww.train_candidates_run, ww.train_candidates_eligible,
                    ww.train_has_best?DoubleToString(ww.train_best_value,4):"n/a",
                    ww.train_narrow_peak?"true":"false", ww.train_unstable_zone?"true":"false", ww.train_safe_to_adopt?"true":"false");
         if(ww.HasSelection())
           {
            report += StringFormat("     selected=%s=%.4f | train: trades=%d expectancy=%.4f\n",
                       wf.axis_label, ww.selected_value, ww.train_stats.trade_count, ww.train_stats.expectancy);
            if(ww.validation_ran)
               report += StringFormat("     validation: trades=%d net_r=%.3f expectancy=%.4f max_dd=%.3fR%s | fixed baseline on same slice: trades=%d net_r=%.3f expectancy=%.4f\n",
                          ww.val_stats.trade_count, ww.val_stats.net_r, ww.val_stats.expectancy, ww.val_risk.max_drawdown_r,
                          ww.low_validation_trades?" LOW_VALIDATION_TRADES":"",
                          ww.baseline_val_stats.trade_count, ww.baseline_val_stats.net_r, ww.baseline_val_stats.expectancy);
           }
        }
      report += StringFormat("Pooled out-of-sample (all validated windows): trades=%d winners=%d losers=%d net_r=%.3f expectancy=%.4f win_rate=%.1f%% profit_factor=%s\n",
                 wf.pooled_trades, wf.pooled_winners, wf.pooled_losers, wf.pooled_net_r, wf.pooled_expectancy, wf.pooled_win_rate*100.0,
                 wf.pooled_profit_factor_undefined ? "undefined(no losing R)" : DoubleToString(wf.pooled_profit_factor,3));
      report += StringFormat("Fixed baseline over the SAME validation slices: trades=%d net_r=%.3f expectancy=%.4f | selection edge (pooled minus baseline expectancy)=%s\n",
                 wf.baseline_pooled_trades, wf.baseline_pooled_net_r, wf.baseline_pooled_expectancy,
                 wf.selection_edge_defined ? StringFormat("%.4fR", wf.selection_edge_expectancy) : "undefined");
      report += StringFormat("Mean training expectancy=%.4f mean validation expectancy=%.4f walk-forward efficiency=%s\n",
                 wf.mean_train_expectancy, wf.mean_val_expectancy,
                 wf.efficiency_defined ? DoubleToString(wf.walk_forward_efficiency,3) : "undefined");
      report += StringFormat("Parameter stability: distinct selected values=%d most common chosen %dx changes between consecutive windows=%d range=[%.4f .. %.4f]\n",
                 wf.distinct_selected_values, wf.most_common_selected_count, wf.selection_changes, wf.selected_value_min, wf.selected_value_max);
      report += StringFormat("Flags: param_unstable=%s overfit_suspect=%s negative_oos=%s validation_overlap=%s\n",
                 wf.param_unstable?"true":"false", wf.overfit_suspect?"true":"false", wf.negative_oos?"true":"false", wf.validation_overlap?"true":"false");
      for(int ni=0; ni<wf.note_count; ni++)
         report += StringFormat("  note: %s\n", wf.notes[ni]);
      report += "Selection used ONLY each window's own training bars (validation data is not even loaded into the\n";
      report += "training sweep - see T141); every candidate is a FULL Phase 2-8 re-simulation of that window's slice\n";
      report += "from a cold start (warm-up bars are consumed inside the window - documented limitation, see\n";
      report += "GZ_WalkForwardTypes.mqh design note 4). Results here are research diagnostics, not a trading signal.\n";
     }
   else
      report += "Skipped (InpRunPhase13=false, or InpWfAxis was the sentinel, or no M5 data).\n";
   report += StringFormat("InpWfAxis=%s InpWfTrainDays=%d InpWfValidateDays=%d InpWfStepDays=%d InpWfMinTrades=%d InpWfMinValidationTrades=%d InpWfRequireSafeSelection=%s.\n\n",
              EnumToString(InpWfAxis), InpWfTrainDays, InpWfValidateDays, InpWfStepDays, InpWfMinTrades,
              InpWfMinValidationTrades, InpWfRequireSafeSelection?"true":"false");

   report += "--- Phase 14: Monte Carlo Research ---\n";
   if(g_phase14_ran)
     {
      for(int mi=0; mi<2; mi++)
        {
         GZ_McResult mc;
         if(mi==0) mc = g_mc_order; else mc = g_mc_bootstrap;
         report += StringFormat("%s mode=%s status=%s seed=%u simulations=%d/%d closed trades=%d\n",
                    mc.id, GZMcModeToString(mc.mode), GZMcStatusToString(mc.status), mc.seed,
                    mc.simulations_run, mc.simulations_requested, mc.trade_count);
         if(mc.status==GZ_MC_OK)
           {
            report += StringFormat("  Historical (original order): net_r=%.3f max_drawdown=%.3fR max_losing_streak=%d\n",
                       mc.hist_net_r, mc.hist_max_dd, mc.hist_max_losing_streak);
            report += "  Distribution across simulations:      mean     min     p05     p25  median     p75     p95     max (worst sim #)\n";
            report += StringFormat("    net R                          %8.3f%8.3f%8.3f%8.3f%8.3f%8.3f%8.3f%8.3f (min sim #%d)\n",
                       mc.net_r.mean, mc.net_r.minimum, mc.net_r.p05, mc.net_r.p25, mc.net_r.median, mc.net_r.p75, mc.net_r.p95, mc.net_r.maximum, mc.net_r.min_sim_index);
            report += StringFormat("    max drawdown (R)               %8.3f%8.3f%8.3f%8.3f%8.3f%8.3f%8.3f%8.3f (max sim #%d)\n",
                       mc.max_dd.mean, mc.max_dd.minimum, mc.max_dd.p05, mc.max_dd.p25, mc.max_dd.median, mc.max_dd.p75, mc.max_dd.p95, mc.max_dd.maximum, mc.max_dd.max_sim_index);
            report += StringFormat("    max losing streak (trades)     %8.2f%8.0f%8.1f%8.1f%8.1f%8.1f%8.1f%8.0f (max sim #%d)\n",
                       mc.max_losing_streak.mean, mc.max_losing_streak.minimum, mc.max_losing_streak.p05, mc.max_losing_streak.p25,
                       mc.max_losing_streak.median, mc.max_losing_streak.p75, mc.max_losing_streak.p95, mc.max_losing_streak.maximum, mc.max_losing_streak.max_sim_index);
            report += StringFormat("  Worst simulated cases: max drawdown %.3fR (sim #%d), losing streak %.0f trades (sim #%d), net R %.3f (sim #%d)\n",
                       mc.max_dd.maximum, mc.max_dd.max_sim_index, mc.max_losing_streak.maximum, mc.max_losing_streak.max_sim_index,
                       mc.net_r.minimum, mc.net_r.min_sim_index);
            report += StringFormat("  Historical rank: %.1f%% of simulations had a max drawdown <= the historical %.3fR; %.1f%% had a losing streak <= the historical %d. (near 100%% = the actual order was unusually BAD, near 0%% = unusually GOOD)\n",
                       mc.hist_dd_rank*100.0, mc.hist_max_dd, mc.hist_streak_rank*100.0, mc.hist_max_losing_streak);
            report += StringFormat("  Share of simulations ending below 0R: %.1f%%\n", mc.frac_net_r_negative*100.0);
            report += "  Equity-path variation (cumulative R after N trades):  trades  historical     p05     p50     p95\n";
            for(int ci=0; ci<mc.checkpoint_count; ci++)
               report += StringFormat("                                                        %6d %10.3f %8.3f %8.3f %8.3f\n",
                          mc.checkpoint_trades[ci], mc.hist_equity[ci], mc.eq_p05[ci], mc.eq_p50[ci], mc.eq_p95[ci]);
           }
         for(int ni=0; ni<mc.note_count; ni++)
            report += StringFormat("  note: %s\n", mc.notes[ni]);
        }
      //--- cross-check: the MC's own drawdown/streak formulas vs Phase 8's, on the SAME series
      if(g_mc_order.status==GZ_MC_OK)
        {
         bool dd_ok = (MathAbs(g_mc_order.hist_max_dd - g_metrics.risk.max_drawdown_r)<0.0001);
         bool st_ok = (g_mc_order.hist_max_losing_streak == g_metrics.risk.max_losing_streak);
         report += StringFormat("Consistency with Phase 8 on the same series: max drawdown MC=%.3fR Phase8=%.3fR (%s), max losing streak MC=%d Phase8=%d (%s)\n",
                    g_mc_order.hist_max_dd, g_metrics.risk.max_drawdown_r, dd_ok?"match":"MISMATCH",
                    g_mc_order.hist_max_losing_streak, g_metrics.risk.max_losing_streak, st_ok?"match":"MISMATCH");
        }
      report += "Both modes assume trades are exchangeable (no serial dependence, no regime effects) - a shuffle cannot\n";
      report += "reveal clustering that the real sequence may contain. The historical ledger was not modified; results are\n";
      report += "research diagnostics on the whole loaded range, not a forecast and not a trading signal.\n";
     }
   else
      report += "Skipped (InpRunPhase14=false).\n";
   report += StringFormat("InpMcSimulations=%d InpMcSeed=%u InpMcMaxSimulations=%d.\n\n", InpMcSimulations, InpMcSeed, InpMcMaxSimulations);

   report += "--- Phase 15: Final OOS ---\n";
   if(g_phase15_ran)
     {
      GZ_FinalOosResult fo = g_oos_result;
      report += StringFormat("%s status=%s strategy=%s\n", fo.id, GZOosStatusToString(fo.status), fo.strategy_version);
      report += StringFormat("Development range requested [%s .. %s]; Final OOS range requested [%s .. %s] (loaded only by Phase 15)\n",
                 TimeToString(fo.dev_req_start), TimeToString(fo.dev_req_end), TimeToString(fo.oos_req_start), TimeToString(fo.oos_req_end));
      report += StringFormat("OOS bars loaded: M1=%d M5=%d | OOS validation: M1=%s M5=%s\n", g_oos_m1_bars, g_oos_m5_bars_loaded,
                 EnumToString(fo.oos_m1_status), EnumToString(fo.oos_m5_status));
      if(fo.status==GZ_OOS_OK)
        {
         report += StringFormat("Development actual [%s .. %s] M5 bars=%d | OOS actual [%s .. %s] M5 bars=%d boundary bars dropped=%d\n",
                    TimeToString(fo.dev_first), TimeToString(fo.dev_last), fo.dev_m5_bars,
                    TimeToString(fo.oos_first), TimeToString(fo.oos_last), fo.oos_m5_bars, fo.oos_boundary_bars_dropped);
         report += "                              Development        OOS      delta(OOS-Dev)\n";
         report += StringFormat("  trades                      %11d %10d\n", fo.dev.trade.trade_count, fo.oos.trade.trade_count);
         report += StringFormat("  win rate                    %10.1f%% %9.1f%% %+12.1f pts\n", fo.dev.trade.win_rate*100.0, fo.oos.trade.win_rate*100.0, fo.win_rate_delta*100.0);
         report += StringFormat("  profit factor               %11s %10s %13s\n",
                    fo.dev.trade.profit_factor_undefined ? "undef" : DoubleToString(fo.dev.trade.profit_factor,3),
                    fo.oos.trade.profit_factor_undefined ? "undef" : DoubleToString(fo.oos.trade.profit_factor,3),
                    fo.profit_factor_delta_defined ? DoubleToString(fo.profit_factor_delta,3) : "n/a");
         report += StringFormat("  expectancy (R)              %11.4f %10.4f %+13.4f\n", fo.dev.trade.expectancy, fo.oos.trade.expectancy, fo.expectancy_delta);
         report += StringFormat("  net R                       %11.3f %10.3f\n", fo.dev.trade.net_r, fo.oos.trade.net_r);
         report += StringFormat("  max drawdown (R)            %11.3f %10.3f %+13.3f\n", fo.dev.risk.max_drawdown_r, fo.oos.risk.max_drawdown_r, fo.max_dd_delta);
         report += StringFormat("  max losing streak           %11d %10d\n", fo.dev.risk.max_losing_streak, fo.oos.risk.max_losing_streak);
         report += StringFormat("  avg MAE (R)                 %11.3f %10.3f %+13.3f\n", fo.dev.behavior.avg_mae_r, fo.oos.behavior.avg_mae_r, fo.avg_mae_delta);
         report += StringFormat("  avg MFE (R)                 %11.3f %10.3f %+13.3f\n", fo.dev.behavior.avg_mfe_r, fo.oos.behavior.avg_mfe_r, fo.avg_mfe_delta);
         report += StringFormat("Expectancy retention (OOS/Development): %s\n", fo.retention_defined ? StringFormat("%.1f%%", fo.expectancy_retention*100.0) : "undefined");
         report += StringFormat("Flags: low_oos_trades=%s oos_no_trades=%s oos_negative=%s oos_degraded=%s\n",
                    fo.low_oos_trades?"true":"false", fo.oos_no_trades?"true":"false", fo.oos_negative?"true":"false", fo.oos_degraded?"true":"false");
         report += "OOS distribution by direction:\n";
         for(int di=0; di<GZ_BREAKDOWN_DIRECTION_COUNT; di++)
            report += StringFormat("  %-8s trades=%d win_rate=%.1f%% expectancy=%.4f net_r=%.3f\n", fo.oos.by_direction[di].label,
                       fo.oos.by_direction[di].stats.trade_count, fo.oos.by_direction[di].stats.win_rate*100.0,
                       fo.oos.by_direction[di].stats.expectancy, fo.oos.by_direction[di].stats.net_r);
         report += "OOS distribution by month (months with trades):\n";
         for(int mo=0; mo<GZ_BREAKDOWN_MONTH_COUNT; mo++)
            if(fo.oos.by_month[mo].stats.trade_count>0)
               report += StringFormat("  %-8s trades=%d win_rate=%.1f%% expectancy=%.4f net_r=%.3f\n", fo.oos.by_month[mo].label,
                          fo.oos.by_month[mo].stats.trade_count, fo.oos.by_month[mo].stats.win_rate*100.0,
                          fo.oos.by_month[mo].stats.expectancy, fo.oos.by_month[mo].stats.net_r);
         if(g_phase13_ran && g_wf_result.windows_validated>0)
            report += StringFormat("For reference - Phase 13 walk-forward pooled validation: trades=%d expectancy=%.4f pf=%s\n",
                       g_wf_result.pooled_trades, g_wf_result.pooled_expectancy,
                       g_wf_result.pooled_profit_factor_undefined ? "undef" : DoubleToString(g_wf_result.pooled_profit_factor,3));
        }
      for(int ni=0; ni<fo.note_count; ni++)
         report += StringFormat("  note: %s\n", fo.notes[ni]);
      report += "The OOS range was loaded only by Phase 15 and used for nothing else. ONE frozen configuration was run once on each\n";
      report += "range; nothing was selected or tuned from this result. If you change parameters after reading it, this OOS is\n";
      report += "contaminated - use Phase 16 (freeze, new version) and NEW data for the next OOS. Each range is simulated from a\n";
      report += "cold start (warm-up bars are consumed inside the range).\n";
     }
   else
      report += "Skipped (InpRunPhase15=false).\n";
   report += StringFormat("InpOosStart=%s InpOosEnd=%s InpOosMinTrades=%d (Development range InpRangeStart=%s InpRangeEnd=%s).\n\n",
              TimeToString(InpOosStart), TimeToString(InpOosEnd), InpOosMinTrades, TimeToString(InpRangeStart), TimeToString(InpRangeEnd));

   report += "--- Automated Test Results (T01-T180: T01-T18 Phase 1, T19-T23 Phase 2, T24-T34 Phase 3, T35-T45 Phase 4, T46-T54 Phase 5, T55-T64 Phase 6, T65-T74 Phase 7, T75-T86 Phase 8, T87-T96 Phase 9, T97-T106 Phase 10, T107-T116 Phase 11, T117-T127 Phase 12, T128-T142 Phase 13, T143-T158 Phase 14, T159-T166 Phase 15, T167-T180 Phase 15.5) ---\n";
   int pass = g_harness.PassCount();
   int fail = g_harness.FailCount();
   for(int i=0;i<g_harness.ResultCount();i++)
     {
      GZ_TestResult r = g_harness.GetResult(i);
      report += StringFormat("%s: %s - %s\n", r.id, r.passed?"PASS":"FAIL", r.detail);
     }
   report += StringFormat("\nTOTAL: %d PASS / %d FAIL (of %d)\n\n", pass, fail, g_harness.ResultCount());

   report += "--- Known Limitations / Deferred Work ---\n";
   report += "DEFERRED: Research Freeze (Phase 16), Future Execution Adapter (Phase 17) - not implemented, by design.\n";
   report += "Phases 11-15 ARE now implemented (see their sections above). Phase 13 selects ONE axis value per window\n";
   report += "(single-axis walk-forward); multi-axis selection and anchored/expanding training windows are DEFERRED\n";
   report += "(GZ_WalkForwardTypes.mqh design notes 1 and 3). Phase 14 randomizes the main pipeline's whole closed-trade R\n";
   report += "series; Monte Carlo over walk-forward or OOS trades is DEFERRED. Phase 15 evaluates the EA's current inputs as\n";
   report += "ONE frozen configuration; freezing/versioning it formally is Phase 16 (DEFERRED).\n";
   report += "Phase 12's axis sweeps demonstrate 2 axes by default\n";
   report += "(InpRobustnessAxis1/2); the other 9 defined in ENUM_GZ_ROBUSTNESS_PARAM (GZ_RobustnessTypes.mqh)\n";
   report += "are equally usable by changing those inputs - no code change needed to sweep a different axis.\n";
   report += "Phase 11: R11-A/B/C sweep Phase 10's own CGZFilterEngine directly as post-hoc\n";
   report += "masks over the already-final Phase 2-9 setup/trade population, rather than through\n";
   report += "CGZExperimentRunner's SINGLE/SWEEP/GRID/BATCH (that runner varies STRATEGY config - pivot\n";
   report += "strength, break/entry/exit parameters, etc. - and re-simulates the full pipeline per config;\n";
   report += "a filter never changes what the strategy engines themselves produce, only which already-\n";
   report += "produced setups/trades are counted, so re-simulating per combo would be wasted, incorrect-by-\n";
   report += "design work - see GZ_FilterComboTypes.mqh design note 2). Any pair naming VWAP/M15 Context is\n";
   report += "still built by the R11-B request list (architecture stays extensible) but is NOT run unless\n";
   report += "InpFilterComboIncludeReserved=true - VWAP/M15 Context/News remain reserved NOT_AVAILABLE stubs\n";
   report += "(see Phase 10 section above) - no VWAP engine, M15 structure engine, or news/economic-calendar\n";
   report += "data source exists anywhere in Phases 1-11; each was explicitly out of scope through this point.\n";
   report += "Weekend-gap classification uses a Saturday-presence heuristic; broker-specific holiday\n";
   report += "calendars are not modeled and would need broker session data if required later.\n";
   report += "SESSION_END (Phase 4, pre-entry setup cancellation) only fires when\n";
   report += "InpApplySessionFilter=true; SESSION_EXIT (Phase 6, open-trade force-close) only fires\n";
   report += "when InpForceSessionExit=true - the two are independent flags on purpose (default both\n";
   report += "false), since the Roadmap does not state either should be on by default. Spread\n";
   report += "assumption is the historical bar's own recorded spread (points), not a separate\n";
   report += "configurable spread model (see GZ_EntryTypes.mqh). entry_fib_ratio (default 0.618),\n";
   report += "sl_atr_mult (default 1.5) and tp_r_multiple (default 2.0) are single configurable\n";
   report += "values with no stated Roadmap baseline - documented conventional defaults, not silently\n";
   report += "assumed (see each type file's design notes). The Reach Matrix/MAE/MFE 'R-multiple path'\n";
   report += "scope interpretation is documented in GZ_JournalTypes.mqh design note 1 (no continuous\n";
   report += "per-bar curve is stored, by design).\n\n";

   report += "--- User Verification Required ---\n";
   report += "USER TEST REQUIRED #1: Compile this project in MetaEditor and attach the EA to a chart\n";
   report += "  for the configured symbol, then copy this Experts-log report back for review.\n";
   report += "USER TEST REQUIRED #2: Confirm actual broker server UTC offset (InpBrokerUtcOffsetHrs)\n";
   report += "  with your broker/terminal (Market Watch -> Symbols -> session, or broker docs), then\n";
   report += "  set InpBrokerOffsetKnown=true once verified. Until then TIMEZONE_STATUS=UNKNOWN.\n\n";

   string final_status;
   bool data_ok = (g_info_m1.total_bars>0 && g_info_m5.total_bars>0);
   if(fail>0)
      final_status = "PHASE 1+2+3+4+5+6+7+8+9+10+11+12+13+14+15 BLOCKED (automated test failure - see detail above)";
   else if(!data_ok)
      final_status = "PHASE 1+2+3+4+5+6+7+8+9+10+11+12+13+14+15 BLOCKED (historical data unavailable for requested symbol/range)";
   else if(!InpBrokerOffsetKnown)
      final_status = "PHASE 1+2+3+4+5+6+7+8+9+10+11+12+13+14+15 BLOCKED (broker UTC offset not yet verified by user)";
   else
      // This report is only ever printed by the EA's own OnInit() running
      // inside MT5, so reaching this branch already proves compile+attach
      // succeeded - there is nothing further to "wait" on.
      final_status = "PHASE 1+2+3+4+5+6+7+8+9+10+11+12+13+14+15 COMPLETE";

   report += "--- Final Status ---\n" + final_status + "\n";
   report += "===================================================\n";

   PrintReportChunked(report);

   int handle = FileOpen("GZ_Phase1_2_3_4_5_6_7_8_9_10_11_12_13_14_15_Report.txt", FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle!=INVALID_HANDLE)
     {
      FileWriteString(handle, report);
      FileClose(handle);
      Print("[GZ] Report written to Common\\Files\\GZ_Phase1_2_3_4_5_6_7_8_9_10_11_12_13_14_15_Report.txt");
     }
   else
     {
      Print("[GZ] WARNING: could not open report file for writing, error=", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Phase 15.5: write the human-readable report + machine-readable   |
//| CSVs (Common\Files). Called after the harness ran, so the        |
//| T167-T180 unit-test results can be embedded.                      |
//+------------------------------------------------------------------+
void EmitPhase155Report()
  {
   if(!g_phase155_ran)
      return;

   string ctx = "";
   ctx += StringFormat("Symbol=%s | Development range InpRangeStart=%s InpRangeEnd=%s | Final OOS (InpOosStart=%s) NOT loaded, NOT inspected (Phase 15 skipped: %s).\n",
                       InpSymbol, TimeToString(InpRangeStart), TimeToString(InpRangeEnd), TimeToString(InpOosStart), g_phase15_ran?"NO - it ran!":"yes");
   ctx += StringFormat("Held identical in every run: entry=%s fib=%.3f penetration=%.2fATR | SL=%s buffer=%.2fATR slATR=%.2f | conflict policy=%s | force_session_exit=%s apply_session_filter=%s | pivot=%d | break buffer=%.2fATR atr_period=%d.\n",
                       EnumToString(InpEntryModel), InpEntryFibRatio, InpEntryPenetrationAtrMult, EnumToString(InpSlModel), InpSlBufferAtrMult, InpSlAtrMult,
                       EnumToString(InpIntrabarConflictPolicy), InpForceSessionExit?"true":"false", InpApplySessionFilter?"true":"false",
                       InpPivotStrength, InpBreakBufferAtrMult, InpAtrPeriod);
   ctx += "Varied: exit_config.tp_r_multiple and exit_config.be_trigger_r ONLY (BE level = Entry, offset 0R; be_level_mode/offset forced for every run).\n";
   ctx += "Same-candle rules (UNCHANGED baseline engine, documented in GZ_ExitEngine.mqh): SL/TP evaluated before BE arming; a newly armed BE stop applies from the NEXT M1 candle;\n";
   ctx += "SL and TP on one candle -> policy SL_FIRST; SL/TP/BE are also evaluated on the trade's own entry candle. Section F counts how often each situation occurs.\n";
   ctx += "Trade order for drawdown/streaks = journal order = trade-ENTRY order (trades overlap; the Phase 8 source comment says 'exit order' but journals are appended at entry). Kept as-is for reproducibility with Phase 8/15.\n\n";

   string ut = "";
   int up = 0, uf = 0;
   for(int i=0;i<g_harness.ResultCount();i++)
     {
      GZ_TestResult r = g_harness.GetResult(i);
      if(StringLen(r.id)<2 || StringGetCharacter(r.id,0)!='T') continue;
      int num = (int)StringToInteger(StringSubstr(r.id,1));
      if(num<167) continue;
      ut += StringFormat("%s: %s - %s\n", r.id, r.passed?"PASS":"FAIL", r.detail);
      if(r.passed) up++; else uf++;
     }
   ut += StringFormat("(Full suite T01-T180: %d PASS / %d FAIL - see the main report.)\n", g_harness.PassCount(), g_harness.FailCount());
   // a failure ANYWHERE in the suite must also block the 15.5 status
   if(g_harness.FailCount()>0 && uf==0) uf = g_harness.FailCount();

   string report = g_rewardbe_engine.BuildReport(ctx, ut, up, uf);
   PrintReportChunked(report);

   string names[3] = {"GZ_Phase155_Report.txt", "GZ_Phase155_Matrix.csv", "GZ_Phase155_Pairwise.csv"};
   string bodies[3];
   bodies[0] = report;
   bodies[1] = g_rewardbe_engine.BuildMatrixCsv();
   bodies[2] = g_rewardbe_engine.BuildPairCsv();
   for(int k=0;k<3;k++)
     {
      int h = FileOpen(names[k], FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(h!=INVALID_HANDLE)
        {
         FileWriteString(h, bodies[k]);
         FileClose(h);
         Print("[GZ] Phase 15.5 output written to Common\\Files\\", names[k]);
        }
      else
         Print("[GZ] WARNING: could not open ", names[k], " for writing, error=", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Runtime marker: proves the EA currently attached/running is compiled
   // from THIS source file. Printed first, before anything else, and via
   // raw Print() (not CGZLogger) so nothing upstream can suppress it.
   Print("[GZ][BUILD] GoldenZoneSTR_Research_RUNTIME_MARKER_20260924_V15_5_REWARD_BE");

   // Runtime Inputs marker: prints the ACTUAL live values of the inputs
   // this specific EA instance is running with (per-attachment values from
   // the MT5 "Inputs" tab, not the source-file defaults) - directly
   // independent of CGZLogger.
   Print(StringFormat(
      "[GZ][RUNTIME INPUTS] Symbol=%s RangeStart=%s RangeEnd=%s BrokerOffset=%d BrokerOffsetKnown=%s",
      InpSymbol,
      TimeToString(InpRangeStart, TIME_DATE|TIME_MINUTES),
      TimeToString(InpRangeEnd,   TIME_DATE|TIME_MINUTES),
      InpBrokerUtcOffsetHrs,
      InpBrokerOffsetKnown ? "true" : "false"));

   g_logger.EnableVerbose(InpVerboseLogging);
   g_p155_only = (InpRunPhase155 && InpPhase155Only);
   if(InpRunPhase155)
      g_logger.Info("RewardBe", StringFormat("Phase 15.5 mode: Final OOS will NOT be loaded (Phase 15 skipped); Phases 11-14 skipped=%s.", g_p155_only?"true":"false"));
   g_logger.Info("Init", "GoldenZone STR Phase 1+2+3+4+5+6+7+8+9+10+11+12+13+14+15 starting up (research/diagnostic mode - no trading).");

   //--- Time engine configuration -----------------------------------------
   GZ_TimeConfig time_cfg;
   time_cfg.dst_mode                = InpDstMode;
   time_cfg.fixed_ny_offset_hours   = InpFixedNyOffsetHrs;
   time_cfg.broker_utc_offset_hours = InpBrokerUtcOffsetHrs;
   time_cfg.broker_offset_known     = InpBrokerOffsetKnown;
   g_time_engine.Configure(time_cfg);

   if(!InpBrokerOffsetKnown)
      g_logger.Warning("Init", "Broker UTC offset not verified by user - TIMEZONE_STATUS=UNKNOWN. UTC/NY conversions use the configured value provisionally.");

   //--- Load historical data ------------------------------------------------
   MqlRates m1[], m5[], m15[];
   Print("[GZ][TRACE][Init] Reached data-loading section - about to call LoadM1/LoadM5 for Symbol=", InpSymbol);
   int n1 = g_provider.LoadM1(InpSymbol, InpRangeStart, InpRangeEnd, m1);
   int n5 = g_provider.LoadM5(InpSymbol, InpRangeStart, InpRangeEnd, m5);
   int n15 = 0;
   if(InpLoadM15)
      n15 = g_provider.LoadM15(InpSymbol, InpRangeStart, InpRangeEnd, m15);

   //--- Validate M1 -----------------------------------------------------------
   g_info_m1.Clear();
   g_info_m1.symbol = InpSymbol;
   g_info_m1.execution_timeframe = PERIOD_M1;
   g_info_m1.start_timestamp = InpRangeStart;
   g_info_m1.end_timestamp   = InpRangeEnd;
   g_info_m1.broker_utc_offset_hours = InpBrokerUtcOffsetHrs;
   g_info_m1.broker_tz_status = InpBrokerOffsetKnown ? GZ_TZ_KNOWN : GZ_TZ_UNKNOWN;
   g_info_m1.total_bars = n1;
   if(n1>0)
     {
      g_info_m1.first_bar_time = m1[0].time;
      g_info_m1.last_bar_time  = m1[n1-1].time;
      g_validator.ValidateOHLC(m1, g_info_m1);
      g_validator.ValidateTimestamps(m1, GZ_SPACING_M1_SECONDS, g_info_m1);
      g_info_m1.spread_availability      = g_provider.SpreadAvailability(m1);
      g_info_m1.tick_volume_availability = g_provider.TickVolumeAvailability(m1);
      g_info_m1.real_volume_availability = g_provider.RealVolumeAvailability(m1);
     }
   else
      g_info_m1.AddError("No M1 data returned for requested symbol/range.");
   g_info_m1.Finalize();

   //--- Validate M5 -----------------------------------------------------------
   g_info_m5.Clear();
   g_info_m5.symbol = InpSymbol;
   g_info_m5.structure_timeframe = PERIOD_M5;
   g_info_m5.start_timestamp = InpRangeStart;
   g_info_m5.end_timestamp   = InpRangeEnd;
   g_info_m5.broker_utc_offset_hours = InpBrokerUtcOffsetHrs;
   g_info_m5.broker_tz_status = InpBrokerOffsetKnown ? GZ_TZ_KNOWN : GZ_TZ_UNKNOWN;
   g_info_m5.total_bars = n5;
   if(n5>0)
     {
      g_info_m5.first_bar_time = m5[0].time;
      g_info_m5.last_bar_time  = m5[n5-1].time;
      g_validator.ValidateOHLC(m5, g_info_m5);
      g_validator.ValidateTimestamps(m5, GZ_SPACING_M5_SECONDS, g_info_m5);
      g_info_m5.spread_availability      = g_provider.SpreadAvailability(m5);
      g_info_m5.tick_volume_availability = g_provider.TickVolumeAvailability(m5);
      g_info_m5.real_volume_availability = g_provider.RealVolumeAvailability(m5);
     }
   else
      g_info_m5.AddError("No M5 data returned for requested symbol/range.");
   g_info_m5.Finalize();

   //--- M1/M5 deterministic sync spot-check (uses real loaded data if available)
   if(n1>0 && n5>0)
     {
      int mid = n1/2;
      int idx = g_validator.FindM5ContextForM1(m1[mid].time, m5);
      g_logger.Info("Sync", StringFormat("Sample M1 bar %s maps to M5 index %d (%s)",
                    TimeToString(m1[mid].time), idx, idx>=0?TimeToString(m5[idx].time):"none"));
     }

   //--- Phase 2: M5 Structure Engine (swing/pivot detection) ------------------
   // Diagnostic only - detects swings over the already-loaded, already-
   // validated M5 range and logs a summary. No leg/break/fib/entry/exit
   // logic consumes this output yet (deferred to Phase 3+).
   g_swing_engine.Init(InpPivotStrength);
   g_swing_count = 0;
   if(n5>0)
     {
      g_swing_count = g_swing_engine.DetectAll(m5, g_swings);
      g_logger.Info("Structure", StringFormat("M5 swing detection: strength=%d bars=%d swings=%d",
                    InpPivotStrength, n5, g_swing_count));
      int show = (g_swing_count<5) ? g_swing_count : 5;
      for(int i=0;i<show;i++)
         g_logger.Info("Structure", StringFormat("  Swing #%d id=%d %s price=%.5f pivot=%s confirm=%s",
                       i+1, (int)g_swings[i].id, g_swings[i].DirectionToString(), g_swings[i].price,
                       TimeToString(g_swings[i].pivot_time), TimeToString(g_swings[i].confirmation_time)));
      if(g_swing_count>show)
         g_logger.Info("Structure", StringFormat("  ... and %d more swing(s)", g_swing_count-show));
     }
   else
      g_logger.Warning("Structure", "No M5 data loaded - swing detection skipped.");

   //--- Phase 3+4: Leg Engine + Break Engine + Setup State Machine (diagnostic
   //--- and Phase 5/6 entry/exit decision, only). CGZTradeSimulator replays the
   //--- already-loaded, already-validated M1+M5 bars and the already-
   //--- confirmed swings (Phase 2) in strict chronological order, with M1
   //--- execution granularity nested inside M5 structure granularity and NO
   //--- lookahead in either direction - see GZ_TradeSimulator.mqh's header
   //--- for the exact ordering guarantee (also covered by T53).
   g_leg_engine.Init(InpLegVariant);
   GZ_BreakConfig break_cfg; break_cfg.Default();
   break_cfg.mode            = InpBreakMode;
   break_cfg.buffer_atr_mult = InpBreakBufferAtrMult;
   break_cfg.atr_period      = InpAtrPeriod;
   g_break_engine.Configure(break_cfg);

   g_setup_sm.Init(InpFibZoneMinRatio, InpFibZoneMaxRatio);
   GZ_SessionProfile session_profile;
   session_profile.Set("PROFILE_01", "Session", InpTimeMode,
                        InpSessionStartHour, InpSessionStartMinute,
                        InpSessionEndHour, InpSessionEndMinute,
                        InpSessionInclude, true);

   GZ_EntryConfig entry_cfg; entry_cfg.Default();
   entry_cfg.model                = InpEntryModel;
   entry_cfg.entry_fib_ratio      = InpEntryFibRatio;
   entry_cfg.confirmation_candles = InpConfirmationCandles;
   entry_cfg.penetration_atr_mult = InpEntryPenetrationAtrMult;
   g_entry_engine.Init(entry_cfg);

   GZ_ExitConfig exit_cfg; exit_cfg.Default();
   exit_cfg.sl_model                = InpSlModel;
   exit_cfg.sl_buffer_atr_mult      = InpSlBufferAtrMult;
   exit_cfg.sl_atr_mult             = InpSlAtrMult;
   exit_cfg.tp_r_multiple           = InpTpRMultiple;
   exit_cfg.be_trigger_r            = InpBeTriggerR;
   exit_cfg.be_level_mode           = InpBeLevelMode;
   exit_cfg.be_level_offset_r       = InpBeLevelOffsetR;
   exit_cfg.intrabar_conflict_policy= InpIntrabarConflictPolicy;
   g_exit_engine.Init(exit_cfg);

   g_journal_engine.Init();
   g_event_ledger.Init();

   g_leg_count = 0;
   g_broken_leg_count = 0;
   g_setup_count = 0;
   g_trade_count = 0;
   g_exit_count = 0;
   g_metrics.Clear();
   if(n5>0)
     {
      g_trade_simulator.Run(m1, m5, g_swings, g_swing_count,
                             g_leg_engine, g_break_engine, g_setup_sm, g_entry_engine, g_exit_engine,
                             g_journal_engine, g_event_ledger,
                             g_time_engine, g_session_engine, session_profile, InpApplySessionFilter, InpForceSessionExit);

      g_leg_count = g_leg_engine.LegCount();
      for(int j=0;j<g_leg_count;j++)
         if(g_leg_engine.GetLeg(j).broken)
            g_broken_leg_count++;
      g_setup_count = g_setup_sm.SetupCount();
      g_trade_count = g_entry_engine.TradeCount();
      g_exit_count = g_exit_engine.ExitCount();

      g_logger.Info("Leg", StringFormat("Phase 3: legs created=%d broken=%d open=%d (variant=%s break=%s buffer_atr=%.2f atr_period=%d)",
                    g_leg_count, g_broken_leg_count, g_leg_count-g_broken_leg_count,
                    EnumToString(InpLegVariant), EnumToString(InpBreakMode), InpBreakBufferAtrMult, InpAtrPeriod));
      int show_legs = (g_leg_count<5) ? g_leg_count : 5;
      for(int j=0;j<show_legs;j++)
        {
         GZ_Leg leg = g_leg_engine.GetLeg(j);
         g_logger.Info("Leg", StringFormat("  Leg #%d %s origin=%.5f@%s target=%.5f@%s extreme=%.5f@%s broken=%s",
                       (int)leg.id, leg.DirectionToString(), leg.origin_swing.price, TimeToString(leg.origin_swing.pivot_time),
                       leg.target_swing.price, TimeToString(leg.target_swing.pivot_time),
                       leg.extreme_price, TimeToString(leg.extreme_time), leg.broken?"true":"false"));
        }
      if(g_leg_count>show_legs)
         g_logger.Info("Leg", StringFormat("  ... and %d more leg(s)", g_leg_count-show_legs));

      g_logger.Info("Setup", StringFormat(
         "Phase 4: setups=%d LEG_DETECTED=%d FIB_ACTIVE=%d WAITING_ENTRY=%d ENTERED=%d EXITED=%d CANCELLED=%d (zone=[%.2f,%.2f] session_filter=%s)",
         g_setup_count, g_setup_sm.CountByState(GZ_SETUP_LEG_DETECTED), g_setup_sm.CountByState(GZ_SETUP_FIB_ACTIVE),
         g_setup_sm.CountByState(GZ_SETUP_WAITING_ENTRY), g_setup_sm.CountByState(GZ_SETUP_ENTERED),
         g_setup_sm.CountByState(GZ_SETUP_EXITED), g_setup_sm.CountByState(GZ_SETUP_CANCELLED),
         InpFibZoneMinRatio, InpFibZoneMaxRatio, InpApplySessionFilter?"true":"false"));
      g_logger.Info("Setup", StringFormat(
         "  Cancel reasons: OPPOSITE_BREAK=%d NEW_VALID_SETUP=%d SESSION_END=%d INVALID_PENETRATION=%d DATA_END=%d",
         g_setup_sm.CountTerminalByReason(GZ_CANCEL_OPPOSITE_BREAK), g_setup_sm.CountTerminalByReason(GZ_CANCEL_NEW_VALID_SETUP),
         g_setup_sm.CountTerminalByReason(GZ_CANCEL_SESSION_END), g_setup_sm.CountTerminalByReason(GZ_CANCEL_INVALID_PENETRATION),
         g_setup_sm.CountTerminalByReason(GZ_CANCEL_DATA_END)));
      int show_setups = (g_setup_count<5) ? g_setup_count : 5;
      for(int j=0;j<show_setups;j++)
        {
         GZ_Setup s = g_setup_sm.GetSetup(j);
         g_logger.Info("Setup", StringFormat("  Setup #%d %s state=%s origin=%.5f target=%.5f zone=[%.5f,%.5f] reason=%s",
                       (int)s.id, s.leg.DirectionToString(), s.StateToString(), s.leg.origin_swing.price, s.leg.target_swing.price,
                       s.zone_min_price, s.zone_max_price, s.CancelReasonToString()));
        }
      if(g_setup_count>show_setups)
         g_logger.Info("Setup", StringFormat("  ... and %d more setup(s)", g_setup_count-show_setups));

      g_logger.Info("Entry", StringFormat(
         "Phase 5: trades=%d (model=%s fib_ratio=%.3f confirmation_candles=%d penetration_atr=%.2f)",
         g_trade_count, EnumToString(InpEntryModel), InpEntryFibRatio, InpConfirmationCandles, InpEntryPenetrationAtrMult));
      int show_trades = (g_trade_count<5) ? g_trade_count : 5;
      for(int j=0;j<show_trades;j++)
        {
         GZ_Trade tr = g_entry_engine.GetTrade(j);
         g_logger.Info("Entry", StringFormat("  Trade #%d setup=#%d %s model=%s entry=%.5f fib=%.3f slippage=%.5f spread=%.1f at=%s",
                       (int)tr.id, (int)tr.setup_id, tr.DirectionToString(), tr.EntryModelToString(),
                       tr.entry_price, tr.fib_level, tr.slippage_assumption, tr.spread_assumption, TimeToString(tr.entry_time)));
        }
      if(g_trade_count>show_trades)
         g_logger.Info("Entry", StringFormat("  ... and %d more trade(s)", g_trade_count-show_trades));

      g_logger.Info("Exit", StringFormat(
         "Phase 6: exits=%d open=%d TP_HIT=%d SL_HIT=%d BREAK_EVEN=%d SESSION_EXIT=%d DATA_END=%d (sl_model=%s tp=%.2fR be_trigger=%.2fR conflict_policy=%s)",
         g_exit_count, g_exit_engine.OpenCount(),
         g_exit_engine.CountByReason(GZ_EXIT_TP_HIT), g_exit_engine.CountByReason(GZ_EXIT_SL_HIT),
         g_exit_engine.CountByReason(GZ_EXIT_BREAK_EVEN), g_exit_engine.CountByReason(GZ_EXIT_SESSION_EXIT),
         g_exit_engine.CountByReason(GZ_EXIT_DATA_END),
         EnumToString(InpSlModel), InpTpRMultiple, InpBeTriggerR, EnumToString(InpIntrabarConflictPolicy)));
      int show_exits = (g_exit_count<5) ? g_exit_count : 5;
      for(int j=0;j<show_exits;j++)
        {
         GZ_TradeExit ex = g_exit_engine.GetExit(j);
         g_logger.Info("Exit", StringFormat("  Exit #%d trade=#%d %s sl=%.5f tp=%.5f reason=%s exit=%.5f R=%.3f be=%s at=%s",
                       (int)ex.trade_id, (int)ex.setup_id, ex.DirectionToString(), ex.sl_price, ex.tp_price,
                       ex.ExitReasonToString(), ex.exit_price, ex.realized_r, ex.be_triggered?"true":"false", TimeToString(ex.exit_time)));
        }
      if(g_exit_count>show_exits)
         g_logger.Info("Exit", StringFormat("  ... and %d more exit(s)", g_exit_count-show_exits));

      g_journal_count = g_journal_engine.JournalCount();
      g_ledger_event_count = g_event_ledger.EventCount();
      g_logger.Info("Journal", StringFormat(
         "Phase 7: journals=%d open=%d avg_mae=%.3fR avg_mfe=%.3fR reach>=1R=%d reach>=2R=%d reach>=3R=%d | ledger events=%d VALID=%d CANCELLED=%d INVALIDATED=%d ENTRY=%d EXIT=%d REJECTION=%d FILTER_RESULT=%d",
         g_journal_count, g_journal_engine.OpenCount(), g_journal_engine.AverageMae(), g_journal_engine.AverageMfe(),
         g_journal_engine.ReachCountAtIndex(1), g_journal_engine.ReachCountAtIndex(3), g_journal_engine.ReachCountAtIndex(5),
         g_ledger_event_count, g_event_ledger.CountByType(GZ_LEDGER_SETUP_VALID), g_event_ledger.CountByType(GZ_LEDGER_SETUP_CANCELLED),
         g_event_ledger.CountByType(GZ_LEDGER_SETUP_INVALIDATED), g_event_ledger.CountByType(GZ_LEDGER_ENTRY),
         g_event_ledger.CountByType(GZ_LEDGER_EXIT), g_event_ledger.CountByType(GZ_LEDGER_REJECTION),
         g_event_ledger.CountByType(GZ_LEDGER_FILTER_RESULT)));
      int show_journals = (g_journal_count<5) ? g_journal_count : 5;
      for(int j=0;j<show_journals;j++)
        {
         GZ_TradeJournal tj = g_journal_engine.GetJournal(j);
         g_logger.Info("Journal", StringFormat("  Trade #%d %s mae=%.3fR@%s mfe=%.3fR@%s final_r=%.3f duration=%ds highest_reach=%.2fR",
                       (int)tj.trade_id, tj.DirectionToString(), tj.mae_r, TimeToString(tj.time_to_mae),
                       tj.mfe_r, TimeToString(tj.time_to_mfe), tj.final_r, tj.duration_seconds, tj.HighestReachHit()));
        }
      if(g_journal_count>show_journals)
         g_logger.Info("Journal", StringFormat("  ... and %d more journal(s)", g_journal_count-show_journals));

      //--- Phase 8: Metrics + Reporting - one deterministic, post-hoc pass
      //--- over the now-final Phase 7 journal (see GZ_MetricsEngine.mqh).
      g_metrics_engine.Compute(g_journal_engine, g_time_engine, g_session_engine, session_profile, g_metrics);
      g_logger.Info("Metrics", StringFormat(
         "Phase 8: closed_trades=%d winners=%d losers=%d win_rate=%.1f%% net_r=%.3f avg_r=%.3f pf=%s | max_dd=%.3fR avg_dd=%.3fR dd_len=%d win_streak=%d lose_streak=%d",
         g_metrics.trade.trade_count, g_metrics.trade.winners, g_metrics.trade.losers, g_metrics.trade.win_rate*100.0,
         g_metrics.trade.net_r, g_metrics.trade.avg_r,
         g_metrics.trade.profit_factor_undefined ? "UNDEFINED(inf)" : DoubleToString(g_metrics.trade.profit_factor,3),
         g_metrics.risk.max_drawdown_r, g_metrics.risk.avg_drawdown_r, g_metrics.risk.max_drawdown_duration_trades,
         g_metrics.risk.max_winning_streak, g_metrics.risk.max_losing_streak));
      g_logger.Info("Metrics", StringFormat(
         "  Behavior: avg_mae=%.3fR avg_mfe=%.3fR avg_duration=%.0fs avg_time_to_mae=%.0fs avg_time_to_mfe=%.0fs | range=[%s .. %s]",
         g_metrics.behavior.avg_mae_r, g_metrics.behavior.avg_mfe_r, g_metrics.behavior.avg_duration_seconds,
         g_metrics.behavior.avg_time_to_mae_seconds, g_metrics.behavior.avg_time_to_mfe_seconds,
         TimeToString(g_metrics.range_start), TimeToString(g_metrics.range_end)));
      g_logger.Info("Metrics", StringFormat(
         "  By direction: LONG n=%d net_r=%.3f win_rate=%.1f%% | SHORT n=%d net_r=%.3f win_rate=%.1f%%",
         g_metrics.by_direction[0].stats.trade_count, g_metrics.by_direction[0].stats.net_r, g_metrics.by_direction[0].stats.win_rate*100.0,
         g_metrics.by_direction[1].stats.trade_count, g_metrics.by_direction[1].stats.net_r, g_metrics.by_direction[1].stats.win_rate*100.0));
      g_logger.Info("Metrics", StringFormat(
         "  By session:   INSIDE n=%d net_r=%.3f win_rate=%.1f%% | OUTSIDE n=%d net_r=%.3f win_rate=%.1f%%",
         g_metrics.by_session[0].stats.trade_count, g_metrics.by_session[0].stats.net_r, g_metrics.by_session[0].stats.win_rate*100.0,
         g_metrics.by_session[1].stats.trade_count, g_metrics.by_session[1].stats.net_r, g_metrics.by_session[1].stats.win_rate*100.0));

      //--- Phase 10: Filter Engine - evaluate every one of the g_setup_count
      //--- setups the direct pipeline above already produced (same setups
      //--- Phase 8 just summarized), using the SAME already-loaded/validated
      //--- m5 array (no second data load) and the SAME g_time_engine/
      //--- g_session_engine instances every earlier phase already uses (see
      //--- GZ_FilterEngine.mqh header). Then diff an unfiltered-vs-filtered
      //--- GZ_MetricsSummary to populate GZ_FilterDiagnostics (design note 7,
      //--- GZ_MetricsTypes.mqh) - the WITH/WITHOUT population the Roadmap's
      //--- Phase 8 "Filter Diagnostics" bullet list asked for, now that a
      //--- Filter Engine actually exists to produce it.
      GZ_FilterSetConfig filter_cfg; filter_cfg.Default();
      filter_cfg.mode[GZ_FILTER_BREAK_QUALITY] = InpFilterBreakQualityMode;
      filter_cfg.mode[GZ_FILTER_LEG_QUALITY]   = InpFilterLegQualityMode;
      filter_cfg.mode[GZ_FILTER_VOLUME]        = InpFilterVolumeMode;
      filter_cfg.mode[GZ_FILTER_VOLATILITY]    = InpFilterVolatilityMode;
      filter_cfg.mode[GZ_FILTER_VWAP]          = InpFilterVwapMode;
      filter_cfg.mode[GZ_FILTER_M15_CONTEXT]   = InpFilterM15ContextMode;
      filter_cfg.mode[GZ_FILTER_SESSION]       = InpFilterSessionMode;
      filter_cfg.mode[GZ_FILTER_NEWS]          = InpFilterNewsMode;
      filter_cfg.atr_period                  = InpAtrPeriod;
      filter_cfg.break_quality_min_atr_mult  = InpFilterBreakQualityMinAtrMult;
      filter_cfg.leg_quality_min_atr_mult    = InpFilterLegQualityMinAtrMult;
      filter_cfg.volume_lookback             = InpFilterVolumeLookback;
      filter_cfg.volume_min_mult             = InpFilterVolumeMinMult;
      filter_cfg.volatility_lookback         = InpFilterVolatilityLookback;
      filter_cfg.volatility_min_mult         = InpFilterVolatilityMinMult;
      filter_cfg.volatility_max_mult         = InpFilterVolatilityMaxMult;
      filter_cfg.session_profile             = session_profile; // reuse the same window (design note, GZ_FilterTypes.mqh)

      long   filter_setup_ids[];
      bool   filter_setup_pass[];
      ArrayResize(filter_setup_ids, g_setup_count);
      ArrayResize(filter_setup_pass, g_setup_count);
      g_filter_setups_after = 0;

      for(int fi=0; fi<g_setup_count; fi++)
        {
         GZ_Setup fs = g_setup_sm.GetSetup(fi);
         GZ_SetupFilterOutcome outcome;
         g_filter_engine.Evaluate(fs, m5, filter_cfg, g_time_engine, g_session_engine, outcome);

         filter_setup_ids[fi]  = fs.id;
         filter_setup_pass[fi] = outcome.overall_pass;
         if(outcome.overall_pass)
            g_filter_setups_after++;

         g_event_ledger.RecordFilterResult(fs.id, fs.detected_time, fs.leg.direction, outcome.Summary());
         if(!outcome.overall_pass && fs.state==GZ_SETUP_EXITED)
            g_event_ledger.RecordRejection(fs.id, fs.terminal_time, fs.leg.direction, "FILTER_REJECTED: "+outcome.Summary());
        }

      // Build the journal-index-aligned inclusion mask ComputeFiltered()
      // needs (see GZ_MetricsEngine.mqh) by joining each closed journal
      // entry's own setup_id against the per-setup decision above.
      bool filter_journal_mask[];
      ArrayResize(filter_journal_mask, g_journal_engine.JournalCount());
      g_filter_rejections = 0;
      for(int ji=0; ji<g_journal_engine.JournalCount(); ji++)
        {
         GZ_TradeJournal fj = g_journal_engine.GetJournal(ji);
         bool fpass = true; // a journal entry whose setup somehow is not found stays included (defensive default)
         for(int fk=0; fk<g_setup_count; fk++)
            if(filter_setup_ids[fk]==fj.setup_id) { fpass = filter_setup_pass[fk]; break; }
         filter_journal_mask[ji] = fpass;
         if(!fj.is_open && !fpass)
            g_filter_rejections++;
        }

      g_filter_metrics_after.Clear();
      g_metrics_engine.ComputeFiltered(g_journal_engine, g_time_engine, g_session_engine, session_profile,
                                        filter_journal_mask, g_filter_metrics_after);

      g_metrics.filters.available     = true;
      g_metrics.filters.setups_before = g_setup_count;
      g_metrics.filters.setups_after  = g_filter_setups_after;
      g_metrics.filters.trades_before = g_metrics.trade.trade_count;
      g_metrics.filters.trades_after  = g_filter_metrics_after.trade.trade_count;
      g_metrics.filters.rejections    = g_filter_rejections;
      g_metrics.filters.win_rate_delta      = g_filter_metrics_after.trade.win_rate     - g_metrics.trade.win_rate;
      g_metrics.filters.profit_factor_delta = g_filter_metrics_after.trade.profit_factor- g_metrics.trade.profit_factor;
      g_metrics.filters.expectancy_delta    = g_filter_metrics_after.trade.expectancy   - g_metrics.trade.expectancy;
      g_metrics.filters.max_drawdown_delta  = g_filter_metrics_after.risk.max_drawdown_r- g_metrics.risk.max_drawdown_r;
      g_metrics.filters.trade_count_delta   = g_filter_metrics_after.trade.trade_count  - g_metrics.trade.trade_count;

      g_logger.Info("Filter", StringFormat(
         "Phase 10: setups_before=%d setups_after=%d trades_before=%d trades_after=%d rejections=%d | "+
         "win_rate_delta=%.4f pf_delta=%.4f expectancy_delta=%.4f max_dd_delta=%.4f trade_count_delta=%d | "+
         "modes: break_q=%s leg_q=%s volume=%s volatility=%s vwap=%s m15=%s session=%s news=%s",
         g_metrics.filters.setups_before, g_metrics.filters.setups_after,
         g_metrics.filters.trades_before, g_metrics.filters.trades_after, g_metrics.filters.rejections,
         g_metrics.filters.win_rate_delta, g_metrics.filters.profit_factor_delta,
         g_metrics.filters.expectancy_delta, g_metrics.filters.max_drawdown_delta, g_metrics.filters.trade_count_delta,
         GZFilterModeToString(InpFilterBreakQualityMode), GZFilterModeToString(InpFilterLegQualityMode),
         GZFilterModeToString(InpFilterVolumeMode), GZFilterModeToString(InpFilterVolatilityMode),
         GZFilterModeToString(InpFilterVwapMode), GZFilterModeToString(InpFilterM15ContextMode),
         GZFilterModeToString(InpFilterSessionMode), GZFilterModeToString(InpFilterNewsMode)));

      //--- Phase 11: Filter Combination Research - R11-A/B/C sweeps of
      //--- Phase 10's own CGZFilterEngine over the SAME g_setup_count
      //--- setups / g_journal_engine trades already produced above - NO
      //--- pipeline re-simulation (filters are post-hoc masks, see
      //--- GZ_FilterComboTypes.mqh design note 2). filter_cfg (built just
      //--- above for the single Phase 10 diagnostic run) is reused as
      //--- every combo's shared baseline threshold/session config - Phase
      //--- 11 only varies WHICH filters are turned on, never their
      //--- thresholds. g_metrics (Phase 8's unfiltered summary, already
      //--- computed above) is the one unfiltered baseline every combo in
      //--- this sweep is diffed against (design note 2).
      if(InpRunPhase11 && !g_p155_only)
        {
         g_filter_combo_engine.SetMaxBatchSize(InpFilterComboMaxBatchSize);

         GZ_Setup all_setups[];
         ArrayResize(all_setups, g_setup_count);
         for(int gi=0; gi<g_setup_count; gi++)
            all_setups[gi] = g_setup_sm.GetSetup(gi);

         GZ_FilterComboRequest r11a_reqs[];
         g_filter_combo_engine.BuildR11ASingleRequests(filter_cfg, r11a_reqs, InpFilterComboIncludeReserved);
         g_filter_combo_engine.RunBatch(r11a_reqs, ArraySize(r11a_reqs), all_setups, g_setup_count, m5,
                                         g_journal_engine, g_time_engine, g_session_engine, session_profile,
                                         g_metrics, g_r11a_results);

         GZ_FilterComboRequest r11b_reqs[];
         g_filter_combo_engine.BuildR11BTwoFilterRequests(filter_cfg, r11b_reqs, InpFilterComboIncludeReserved);
         g_filter_combo_engine.RunBatch(r11b_reqs, ArraySize(r11b_reqs), all_setups, g_setup_count, m5,
                                         g_journal_engine, g_time_engine, g_session_engine, session_profile,
                                         g_metrics, g_r11b_results);

         GZ_FilterComboRequest r11c_reqs[];
         g_filter_combo_engine.BuildR11CMultiFilterRequests(g_r11a_results, ArraySize(g_r11a_results), filter_cfg,
                                                              r11c_reqs, InpFilterComboR11CTopN);
         if(ArraySize(r11c_reqs)>0)
            g_filter_combo_engine.RunBatch(r11c_reqs, ArraySize(r11c_reqs), all_setups, g_setup_count, m5,
                                            g_journal_engine, g_time_engine, g_session_engine, session_profile,
                                            g_metrics, g_r11c_results);
         else
            ArrayResize(g_r11c_results, 0);

         g_phase11_ran  = true;
         g_r11a_best_idx = BestFilterComboIndex(g_r11a_results);
         g_r11b_best_idx = BestFilterComboIndex(g_r11b_results);
         g_r11c_best_idx = BestFilterComboIndex(g_r11c_results);

         g_logger.Info("FilterCombo", StringFormat(
            "Phase 11: R11-A=%d combos  R11-B=%d combos  R11-C=%d combos | best expectancy_delta: A=%s B=%s C=%s",
            ArraySize(g_r11a_results), ArraySize(g_r11b_results), ArraySize(g_r11c_results),
            (g_r11a_best_idx>=0)?StringFormat("%s(%.4f)", g_r11a_results[g_r11a_best_idx].label, g_r11a_results[g_r11a_best_idx].diagnostics.expectancy_delta):"n/a",
            (g_r11b_best_idx>=0)?StringFormat("%s(%.4f)", g_r11b_results[g_r11b_best_idx].label, g_r11b_results[g_r11b_best_idx].diagnostics.expectancy_delta):"n/a",
            (g_r11c_best_idx>=0)?StringFormat("%s(%.4f)", g_r11c_results[g_r11c_best_idx].label, g_r11c_results[g_r11c_best_idx].diagnostics.expectancy_delta):"n/a"));
        }
      else
         g_logger.Info("FilterCombo", "Phase 11: skipped (InpRunPhase11=false).");

      //--- Phase 9: Experiment Configuration + Runner - demonstrate
      //--- CGZExperimentRunner as one SINGLE-mode experiment, reusing the
      //--- EXACT config the direct Phase 2-8 pipeline above just used
      //--- (time_cfg/session_profile/break_cfg/entry_cfg/exit_cfg are all
      //--- already in scope). Runs against a RECENT WINDOW of the same
      //--- already-loaded/validated m1/m5 (InpExperimentWindowM5Bars M5
      //--- bars, default 1000 - about a week of XAUUSD M5 data), not the
      //--- full requested range: Phase 2-8's own correctness already ran
      //--- and got tested (T01-T86) on the full range above, so re-running
      //--- the entire multi-month pipeline a SECOND time here would only
      //--- double this EA's runtime for no new information - the window
      //--- is enough to prove the Phase 9 wrapper itself (config in,
      //--- GZ_ExperimentResult out) against real market data.
      g_experiment_runner.SetMaxBatchSize(InpExperimentMaxBatchSize);
      int win_bars = (InpExperimentWindowM5Bars>0) ? InpExperimentWindowM5Bars : 1000;
      int win_count = (n5<win_bars) ? n5 : win_bars;
      int win_start = n5-win_count;
      MqlRates m5_window[];
      ArrayResize(m5_window, win_count);
      ArrayCopy(m5_window, m5, 0, win_start, win_count);

      MqlRates m1_window[];
      int m1_win_start = -1;
      for(int k=0;k<n1;k++)
         if(m1[k].time>=m5_window[0].time) { m1_win_start=k; break; }
      if(m1_win_start>=0)
        {
         int m1_win_count = n1-m1_win_start;
         ArrayResize(m1_window, m1_win_count);
         ArrayCopy(m1_window, m1, 0, m1_win_start, m1_win_count);
        }
      else
         ArrayResize(m1_window, 0);

      GZ_ExperimentConfig exp_cfg; exp_cfg.Default();
      exp_cfg.symbol               = InpSymbol;
      exp_cfg.range_start          = m5_window[0].time;
      exp_cfg.range_end            = m5_window[win_count-1].time;
      exp_cfg.time_config          = time_cfg;
      exp_cfg.session_profile      = session_profile;
      exp_cfg.apply_session_filter = InpApplySessionFilter;
      exp_cfg.force_session_exit   = InpForceSessionExit;
      exp_cfg.pivot_strength       = InpPivotStrength;
      exp_cfg.leg_variant          = InpLegVariant;
      exp_cfg.break_config         = break_cfg;
      exp_cfg.fib_zone_min_ratio   = InpFibZoneMinRatio;
      exp_cfg.fib_zone_max_ratio   = InpFibZoneMaxRatio;
      exp_cfg.entry_config         = entry_cfg;
      exp_cfg.exit_config          = exit_cfg;

      string dataset_id = StringFormat("%s_M1M5_RECENT_%s_%s", InpSymbol,
                           TimeToString(exp_cfg.range_start, TIME_DATE), TimeToString(exp_cfg.range_end, TIME_DATE));

      g_experiment_runner.RunSingle(exp_cfg, m1_window, m5_window, dataset_id,
                                     g_info_m1.validation_status, g_info_m5.validation_status, g_experiment_result);
      g_experiment_ran = true;

      g_logger.Info("Experiment", StringFormat(
         "Phase 9: id=%s dataset=%s window=[%s .. %s] (%d M5 bars) swings=%d legs=%d setups=%d trades=%d exits=%d net_r=%.3f warnings=%d",
         g_experiment_result.id, g_experiment_result.dataset_id,
         TimeToString(g_experiment_result.range_start), TimeToString(g_experiment_result.range_end), win_count,
         g_experiment_result.swing_count, g_experiment_result.leg_count, g_experiment_result.setup_count,
         g_experiment_result.trade_count, g_experiment_result.exit_count, g_experiment_result.metrics.trade.net_r,
         g_experiment_result.warning_count));
      for(int w=0; w<g_experiment_result.warning_count; w++)
         g_logger.Info("Experiment", StringFormat("  Warning: %s", g_experiment_result.warnings[w]));

      //--- Phase 12: Robustness + Sensitivity Research - sweep
      //--- InpRobustnessAxis1/2 around exp_cfg's OWN current value for
      //--- each (auto-baseline, see CGZRobustnessEngine::
      //--- BuildNeighborhoodRequest()), over the SAME recent
      //--- m1_window/m5_window Phase 9 just used above (see the Phase 12
      //--- input block for why a window, not the full range). ATR-
      //--- multiple-style axes (break buffer / SL ATR mult / SL buffer /
      //--- entry penetration) use the Roadmap's OWN worked-example
      //--- offsets; everything else falls back to a small integer or
      //--- ratio neighborhood - see GZRobustnessDefault*Offsets() in
      //--- GZ_RobustnessTypes.mqh.
      if(InpRunPhase12 && !g_p155_only)
        {
         g_robustness_engine.SetMaxBatchSize(InpRobustnessMaxBatchSize);

         ENUM_GZ_ROBUSTNESS_PARAM axes[2] = {InpRobustnessAxis1, InpRobustnessAxis2};
         GZ_RobustnessSweepRequest rob_reqs[2];
         int rob_req_count = 0;
         for(int a=0; a<2; a++)
           {
            if(axes[a]==GZ_ROBUST_PARAM_COUNT) continue; // sentinel - not a real axis, skip if mistakenly selected
            double offs[];
            switch(axes[a])
              {
               case GZ_ROBUST_BREAK_BUFFER_ATR:
               case GZ_ROBUST_SL_ATR_MULT:
               case GZ_ROBUST_SL_BUFFER_ATR:
               case GZ_ROBUST_ENTRY_PENETRATION_ATR:
                  GZRobustnessDefaultAtrOffsets(offs); break;
               case GZ_ROBUST_FIB_ZONE_MIN_RATIO:
               case GZ_ROBUST_FIB_ZONE_MAX_RATIO:
                  GZRobustnessDefaultRatioOffsets(offs); break;
               default:
                  GZRobustnessDefaultIntOffsets(offs); break; // PIVOT_STRENGTH/ATR_PERIOD/CONFIRMATION_CANDLES/TP_R_MULTIPLE/BE_TRIGGER_R
              }
            g_robustness_engine.BuildNeighborhoodRequest(exp_cfg, axes[a], offs, ArraySize(offs), rob_reqs[rob_req_count]);
            rob_req_count++;
           }

         if(rob_req_count>0)
            g_robustness_engine.RunSweepBatch(rob_reqs, rob_req_count, m1_window, m5_window, dataset_id,
                                               g_info_m1.validation_status, g_info_m5.validation_status, g_robustness_results);
         else
            ArrayResize(g_robustness_results, 0);

         g_phase12_ran = true;
         for(int ri=0; ri<ArraySize(g_robustness_results); ri++)
           {
            GZ_RobustnessSweepResult rr = g_robustness_results[ri];
            g_logger.Info("Robustness", StringFormat(
               "Phase 12: %s [%s] baseline=%.4f points=%d best=%s expectancy=%s safe_to_adopt=%s | flags: narrow_peak=%s flat_region=%s unstable_zone=%s parameter_sensitive=%s",
               rr.id, rr.param_label, rr.baseline_value, rr.point_count,
               (rr.best_idx>=0)?DoubleToString(rr.points[rr.best_idx].param_value,4):"n/a",
               (rr.best_idx>=0)?DoubleToString(rr.points[rr.best_idx].result.metrics.trade.expectancy,4):"n/a",
               rr.safe_to_adopt_best?"true":"false", rr.narrow_peak?"true":"false", rr.flat_region?"true":"false",
               rr.unstable_zone?"true":"false", rr.parameter_sensitive?"true":"false"));
            for(int pi=0; pi<rr.point_count; pi++)
               g_logger.Info("Robustness", StringFormat("  %s=%.4f -> trades=%d net_r=%.3f expectancy=%.4f",
                              rr.param_label, rr.points[pi].param_value, rr.points[pi].result.trade_count,
                              rr.points[pi].result.metrics.trade.net_r, rr.points[pi].result.metrics.trade.expectancy));
           }
        }
      else
         g_logger.Info("Robustness", "Phase 12: skipped (InpRunPhase12=false).");

      //--- Phase 13: Walk-Forward Research - rolling Train -> Validate
      //--- windows over the FULL loaded m1/m5 (not the recent window Phase
      //--- 9/12 used: walk-forward needs several consecutive windows).
      //--- Candidate values for InpWfAxis = exp_cfg's OWN current value for
      //--- that axis + the SAME default offsets Phase 12 uses (see
      //--- GZWalkForwardDefaultOffsets()) - no second grid definition.
      //--- exp_cfg is the base for every window; only the axis value varies.
      if(InpRunPhase13 && !g_p155_only)
        {
         if(InpWfAxis==GZ_ROBUST_PARAM_COUNT)
            g_logger.Warning("WalkForward", "Phase 13: InpWfAxis is the GZ_ROBUST_PARAM_COUNT sentinel, not a real axis - skipped.");
         else
           {
            GZ_WalkForwardConfig wf_cfg;
            wf_cfg.Default();
            wf_cfg.base_config             = exp_cfg;
            wf_cfg.base_config.range_start = m5[0].time;
            wf_cfg.base_config.range_end   = m5[n5-1].time;
            wf_cfg.axis                    = InpWfAxis;
            wf_cfg.train_days              = InpWfTrainDays;
            wf_cfg.validate_days           = InpWfValidateDays;
            wf_cfg.step_days               = InpWfStepDays;
            wf_cfg.min_trades              = InpWfMinTrades;
            wf_cfg.min_validation_trades   = InpWfMinValidationTrades;
            wf_cfg.require_safe_selection  = InpWfRequireSafeSelection;

            double wf_offs[];
            GZWalkForwardDefaultOffsets(InpWfAxis, wf_offs);
            GZ_RobustnessSweepRequest wf_req;
            g_robustness_engine.BuildNeighborhoodRequest(exp_cfg, InpWfAxis, wf_offs, ArraySize(wf_offs), wf_req);
            for(int ci=0; ci<wf_req.value_count; ci++)
               wf_cfg.candidates[ci] = wf_req.values[ci];
            wf_cfg.candidate_count = wf_req.value_count;

            string wf_dataset_id = StringFormat("%s_M1M5_FULL_%s_%s", InpSymbol,
                                    TimeToString(m5[0].time, TIME_DATE), TimeToString(m5[n5-1].time, TIME_DATE));
            g_walkforward_engine.RunWalkForward(wf_cfg, m1, m5, wf_dataset_id,
                                                 g_info_m1.validation_status, g_info_m5.validation_status, g_wf_result);
            g_phase13_ran = true;

            g_logger.Info("WalkForward", StringFormat(
               "Phase 13: %s [%s] windows=%d selected=%d validated=%d | pooled OOS trades=%d net_r=%.3f expectancy=%.4f | efficiency=%s | flags: param_unstable=%s overfit_suspect=%s negative_oos=%s",
               g_wf_result.id, g_wf_result.axis_label, g_wf_result.window_count, g_wf_result.windows_selected,
               g_wf_result.windows_validated, g_wf_result.pooled_trades, g_wf_result.pooled_net_r, g_wf_result.pooled_expectancy,
               g_wf_result.efficiency_defined ? DoubleToString(g_wf_result.walk_forward_efficiency,3) : "undefined",
               g_wf_result.param_unstable?"true":"false", g_wf_result.overfit_suspect?"true":"false",
               g_wf_result.negative_oos?"true":"false"));
           }
        }
      else
         g_logger.Info("WalkForward", "Phase 13: skipped (InpRunPhase13=false).");

      //--- Phase 15: Final OOS. Loads the OOS range SEPARATELY (nothing above ever saw
      //--- it), validates it exactly like the Development data, then runs the frozen
      //--- exp_cfg once on each range and compares. No selection, no tuning.
      if(InpRunPhase15 && !InpRunPhase155)   // Phase 15.5 NEVER loads the Final OOS
        {
         MqlRates oos_m1[], oos_m5[];
         g_oos_m1_bars        = g_provider.LoadM1(InpSymbol, InpOosStart, InpOosEnd, oos_m1);
         g_oos_m5_bars_loaded = g_provider.LoadM5(InpSymbol, InpOosStart, InpOosEnd, oos_m5);

         CGZDatasetInfo oos_i1, oos_i5;
         oos_i1.Clear(); oos_i1.symbol = InpSymbol; oos_i1.execution_timeframe = PERIOD_M1;
         oos_i1.start_timestamp = InpOosStart; oos_i1.end_timestamp = InpOosEnd;
         oos_i1.broker_utc_offset_hours = InpBrokerUtcOffsetHrs;
         oos_i1.broker_tz_status = InpBrokerOffsetKnown ? GZ_TZ_KNOWN : GZ_TZ_UNKNOWN;
         oos_i1.total_bars = g_oos_m1_bars;
         if(g_oos_m1_bars>0)
           {
            oos_i1.first_bar_time = oos_m1[0].time; oos_i1.last_bar_time = oos_m1[g_oos_m1_bars-1].time;
            g_validator.ValidateOHLC(oos_m1, oos_i1);
            g_validator.ValidateTimestamps(oos_m1, GZ_SPACING_M1_SECONDS, oos_i1);
           }
         else
            oos_i1.AddError("No M1 data returned for the Final OOS range.");
         oos_i1.Finalize();

         oos_i5.Clear(); oos_i5.symbol = InpSymbol; oos_i5.structure_timeframe = PERIOD_M5;
         oos_i5.start_timestamp = InpOosStart; oos_i5.end_timestamp = InpOosEnd;
         oos_i5.broker_utc_offset_hours = InpBrokerUtcOffsetHrs;
         oos_i5.broker_tz_status = InpBrokerOffsetKnown ? GZ_TZ_KNOWN : GZ_TZ_UNKNOWN;
         oos_i5.total_bars = g_oos_m5_bars_loaded;
         if(g_oos_m5_bars_loaded>0)
           {
            oos_i5.first_bar_time = oos_m5[0].time; oos_i5.last_bar_time = oos_m5[g_oos_m5_bars_loaded-1].time;
            g_validator.ValidateOHLC(oos_m5, oos_i5);
            g_validator.ValidateTimestamps(oos_m5, GZ_SPACING_M5_SECONDS, oos_i5);
           }
         else
            oos_i5.AddError("No M5 data returned for the Final OOS range.");
         oos_i5.Finalize();

         GZ_ExperimentConfig oos_cfg = exp_cfg;   // the frozen configuration - same base Phases 9-14 used
         string oos_prefix = StringFormat("%s_FINALOOS", InpSymbol);
         g_oos_engine.Evaluate(oos_cfg, InpRangeStart, InpRangeEnd, InpOosStart, InpOosEnd, InpOosMinTrades,
                               m1, m5, oos_m1, oos_m5,
                               g_info_m1.validation_status, g_info_m5.validation_status,
                               oos_i1.validation_status, oos_i5.validation_status, oos_prefix, g_oos_result);
         g_phase15_ran = true;
         g_logger.Info("FinalOOS", StringFormat("Phase 15: %s status=%s OOS M1=%d M5=%d bars loaded | OOS validation M1=%s M5=%s",
                       g_oos_result.id, GZOosStatusToString(g_oos_result.status), g_oos_m1_bars, g_oos_m5_bars_loaded,
                       EnumToString(oos_i1.validation_status), EnumToString(oos_i5.validation_status)));
        }
      else
         g_logger.Info("FinalOOS", "Phase 15: skipped (InpRunPhase15=false).");

      //--- Phase 15.5: Reward / TP x Risk-Free (BE) research matrix. DEVELOPMENT arrays m1/m5
      //--- ONLY (the Final OOS is never loaded in this run - see the Phase 15 guard above).
      //--- Only exit_config.tp_r_multiple / be_trigger_r vary between the runs.
      if(InpRunPhase155)
        {
         GZ_ExperimentConfig p155_cfg = exp_cfg;
         p155_cfg.range_start = m5[0].time;
         p155_cfg.range_end   = m5[n5-1].time;

         GZ_RewardBeBaselineRef p155_ref; p155_ref.Clear();
         if(MathAbs(InpTpRMultiple-2.0)<0.000001 && InpBeTriggerR<=0.0)
           {
            p155_ref.main_available  = true;
            p155_ref.main_trades     = g_metrics.trade.trade_count;
            p155_ref.main_winners    = g_metrics.trade.winners;
            p155_ref.main_net_r      = g_metrics.trade.net_r;
            p155_ref.main_expectancy = g_metrics.trade.expectancy;
           }
         p155_ref.ext_available   = true;
         p155_ref.ext_win_rate    = InpP155RefWinRate;
         p155_ref.ext_expectancy  = InpP155RefExpectancy;
         p155_ref.ext_pf          = InpP155RefPF;
         p155_ref.ext_net_r       = InpP155RefNetR;

         g_p155_dataset_id = StringFormat("%s_M1M5_DEV_%s_%s", InpSymbol,
                              TimeToString(m5[0].time, TIME_DATE), TimeToString(m5[n5-1].time, TIME_DATE));
         g_logger.Info("RewardBe", StringFormat("Phase 15.5: starting TP x BE matrix on Development data %s (%d M1 / %d M5 bars). This runs ~130 full simulations - expect several minutes.",
                       g_p155_dataset_id, n1, n5));
         g_rewardbe_engine.Run(p155_cfg, m1, m5, g_p155_dataset_id, g_info_m1.validation_status, g_info_m5.validation_status,
                               InpP155IncludeInactiveEquivalent, InpRangeStart, InpRangeEnd, InpOosStart, !g_phase15_ran, p155_ref);
         g_phase155_ran = true;
         g_logger.Info("RewardBe", StringFormat("Phase 15.5: %d experiments executed, %d matrix rows, runtime validations failed=%d blocked=%d.",
                       g_rewardbe_engine.ExperimentCount(), g_rewardbe_engine.RowCount(),
                       g_rewardbe_engine.ValidationFailCount(), g_rewardbe_engine.ValidationBlockedCount()));
        }
      else
         g_logger.Info("RewardBe", "Phase 15.5: skipped (InpRunPhase155=false).");
     }
   else
      g_logger.Warning("Leg", "No M5 data loaded - leg/break/setup/entry/exit detection skipped.");

   //--- Phase 14: Monte Carlo Research - reads the main pipeline's journal
   //--- (closed trades only, journal order) into a plain R series; the journal
   //--- itself is never modified. Both randomization modes, same seed.
   if(InpRunPhase14 && !g_p155_only)
     {
      g_montecarlo_engine.SetMaxSimulations(InpMcMaxSimulations);
      double mc_series[];
      int mc_n = g_montecarlo_engine.BuildRSeries(g_journal_engine, mc_series);
      g_montecarlo_engine.Run(GZ_MC_TRADE_ORDER,     mc_series, InpMcSimulations, InpMcSeed, g_mc_order);
      g_montecarlo_engine.Run(GZ_MC_RETURN_SEQUENCE, mc_series, InpMcSimulations, InpMcSeed, g_mc_bootstrap);
      g_phase14_ran = true;
      g_logger.Info("MonteCarlo", StringFormat("Phase 14: closed-trade R series n=%d | %s=%s | %s=%s",
                    mc_n, g_mc_order.id, GZMcStatusToString(g_mc_order.status), g_mc_bootstrap.id, GZMcStatusToString(g_mc_bootstrap.status)));
     }
   else
      g_logger.Info("MonteCarlo", "Phase 14: skipped (InpRunPhase14=false).");

   //--- Run deterministic automated test harness (synthetic data) -------------
   g_harness.RunAll();

   //--- Report ------------------------------------------------------------------
   BuildAndEmitReport();
   EmitPhase155Report();

   g_logger.Info("Init", "Phase 1+2+3+4+5+6+7+8+9+10+11+12+13+14+15 diagnostics complete. STOPPING after Phase 15.5 - not proceeding to Phase 16 (Research Freeze) logic.");

   // Initialization succeeds regardless of data/test outcome so the report is
   // visible in the Experts log; the report itself states BLOCKED/FAILED status.
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_logger.Info("Deinit", "GoldenZone STR Phase 1+2+3+4+5+6+7+8+9+10+11+12+13+14+15 EA removed.");
  }

//+------------------------------------------------------------------+
//| Expert tick function - intentionally empty.                       |
//| Phase 1 performs no trading and no per-tick strategy logic.       |
//| All diagnostic work happens once, in OnInit.                       |
//+------------------------------------------------------------------+
void OnTick()
  {
  }
//+------------------------------------------------------------------+
