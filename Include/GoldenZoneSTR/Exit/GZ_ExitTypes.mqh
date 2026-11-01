//+------------------------------------------------------------------+
//| GZ_ExitTypes.mqh                                                  |
//| GoldenZone STR - Phase 6 - Exit Engine (SL/TP/BE) - Types         |
//|                                                                    |
//| Shared enums/structs for exit management. This file contains NO   |
//| exit-decision logic (see GZ_ExitEngine.mqh) and NO MAE/MFE/R-path |
//| /event-ledger logic (Phase 7+). Types only.                       |
//|                                                                    |
//| DESIGN NOTES (documented per spec Section 26 - the Roadmap        |
//| describes Phase 6 at a feature level, same situation as every     |
//| phase since Phase 3):                                              |
//|                                                                    |
//| 1) GZ_TradeExit is a SEPARATE struct from Phase 5's GZ_Trade,     |
//|    keyed by trade_id, rather than new fields bolted onto GZ_Trade |
//|    itself. Phase 5's GZ_Trade is a tested, working interface -    |
//|    this repo's established discipline (see GZ_SetupTypes.mqh's   |
//|    own design note) is that an earlier phase's frozen type is     |
//|    either left untouched or, when it anticipated a stub for this  |
//|    phase, that stub is wired up (GZ_SETUP_ENTERED was exactly     |
//|    this in Phase 5). GZ_Trade left no such stub for exit fields,  |
//|    so Phase 6 adds its own record instead of mutating Phase 5's   |
//|    file - one CGZExitEngine instance produces exactly one         |
//|    GZ_TradeExit per GZ_Trade, in the same order, joinable by id.  |
//|                                                                    |
//| 2) initial_risk. Phase 5 reserved GZ_Trade.initial_risk at 0.0    |
//|    specifically because it needs a stop-loss price (see           |
//|    GZ_EntryTypes.mqh design note 2). GZ_TradeExit.initial_risk is |
//|    the real value (|entry_price - sl_price|, fixed the instant    |
//|    the trade enters) - callers that want the true initial risk    |
//|    once Phase 6 exists should read it from here.                  |
//|                                                                    |
//| 3) Intrabar SL/TP conflict (Roadmap: "if a single M1 bar touches  |
//|    both SL and TP with no way to know the true intrabar order:    |
//|    record the ambiguity, make the resolution policy configurable, |
//|    never bake in a silent assumed order"). intrabar_conflict is   |
//|    always recorded (true) whenever a single evaluated bar's range |
//|    touches both levels, REGARDLESS of which policy resolved it -  |
//|    the flag is the "ambiguity was recorded" part; intrabar_       |
//|    conflict_policy in GZ_ExitConfig is the "resolution policy is  |
//|    configurable" part. Neither is ever silently skipped.          |
//|                                                                    |
//| 4) BREAK_EVEN vs SL_HIT. Mechanically both close the trade at the |
//|    active stop price, but the Roadmap lists BREAK_EVEN as its own |
//|    Exit Reason distinct from SL_HIT. GZ_ExitEngine assigns        |
//|    BREAK_EVEN whenever the stop that got hit is the BE-adjusted   |
//|    one (be_triggered already true at the time of the hit);        |
//|    SL_HIT is reserved for a stop hit that was never BE-adjusted.  |
//|                                                                    |
//| 5) realized_r is the trade's terminal signed R-multiple outcome   |
//|    only (0.0 while still open) - a single scalar, not a path. The |
//|    Roadmap's full "R-multiple path" / running MAE/MFE tracking is |
//|    explicitly Phase 7 scope (MAE/MFE + R-Path + Event Ledger) and |
//|    is NOT implemented here.                                        |
//+------------------------------------------------------------------+
#ifndef __GZ_EXIT_TYPES_MQH__
#define __GZ_EXIT_TYPES_MQH__

#include "..\Leg\GZ_LegTypes.mqh"

//--- Stop-loss model (Roadmap Phase 6) ------------------------------------
enum ENUM_GZ_SL_MODEL
  {
   GZ_SL_STRUCTURE = 0,   // baseline: Leg Origin +/- buffer (ATR multiples)
   GZ_SL_ATR              // ATR-based: entry price +/- configurable ATR multiple
  };

//--- Break-even stop level (Roadmap: "Entry" or "Entry +/- configurable R offset")
enum ENUM_GZ_BE_LEVEL_MODE
  {
   GZ_BE_LEVEL_ENTRY = 0,
   GZ_BE_LEVEL_ENTRY_OFFSET
  };

//--- Intrabar SL/TP conflict resolution policy (Roadmap: "policy configurable")
enum ENUM_GZ_INTRABAR_CONFLICT_POLICY
  {
   GZ_CONFLICT_SL_FIRST = 0,  // baseline: conservative - assume the worse outcome
   GZ_CONFLICT_TP_FIRST       // optimistic - assume the better outcome
  };

