//+------------------------------------------------------------------+
//| GZ_RewardBeEngine.mqh                                             |
//| GoldenZone STR - Phase 15.5 - Reward / TP x Risk-Free (BE)        |
//| Research Matrix Engine                                             |
//|                                                                    |
//| RESEARCH + MEASUREMENT ONLY. Drives the EXISTING Phase 9           |
//| CGZExperimentRunner once per (TP, BE trigger) pair over the        |
//| DEVELOPMENT data it is handed - it never loads data itself, so it |
//| structurally cannot touch the Final OOS. Only exit_config.         |
//| tp_r_multiple and exit_config.be_trigger_r vary between runs;      |
//| every other field of the base configuration is held identical.    |
//| It adds NO simulation logic, changes NO baseline behavior, selects |
//| NO configuration and ranks NOTHING.                                |
//|                                                                    |
//| PAIRWISE BE ANALYSIS (required): for every TP, the BE-OFF run is   |
//| compared with each BE-ON run trade by trade, joined by the stable  |
//| trade_id (entry never depends on exit, so ids/entries are          |
//| identical across runs - this is verified, not assumed).            |
//| See GZ_RewardBeTypes.mqh for categories A-E.                        |
//+------------------------------------------------------------------+
#ifndef __GZ_REWARDBE_ENGINE_MQH__
#define __GZ_REWARDBE_ENGINE_MQH__

#include "GZ_RewardBeTypes.mqh"
#include "GZ_RunDetail.mqh"
#include "..\Experiment\GZ_ExperimentTypes.mqh"
#include "..\Experiment\GZ_ExperimentRunner.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

//--- Comparison inputs the caller supplies (all optional).
struct GZ_RewardBeBaselineRef
  {
   bool     main_available;   // true only if the main pipeline ran TP=2.0 / BE off / offset 0 (comparison is then valid)
   int      main_trades;
   int      main_winners;
   double   main_net_r;
   double   main_expectancy;

   bool     ext_available;    // Phase 15 Development baseline as REPORTED (rounded) - external reference check
   double   ext_win_rate;     // fraction (0.507 = 50.7%)
   double   ext_expectancy;
   double   ext_pf;
   double   ext_net_r;
   int      ext_trades;       // 412 (Phase 15 Development baseline)
   double   ext_max_dd_r;     // 6.0

   void Clear()
     {
      main_available=false; main_trades=0; main_winners=0; main_net_r=0.0; main_expectancy=0.0;
      ext_available=false; ext_win_rate=0.0; ext_expectancy=0.0; ext_pf=0.0; ext_net_r=0.0; ext_trades=0; ext_max_dd_r=0.0;
     }
  };

