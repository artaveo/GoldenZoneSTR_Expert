//+------------------------------------------------------------------+
//| GZ_EntryBarTests.mqh - Entry-bar rule (GZ_ENTRY_BAR_SAFE) T289-295 |
//|                                                                    |
//| Hand-built trades driven straight into CGZExitEngine /             |
//| CGZJournalEngine, same self-contained-suite convention as          |
//| GZ_CostRSymTests.mqh. Common fixture: entry 100, structure SL 90   |
//| (risk 10), TP 1R = 110, no real-spread fills, no BE unless stated. |
//+------------------------------------------------------------------+
#ifndef __GZ_ENTRY_BAR_TESTS_MQH__
#define __GZ_ENTRY_BAR_TESTS_MQH__

#include "GZ_ExitEngine.mqh"
#include "GZ_ExitTypes.mqh"
#include "..\Entry\GZ_EntryTypes.mqh"
#include "..\Leg\GZ_LegTypes.mqh"
#include "..\Journal\GZ_JournalEngine.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZEntryBarTests
  {
private:
   CGZLogger        *m_logger;
   GZ_TestResult     m_results[];

   void AddResult(string id, bool passed, string detail)
     {
      int n = ArraySize(m_results);
      ArrayResize(m_results, n+1);
      m_results[n].id = id; m_results[n].passed = passed; m_results[n].blocked = false; m_results[n].detail = detail;
      if(m_logger!=NULL)
         m_logger.Info("Test", StringFormat("%s: %s - %s", id, passed?"PASS":"FAIL", detail));
     }

   datetime T(int minute) const
     {
      MqlDateTime dt; dt.year=2026; dt.mon=5; dt.day=4; dt.hour=10; dt.min=minute; dt.sec=0;
      return StructToTime(dt);
     }

   MqlRates Bar(datetime t, double o, double h, double l, double c) const
     {
      MqlRates r; r.time=t; r.open=o; r.high=h; r.low=l; r.close=c;
      r.tick_volume=100; r.spread=0; r.real_volume=0;
      return r;
     }

   GZ_Leg MakeLeg(ENUM_GZ_LEG_DIR dir, double origin) const
     {
      GZ_Leg leg; leg.Clear();
      leg.id=1; leg.direction=dir; leg.origin_swing.price=origin; leg.extreme_price=origin;
      return leg;
     }

   GZ_Trade MakeTrade(ENUM_GZ_LEG_DIR dir, double entry, ENUM_GZ_ENTRY_MODEL model, datetime t) const
     {
      GZ_Trade tr; tr.Clear();
      tr.id=1; tr.setup_id=1; tr.entry_time=t; tr.entry_price=entry; tr.direction=dir;
      tr.entry_model=model; tr.spread_assumption=0.0;
      return tr;
     }

   GZ_ExitConfig Cfg(ENUM_GZ_ENTRY_BAR_RULE rule, double be_trigger=0.0,
                     ENUM_GZ_INTRABAR_CONFLICT_POLICY pol=GZ_CONFLICT_SL_FIRST) const
     {
      GZ_ExitConfig c; c.Default();
      c.sl_model=GZ_SL_STRUCTURE; c.sl_buffer_atr_mult=0.0; c.tp_r_multiple=1.0;
      c.use_real_spread_fills=false; c.point=0.01; c.entry_bar_rule=rule;
      c.be_trigger_r=be_trigger; c.intrabar_conflict_policy=pol;
      return c;
     }

   //--- One trade, then the given bars. Returns the exit record after bar `upto`.
   //--- The config is built HERE from scalars: MQL5 passes structs by reference
   //--- only, so a function result must never be handed to a reference parameter.
   GZ_TradeExit Play(ENUM_GZ_ENTRY_BAR_RULE rule, double be_trigger, ENUM_GZ_INTRABAR_CONFLICT_POLICY pol,
                     ENUM_GZ_LEG_DIR dir, double entry, double origin,
                     ENUM_GZ_ENTRY_MODEL model, const MqlRates &bars[], int upto)
     {
      GZ_ExitConfig cfg = Cfg(rule, be_trigger, pol);
      CGZExitEngine ex; ex.Init(cfg);
      GZ_Trade tr = MakeTrade(dir, entry, model, bars[0].time);
      GZ_Leg leg  = MakeLeg(dir, origin);
      ex.OnTradeEntered(tr, leg, 0.0, true);
      for(int i=0;i<=upto;i++)
         ex.OnBar(bars[i], true, false);
      return ex.GetExit(0);
     }

   //--- T289: LONG, LIMIT fill. Entry bar: high 115 (>= TP 110) but close 105.
   //--- SAFE: the high may have printed BEFORE the fill -> still open.
   //--- LEGACY: TP credited on the entry bar (the old optimistic behavior).
   void T289_HighBeforeFillNotCredited()
     {
      MqlRates b[]; ArrayResize(b,1); b[0]=Bar(T(0),108,115,99,105);
      GZ_TradeExit s = Play(GZ_ENTRY_BAR_SAFE, 0.0, GZ_CONFLICT_SL_FIRST,   GZ_LEG_BULLISH,100,90,GZ_ENTRY_LIMIT,b,0);
      GZ_TradeExit l = Play(GZ_ENTRY_BAR_LEGACY, 0.0, GZ_CONFLICT_SL_FIRST, GZ_LEG_BULLISH,100,90,GZ_ENTRY_LIMIT,b,0);
      bool ok = s.is_open && (!l.is_open) && (l.exit_reason==GZ_EXIT_TP_HIT) && MathAbs(l.realized_r-1.0)<0.0001;
      AddResult("T289", ok, StringFormat("long LIMIT, entry bar H=115 C=105 (TP=110): SAFE open=%s | LEGACY open=%s reason=%s r=%.3f (expect SAFE open, LEGACY TP_HIT +1.000)",
                s.is_open?"true":"false", l.is_open?"true":"false", EnumToString(l.exit_reason), l.realized_r));
     }

   //--- T290: same bar but close 111 >= TP. The close is provably after the fill,
   //--- so the price must have crossed 110 after it: TP is credited under SAFE too.
   void T290_CloseProvesTp()
     {
      MqlRates b[]; ArrayResize(b,1); b[0]=Bar(T(0),108,115,99,111);
      GZ_TradeExit s = Play(GZ_ENTRY_BAR_SAFE, 0.0, GZ_CONFLICT_SL_FIRST, GZ_LEG_BULLISH,100,90,GZ_ENTRY_LIMIT,b,0);
      bool ok = (!s.is_open) && (s.exit_reason==GZ_EXIT_TP_HIT) && MathAbs(s.realized_r-1.0)<0.0001;
      AddResult("T290", ok, StringFormat("long LIMIT, entry bar C=111 >= TP 110: SAFE open=%s reason=%s r=%.3f (expect TP_HIT +1.000)",
                s.is_open?"true":"false", EnumToString(s.exit_reason), s.realized_r));
     }

   //--- T291: adverse extreme IS after the fill: low 89 <= SL 90 stops the trade
   //--- even under SAFE. With close 111 both SL and TP are provable -> policy
   //--- SL_FIRST -> SL_HIT; TP_FIRST -> TP_HIT.
   void T291_AdverseExtremeStillStops()
     {
      MqlRates b[]; ArrayResize(b,1); b[0]=Bar(T(0),100,115,89,105);
      MqlRates c[]; ArrayResize(c,1); c[0]=Bar(T(0),100,115,89,111);
      GZ_TradeExit a = Play(GZ_ENTRY_BAR_SAFE, 0.0, GZ_CONFLICT_SL_FIRST, GZ_LEG_BULLISH,100,90,GZ_ENTRY_LIMIT,b,0);
      GZ_TradeExit s = Play(GZ_ENTRY_BAR_SAFE, 0.0, GZ_CONFLICT_SL_FIRST, GZ_LEG_BULLISH,100,90,GZ_ENTRY_LIMIT,c,0);
      GZ_TradeExit t = Play(GZ_ENTRY_BAR_SAFE, 0.0, GZ_CONFLICT_TP_FIRST, GZ_LEG_BULLISH,100,90,GZ_ENTRY_LIMIT,c,0);
      bool ok = (!a.is_open) && (a.exit_reason==GZ_EXIT_SL_HIT) && MathAbs(a.realized_r+1.0)<0.0001 &&
                (!s.is_open) && (s.exit_reason==GZ_EXIT_SL_HIT) && s.intrabar_conflict &&
                (!t.is_open) && (t.exit_reason==GZ_EXIT_TP_HIT);
      AddResult("T291", ok, StringFormat("low 89 <= SL: C=105 -> %s r=%.3f | C=111 SL_FIRST -> %s conflict=%s | C=111 TP_FIRST -> %s (expect SL_HIT -1 | SL_HIT conflict | TP_HIT)",
                EnumToString(a.exit_reason), a.realized_r, EnumToString(s.exit_reason), s.intrabar_conflict?"true":"false", EnumToString(t.exit_reason)));
     }

   //--- T292: confirmation models fill AT the close - nothing inside the fill bar is
   //--- after the fill. Bar with low 89 (< SL) and high 115 (> TP): SAFE skips it; the
   //--- NEXT bar (95..111) then takes the TP. LEGACY closes on the entry bar (conflict -> SL).
   void T292_ConfirmationFillBarSkipped()
     {
      MqlRates b[]; ArrayResize(b,2); b[0]=Bar(T(0),95,115,89,100); b[1]=Bar(T(1),100,111,95,105);
      GZ_TradeExit s0 = Play(GZ_ENTRY_BAR_SAFE, 0.0, GZ_CONFLICT_SL_FIRST,   GZ_LEG_BULLISH,100,90,GZ_ENTRY_M1_CONFIRMATION,b,0);
      GZ_TradeExit s1 = Play(GZ_ENTRY_BAR_SAFE, 0.0, GZ_CONFLICT_SL_FIRST,   GZ_LEG_BULLISH,100,90,GZ_ENTRY_M1_CONFIRMATION,b,1);
      GZ_TradeExit l0 = Play(GZ_ENTRY_BAR_LEGACY, 0.0, GZ_CONFLICT_SL_FIRST, GZ_LEG_BULLISH,100,90,GZ_ENTRY_M1_CONFIRMATION,b,0);
      bool ok = s0.is_open && (!s1.is_open) && (s1.exit_reason==GZ_EXIT_TP_HIT) && (s1.exit_time==T(1)) &&
                (!l0.is_open) && (l0.exit_reason==GZ_EXIT_SL_HIT);
      AddResult("T292", ok, StringFormat("M1_CONFIRMATION fill at close: SAFE after fill bar open=%s, after next bar %s at %s | LEGACY on fill bar %s (expect open, TP_HIT at bar 2, SL_HIT)",
                s0.is_open?"true":"false", EnumToString(s1.exit_reason), TimeToString(s1.exit_time,TIME_MINUTES), EnumToString(l0.exit_reason)));
     }

   //--- T293: SHORT mirror. Entry 100, SL 110, TP 90. Entry bar low 85 (<= TP) but close 95.
   void T293_ShortMirror()
     {
      MqlRates b[]; ArrayResize(b,1); b[0]=Bar(T(0),92,101,85,95);
      MqlRates c[]; ArrayResize(c,1); c[0]=Bar(T(0),92,101,85,89);
      MqlRates d[]; ArrayResize(d,1); d[0]=Bar(T(0),92,111,85,95);
      GZ_TradeExit s = Play(GZ_ENTRY_BAR_SAFE, 0.0, GZ_CONFLICT_SL_FIRST,   GZ_LEG_BEARISH,100,110,GZ_ENTRY_LIMIT,b,0);
      GZ_TradeExit l = Play(GZ_ENTRY_BAR_LEGACY, 0.0, GZ_CONFLICT_SL_FIRST, GZ_LEG_BEARISH,100,110,GZ_ENTRY_LIMIT,b,0);
      GZ_TradeExit p = Play(GZ_ENTRY_BAR_SAFE, 0.0, GZ_CONFLICT_SL_FIRST,   GZ_LEG_BEARISH,100,110,GZ_ENTRY_LIMIT,c,0);
      GZ_TradeExit a = Play(GZ_ENTRY_BAR_SAFE, 0.0, GZ_CONFLICT_SL_FIRST,   GZ_LEG_BEARISH,100,110,GZ_ENTRY_LIMIT,d,0);
      bool ok = s.is_open && (!l.is_open) && (l.exit_reason==GZ_EXIT_TP_HIT) &&
                (!p.is_open) && (p.exit_reason==GZ_EXIT_TP_HIT) &&
                (!a.is_open) && (a.exit_reason==GZ_EXIT_SL_HIT);
      AddResult("T293", ok, StringFormat("short LIMIT: low<=TP,C=95 SAFE open=%s LEGACY %s | C=89 SAFE %s | high 111>=SL SAFE %s (expect open, TP_HIT, TP_HIT, SL_HIT)",
                s.is_open?"true":"false", EnumToString(l.exit_reason), EnumToString(p.exit_reason), EnumToString(a.exit_reason)));
     }

   //--- T294: MAE/MFE/Reach must not credit a favorable extreme that may predate the
   //--- fill. Long entry 100, risk 10; entry bar H=115 L=98 C=104. SAFE: MFE from the
   //--- close only = 0.4R, MAE from the low = 0.2R, no 1R reach. LEGACY: MFE 1.5R.
   void T294_JournalMfeUsesCloseOnly()
     {
      MqlRates bar = Bar(T(0),108,115,98,104);
      GZ_Trade tr = MakeTrade(GZ_LEG_BULLISH,100,GZ_ENTRY_LIMIT,bar.time);
      CGZJournalEngine js(m_logger); js.Init(); js.SetEntryBarSafe(true);
      js.OnTradeEntered(tr, 10.0); js.OnBar(bar);
      CGZJournalEngine jl(m_logger); jl.Init(); jl.SetEntryBarSafe(false);
      jl.OnTradeEntered(tr, 10.0); jl.OnBar(bar);
      GZ_TradeJournal a = js.GetJournal(0);
      GZ_TradeJournal b = jl.GetJournal(0);
      bool ok = MathAbs(a.mfe_r-0.4)<0.0001 && MathAbs(a.mae_r-0.2)<0.0001 && !a.reach_hit[1] && MathAbs(b.mfe_r-1.5)<0.0001;
      AddResult("T294", ok, StringFormat("entry bar H=115 L=98 C=104 risk=10: SAFE mfe=%.3fR mae=%.3fR | LEGACY mfe=%.3fR (expect 0.400 / 0.200 | 1.500)",
                a.mfe_r, a.mae_r, b.mfe_r));
     }

   //--- T295: break-even arming must not come from an entry-bar high that may predate the
   //--- fill. BE trigger 0.5R (=105). Entry bar H=106 C=101, next bar L=99 H=104.
   //--- LEGACY: armed on the entry bar, then the next bar stops at entry (BREAK_EVEN).
   //--- SAFE: not armed (close 101 < 105), so the next bar leaves the trade open.
   void T295_BreakEvenNotArmedByPreFillHigh()
     {
      MqlRates b[]; ArrayResize(b,2); b[0]=Bar(T(0),104,106,99,101); b[1]=Bar(T(1),101,104,99,102);
      GZ_TradeExit s = Play(GZ_ENTRY_BAR_SAFE, 0.5, GZ_CONFLICT_SL_FIRST,   GZ_LEG_BULLISH,100,90,GZ_ENTRY_LIMIT,b,1);
      GZ_TradeExit l = Play(GZ_ENTRY_BAR_LEGACY, 0.5, GZ_CONFLICT_SL_FIRST, GZ_LEG_BULLISH,100,90,GZ_ENTRY_LIMIT,b,1);
      bool ok = s.is_open && (!s.be_triggered) && (!l.is_open) && (l.exit_reason==GZ_EXIT_BREAK_EVEN);
      AddResult("T295", ok, StringFormat("BE trigger 105: SAFE open=%s armed=%s | LEGACY %s (expect open/not armed | BREAK_EVEN)",
                s.is_open?"true":"false", s.be_triggered?"true":"false", EnumToString(l.exit_reason)));
     }

public:
                     CGZEntryBarTests(CGZLogger *logger=NULL) { m_logger=logger; }

   int               ResultCount() const { return ArraySize(m_results); }
   GZ_TestResult     GetResult(int i) const { return m_results[i]; }

   void              RunAll()
     {
      T289_HighBeforeFillNotCredited();
      T290_CloseProvesTp();
      T291_AdverseExtremeStillStops();
      T292_ConfirmationFillBarSkipped();
      T293_ShortMirror();
      T294_JournalMfeUsesCloseOnly();
      T295_BreakEvenNotArmedByPreFillHigh();
     }
  };

#endif // __GZ_ENTRY_BAR_TESTS_MQH__
