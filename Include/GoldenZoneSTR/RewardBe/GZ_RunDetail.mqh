//+------------------------------------------------------------------+
//| GZ_RunDetail.mqh                                                  |
//| GoldenZone STR - Phase 15.5 - per-trade detail of ONE experiment  |
//|                                                                    |
//| CGZExperimentRunner::Execute() builds fresh Exit/Journal engines   |
//| per experiment and discards them once GZ_ExperimentResult (metrics |
//| only) is packaged. Phase 15.5 needs the per-trade exit reason, R,  |
//| MAE/MFE, Reach flags and the two intrabar diagnostics of every     |
//| experiment, so this class snapshots them (read-only) right before  |
//| the engines go out of scope. It changes NO simulation behavior:   |
//| an experiment run WITHOUT a detail object is byte-for-byte the    |
//| same code path as before.                                          |
//|                                                                    |
//| Storage is parallel dynamic arrays inside a CLASS (not nested in a |
//| struct that lives in another dynamic array - the MQL5 trouble spot |
//| this repo avoids everywhere, see GZ_RobustnessTypes.mqh note 2).   |
//| Row i of every array describes the same trade. Order == the         |
//| journal/exit engines' own order (trade-entry order), i.e. exactly  |
//| the order Phase 8's Metrics Engine uses for its drawdown/streaks.  |
//+------------------------------------------------------------------+
#ifndef __GZ_RUN_DETAIL_MQH__
#define __GZ_RUN_DETAIL_MQH__

#include "..\Exit\GZ_ExitTypes.mqh"
#include "..\Exit\GZ_ExitEngine.mqh"
#include "..\Journal\GZ_JournalTypes.mqh"
#include "..\Journal\GZ_JournalEngine.mqh"

