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
      if(m_logger!=NULL)
         m_logger.Info("Exit", StringFormat(
            "Trade #%d setup=#%d (%s) CLOSED reason=%s price=%.5f R=%.3f at=%s",
            (int)e.trade_id, (int)e.setup_id, e.DirectionToString(), e.ExitReasonToString(),
            e.exit_price, e.realized_r, TimeToString(t)));
     }

public:
                     CGZExitEngine(CGZLogger *logger=NULL) { m_logger=logger; m_cfg.Default(); }

   void              Init(const GZ_ExitConfig &cfg)
     {
      m_cfg = cfg;
      ArrayResize(m_exits, 0);
     }

   int               ExitCount() const { return ArraySize(m_exits); }
   GZ_TradeExit      GetExit(int i) const { return m_exits[i]; }

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

      double initial_risk = MathAbs(trade.entry_price-sl_price);
      double tp_price = bullish ? (trade.entry_price+m_cfg.tp_r_multiple*initial_risk)
                                 : (trade.entry_price-m_cfg.tp_r_multiple*initial_risk);

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

      int n = ArraySize(m_exits);
      ArrayResize(m_exits, n+1);
      m_exits[n] = e;

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
      int n = ArraySize(m_exits);
      for(int i=0;i<n;i++)
        {
         if(!m_exits[i].is_open)
            continue;

         bool bullish = (m_exits[i].direction==GZ_LEG_BULLISH);

         bool touched_sl = bullish ? (bar.low<=m_exits[i].sl_price)  : (bar.high>=m_exits[i].sl_price);
         bool touched_tp = bullish ? (bar.high>=m_exits[i].tp_price) : (bar.low<=m_exits[i].tp_price);

         if(touched_sl || touched_tp)
           {
            if(touched_sl && touched_tp)
              {
               m_exits[i].intrabar_conflict = true;
               if(m_cfg.intrabar_conflict_policy==GZ_CONFLICT_SL_FIRST)
                  CloseTrade(m_exits[i], bar.time, m_exits[i].sl_price,
                             m_exits[i].be_triggered ? GZ_EXIT_BREAK_EVEN : GZ_EXIT_SL_HIT);
               else
                  CloseTrade(m_exits[i], bar.time, m_exits[i].tp_price, GZ_EXIT_TP_HIT);
              }
            else if(touched_sl)
               CloseTrade(m_exits[i], bar.time, m_exits[i].sl_price,
                          m_exits[i].be_triggered ? GZ_EXIT_BREAK_EVEN : GZ_EXIT_SL_HIT);
            else
               CloseTrade(m_exits[i], bar.time, m_exits[i].tp_price, GZ_EXIT_TP_HIT);
            continue; // closed this bar - nothing else applies to it (see header)
           }

         //--- break-even arming (only if not already armed and configured on) ---
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
