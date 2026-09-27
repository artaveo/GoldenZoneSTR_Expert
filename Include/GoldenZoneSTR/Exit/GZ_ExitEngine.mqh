//+------------------------------------------------------------------+
//| GZ_ExitEngine.mqh                                                 |
//| GoldenZone STR - Phase 6 - Exit Engine (SL/TP/BE)                |
//|                                                                    |
//| Manages every open GZ_Trade (Phase 5) from the instant it enters  |
//| until it closes: computes SL/TP once at entry, arms break-even    |
//| when configured, and evaluates SL/TP hits bar-by-bar. NO MAE/MFE/ |
//| R-path/event-ledger/metrics logic lives here (Phase 7+).          |
//|                                                                    |
//| Shared-Strategy-Core design (mirrors Phases 2-5): a single         |
//| instance works for both historical research (fed bars in bulk via |
//| CGZTradeSimulator) and a future live Execution Adapter (fed one   |
//| closed bar at a time via OnBar()). It never inspects data beyond  |
//| what it has been given.                                            |
//|                                                                    |
//| GRANULARITY: exit management runs at M1 (execution) granularity   |
//| exclusively, regardless of which granularity the trade's entry    |
//| model used (a trade entered via CLOSE_CONFIRMATION on M5 is still |
//| managed tick-by-M1-bar once it is open) - "M1 execution" per the  |
//| Phase 1 spec's own architecture framing (Section 11). This is a   |
//| documented architectural decision, not a Roadmap-stated one (see  |
//| GZ_ExitTypes.mqh design notes).                                    |
//|                                                                    |
//| SAME-BAR ORDERING (documented, deterministic - no intrabar path   |
//| data exists, only OHLC): on any one bar, for an open trade,        |
//|   1. SL/TP hit is evaluated FIRST, against the CURRENT stop        |
//|      (already BE-adjusted if BE armed on an earlier bar). If hit, |
//|      the trade closes on this bar - nothing else about this bar   |
//|      matters for it any more.                                      |
//|   2. Only if the trade did NOT close on this bar is break-even    |
//|      arming evaluated (using this same bar's own high/low) for    |
//|      use starting the NEXT bar.                                    |
//|   3. Only if the trade did NOT close on this bar is session-exit  |
//|      evaluated (a schedule fact, given lower priority than a      |
//|      price fact).                                                  |
//| This ordering is a documented choice (Roadmap does not specify    |
//| it), not a hidden assumption - see GZ_ExitTypes.mqh design note 3 |
//| for the separate, Roadmap-mandated SL-vs-TP-in-the-same-bar rule. |
//+------------------------------------------------------------------+
#ifndef __GZ_EXIT_ENGINE_MQH__
#define __GZ_EXIT_ENGINE_MQH__

