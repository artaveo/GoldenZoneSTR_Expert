//+------------------------------------------------------------------+
//| GZ_EntryEngine.mqh                                                |
//| GoldenZone STR - Phase 5 - Entry Engine                          |
//|                                                                    |
//| Watches setups already at FIB_ACTIVE/WAITING_ENTRY (Phase 4       |
//| output - unmodified) and decides WHEN and AT WHAT PRICE a setup   |
//| is actually entered, producing one GZ_Trade per fill. NO SL/TP/BE |
//| logic and NO trade management lives here (Phase 6+) - initial_risk|
//| is left at its reserved 0.0 (see GZ_EntryTypes.mqh design note 2).|
//|                                                                    |
//| Shared-Strategy-Core design (mirrors Phases 2-4): a single         |
//| instance works for both historical research (fed bars in bulk via |
//| CGZTradeSimulator) and a future live Execution Adapter (fed one   |
//| closed bar at a time via OnBar()). It never inspects data beyond  |
//| what it has been given.                                            |
//|                                                                    |
//| GRANULARITY (Roadmap: "M1 execution; M5 structure" - Phase 1 spec |
//| Section 11). Phase 4's WAITING_ENTRY gate (price touched the      |
//| broader watched zone) stays M5-only and untouched by this file.   |
//| On top of that gate, this engine evaluates the actual fill        |
//| trigger at whichever granularity its configured model calls for:  |
//|   GZ_ENTRY_TOUCH / GZ_ENTRY_LIMIT / GZ_ENTRY_M1_CONFIRMATION -> M1 |
//|   GZ_ENTRY_CLOSE_CONFIRMATION                                -> M5 |
//| OnBar() is a no-op for bars of the "wrong" granularity for the    |
//| configured model (see is_m1_bar) - one call site, no duplicated   |
//| setup-iteration logic per model.                                   |
//|                                                                    |
//| NO LOOKAHEAD: OnBar() only ever uses the bar it is given and       |
//| state already recorded on earlier calls. It is CGZTradeSimulator's|
//| job (not this file's) to guarantee that the M1 bars it feeds here |
//| were not evaluated using a not-yet-closed M5 structure update -   |
//| see that file's header for the exact ordering guarantee.           |
//+------------------------------------------------------------------+
#ifndef __GZ_ENTRY_ENGINE_MQH__
#define __GZ_ENTRY_ENGINE_MQH__

