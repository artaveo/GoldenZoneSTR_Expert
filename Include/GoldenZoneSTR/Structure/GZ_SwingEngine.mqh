//+------------------------------------------------------------------+
//| GZ_SwingEngine.mqh                                                |
//| GoldenZone STR - Phase 2 - M5 Structure Engine                    |
//|                                                                    |
//| Detects swing highs/lows on M5 data with a configurable pivot    |
//| strength. NO leg, break, fibonacci, entry, exit or filter logic  |
//| (Phase 3+) lives here - this file only detects and confirms      |
//| swing points.                                                     |
//|                                                                    |
//| DESIGN (Roadmap Phase 17, Shared Strategy Core):                 |
//| The same engine instance must work for both the historical       |
//| Research Adapter (fed a full array via DetectAll) and, later, a  |
//| live Execution Adapter (fed one CLOSED bar at a time via         |
//| Update()). It NEVER inspects data beyond the bars it has been    |
//| given, and a pivot at position p is only ever evaluated once bar |
//| p+strength has been fed - i.e. once strength bars have closed on |
//| its right side. No future bar is used merely because it exists   |
//| later in an array.                                                |
//+------------------------------------------------------------------+
#ifndef __GZ_SWING_ENGINE_MQH__
#define __GZ_SWING_ENGINE_MQH__

#include "GZ_StructureTypes.mqh"
#include "..\Diagnostics\GZ_Logger.mqh"

class CGZSwingEngine
  {
private:
   int               m_strength;     // bars required strictly higher/lower on EACH side
   long              m_next_id;
   MqlRates          m_win[];        // rolling window, size == 2*m_strength+1
   int               m_win_count;    // bars currently held in the window (<= size)
   long              m_bar_counter;  // total bars fed since Init()/Reset()
   CGZLogger        *m_logger;

   //--- Evaluate whether the CENTER bar of the (full) window is a
   //--- confirmed pivot. Only called once the window is full, i.e.
   //--- only once `m_strength` bars exist on both sides of it.
   bool EvaluatePivot(GZ_Swing &out)
     {
      int size = ArraySize(m_win);
      int mid  = m_strength; // center index within the window

      double midHigh = m_win[mid].high;
      double midLow  = m_win[mid].low;

      bool isHigh = true;
      bool isLow  = true;
      for(int k=0; k<size; k++)
        {
         if(k==mid)
            continue;
         // Strict inequality: a tie on either side disqualifies that
         // side deterministically (no hidden tie-break, no plateau
         // treated as a pivot).
         if(m_win[k].high >= midHigh)
            isHigh = false;
         if(m_win[k].low <= midLow)
            isLow = false;
        }

      if(!isHigh && !isLow)
         return false;

      // A single candle can in principle qualify as both (e.g. an
      // isolated spike). Deterministic, documented priority: HIGH
      // wins. This is a documented rule, not a random tie-break.
      out.Clear();
      out.id                = m_next_id++;
      out.direction         = isHigh ? GZ_SWING_HIGH : GZ_SWING_LOW;
      out.price             = isHigh ? midHigh : midLow;
      out.pivot_time        = m_win[mid].time;
      out.pivot_bar_index   = (int)(m_bar_counter - (size - mid));
      out.detection_time    = m_win[mid].time;
      out.confirmation_time = m_win[size-1].time; // rightmost bar = confirming bar
      out.pivot_strength    = m_strength;
      return true;
     }

public:
                     CGZSwingEngine(CGZLogger *logger=NULL) { m_logger=logger; m_strength=2; m_win_count=0; m_bar_counter=0; m_next_id=1; }

   //--- Configure and reset all state. Call before first Update()/DetectAll().
   void              Init(int strength)
     {
      m_strength    = (strength<1) ? 1 : strength;
      m_next_id     = 1;
      m_win_count   = 0;
      m_bar_counter = 0;
      ArrayResize(m_win, 2*m_strength+1);
     }

   void              Reset() { Init(m_strength); }

   int               Strength() const { return m_strength; }
   long              BarsFed()  const { return m_bar_counter; }

   //--- Incremental (live-safe) API -------------------------------------
   // Feed exactly one CLOSED bar, oldest to newest. Returns true and
   // fills `out` when this call confirms a swing. Safe to call from a
   // live/forward-testing context: it only ever looks at bars already
   // fed to it.
   bool              Update(const MqlRates &bar, GZ_Swing &out)
     {
      int need = 2*m_strength+1;
      if(ArraySize(m_win)!=need)
         ArrayResize(m_win, need);

      if(m_win_count<need)
        {
         m_win[m_win_count] = bar;
         m_win_count++;
        }
      else
        {
         for(int i=1; i<need; i++)
            m_win[i-1] = m_win[i];
         m_win[need-1] = bar;
        }
      m_bar_counter++;

      if(m_win_count<need)
         return false; // not enough bars yet to confirm a center pivot

      bool found = EvaluatePivot(out);
      if(found && m_logger!=NULL)
         m_logger.Debug("Swing", StringFormat("%s confirmed id=%d price=%.5f pivot=%s confirm=%s strength=%d",
                         out.DirectionToString(), (int)out.id, out.price,
                         TimeToString(out.pivot_time), TimeToString(out.confirmation_time), out.pivot_strength));
      return found;
     }

   //--- Batch (research/backtest convenience) API ------------------------
   // Detects every confirmed swing in a chronologically ordered array in
   // one call. Uses its own independent internal state (does not disturb
   // any ongoing incremental session on `this`), and produces exactly the
   // sequence Update() would have produced bar-by-bar - same order, same
   // confirmation times. No swing is emitted "early" relative to that
   // bar-by-bar sequence.
   int               DetectAll(const MqlRates &rates[], GZ_Swing &swings[])
     {
      ArrayResize(swings, 0);
      int n = ArraySize(rates);

      CGZSwingEngine local(m_logger);
      local.Init(m_strength);

      int cnt = 0;
      for(int i=0; i<n; i++)
        {
         GZ_Swing s;
         if(local.Update(rates[i], s))
           {
            cnt++;
            ArrayResize(swings, cnt);
            swings[cnt-1] = s;
           }
        }
      return cnt;
     }
  };

#endif // __GZ_SWING_ENGINE_MQH__
