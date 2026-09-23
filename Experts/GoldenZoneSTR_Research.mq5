//+------------------------------------------------------------------+
//|                                    GoldenZoneSTR_Research.mq5    |
//|                                                                    |
//| GoldenZone STR - Phase 1+2+3+4+5+6+7+8 Research EA                |
//| Phase 1: Data Layer + Data Validator + Time Engine                |
//| Phase 2: M5 Structure Engine (swing/pivot detection)               |
//| Phase 3: Leg Engine + Break Engine                                 |
//| Phase 4: Fibonacci Engine + Setup State Machine                    |
//| Phase 5: Entry Engine + Historical Trade Simulator                 |
//| Phase 6: Exit Engine (SL/TP/BE)                                    |
//| Phase 7: MAE/MFE + R-Path + Event Ledger                          |
//| Phase 8: Metrics + Reporting                                       |
//|                                                                    |
//| SCOPE: This EA implements ONLY Phase 1 (Data/Validator/Time/      |
//| Session/Diagnostics/TestHarness), Phase 2 (M5 swing/pivot         |
//| detection), Phase 3 (Leg Engine + Break Engine), Phase 4           |
//| (Fibonacci Engine + Setup State Machine), Phase 5 (Entry Engine + |
//| Historical Trade Simulator), Phase 6 (Exit Engine: SL/TP/BE),     |
//| Phase 7 (MAE/MFE + R-Path + Event Ledger) and Phase 8 (Metrics +  |
//| Reporting). It contains NO filter or experiment-runner logic       |
//| (Phase 9+), and it places NO live orders. On init it loads         |
//| historical M1+M5 data, runs validation, runs swing detection,      |
//| replays the M1/M5 data through the Leg/Break/Setup/Entry/Exit/     |
//| Journal/Ledger engines via CGZTradeSimulator, computes the Phase 8 |
//| Metrics summary from the resulting journal via CGZMetricsEngine,   |
//| runs the deterministic T01-T86 test harness, and prints a          |
//| completion report. Then it stops - it does not trade and does not  |
//| proceed to Phase 9 (Experiment Configuration + Runner) logic.      |
//+------------------------------------------------------------------+
#property copyright "GoldenZone STR"
#property version   "1.80"
#property description "Phase 1+2+3+4+5+6+7+8: Data/Validator/Time Engine + M5 Structure Engine + Leg/Break Engine + Fibonacci/Setup State Machine + Entry Engine/Trade Simulator + Exit Engine SL/TP/BE + MAE/MFE/R-Path/Event Ledger + Metrics/Reporting (research/diagnostic only, no trading)"

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

