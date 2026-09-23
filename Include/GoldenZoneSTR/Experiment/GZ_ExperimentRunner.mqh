//+------------------------------------------------------------------+
//| GZ_ExperimentRunner.mqh                                           |
//| GoldenZone STR - Phase 9 - Experiment Configuration + Runner      |
//|                                                                    |
//| Research Adapter concern (Roadmap Phase 17 vocabulary, same as    |
//| CGZTradeSimulator/CGZMetricsEngine - see those files' headers):   |
//| drives the FULL Phase 2-8 pipeline (Swing -> Leg -> Break -> Setup |
//| -> Entry -> Exit -> Journal -> Event Ledger -> Metrics) once per   |
//| supplied GZ_ExperimentConfig, against already-loaded, already-     |
//| validated M1/M5 data (Phase 1's job - not repeated here, see       |
//| GZ_ExperimentTypes.mqh design note 4), and packages one            |
//| GZ_ExperimentResult per config. Every engine it drives is a fresh, |
//| local instance per experiment - no state leaks between experiments |
//| in a SWEEP/GRID/BATCH run (each one gets its own Leg/Break/Setup/  |
//| Entry/Exit/Journal/Ledger engines, exactly like T54/T64/T74/T86's  |
//| own two-independent-runs determinism tests already prove for the   |
//| underlying pipeline).                                              |
//|                                                                    |
//| See GZ_ExperimentTypes.mqh for the full set of documented scope    |
//| decisions (config reuse, modes-are-a-label, ID format, caller-      |
//| supplied dataset ID/validation status, bounded warnings).           |
//+------------------------------------------------------------------+
#ifndef __GZ_EXPERIMENT_RUNNER_MQH__
#define __GZ_EXPERIMENT_RUNNER_MQH__