class CGZRunDetail
  {
public:
   int       count;
   long      trade_id[];
   datetime  entry_time[];
   double    entry_price[];
   int       direction[];
   datetime  exit_time[];
   int       exit_reason[];        // ENUM_GZ_EXIT_REASON as int
   double    realized_r[];
   double    initial_risk[];
   bool      be_triggered[];
   bool      intrabar_conflict[];
   bool      be_on_entry_bar[];
   bool      be_arm_retrace[];
   double    mae_r[];
   double    mfe_r[];
   datetime  time_to_mae[];      // journal: time the FINAL mae_r was last set (initial value = entry_time)
   datetime  time_to_mfe[];      // journal: time the FINAL mfe_r was last set (initial value = entry_time)
   bool      reach[];              // count*GZ_REACH_LEVEL_COUNT, row-major

                     CGZRunDetail() { Clear(); }

   void              Clear()
     {
      count = 0;
      ArrayResize(trade_id, 0);       ArrayResize(entry_time, 0);   ArrayResize(entry_price, 0);
      ArrayResize(direction, 0);      ArrayResize(exit_time, 0);    ArrayResize(exit_reason, 0);
      ArrayResize(realized_r, 0);     ArrayResize(initial_risk, 0); ArrayResize(be_triggered, 0);
      ArrayResize(intrabar_conflict, 0); ArrayResize(be_on_entry_bar, 0); ArrayResize(be_arm_retrace, 0);
      ArrayResize(mae_r, 0);          ArrayResize(mfe_r, 0);        ArrayResize(reach, 0);
      ArrayResize(time_to_mae, 0);    ArrayResize(time_to_mfe, 0);
     }

   //--- Reach flags are derived from mfe_r with the SAME rule the Journal
   //--- Engine uses (mfe_r >= GZ_REACH_LEVELS[l]); also used by unit tests
   //--- to hand-build populations.
   void              AddTrade(long id, datetime et, double ep, int dir, datetime xt, int reason, double r, double risk,
                              bool be_trig, bool conflict, bool be_entry_bar, bool retrace, double mae, double mfe,
                              datetime t_mae=0, datetime t_mfe=0)
     {
      int n = count;
      ArrayResize(trade_id, n+1);          ArrayResize(entry_time, n+1);   ArrayResize(entry_price, n+1);
      ArrayResize(direction, n+1);         ArrayResize(exit_time, n+1);    ArrayResize(exit_reason, n+1);
      ArrayResize(realized_r, n+1);        ArrayResize(initial_risk, n+1); ArrayResize(be_triggered, n+1);
      ArrayResize(intrabar_conflict, n+1); ArrayResize(be_on_entry_bar, n+1); ArrayResize(be_arm_retrace, n+1);
      ArrayResize(mae_r, n+1);             ArrayResize(mfe_r, n+1);
      ArrayResize(reach, (n+1)*GZ_REACH_LEVEL_COUNT);
      ArrayResize(time_to_mae, n+1);       ArrayResize(time_to_mfe, n+1);

      trade_id[n]=id; entry_time[n]=et; entry_price[n]=ep; direction[n]=dir; exit_time[n]=xt; exit_reason[n]=reason;
      realized_r[n]=r; initial_risk[n]=risk; be_triggered[n]=be_trig; intrabar_conflict[n]=conflict;
      be_on_entry_bar[n]=be_entry_bar; be_arm_retrace[n]=retrace; mae_r[n]=mae; mfe_r[n]=mfe;
      time_to_mae[n]=t_mae; time_to_mfe[n]=t_mfe;
      for(int l=0;l<GZ_REACH_LEVEL_COUNT;l++)
         reach[n*GZ_REACH_LEVEL_COUNT+l] = (risk>0.0 && mfe>=GZ_REACH_LEVELS[l]);
      count = n+1;
     }

   //--- Snapshot every CLOSED exit (all of them, after OnDataEnd()) joined
   //--- with its journal record by trade_id. Read-only on both engines.
   void              Capture(CGZExitEngine &ex, CGZJournalEngine &jr)
     {
      Clear();
      int n  = ex.ExitCount();
      int jn = jr.JournalCount();
      for(int i=0;i<n;i++)
        {
         GZ_TradeExit e = ex.GetExit(i);
         if(e.is_open)
            continue;
         double mae = 0.0, mfe = 0.0;
         datetime t_mae = 0, t_mfe = 0;
         int jidx = -1;
         if(i<jn && jr.GetJournal(i).trade_id==e.trade_id)
            jidx = i;
         else
           {
            for(int k=0;k<jn;k++)
               if(jr.GetJournal(k).trade_id==e.trade_id) { jidx = k; break; }
           }
         if(jidx>=0)
           {
            GZ_TradeJournal j = jr.GetJournal(jidx);
            mae = j.mae_r;
            mfe = j.mfe_r;
            t_mae = j.time_to_mae;
            t_mfe = j.time_to_mfe;
           }
         AddTrade(e.trade_id, e.entry_time, e.entry_price, (int)e.direction, e.exit_time, (int)e.exit_reason,
                  e.realized_r, e.initial_risk, e.be_triggered, e.intrabar_conflict,
                  e.be_armed_on_entry_bar, e.be_arm_bar_retrace, mae, mfe, t_mae, t_mfe);
        }
     }

   //--- Aggregates ---------------------------------------------------------
   double            NetR() const
     {
      double s=0.0;
      for(int i=0;i<count;i++) s += realized_r[i];
      return s;
     }

   int               CountReason(int reason) const
     {
      int c=0;
      for(int i=0;i<count;i++) if(exit_reason[i]==reason) c++;
      return c;
     }

   int               ReachCount(int lvl) const
     {
      if(lvl<0 || lvl>=GZ_REACH_LEVEL_COUNT) return 0;
      int c=0;
      for(int i=0;i<count;i++) if(reach[i*GZ_REACH_LEVEL_COUNT+lvl]) c++;
      return c;
     }

   double            MaxMae() const { double m=0.0; for(int i=0;i<count;i++) if(mae_r[i]>m) m=mae_r[i]; return m; }
   double            MaxMfe() const { double m=0.0; for(int i=0;i<count;i++) if(mfe_r[i]>m) m=mfe_r[i]; return m; }

   //--- Mean length of every maximal run of consecutive LOSERS (R<0) in the
   //--- same trade order Phase 8 uses for MaxLosingStreak. A flat (R==0) or
   //--- winning trade ends a run. 0.0 when there is no losing run at all.
   double            AvgLosingStreak() const
     {
      int runs=0, total=0, cur=0;
      for(int i=0;i<count;i++)
        {
         if(realized_r[i]<0.0) cur++;
         else
           {
            if(cur>0) { runs++; total+=cur; cur=0; }
           }
        }
      if(cur>0) { runs++; total+=cur; }
      return (runs>0) ? (double)total/runs : 0.0;
     }

   int               CountBeTriggered() const { int c=0; for(int i=0;i<count;i++) if(be_triggered[i]) c++; return c; }
   int               CountConflict() const    { int c=0; for(int i=0;i<count;i++) if(intrabar_conflict[i]) c++; return c; }
   int               CountBeOnEntryBar() const{ int c=0; for(int i=0;i<count;i++) if(be_triggered[i] && be_on_entry_bar[i]) c++; return c; }
   int               CountRetrace() const     { int c=0; for(int i=0;i<count;i++) if(be_triggered[i] && be_arm_retrace[i]) c++; return c; }
   int               CountRetraceNonEntryBar() const
     { int c=0; for(int i=0;i<count;i++) if(be_triggered[i] && be_arm_retrace[i] && !be_on_entry_bar[i]) c++; return c; }

   //--- Journal accounting diagnostics. The Journal Engine updates MFE/MAE/Reach with the
   //--- FULL high/low of every candle it is fed while the trade is still journal-open, and
   //--- it is fed the exit candle BEFORE the closure is synchronized (see GZ_TradeSimulator).
   //--- These counters make that rule observable (they never change any number).
   int               CountMfeSetOnExitBar() const
     { int c=0; for(int i=0;i<count;i++) if(mfe_r[i]>0.0 && time_to_mfe[i]==exit_time[i]) c++; return c; }
   int               CountMaeSetOnExitBar() const
     { int c=0; for(int i=0;i<count;i++) if(mae_r[i]>0.0 && time_to_mae[i]==exit_time[i]) c++; return c; }
   int               CountTpExitMfeOvershoot(double tp_r) const
     { int c=0; for(int i=0;i<count;i++) if(exit_reason[i]==(int)GZ_EXIT_TP_HIT && mfe_r[i]>tp_r+1.0e-9) c++; return c; }
   int               CountSlExitMaeBeyondStop() const
     { int c=0; for(int i=0;i<count;i++) if(exit_reason[i]==(int)GZ_EXIT_SL_HIT && mae_r[i]>1.0+1.0e-9) c++; return c; }

   //--- Trades that CLOSED on the very M1 candle they entered on
   //--- (exit_time==entry_time); reason<0 counts every reason.
   int               CountEntryBarExits(int reason) const
     {
      int c=0;
      for(int i=0;i<count;i++)
         if(exit_time[i]==entry_time[i] && (reason<0 || exit_reason[i]==reason)) c++;
      return c;
     }
  };

#endif // __GZ_RUN_DETAIL_MQH__