#include "GZ_ExitTypes.mqh"
#include "..\Entry\GZ_EntryTypes.mqh"
#include "..\Leg\GZ_LegTypes.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZExitEngine
  {
private:
   GZ_ExitConfig     m_cfg;
   CGZLogger        *m_logger;
   GZ_TradeExit      m_exits[];

   //--- Diagnostics only (Phase "Concurrent Same-Direction Setups +
   //--- Opposite-Break Survival" follow-up): the maximum number of trades
   //--- simultaneously OPEN (ENTERED but not yet EXITED) at any single
   //--- point during this run - reported regardless of which switches
   //--- are on, same baseline-comparison purpose as
   //--- CGZSetupStateMachine::PeakNonTerminalSetups(). Peak open count
   //--- can only ever rise the instant a trade is opened
   //--- (OnTradeEntered) - closing a trade never raises it - so
   //--- sampling there is sufficient and exact.
   int               m_peak_open_trades;

   //--- Daily Loss Limit support (NOT diagnostics-only - CGZTradeSimulator
   //--- reads this every bar to accumulate its own running daily total).
   //--- Sum of realized_r over every trade CLOSED during the MOST RECENT
   //--- OnBar() call only - reset to 0.0 at the top of every OnBar() call,
   //--- accumulated by CloseTrade() (called from OnBar() and OnDataEnd()).
   //--- This lets the caller fold "R closed just now" into a day-running
   //--- total in O(1) per bar, without ever re-scanning the full (and
   //--- potentially very large) m_exits[] array.
   double            m_last_bar_closed_r_sum;

   int FindByTradeId(long trade_id) const
     {
      int n = ArraySize(m_exits);
      for(int i=0;i<n;i++)
         if(m_exits[i].trade_id==trade_id)
            return i;
      return -1;
     }

   double ComputeRealizedR(const GZ_TradeExit &e, double exit_price) const
     {
      if(e.initial_risk<=0.0)
         return 0.0; // defensive only - initial_risk is always >0 by construction (see OnTradeEntered)
      double raw = (e.direction==GZ_LEG_BULLISH) ? (exit_price-e.entry_price) : (e.entry_price-exit_price);
      return raw / e.initial_risk;
     }

   void CloseTrade(GZ_TradeExit &e, datetime t, double price, ENUM_GZ_EXIT_REASON reason)
     {
      e.is_open     = false;
      e.exit_time   = t;
      e.exit_price  = price;
      e.exit_reason = reason;
      e.realized_r  = ComputeRealizedR(e, price);
      m_last_bar_closed_r_sum += e.realized_r;
      if(m_logger!=NULL)
         m_logger.Info("Exit", StringFormat(
            "Trade #%d setup=#%d (%s) CLOSED reason=%s price=%.5f R=%.3f at=%s",
            (int)e.trade_id, (int)e.setup_id, e.DirectionToString(), e.ExitReasonToString(),
            e.exit_price, e.realized_r, TimeToString(t)));
     }

   //--- Phase FCIS Step 2 (real bid/ask fills, spec Section 5.2): closing a
   //--- Short is a Buy, filled at the ASK of the bar that touched the level
   //--- (level_price + spread*point); closing a Long is a Sell, unaffected
   //--- (bars are already bid-based). Default false / bullish -> unchanged.
   double ExitFillPrice(double level_price, bool bullish, long bar_spread) const
     {
      if(!m_cfg.use_real_spread_fills || bullish)
         return level_price;
      return level_price + (double)bar_spread * m_cfg.point;
     }

   //--- Phase "Cost Unification + R-Symmetry Fix" Sub-phase A: mirrors
   //--- ExitFillPrice()'s ask-adjustment above, but applied to the STOP
   //--- DISTANCE at entry time rather than to an actual fill price. A
   //--- Long's initial_risk already includes the ask premium paid at
   //--- entry, because trade.entry_price itself is already ask-adjusted
   //--- there (see CGZEntryEngine::ApplyRealSpreadIfLong) - that half is
   //--- untouched by this fix. A Short pays no premium at entry
   //--- (trade.entry_price stays raw bid) but WILL pay one on exit
   //--- (ExitFillPrice() above ask-adjusts a Short's SL/TP fill) - so a
   //--- Short's initial_risk must anticipate that same eventual premium
   //--- here, the same way Long's already does, using the entry bar's
   //--- own recorded spread (trade.spread_assumption). Without this, "1R"
   //--- is not the same real-world distance for both directions (spec
   //--- Bug 1). `false` for use_real_spread_fills, or bullish direction,
   //--- returns raw_sl_price unchanged - the exact pre-this-phase value,
   //--- so behavior with use_real_spread_fills=false is byte-identical.
   double AnticipatedSlPriceIfShort(double raw_sl_price, bool bullish, double entry_bar_spread) const
     {
      if(!m_cfg.use_real_spread_fills || bullish)
         return raw_sl_price;
      return raw_sl_price + entry_bar_spread * m_cfg.point;
     }

   //--- Companion to AnticipatedSlPriceIfShort() above, same Sub-phase A fix.
   //--- ExitFillPrice() ask-adjusts a Short's TP fill exactly the same way it
   //--- ask-adjusts its SL fill (both are a Buy-to-close) - so the STORED
   //--- tp_price must anticipate that same future +spread addition, the same
   //--- way the SL side already does, or a Short's TP-hit lands short of the
   //--- configured tp_r_multiple by spread/initial_risk even after the
   //--- initial_risk correction above (verified algebraically and by
   //--- T-R-SYM-03). `desired_fill_price` is the untouched target this trade
   //--- is meant to realize (entry +/- tp_r_multiple*initial_risk); this
   //--- returns the LEVEL that must be stored so the eventual ask-adjusted
   //--- fill lands exactly on that target. `false` for use_real_spread_fills,
   //--- or bullish direction, returns desired_fill_price unchanged - byte-
   //--- identical to pre-this-phase code in both those cases.
   double AnticipatedTpLevelIfShort(double desired_fill_price, bool bullish, double entry_bar_spread) const
     {
      if(!m_cfg.use_real_spread_fills || bullish)
         return desired_fill_price;
      return desired_fill_price - entry_bar_spread * m_cfg.point;
     }

public:
                     CGZExitEngine(CGZLogger *logger=NULL) { m_logger=logger; m_cfg.Default(); m_peak_open_trades=0; m_last_bar_closed_r_sum=0.0; }

   void              Init(const GZ_ExitConfig &cfg)
     {
      m_cfg = cfg;
      m_peak_open_trades = 0;
      m_last_bar_closed_r_sum = 0.0;
      ArrayResize(m_exits, 0);
     }

   int               ExitCount() const { return ArraySize(m_exits); }
   GZ_TradeExit      GetExit(int i) const { return m_exits[i]; }

   //--- Diagnostics only - see m_peak_open_trades' own comment.
   int               PeakOpenTrades() const { return m_peak_open_trades; }

   //--- Daily Loss Limit support - see m_last_bar_closed_r_sum's own
   //--- comment. Valid only immediately after the OnBar() call it
   //--- belongs to; read it once per bar, right after calling OnBar().
   double            LastBarClosedRealizedR() const { return m_last_bar_closed_r_sum; }

   int               CountByReason(ENUM_GZ_EXIT_REASON reason) const
     {
      int c=0, n=ArraySize(m_exits);
      for(int i=0;i<n;i++) if(!m_exits[i].is_open && m_exits[i].exit_reason==reason) c++;
      return c;
     }

   int               OpenCount() const
     {
      int c=0, n=ArraySize(m_exits);
      for(int i=0;i<n;i++) if(m_exits[i].is_open) c++;
      return c;
     }

   //--- Called exactly once, the instant a GZ_Trade is produced by
   //--- CGZEntryEngine. `leg` is the (locked) leg behind the trade's
   //--- setup - needed for the STRUCTURE SL model's origin price.
   //--- `current_atr`/`atr_ready` must be the shared Break Engine ATR
   //--- value as of this same point in the replay. Computes SL/TP once
   //--- and appends a new open GZ_TradeExit record.
   void              OnTradeEntered(const GZ_Trade &trade, const GZ_Leg &leg, double current_atr, bool atr_ready)
     {
      bool bullish = (trade.direction==GZ_LEG_BULLISH);

      ENUM_GZ_SL_MODEL model_used = m_cfg.sl_model;
      double sl_price;

      bool needs_atr = (m_cfg.sl_model==GZ_SL_ATR) || (m_cfg.sl_model==GZ_SL_STRUCTURE && m_cfg.sl_buffer_atr_mult>0.0);
      if(needs_atr && !atr_ready)
        {
         // ATR requested but not ready - do not guess (mirrors CGZLegEngine's
         // own documented MIN_ATR_DISTANCE fallback): fall back to the
         // STRUCTURE model with zero buffer, logged once.
         model_used = GZ_SL_STRUCTURE;
         sl_price   = leg.origin_swing.price;
         if(m_logger!=NULL)
            m_logger.Warning("Exit", StringFormat(
               "Trade #%d: ATR not ready for configured SL model - falling back to STRUCTURE/zero-buffer SL=%.5f",
               (int)trade.id, sl_price));
        }
      else if(m_cfg.sl_model==GZ_SL_ATR)
        {
         double dist = m_cfg.sl_atr_mult * current_atr;
         sl_price = bullish ? (trade.entry_price-dist) : (trade.entry_price+dist);
        }
      else // GZ_SL_STRUCTURE
        {
         double buffer = m_cfg.sl_buffer_atr_mult * current_atr;
         sl_price = bullish ? (leg.origin_swing.price-buffer) : (leg.origin_swing.price+buffer);
        }

      //--- R-Symmetry Fix (Sub-phase A, spec Bug 1): the SL/TP touch-and-fill
      //--- logic in OnBar() below still uses the RAW sl_price stored in
      //--- e.sl_price - that part is unaffected by this fix and continues to
      //--- ask-adjust dynamically using each bar's OWN spread at touch time.
      //--- Only the RISK DENOMINATOR (initial_risk) is corrected here, using
      //--- the entry bar's spread, so a Short's "1R" already anticipates the
      //--- same exit-side premium a Long's "1R" already anticipates via its
      //--- ask-adjusted entry_price. See AnticipatedSlPriceIfShort() above.
      double anticipated_sl_price_for_risk = AnticipatedSlPriceIfShort(sl_price, bullish, trade.spread_assumption);
      double initial_risk = MathAbs(trade.entry_price-anticipated_sl_price_for_risk);
      double tp_target_fill = bullish ? (trade.entry_price+m_cfg.tp_r_multiple*initial_risk)
                                       : (trade.entry_price-m_cfg.tp_r_multiple*initial_risk);
      double tp_price = AnticipatedTpLevelIfShort(tp_target_fill, bullish, trade.spread_assumption);

      GZ_TradeExit e; e.Clear();
      e.trade_id           = trade.id;
      e.setup_id           = trade.setup_id;
      e.direction          = trade.direction;
      e.entry_price        = trade.entry_price;
      e.sl_model_used      = model_used;
      e.sl_price           = sl_price;
      e.tp_price           = tp_price;
      e.initial_risk       = initial_risk;
      e.tp_r_multiple_used = m_cfg.tp_r_multiple;
      e.entry_time         = trade.entry_time; // Phase 15.5 diagnostic only

      int n = ArraySize(m_exits);
      ArrayResize(m_exits, n+1);
      m_exits[n] = e;

      //--- Peak concurrency: the only point open-trade count can rise -
      //--- see m_peak_open_trades' own comment. e.is_open==true by
      //--- construction (GZ_TradeExit::Clear()), so OpenCount() here
      //--- already includes the trade just appended.
      int open_now = OpenCount();
      if(open_now > m_peak_open_trades)
         m_peak_open_trades = open_now;

      if(m_logger!=NULL)
         m_logger.Info("Exit", StringFormat(
            "Trade #%d setup=#%d (%s) SL/TP set: sl_model=%s sl=%.5f tp=%.5f (%.2fR) initial_risk=%.5f",
            (int)trade.id, (int)trade.setup_id, e.DirectionToString(), EnumToString(model_used),
            sl_price, tp_price, m_cfg.tp_r_multiple, initial_risk));
     }

   //--- Feed one CLOSED M1 bar. Evaluates every open trade per the
   //--- same-bar ordering documented in this file's header.
   //--- `inside_session`/`force_session_exit` drive the SESSION_EXIT
   //--- reason; pass force_session_exit=false to disable it entirely.
   void              OnBar(const MqlRates &bar, bool inside_session, bool force_session_exit)
     {
      m_last_bar_closed_r_sum = 0.0; // reset for THIS bar only - see member's own comment
      int n = ArraySize(m_exits);
      for(int i=0;i<n;i++)
        {
         if(!m_exits[i].is_open)
            continue;

         bool bullish = (m_exits[i].direction==GZ_LEG_BULLISH);

         //--- Phase FCIS Step 2: a Short's SL/TP touch is checked against the
         //--- ASK of this bar (high/low + spread*point) - the same spec
         //--- Section 5.2 approximation documented in GZ_CostTypes.mqh design
         //--- note 5, now applied INSIDE the simulation itself rather than
         //--- only post-hoc. A Long's touch check stays on raw bid HL.
         bool  ask_adjust = (!bullish) && m_cfg.use_real_spread_fills;
         double eval_high = ask_adjust ? (bar.high + (double)bar.spread*m_cfg.point) : bar.high;
         double eval_low  = ask_adjust ? (bar.low  + (double)bar.spread*m_cfg.point) : bar.low;

         bool touched_sl = bullish ? (bar.low<=m_exits[i].sl_price)  : (eval_high>=m_exits[i].sl_price);
         bool touched_tp = bullish ? (bar.high>=m_exits[i].tp_price) : (eval_low<=m_exits[i].tp_price);

         if(touched_sl || touched_tp)
           {
            double sl_fill = ExitFillPrice(m_exits[i].sl_price, bullish, bar.spread);
            double tp_fill = ExitFillPrice(m_exits[i].tp_price, bullish, bar.spread);
            if(touched_sl && touched_tp)
              {
               m_exits[i].intrabar_conflict = true;
               if(m_cfg.intrabar_conflict_policy==GZ_CONFLICT_SL_FIRST)
                  CloseTrade(m_exits[i], bar.time, sl_fill,
                             m_exits[i].be_triggered ? GZ_EXIT_BREAK_EVEN : GZ_EXIT_SL_HIT);
               else
                  CloseTrade(m_exits[i], bar.time, tp_fill, GZ_EXIT_TP_HIT);
              }
            else if(touched_sl)
               CloseTrade(m_exits[i], bar.time, sl_fill,
                          m_exits[i].be_triggered ? GZ_EXIT_BREAK_EVEN : GZ_EXIT_SL_HIT);
            else
               CloseTrade(m_exits[i], bar.time, tp_fill, GZ_EXIT_TP_HIT);
            continue; // closed this bar - nothing else applies to it (see header)
           }

         //--- break-even arming (only if not already armed and configured on) ---
         //--- Phase FCIS Step 2 note: arming is a MARKET-STATE check (did price
         //--- move far enough in favor to justify moving the stop), not an
         //--- order fill, so it deliberately stays on raw bid HL even when
         //--- use_real_spread_fills is on - the ask-adjusted check on the NEXT
         //--- bar's touched_sl (above) is what actually prices the eventual
         //--- BE exit for a Short. Documented choice, not an oversight.
         if(!m_exits[i].be_triggered && m_cfg.be_trigger_r>0.0)
           {
            double trigger_price = bullish ? (m_exits[i].entry_price+m_cfg.be_trigger_r*m_exits[i].initial_risk)
                                            : (m_exits[i].entry_price-m_cfg.be_trigger_r*m_exits[i].initial_risk);
            bool armed = bullish ? (bar.high>=trigger_price) : (bar.low<=trigger_price);
            if(armed)
              {
               double new_sl;
               if(m_cfg.be_level_mode==GZ_BE_LEVEL_ENTRY)
                  new_sl = m_exits[i].entry_price;
               else // ENTRY_OFFSET
                  new_sl = bullish ? (m_exits[i].entry_price+m_cfg.be_level_offset_r*m_exits[i].initial_risk)
                                    : (m_exits[i].entry_price-m_cfg.be_level_offset_r*m_exits[i].initial_risk);

               m_exits[i].be_triggered    = true;
               m_exits[i].be_trigger_time = bar.time;
               m_exits[i].be_new_sl_price = new_sl;
               m_exits[i].sl_price        = new_sl; // active stop moves from this point on

               //--- Phase 15.5 DIAGNOSTICS ONLY (no decision reads these; baseline behavior unchanged)
               m_exits[i].be_armed_on_entry_bar = (bar.time==m_exits[i].entry_time);
               m_exits[i].be_arm_bar_retrace    = bullish ? (bar.low<=new_sl) : (bar.high>=new_sl);

               if(m_logger!=NULL)
                  m_logger.Info("Exit", StringFormat("Trade #%d BREAK-EVEN armed: new_sl=%.5f at=%s",
                                (int)m_exits[i].trade_id, new_sl, TimeToString(bar.time)));
              }
           }

         //--- session-exit (schedule fact, lowest priority - see header) -------
         if(force_session_exit && !inside_session)
            CloseTrade(m_exits[i], bar.time, bar.close, GZ_EXIT_SESSION_EXIT);
        }
     }

   //--- Force-close every still-open trade at the given last-known price
   //--- (the real last bar's close - never fabricated). Mirrors
   //--- CGZSetupStateMachine::OnDataEnd()'s pattern.
   void              OnDataEnd(datetime last_time, double last_price)
     {
      int n = ArraySize(m_exits);
      for(int i=0;i<n;i++)
         if(m_exits[i].is_open)
            CloseTrade(m_exits[i], last_time, last_price, GZ_EXIT_DATA_END);
     }
  };

#endif // __GZ_EXIT_ENGINE_MQH__