//--- What the exit engine may believe about the bar a trade ENTERED on.
//--- OHLC data cannot say WHEN inside the bar the fill happened, so the
//--- part of the bar that came BEFORE the fill must never decide the trade:
//---   GZ_ENTRY_BAR_LEGACY - the whole bar (high AND low) is evaluated, exactly
//---                         like every result produced before this option
//---                         existed. Optimistic: a favorable extreme that
//---                         printed BEFORE the fill can hit the TP. The error
//---                         grows with bar size (small on M1, large on M5/M15).
//---   GZ_ENTRY_BAR_SAFE   - only what is PROVABLY after the fill is used (see
//---                         GZEntryBarView below). The default of the EA.
enum ENUM_GZ_ENTRY_BAR_RULE
  {
   GZ_ENTRY_BAR_LEGACY = 0,
   GZ_ENTRY_BAR_SAFE   = 1
  };

//--- The view of the FILL BAR that is provably after the fill.
//---   adverse_ok - the bar's ADVERSE extreme (low for a long, high for a short)
//---                is after the fill. True for TOUCH/LIMIT: the fill happens the
//---                first time price crosses the entry level on its way to that
//---                extreme, so the extreme cannot have printed earlier.
//---   close_ok   - the bar's CLOSE is after the fill (true for TOUCH/LIMIT).
//---   Both false = the fill IS the bar's close (confirmation models): nothing
//---                inside that bar is after the fill.
//--- The FAVORABLE extreme (high for a long, low for a short) is NOT provably
//--- after the fill (it may have printed before it), so it is never used; the
//--- only favorable evidence allowed is the close. Every SL/TP/BE decision on
//--- the entry bar is made on this reduced view.
void GZEntryBarView(const MqlRates &bar, bool bullish, double entry_price,
                    bool adverse_ok, bool close_ok, double &eff_high, double &eff_low)
  {
   if(bullish)
     {
      eff_low  = adverse_ok ? MathMin(entry_price, bar.low) : entry_price;
      eff_high = close_ok   ? MathMax(entry_price, bar.close) : entry_price;
     }
   else
     {
      eff_high = adverse_ok ? MathMax(entry_price, bar.high) : entry_price;
      eff_low  = close_ok   ? MathMin(entry_price, bar.close) : entry_price;
     }
  }

//--- Exit reason (Roadmap Phase 6 list) -----------------------------------
enum ENUM_GZ_EXIT_REASON
  {
   GZ_EXIT_NONE = 0,     // still open
   GZ_EXIT_TP_HIT,
   GZ_EXIT_SL_HIT,
   GZ_EXIT_BREAK_EVEN,
   GZ_EXIT_SESSION_EXIT,
   GZ_EXIT_DATA_END,
   GZ_EXIT_OTHER          // reserved; never assigned in this build (no trigger defined by the Roadmap for it yet)
  };

//+------------------------------------------------------------------+
//| Exit Engine configuration.                                       |
//| sl_buffer_atr_mult: STRUCTURE model only, buffer beyond the leg's |
//|   origin price, in ATR multiples. Baseline 0.0 (no buffer),       |
//|   mirroring the Break Engine's own buffer default (GZ_Constants). |
//| sl_atr_mult: ATR model only, SL distance from entry price, in ATR |
//|   multiples. No Roadmap baseline stated - 1.5 used as the         |
//|   conventional default (documented, not silently assumed, same   |
//|   pattern as GZ_DEFAULT_ATR_PERIOD in Phase 3).                   |
//| tp_r_multiple: research grid 0.5R-5R (Roadmap), extensible above. |
//|   No single Roadmap baseline stated - 2.0R used as the            |
//|   conventional default (documented).                              |
//| be_trigger_r: 0.0 = OFF (Roadmap's own "OFF" grid value); any     |
//|   other value is the R-multiple of favorable excursion that arms  |
//|   break-even.                                                      |
//| ATR itself is NOT owned here - fed from the shared Break Engine   |
//| ATR (Phase 3), the same pattern already used by Phase 5's         |
//| GZ_EntryConfig - one shared deterministic ATR source.             |
//+------------------------------------------------------------------+
struct GZ_ExitConfig
  {
   ENUM_GZ_SL_MODEL     sl_model;
   double               sl_buffer_atr_mult;
   double               sl_atr_mult;
   double               tp_r_multiple;
   double               be_trigger_r;
   ENUM_GZ_BE_LEVEL_MODE be_level_mode;
   double               be_level_offset_r;
   ENUM_GZ_INTRABAR_CONFLICT_POLICY intrabar_conflict_policy;

   //--- Phase FCIS Step 2 (real bid/ask fills). Default false/0.01 = exact
   //--- pre-FCIS behavior (bars are bid-based, SL/TP/BE always evaluated and
   //--- filled on bid). See GZ_ExitEngine.mqh::OnBar() for the exact rule
   //--- (spec Section 5.2): a Short's close (Buy) checks/fills at the ask of
   //--- the relevant M1 candle; a Long's close (Sell) is unaffected.
   bool                 use_real_spread_fills;
   double               point;
   //--- Entry-bar rule (see ENUM_GZ_ENTRY_BAR_RULE). Default() keeps LEGACY so every
   //--- existing synthetic test and any caller that does not set it is unchanged;
   //--- the EA input InpEntryBarExitRule (default SAFE) sets the real value.
   ENUM_GZ_ENTRY_BAR_RULE entry_bar_rule;

   void Default()
     {
      sl_model                 = GZ_SL_STRUCTURE;
      sl_buffer_atr_mult        = 0.0;
      sl_atr_mult               = 1.5;
      tp_r_multiple             = 2.0;
      be_trigger_r              = 0.0; // OFF
      be_level_mode             = GZ_BE_LEVEL_ENTRY;
      be_level_offset_r         = 0.0;
      intrabar_conflict_policy  = GZ_CONFLICT_SL_FIRST;

      use_real_spread_fills    = false;
      point                    = 0.01;
      entry_bar_rule           = GZ_ENTRY_BAR_LEGACY;
     }
  };

