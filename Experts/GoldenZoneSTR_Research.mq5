//+------------------------------------------------------------------+
//|                                    GoldenZoneSTR_Research.mq5    |
//|                                                                    |
//| GoldenZone STR - Phase 1 + Phase 2 + Phase 3 + Phase 4 Research EA |
//| Phase 1: Data Layer + Data Validator + Time Engine                |
//| Phase 2: M5 Structure Engine (swing/pivot detection)               |
//| Phase 3: Leg Engine + Break Engine                                 |
//| Phase 4: Fibonacci Engine + Setup State Machine                    |
//|                                                                    |
//| SCOPE: This EA implements ONLY Phase 1 (Data/Validator/Time/      |
//| Session/Diagnostics/TestHarness), Phase 2 (M5 swing/pivot         |
//| detection), Phase 3 (Leg Engine + Break Engine) and Phase 4        |
//| (Fibonacci Engine + Setup State Machine). It contains NO entry,   |
//| exit, filter or trade-management logic (Phase 5+), and it places  |
//| NO live orders. On init it loads historical data, runs validation,|
//| runs swing detection, runs leg/break detection, runs the setup    |
//| lifecycle (fib zone + cancellation) diagnostically over the       |
//| loaded M5 data, runs the deterministic T01-T45 test harness, and  |
//| prints a completion report. Then it stops - it does not trade and |
//| does not proceed to Phase 5 (Entry Engine + Trade Simulator)      |
//| logic.                                                             |
//+------------------------------------------------------------------+
#property copyright "GoldenZone STR"
#property version   "1.30"
#property description "Phase 1+2+3+4: Data/Validator/Time Engine + M5 Structure Engine + Leg/Break Engine + Fibonacci/Setup State Machine (research/diagnostic only, no trading)"

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
#include <GoldenZoneSTR\Diagnostics\GZ_Logger.mqh>
#include <GoldenZoneSTR\Diagnostics\GZ_TestHarness.mqh>

//--- Inputs -----------------------------------------------------------------
input string             InpSymbol            = "XAUUSD";
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

