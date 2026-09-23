//+------------------------------------------------------------------+
//| GZ_RobustnessEngine.mqh                                           |
//| GoldenZone STR - Phase 12 - Robustness + Sensitivity Research     |
//|                                                                    |
//| Research Adapter concern (Roadmap Phase 17 vocabulary, same as     |
//| CGZExperimentRunner/CGZFilterComboEngine - see those files'        |
//| headers). Builds a neighborhood of GZ_ExperimentConfig values      |
//| around one axis, runs EACH through Phase 9's own                   |
//| CGZExperimentRunner (a FULL Phase 2-8 re-simulation per point -    |
//| see GZ_RobustnessTypes.mqh design note 1, this is the opposite of  |
//| Phase 11's no-re-simulation post-hoc masking), then analyzes the   |
//| resulting expectancy curve for the Roadmap's named sensitivity     |
//| patterns (Narrow peak / Flat region / Unstable zone / Parameter    |
//| sensitivity - see Analyze() below). Adds NO new strategy logic -   |
//| every point's actual trading behavior comes entirely from the      |
//| already-tested Phase 2-9 pipeline (T01-T96); T117+ below cover     |
//| only the NEW axis-application and curve-analysis logic itself.     |
//+------------------------------------------------------------------+
#ifndef __GZ_ROBUSTNESS_ENGINE_MQH__
#define __GZ_ROBUSTNESS_ENGINE_MQH__