//+------------------------------------------------------------------+
//| One exit-management record per GZ_Trade (see design note 1),      |
//| joined by trade_id/setup_id. Produced once at OnTradeEntered()   |
//| and updated bar-by-bar by CGZExitEngine.OnBar() until terminal.  |
//+------------------------------------------------------------------+
struct GZ_TradeExit
  {
   long                 trade_id;
   long                 setup_id;
   ENUM_GZ_LEG_DIR      direction;
   double               entry_price;

   ENUM_GZ_SL_MODEL     sl_model_used;
   double               sl_price;          // active stop (moves once BE arms)
   double               tp_price;
   double               initial_risk;      // |entry_price - sl_price| at entry (design note 2)
   double               tp_r_multiple_used;

   bool                 be_triggered;
   datetime             be_trigger_time;
   double               be_new_sl_price;

   bool                 is_open;
   datetime             exit_time;
   double               exit_price;
   ENUM_GZ_EXIT_REASON  exit_reason;
   bool                 intrabar_conflict; // design note 3
   double               realized_r;        // design note 5 (0.0 while open)

   //--- Phase 15.5 DIAGNOSTIC-ONLY fields (measurement, never read by any decision):
   //--- they record how often two known same-candle ambiguities occur, without
   //--- changing the baseline behavior documented in GZ_ExitEngine.mqh.
   datetime             entry_time;            // trade's own entry time (copy of GZ_Trade.entry_time)
   bool                 be_armed_on_entry_bar; // BE armed on the SAME M1 candle the trade entered on
   //--- what part of the FILL bar is provably after the fill (set once by OnTradeEntered from the
   //--- entry model, read only under GZ_ENTRY_BAR_SAFE - see GZEntryBarView)
   bool                 entry_bar_adverse_ok;
   bool                 entry_bar_close_ok;
   bool                 be_arm_bar_retrace;    // on the BE-arming candle, the candle's own range ALSO reached the new
                                               // BE stop level (true intrabar order unknown; engine applies the new stop from the NEXT candle)

   void Clear()
     {
      trade_id            = 0;
      setup_id            = 0;
      direction           = GZ_LEG_BULLISH;
      entry_price         = 0.0;
      entry_bar_adverse_ok = true;
      entry_bar_close_ok   = true;
      sl_model_used       = GZ_SL_STRUCTURE;
      sl_price            = 0.0;
      tp_price            = 0.0;
      initial_risk        = 0.0;
      tp_r_multiple_used  = 0.0;
      be_triggered        = false;
      be_trigger_time     = 0;
      be_new_sl_price     = 0.0;
      is_open             = true;
      exit_time           = 0;
      exit_price          = 0.0;
      exit_reason         = GZ_EXIT_NONE;
      intrabar_conflict   = false;
      realized_r          = 0.0;
      entry_time          = 0;
      be_armed_on_entry_bar = false;
      be_arm_bar_retrace  = false;
     }

   string DirectionToString() const { return (direction==GZ_LEG_BULLISH) ? "BULLISH" : "BEARISH"; }

   string ExitReasonToString() const
     {
      switch(exit_reason)
        {
         case GZ_EXIT_NONE:         return "NONE";
         case GZ_EXIT_TP_HIT:       return "TP_HIT";
         case GZ_EXIT_SL_HIT:       return "SL_HIT";
         case GZ_EXIT_BREAK_EVEN:   return "BREAK_EVEN";
         case GZ_EXIT_SESSION_EXIT: return "SESSION_EXIT";
         case GZ_EXIT_DATA_END:     return "DATA_END";
         case GZ_EXIT_OTHER:        return "OTHER";
        }
      return "UNKNOWN";
     }
  };

#endif // __GZ_EXIT_TYPES_MQH__