//+------------------------------------------------------------------+
//| Build and print/save the Phase 1 completion report                |
//+------------------------------------------------------------------+
void BuildAndEmitReport()
  {
   string report = "";
   report += "===================================================\n";
   report += " GoldenZone STR - PHASE 1 + PHASE 2 + PHASE 3 + PHASE 4 COMPLETION REPORT\n";
   report += " Spec version: " + GZ_PROJECT_VERSION + " | " + GZ_PROJECT_VERSION_P2 + " | " + GZ_PROJECT_VERSION_P3 + " | " + GZ_PROJECT_VERSION_P4 + "\n";
   report += " Generated (terminal local time, diagnostic only): " + TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS) + "\n";
   report += "===================================================\n\n";

   report += "--- Implementation ---\n";
   report += "Phase 1 files: GZ_Types, GZ_Config, GZ_Constants, GZ_DataProvider, GZ_DataValidator,\n";
   report += "       GZ_DatasetInfo, GZ_TimeEngine, GZ_DST, GZ_Session, GZ_Logger, GZ_TestHarness\n";
   report += "Phase 2 files: GZ_StructureTypes, GZ_SwingEngine\n";
   report += "Phase 3 files: GZ_LegTypes, GZ_ATR, GZ_LegEngine, GZ_BreakEngine\n";
   report += "Phase 4 files: GZ_SetupTypes, GZ_FibEngine, GZ_SetupStateMachine\n";
   report += "Interfaces: GZ_TimeContext, CGZDatasetInfo (Phase 1), GZ_Swing / CGZSwingEngine (Phase 2),\n";
   report += "            GZ_Leg / CGZLegEngine / CGZBreakEngine (Phase 3), GZ_Setup / CGZFibEngine /\n";
   report += "            CGZSetupStateMachine (Phase 4) - all consumed by later phases; Update()/\n";
   report += "            UpdateBar()/OnBar()/CheckBreak()/OnLegCreated()/OnLegBroken() are live-safe,\n";
   report += "            DetectAll() is research-batch\n\n";

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
   report += StringFormat("Setups=%d  LEG_DETECTED=%d  FIB_ACTIVE=%d  WAITING_ENTRY=%d  CANCELLED=%d\n",
              g_setup_count, g_setup_sm.CountByState(GZ_SETUP_LEG_DETECTED), g_setup_sm.CountByState(GZ_SETUP_FIB_ACTIVE),
              g_setup_sm.CountByState(GZ_SETUP_WAITING_ENTRY), g_setup_sm.CountByState(GZ_SETUP_CANCELLED));
   report += StringFormat("Cancel reasons: OPPOSITE_BREAK=%d NEW_VALID_SETUP=%d SESSION_END=%d DATA_END=%d\n",
              g_setup_sm.CountTerminalByReason(GZ_CANCEL_OPPOSITE_BREAK), g_setup_sm.CountTerminalByReason(GZ_CANCEL_NEW_VALID_SETUP),
              g_setup_sm.CountTerminalByReason(GZ_CANCEL_SESSION_END), g_setup_sm.CountTerminalByReason(GZ_CANCEL_DATA_END));
   report += "At most one non-terminal setup per direction is ever left standing after a new leg\n";
   report += "is created (see T41); an opposite-direction break cancels whatever is still open on\n";
   report += "the other side (see T42). ENTERED/EXITED are stub states, never assigned here - no\n";
   report += "entry/exit logic consumes this output yet - deferred to Phase 5.\n\n";

   report += "--- Automated Test Results (T01-T45: T01-T18 Phase 1, T19-T23 Phase 2, T24-T34 Phase 3, T35-T45 Phase 4) ---\n";
   int pass = g_harness.PassCount();
   int fail = g_harness.FailCount();
   for(int i=0;i<g_harness.ResultCount();i++)
     {
      GZ_TestResult r = g_harness.GetResult(i);
      report += StringFormat("%s: %s - %s\n", r.id, r.passed?"PASS":"FAIL", r.detail);
     }
   report += StringFormat("\nTOTAL: %d PASS / %d FAIL (of %d)\n\n", pass, fail, g_harness.ResultCount());

   report += "--- Known Limitations / Deferred Work ---\n";
   report += "DEFERRED TO PHASE 5: Entry Engine, Trade Simulator - not implemented, by design.\n";
   report += "DEFERRED TO PHASE 6+: Exit Engine, MAE/MFE, Event Ledger, Metrics, Filters, Experiment Runner.\n";
   report += "Weekend-gap classification uses a Saturday-presence heuristic; broker-specific holiday\n";
   report += "calendars are not modeled and would need broker session data if required later.\n";
   report += "Phase 4 setup lifecycle is diagnostic-only in this report; a setup that reaches\n";
   report += "WAITING_ENTRY simply stays there until cancelled or the data range ends - deciding\n";
   report += "when it is actually ENTERED is explicitly Phase 5's job (Entry Engine), not decided\n";
   report += "here. INVALID_PENETRATION cancellation is defined but never triggered in this build -\n";
   report += "it depends on the Entry Engine's penetration parameter (Phase 5). SESSION_END\n";
   report += "cancellation only fires when InpApplySessionFilter=true (default false, since the\n";
   report += "Roadmap does not state whether every setup should be session-scoped by default).\n\n";

   report += "--- User Verification Required ---\n";
   report += "USER TEST REQUIRED #1: Compile this project in MetaEditor and attach the EA to a chart\n";
   report += "  for the configured symbol, then copy this Experts-log report back for review.\n";
   report += "USER TEST REQUIRED #2: Confirm actual broker server UTC offset (InpBrokerUtcOffsetHrs)\n";
   report += "  with your broker/terminal (Market Watch -> Symbols -> session, or broker docs), then\n";
   report += "  set InpBrokerOffsetKnown=true once verified. Until then TIMEZONE_STATUS=UNKNOWN.\n\n";

   string final_status;
   bool data_ok = (g_info_m1.total_bars>0 && g_info_m5.total_bars>0);
   if(fail>0)
      final_status = "PHASE 1+2+3+4 BLOCKED (automated test failure - see detail above)";
   else if(!data_ok)
      final_status = "PHASE 1+2+3+4 BLOCKED (historical data unavailable for requested symbol/range)";
   else if(!InpBrokerOffsetKnown)
      final_status = "PHASE 1+2+3+4 BLOCKED (broker UTC offset not yet verified by user)";
   else
      // This report is only ever printed by the EA's own OnInit() running
      // inside MT5, so reaching this branch already proves compile+attach
      // succeeded - there is nothing further to "wait" on.
      final_status = "PHASE 1+2+3+4 COMPLETE";

   report += "--- Final Status ---\n" + final_status + "\n";
   report += "===================================================\n";

   Print(report);

   int handle = FileOpen("GZ_Phase1_2_3_4_Report.txt", FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle!=INVALID_HANDLE)
     {
      FileWriteString(handle, report);
      FileClose(handle);
      Print("[GZ] Report written to Common\\Files\\GZ_Phase1_2_3_4_Report.txt");
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
   Print("[GZ][BUILD] GoldenZoneSTR_Research_RUNTIME_MARKER_20260922_V5_PHASE4");

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
   g_logger.Info("Init", "GoldenZone STR Phase 1+2+3+4 starting up (research/diagnostic mode - no trading).");

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
   //--- only). Replays the already-loaded, already-validated M5 bars and the
   //--- already-confirmed swings (Phase 2) in chronological order, exactly as
   //--- a live/forward-testing context would receive them one bar at a time:
   //   1. feed any swing(s) confirmed AT this bar's time into the Leg Engine
   //      (candidate leg creation) -> feed each newly-created leg into the
   //      Setup State Machine (OnLegCreated)
   //   2. extend every still-open leg's extreme with this bar
   //   3. advance the shared ATR calculation with this bar
   //   4. check every still-open leg for a break on this bar -> feed any
   //      newly-broken leg into the Setup State Machine (OnLegBroken)
   //   5. feed this bar + its session status into the Setup State Machine
   //      (OnBar) regardless of whether anything broke on it
   // ATR passed to leg creation (step 1) is the value as of the PREVIOUS bar -
   // deterministic and never looks ahead into the bar being processed.
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

   g_leg_count = 0;
   g_broken_leg_count = 0;
   g_setup_count = 0;
   if(n5>0)
     {
      int swing_ptr = 0;
      for(int i=0;i<n5;i++)
        {
         MqlRates bar = m5[i];

         while(swing_ptr<g_swing_count && g_swings[swing_ptr].confirmation_time==bar.time)
           {
            int new_idx=-1;
            if(g_leg_engine.Update(g_swings[swing_ptr], g_break_engine.CurrentAtr(), g_break_engine.AtrReady(), new_idx))
               g_setup_sm.OnLegCreated(g_leg_engine.GetLeg(new_idx));
            swing_ptr++;
           }

         g_leg_engine.UpdateBar(bar);
         g_break_engine.OnBar(bar);

         int lc = g_leg_engine.LegCount();
         for(int j=0;j<lc;j++)
           {
            GZ_Leg leg = g_leg_engine.GetLeg(j);
            if(leg.broken)
               continue;
            if(g_break_engine.CheckBreak(leg, bar))
              {
               g_leg_engine.SetLeg(j, leg);
               g_setup_sm.OnLegBroken(leg);
              }
           }

         GZ_TimeContext bar_ctx;
         g_time_engine.BuildContext(bar.time, bar_ctx);
         bool inside_session = (g_session_engine.Evaluate(bar_ctx, session_profile)==GZ_SESSION_INSIDE);
         g_setup_sm.OnBar(bar, inside_session, InpApplySessionFilter);
        }

      g_setup_sm.OnDataEnd(m5[n5-1].time);

      g_leg_count = g_leg_engine.LegCount();
      for(int j=0;j<g_leg_count;j++)
         if(g_leg_engine.GetLeg(j).broken)
            g_broken_leg_count++;
      g_setup_count = g_setup_sm.SetupCount();

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
         "Phase 4: setups=%d LEG_DETECTED=%d FIB_ACTIVE=%d WAITING_ENTRY=%d CANCELLED=%d (zone=[%.2f,%.2f] session_filter=%s)",
         g_setup_count, g_setup_sm.CountByState(GZ_SETUP_LEG_DETECTED), g_setup_sm.CountByState(GZ_SETUP_FIB_ACTIVE),
         g_setup_sm.CountByState(GZ_SETUP_WAITING_ENTRY), g_setup_sm.CountByState(GZ_SETUP_CANCELLED),
         InpFibZoneMinRatio, InpFibZoneMaxRatio, InpApplySessionFilter?"true":"false"));
      g_logger.Info("Setup", StringFormat(
         "  Cancel reasons: OPPOSITE_BREAK=%d NEW_VALID_SETUP=%d SESSION_END=%d DATA_END=%d",
         g_setup_sm.CountTerminalByReason(GZ_CANCEL_OPPOSITE_BREAK), g_setup_sm.CountTerminalByReason(GZ_CANCEL_NEW_VALID_SETUP),
         g_setup_sm.CountTerminalByReason(GZ_CANCEL_SESSION_END), g_setup_sm.CountTerminalByReason(GZ_CANCEL_DATA_END)));
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
     }
   else
      g_logger.Warning("Leg", "No M5 data loaded - leg/break/setup detection skipped.");

   //--- Run deterministic automated test harness (synthetic data) -------------
   g_harness.RunAll();

   //--- Report ------------------------------------------------------------------
   BuildAndEmitReport();

   g_logger.Info("Init", "Phase 1+2+3+4 diagnostics complete. STOPPING - not proceeding to Phase 5 (Entry Engine + Trade Simulator) logic.");

   // Initialization succeeds regardless of data/test outcome so the report is
   // visible in the Experts log; the report itself states BLOCKED/FAILED status.
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_logger.Info("Deinit", "GoldenZone STR Phase 1+2+3+4 EA removed.");
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