#include "GZ_ExperimentTypes.mqh"
#include "..\Structure\GZ_StructureTypes.mqh"
#include "..\Structure\GZ_SwingEngine.mqh"
#include "..\Leg\GZ_LegEngine.mqh"
#include "..\Leg\GZ_BreakEngine.mqh"
#include "..\Setup\GZ_SetupStateMachine.mqh"
#include "..\Entry\GZ_EntryEngine.mqh"
#include "..\Entry\GZ_TradeSimulator.mqh"
#include "..\Exit\GZ_ExitEngine.mqh"
#include "..\Journal\GZ_JournalEngine.mqh"
#include "..\Journal\GZ_EventLedger.mqh"
#include "..\Metrics\GZ_MetricsEngine.mqh"
#include "..\Time\GZ_TimeEngine.mqh"
#include "..\Time\GZ_Session.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZExperimentRunner
  {
private:
   CGZLogger        *m_logger;
   long              m_next_seq;        // sequential experiment id counter - see design note 3
   int               m_max_batch_size;  // Roadmap "stage research, don't run one huge Grid" cap

   string NextId()
     {
      string id = StringFormat("GZ_%06d", (int)m_next_seq);
      m_next_seq++;
      return id;
     }

   //--- Core single-config execution: fresh, local engines every call
   //--- (see header - no cross-experiment state leakage), then packages
   //--- a GZ_ExperimentResult. RunSingle()/RunBatch() are the public
   //--- entry points; this is not exposed directly so every experiment
   //--- - whichever mode requested it - goes through the exact same
   //--- code path (design note 2, GZ_ExperimentTypes.mqh).
   void Execute(const GZ_ExperimentConfig &cfg, const MqlRates &m1[], const MqlRates &m5[],
                string dataset_id, ENUM_GZ_VALIDATION_STATUS m1_status, ENUM_GZ_VALIDATION_STATUS m5_status,
                GZ_ExperimentResult &out)
     {
      out.Clear();
      out.id                   = NextId();
      out.dataset_id           = dataset_id;
      out.config               = cfg;
      out.strategy_version     = GZ_STRATEGY_VERSION;
      out.m1_validation_status = m1_status;
      out.m5_validation_status = m5_status;

      int n5 = ArraySize(m5);
      if(n5==0)
        {
         out.AddWarning("NO_M5_DATA");
         if(m_logger!=NULL)
            m_logger.Warning("Experiment", StringFormat("%s: no M5 data supplied - experiment skipped.", out.id));
         return;
        }

      out.range_start = m5[0].time;
      out.range_end   = m5[n5-1].time;

      if(!cfg.time_config.broker_offset_known)
         out.AddWarning("BROKER_OFFSET_UNKNOWN");

      CGZSwingEngine swing_engine(m_logger);
      swing_engine.Init(cfg.pivot_strength);
      GZ_Swing swings[];
      int swing_count = swing_engine.DetectAll(m5, swings);
      out.swing_count = swing_count;
      if(swing_count==0)
         out.AddWarning("NO_SWINGS_DETECTED");

      CGZLegEngine          leg_engine(m_logger);   leg_engine.Init(cfg.leg_variant);
      CGZBreakEngine        break_engine(m_logger);  break_engine.Configure(cfg.break_config);
      CGZSetupStateMachine  setup_sm(m_logger);      setup_sm.Init(cfg.fib_zone_min_ratio, cfg.fib_zone_max_ratio);
      CGZEntryEngine        entry_engine(m_logger);  entry_engine.Init(cfg.entry_config);
      CGZExitEngine         exit_engine(m_logger);   exit_engine.Init(cfg.exit_config);
      CGZJournalEngine      journal_engine(m_logger);journal_engine.Init();
      CGZEventLedger        event_ledger(m_logger);  event_ledger.Init();
      CGZTimeEngine         time_engine(m_logger);   time_engine.Configure(cfg.time_config);
      CGZSessionEngine      session_engine;
      CGZTradeSimulator     simulator(m_logger);

      simulator.Run(m1, m5, swings, swing_count, leg_engine, break_engine, setup_sm, entry_engine, exit_engine,
                     journal_engine, event_ledger, time_engine, session_engine, cfg.session_profile,
                     cfg.apply_session_filter, cfg.force_session_exit);

      out.leg_count   = leg_engine.LegCount();
      out.setup_count = setup_sm.SetupCount();
      out.trade_count = entry_engine.TradeCount();
      out.exit_count  = exit_engine.ExitCount();

      CGZMetricsEngine metrics_engine(m_logger);
      metrics_engine.Compute(journal_engine, time_engine, session_engine, cfg.session_profile, out.metrics);

      if(out.trade_count==0)
         out.AddWarning("NO_TRADES_PRODUCED");

      if(m_logger!=NULL)
         m_logger.Info("Experiment", StringFormat(
            "%s: swings=%d legs=%d setups=%d trades=%d exits=%d net_r=%.3f win_rate=%.1f%% warnings=%d",
            out.id, out.swing_count, out.leg_count, out.setup_count, out.trade_count, out.exit_count,
            out.metrics.trade.net_r, out.metrics.trade.win_rate*100.0, out.warning_count));
     }

public:
                     CGZExperimentRunner(CGZLogger *logger=NULL)
     {
      m_logger         = logger;
      m_next_seq       = 1;
      m_max_batch_size = GZ_DEFAULT_MAX_EXPERIMENT_BATCH_SIZE;
     }

   void              SetMaxBatchSize(int max_size) { m_max_batch_size = (max_size>0) ? max_size : GZ_DEFAULT_MAX_EXPERIMENT_BATCH_SIZE; }
   int               MaxBatchSize()  const { return m_max_batch_size; }
   long              NextSequence()  const { return m_next_seq; } // diagnostic/testing accessor - next id that WILL be assigned

   //--- SINGLE mode (Roadmap) - exactly one config in, exactly one
   //--- result out.
   void              RunSingle(const GZ_ExperimentConfig &cfg, const MqlRates &m1[], const MqlRates &m5[],
                                string dataset_id, ENUM_GZ_VALIDATION_STATUS m1_status, ENUM_GZ_VALIDATION_STATUS m5_status,
                                GZ_ExperimentResult &out)
     {
      Execute(cfg, m1, m5, dataset_id, m1_status, m5_status, out);
     }

   //--- SWEEP/GRID/BATCH modes (Roadmap) - architecturally identical
   //--- (design note 2, GZ_ExperimentTypes.mqh): `mode` only records
   //--- which the caller intended, for the result's own bookkeeping: it
   //--- does not change execution. Enforces the Roadmap's own staging
   //--- rule ("از Grid عظیم همزمان استفاده نشود؛ Research مرحله‌ای
   //--- باشد") as an actual cap - `configs` exceeding MaxBatchSize() is
   //--- REJECTED outright (results[] resized to 0, NOTHING executed,
   //--- m_next_seq untouched) rather than silently truncated or
   //--- partially run; raise the cap explicitly via SetMaxBatchSize()
   //--- or split the batch yourself if you actually intend to run that
   //--- many at once.
   ENUM_GZ_BATCH_STATUS RunBatch(const GZ_ExperimentConfig &configs[], int count, ENUM_GZ_EXPERIMENT_MODE mode,
                                  const MqlRates &m1[], const MqlRates &m5[], string dataset_id,
                                  ENUM_GZ_VALIDATION_STATUS m1_status, ENUM_GZ_VALIDATION_STATUS m5_status,
                                  GZ_ExperimentResult &results[])
     {
      ArrayResize(results, 0);

      if(count<=0)
        {
         if(m_logger!=NULL)
            m_logger.Warning("Experiment", "RunBatch: empty config list - nothing to run.");
         return GZ_BATCH_REJECTED_EMPTY;
        }

      if(count>m_max_batch_size)
        {
         if(m_logger!=NULL)
            m_logger.Error("Experiment", StringFormat(
               "RunBatch(%s): %d configs exceeds max batch size %d - REJECTED (Roadmap Phase 9: stage research, "+
               "don't run one huge Grid at once). Call SetMaxBatchSize() to raise the cap, or split into smaller batches.",
               EnumToString(mode), count, m_max_batch_size));
         return GZ_BATCH_REJECTED_TOO_LARGE;
        }

      ArrayResize(results, count);
      for(int i=0;i<count;i++)
         Execute(configs[i], m1, m5, dataset_id, m1_status, m5_status, results[i]);

      if(m_logger!=NULL)
         m_logger.Info("Experiment", StringFormat("RunBatch(%s): %d configs executed -> %d results.",
                        EnumToString(mode), count, ArraySize(results)));
      return GZ_BATCH_OK;
     }
  };

#endif // __GZ_EXPERIMENT_RUNNER_MQH__
