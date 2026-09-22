//+------------------------------------------------------------------+
//| GZ_ATR.mqh                                                        |
//| GoldenZone STR - Phase 3 - ATR helper                            |
//|                                                                    |
//| Deterministic, live-safe streaming Average True Range, used only  |
//| to size the Break Engine's buffer. NOT a filter/indicator for     |
//| entry logic (Phase 4+).                                            |
//|                                                                    |
//| DESIGN NOTE: uses a simple moving average of True Range (not      |
//| Wilder's exponential smoothing). This is a documented, explicit   |
//| simplification chosen for full bar-by-bar/batch reproducibility   |
//| with no hidden recursive state; it can be swapped for Wilder's    |
//| method later without changing any consumer's interface.           |
//+------------------------------------------------------------------+
#ifndef __GZ_ATR_MQH__
#define __GZ_ATR_MQH__

class CGZAtr
  {
private:
   int               m_period;
   double            m_ring[];      // ring buffer of True Range values
   int               m_ring_pos;
   int               m_count;       // bars of TR fed so far (caps at m_period)
   double            m_sum;
   bool              m_have_prev_close;
   double            m_prev_close;

   double TrueRange(const MqlRates &bar) const
     {
      double hl = bar.high - bar.low;
      if(!m_have_prev_close)
         return hl;
      double hc = MathAbs(bar.high - m_prev_close);
      double lc = MathAbs(bar.low  - m_prev_close);
      double tr = hl;
      if(hc>tr) tr = hc;
      if(lc>tr) tr = lc;
      return tr;
     }

public:
                     CGZAtr() { m_period=14; m_ring_pos=0; m_count=0; m_sum=0.0; m_have_prev_close=false; m_prev_close=0.0; }

   void              Init(int period)
     {
      m_period = (period<1) ? 1 : period;
      ArrayResize(m_ring, m_period);
      ArrayInitialize(m_ring, 0.0);
      m_ring_pos = 0;
      m_count = 0;
      m_sum = 0.0;
      m_have_prev_close = false;
      m_prev_close = 0.0;
     }

   int               Period() const { return m_period; }
   bool              IsReady() const { return m_count>=m_period; }

   // Current ATR (simple average of the last `period` True Range values).
   // Returns 0.0 and IsReady()==false until enough bars have been fed -
   // callers must check IsReady() rather than trust a 0.0 value blindly.
   double            Value() const { return IsReady() ? (m_sum/m_period) : 0.0; }

   // Feed exactly one CLOSED bar, oldest to newest. Live-safe: only ever
   // uses this bar and the previously fed bar's close (no lookahead).
   void              Update(const MqlRates &bar)
     {
      double tr = TrueRange(bar);

      if(m_count<m_period)
        {
         m_ring[m_ring_pos] = tr;
         m_sum += tr;
         m_count++;
        }
      else
        {
         m_sum -= m_ring[m_ring_pos];
         m_ring[m_ring_pos] = tr;
         m_sum += tr;
        }
      m_ring_pos = (m_ring_pos+1) % m_period;

      m_prev_close = bar.close;
      m_have_prev_close = true;
     }
  };

#endif // __GZ_ATR_MQH__