#include "GZ_RobustnessTypes.mqh"
#include "..\Experiment\GZ_ExperimentTypes.mqh"
#include "..\Experiment\GZ_ExperimentRunner.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZRobustnessEngine
  {
private:
   CGZLogger        *m_logger;
   long              m_next_seq;        // sequential sweep id counter - mirrors GZ_ExperimentTypes.mqh design note 3
   int               m_max_batch_size;  // Roadmap "stage research, don't run one huge Grid" cap, reapplied here (axes per RunSweepBatch call)

   string NextId()
     {
      string id = StringFormat("ROB_%06d", (int)m_next_seq);
      m_next_seq++;
      return id;
     }

   //--- Read the CURRENT value of `axis` out of a config - used both as
   //--- the sweep's auto-baseline (BuildNeighborhoodRequest) and as the
   //--- "distance from baseline" tie-break in Analyze()'s best_idx pick.
   double AxisBaselineValue(const GZ_ExperimentConfig &cfg, ENUM_GZ_ROBUSTNESS_PARAM axis) const
     {
      switch(axis)
        {
         case GZ_ROBUST_PIVOT_STRENGTH:        return (double)cfg.pivot_strength;
         case GZ_ROBUST_BREAK_BUFFER_ATR:      return cfg.break_config.buffer_atr_mult;
         case GZ_ROBUST_ATR_PERIOD:            return (double)cfg.break_config.atr_period;
         case GZ_ROBUST_FIB_ZONE_MIN_RATIO:    return cfg.fib_zone_min_ratio;
         case GZ_ROBUST_FIB_ZONE_MAX_RATIO:    return cfg.fib_zone_max_ratio;
         case GZ_ROBUST_ENTRY_PENETRATION_ATR: return cfg.entry_config.penetration_atr_mult;
         case GZ_ROBUST_CONFIRMATION_CANDLES:  return (double)cfg.entry_config.confirmation_candles;
         case GZ_ROBUST_SL_ATR_MULT:           return cfg.exit_config.sl_atr_mult;
         case GZ_ROBUST_SL_BUFFER_ATR:         return cfg.exit_config.sl_buffer_atr_mult;
         case GZ_ROBUST_TP_R_MULTIPLE:         return cfg.exit_config.tp_r_multiple;
         case GZ_ROBUST_BE_TRIGGER_R:          return cfg.exit_config.be_trigger_r;
         default:                              return 0.0;
        }
     }

   //--- Mutate ONLY `axis`'s own field of `cfg`, everything else in cfg
   //--- untouched. Integer-backed axes round to the nearest int.
   void ApplyAxisValue(GZ_ExperimentConfig &cfg, ENUM_GZ_ROBUSTNESS_PARAM axis, double value) const
     {
      switch(axis)
        {
         case GZ_ROBUST_PIVOT_STRENGTH:        cfg.pivot_strength               = (int)MathRound(value); break;
         case GZ_ROBUST_BREAK_BUFFER_ATR:      cfg.break_config.buffer_atr_mult = value; break;
         case GZ_ROBUST_ATR_PERIOD:            cfg.break_config.atr_period      = (int)MathRound(value); break;
         case GZ_ROBUST_FIB_ZONE_MIN_RATIO:    cfg.fib_zone_min_ratio           = value; break;
         case GZ_ROBUST_FIB_ZONE_MAX_RATIO:    cfg.fib_zone_max_ratio           = value; break;
         case GZ_ROBUST_ENTRY_PENETRATION_ATR: cfg.entry_config.penetration_atr_mult = value; break;
         case GZ_ROBUST_CONFIRMATION_CANDLES:  cfg.entry_config.confirmation_candles = (int)MathRound(value); break;
         case GZ_ROBUST_SL_ATR_MULT:           cfg.exit_config.sl_atr_mult      = value; break;
         case GZ_ROBUST_SL_BUFFER_ATR:         cfg.exit_config.sl_buffer_atr_mult = value; break;
         case GZ_ROBUST_TP_R_MULTIPLE:         cfg.exit_config.tp_r_multiple    = value; break;
         case GZ_ROBUST_BE_TRIGGER_R:          cfg.exit_config.be_trigger_r     = value; break;
         default: break;
        }
     }

   //--- Domain check BEFORE a value is ever applied/run - an out-of-domain
   //--- value is SKIPPED (documented in the result's notes[], see
   //--- ExecutePoints()), never silently clamped into a different number
   //--- and never silently run anyway (same "do not fabricate/silently
   //--- repair" discipline as Phase 1's own validator).
   bool IsValidAxisValue(const GZ_ExperimentConfig &cfg, ENUM_GZ_ROBUSTNESS_PARAM axis, double value) const
     {
      switch(axis)
        {
         case GZ_ROBUST_PIVOT_STRENGTH:        return (value>=1.0);
         case GZ_ROBUST_BREAK_BUFFER_ATR:      return (value>=0.0);
         case GZ_ROBUST_ATR_PERIOD:            return (value>=1.0);
         case GZ_ROBUST_FIB_ZONE_MIN_RATIO:    return (value>0.0 && value<1.0 && value<cfg.fib_zone_max_ratio);
         case GZ_ROBUST_FIB_ZONE_MAX_RATIO:    return (value>0.0 && value<=1.0 && value>cfg.fib_zone_min_ratio);
         case GZ_ROBUST_ENTRY_PENETRATION_ATR: return (value>=0.0);
         case GZ_ROBUST_CONFIRMATION_CANDLES:  return (value>=1.0);
         case GZ_ROBUST_SL_ATR_MULT:           return (value>0.0);
         case GZ_ROBUST_SL_BUFFER_ATR:         return (value>=0.0);
         case GZ_ROBUST_TP_R_MULTIPLE:         return (value>0.0);
         case GZ_ROBUST_BE_TRIGGER_R:          return (value>=0.0);
         default:                              return false;
        }
     }

   //--- Run every (valid) requested value through a FRESH, LOCAL
   //--- CGZExperimentRunner (no cross-call state - this repo's
   //--- established discipline, see CGZExperimentRunner's own header and
   //--- CGZFilterComboEngine::Execute()'s identical choice), fill
   //--- out.points[], then sort points ascending by param_value
   //--- (deterministic insertion sort, mirrors R11-C's own ranking sort
   //--- in GZ_FilterComboEngine.mqh) so Analyze() can assume adjacency ==
   //--- neighboring parameter values.
   void ExecutePoints(GZ_RobustnessSweepResult &out, const GZ_RobustnessSweepRequest &req,
                       const MqlRates &m1[], const MqlRates &m5[], string dataset_id,
                       ENUM_GZ_VALIDATION_STATUS m1_status, ENUM_GZ_VALIDATION_STATUS m5_status)
     {
      CGZExperimentRunner runner(m_logger);
      out.point_count = 0;
      for(int i=0; i<req.value_count; i++)
        {
         if(!IsValidAxisValue(req.base_config, req.param, req.values[i]))
           {
            out.AddNote(StringFormat("SKIPPED value=%.4f for %s - out of domain, not run.",
                        req.values[i], GZRobustnessParamToString(req.param)));
            continue;
           }
         GZ_ExperimentConfig cfg = req.base_config;
         ApplyAxisValue(cfg, req.param, req.values[i]);

         int pi = out.point_count;
         out.points[pi].Clear();
         out.points[pi].param_value   = req.values[i];
         out.points[pi].value_applied = true;
         runner.RunSingle(cfg, m1, m5, dataset_id, m1_status, m5_status, out.points[pi].result);
         out.point_count++;
         if(out.point_count>=GZ_MAX_ROBUSTNESS_POINTS)
            break; // defensive only - req.value_count is already capped at build time
        }

      //--- Insertion sort by param_value ascending (small N - at most
      //--- GZ_MAX_ROBUSTNESS_POINTS - no need for anything fancier;
      //--- identical technique to CGZFilterComboEngine::
      //--- BuildR11CMultiFilterRequests()'s own candidate ranking sort).
      for(int i=1; i<out.point_count; i++)
        {
         GZ_RobustnessPoint tmp = out.points[i];
         int j = i-1;
         while(j>=0 && out.points[j].param_value>tmp.param_value)
           {
            out.points[j+1] = out.points[j];
            j--;
           }
         out.points[j+1] = tmp;
        }
     }

public:
                     CGZRobustnessEngine(CGZLogger *logger=NULL)
     {
      m_logger         = logger;
      m_next_seq       = 1;
      m_max_batch_size = GZ_DEFAULT_MAX_ROBUSTNESS_BATCH_SIZE;
     }

   void              SetMaxBatchSize(int max_size) { m_max_batch_size = (max_size>0) ? max_size : GZ_DEFAULT_MAX_ROBUSTNESS_BATCH_SIZE; }
   int               MaxBatchSize()  const { return m_max_batch_size; }
   long              NextSequence()  const { return m_next_seq; }

   //--- Public accessor - lets a caller (or a test) read what value an
   //--- axis currently holds in an arbitrary config, without duplicating
   //--- the switch above.
   double            GetAxisValue(const GZ_ExperimentConfig &cfg, ENUM_GZ_ROBUSTNESS_PARAM axis) const
     {
      return AxisBaselineValue(cfg, axis);
     }

   //--- Build a request: baseline = base_cfg's OWN current value for
   //--- `axis` (read via AxisBaselineValue - the caller never has to
   //--- restate the center), values = baseline+offsets[i], truncated to
   //--- GZ_MAX_ROBUSTNESS_POINTS if the caller supplies more (documented
   //--- cap, not silently grown elsewhere). Domain filtering happens
   //--- later, in ExecutePoints() - a request may legally contain values
   //--- that get skipped at run time (e.g. a negative buffer offset near
   //--- a zero baseline), so the SKIPPED note always explains why a point
   //--- is missing rather than the point silently not existing.
   int BuildNeighborhoodRequest(const GZ_ExperimentConfig &base_cfg, ENUM_GZ_ROBUSTNESS_PARAM axis,
                                 const double &offsets[], int offset_count, GZ_RobustnessSweepRequest &out, string label="")
     {
      out.Clear();
      out.param       = axis;
      out.label        = (label=="") ? GZRobustnessParamToString(axis) : label;
      out.base_config  = base_cfg;

      double center = AxisBaselineValue(base_cfg, axis);
      int n = offset_count;
      if(n>GZ_MAX_ROBUSTNESS_POINTS)
         n = GZ_MAX_ROBUSTNESS_POINTS;

      out.value_count = 0;
      for(int i=0; i<n; i++)
        {
         out.values[out.value_count] = center + offsets[i];
         out.value_count++;
        }
      return out.value_count;
     }

   //--- One axis in, one GZ_RobustnessSweepResult out: run every point
   //--- (ExecutePoints), then analyze the resulting curve (Analyze()).
   void RunSweep(const GZ_RobustnessSweepRequest &req, const MqlRates &m1[], const MqlRates &m5[],
                  string dataset_id, ENUM_GZ_VALIDATION_STATUS m1_status, ENUM_GZ_VALIDATION_STATUS m5_status,
                  GZ_RobustnessSweepResult &out)
     {
      out.Clear();
      out.id             = NextId();
      out.param          = req.param;
      out.param_label    = (req.label=="") ? GZRobustnessParamToString(req.param) : req.label;
      out.baseline_value = AxisBaselineValue(req.base_config, req.param);

      ExecutePoints(out, req, m1, m5, dataset_id, m1_status, m5_status);
      Analyze(out);

      if(m_logger!=NULL)
         m_logger.Info("Robustness", StringFormat(
            "%s [%s] baseline=%.4f points=%d best=%s expectancy=%s safe_to_adopt=%s | flags: narrow_peak=%s flat_region=%s unstable_zone=%s parameter_sensitive=%s",
            out.id, out.param_label, out.baseline_value, out.point_count,
            (out.best_idx>=0)?DoubleToString(out.points[out.best_idx].param_value,4):"n/a",
            (out.best_idx>=0)?DoubleToString(out.points[out.best_idx].result.metrics.trade.expectancy,4):"n/a",
            out.safe_to_adopt_best?"true":"false", out.narrow_peak?"true":"false", out.flat_region?"true":"false",
            out.unstable_zone?"true":"false", out.parameter_sensitive?"true":"false"));
     }

   //--- Several axes swept in one call, same cap-and-reject pattern as
   //--- every other phase's own RunBatch() (Roadmap "stage research,
   //--- don't run one huge Grid at once") - REJECTED outright (results
   //--- resized to 0, nothing executed, m_next_seq untouched) rather than
   //--- silently truncated.
   ENUM_GZ_ROBUSTNESS_BATCH_STATUS RunSweepBatch(const GZ_RobustnessSweepRequest &requests[], int count,
                                                  const MqlRates &m1[], const MqlRates &m5[], string dataset_id,
                                                  ENUM_GZ_VALIDATION_STATUS m1_status, ENUM_GZ_VALIDATION_STATUS m5_status,
                                                  GZ_RobustnessSweepResult &results[])
     {
      ArrayResize(results, 0);

      if(count<=0)
        {
         if(m_logger!=NULL)
            m_logger.Warning("Robustness", "RunSweepBatch: empty request list - nothing to run.");
         return GZ_ROBUST_BATCH_REJECTED_EMPTY;
        }

      if(count>m_max_batch_size)
        {
         if(m_logger!=NULL)
            m_logger.Error("Robustness", StringFormat(
               "RunSweepBatch: %d axis-sweeps exceeds max batch size %d - REJECTED (Roadmap: stage research, "+
               "don't run one huge Grid at once). Call SetMaxBatchSize() to raise the cap, or split into smaller batches.",
               count, m_max_batch_size));
         return GZ_ROBUST_BATCH_REJECTED_TOO_LARGE;
        }

      ArrayResize(results, count);
      for(int i=0; i<count; i++)
         RunSweep(requests[i], m1, m5, dataset_id, m1_status, m5_status, results[i]);

      if(m_logger!=NULL)
         m_logger.Info("Robustness", StringFormat("RunSweepBatch: %d axis-sweeps executed -> %d results.", count, ArraySize(results)));
      return GZ_ROBUST_BATCH_OK;
     }

   //+---------------------------------------------------------------+
   //| Analyze() - PUBLIC on purpose: it operates ONLY on an already-  |
   //| populated r.points[0..r.point_count-1]/r.baseline_value, with no|
   //| dependency on how those points were produced. RunSweep() calls  |
   //| it internally, but a caller (or a test - see T121-T124) can also|
   //| hand-build a GZ_RobustnessSweepResult (synthetic param_value/    |
   //| trade_count/expectancy per point, no simulation at all) and call |
   //| Analyze() directly - exactly the same "hand-built result, test   |
   //| only the NEW logic" pattern GZ_FilterComboEngine's own R11-C     |
   //| ranking test (T111) already uses.                                |
   //|                                                                  |
   //| Roadmap Phase 12 flags, as concrete, documented rules (no formula |
   //| given by the Roadmap itself - see GZ_RobustnessTypes.mqh design  |
   //| note 4 / GZ_Constants.mqh for every threshold used below):        |
   //|                                                                  |
   //|  - best_idx: highest expectancy among points that actually        |
   //|    produced trades (trade_count>0); a trade_count==0 point can     |
   //|    never win (there is nothing to trust it on). Ties broken by     |
   //|    distance-from-baseline ascending, then param_value ascending -  |
   //|    deterministic, and biased toward the LEAST-changed config on a  |
   //|    tie rather than an arbitrary array-order pick.                  |
   //|                                                                    |
   //|  - NARROW_PEAK: best_idx is a strict interior point (both           |
   //|    neighbors exist and produced trades) AND best_idx's expectancy   |
   //|    is positive AND BOTH immediate neighbors fall below              |
   //|    (1-GZ_ROBUST_NARROW_PEAK_DROP_PCT) of the peak - i.e. performance |
   //|    craters just one step away from the "best" value on both sides,  |
   //|    exactly the fragile-single-number case Roadmap Phase 12 warns    |
   //|    about.                                                            |
   //|                                                                      |
   //|  - FLAT_REGION: ANY run of GZ_ROBUST_FLAT_REGION_MIN_POINTS or more   |
   //|    CONSECUTIVE (sorted-by-value, all trade_count>0) points whose      |
   //|    expectancy stays within GZ_ROBUST_FLAT_REGION_TOL_PCT of that       |
   //|    window's own max - a stable plateau, the opposite finding from     |
   //|    NARROW_PEAK.                                                        |
   //|                                                                        |
   //|  - UNSTABLE_ZONE: at least GZ_ROBUST_UNSTABLE_SIGN_FLIPS_MIN            |
   //|    consecutive-pair sign flips in expectancy (ignoring pairs where      |
   //|    either side is within the GZ_ROBUST_NOISE_FLOOR_R noise floor of     |
   //|    zero) - the curve is erratic, not a smooth function of the axis,     |
   //|    so no single value in that zone should be trusted.                   |
   //|                                                                          |
   //|  - PARAMETER_SENSITIVE: the whole sweep's (max-min) expectancy range     |
   //|    exceeds GZ_ROBUST_PARAM_SENSITIVE_RANGE_PCT of |best expectancy|       |
   //|    (or the absolute floor GZ_ROBUST_PARAM_SENSITIVE_ABS_FLOOR when        |
   //|    |best| is near zero) - the result as a whole depends heavily on        |
   //|    exactly which value is chosen.                                         |
   //|                                                                            |
   //|  - safe_to_adopt_best (design note 5): best_idx>=0 AND !narrow_peak AND    |
   //|    !unstable_zone. flat_region/parameter_sensitive do NOT block            |
   //|    adoption on their own (a flat plateau is actually reassuring; a         |
   //|    sensitive-but-smooth, non-narrow curve still has a defensible           |
   //|    single best point) - only the two flags that mean "this exact           |
   //|    point's own number cannot be trusted" do.                               |
   //+---------------------------------------------------------------+
   void Analyze(GZ_RobustnessSweepResult &r) const
     {
      r.best_idx            = -1;
      r.narrow_peak          = false;
      r.flat_region          = false;
      r.unstable_zone        = false;
      r.parameter_sensitive  = false;

      int n = r.point_count;
      if(n<=0)
        {
         r.AddNote("Sweep produced no runnable points (all values out of domain, or empty request).");
         r.safe_to_adopt_best = false;
         return;
        }

      bool   has[GZ_MAX_ROBUSTNESS_POINTS];
      double val[GZ_MAX_ROBUSTNESS_POINTS];
      for(int i=0; i<n; i++)
        {
         has[i] = (r.points[i].result.metrics.trade.trade_count>0);
         val[i] = r.points[i].result.metrics.trade.expectancy;
        }

      //--- best_idx: highest expectancy among has[]==true points, ties by
      //--- distance-from-baseline then param_value ascending.
      for(int i=0; i<n; i++)
        {
         if(!has[i]) continue;
         if(r.best_idx==-1) { r.best_idx=i; continue; }
         bool better = false;
         if(val[i] > val[r.best_idx] + 0.0000001)
            better = true;
         else if(MathAbs(val[i]-val[r.best_idx])<=0.0000001)
           {
            double di = MathAbs(r.points[i].param_value        - r.baseline_value);
            double db = MathAbs(r.points[r.best_idx].param_value - r.baseline_value);
            if(di < db - 0.0000001)
               better = true;
            else if(MathAbs(di-db)<=0.0000001 && r.points[i].param_value<r.points[r.best_idx].param_value)
               better = true;
           }
         if(better) r.best_idx = i;
        }

      //--- NARROW_PEAK.
      if(r.best_idx>0 && r.best_idx<n-1 && has[r.best_idx-1] && has[r.best_idx+1])
        {
         double peak = val[r.best_idx];
         if(peak>0.0000001)
           {
            double thresh = peak*(1.0-GZ_ROBUST_NARROW_PEAK_DROP_PCT);
            if(val[r.best_idx-1]<thresh && val[r.best_idx+1]<thresh)
              {
               r.narrow_peak = true;
               r.AddNote(StringFormat("NARROW_PEAK at %s=%.4f (expectancy=%.3fR) - both neighbors drop below %.0f%% of the peak.",
                          r.param_label, r.points[r.best_idx].param_value, peak, (1.0-GZ_ROBUST_NARROW_PEAK_DROP_PCT)*100.0));
              }
           }
        }

      //--- FLAT_REGION: slide a window of GZ_ROBUST_FLAT_REGION_MIN_POINTS
      //--- consecutive points, stop at the first fully-valid window whose
      //--- own max-min is within tolerance of its own max.
      for(int start=0; start+GZ_ROBUST_FLAT_REGION_MIN_POINTS<=n; start++)
        {
         bool all_valid = true;
         double wmax=-1000000.0, wmin=1000000.0;
         for(int k=start; k<start+GZ_ROBUST_FLAT_REGION_MIN_POINTS; k++)
           {
            if(!has[k]) { all_valid=false; break; }
            if(val[k]>wmax) wmax=val[k];
            if(val[k]<wmin) wmin=val[k];
           }
         if(!all_valid) continue;
         double scale = MathMax(MathAbs(wmax), GZ_ROBUST_NOISE_FLOOR_R);
         if((wmax-wmin) <= GZ_ROBUST_FLAT_REGION_TOL_PCT*scale)
           {
            r.flat_region = true;
            r.AddNote(StringFormat("FLAT_REGION: %s in [%.4f, %.4f] - %d consecutive points within %.0f%% of each other's expectancy.",
                       r.param_label, r.points[start].param_value, r.points[start+GZ_ROBUST_FLAT_REGION_MIN_POINTS-1].param_value,
                       GZ_ROBUST_FLAT_REGION_MIN_POINTS, GZ_ROBUST_FLAT_REGION_TOL_PCT*100.0));
            break;
           }
        }

      //--- UNSTABLE_ZONE: consecutive-pair sign flips above the noise floor.
      int flips = 0;
      for(int i=0; i<n-1; i++)
        {
         if(!has[i] || !has[i+1]) continue;
         if(MathAbs(val[i])<GZ_ROBUST_NOISE_FLOOR_R || MathAbs(val[i+1])<GZ_ROBUST_NOISE_FLOOR_R) continue;
         bool pos_a = (val[i]>0.0);
         bool pos_b = (val[i+1]>0.0);
         if(pos_a!=pos_b) flips++;
        }
      if(flips>=GZ_ROBUST_UNSTABLE_SIGN_FLIPS_MIN)
        {
         r.unstable_zone = true;
         r.AddNote(StringFormat("UNSTABLE_ZONE: %d sign flips across the %s sweep - the curve is not a smooth function of this axis here.",
                    flips, r.param_label));
        }

      //--- PARAMETER_SENSITIVE: whole-sweep range vs |best|.
      double vmax=-1000000.0, vmin=1000000.0; int valid_count=0;
      for(int i=0; i<n; i++)
         if(has[i]) { valid_count++; if(val[i]>vmax) vmax=val[i]; if(val[i]<vmin) vmin=val[i]; }
      if(valid_count>=2)
        {
         double range = vmax-vmin;
         double scale = (r.best_idx>=0 && MathAbs(val[r.best_idx])>0.0000001) ? MathAbs(val[r.best_idx]) : GZ_ROBUST_PARAM_SENSITIVE_ABS_FLOOR;
         if(range > GZ_ROBUST_PARAM_SENSITIVE_RANGE_PCT*scale)
           {
            r.parameter_sensitive = true;
            r.AddNote(StringFormat("PARAMETER_SENSITIVE: expectancy ranges %.3fR to %.3fR across the %s sweep.",
                       vmin, vmax, r.param_label));
           }
        }

      r.safe_to_adopt_best = (r.best_idx>=0) && !r.narrow_peak && !r.unstable_zone;
      if(r.best_idx==-1)
         r.AddNote("No point in this sweep produced any trades - inconclusive, nothing to adopt.");
      else if(!r.safe_to_adopt_best)
         r.AddNote("Roadmap Phase 12: the single highest historical value must NOT be accepted alone - "+
                    "see narrow_peak/unstable_zone above before adopting "+r.param_label+"="+
                    DoubleToString(r.points[r.best_idx].param_value,4)+".");
     }
  };

#endif // __GZ_ROBUSTNESS_ENGINE_MQH__