class CGZRewardBeEngine
  {
private:
   CGZLogger            *m_logger;
   CGZLogger             m_quiet;            // errors-only logger handed to the runner: ~130 full runs would otherwise flood the journal with per-trade lines
   CGZExperimentRunner  *m_runner;
   GZ_RewardBeRow        m_rows[];
   GZ_TestResult         m_val[];
   ENUM_GZ_RB_STATUS     m_status;
   int                   m_runs;             // experiments executed (incl. determinism repeats)
   int                   m_matrix_runs;      // experiments that became matrix rows
   int                   m_detail_mismatch;  // runs whose detail snapshot disagreed with Phase 8 metrics
   int                   m_entry_mismatch_total;
   int                   m_unmatched_total;
   datetime              m_dev_first, m_dev_last;
   int                   m_m1_bars, m_m5_bars;
   string                m_dataset_id;

   //--- text helpers -------------------------------------------------------
   string PadR(string s, int w) const { while(StringLen(s)<w) s += " "; return s; }
   string PadL(string s, int w) const { while(StringLen(s)<w) s = " " + s; return s; }
   string Dbl(double v, int d) const    { return DoubleToString(v, d); }
   string Pct(double v) const         { return DoubleToString(v*100.0, 1) + "%"; }
   string Pf(const GZ_RewardBeRow &r) const { return r.pf_undefined ? "inf" : DoubleToString(r.profit_factor, 3); }
   string YN(bool b) const            { return b ? "true" : "false"; }

   void AddVal(string id, bool passed, bool blocked, string detail)
     {
      int n = ArraySize(m_val);
      ArrayResize(m_val, n+1);
      m_val[n].id = id; m_val[n].passed = passed; m_val[n].blocked = blocked; m_val[n].detail = detail;
      if(m_logger!=NULL)
         m_logger.Info("RewardBe", StringFormat("%s: %s - %s", id, blocked?"BLOCKED":(passed?"PASS":"FAIL"), detail));
     }

   int AppendRow(const GZ_RewardBeRow &r)
     {
      int n = ArraySize(m_rows);
      ArrayResize(m_rows, n+1);
      m_rows[n] = r;
      return n;
     }

   //--- One experiment: ONLY tp and be trigger are set here.
   void RunOne(const GZ_ExperimentConfig &base, double tp, double trig, const MqlRates &m1[], const MqlRates &m5[],
               ENUM_GZ_VALIDATION_STATUS s1, ENUM_GZ_VALIDATION_STATUS s5,
               GZ_ExperimentResult &res, CGZRunDetail *detail)
     {
      GZ_ExperimentConfig cfg = base;
      cfg.exit_config.tp_r_multiple    = tp;
      cfg.exit_config.be_trigger_r     = trig;
      cfg.exit_config.be_level_mode    = GZ_BE_LEVEL_ENTRY;   // approved decision: BE level = Entry, offset 0R only
      cfg.exit_config.be_level_offset_r= 0.0;
      m_runner.RunSingleDetailed(cfg, m1, m5, m_dataset_id, s1, s5, res, detail);
      m_runs++;
     }

   void FillRow(const GZ_ExperimentResult &res, CGZRunDetail *d, ENUM_GZ_RB_KIND kind, double tp, double trig, GZ_RewardBeRow &row)
     {
      row.Clear();
      row.run_index     = m_runs;
      row.experiment_id = res.id;
      row.kind          = kind;
      row.tp_r          = tp;
      row.be_trigger_r  = trig;
      row.be_offset_r   = 0.0;

      row.trades   = res.metrics.trade.trade_count;
      row.winners  = res.metrics.trade.winners;
      row.losers   = res.metrics.trade.losers;
      row.flat     = row.trades - row.winners - row.losers;
      row.win_rate = res.metrics.trade.win_rate;
      row.loss_rate= (row.trades>0) ? (double)row.losers/row.trades : 0.0;
      row.expectancy    = res.metrics.trade.expectancy;
      row.profit_factor = res.metrics.trade.profit_factor;
      row.pf_undefined  = res.metrics.trade.profit_factor_undefined;
      row.net_r         = res.metrics.trade.net_r;
      row.avg_win_r     = res.metrics.trade.avg_win_r;
      row.avg_loss_r    = res.metrics.trade.avg_loss_r;
      row.max_dd_r      = res.metrics.risk.max_drawdown_r;
      row.max_lose_streak = res.metrics.risk.max_losing_streak;
      row.avg_mae_r     = res.metrics.behavior.avg_mae_r;
      row.avg_mfe_r     = res.metrics.behavior.avg_mfe_r;

      row.avg_lose_streak = d.AvgLosingStreak();
      row.max_mae_r       = d.MaxMae();
      row.max_mfe_r       = d.MaxMfe();
      for(int e=1;e<GZ_RB_EXIT_SLOTS;e++)
         row.exit_count[e] = d.CountReason(e);
      row.be_rate = (row.trades>0) ? (double)row.exit_count[GZ_EXIT_BREAK_EVEN]/row.trades : 0.0;
      for(int l=0;l<GZ_REACH_LEVEL_COUNT;l++)
         row.reach_count[l] = d.ReachCount(l);

      row.be_armed                  = d.CountBeTriggered();
      row.intrabar_conflicts        = d.CountConflict();
      row.eb_exit_total             = d.CountEntryBarExits(-1);
      row.eb_exit_tp                = d.CountEntryBarExits(GZ_EXIT_TP_HIT);
      row.eb_exit_sl                = d.CountEntryBarExits(GZ_EXIT_SL_HIT);
      row.be_armed_on_entry_bar     = d.CountBeOnEntryBar();
      row.be_arm_retrace            = d.CountRetrace();
      row.be_arm_retrace_non_entry  = d.CountRetraceNonEntryBar();
      row.mfe_set_on_exit_bar       = d.CountMfeSetOnExitBar();
      row.mae_set_on_exit_bar       = d.CountMaeSetOnExitBar();
      row.tp_exit_mfe_overshoot     = d.CountTpExitMfeOvershoot(tp);
      row.sl_exit_mae_beyond_stop   = d.CountSlExitMaeBeyondStop();

      //--- snapshot vs Phase 8 metrics consistency (V11 input)
      bool consistent = (d.count==row.trades) && (MathAbs(d.NetR()-row.net_r)<0.000001);
      if(!consistent)
         m_detail_mismatch++;
     }

   //--- BE-OFF vs BE-ON, joined by trade_id.
   void ComparePairs(CGZRunDetail *off, CGZRunDetail *on, GZ_PairStats &ps)
     {
      ps.Clear();
      ps.valid = true;
      for(int i=0;i<on.count;i++)
        {
         int j = -1;
         if(i<off.count && off.trade_id[i]==on.trade_id[i])
            j = i;
         else
           {
            for(int k=0;k<off.count;k++)
               if(off.trade_id[k]==on.trade_id[i]) { j = k; break; }
           }
         if(j<0)
           {
            ps.unmatched_on++;
            continue;
           }
         ps.matched++;

         if(off.entry_time[j]!=on.entry_time[i] || off.direction[j]!=on.direction[i] ||
            MathAbs(off.entry_price[j]-on.entry_price[i])>GZ_RB_EPS)
            ps.entry_mismatch++;

         int    offr = off.exit_reason[j];
         int    onr  = on.exit_reason[i];
         double dr   = on.realized_r[i] - off.realized_r[j];
         bool   same = (offr==onr && MathAbs(dr)<GZ_RB_EPS);

         if(offr==GZ_EXIT_TP_HIT) ps.off_tp_total++;
         if(offr==GZ_EXIT_SL_HIT) ps.off_sl_total++;
         if(same) ps.no_change++;
         if(on.be_triggered[i])
           {
            ps.be_armed_total++;
            if(same) ps.be_armed_no_change++;
           }
         ps.dr_total += dr;

         if(offr==GZ_EXIT_SL_HIT && onr==GZ_EXIT_BREAK_EVEN)      { ps.cat_a++; ps.dr_a += dr; }
         else if(offr==GZ_EXIT_TP_HIT && onr==GZ_EXIT_BREAK_EVEN) { ps.cat_b++; ps.dr_b += dr; }
         else if(offr==GZ_EXIT_TP_HIT && onr==GZ_EXIT_TP_HIT)     { ps.cat_c++; ps.dr_c += dr; }
         else if(offr==GZ_EXIT_SL_HIT && onr==GZ_EXIT_SL_HIT)     { ps.cat_d++; ps.dr_d += dr; }
         else
           {
            ps.cat_e++; ps.dr_e += dr;
            if(onr==GZ_EXIT_BREAK_EVEN && offr!=GZ_EXIT_TP_HIT && offr!=GZ_EXIT_SL_HIT) ps.e_be_from_other++;
            else if(offr==onr)                                                            ps.e_same_other++;
            else                                                                          ps.e_anomaly++;
           }
        }
      ps.unmatched_off = off.count - ps.matched;
      if(ps.unmatched_off<0) ps.unmatched_off = 0;
     }

   bool RowsIdentical(const GZ_RewardBeRow &a, const GZ_RewardBeRow &b) const
     {
      if(a.trades!=b.trades || a.winners!=b.winners || a.losers!=b.losers) return false;
      if(MathAbs(a.net_r-b.net_r)>GZ_RB_EPS) return false;
      if(MathAbs(a.max_dd_r-b.max_dd_r)>GZ_RB_EPS) return false;
      if(a.max_lose_streak!=b.max_lose_streak) return false;
      for(int e=0;e<GZ_RB_EXIT_SLOTS;e++)
         if(a.exit_count[e]!=b.exit_count[e]) return false;
      for(int l=0;l<GZ_REACH_LEVEL_COUNT;l++)
         if(a.reach_count[l]!=b.reach_count[l]) return false;
      return true;
     }

   int FindRow(ENUM_GZ_RB_KIND kind, double tp, double trig) const
     {
      int n = ArraySize(m_rows);
      for(int i=0;i<n;i++)
         if(m_rows[i].kind==kind && MathAbs(m_rows[i].tp_r-tp)<GZ_RB_EPS && MathAbs(m_rows[i].be_trigger_r-trig)<GZ_RB_EPS)
            return i;
      return -1;
     }

   int FindOffRow(double tp) const { return FindRow(GZ_RB_OFF, tp, 0.0); }

public:
                     CGZRewardBeEngine(CGZLogger *logger=NULL)
     {
      m_logger = logger; m_runner = NULL; m_status = GZ_RB_STATUS_NO_DATA;
      m_quiet.SetMinLevel(GZ_SEV_ERROR);
      m_runs = 0; m_matrix_runs = 0; m_detail_mismatch = 0; m_entry_mismatch_total = 0; m_unmatched_total = 0;
      m_dev_first = 0; m_dev_last = 0; m_m1_bars = 0; m_m5_bars = 0; m_dataset_id = "";
     }

   ENUM_GZ_RB_STATUS Status() const       { return m_status; }
   int               RowCount() const     { return ArraySize(m_rows); }
   GZ_RewardBeRow    GetRow(int i) const  { return m_rows[i]; }
   int               ValidationCount() const { return ArraySize(m_val); }
   GZ_TestResult     GetValidation(int i) const { return m_val[i]; }
   int               ExperimentCount() const { return m_runs; }
   int               MatrixRunCount() const  { return m_matrix_runs; }

   int               CountKind(ENUM_GZ_RB_KIND k) const
     {
      int c=0, n=ArraySize(m_rows);
      for(int i=0;i<n;i++) if(m_rows[i].kind==k) c++;
      return c;
     }

   int               ValidationFailCount() const
     {
      int c=0, n=ArraySize(m_val);
      for(int i=0;i<n;i++) if(!m_val[i].passed && !m_val[i].blocked) c++;
      return c;
     }

   int               ValidationBlockedCount() const
     {
      int c=0, n=ArraySize(m_val);
      for(int i=0;i<n;i++) if(m_val[i].blocked) c++;
      return c;
     }

   //--- Number of MAIN-MATRIX configurations (pure; used by tests and the report header).
   //--- off_runs = one BE-off run per TP; active_runs = the reduced BE trigger list of each TP (GZRewardBeTriggersForTp).
   static void       CountGrid(int &off_runs, int &active_runs)
     {
      double tps[], trigs[];
      GZRewardBeTpGrid(tps);
      off_runs = ArraySize(tps); active_runs = 0;
      for(int t=0;t<ArraySize(tps);t++)
         active_runs += GZRewardBeTriggersForTp(tps[t], trigs);
     }

   //--- Run the whole Phase 15.5 matrix over the supplied DEVELOPMENT data.
   //--- `dev_range_end` must not exceed `oos_start` (the protected Final OOS
   //--- boundary) or nothing runs. `phase15_skipped` records whether the caller
   //--- avoided loading the Final OOS in this run (V08).
   ENUM_GZ_RB_STATUS Run(const GZ_ExperimentConfig &base_cfg, const MqlRates &m1[], const MqlRates &m5[],
                         string dataset_id, ENUM_GZ_VALIDATION_STATUS m1_status, ENUM_GZ_VALIDATION_STATUS m5_status,
                         datetime dev_range_start, datetime dev_range_end,
                         datetime oos_start, bool phase15_skipped, const GZ_RewardBeBaselineRef &bref)
     {
      ArrayResize(m_rows, 0);
      ArrayResize(m_val, 0);
      m_runs = 0; m_matrix_runs = 0; m_detail_mismatch = 0; m_entry_mismatch_total = 0; m_unmatched_total = 0;
      m_dataset_id = dataset_id;

      int n1 = ArraySize(m1);
      int n5 = ArraySize(m5);
      m_m1_bars = n1; m_m5_bars = n5;
      if(n5==0)
        {
         m_status = GZ_RB_STATUS_NO_DATA;
         if(m_logger!=NULL) m_logger.Error("RewardBe", "Phase 15.5: no M5 data supplied - nothing run.");
         return m_status;
        }
      m_dev_first = m5[0].time;
      m_dev_last  = m5[n5-1].time;

      if(dev_range_end > oos_start)
        {
         m_status = GZ_RB_STATUS_REJECTED_OOS_OVERLAP;
         if(m_logger!=NULL)
            m_logger.Error("RewardBe", StringFormat("Phase 15.5 REJECTED: development range end %s is after the protected Final OOS start %s - nothing run.",
                           TimeToString(dev_range_end), TimeToString(oos_start)));
         return m_status;
        }

      m_status = GZ_RB_STATUS_OK;
      m_runner = new CGZExperimentRunner(GetPointer(m_quiet));

      double tps[], trigs[];
      GZRewardBeTpGrid(tps);

      for(int t=0; t<ArraySize(tps); t++)
        {
         double tp = tps[t];

         GZ_ExperimentResult r_off;
         CGZRunDetail *d_off = new CGZRunDetail();
         RunOne(base_cfg, tp, 0.0, m1, m5, m1_status, m5_status, r_off, d_off);
         GZ_RewardBeRow row_off;
         FillRow(r_off, d_off, GZ_RB_OFF, tp, 0.0, row_off);
         int off_idx = AppendRow(row_off);
         m_matrix_runs++;
         if(m_logger!=NULL)
            m_logger.Info("RewardBe", StringFormat("run %d: TP=%.2fR BE=OFF trades=%d net_r=%.3f", m_runs, tp, row_off.trades, row_off.net_r));

         // Reduced BE trigger list of this TP (all strictly below TP; no 0.25R/0.75R). BE >= TP is never executed.
         int n_trig = GZRewardBeTriggersForTp(tp, trigs);
         for(int g=0; g<n_trig; g++)
           {
            double trig = trigs[g];

            GZ_ExperimentResult r_on;
            CGZRunDetail *d_on = new CGZRunDetail();
            RunOne(base_cfg, tp, trig, m1, m5, m1_status, m5_status, r_on, d_on);
            GZ_RewardBeRow row_on;
            FillRow(r_on, d_on, GZ_RB_BE_ACTIVE, tp, trig, row_on);
            ComparePairs(d_off, d_on, row_on.pair);
            m_entry_mismatch_total += row_on.pair.entry_mismatch;
            m_unmatched_total      += (row_on.pair.unmatched_on + row_on.pair.unmatched_off);
            if(row_on.trades!=row_off.trades) m_unmatched_total++;
            AppendRow(row_on);
            m_matrix_runs++;
            if(m_logger!=NULL)
               m_logger.Info("RewardBe", StringFormat("run %d: TP=%.2fR BE=%.2fR [%s] trades=%d net_r=%.3f A=%d B=%d",
                             m_runs, tp, trig, GZRewardBeKindToString(row_on.kind), row_on.trades, row_on.net_r,
                             row_on.pair.cat_a, row_on.pair.cat_b));
            delete d_on;
           }
         delete d_off;
        }

      //--- REFERENCE_ONLY / HIGH_TP_REACH_REFERENCE run (executed exactly ONCE): TP=1000R, BE off. Not a strategy TP.
      GZ_ExperimentResult r_ref;
      CGZRunDetail *d_ref = new CGZRunDetail();
      RunOne(base_cfg, GZ_RB_REFERENCE_TP_R, 0.0, m1, m5, m1_status, m5_status, r_ref, d_ref);
      GZ_RewardBeRow row_ref;
      FillRow(r_ref, d_ref, GZ_RB_REFERENCE_ONLY, GZ_RB_REFERENCE_TP_R, 0.0, row_ref);
      AppendRow(row_ref);
      m_matrix_runs++;
      delete d_ref;

      //--- Determinism repeats (V09): rerun two already-recorded configurations.
      bool det_off_ok = false, det_on_ok = false, det_done = false;
      int  i_off2 = FindOffRow(2.0);
      int  i_on2  = FindRow(GZ_RB_BE_ACTIVE, 2.0, 1.0);
      if(i_off2>=0 && i_on2>=0)
        {
         GZ_ExperimentResult rr1, rr2;
         CGZRunDetail dd1, dd2;
         RunOne(base_cfg, 2.0, 0.0, m1, m5, m1_status, m5_status, rr1, GetPointer(dd1));
         GZ_RewardBeRow rw1; FillRow(rr1, GetPointer(dd1), GZ_RB_OFF, 2.0, 0.0, rw1);
         RunOne(base_cfg, 2.0, 1.0, m1, m5, m1_status, m5_status, rr2, GetPointer(dd2));
         GZ_RewardBeRow rw2; FillRow(rr2, GetPointer(dd2), GZ_RB_BE_ACTIVE, 2.0, 1.0, rw2);
         det_off_ok = RowsIdentical(m_rows[i_off2], rw1);
         det_on_ok  = RowsIdentical(m_rows[i_on2], rw2);
         det_done = true;
        }

      delete m_runner;
      m_runner = NULL;

      EvaluateValidations(dev_range_start, dev_range_end, oos_start, phase15_skipped,
                          det_done, det_off_ok, det_on_ok, bref, m1, m5);
      return m_status;
     }

   //--- Section G ------------------------------------------------------------
   void EvaluateValidations(datetime dev_start, datetime dev_end,
                            datetime oos_start, bool phase15_skipped, bool det_done, bool det_off_ok, bool det_on_ok,
                            const GZ_RewardBeBaselineRef &bref, const MqlRates &m1[], const MqlRates &m5[])
     {
      int n = ArraySize(m_rows);

      // V01 - the TP sweep genuinely changes behavior (BE-off rows only)
      {
       int distinct = 0;
       for(int i=0;i<n;i++)
        {
         if(m_rows[i].kind!=GZ_RB_OFF) continue;
         bool seen = false;
         for(int k=0;k<i;k++)
            if(m_rows[k].kind==GZ_RB_OFF && MathAbs(m_rows[k].net_r-m_rows[i].net_r)<GZ_RB_EPS &&
               m_rows[k].exit_count[GZ_EXIT_TP_HIT]==m_rows[i].exit_count[GZ_EXIT_TP_HIT]) { seen = true; break; }
         if(!seen) distinct++;
        }
       int i_lo = FindOffRow(0.5), i_hi = FindOffRow(5.0);
       bool tp_differs = (i_lo>=0 && i_hi>=0 && m_rows[i_lo].exit_count[GZ_EXIT_TP_HIT]!=m_rows[i_hi].exit_count[GZ_EXIT_TP_HIT]);
       AddVal("V01_TP_SWEEP_CHANGES_BEHAVIOR", (distinct>=2 && tp_differs), false,
              StringFormat("distinct BE-off (net_r,TP_HIT) signatures across %d TP levels = %d; TP_HIT(0.5R) %s TP_HIT(5.0R)",
                           CountKind(GZ_RB_OFF), distinct, tp_differs?"!=":"=="));
      }

      int i_base = FindOffRow(2.0);

      // V02 - TP=2R + BE off reproduces the main pipeline (same inputs, same data) EXACTLY
      if(!bref.main_available || i_base<0)
         AddVal("V02_BASELINE_EQUALS_MAIN_PIPELINE", false, true,
                "main pipeline was not run with TP=2.0/BE off/offset 0 in this attachment (or no TP=2.0 row) - comparison not applicable");
      else
        {
         bool ok = (m_rows[i_base].trades==bref.main_trades) && (m_rows[i_base].winners==bref.main_winners) &&
                   (MathAbs(m_rows[i_base].net_r-bref.main_net_r)<0.000001) &&
                   (MathAbs(m_rows[i_base].expectancy-bref.main_expectancy)<0.000001);
         AddVal("V02_BASELINE_EQUALS_MAIN_PIPELINE", ok, false,
                StringFormat("matrix TP=2.0/BE off: trades=%d winners=%d net_r=%.6f exp=%.6f | main pipeline: trades=%d winners=%d net_r=%.6f exp=%.6f",
                             m_rows[i_base].trades, m_rows[i_base].winners, m_rows[i_base].net_r, m_rows[i_base].expectancy,
                             bref.main_trades, bref.main_winners, bref.main_net_r, bref.main_expectancy));
        }

      // V03 - TP=2R + BE off vs the REPORTED Phase 15 Development baseline (rounded figures -> tolerances)
      if(!bref.ext_available || i_base<0)
         AddVal("V03_BASELINE_EQUALS_PHASE15_DEV_REPORT", false, true, "no external Phase 15 Development reference supplied");
      else
        {
         double dw = MathAbs(m_rows[i_base].win_rate-bref.ext_win_rate);
         double de = MathAbs(m_rows[i_base].expectancy-bref.ext_expectancy);
         double dp = MathAbs(m_rows[i_base].profit_factor-bref.ext_pf);
         double dn = MathAbs(m_rows[i_base].net_r-bref.ext_net_r);
         double dd_diff = MathAbs(m_rows[i_base].max_dd_r-bref.ext_max_dd_r);
         bool trades_ok = (bref.ext_trades<=0) || (m_rows[i_base].trades==bref.ext_trades);
         bool ok = (dw<=0.0006) && (de<=0.0002) && (dp<=0.0015) && (dn<=0.6) && trades_ok && (dd_diff<=0.05);
         AddVal("V03_BASELINE_EQUALS_PHASE15_DEV_REPORT", ok, false,
                StringFormat("matrix: trades=%d win=%.4f exp=%.4f pf=%.3f net_r=%.3f max_dd=%.2f | Phase 15 report: trades=%d win=%.4f exp=%.4f pf=%.3f net_r=%.1f max_dd=%.2f | |diff| win=%.5f exp=%.5f pf=%.4f net_r=%.3f max_dd=%.3f (tolerances: rounding of the printed figures; trade count exact)",
                             m_rows[i_base].trades, m_rows[i_base].win_rate, m_rows[i_base].expectancy, m_rows[i_base].profit_factor, m_rows[i_base].net_r, m_rows[i_base].max_dd_r,
                             bref.ext_trades, bref.ext_win_rate, bref.ext_expectancy, bref.ext_pf, bref.ext_net_r, bref.ext_max_dd_r, dw, de, dp, dn, dd_diff));
        }

      // V04 - main-matrix grid rule (reduced grid): TP <= 4.5R (no 5.0R); BE OFF once per TP; the BE-active rows of every TP are EXACTLY
      //       GZRewardBeTriggersForTp(TP) (no 0.25R/0.75R; TP>=2R whole-R only; all < TP); no trigger >= TP; exactly one reference row.
      {
       double tps[], trigs[];
       GZRewardBeTpGrid(tps);
       bool ok = true;
       string why = "";
       int off_rows = 0, act_rows = 0, ref_rows = 0, eq_rows = 0;
       for(int i=0;i<n;i++)
         {
          if(m_rows[i].kind==GZ_RB_OFF) off_rows++;
          else if(m_rows[i].kind==GZ_RB_BE_ACTIVE) act_rows++;
          else if(m_rows[i].kind==GZ_RB_REFERENCE_ONLY) ref_rows++;
          else eq_rows++;
          if(m_rows[i].kind==GZ_RB_REFERENCE_ONLY) continue;
          if(m_rows[i].tp_r>GZ_RB_MAX_TP_R+GZ_RB_EPS) { ok = false; why += "TP>4.5 "; }
          if(m_rows[i].kind==GZ_RB_BE_ACTIVE)
            {
             double g = m_rows[i].be_trigger_r;
             if(!(g>0.0 && g<m_rows[i].tp_r-GZ_RB_EPS)) { ok = false; why += "trigger_not_below_TP "; }
             if(MathAbs(g-0.25)<GZ_RB_EPS || MathAbs(g-0.75)<GZ_RB_EPS) { ok = false; why += "trigger_0.25_or_0.75_present "; }
             if(m_rows[i].tp_r>=GZ_RB_WHOLE_R_FROM_TP-GZ_RB_EPS && MathAbs(g-MathRound(g))>GZ_RB_EPS) { ok = false; why += "non_whole_R_trigger_at_TP>=2 "; }
            }
         }
       for(int t=0;t<ArraySize(tps);t++)
         {
          if(FindOffRow(tps[t])<0) { ok = false; why += StringFormat("missing_OFF@%.1f ", tps[t]); }
          int nt = GZRewardBeTriggersForTp(tps[t], trigs);
          for(int k=0;k<nt;k++)
             if(FindRow(GZ_RB_BE_ACTIVE, tps[t], trigs[k])<0) { ok = false; why += StringFormat("missing_BE%.2f@%.1f ", trigs[k], tps[t]); }
         }
       int exp_off, exp_act;
       CountGrid(exp_off, exp_act);
       if(off_rows!=exp_off || act_rows!=exp_act || ref_rows!=1 || eq_rows!=0) { ok = false; why += "row_counts "; }
       if(FindOffRow(5.0)>=0) { ok = false; why += "TP5_present "; }
       AddVal("V04_MAIN_MATRIX_GRID_RULE", ok, false,
              StringFormat("TP grid 0.5..4.5R (no 5.0R); BE-off rows=%d (expect %d), BE-active rows=%d (expect %d; triggers exactly per the reduced rule, none >= TP, no 0.25R/0.75R), reference rows=%d (expect 1), BE>=TP rows executed=%d (expect 0) %s",
                           off_rows, exp_off, act_rows, exp_act, ref_rows, eq_rows, why));
      }

      // V05 - BE settings genuinely change exit behavior where expected (active rows)
      {
       int active = 0, with_be = 0, changed = 0;
       for(int i=0;i<n;i++)
         {
          if(m_rows[i].kind!=GZ_RB_BE_ACTIVE) continue;
          active++;
          if(m_rows[i].exit_count[GZ_EXIT_BREAK_EVEN]>0) with_be++;
          int o = FindOffRow(m_rows[i].tp_r);
          if(o>=0 && MathAbs(m_rows[o].net_r-m_rows[i].net_r)>GZ_RB_EPS) changed++;
         }
       AddVal("V05_BE_SETTINGS_CHANGE_EXITS", (active>0 && with_be>0 && changed>0), false,
              StringFormat("%d BE-active runs; %d produced BREAK_EVEN exits; %d differ from their BE-off net R", active, with_be, changed));
      }

      // V06 - entry logic untouched by TP/BE (ids, entry times/prices/directions, trade counts)
      AddVal("V06_ENTRY_LOGIC_UNCHANGED", (m_entry_mismatch_total==0 && m_unmatched_total==0), false,
             StringFormat("entry field mismatches=%d, unmatched/extra trades or trade-count differences=%d across all BE-on runs vs BE-off (0/0 required)",
                          m_entry_mismatch_total, m_unmatched_total));

      // V07 - dataset boundary
      {
       int n1 = ArraySize(m1), n5 = ArraySize(m5);
       datetime f5 = m5[0].time, l5 = m5[n5-1].time;
       bool ok = (f5>=dev_start) && (l5<=dev_end) && (dev_end<=oos_start);
       if(n1>0) ok = ok && (m1[0].time>=dev_start) && (m1[n1-1].time<=dev_end);
       AddVal("V07_DATASET_BOUNDARY", ok, false,
              StringFormat("Development range [%s .. %s]; M5 bars=%d [%s .. %s]; M1 bars=%d; protected Final OOS starts %s (dev end <= OOS start required)",
                           TimeToString(dev_start), TimeToString(dev_end), n5, TimeToString(f5), TimeToString(l5), n1, TimeToString(oos_start)));
      }

      // V08 - Final OOS not loaded / not accessed
      AddVal("V08_FINAL_OOS_NOT_ACCESSED", phase15_skipped, false,
             StringFormat("Phase 15 (which loads the Final OOS) skipped in this run: %s; this engine only ever receives the Development arrays", YN(phase15_skipped)));

      // V09 - determinism
      if(!det_done)
         AddVal("V09_DETERMINISM_REPEAT", false, true, "no TP=2.0/BE=1.0 pair available to repeat");
      else
         AddVal("V09_DETERMINISM_REPEAT", (det_off_ok && det_on_ok), false,
                StringFormat("re-ran TP=2.0/BE off (identical=%s) and TP=2.0/BE 1.0R (identical=%s); compared trades, winners, net R, drawdown, streaks, exit counts, reach counts",
                             YN(det_off_ok), YN(det_on_ok)));

      // V10 - Reach is NOT Win Rate: in the TP=1000R reference run no trade can exit by TP, yet Reach counts are non-zero
      {
       int ir = FindRow(GZ_RB_REFERENCE_ONLY, GZ_RB_REFERENCE_TP_R, 0.0);
       if(ir<0)
          AddVal("V10_REACH_IS_NOT_WIN_RATE", false, true, "no reference row");
       else
         {
          int tp_hits = m_rows[ir].exit_count[GZ_EXIT_TP_HIT];
          int reach_any = m_rows[ir].reach_count[0];
          // NB: a TP of 1000R is not strictly unreachable (a trade with a tiny initial risk can exceed it), so TP_HIT may be > 0.
          // The property being proven is only that Reach (favorable excursion) is a different quantity from TP exits.
          bool ok = (reach_any>tp_hits);
          AddVal("V10_REACH_IS_NOT_WIN_RATE", ok, false,
                 StringFormat("reference run (TP=%.0fR, BE off): TP_HIT exits=%d while trades that reached >=0.5R=%d of %d (reach exceeds exits) - reach counts are kept separate from exit/win-rate figures and never converted into one another",
                              GZ_RB_REFERENCE_TP_R, tp_hits, reach_any, m_rows[ir].trades));
         }
      }

      // V11 - per-trade detail snapshot agrees with the Phase 8 metrics for every run
      AddVal("V11_DETAIL_MATCHES_METRICS", (m_detail_mismatch==0), false,
             StringFormat("runs whose per-trade snapshot disagreed with Phase 8 trade count / net R: %d (0 required)", m_detail_mismatch));

      // V12 - pairwise categories partition every matched trade
      {
       int bad = 0, checked = 0;
       for(int i=0;i<n;i++)
         {
          if(!m_rows[i].pair.valid) continue;
          checked++;
          GZ_PairStats p = m_rows[i].pair;
          if(p.cat_a+p.cat_b+p.cat_c+p.cat_d+p.cat_e != p.matched) bad++;
         }
       AddVal("V12_PAIR_CATEGORIES_PARTITION", (checked>0 && bad==0), (checked==0),
              StringFormat("%d pairwise comparisons checked; A+B+C+D+E==matched failed in %d", checked, bad));
      }
     }

   //=====================================================================
   //  REPORT / CSV
   //=====================================================================
   string BuildReport(const string context_text, const string unit_tests_text, int unit_pass, int unit_fail)
     {
      string s = "";
      int n = ArraySize(m_rows);
      int off_n, act_n;
      CountGrid(off_n, act_n);

      s += "===================================================\n";
      s += "GoldenZone STR - Phase 15.5 - Reward / TP x Risk-Free (BE) Research Matrix\n";
      s += "RESEARCH / MEASUREMENT ONLY. Historical Development data. No configuration is chosen, ranked or frozen. No parameter is called best/optimal/final.\n";
      s += "===================================================\n";
      s += context_text;
      s += StringFormat("Dataset ID: %s | M1 bars=%d M5 bars=%d | first M5 bar=%s last M5 bar=%s\n", m_dataset_id, m_m1_bars, m_m5_bars,
                        TimeToString(m_dev_first), TimeToString(m_dev_last));
      s += "TP GRID: 0.5R, 1.0R, 1.5R, 2.0R, 2.5R, 3.0R, 3.5R, 4.0R, 4.5R  (5.0R is NOT part of the main matrix).\n";
      s += "BE GRID RULE: for every TP, BE OFF plus BE triggers strictly below TP; 0.25R and 0.75R are never used. TP<2R: TP1.0 -> 0.5R, TP1.5 -> 1.0R (TP 0.5R has BE OFF only).\n";
      s += "TP>=2R: whole-R triggers only (1R, 2R, 3R, 4R that are < TP): TP2.0:1 | 2.5:1,2 | 3.0:1,2 | 3.5:1,2,3 | 4.0:1,2,3 | 4.5:1,2,3,4. A BE trigger >= TP is never executed\n";
      s += "(such a run is BE_INACTIVE_EQUIVALENT / VALIDATION_ONLY: TP is evaluated before BE arming, so it would just repeat BE OFF). BE level = Entry, offset = 0R ONLY.\n";
      s += StringFormat("MAIN MATRIX EXPERIMENTS: %d = %d BE-off + %d BE-active.  REFERENCE EXPERIMENTS: 1 (TP=%.0fR, BE off; REFERENCE_ONLY / HIGH_TP_REACH_REFERENCE, run once).\n",
                        off_n + act_n, off_n, act_n, GZ_RB_REFERENCE_TP_R);
      s += StringFormat("Executed: %d experiments in total (matrix rows incl. reference=%d, plus 2 determinism repeats). Status=%s\n\n",
                        m_runs, m_matrix_runs, (m_status==GZ_RB_STATUS_OK)?"OK":((m_status==GZ_RB_STATUS_NO_DATA)?"NO_DATA":"REJECTED_OOS_OVERLAP"));

      s += "Definitions: WinRate = trades with realized R>0; LossRate = R<0; BE_Rate = BREAK_EVEN exits / trades (BE level = Entry -> R exactly 0).\n";
      s += "WinRate+LossRate+flat(R==0) = 100%. Flat and winning trades both END a losing streak. MaxDD/MaxLS/PF/expectancy come from the Phase 8 Metrics Engine\n";
      s += "(trade order = trade-entry order, exactly as Phase 8 uses it); AvgLS = mean length of losing-streak runs in that same order.\n";
      s += "R is GROSS: no spread/commission/slippage cost model exists in this project (spread is recorded, never charged). Identical for every run.\n\n";

      if(m_status!=GZ_RB_STATUS_OK)
        {
         s += "NO MATRIX PRODUCED (see status above).\n";
         return s;
        }

      //--- A ------------------------------------------------------------------
      s += "--- A. TP x BE exit-results matrix (BE_OFF and BE-active rows; BE >= TP is never executed) ---\n";
      s += PadL("TP",4)+PadL("BE",6)+PadL("N",5)+PadL("TP_HIT",7)+PadL("SL_HIT",7)+PadL("BE_EX",6)+PadL("SESS",5)+PadL("DATA",5)+PadL("OTH",4)
           +PadL("Win%",7)+PadL("Loss%",7)+PadL("BE%",6)+PadL("Exp",8)+PadL("PF",7)+PadL("NetR",8)+PadL("MaxDD",7)+PadL("MaxLS",6)+PadL("AvgLS",6)
           +PadL("AvgW",6)+PadL("AvgL",6)+"\n";
      for(int i=0;i<n;i++)
        {
         if(m_rows[i].kind!=GZ_RB_OFF && m_rows[i].kind!=GZ_RB_BE_ACTIVE) continue;
         GZ_RewardBeRow r = m_rows[i];
         s += PadL(Dbl(r.tp_r,1),4)+PadL(r.kind==GZ_RB_OFF?"OFF":Dbl(r.be_trigger_r,2),6)+PadL(IntegerToString(r.trades),5)
              +PadL(IntegerToString(r.exit_count[GZ_EXIT_TP_HIT]),7)+PadL(IntegerToString(r.exit_count[GZ_EXIT_SL_HIT]),7)
              +PadL(IntegerToString(r.exit_count[GZ_EXIT_BREAK_EVEN]),6)+PadL(IntegerToString(r.exit_count[GZ_EXIT_SESSION_EXIT]),5)
              +PadL(IntegerToString(r.exit_count[GZ_EXIT_DATA_END]),5)+PadL(IntegerToString(r.exit_count[GZ_EXIT_OTHER]),4)
              +PadL(Pct(r.win_rate),7)+PadL(Pct(r.loss_rate),7)+PadL(Pct(r.be_rate),6)+PadL(Dbl(r.expectancy,4),8)+PadL(Pf(r),7)
              +PadL(Dbl(r.net_r,1),8)+PadL(Dbl(r.max_dd_r,2),7)+PadL(IntegerToString(r.max_lose_streak),6)+PadL(Dbl(r.avg_lose_streak,2),6)
              +PadL(Dbl(r.avg_win_r,2),6)+PadL(Dbl(r.avg_loss_r,2),6)+"\n";
        }
      s += "\nA2. Path-risk figures per row (MAE/MFE are measured while the trade is OPEN in that run):\n";
      s += PadL("TP",4)+PadL("BE",6)+PadL("AvgMAE",8)+PadL("MaxMAE",8)+PadL("AvgMFE",8)+PadL("MaxMFE",9)+"\n";
      for(int i=0;i<n;i++)
        {
         if(m_rows[i].kind!=GZ_RB_OFF && m_rows[i].kind!=GZ_RB_BE_ACTIVE) continue;
         GZ_RewardBeRow r = m_rows[i];
         s += PadL(Dbl(r.tp_r,1),4)+PadL(r.kind==GZ_RB_OFF?"OFF":Dbl(r.be_trigger_r,2),6)+PadL(Dbl(r.avg_mae_r,3),8)+PadL(Dbl(r.max_mae_r,3),8)
              +PadL(Dbl(r.avg_mfe_r,3),8)+PadL(Dbl(r.max_mfe_r,3),9)+"\n";
        }
      s += "\n";

      //--- B ------------------------------------------------------------------
      s += "--- B. TP summary, BE disabled ---\n";
      s += PadL("TP",4)+PadL("Trades",7)+PadL("Win%",7)+PadL("Loss%",7)+PadL("BE%",5)+PadL("Exp",8)+PadL("PF",7)+PadL("NetR",8)+PadL("MaxDD",7)+PadL("MaxLS",6)+"\n";
      for(int i=0;i<n;i++)
        {
         if(m_rows[i].kind!=GZ_RB_OFF) continue;
         GZ_RewardBeRow r = m_rows[i];
         s += PadL(Dbl(r.tp_r,1),4)+PadL(IntegerToString(r.trades),7)+PadL(Pct(r.win_rate),7)+PadL(Pct(r.loss_rate),7)+PadL(Pct(r.be_rate),5)
              +PadL(Dbl(r.expectancy,4),8)+PadL(Pf(r),7)+PadL(Dbl(r.net_r,1),8)+PadL(Dbl(r.max_dd_r,2),7)+PadL(IntegerToString(r.max_lose_streak),6)+"\n";
        }
      s += "(Descriptive only. Rows are NOT ranked and no TP is chosen.)\n\n";

      //--- C ------------------------------------------------------------------
      s += "--- C. BE effect: pairwise transitions, BE OFF vs BE ON at the same TP, joined by Trade ID ---\n";
      s += "A = SL_HIT(off)->BREAK_EVEN(on)  [BE protected the trade from a full SL]\n";
      s += "B = TP_HIT(off)->BREAK_EVEN(on)  [BE exited a trade that, without BE, went on to hit TP]\n";
      s += "C = TP_HIT->TP_HIT  D = SL_HIT->SL_HIT  [no exit-state change]   E = any other transition (sub-counts: BE-from-other / same-other / anomaly)\n";
      s += PadL("TP",4)+PadL("BE",6)+PadL("Match",6)+PadL("A",5)+PadL("B",5)+PadL("C",5)+PadL("D",5)+PadL("E",4)+PadL("E:be/same/an",13)
           +PadL("NoChg",6)+PadL("Armed",6)+PadL("BEexit",7)+PadL("dR_A",8)+PadL("dR_B",8)+PadL("dNetR",8)+PadL("dExp",8)+PadL("dPF",8)+PadL("dWin%",8)+PadL("dMaxDD",8)+PadL("SLprot%",8)+PadL("TPlost%",8)+"\n";
      for(int i=0;i<n;i++)
        {
         if(m_rows[i].kind!=GZ_RB_BE_ACTIVE) continue;
         GZ_RewardBeRow r = m_rows[i];
         int o = FindOffRow(r.tp_r);
         double d_net = (o>=0) ? r.net_r-m_rows[o].net_r : 0.0;
         double d_exp = (o>=0) ? r.expectancy-m_rows[o].expectancy : 0.0;
         double d_dd  = (o>=0) ? r.max_dd_r-m_rows[o].max_dd_r : 0.0;
         double d_pf  = (o>=0) ? r.profit_factor-m_rows[o].profit_factor : 0.0;
         double d_win = (o>=0) ? (r.win_rate-m_rows[o].win_rate)*100.0 : 0.0;
         double prot  = (r.pair.off_sl_total>0) ? (double)r.pair.cat_a/r.pair.off_sl_total : 0.0;
         double lost  = (r.pair.off_tp_total>0) ? (double)r.pair.cat_b/r.pair.off_tp_total : 0.0;
         s += PadL(Dbl(r.tp_r,1),4)+PadL(Dbl(r.be_trigger_r,2),6)+PadL(IntegerToString(r.pair.matched),6)
              +PadL(IntegerToString(r.pair.cat_a),5)+PadL(IntegerToString(r.pair.cat_b),5)+PadL(IntegerToString(r.pair.cat_c),5)
              +PadL(IntegerToString(r.pair.cat_d),5)+PadL(IntegerToString(r.pair.cat_e),4)
              +PadL(StringFormat("%d/%d/%d", r.pair.e_be_from_other, r.pair.e_same_other, r.pair.e_anomaly),13)
              +PadL(IntegerToString(r.pair.no_change),6)+PadL(IntegerToString(r.pair.be_armed_total),6)+PadL(IntegerToString(r.exit_count[GZ_EXIT_BREAK_EVEN]),7)
              +PadL(Dbl(r.pair.dr_a,1),8)+PadL(Dbl(r.pair.dr_b,1),8)+PadL(Dbl(d_net,1),8)+PadL(Dbl(d_exp,4),8)+PadL(Dbl(d_pf,3),8)+PadL(Dbl(d_win,1),8)+PadL(Dbl(d_dd,2),8)
              +PadL(Pct(prot),8)+PadL(Pct(lost),8)+"\n";
        }
      s += "SLprot% = A / (BE-off SL_HIT trades). TPlost% = B / (BE-off TP_HIT trades). NoChg = same exit reason and same R as BE off.\n";
      s += "'Armed' = trades whose BE armed at any time (armed trades that still ended TP_HIT/no change are inside C).\n";
      s += "Per-TP context (BE-off SL_HIT / TP_HIT counts) is in section B/A. dPF/dWin%(percentage points)/dMaxDD are BE-on minus BE-off. PF differences can be huge when the BE-on run has almost no losing trades (tiny denominator). This section is descriptive; no BE setting is preferred.\n\n";

      //--- D ------------------------------------------------------------------
      int ir = FindRow(GZ_RB_REFERENCE_ONLY, GZ_RB_REFERENCE_TP_R, 0.0);
      s += "--- D. High-TP reach reference [REFERENCE_ONLY / HIGH_TP_REACH_REFERENCE - NOT a strategy TP, NOT in the TP grid, NOT rankable] ---\n";
      if(ir>=0)
        {
         GZ_RewardBeRow r = m_rows[ir];
         s += StringFormat("Run (executed once): TP=%.0fR (very high, reduced-censoring reach diagnostic; a tiny-risk trade CAN still hit it), BE off. Trades=%d. Exits: SL_HIT=%d TP_HIT=%d DATA_END=%d SESSION_EXIT=%d BREAK_EVEN=%d OTHER=%d.\n",
                           r.tp_r, r.trades, r.exit_count[GZ_EXIT_SL_HIT], r.exit_count[GZ_EXIT_TP_HIT], r.exit_count[GZ_EXIT_DATA_END],
                           r.exit_count[GZ_EXIT_SESSION_EXIT], r.exit_count[GZ_EXIT_BREAK_EVEN], r.exit_count[GZ_EXIT_OTHER]);
         s += "Reach here = trades whose favorable excursion touched +xR while the trade was journal-open (before its stop/data end; see section H for the exact candle rule). It is NOT a TP win rate and is not converted into one.\n";
         s += "The BE-off TP_HIT count at TP=xR (from the independent TP=xR run, section A) is printed beside it purely for side-by-side reading.\n";
         s += PadL("Level",7)+PadL("Reached",9)+PadL("Reached%",10)+PadL("TP_HIT@TP=x",13)+PadL("TP_HIT%",9)+"\n";
         for(int l=0;l<GZ_REACH_LEVEL_COUNT;l++)
           {
            int io = FindOffRow(GZ_REACH_LEVELS[l]);
            double rp = (r.trades>0) ? (double)r.reach_count[l]/r.trades : 0.0;
            string th_txt  = (io>=0) ? IntegerToString(m_rows[io].exit_count[GZ_EXIT_TP_HIT]) : "n/a";   // 5.0R is not a main-matrix TP
            string thp_txt = (io>=0 && m_rows[io].trades>0) ? Pct((double)m_rows[io].exit_count[GZ_EXIT_TP_HIT]/m_rows[io].trades) : "n/a";
            s += PadL(">="+Dbl(GZ_REACH_LEVELS[l],1)+"R",7)+PadL(IntegerToString(r.reach_count[l]),9)+PadL(Pct(rp),10)
                 +PadL(th_txt,13)+PadL(thp_txt,9)+"\n";
           }
         s += StringFormat("Reference-run data-end truncation: %d trades were still open at the end of the data (their Reach is cut off there).\n", r.exit_count[GZ_EXIT_DATA_END]);
         s += StringFormat("Reference-run MFE: avg=%.3fR max=%.3fR | avg MAE=%.3fR max MAE=%.3fR (descriptive; no causal reading is made).\n\n",
                           r.avg_mfe_r, r.max_mfe_r, r.avg_mae_r, r.max_mae_r);
        }

      //--- E ------------------------------------------------------------------
      s += "--- E. Reach matrix per TP/BE row (measured while OPEN in THAT run - censored by that run's own exits; NOT win rates) ---\n";
      s += PadL("TP",4)+PadL("BE",6)+PadL("N",5);
      for(int l=0;l<GZ_REACH_LEVEL_COUNT;l++) s += PadL(">="+Dbl(GZ_REACH_LEVELS[l],1),6);
      s += "\n";
      for(int i=0;i<n;i++)
        {
         if(m_rows[i].kind!=GZ_RB_OFF && m_rows[i].kind!=GZ_RB_BE_ACTIVE) continue;
         GZ_RewardBeRow r = m_rows[i];
         s += PadL(Dbl(r.tp_r,1),4)+PadL(r.kind==GZ_RB_OFF?"OFF":Dbl(r.be_trigger_r,2),6)+PadL(IntegerToString(r.trades),5);
         for(int l=0;l<GZ_REACH_LEVEL_COUNT;l++) s += PadL(IntegerToString(r.reach_count[l]),6);
         s += "\n";
        }
      s += "\n";

      //--- F ------------------------------------------------------------------
      s += "--- F. Intrabar / exit-candle diagnostic counts (measurement only; the baseline engine behavior was NOT changed) ---\n";
      s += "CONFLICT   = one M1 candle touched both SL and TP (policy SL_FIRST resolves it; always recorded).\n";
      s += "EB_EXIT    = trade CLOSED on the very M1 candle it entered on (entry-candle behavior: SL/TP/BE are evaluated on the entry candle itself,\n";
      s += "             and TOUCH fills at that candle's extreme). EB_TP/EB_SL split by reason.\n";
      s += "BE_ON_EB   = BE armed on the entry candle itself.\n";
      s += "RETRACE    = on the BE-arming candle, that candle's own range ALSO reached the new BE stop (true order unknown; the engine applies the\n";
      s += "             new stop from the NEXT candle). RETRACE_NEB excludes entry-candle arms (where TOUCH entry makes the level trivially reached).\n";
      s += PadL("TP",4)+PadL("BE",6)+PadL("N",5)+PadL("CONFL",6)+PadL("EB_EXIT",8)+PadL("EB_TP",6)+PadL("EB_SL",6)+PadL("ARMED",6)+PadL("BE_ON_EB",9)+PadL("RETRACE",8)+PadL("RETR_NEB",9)+"\n";
      for(int i=0;i<n;i++)
        {
         if(m_rows[i].kind!=GZ_RB_OFF && m_rows[i].kind!=GZ_RB_BE_ACTIVE) continue;
         GZ_RewardBeRow r = m_rows[i];
         s += PadL(Dbl(r.tp_r,1),4)+PadL(r.kind==GZ_RB_OFF?"OFF":Dbl(r.be_trigger_r,2),6)+PadL(IntegerToString(r.trades),5)
              +PadL(IntegerToString(r.intrabar_conflicts),6)+PadL(IntegerToString(r.eb_exit_total),8)+PadL(IntegerToString(r.eb_exit_tp),6)
              +PadL(IntegerToString(r.eb_exit_sl),6)+PadL(IntegerToString(r.be_armed),6)+PadL(IntegerToString(r.be_armed_on_entry_bar),9)
              +PadL(IntegerToString(r.be_arm_retrace),8)+PadL(IntegerToString(r.be_arm_retrace_non_entry),9)+"\n";
        }
      s += "\n";

      //--- H ------------------------------------------------------------------
      s += "--- H. MFE / MAE / Reach accounting rule (audit; documented, observable, UNCHANGED baseline behavior) ---\n";
      s += "Per M1 candle the simulator order is: entry engine -> new trade handed to Exit+Journal -> ExitEngine.OnBar -> JournalEngine.OnBar -> SyncJournalClosures.\n";
      s += "  ENTRY candle : the journal is opened BEFORE that candle's own OnBar, so the entry candle's FULL high/low count (a TOUCH entry fills at the candle extreme).\n";
      s += "  EXIT candle  : the journal is still open when it is fed the exit candle (closure is synchronized afterwards), so the exit candle's FULL high/low count toward\n";
      s += "                 MFE, MAE and Reach - including the part beyond the TP/SL price (MFE can exceed the TP R; MAE can exceed 1R on an SL exit; on a same-candle\n";
      s += "                 SL+TP conflict resolved SL_FIRST the candle's high still counts as favorable excursion/Reach).\n";
      s += "  BE ARM candle: counted fully like any candle; the new BE stop applies from the NEXT candle (unchanged).\n";
      s += "  Reach levels use mfe_r >= level on floating-point R values (no tolerance).\n";
      s += "Realized R is never affected by this: exits fill exactly at the TP/SL/BE price. The counts below make the rule observable:\n";
      s += "  MFE@EXIT = trades whose final MFE was last set on their exit candle; MAE@EXIT = same for MAE; TPovr = TP_HIT trades with MFE > TP R;\n";
      s += "  SLbeyond = SL_HIT trades with MAE > 1R.\n";
      s += PadL("TP",4)+PadL("BE",6)+PadL("N",5)+PadL("MFE@EXIT",9)+PadL("MAE@EXIT",9)+PadL("TPovr",7)+PadL("SLbeyond",9)+"\n";
      for(int i=0;i<n;i++)
        {
         if(m_rows[i].kind!=GZ_RB_OFF && m_rows[i].kind!=GZ_RB_BE_ACTIVE) continue;
         GZ_RewardBeRow r = m_rows[i];
         s += PadL(Dbl(r.tp_r,1),4)+PadL(r.kind==GZ_RB_OFF?"OFF":Dbl(r.be_trigger_r,2),6)+PadL(IntegerToString(r.trades),5)
              +PadL(IntegerToString(r.mfe_set_on_exit_bar),9)+PadL(IntegerToString(r.mae_set_on_exit_bar),9)
              +PadL(IntegerToString(r.tp_exit_mfe_overshoot),7)+PadL(IntegerToString(r.sl_exit_mae_beyond_stop),9)+"\n";
        }
      s += "\n";

      //--- G ------------------------------------------------------------------
      s += "--- G. Deterministic validation (runtime, on the Development data) ---\n";
      for(int i=0;i<ArraySize(m_val);i++)
         s += StringFormat("%s: %s - %s\n", m_val[i].id, m_val[i].blocked?"BLOCKED":(m_val[i].passed?"PASS":"FAIL"), m_val[i].detail);
      s += StringFormat("Runtime validation: %d PASS / %d FAIL / %d BLOCKED\n\n", ArraySize(m_val)-ValidationFailCount()-ValidationBlockedCount(),
                        ValidationFailCount(), ValidationBlockedCount());

      s += "--- Unit tests (synthetic fixtures, T167 onward) ---\n";
      s += unit_tests_text;
      s += StringFormat("Unit tests: %d PASS / %d FAIL\n\n", unit_pass, unit_fail);

      string status;
      if(unit_fail>0 || ValidationFailCount()>0)
         status = "PHASE 15.5 FAILED (a validation or unit test failed - see above)";
      else if(ValidationBlockedCount()>0)
         status = "PHASE 15.5 BLOCKED (at least one validation could not be evaluated - see above)";
      else
         status = "PHASE 15.5 COMPLETE";
      s += "--- Phase Status ---\n" + status + "\n";
      bool oos_ok = false;
      for(int v=0; v<ArraySize(m_val); v++)
         if(m_val[v].id=="V08_FINAL_OOS_NOT_ACCESSED") oos_ok = m_val[v].passed && !m_val[v].blocked;
      s += StringFormat("CONFIRMATION: Final OOS was NOT loaded or inspected in this run (V08 %s). Phase 16 was NOT executed. No configuration was chosen, ranked or frozen.\n", oos_ok?"PASS":"NOT CONFIRMED");
      s += "Baseline regression (TP=2.0R + BE off vs Phase 15 Development) is validation V02/V03 above.\n";
      s += "This is historical research only; nothing here is evidence of future performance.\n";
      s += "===================================================\n";
      return s;
     }

   //--- Machine-readable: one line per matrix row (all kinds).
   string BuildMatrixCsv()
     {
      string s = "run,experiment_id,kind,tp_r,be_trigger_r,be_offset_r,trades,winners,losers,flat,win_rate,loss_rate,be_rate,expectancy,profit_factor,pf_undefined,net_r,avg_win_r,avg_loss_r,"
                 "max_dd_r,max_lose_streak,avg_lose_streak,avg_mae_r,max_mae_r,avg_mfe_r,max_mfe_r,"
                 "exit_tp_hit,exit_sl_hit,exit_break_even,exit_session_exit,exit_data_end,exit_other,"
                 "reach_0.5,reach_1.0,reach_1.5,reach_2.0,reach_2.5,reach_3.0,reach_3.5,reach_4.0,reach_4.5,reach_5.0,"
                 "be_armed,intrabar_conflicts,entry_bar_exit_total,entry_bar_exit_tp,entry_bar_exit_sl,be_armed_on_entry_bar,be_arm_retrace,be_arm_retrace_non_entry,mfe_set_on_exit_bar,mae_set_on_exit_bar,tp_exit_mfe_overshoot,sl_exit_mae_beyond_stop\n";
      int n = ArraySize(m_rows);
      for(int i=0;i<n;i++)
        {
         GZ_RewardBeRow r = m_rows[i];
         s += StringFormat("%d,%s,%s,%.2f,%.2f,%.2f,%d,%d,%d,%d,%.6f,%.6f,%.6f,%.6f,%s,%s,%.6f,%.6f,%.6f,%.6f,%d,%.4f,%.6f,%.6f,%.6f,%.6f,",
                           r.run_index, r.experiment_id, GZRewardBeKindToString(r.kind), r.tp_r, r.be_trigger_r, r.be_offset_r,
                           r.trades, r.winners, r.losers, r.flat, r.win_rate, r.loss_rate, r.be_rate, r.expectancy,
                           r.pf_undefined ? "inf" : DoubleToString(r.profit_factor,6), YN(r.pf_undefined), r.net_r, r.avg_win_r, r.avg_loss_r,
                           r.max_dd_r, r.max_lose_streak, r.avg_lose_streak, r.avg_mae_r, r.max_mae_r, r.avg_mfe_r, r.max_mfe_r);
         s += StringFormat("%d,%d,%d,%d,%d,%d,",
                           r.exit_count[GZ_EXIT_TP_HIT], r.exit_count[GZ_EXIT_SL_HIT], r.exit_count[GZ_EXIT_BREAK_EVEN],
                           r.exit_count[GZ_EXIT_SESSION_EXIT], r.exit_count[GZ_EXIT_DATA_END], r.exit_count[GZ_EXIT_OTHER]);
         for(int l=0;l<GZ_REACH_LEVEL_COUNT;l++) s += IntegerToString(r.reach_count[l]) + ",";
         s += StringFormat("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n", r.be_armed, r.intrabar_conflicts, r.eb_exit_total, r.eb_exit_tp, r.eb_exit_sl,
                           r.be_armed_on_entry_bar, r.be_arm_retrace, r.be_arm_retrace_non_entry,
                           r.mfe_set_on_exit_bar, r.mae_set_on_exit_bar, r.tp_exit_mfe_overshoot, r.sl_exit_mae_beyond_stop);
        }
      return s;
     }

   //--- Machine-readable pairwise transitions (every BE-on run, including trigger>=TP validation rows).
   string BuildPairCsv()
     {
      string s = "run,experiment_id,kind,tp_r,be_trigger_r,matched,unmatched_on,unmatched_off,entry_mismatch,off_tp_total,off_sl_total,"
                 "cat_A_sl_to_be,cat_B_tp_to_be,cat_C_tp_to_tp,cat_D_sl_to_sl,cat_E_other,e_be_from_other,e_same_other,e_anomaly,"
                 "no_change,be_armed_total,be_armed_no_change,dR_A,dR_B,dR_C,dR_D,dR_E,dR_total\n";
      int n = ArraySize(m_rows);
      for(int i=0;i<n;i++)
        {
         if(!m_rows[i].pair.valid) continue;
         GZ_RewardBeRow r = m_rows[i];
         GZ_PairStats p = r.pair;
         s += StringFormat("%d,%s,%s,%.2f,%.2f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
                           r.run_index, r.experiment_id, GZRewardBeKindToString(r.kind), r.tp_r, r.be_trigger_r,
                           p.matched, p.unmatched_on, p.unmatched_off, p.entry_mismatch, p.off_tp_total, p.off_sl_total,
                           p.cat_a, p.cat_b, p.cat_c, p.cat_d, p.cat_e, p.e_be_from_other, p.e_same_other, p.e_anomaly,
                           p.no_change, p.be_armed_total, p.be_armed_no_change, p.dr_a, p.dr_b, p.dr_c, p.dr_d, p.dr_e, p.dr_total);
        }
      return s;
     }

   //--- Test hooks -------------------------------------------------------------
   void              TestComparePairs(CGZRunDetail *off, CGZRunDetail *on, GZ_PairStats &ps) { ComparePairs(off, on, ps); }
  };

#endif // __GZ_REWARDBE_ENGINE_MQH__
