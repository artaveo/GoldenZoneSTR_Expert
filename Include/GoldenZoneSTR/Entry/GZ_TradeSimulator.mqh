//+------------------------------------------------------------------+
//| GZ_TradeSimulator.mqh                                             |
//| GoldenZone STR - Phase 5 - Historical Trade Simulator            |
//|                                                                    |
//| Research Adapter concern (Roadmap Phase 17 vocabulary): replays   |
//| already-loaded, already-validated M1+M5 data and already-detected |
//| M5 swings (Phase 1/2 output) through the Shared Strategy Core      |
//| (Leg/Break/Setup/Entry/Exit engines, Phases 3-6) in strict         |
//| chronological order, producing the full deterministic trade and   |
//| exit list. It owns NO strategy decisions itself - every decision  |
//| is made by the engines it drives; this file is purely bar-        |
//| ordering/sequencing.                                               |
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
//|        Break/Setup) -> CGZEntryEngine.OnBar(..., is_m1_bar=true), |
//|        then any newly-produced trade is handed to CGZExitEngine   |
//|        (OnTradeEntered), then CGZExitEngine.OnBar() manages every |
//|        already-open trade against this same M1 bar (Phase 6 exit  |
//|        management has no structure dependency, so it carries no   |
//|        equivalent lookahead risk - see GZ_ExitEngine.mqh)         |
//|     2. THEN close this M5 bar: feed newly-confirmed swings into   |
//|        the Leg Engine, extend open legs, advance the shared ATR,  |
//|        check breaks, feed the Setup State Machine (Phase 3/4,     |
//|        unchanged), then feed the Entry Engine's M5-granularity    |
//|        path -> CGZEntryEngine.OnBar(..., is_m1_bar=false), again  |
//|        handing any newly-produced trade to CGZExitEngine           |
//| M1 bars at/after the LAST M5 bar's close time have no closed M5   |
//| bar to be attributed to in this dataset and are intentionally NOT |
//| processed (documented, not silently guessed - spec "do not        |
//| fabricate data").                                                  |
//|                                                                    |
//| PHASE 7 INTEGRATION (MAE/MFE + Event Ledger - see                 |
//| GZ_JournalEngine.mqh / GZ_EventLedger.mqh): CGZJournalEngine is a  |
//| live, bar-by-bar hook (MAE/MFE cannot be reconstructed after the   |
//| fact) wired into the exact same points as CGZExitEngine above -   |
//| OnTradeEntered() right after Phase 6's own OnTradeEntered() (so    |
//| the real initial_risk it just computed is available), then         |
//| OnBar() alongside CGZExitEngine.OnBar() for every M1 bar. Trade    |
//| closure is detected by scanning CGZExitEngine's own exits after    |
//| each OnBar() call (SyncJournalClosures()) rather than adding any   |
//| new hook into GZ_ExitEngine.mqh itself - this keeps Phase 6's      |
//| already-frozen engine file completely untouched (documented       |
//| choice, not an oversight - the scan is bounded by open-trade count |
//| via CGZJournalEngine::OpenCount() so it is a cheap no-op whenever  |
//| nothing is open, which is most of any dataset). CGZEventLedger, in |
//| contrast, needs NO bar-by-bar hook at all - every ledger row is    |
//| fully determined by already-final Setup/Entry/Exit state, so it is |
//| built once via BuildFromFinalState() at the very end, alongside    |
//| the existing MarkExited() final pass below.                        |
//+------------------------------------------------------------------+
#ifndef __GZ_TRADE_SIMULATOR_MQH__
#define __GZ_TRADE_SIMULATOR_MQH__

