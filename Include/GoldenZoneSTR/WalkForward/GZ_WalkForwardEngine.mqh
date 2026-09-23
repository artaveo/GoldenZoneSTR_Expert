//+------------------------------------------------------------------+
//| GZ_WalkForwardEngine.mqh                                          |
//| GoldenZone STR - Phase 13 - Walk-Forward Research                  |
//|                                                                    |
//| Research Adapter concern (Roadmap Phase 17 vocabulary, same as     |
//| CGZExperimentRunner/CGZFilterComboEngine/CGZRobustnessEngine).     |
//| Builds rolling Train -> Validate windows over already-loaded,      |
//| already-validated M1/M5 data, and per window:                      |
//|   1) simulates every candidate value of ONE Phase 12 axis on the   |
//|      TRAINING slice (a FULL Phase 2-8 re-simulation per candidate, |
//|      via Phase 12's CGZRobustnessEngine::RunSweep -> Phase 9's     |
//|      CGZExperimentRunner - NO new simulation logic here),          |
//|   2) selects one value with Phase 12's own Analyze() flags and the |
//|      min-trades floor (see GZ_WalkForwardTypes.mqh design note 2), |
//|   3) runs ONLY that selected value (and, for comparison, the fixed |
//|      BASELINE value) on the VALIDATION slice.                      |
//| Then pools the out-of-sample (validation) trades and computes      |
//| stability information (see Aggregate()).                           |
//|                                                                    |
//| NO LOOKAHEAD, by construction: the training sweep is handed ONLY   |
//| the [train_start, train_end) slice, so validation bars are not     |
//| even present in memory while a value is being selected; the        |
//| validation run is handed ONLY [validate_start, validate_end).      |
//| T141 proves this by mutating every bar at/after train_end and      |
//| checking the first window's training result does not change.       |
//|                                                                    |
//| Adds NO strategy logic - every trade comes from the already-tested |
//| Phase 2-9 pipeline (T01-T96) and every flag/best-pick from Phase   |
//| 12's already-tested Analyze() (T121-T125); T128+ cover only the    |
//| NEW window/selection/aggregation logic itself.                     |
//+------------------------------------------------------------------+
#ifndef __GZ_WALKFORWARD_ENGINE_MQH__
#define __GZ_WALKFORWARD_ENGINE_MQH__