//+------------------------------------------------------------------+
//| Build and print/save the Phase 1 completion report                |
//+------------------------------------------------------------------+
void BuildAndEmitReport()
  {
   string report = "";
   report += "===================================================\n";
   report += " GoldenZone STR - PHASE 1 + PHASE 2 + PHASE 3 + PHASE 4 + PHASE 5 + PHASE 6 + PHASE 7 + PHASE 8 COMPLETION REPORT\n";
   report += " Spec version: " + GZ_PROJECT_VERSION + " | " + GZ_PROJECT_VERSION_P2 + " | " + GZ_PROJECT_VERSION_P3 + " | " + GZ_PROJECT_VERSION_P4 + " | " + GZ_PROJECT_VERSION_P5 + " | " + GZ_PROJECT_VERSION_P6 + " | " + GZ_PROJECT_VERSION_P7 + " | " + GZ_PROJECT_VERSION_P8 + "\n";
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
   report += "Interfaces: GZ_TimeContext, CGZDatasetInfo (Phase 1), GZ_Swing / CGZSwingEngine (Phase 2),\n";
   report += "            GZ_Leg / CGZLegEngine / CGZBreakEngine (Phase 3), GZ_Setup / CGZFibEngine /\n";
   report += "            CGZSetupStateMachine (Phase 4), GZ_Trade / CGZEntryEngine / CGZTradeSimulator\n";
   report += "            (Phase 5), GZ_TradeExit / CGZExitEngine (Phase 6), GZ_TradeJournal /\n";
   report += "            CGZJournalEngine / GZ_LedgerEvent / CGZEventLedger (Phase 7), GZ_MetricsSummary /\n";
   report += "            CGZMetricsEngine (Phase 8) - all consumed by later phases; Update()/UpdateBar()/\n";
   report += "            OnBar()/CheckBreak()/OnLegCreated()/OnLegBroken()/MarkEntered()/\n";
   report += "            CancelForInvalidPenetration()/OnTradeEntered() are live-safe, DetectAll()/\n";
   report += "            CGZTradeSimulator.Run()/BuildFromFinalState()/CGZMetricsEngine.Compute() are\n";
   report += "            research-batch\n\n";

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
   report += "(no bar-by-bar hook needed for it - see GZ_EventLedger.mqh); REJECTION/FILTER_RESULT are\n";
   report += "reserved event types with no producer until Phase 10's Filter Engine and are never\n";
   report += "emitted in this build (see T72).\n\n";

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
   report += "Filter Diagnostics (Setups/Trades before-after, Rejections, metric deltas) is a RESERVED,\n";
   report += "always-zero stub - it needs Phase 10's Filter Engine to produce a WITH/WITHOUT population\n";
   report += "to diff, which does not exist yet (design note 7, see T84) - DEFERRED TO PHASE 10/11.\n\n";

   report += "--- Automated Test Results (T01-T86: T01-T18 Phase 1, T19-T23 Phase 2, T24-T34 Phase 3, T35-T45 Phase 4, T46-T54 Phase 5, T55-T64 Phase 6, T65-T74 Phase 7, T75-T86 Phase 8) ---\n";
   int pass = g_harness.PassCount();
   int fail = g_harness.FailCount();
   for(int i=0;i<g_harness.ResultCount();i++)
     {
      GZ_TestResult r = g_harness.GetResult(i);
      report += StringFormat("%s: %s - %s\n", r.id, r.passed?"PASS":"FAIL", r.detail);
     }
   report += StringFormat("\nTOTAL: %d PASS / %d FAIL (of %d)\n\n", pass, fail, g_harness.ResultCount());

   report += "--- Known Limitations / Deferred Work ---\n";
   report += "DEFERRED TO PHASE 9+: Experiment Runner (Phase 9), Filter\n";
   report += "Engine (Phase 10, and therefore the Event Ledger's REJECTION/FILTER_RESULT event types AND\n";
   report += "Phase 8's Filter Diagnostics stub - reserved now, never emitted/populated here), Filter\n";
   report += "Combination Research (Phase 11), Robustness/Sensitivity (Phase 12), Walk-Forward (Phase 13),\n";
   report += "Monte Carlo (Phase 14), Final OOS (Phase 15), Research Freeze (Phase 16), Future Execution\n";
   report += "Adapter (Phase 17) - not implemented, by design.\n";
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
      final_status = "PHASE 1+2+3+4+5+6+7+8 BLOCKED (automated test failure - see detail above)";
   else if(!data_ok)
      final_status = "PHASE 1+2+3+4+5+6+7+8 BLOCKED (historical data unavailable for requested symbol/range)";
   else if(!InpBrokerOffsetKnown)
      final_status = "PHASE 1+2+3+4+5+6+7+8 BLOCKED (broker UTC offset not yet verified by user)";
   else
      // This report is only ever printed by the EA's own OnInit() running
      // inside MT5, so reaching this branch already proves compile+attach
      // succeeded - there is nothing further to "wait" on.
      final_status = "PHASE 1+2+3+4+5+6+7+8 COMPLETE";

   report += "--- Final Status ---\n" + final_status + "\n";
   report += "===================================================\n";

   Print(report);

   int handle = FileOpen("GZ_Phase1_2_3_4_5_6_7_8_Report.txt", FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle!=INVALID_HANDLE)
     {
      FileWriteString(handle, report);
      FileClose(handle);
      Print("[GZ] Report written to Common\\Files\\GZ_Phase1_2_3_4_5_6_7_8_Report.txt");
     }
   else
     {
      Print("[GZ] WARNING: could not open report file for writing, error=", GetLastError());
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
   Print("[GZ][BUILD] GoldenZoneSTR_Research_RUNTIME_MARKER_20260923_V9_PHASE8");

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
   g_logger.Info("Init", "GoldenZone STR Phase 1+2+3+4+5+6+7+8 starting up (research/diagnostic mode - no trading).");

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
     }
   else
      g_logger.Warning("Leg", "No M5 data loaded - leg/break/setup/entry/exit detection skipped.");

   //--- Run deterministic automated test harness (synthetic data) -------------
   g_harness.RunAll();

   //--- Report ------------------------------------------------------------------
   BuildAndEmitReport();

   g_logger.Info("Init", "Phase 1+2+3+4+5+6+7+8 diagnostics complete. STOPPING - not proceeding to Phase 9 (Experiment Configuration + Runner) logic.");

   // Initialization succeeds regardless of data/test outcome so the report is
   // visible in the Experts log; the report itself states BLOCKED/FAILED status.
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_logger.Info("Deinit", "GoldenZone STR Phase 1+2+3+4+5+6+7+8 EA removed.");
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
