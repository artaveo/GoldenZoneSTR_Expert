//+------------------------------------------------------------------+
//| GZ_FilterComboEngine.mqh                                          |
//| GoldenZone STR - Phase 11 - Filter Combination Research           |
//|                                                                    |
//| Research Adapter concern (Roadmap Phase 17 vocabulary, same as     |
//| CGZExperimentRunner/CGZMetricsEngine - see those files' headers):  |
//| builds and runs GZ_FilterSetConfig sweeps over an ALREADY-FINAL     |
//| setup/trade population (Phase 2-9's own output - not re-simulated  |
//| here, see GZ_FilterComboTypes.mqh design note 2), using Phase 10's  |
//| own CGZFilterEngine + CGZMetricsEngine::ComputeFiltered() for every |
//| single evaluation - Phase 11 adds NO new gating/metric logic of its |
//| own, only the R11-A/B/C request-building and batch-running around   |
//| that already-tested mechanism (T97-T106 already cover the gating     |
//| logic itself; T107+ below cover only the NEW combination-building    |
//| and batch behavior - see GZ_TestHarness.mqh).                        |
//|                                                                    |
//| See GZ_FilterComboTypes.mqh for the full set of documented scope   |
//| decisions (why no re-simulation, reconstructability, reserved-filter|
//| handling, the R11-C ranking rule).                                  |
//+------------------------------------------------------------------+
#ifndef __GZ_FILTER_COMBO_ENGINE_MQH__
#define __GZ_FILTER_COMBO_ENGINE_MQH__