#include "GZ_WalkForwardTypes.mqh"
#include "..\Robustness\GZ_RobustnessTypes.mqh"
#include "..\Robustness\GZ_RobustnessEngine.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZWalkForwardEngine
  {
private:
   CGZLogger        *m_logger;
   long              m_next_seq;   // sequential run id counter - mirrors GZ_RobustnessEngine's own pattern

   string NextId()
     {
      string id = StringFormat("WF_%06d", (int)m_next_seq);
      m_next_seq++;
      return id;
     }

   //--- First index whose bar time is >= t (ArraySize(a) if none).
   //--- Binary search - the arrays are chronological (Phase 1 guarantees
   //--- ordering; see GZ_DataValidator).
   int LowerBound(const MqlRates &a[], datetime t) const
     {
      int lo = 0;
      int hi = ArraySize(a);
      while(lo<hi)
        {
         int mid = lo + (hi-lo)/2;
         if(a[mid].time < t)
            lo = mid+1;
         else
            hi = mid;
        }
      return lo;
     }

   //--- Run exactly ONE axis value on one data slice through Phase 12's
   //--- RunSweep (a one-point sweep) and hand back its compact stats.
   //--- `scratch` is a caller-owned reusable result (RunSweep Clear()s it),
   //--- only to avoid stacking several very large locals.
   bool RunOneValue(const GZ_ExperimentConfig &base_cfg, ENUM_GZ_ROBUSTNESS_PARAM axis, double value,
                    const MqlRates &m1[], const MqlRates &m5[], string dataset_id,
                    ENUM_GZ_VALIDATION_STATUS m1_status, ENUM_GZ_VALIDATION_STATUS m5_status,
                    GZ_RobustnessSweepResult &scratch, GZ_TradeStats &out_stats, GZ_RiskStats &out_risk)
     {
      CGZRobustnessEngine rob(m_logger);
      GZ_RobustnessSweepRequest req;
      req.Clear();
      req.param        = axis;
      req.label        = GZRobustnessParamToString(axis);
      req.base_config  = base_cfg;
      req.values[0]    = value;
      req.value_count  = 1;
      rob.RunSweep(req, m1, m5, dataset_id, m1_status, m5_status, scratch);
      if(scratch.point_count<1)
         return false;
      out_stats = scratch.points[0].result.metrics.trade;
      out_risk  = scratch.points[0].result.metrics.risk;
      return true;
     }

public:
                     CGZWalkForwardEngine(CGZLogger *logger=NULL)
     {
      m_logger   = logger;
      m_next_seq = 1;
     }

   long              NextSequence() const { return m_next_seq; }

   //+---------------------------------------------------------------+
   //| SliceByTime() - copies src bars with from <= time < to_excl     |
   //| (HALF-OPEN, same [start,end) convention as Phase 1's session    |
   //| boundaries) into dst, preserving order. Returns the bar count.   |
   //+---------------------------------------------------------------+
   int               SliceByTime(const MqlRates &src[], datetime from, datetime to_excl, MqlRates &dst[]) const
     {
      int lo  = LowerBound(src, from);
      int hi  = LowerBound(src, to_excl);
      int cnt = hi-lo;
      if(cnt<=0)
        {
         ArrayResize(dst, 0);
         return 0;
        }
      ArrayResize(dst, cnt);
      ArrayCopy(dst, src, 0, lo, cnt);
      return cnt;
     }

   //+---------------------------------------------------------------+
   //| BuildWindows() - PUBLIC and pure (no simulation): fills         |
   //| out.windows[]/window_count/windows_capped from the data range   |
   //| and cfg's train/validate/step days (design note 3, Types file). |
   //| data_end_excl is EXCLUSIVE (last bar time + one bar period).    |
   //| Invalid lengths (<=0) generate nothing and record a note - never|
   //| silently defaulted.                                              |
   //+---------------------------------------------------------------+
   int               BuildWindows(datetime data_start, datetime data_end_excl, const GZ_WalkForwardConfig &cfg,
                                  GZ_WalkForwardResult &out)
     {
      out.window_count   = 0;
      out.windows_capped = false;

      if(cfg.train_days<=0 || cfg.validate_days<=0 || cfg.step_days<=0)
        {
         out.AddNote("INVALID_WINDOW_CONFIG: train_days, validate_days and step_days must all be > 0 - no windows generated.");
         return 0;
        }
      if(data_end_excl<=data_start)
        {
         out.AddNote("EMPTY_DATA_RANGE: data end is not after data start - no windows generated.");
         return 0;
        }

      long tr = (long)cfg.train_days    * GZ_SECONDS_PER_DAY;
      long va = (long)cfg.validate_days * GZ_SECONDS_PER_DAY;
      long st = (long)cfg.step_days     * GZ_SECONDS_PER_DAY;

      long start = (long)data_start;
      int  n     = 0;
      while(true)
        {
         long tr_end = start + tr;
         long va_end = tr_end + va;
         if(va_end > (long)data_end_excl)
            break;                                  // window does not fully fit - never invent a partial one
         if(n>=GZ_MAX_WALKFORWARD_WINDOWS)
           {
            out.windows_capped = true;              // documented cap, flagged not silent (design note 5)
            break;
           }
         out.windows[n].Clear();
         out.windows[n].index          = n;
         out.windows[n].train_start    = (datetime)start;
         out.windows[n].train_end      = (datetime)tr_end;
         out.windows[n].validate_start = (datetime)tr_end;
         out.windows[n].validate_end   = (datetime)va_end;
         n++;
         start += st;
        }
      out.window_count = n;
      return n;
     }

   //+---------------------------------------------------------------+
   //| SelectFromSweep() - PUBLIC on purpose (same reasoning as        |
   //| CGZRobustnessEngine::Analyze()): it needs only an already-       |
   //| populated training sweep, so a test can hand-build one with no   |
   //| simulation at all. NOTE: `sweep` is CONSUMED - candidates below  |
   //| the min-trades floor have their trade_count zeroed so Phase 12's |
   //| Analyze() (which ignores trade_count==0 points) treats them as   |
   //| ineligible, then Analyze() runs on it. Pass a scratch copy if the|
   //| caller still needs the raw sweep.                                 |
   //|                                                                    |
   //| Rule (Types file design note 2): best eligible value, EXCEPT that|
   //| when require_safe is true and Phase 12 says the best is not safe |
   //| to adopt (narrow peak / unstable zone), fall back to the BASELINE|
   //| value if the baseline candidate is itself eligible, else select  |
   //| nothing. Fills the training half of `w` only.                     |
   //+---------------------------------------------------------------+
   void              SelectFromSweep(GZ_RobustnessSweepResult &sweep, int min_trades, bool require_safe,
                                     double baseline_value, GZ_WalkForwardWindow &w)
     {
      int floor_trades = (min_trades>1) ? min_trades : 1;

      w.train_candidates_run      = sweep.point_count;
      w.train_candidates_eligible = 0;
      w.baseline_value            = baseline_value;
      w.train_has_best            = false;
      w.selected_value            = 0.0;
      w.train_stats.Clear();

      for(int i=0; i<sweep.point_count; i++)
        {
         if(sweep.points[i].result.metrics.trade.trade_count >= floor_trades)
            w.train_candidates_eligible++;
         else
            sweep.points[i].result.metrics.trade.trade_count = 0; // ineligible marker for Analyze()
        }

      CGZRobustnessEngine analyzer(m_logger);
      analyzer.Analyze(sweep);

      w.train_narrow_peak     = sweep.narrow_peak;
      w.train_flat_region     = sweep.flat_region;
      w.train_unstable_zone   = sweep.unstable_zone;
      w.train_param_sensitive = sweep.parameter_sensitive;
      w.train_safe_to_adopt   = sweep.safe_to_adopt_best;

      if(sweep.best_idx<0)
        {
         w.status = GZ_WF_SEL_NO_ELIGIBLE;
         return;
        }

      w.train_has_best   = true;
      w.train_best_value = sweep.points[sweep.best_idx].param_value;

      int pick = -1;
      if(!require_safe || sweep.safe_to_adopt_best)
        {
         pick     = sweep.best_idx;
         w.status = GZ_WF_SEL_SELECTED;
        }
      else
        {
         for(int i=0; i<sweep.point_count; i++)
           {
            if(MathAbs(sweep.points[i].param_value - baseline_value)<=0.0000001 &&
               sweep.points[i].result.metrics.trade.trade_count>0)
              {
               pick = i;
               break;
              }
           }
         w.status = (pick>=0) ? GZ_WF_SEL_FALLBACK_BASELINE : GZ_WF_SEL_NO_SAFE_CANDIDATE;
        }

      if(pick>=0)
        {
         w.selected_value = sweep.points[pick].param_value;
         w.train_stats    = sweep.points[pick].result.metrics.trade;
        }
     }

   //+---------------------------------------------------------------+
   //| Aggregate() - PUBLIC and pure: computes every aggregate field of |
   //| `r` from r.windows[0..window_count-1] and r.config alone, so a   |
   //| test can hand-build windows (no simulation). Idempotent for the  |
   //| numeric fields (ClearAggregate() first); it APPENDS notes, so    |
   //| call it once per result.                                          |
   //|                                                                    |
   //| Rules (no Roadmap formula - conventional, documented):            |
   //|  - POOLED out-of-sample = every validated window's validation     |
   //|    trades concatenated. Win/loss R sums are rebuilt from          |
   //|    avg_win_r*winners and avg_loss_r*losers (Phase 8's own stats), |
   //|    so pooled profit factor needs no per-trade list.                |
   //|  - BASELINE comparison = the fixed baseline value over the SAME    |
   //|    validation slices; selection_edge_expectancy = pooled minus     |
   //|    baseline pooled expectancy (does selecting per window beat      |
   //|    never changing the parameter at all?).                          |
   //|  - walk_forward_efficiency = mean validation expectancy / mean     |
   //|    training expectancy (each validated window weighted equally),   |
   //|    UNDEFINED unless mean training expectancy > GZ_WF_NOISE_FLOOR_R.|
   //|  - OVERFIT_SUSPECT: efficiency defined AND < GZ_WF_EFFICIENCY_MIN. |
   //|  - PARAM_UNSTABLE: >= GZ_WF_PARAM_UNSTABLE_MIN_WINDOWS selected    |
   //|    windows AND (changes between consecutive selected windows) /    |
   //|    (selected windows - 1) > GZ_WF_PARAM_UNSTABLE_CHANGE_PCT.        |
   //|  - NEGATIVE_OOS: pooled trades > 0 AND pooled expectancy <= 0.      |
   //|  - VALIDATION_OVERLAP: step_days < validate_days (pooled trades     |
   //|    then double-count the overlapped span).                          |
   //+---------------------------------------------------------------+
   void              Aggregate(GZ_WalkForwardResult &r) const
     {
      r.ClearAggregate();
      r.validation_overlap = (r.config.step_days < r.config.validate_days);

      double sum_win_r = 0.0, sum_loss_r = 0.0;
      double sum_train_exp = 0.0, sum_val_exp = 0.0;
      double base_net = 0.0;
      int    base_trades = 0;

      double sel_vals[GZ_MAX_WALKFORWARD_WINDOWS];
      int    sel_n = 0;

      for(int i=0; i<r.window_count; i++)
        {
         if(r.windows[i].HasSelection())
           {
            r.windows_selected++;
            sel_vals[sel_n] = r.windows[i].selected_value;
            sel_n++;
           }

         if(!r.windows[i].validation_ran)
            continue;

         r.windows_validated++;
         if(r.windows[i].low_validation_trades)
            r.windows_low_validation_trades++;

         r.pooled_trades  += r.windows[i].val_stats.trade_count;
         r.pooled_winners += r.windows[i].val_stats.winners;
         r.pooled_losers  += r.windows[i].val_stats.losers;
         r.pooled_net_r   += r.windows[i].val_stats.net_r;
         sum_win_r        += r.windows[i].val_stats.avg_win_r  * (double)r.windows[i].val_stats.winners;
         sum_loss_r       += r.windows[i].val_stats.avg_loss_r * (double)r.windows[i].val_stats.losers;
         if(r.windows[i].val_stats.net_r > 0.0000001)
            r.positive_windows++;

         sum_train_exp += r.windows[i].train_stats.expectancy;
         sum_val_exp   += r.windows[i].val_stats.expectancy;

         if(r.windows[i].baseline_val_ran)
           {
            base_trades += r.windows[i].baseline_val_stats.trade_count;
            base_net    += r.windows[i].baseline_val_stats.net_r;
           }
        }

      //--- Pooled out-of-sample statistics
      if(r.pooled_trades>0)
        {
         r.pooled_expectancy = r.pooled_net_r / (double)r.pooled_trades;
         r.pooled_win_rate   = (double)r.pooled_winners / (double)r.pooled_trades;
        }
      if(sum_loss_r > 0.0000001)
         r.pooled_profit_factor = sum_win_r / sum_loss_r;
      else if(sum_win_r > 0.0000001)
        {
         r.pooled_profit_factor           = 0.0;
         r.pooled_profit_factor_undefined = true;   // winners exist with zero losing R - same meaning as GZ_TradeStats
        }

      //--- Baseline comparison
      r.baseline_pooled_trades = base_trades;
      r.baseline_pooled_net_r  = base_net;
      if(base_trades>0)
         r.baseline_pooled_expectancy = base_net / (double)base_trades;
      if(r.pooled_trades>0 && base_trades>0)
        {
         r.selection_edge_defined    = true;
         r.selection_edge_expectancy = r.pooled_expectancy - r.baseline_pooled_expectancy;
        }

      //--- Walk-forward efficiency
      if(r.windows_validated>0)
        {
         r.mean_train_expectancy = sum_train_exp / (double)r.windows_validated;
         r.mean_val_expectancy   = sum_val_exp   / (double)r.windows_validated;
         if(r.mean_train_expectancy > GZ_WF_NOISE_FLOOR_R)
           {
            r.efficiency_defined       = true;
            r.walk_forward_efficiency  = r.mean_val_expectancy / r.mean_train_expectancy;
           }
        }

      //--- Parameter stability across the windows that selected a value
      if(sel_n>0)
        {
         double uniq[GZ_MAX_WALKFORWARD_WINDOWS];
         int    cnt[GZ_MAX_WALKFORWARD_WINDOWS];
         int    u = 0;
         r.selected_value_min = sel_vals[0];
         r.selected_value_max = sel_vals[0];
         for(int k=0; k<sel_n; k++)
           {
            if(sel_vals[k]<r.selected_value_min) r.selected_value_min = sel_vals[k];
            if(sel_vals[k]>r.selected_value_max) r.selected_value_max = sel_vals[k];

            int found = -1;
            for(int j=0; j<u; j++)
              {
               if(MathAbs(uniq[j]-sel_vals[k])<=0.0000001) { found = j; break; }
              }
            if(found>=0)
               cnt[found]++;
            else
              {
               uniq[u] = sel_vals[k];
               cnt[u]  = 1;
               u++;
              }
            if(k>0 && MathAbs(sel_vals[k]-sel_vals[k-1])>0.0000001)
               r.selection_changes++;
           }
         r.distinct_selected_values = u;
         for(int j=0; j<u; j++)
            if(cnt[j]>r.most_common_selected_count)
               r.most_common_selected_count = cnt[j];
        }

      //--- Flags
      if(sel_n>=GZ_WF_PARAM_UNSTABLE_MIN_WINDOWS)
         r.param_unstable = ((double)r.selection_changes / (double)(sel_n-1)) > GZ_WF_PARAM_UNSTABLE_CHANGE_PCT;
      r.overfit_suspect = (r.efficiency_defined && r.walk_forward_efficiency < GZ_WF_EFFICIENCY_MIN);
      r.negative_oos    = (r.pooled_trades>0 && r.pooled_expectancy<=0.0);

      //--- Notes
      if(r.windows_capped)
         r.AddNote(StringFormat("WINDOWS_CAPPED: more windows would fit but generation stopped at GZ_MAX_WALKFORWARD_WINDOWS=%d.", GZ_MAX_WALKFORWARD_WINDOWS));
      if(r.validation_overlap)
         r.AddNote("VALIDATION_OVERLAP: step_days < validate_days, so consecutive validation windows overlap and pooled OOS trades double-count the overlapped span.");
      if(r.window_count>0 && r.windows_validated==0)
         r.AddNote("NO_VALIDATED_WINDOWS: no window selected a value and reached validation - no out-of-sample result exists.");
      if(r.windows_low_validation_trades>0)
         r.AddNote(StringFormat("LOW_VALIDATION_TRADES: %d validated window(s) had fewer than min_validation_trades=%d trades - their individual results are weak evidence.",
                    r.windows_low_validation_trades, r.config.min_validation_trades));
      if(r.param_unstable)
         r.AddNote(StringFormat("PARAM_UNSTABLE: the selected value changed between %d of %d consecutive selected-window pairs.",
                    r.selection_changes, sel_n-1));
      if(r.overfit_suspect)
         r.AddNote(StringFormat("OVERFIT_SUSPECT: walk-forward efficiency %.2f is below %.2f - validation expectancy captured little of what training selected.",
                    r.walk_forward_efficiency, GZ_WF_EFFICIENCY_MIN));
      if(r.negative_oos)
         r.AddNote("NEGATIVE_OOS: pooled out-of-sample expectancy is not positive.");
     }

   //+---------------------------------------------------------------+
   //| RunWalkForward() - windows -> per-window train sweep -> select   |
   //| -> validate selected + baseline -> Aggregate(). Needs already-   |
   //| loaded, already-validated M1/M5 (Phase 1's job, not repeated     |
   //| here - GZ_ExperimentTypes.mqh design note 4). Deterministic: no  |
   //| randomness, no wall-clock, no cross-run state except the id      |
   //| counter.                                                          |
   //+---------------------------------------------------------------+
   void              RunWalkForward(const GZ_WalkForwardConfig &cfg, const MqlRates &m1[], const MqlRates &m5[],
                                    string dataset_id, ENUM_GZ_VALIDATION_STATUS m1_status,
                                    ENUM_GZ_VALIDATION_STATUS m5_status, GZ_WalkForwardResult &out)
     {
      out.Clear();
      out.id                   = NextId();
      out.dataset_id           = dataset_id;
      out.config               = cfg;
      out.axis                 = cfg.axis;
      out.axis_label           = GZRobustnessParamToString(cfg.axis);
      out.strategy_version     = GZ_STRATEGY_VERSION;
      out.m1_validation_status = m1_status;
      out.m5_validation_status = m5_status;

      CGZRobustnessEngine rob(m_logger);
      out.baseline_value = rob.GetAxisValue(cfg.base_config, cfg.axis);

      int n5 = ArraySize(m5);
      if(n5==0)
        {
         out.AddNote("NO_M5_DATA: no M5 data supplied - walk-forward skipped.");
         if(m_logger!=NULL)
            m_logger.Warning("WalkForward", StringFormat("%s: no M5 data supplied - skipped.", out.id));
         return;
        }
      if(cfg.candidate_count<=0)
        {
         out.AddNote("NO_CANDIDATES: candidate_count is 0 - nothing to select between, walk-forward skipped.");
         if(m_logger!=NULL)
            m_logger.Warning("WalkForward", StringFormat("%s: no candidate values supplied - skipped.", out.id));
         return;
        }

      datetime data_start = m5[0].time;
      datetime data_end   = (datetime)((long)m5[n5-1].time + GZ_SPACING_M5_SECONDS);
      BuildWindows(data_start, data_end, cfg, out);
      if(out.window_count==0)
         out.AddNote("NO_WINDOWS: the data range is too short for even one full train+validate window.");

      MqlRates m5_train[], m1_train[], m5_val[], m1_val[];
      GZ_RobustnessSweepResult sweep;

      int nc = cfg.candidate_count;
      if(nc>GZ_MAX_ROBUSTNESS_POINTS)
         nc = GZ_MAX_ROBUSTNESS_POINTS;

      for(int k=0; k<out.window_count; k++)
        {
         datetime ts = out.windows[k].train_start;
         datetime te = out.windows[k].train_end;
         datetime vs = out.windows[k].validate_start;
         datetime ve = out.windows[k].validate_end;

         SliceByTime(m5, ts, te, m5_train);
         SliceByTime(m1, ts, te, m1_train);
         SliceByTime(m5, vs, ve, m5_val);
         SliceByTime(m1, vs, ve, m1_val);
         out.windows[k].train_m5_bars    = ArraySize(m5_train);
         out.windows[k].validate_m5_bars = ArraySize(m5_val);
         out.windows[k].baseline_value   = out.baseline_value;

         if(ArraySize(m5_train)==0)
           {
            out.windows[k].status = GZ_WF_SEL_NO_DATA;
            continue;
           }

         //--- 1) TRAINING sweep over every candidate value
         GZ_RobustnessSweepRequest req;
         req.Clear();
         req.param       = cfg.axis;
         req.label       = out.axis_label;
         req.base_config = cfg.base_config;
         req.base_config.range_start = ts;
         req.base_config.range_end   = (datetime)((long)te - 1);
         for(int i=0; i<nc; i++)
            req.values[i] = cfg.candidates[i];
         req.value_count = nc;

         string ds_train = StringFormat("%s_WF%d_TRAIN", dataset_id, k);
         rob.RunSweep(req, m1_train, m5_train, ds_train, m1_status, m5_status, sweep);

         //--- 2) SELECT (validation data was never handed to anything above)
         SelectFromSweep(sweep, cfg.min_trades, cfg.require_safe_selection, out.baseline_value, out.windows[k]);
         if(!out.windows[k].HasSelection())
           {
            if(m_logger!=NULL)
               m_logger.Info("WalkForward", StringFormat("%s window %d: %s (run=%d eligible=%d) - not validated.",
                              out.id, k, GZWfSelectionStatusToString(out.windows[k].status),
                              out.windows[k].train_candidates_run, out.windows[k].train_candidates_eligible));
            continue;
           }

         //--- 3) VALIDATE the selected value, then the fixed baseline for comparison
         GZ_ExperimentConfig vbase = cfg.base_config;
         vbase.range_start = vs;
         vbase.range_end   = (datetime)((long)ve - 1);
         string ds_val = StringFormat("%s_WF%d_VAL", dataset_id, k);

         bool ok = RunOneValue(vbase, cfg.axis, out.windows[k].selected_value, m1_val, m5_val, ds_val,
                                m1_status, m5_status, sweep, out.windows[k].val_stats, out.windows[k].val_risk);
         out.windows[k].validation_ran = ok;
         if(ok)
            out.windows[k].low_validation_trades = (out.windows[k].val_stats.trade_count < cfg.min_validation_trades);

         if(MathAbs(out.windows[k].selected_value - out.baseline_value)<=0.0000001)
           {
            out.windows[k].baseline_val_stats = out.windows[k].val_stats;   // selected IS the baseline - identical run, don't repeat it
            out.windows[k].baseline_val_ran   = ok;
           }
         else
           {
            GZ_RiskStats unused_risk;
            out.windows[k].baseline_val_ran = RunOneValue(vbase, cfg.axis, out.baseline_value, m1_val, m5_val, ds_val,
                                                           m1_status, m5_status, sweep,
                                                           out.windows[k].baseline_val_stats, unused_risk);
           }

         if(m_logger!=NULL)
            m_logger.Info("WalkForward", StringFormat(
               "%s window %d: train=[%s .. %s) validate=[%s .. %s) %s=%.4f (%s) train_trades=%d train_exp=%.4f | val_trades=%d val_net_r=%.3f val_exp=%.4f baseline_val_exp=%.4f",
               out.id, k, TimeToString(ts), TimeToString(te), TimeToString(vs), TimeToString(ve),
               out.axis_label, out.windows[k].selected_value, GZWfSelectionStatusToString(out.windows[k].status),
               out.windows[k].train_stats.trade_count, out.windows[k].train_stats.expectancy,
               out.windows[k].val_stats.trade_count, out.windows[k].val_stats.net_r, out.windows[k].val_stats.expectancy,
               out.windows[k].baseline_val_stats.expectancy));
        }

      Aggregate(out);

      if(m_logger!=NULL)
         m_logger.Info("WalkForward", StringFormat(
            "%s [%s] baseline=%.4f windows=%d selected=%d validated=%d | pooled OOS: trades=%d net_r=%.3f expectancy=%.4f pf=%.3f | efficiency=%s | flags: param_unstable=%s overfit_suspect=%s negative_oos=%s validation_overlap=%s",
            out.id, out.axis_label, out.baseline_value, out.window_count, out.windows_selected, out.windows_validated,
            out.pooled_trades, out.pooled_net_r, out.pooled_expectancy, out.pooled_profit_factor,
            out.efficiency_defined ? DoubleToString(out.walk_forward_efficiency,3) : "undefined",
            out.param_unstable?"true":"false", out.overfit_suspect?"true":"false",
            out.negative_oos?"true":"false", out.validation_overlap?"true":"false"));
     }
  };

#endif // __GZ_WALKFORWARD_ENGINE_MQH__
