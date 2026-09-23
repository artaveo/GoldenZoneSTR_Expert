//+------------------------------------------------------------------+
//| GZ_JournalEngine.mqh                                              |
//| GoldenZone STR - Phase 7 - MAE/MFE + R-Path Engine                |
//|                                                                    |
//| Tracks every open GZ_Trade (Phase 5) from the instant it enters   |
//| until it closes: running Maximum Adverse/Favorable Excursion,     |
//| when each was (last) reached, the Reach Matrix of favorable       |
//| R-levels touched, and final duration/realized-R once closed. NO   |
//| entry/exit/SL/TP/BE decision logic lives here (Phase 5/6) and NO  |
//| event-ledger logic (see GZ_EventLedger.mqh) - this file only      |
//| watches price against already-opened trades.                      |
//|                                                                    |
//| Shared-Strategy-Core design (mirrors Phases 2-6): a single         |
//| instance works for both historical research (fed bars in bulk via |
//| CGZTradeSimulator) and a future live Execution Adapter (fed one   |
//| closed bar at a time via OnBar()). It never inspects data beyond  |
//| what it has been given, and it owns its own open/closed state     |
//| independently of CGZExitEngine's - see GZ_TradeSimulator.mqh for  |
//| how the two are kept in sync bar-by-bar without this file ever    |
//| reaching into CGZExitEngine's internals.                          |
//|                                                                    |
//| NO LOOKAHEAD: OnBar() only ever updates a trade using the bar it  |
//| is given; once OnTradeClosed() has been called for a trade_id,    |
//| every subsequent OnBar()/OnTradeClosed() call is a documented,    |
//| idempotent no-op for that record (see T67) - a closed trade's     |
//| MAE/MFE can never be contaminated by bars after its own exit.     |
//+------------------------------------------------------------------+
#ifndef __GZ_JOURNAL_ENGINE_MQH__
#define __GZ_JOURNAL_ENGINE_MQH__