#include "GZ_FilterComboTypes.mqh"
#include "GZ_FilterEngine.mqh"
#include "..\Setup\GZ_SetupTypes.mqh"
#include "..\Journal\GZ_JournalEngine.mqh"
#include "..\Metrics\GZ_MetricsEngine.mqh"
#include "..\Time\GZ_TimeEngine.mqh"
#include "..\Time\GZ_Session.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZFilterComboEngine
  {
private:
   CGZLogger        *m_logger;
   long              m_next_seq;        // sequential combo id counter - mirrors GZ_ExperimentTypes.mqh design note 3
   int               m_max_batch_size;  // Roadmap "stage research, don't run one huge Grid" cap (Phase 9's own rule, reapplied here)

   string NextId()
     {
      string id = StringFormat("R11_%06d", (int)m_next_seq);
      m_next_seq++;
      return id;
     }

   bool IsReservedFilter(ENUM_GZ_FILTER_ID id) const
     {
      return (id==GZ_FILTER_VWAP || id==GZ_FILTER_M15_CONTEXT || id==GZ_FILTER_NEWS);
     }

   string FilterShortName(ENUM_GZ_FILTER_ID id) const { return GZFilterIdToString(id); }

   //--- Core single-combination execution (design note 1/2,
   //--- GZ_FilterComboTypes.mqh): evaluate `cfg` against every supplied
   //--- setup (fresh, local CGZFilterEngine/CGZMetricsEngine instances -
   //--- no cross-call state, same "no state leaks" discipline
   //--- CGZExperimentRunner::Execute() already documents), join onto the
   //--- journal via setup_id (identical mask-building the EA's own Phase
   //--- 10 block already performs inline - see GoldenZoneSTR_Research.mq5),
   //--- then diff against the caller-supplied unfiltered baseline.
   void Execute(const GZ_FilterSetConfig &cfg, ENUM_GZ_FILTER_COMBO_STAGE stage, string label,
                const GZ_Setup &setups[], int setup_count, const MqlRates &m5[],
                CGZJournalEngine &journal_engine, CGZTimeEngine &time_engine, CGZSessionEngine &session_engine,
                const GZ_SessionProfile &session_profile, const GZ_MetricsSummary &baseline_metrics,
                GZ_FilterComboResult &out)
     {
      out.Clear();
      out.id    = NextId();
      out.stage = stage;
      out.label = label;
      out.config = cfg;

      for(int i=0;i<GZ_FILTER_COUNT;i++)
        {
         if(cfg.mode[i]==GZ_FILTER_OFF)
            continue;
         out.filter_ids[out.filter_count] = (ENUM_GZ_FILTER_ID)i;
         out.filter_count++;
         if(IsReservedFilter((ENUM_GZ_FILTER_ID)i))
            out.reserved_filter_used = true;
        }
      if(out.reserved_filter_used)
         out.AddWarning("RESERVED_FILTER_ALWAYS_REJECTS"); // design note 4, GZ_FilterComboTypes.mqh

      CGZFilterEngine filter_engine(m_logger);

      long setup_ids[];
      bool setup_pass[];
      ArrayResize(setup_ids, setup_count);
      ArrayResize(setup_pass, setup_count);
      int setups_after = 0;
      for(int si=0; si<setup_count; si++)
        {
         GZ_SetupFilterOutcome outcome;
         filter_engine.Evaluate(setups[si], m5, cfg, time_engine, session_engine, outcome);
         setup_ids[si]  = setups[si].id;
         setup_pass[si] = outcome.overall_pass;
         if(outcome.overall_pass)
            setups_after++;
        }

      int jn = journal_engine.JournalCount();
      bool mask[];
      ArrayResize(mask, jn);
      int rejections = 0;
      for(int ji=0; ji<jn; ji++)
        {
         GZ_TradeJournal j = journal_engine.GetJournal(ji);
         bool pass = true; // defensive default - a journal entry whose setup is not found stays included (mirrors the EA's own Phase 10 block)
         for(int sk=0; sk<setup_count; sk++)
            if(setup_ids[sk]==j.setup_id) { pass = setup_pass[sk]; break; }
         mask[ji] = pass;
         if(!j.is_open && !pass)
            rejections++;
        }

      CGZMetricsEngine metrics_engine(m_logger);
      metrics_engine.ComputeFiltered(journal_engine, time_engine, session_engine, session_profile, mask, out.metrics_with);

      out.diagnostics.available     = true;
      out.diagnostics.setups_before = setup_count;
      out.diagnostics.setups_after  = setups_after;
      out.diagnostics.trades_before = baseline_metrics.trade.trade_count;
      out.diagnostics.trades_after  = out.metrics_with.trade.trade_count;
      out.diagnostics.rejections    = rejections;
      out.diagnostics.win_rate_delta      = out.metrics_with.trade.win_rate      - baseline_metrics.trade.win_rate;
      out.diagnostics.profit_factor_delta = out.metrics_with.trade.profit_factor - baseline_metrics.trade.profit_factor;
      out.diagnostics.expectancy_delta    = out.metrics_with.trade.expectancy    - baseline_metrics.trade.expectancy;
      out.diagnostics.max_drawdown_delta  = out.metrics_with.risk.max_drawdown_r - baseline_metrics.risk.max_drawdown_r;
      out.diagnostics.trade_count_delta   = out.metrics_with.trade.trade_count   - baseline_metrics.trade.trade_count;

      if(out.metrics_with.trade.trade_count==0)
         out.AddWarning("NO_TRADES_AFTER_FILTER");

      if(m_logger!=NULL)
         m_logger.Info("FilterCombo", StringFormat(
            "%s [%s] %s: setups_after=%d/%d trades_after=%d/%d expectancy_delta=%.4f pf_delta=%.4f",
            out.id, GZFilterComboStageToString(stage), label, setups_after, setup_count,
            out.metrics_with.trade.trade_count, baseline_metrics.trade.trade_count,
            out.diagnostics.expectancy_delta, out.diagnostics.profit_factor_delta));
     }

public:
                     CGZFilterComboEngine(CGZLogger *logger=NULL)
     {
      m_logger         = logger;
      m_next_seq       = 1;
      m_max_batch_size = GZ_DEFAULT_MAX_FILTER_COMBO_BATCH_SIZE;
     }

   void              SetMaxBatchSize(int max_size) { m_max_batch_size = (max_size>0) ? max_size : GZ_DEFAULT_MAX_FILTER_COMBO_BATCH_SIZE; }
   int               MaxBatchSize()  const { return m_max_batch_size; }
   long              NextSequence()  const { return m_next_seq; }

   //--- R11-A: Single Filter (Roadmap). One request per IMPLEMENTED,
   //--- non-reserved filter (Break Quality/Leg Quality/Volume/
   //--- Volatility/Session), each turned INCLUDE alone (every other
   //--- filter OFF), reusing base_cfg's own thresholds/session window
   //--- unchanged. include_reserved (default false, design note 4) also
   //--- appends VWAP/M15 Context/News - documented to deterministically
   //--- reject every setup in THIS build, never run by default.
   int BuildR11ASingleRequests(const GZ_FilterSetConfig &base_cfg, GZ_FilterComboRequest &out[], bool include_reserved=false)
     {
      ArrayResize(out, 0);
      for(int i=0;i<GZ_FILTER_COUNT;i++)
        {
         ENUM_GZ_FILTER_ID id = (ENUM_GZ_FILTER_ID)i;
         if(IsReservedFilter(id) && !include_reserved)
            continue;
         int n = ArraySize(out);
         ArrayResize(out, n+1);
         out[n].Clear();
         out[n].stage  = GZ_COMBO_R11A_SINGLE;
         out[n].label  = FilterShortName(id);
         out[n].config = base_cfg;
         for(int k=0;k<GZ_FILTER_COUNT;k++)
            out[n].config.mode[k] = GZ_FILTER_OFF;
         out[n].config.mode[i] = GZ_FILTER_INCLUDE;
        }
      return ArraySize(out);
     }

   //--- R11-B: Two-Filter (Roadmap named pairs + "ترکیبات قابل توجیه
   //--- دیگر" - other justifiable combinations, documented below). Each
   //--- pair is built the same way as R11-A: exactly those two filters
   //--- INCLUDE, everything else OFF. Pairs naming a reserved filter are
   //--- built but SKIPPED unless include_reserved=true (design note 4) -
   //--- the pair list itself still names them (architecture stays
   //--- extensible per spec Section 3) so nothing needs rewriting once a
   //--- later phase supplies real VWAP/M15/News data.
   //---
   //--- Roadmap-named pairs (R11-B): Break Quality x Volume, Break
   //--- Quality x VWAP, Leg Quality x Volume, Volume x VWAP, Volume x
   //--- Volatility, VWAP x M15 Context.
   //--- Additional justified pairs (documented choice, no Roadmap
   //--- baseline stated - same "documented, not silently assumed"
   //--- pattern as every other undetermined Phase 11 default): Break
   //--- Quality x Leg Quality (both measure the SAME leg's structural
   //--- soundness from two angles), Break Quality x Volatility, Leg
   //--- Quality x Volatility (a leg/break's size relative to two
   //--- different volatility baselines), Break Quality x Session, Volume
   //--- x Session (the two non-quality/non-volatility gates paired with
   //--- the venue/time gate).
   int BuildR11BTwoFilterRequests(const GZ_FilterSetConfig &base_cfg, GZ_FilterComboRequest &out[], bool include_reserved=false)
     {
      ArrayResize(out, 0);

      ENUM_GZ_FILTER_ID pairs_a[11] =
        {
         GZ_FILTER_BREAK_QUALITY, GZ_FILTER_BREAK_QUALITY, GZ_FILTER_LEG_QUALITY, GZ_FILTER_VOLUME,
         GZ_FILTER_VOLUME,        GZ_FILTER_VWAP,          GZ_FILTER_BREAK_QUALITY, GZ_FILTER_BREAK_QUALITY,
         GZ_FILTER_LEG_QUALITY,   GZ_FILTER_BREAK_QUALITY, GZ_FILTER_VOLUME
        };
      ENUM_GZ_FILTER_ID pairs_b[11] =
        {
         GZ_FILTER_VOLUME,      GZ_FILTER_VWAP,        GZ_FILTER_VOLUME,      GZ_FILTER_VWAP,
         GZ_FILTER_VOLATILITY,  GZ_FILTER_M15_CONTEXT, GZ_FILTER_LEG_QUALITY, GZ_FILTER_VOLATILITY,
         GZ_FILTER_VOLATILITY,  GZ_FILTER_SESSION,     GZ_FILTER_SESSION
        };

      for(int p=0;p<11;p++)
        {
         ENUM_GZ_FILTER_ID a = pairs_a[p];
         ENUM_GZ_FILTER_ID b = pairs_b[p];
         if((IsReservedFilter(a) || IsReservedFilter(b)) && !include_reserved)
            continue;

         int n = ArraySize(out);
         ArrayResize(out, n+1);
         out[n].Clear();
         out[n].stage  = GZ_COMBO_R11B_TWO;
         out[n].label  = FilterShortName(a)+"+"+FilterShortName(b);
         out[n].config = base_cfg;
         for(int k=0;k<GZ_FILTER_COUNT;k++)
            out[n].config.mode[k] = GZ_FILTER_OFF;
         out[n].config.mode[a] = GZ_FILTER_INCLUDE;
         out[n].config.mode[b] = GZ_FILTER_INCLUDE;
        }
      return ArraySize(out);
     }

   //--- R11-C: Multi-Filter, limited, based only on previous stages'
   //--- results (design note 5, GZ_FilterComboTypes.mqh). Ranks the
   //--- SUPPLIED R11-A results (implemented/non-reserved filters only -
   //--- a reserved filter's single-filter result is a trivial all-reject
   //--- and never graduates) by expectancy_delta descending, ties broken
   //--- by ENUM_GZ_FILTER_ID ascending, then builds ONE combo per size
   //--- from 3 up to top_n (bounded: top_n-2 combos total, e.g. default
   //--- top_n=4 -> exactly 2 combos: top-3 and top-4 ranked filters).
   //--- top_n is clamped to [3, number of ranked candidates].
   int BuildR11CMultiFilterRequests(const GZ_FilterComboResult &r11a_results[], int r11a_count,
                                     const GZ_FilterSetConfig &base_cfg, GZ_FilterComboRequest &out[], int top_n=4)
     {
      ArrayResize(out, 0);

      //--- Collect eligible single-filter candidates (exactly one
      //--- non-reserved filter enabled, stage==R11-A) with their
      //--- expectancy_delta, for ranking.
      ENUM_GZ_FILTER_ID cand_id[GZ_FILTER_COUNT];
      double            cand_score[GZ_FILTER_COUNT];
      int               cand_count = 0;
      for(int i=0;i<r11a_count;i++)
        {
         if(r11a_results[i].stage!=GZ_COMBO_R11A_SINGLE) continue;
         if(r11a_results[i].filter_count!=1) continue;
         ENUM_GZ_FILTER_ID id = r11a_results[i].filter_ids[0];
         if(IsReservedFilter(id)) continue; // design note 4/5 - never a ranking winner
         cand_id[cand_count]    = id;
         cand_score[cand_count] = r11a_results[i].diagnostics.expectancy_delta;
         cand_count++;
        }

      //--- Deterministic sort: score descending, ties by filter id
      //--- ascending (simple insertion sort - cand_count is at most
      //--- GZ_FILTER_COUNT-3=5, no need for anything fancier).
      for(int i=1;i<cand_count;i++)
        {
         ENUM_GZ_FILTER_ID id_i = cand_id[i];
         double            sc_i = cand_score[i];
         int j = i-1;
         while(j>=0 && (cand_score[j]<sc_i || (cand_score[j]==sc_i && cand_id[j]>id_i)))
           {
            cand_id[j+1]    = cand_id[j];
            cand_score[j+1] = cand_score[j];
            j--;
           }
         cand_id[j+1]    = id_i;
         cand_score[j+1] = sc_i;
        }

      int clamped_top_n = top_n;
      if(clamped_top_n>cand_count) clamped_top_n = cand_count;
      if(clamped_top_n<3) return 0; // not enough ranked candidates for a "multi" (3+) combo - nothing to build

      for(int size=3; size<=clamped_top_n; size++)
        {
         int n = ArraySize(out);
         ArrayResize(out, n+1);
         out[n].Clear();
         out[n].stage  = GZ_COMBO_R11C_MULTI;
         out[n].config = base_cfg;
         for(int k=0;k<GZ_FILTER_COUNT;k++)
            out[n].config.mode[k] = GZ_FILTER_OFF;
         string label = "";
         for(int r=0;r<size;r++)
           {
            out[n].config.mode[cand_id[r]] = GZ_FILTER_INCLUDE;
            label += (r>0?"+":"") + FilterShortName(cand_id[r]);
           }
         out[n].label = StringFormat("TOP%d[%s]", size, label);
        }
      return ArraySize(out);
     }

   //--- Execute a planned batch of requests (any stage mix) against one
   //--- already-final setup/trade population. Enforces the same "stage
   //--- research, don't run one huge Grid at once" cap
   //--- CGZExperimentRunner::RunBatch() already enforces (design note 1) -
   //--- REJECTED outright (results resized to 0, nothing executed,
   //--- m_next_seq untouched) rather than silently truncated.
   ENUM_GZ_FILTER_COMBO_BATCH_STATUS RunBatch(const GZ_FilterComboRequest &requests[], int count,
                                               const GZ_Setup &setups[], int setup_count, const MqlRates &m5[],
                                               CGZJournalEngine &journal_engine, CGZTimeEngine &time_engine,
                                               CGZSessionEngine &session_engine, const GZ_SessionProfile &session_profile,
                                               const GZ_MetricsSummary &baseline_metrics, GZ_FilterComboResult &results[])
     {
      ArrayResize(results, 0);

      if(count<=0)
        {
         if(m_logger!=NULL)
            m_logger.Warning("FilterCombo", "RunBatch: empty request list - nothing to run.");
         return GZ_COMBO_BATCH_REJECTED_EMPTY;
        }

      if(count>m_max_batch_size)
        {
         if(m_logger!=NULL)
            m_logger.Error("FilterCombo", StringFormat(
               "RunBatch: %d requests exceeds max batch size %d - REJECTED (Roadmap: stage research, "+
               "don't run one huge Grid at once). Call SetMaxBatchSize() to raise the cap, or split into smaller batches.",
               count, m_max_batch_size));
         return GZ_COMBO_BATCH_REJECTED_TOO_LARGE;
        }

      ArrayResize(results, count);
      for(int i=0;i<count;i++)
         Execute(requests[i].config, requests[i].stage, requests[i].label, setups, setup_count, m5,
                 journal_engine, time_engine, session_engine, session_profile, baseline_metrics, results[i]);

      if(m_logger!=NULL)
         m_logger.Info("FilterCombo", StringFormat("RunBatch: %d requests executed -> %d results.", count, ArraySize(results)));
      return GZ_COMBO_BATCH_OK;
     }
  };

#endif // __GZ_FILTER_COMBO_ENGINE_MQH__