#include "GZ_EntryEngine.mqh"
#include "..\Exit\GZ_ExitEngine.mqh"
#include "..\Journal\GZ_JournalEngine.mqh"
#include "..\Journal\GZ_EventLedger.mqh"
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

   //--- Look up the (locked) leg behind a trade's setup - needed by
   //--- CGZExitEngine::OnTradeEntered() for the STRUCTURE SL model.
   //--- Linear scan is fine: SetupCount() is small relative to the bar
   //--- counts this replay already processes.
   bool FindLegForSetup(CGZSetupStateMachine &setup_sm, long setup_id, GZ_Leg &leg_out) const
     {
      int n = setup_sm.SetupCount();
      for(int i=0;i<n;i++)
        {
         GZ_Setup s = setup_sm.GetSetup(i);
         if(s.id==setup_id)
           {
            leg_out = s.leg;
            return true;
           }
        }
      return false;
     }

   //--- Hand every trade CGZEntryEngine produced since `handled_count`
   //--- to CGZExitEngine.OnTradeEntered(), then CGZJournalEngine.
   //--- OnTradeEntered() (Phase 7 - needs the initial_risk Phase 6 just
   //--- computed, see header), then return the new total so the
   //--- caller's running count stays in sync.
   int HandOffNewTrades(CGZEntryEngine &entry_engine, CGZSetupStateMachine &setup_sm, CGZExitEngine &exit_engine,
                         CGZJournalEngine &journal_engine, int handled_count, double current_atr, bool atr_ready)
     {
      int total = entry_engine.TradeCount();
      for(int i=handled_count; i<total; i++)
        {
         GZ_Trade tr = entry_engine.GetTrade(i);
         GZ_Leg leg;
         if(FindLegForSetup(setup_sm, tr.setup_id, leg))
           {
            exit_engine.OnTradeEntered(tr, leg, current_atr, atr_ready);
            GZ_TradeExit justOpened = exit_engine.GetExit(exit_engine.ExitCount()-1); // just appended above
            journal_engine.OnTradeEntered(tr, justOpened.initial_risk);
           }
         else if(m_logger!=NULL)
            m_logger.Error("Simulator", StringFormat("Trade #%d: no matching setup #%d found - exit management skipped.",
                           (int)tr.id, (int)tr.setup_id));
        }
      return total;
     }

   //--- Phase 7: detect trades CGZExitEngine has closed (since the last
   //--- call) and finalize their journal record. Scans CGZExitEngine's
   //--- own exits rather than adding a new hook into that (Phase 6,
   //--- already-frozen) file - see header. OnTradeClosed() is itself
   //--- idempotent, so calling this every bar is safe even though it
   //--- re-checks every exit each time; the OpenCount() guard makes the
   //--- common case (nothing open yet) a cheap no-op.
   void SyncJournalClosures(CGZExitEngine &exit_engine, CGZJournalEngine &journal_engine)
     {
      if(journal_engine.OpenCount()==0)
         return;
      int n = exit_engine.ExitCount();
      for(int i=0;i<n;i++)
        {
         GZ_TradeExit ex = exit_engine.GetExit(i);
         if(!ex.is_open)
            journal_engine.OnTradeClosed(ex.trade_id, ex.exit_time, ex.exit_price, ex.realized_r);
        }
     }