#include "GZ_EntryTypes.mqh"
#include "..\Setup\GZ_SetupTypes.mqh"
#include "..\Setup\GZ_FibEngine.mqh"
#include "..\Setup\GZ_SetupStateMachine.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZEntryEngine
  {
private:
   GZ_EntryConfig    m_cfg;
   CGZLogger        *m_logger;
   GZ_Trade          m_trades[];
   long              m_next_trade_id;

   //--- per-setup consecutive-confirmation streak counters, used only by
   //--- GZ_ENTRY_CLOSE_CONFIRMATION / GZ_ENTRY_M1_CONFIRMATION. Parallel
   //--- arrays keyed by setup id (kept separate from GZ_Setup itself -
   //--- Phase 4's struct stays untouched, see design intent above).
   long              m_streak_setup_id[];
   int               m_streak_count[];

   int FindStreak(long setup_id) const
     {
      int n = ArraySize(m_streak_setup_id);
      for(int i=0;i<n;i++)
         if(m_streak_setup_id[i]==setup_id)
            return i;
      return -1;
     }

   int EnsureStreak(long setup_id)
     {
      int idx = FindStreak(setup_id);
      if(idx>=0)
         return idx;
      int n = ArraySize(m_streak_setup_id);
      ArrayResize(m_streak_setup_id, n+1);
      ArrayResize(m_streak_count, n+1);
      m_streak_setup_id[n] = setup_id;
      m_streak_count[n]    = 0;
      return n;
     }

   void ResetStreak(long setup_id)
     {
      int idx = FindStreak(setup_id);
      if(idx>=0)
         m_streak_count[idx] = 0;
     }

   //--- Penetration buffer in price terms. `usable`=false means a buffer
   //--- was requested (penetration_atr_mult>0) but ATR is not yet ready -
   //--- callers must skip this bar entirely rather than treat 0.0 as "no
   //--- buffer configured" (mirrors CGZBreakEngine::CheckBreak's own
   //--- ATR-buffer handling - do not guess).
   double PenetrationPrice(double current_atr, bool atr_ready, bool &usable) const
     {
      if(m_cfg.penetration_atr_mult<=0.0)
        {
         usable = true;
         return 0.0;
        }
      if(!atr_ready)
        {
         usable = false;
         return 0.0;
        }
      usable = true;
      return m_cfg.penetration_atr_mult * current_atr;
     }

   void DoEnter(CGZSetupStateMachine &sm, const GZ_Setup &s, datetime t, double fill_price, double entry_level_price, long bar_spread)
     {
      if(!sm.MarkEntered(s.id, t))
         return; // already terminal (should not happen - defensive only)

      GZ_Trade tr; tr.Clear();
      tr.id                  = m_next_trade_id++;
      tr.setup_id            = s.id;
      tr.entry_time          = t;
      tr.entry_price         = fill_price;
      tr.direction           = s.leg.direction;
      tr.fib_level           = m_cfg.entry_fib_ratio;
      tr.entry_model         = m_cfg.model;
      tr.spread_assumption   = (double)bar_spread;
      tr.slippage_assumption = MathAbs(fill_price - entry_level_price);
      tr.initial_risk        = 0.0; // DEFERRED TO PHASE 6 - see GZ_EntryTypes.mqh design note 2

      int n = ArraySize(m_trades);
      ArrayResize(m_trades, n+1);
      m_trades[n] = tr;

      ResetStreak(s.id);

      if(m_logger!=NULL)
         m_logger.Info("Entry", StringFormat(
            "Trade #%d setup=#%d (%s) model=%s fib=%.3f entry=%.5f slippage=%.5f spread=%.1f at=%s",
            (int)tr.id, (int)s.id, tr.DirectionToString(), tr.EntryModelToString(),
            tr.fib_level, tr.entry_price, tr.slippage_assumption, tr.spread_assumption, TimeToString(t)));
     }

public:
                     CGZEntryEngine(CGZLogger *logger=NULL) { m_logger=logger; m_next_trade_id=1; m_cfg.Default(); }

   void              Init(const GZ_EntryConfig &cfg)
     {
      m_cfg = cfg;
      m_next_trade_id = 1;
      ArrayResize(m_trades, 0);
      ArrayResize(m_streak_setup_id, 0);
      ArrayResize(m_streak_count, 0);
     }

   int               TradeCount() const { return ArraySize(m_trades); }
   GZ_Trade          GetTrade(int i) const { return m_trades[i]; }

   //--- Feed one CLOSED bar. `is_m1_bar` tells the engine which stream
   //--- this bar came from - see the granularity table in the header.
   //--- `current_atr`/`atr_ready` must be the shared Break Engine ATR
   //--- value as of this same point in the replay (no duplicate ATR
   //--- series - see GZ_EntryTypes.mqh).
   void              OnBar(CGZSetupStateMachine &sm, const MqlRates &bar, bool is_m1_bar, double current_atr, bool atr_ready)
     {
      bool model_wants_this_stream = (m_cfg.model==GZ_ENTRY_CLOSE_CONFIRMATION) ? (!is_m1_bar) : is_m1_bar;
      if(!model_wants_this_stream)
         return;

      int n = sm.SetupCount();
      for(int i=0;i<n;i++)
        {
         GZ_Setup s = sm.GetSetup(i);
         if(s.IsTerminal())
            continue;
         if(s.state!=GZ_SETUP_FIB_ACTIVE && s.state!=GZ_SETUP_WAITING_ENTRY)
            continue;
         if(bar.time < s.fib_active_time)
            continue; // never evaluate a bar that predates this setup's fib zone existing

         bool bullish = (s.leg.direction==GZ_LEG_BULLISH);

         //--- Invalid-penetration check: price has fully erased the leg
         //--- (gone past the 100% origin level) without ever being
         //--- entered - wires up GZ_CANCEL_INVALID_PENETRATION (see
         //--- GZ_SetupTypes.mqh / GZ_SetupStateMachine.mqh). Checked
         //--- before the entry trigger below, at whichever granularity
         //--- this OnBar() call represents for the configured model.
         bool invalidated = bullish ? (bar.low<=s.leg.origin_swing.price) : (bar.high>=s.leg.origin_swing.price);
         if(invalidated)
           {
            sm.CancelForInvalidPenetration(s.id, bar.time);
            ResetStreak(s.id);
            continue;
           }

         if(s.state!=GZ_SETUP_WAITING_ENTRY)
            continue; // Phase 4's M5 zone-touch gate has not fired yet
         if(bar.time < s.waiting_entry_time)
            continue; // no lookahead relative to that gate

         double entry_level_price = CGZFibEngine::PriceAtRatio(s.leg, m_cfg.entry_fib_ratio);

         bool   pen_usable;
         double pen_price = PenetrationPrice(current_atr, atr_ready, pen_usable);
         if(!pen_usable)
            continue; // buffer requested but ATR not ready - do not guess

         if(m_cfg.model==GZ_ENTRY_TOUCH || m_cfg.model==GZ_ENTRY_LIMIT)
           {
            bool triggered = bullish ? (bar.low<=entry_level_price-pen_price)
                                      : (bar.high>=entry_level_price+pen_price);
            if(!triggered)
               continue;
            double fill_price = (m_cfg.model==GZ_ENTRY_LIMIT) ? entry_level_price : (bullish ? bar.low : bar.high);
            DoEnter(sm, s, bar.time, fill_price, entry_level_price, bar.spread);
            continue;
           }

         // GZ_ENTRY_CLOSE_CONFIRMATION / GZ_ENTRY_M1_CONFIRMATION: require
         // `confirmation_candles` CONSECUTIVE closes beyond the entry level
         // (a broken streak resets the counter - must be truly consecutive).
         bool confirms = bullish ? (bar.close>=entry_level_price+pen_price)
                                  : (bar.close<=entry_level_price-pen_price);
         int idx = EnsureStreak(s.id);
         if(confirms)
            m_streak_count[idx]++;
         else
            m_streak_count[idx] = 0;

         if(m_streak_count[idx]>=m_cfg.confirmation_candles)
            DoEnter(sm, s, bar.time, bar.close, entry_level_price, bar.spread);
        }
     }
  };

#endif // __GZ_ENTRY_ENGINE_MQH__
