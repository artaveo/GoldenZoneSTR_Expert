//+------------------------------------------------------------------+
//| GZ_TradeSimulator.mqh                                             |
//| GoldenZone STR - Phase 5 - Historical Trade Simulator            |
//|                                                                    |
//| Research Adapter concern (Roadmap Phase 17 vocabulary): replays   |
//| already-loaded, already-validated M1+M5 data and already-detected |
//| M5 swings (Phase 1/2 output) through the Shared Strategy Core      |
//| (Leg/Break/Setup/Entry engines, Phases 3-5) in strict chronological|
//| order, producing the full deterministic trade list. It owns NO    |
//| strategy decisions itself - every decision is made by the engines |
//| it drives; this file is purely bar-ordering/sequencing.            |
//|                                                                    |
//| M1/M5 ORDERING - THE KEY NO-LOOKAHEAD GUARANTEE OF PHASE 5:        |
//| A live system only learns an M5 candle's final OHLC the instant   |
//| it closes (every 5 minutes); until then, in-progress M1 bars must |
//| only ever be evaluated against structure state as of the PREVIOUS |
//| closed M5 bar. This class enforces that ordering explicitly:      |
//|   for each M5 bar (in chronological order):                       |
//|     1. process every M1 bar with time in [bar5.time, bar5.time+   |
//|        300s) FIRST, using the Leg/Break/Setup state as it stood   |
//|        at the end of the PREVIOUS iteration (i.e. the M5 bar      |
//|        that is currently forming has NOT yet been fed to Leg/     |
//|        Break/Setup) -> CGZEntryEngine.OnBar(..., is_m1_bar=true)  |
//|     2. THEN close this M5 bar: feed newly-confirmed swings into   |
//|        the Leg Engine, extend open legs, advance the shared ATR,  |
//|        check breaks, feed the Setup State Machine (Phase 3/4,     |
//|        unchanged), then feed the Entry Engine's M5-granularity    |
//|        path -> CGZEntryEngine.OnBar(..., is_m1_bar=false)         |
//| M1 bars at/after the LAST M5 bar's close time have no closed M5   |
//| bar to be attributed to in this dataset and are intentionally NOT |
//| processed (documented, not silently guessed - spec "do not        |
//| fabricate data").                                                  |
//+------------------------------------------------------------------+
#ifndef __GZ_TRADE_SIMULATOR_MQH__
#define __GZ_TRADE_SIMULATOR_MQH__

#include "GZ_EntryEngine.mqh"
#include "..\Core\GZ_Constants.mqh"
#include "..\Structure\GZ_StructureTypes.mqh"
#include "..\Leg\GZ_LegEngine.mqh"
#include "..\Leg\GZ_BreakEngine.mqh"
#include "..\Setup\GZ_SetupStateMachine.mqh"
#include "..\Time\GZ_TimeEngine.mqh"
#include "..\Time\GZ_Session.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZTradeSimulator
  {
private:
   CGZLogger        *m_logger;

public:
                     CGZTradeSimulator(CGZLogger *logger=NULL) { m_logger=logger; }

   //--- Run the full Phase 3+4+5 pipeline over `m1`/`m5` (already loaded,
   //--- already validated) and `swings` (already detected over `m5` by
   //--- CGZSwingEngine, Phase 2). All engine parameters must already be
   //--- Init()/Configure()d by the caller with the desired research
   //--- configuration; this method only drives them in the correct,
   //--- live-safe order (see header). Calls setup_sm.OnDataEnd() itself
   //--- once the last M5 bar has been processed.
   void Run(const MqlRates &m1[], const MqlRates &m5[], const GZ_Swing &swings[], int swing_count,
            CGZLegEngine &leg_engine, CGZBreakEngine &break_engine, CGZSetupStateMachine &setup_sm,
            CGZEntryEngine &entry_engine, CGZTimeEngine &time_engine, CGZSessionEngine &session_engine,
            const GZ_SessionProfile &session_profile, bool apply_session_filter)
     {
      int n1 = ArraySize(m1);
      int n5 = ArraySize(m5);
      if(n5==0)
        {
         if(m_logger!=NULL)
            m_logger.Warning("Simulator", "No M5 data supplied - Phase 3/4/5 replay skipped.");
         return;
        }

      int swing_ptr = 0;
      int m1_ptr    = 0;

      for(int m5_ptr=0; m5_ptr<n5; m5_ptr++)
        {
         MqlRates bar5 = m5[m5_ptr];
         datetime bar5_close_time = bar5.time + GZ_SPACING_M5_SECONDS;

         //--- 1. M1 bars belonging to this STILL-FORMING M5 candle, using
         //---    only structure state as of the previous M5 close.
         while(m1_ptr<n1 && m1[m1_ptr].time<bar5_close_time)
           {
            entry_engine.OnBar(setup_sm, m1[m1_ptr], true, break_engine.CurrentAtr(), break_engine.AtrReady());
            m1_ptr++;
           }

         //--- 2. Close this M5 bar: structure (Phase 2/3/4, unchanged order).
         while(swing_ptr<swing_count && swings[swing_ptr].confirmation_time==bar5.time)
           {
            int new_idx=-1;
            if(leg_engine.Update(swings[swing_ptr], break_engine.CurrentAtr(), break_engine.AtrReady(), new_idx))
               setup_sm.OnLegCreated(leg_engine.GetLeg(new_idx));
            swing_ptr++;
           }

         leg_engine.UpdateBar(bar5);
         break_engine.OnBar(bar5);

         int lc = leg_engine.LegCount();
         for(int j=0;j<lc;j++)
           {
            GZ_Leg leg = leg_engine.GetLeg(j);
            if(leg.broken)
               continue;
            if(break_engine.CheckBreak(leg, bar5))
              {
               leg_engine.SetLeg(j, leg);
               setup_sm.OnLegBroken(leg);
              }
           }

         GZ_TimeContext ctx;
         time_engine.BuildContext(bar5.time, ctx);
         bool inside_session = (session_engine.Evaluate(ctx, session_profile)==GZ_SESSION_INSIDE);
         setup_sm.OnBar(bar5, inside_session, apply_session_filter);

         //--- 3. Entry Engine's M5-granularity path (CLOSE_CONFIRMATION
         //---    model only - no-op for every other model, see OnBar()).
         entry_engine.OnBar(setup_sm, bar5, false, break_engine.CurrentAtr(), break_engine.AtrReady());
        }

      // Trailing M1 bars at/after the last M5 bar's close time belong to an
      // M5 candle this dataset never delivered - intentionally not
      // processed (documented above), not silently evaluated against stale
      // structure.

      setup_sm.OnDataEnd(m5[n5-1].time);
     }
  };

#endif // __GZ_TRADE_SIMULATOR_MQH__