public:
                     CGZTradeSimulator(CGZLogger *logger=NULL) { m_logger=logger; }

   //--- Run the full Phase 3+4+5+6 pipeline over `m1`/`m5` (already
   //--- loaded, already validated) and `swings` (already detected over
   //--- `m5` by CGZSwingEngine, Phase 2). All engine parameters must
   //--- already be Init()/Configure()d by the caller with the desired
   //--- research configuration; this method only drives them in the
   //--- correct, live-safe order (see header). Calls setup_sm.
   //--- OnDataEnd() and exit_engine.OnDataEnd() itself once the last M5
   //--- bar has been processed. `force_session_exit` gates Phase 6's
   //--- own SESSION_EXIT reason (independent of `apply_session_filter`,
   //--- which only ever governs Phase 4 setup cancellation - see
   //--- GZ_ExitEngine.mqh design note).
   //--- Phase 7 additions: `journal_engine` must already be Init()'d by
   //--- the caller (MAE/MFE/Reach Matrix - streamed live, see header);
   //--- `event_ledger` must already be Init()'d too and is populated
   //--- once, deterministically, at the end of this call (see
   //--- CGZEventLedger::BuildFromFinalState()).
   //--- `use_session_hour_gate` (Phase FCIS Step 0.5): default false = pre-
   //--- FCIS behavior. When true, reuses the SAME `session_profile` already
   //--- passed in (no new profile type - per spec Section 3) as a HARD gate,
   //--- independent of `apply_session_filter`/`force_session_exit` (which
   //--- keep their own pre-existing, different meanings - see
   //--- GZ_SetupStateMachine.mqh / GZ_ExitEngine.mqh):
   //---   - a leg created OUTSIDE the window never becomes/keeps a setup
   //---     (cancelled immediately, GZ_CANCEL_OUTSIDE_SESSION_HOURS);
   //---   - the Entry Engine's trigger is suppressed for any bar (M1 or M5)
   //---     outside the window (GZ_EntryEngine.mqh's `allow_entry_this_bar`).
   //--- Additive trailing parameter - every existing call site (including
   //--- every unit test that calls Run() directly) keeps its exact prior
   //--- behavior unless the caller opts in.
   void Run(const MqlRates &m1[], const MqlRates &m5[], const GZ_Swing &swings[], int swing_count,
            CGZLegEngine &leg_engine, CGZBreakEngine &break_engine, CGZSetupStateMachine &setup_sm,
            CGZEntryEngine &entry_engine, CGZExitEngine &exit_engine,
            CGZJournalEngine &journal_engine, CGZEventLedger &event_ledger,
            CGZTimeEngine &time_engine, CGZSessionEngine &session_engine,
            const GZ_SessionProfile &session_profile, bool apply_session_filter, bool force_session_exit,
            bool use_session_hour_gate=false)
     {
      int n1 = ArraySize(m1);
      int n5 = ArraySize(m5);
      if(n5==0)
        {
         if(m_logger!=NULL)
            m_logger.Warning("Simulator", "No M5 data supplied - Phase 3/4/5/6 replay skipped.");
         return;
        }

      int swing_ptr = 0;
      int m1_ptr    = 0;
      int trades_handled = 0;
      double last_m1_close = 0.0;

      for(int m5_ptr=0; m5_ptr<n5; m5_ptr++)
        {
         MqlRates bar5 = m5[m5_ptr];
         datetime bar5_close_time = bar5.time + GZ_SPACING_M5_SECONDS;

         //--- computed once per M5 bar, up front, so it is available both to
         //--- the leg-creation gate below and to setup_sm.OnBar()/the M5-
         //--- granularity entry call at the end of this iteration.
         GZ_TimeContext ctx;
         time_engine.BuildContext(bar5.time, ctx);
         bool inside_session = (session_engine.Evaluate(ctx, session_profile)==GZ_SESSION_INSIDE);
         bool allow_entry_m5 = (!use_session_hour_gate) || inside_session;

         //--- 1. M1 bars belonging to this STILL-FORMING M5 candle, using
         //---    only structure state as of the previous M5 close.
         while(m1_ptr<n1 && m1[m1_ptr].time<bar5_close_time)
           {
            GZ_TimeContext m1_ctx;
            time_engine.BuildContext(m1[m1_ptr].time, m1_ctx);
            bool m1_inside_session = (session_engine.Evaluate(m1_ctx, session_profile)==GZ_SESSION_INSIDE);
            bool allow_entry_m1 = (!use_session_hour_gate) || m1_inside_session;

            entry_engine.OnBar(setup_sm, m1[m1_ptr], true, break_engine.CurrentAtr(), break_engine.AtrReady(), allow_entry_m1);
            trades_handled = HandOffNewTrades(entry_engine, setup_sm, exit_engine, journal_engine, trades_handled,
                                               break_engine.CurrentAtr(), break_engine.AtrReady());

            exit_engine.OnBar(m1[m1_ptr], m1_inside_session, force_session_exit);
            journal_engine.OnBar(m1[m1_ptr]);
            SyncJournalClosures(exit_engine, journal_engine);

            last_m1_close = m1[m1_ptr].close;
            m1_ptr++;
           }

         //--- 2. Close this M5 bar: structure (Phase 2/3/4, unchanged order).
         while(swing_ptr<swing_count && swings[swing_ptr].confirmation_time==bar5.time)
           {
            int new_idx=-1;
            if(leg_engine.Update(swings[swing_ptr], break_engine.CurrentAtr(), break_engine.AtrReady(), new_idx))
              {
               GZ_Leg new_leg = leg_engine.GetLeg(new_idx);
               int setup_idx = setup_sm.OnLegCreated(new_leg);
               //--- Phase FCIS Step 0.5: a leg formed outside the session-hour
               //--- window never keeps its setup - cancel it immediately with
               //--- the dedicated reason, rather than silently never creating
               //--- it (so the Event Ledger/cancellation counts still show it).
               if(use_session_hour_gate && !inside_session)
                 {
                  GZ_Setup just_created = setup_sm.GetSetup(setup_idx);
                  setup_sm.CancelForOutsideSessionHours(just_created.id, bar5.time);
                 }
              }
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

         setup_sm.OnBar(bar5, inside_session, apply_session_filter);

         //--- 3. Entry Engine's M5-granularity path (CLOSE_CONFIRMATION
         //---    model only - no-op for every other model, see OnBar()).
         entry_engine.OnBar(setup_sm, bar5, false, break_engine.CurrentAtr(), break_engine.AtrReady(), allow_entry_m5);
         trades_handled = HandOffNewTrades(entry_engine, setup_sm, exit_engine, journal_engine, trades_handled,
                                            break_engine.CurrentAtr(), break_engine.AtrReady());
        }

      // Trailing M1 bars at/after the last M5 bar's close time belong to an
      // M5 candle this dataset never delivered - intentionally not
      // processed (documented above), not silently evaluated against stale
      // structure.

      setup_sm.OnDataEnd(m5[n5-1].time);
      double last_price = (last_m1_close>0.0) ? last_m1_close : m5[n5-1].close;
      datetime last_time = (m1_ptr>0) ? m1[m1_ptr-1].time : m5[n5-1].time;
      exit_engine.OnDataEnd(last_time, last_price);
      SyncJournalClosures(exit_engine, journal_engine); // Phase 7: finalize any trades DATA_END just closed

      //--- Final pass: propagate every closed trade's outcome back onto its
      //--- setup (GZ_SETUP_ENTERED -> GZ_SETUP_EXITED), wiring up the stub
      //--- Phase 4 reserved for this exact purpose (see GZ_SetupStateMachine
      //--- ::MarkExited()). Done once, at the end, rather than bar-by-bar -
      //--- no engine in this pipeline consumes a setup's EXITED state for
      //--- any decision, so timing it here changes nothing but is simpler.
      int total_exits = exit_engine.ExitCount();
      for(int i=0;i<total_exits;i++)
        {
         GZ_TradeExit ex = exit_engine.GetExit(i);
         if(!ex.is_open)
            setup_sm.MarkExited(ex.setup_id, ex.exit_time);
        }

      //--- Phase 7: build the Event Ledger, once, from the now-final
      //--- Setup/Entry/Exit state (see GZ_EventLedger.mqh header - no
      //--- bar-by-bar hook needed for this part).
      event_ledger.BuildFromFinalState(setup_sm, entry_engine, exit_engine);
     }
  };

#endif // __GZ_TRADE_SIMULATOR_MQH__