#include "GZ_JournalTypes.mqh"
#include "..\Entry\GZ_EntryTypes.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZJournalEngine
  {
private:
   CGZLogger        *m_logger;
   GZ_TradeJournal   m_journals[];

   int FindByTradeId(long trade_id) const
     {
      int n = ArraySize(m_journals);
      for(int i=0;i<n;i++)
         if(m_journals[i].trade_id==trade_id)
            return i;
      return -1;
     }

public:
                     CGZJournalEngine(CGZLogger *logger=NULL) { m_logger=logger; }

   void              Init()
     {
      ArrayResize(m_journals, 0);
     }

   int               JournalCount() const { return ArraySize(m_journals); }
   GZ_TradeJournal   GetJournal(int i) const { return m_journals[i]; }

   int               OpenCount() const
     {
      int c=0, n=ArraySize(m_journals);
      for(int i=0;i<n;i++) if(m_journals[i].is_open) c++;
      return c;
     }

   //--- Called exactly once, the instant a GZ_Trade is produced by
   //--- CGZEntryEngine AND CGZExitEngine.OnTradeEntered() has already
   //--- computed its initial_risk (see GZ_TradeSimulator.mqh for the
   //--- exact call order - this must run after Phase 6's own hook so
   //--- the real initial_risk, not a guess, is available here).
   void              OnTradeEntered(const GZ_Trade &trade, double initial_risk)
     {
      GZ_TradeJournal j; j.Clear();
      j.trade_id     = trade.id;
      j.setup_id     = trade.setup_id;
      j.direction    = trade.direction;
      j.entry_time   = trade.entry_time;
      j.entry_price  = trade.entry_price;
      j.initial_risk = initial_risk;
      j.mae_price    = trade.entry_price;
      j.mfe_price    = trade.entry_price;
      j.time_to_mae  = trade.entry_time;
      j.time_to_mfe  = trade.entry_time;

      int n = ArraySize(m_journals);
      ArrayResize(m_journals, n+1);
      m_journals[n] = j;

      if(m_logger!=NULL)
         m_logger.Debug("Journal", StringFormat("Trade #%d journal opened entry=%.5f initial_risk=%.5f",
                        (int)trade.id, trade.entry_price, initial_risk));
     }

   //--- Feed one CLOSED M1 bar (same granularity as CGZExitEngine - see
   //--- design note 3 in GZ_JournalTypes.mqh). Updates MAE/MFE/Reach
   //--- Matrix for every currently-open journal record.
   void              OnBar(const MqlRates &bar)
     {
      int n = ArraySize(m_journals);
      for(int i=0;i<n;i++)
        {
         if(!m_journals[i].is_open)
            continue;

         bool bullish = (m_journals[i].direction==GZ_LEG_BULLISH);

         double favorable_price = bullish ? bar.high : bar.low;
         double adverse_price   = bullish ? bar.low  : bar.high;

         double favorable_move = bullish ? (favorable_price-m_journals[i].entry_price)
                                          : (m_journals[i].entry_price-favorable_price);
         double adverse_move   = bullish ? (m_journals[i].entry_price-adverse_price)
                                          : (adverse_price-m_journals[i].entry_price);

         bool have_risk = (m_journals[i].initial_risk>0.0); // design note 5

         // --- MFE (best favorable excursion so far) ---
         double current_mfe_move = bullish ? (m_journals[i].mfe_price-m_journals[i].entry_price)
                                            : (m_journals[i].entry_price-m_journals[i].mfe_price);
         if(favorable_move>current_mfe_move)
           {
            m_journals[i].mfe_price   = favorable_price;
            m_journals[i].mfe_r       = have_risk ? (favorable_move/m_journals[i].initial_risk) : 0.0;
            m_journals[i].time_to_mfe = bar.time;

            if(have_risk)
              {
               for(int lvl=0; lvl<GZ_REACH_LEVEL_COUNT; lvl++)
                 {
                  if(!m_journals[i].reach_hit[lvl] && m_journals[i].mfe_r>=GZ_REACH_LEVELS[lvl])
                    {
                     m_journals[i].reach_hit[lvl]  = true;
                     m_journals[i].reach_time[lvl] = bar.time;
                    }
                 }
              }
           }

         // --- MAE (worst adverse excursion so far) ---
         double current_mae_move = bullish ? (m_journals[i].entry_price-m_journals[i].mae_price)
                                            : (m_journals[i].mae_price-m_journals[i].entry_price);
         if(adverse_move>current_mae_move)
           {
            m_journals[i].mae_price   = adverse_price;
            m_journals[i].mae_r       = have_risk ? (adverse_move/m_journals[i].initial_risk) : 0.0;
            m_journals[i].time_to_mae = bar.time;
           }
        }
     }

   //--- Finalize a trade's journal once CGZExitEngine has closed it.
   //--- Idempotent: a second call for an already-closed trade_id is a
   //--- documented no-op (see T67/GZ_TradeSimulator.mqh's per-bar sync
   //--- loop, which may call this more than once for the same id).
   void              OnTradeClosed(long trade_id, datetime exit_time, double exit_price, double realized_r)
     {
      int idx = FindByTradeId(trade_id);
      if(idx<0 || !m_journals[idx].is_open)
         return;

      m_journals[idx].is_open           = false;
      m_journals[idx].exit_time         = exit_time;
      m_journals[idx].exit_price        = exit_price;
      m_journals[idx].final_r           = realized_r;
      m_journals[idx].duration_seconds  = (int)(exit_time - m_journals[idx].entry_time);

      if(m_logger!=NULL)
         m_logger.Info("Journal", StringFormat(
            "Trade #%d journal CLOSED mae=%.3fR@%s mfe=%.3fR@%s final_r=%.3f duration=%ds highest_reach=%.2fR",
            (int)trade_id, m_journals[idx].mae_r, TimeToString(m_journals[idx].time_to_mae),
            m_journals[idx].mfe_r, TimeToString(m_journals[idx].time_to_mfe),
            realized_r, m_journals[idx].duration_seconds, m_journals[idx].HighestReachHit()));
     }

   //--- Reporting helpers -------------------------------------------------
   double            AverageMae() const
     {
      int n = ArraySize(m_journals);
      if(n==0) return 0.0;
      double sum=0.0; int c=0;
      for(int i=0;i<n;i++) if(!m_journals[i].is_open) { sum+=m_journals[i].mae_r; c++; }
      return (c>0) ? sum/c : 0.0;
     }

   double            AverageMfe() const
     {
      int n = ArraySize(m_journals);
      if(n==0) return 0.0;
      double sum=0.0; int c=0;
      for(int i=0;i<n;i++) if(!m_journals[i].is_open) { sum+=m_journals[i].mfe_r; c++; }
      return (c>0) ? sum/c : 0.0;
     }

   //--- Count of CLOSED journals whose MFE reached-or-passed a given
   //--- Reach Matrix index (0..GZ_REACH_LEVEL_COUNT-1) at some point,
   //--- regardless of the trade's eventual realized outcome - the exact
   //--- "which TP levels would have been achievable" question Phase 12
   //--- Robustness/TP research needs.
   int               ReachCountAtIndex(int level_idx) const
     {
      if(level_idx<0 || level_idx>=GZ_REACH_LEVEL_COUNT)
         return 0;
      int c=0, n=ArraySize(m_journals);
      for(int i=0;i<n;i++)
         if(!m_journals[i].is_open && m_journals[i].reach_hit[level_idx])
            c++;
      return c;
     }
  };

#endif // __GZ_JOURNAL_ENGINE_MQH__
