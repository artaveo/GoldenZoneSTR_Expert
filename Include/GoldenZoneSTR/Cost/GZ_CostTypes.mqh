//+------------------------------------------------------------------+
//| GZ_CostTypes.mqh                                                  |
//| GoldenZone STR - Phase 15.8 Part B - Net-of-cost R layer - types  |
//|                                                                    |
//| Types only (no computation), same discipline as every other        |
//| *Types.mqh file in this repo.                                      |
//|                                                                    |
//| DESIGN NOTES                                                       |
//| 1) POST-HOC AND ADDITIVE. All R values produced by the simulator    |
//|    are GROSS (spread, commission and slippage are never charged     |
//|    there). The net layer runs AFTER a run, from the per-trade       |
//|    record (CGZRunDetail: entry price, initial risk, direction,      |
//|    entry/exit times, exit reason) plus the M1 `spread` field. It     |
//|    changes NO simulator/entry/exit/journal/metrics behavior and NO  |
//|    gross figure; net numbers are only printed NEXT TO the gross     |
//|    ones.                                                            |
//| 2) FORMULA (price units per ounce; XAUUSD is USD-quoted):           |
//|      commission_price = open_price * commission_percent / 100       |
//|                         (PERCENT mode, charged ONCE at opening)     |
//|                       = commission_per_lot_round_turn / contract    |
//|                         size                       (FIXED mode)     |
//|      cost_price = spread_points*point + 2*slippage_points*point     |
//|                   + commission_price                                |
//|      net_R      = gross_R - cost_price / initial_risk_price         |
//|    A BREAK_EVEN exit (gross R exactly 0) therefore ends slightly    |
//|    negative in net terms, automatically.                            |
//| 3) VENUE MODEL (researched proposal, FundedNext MT5 gold): the      |
//|    commission is lot x contract size x open price x 0.0016 %,       |
//|    charged once at opening and not at closing (FundedNext Help      |
//|    Center, structure effective 2026-01-12; example 1 lot XAUUSD at  |
//|    4466.22 -> $7.14). The CURRENT structure is applied to ALL       |
//|    history on purpose: the goal is to estimate the cost of trading  |
//|    the strategy NOW. Older fixed $/lot figures describe older       |
//|    structures. No slippage figure is published by the venue:        |
//|    default 0 plus a mandatory sensitivity table (0/20/50 points     |
//|    per side; 10 points = $0.10 on XAUUSD). These are PROPOSALS the  |
//|    user confirms - nothing here guesses any other broker cost.      |
//| 4) SWAP IS NOT MODELLED. Trades that cross a server midnight        |
//|    (rollover) are only COUNTED so the omission can be judged.       |
//| 5) APPROXIMATION (direction of error): candles are BID-based and    |
//|    the simulator fills on them. A long is bought at the ask        |
//|    (bid + spread) and a short is covered at the ask; the post-hoc   |
//|    cost charges the ENTRY bar's spread once as a proxy for the      |
//|    ask/bid difference of both fill and exit. Where the spread at    |
//|    the EXIT is wider than at the entry (news, rollover, fast        |
//|    stop-outs) the cost is UNDER-stated; the effect on the hit       |
//|    conditions (a short's TP/SL are triggered by the ask) is not     |
//|    modelled at all. Exact bid/ask fill modelling is out of scope.   |
//| 6) Costs not deliberately configured (InpCostsConfigured=false)     |
//|    => NET equals GROSS and the report says so.                      |
//+------------------------------------------------------------------+
#ifndef __GZ_COST_TYPES_MQH__
#define __GZ_COST_TYPES_MQH__


#define GZ_COST_SENS_COUNT 3
const double GZ_COST_SENS_POINTS[GZ_COST_SENS_COUNT] = {0.0, 20.0, 50.0};

enum ENUM_GZ_COST_SPREAD_MODE
  {
   GZ_COST_SPREAD_RECORDED = 0,   // RECORDED: spread field of the entry M1 bar
   GZ_COST_SPREAD_FIXED           // FIXED: use the fixed spread in points
  };

enum ENUM_GZ_COST_COMMISSION_MODE
  {
   GZ_COST_COMM_PERCENT = 0,      // PERCENT: percent of open price, charged once at open
   GZ_COST_COMM_FIXED             // FIXED: USD per lot, round turn
  };

string GZCostSpreadModeToString(ENUM_GZ_COST_SPREAD_MODE m)
  {
   return (m==GZ_COST_SPREAD_RECORDED) ? "RECORDED" : "FIXED";
  }

string GZCostCommissionModeToString(ENUM_GZ_COST_COMMISSION_MODE m)
  {
   return (m==GZ_COST_COMM_PERCENT) ? "PERCENT" : "FIXED";
  }

struct GZ_CostConfig
  {
   ENUM_GZ_COST_SPREAD_MODE      spread_mode;
   double                        fixed_spread_pts;
   ENUM_GZ_COST_COMMISSION_MODE  commission_mode;
   double                        commission_percent;   // PERCENT mode (FundedNext XAUUSD proposal: 0.0016)
   double                        commission_per_lot;   // FIXED mode, USD per lot round turn
   double                        contract_size;        // ounces per lot (XAUUSD = 100)
   double                        slippage_pts;         // per side
   bool                          configured;           // false => NET equals GROSS
   double                        point;                // price units per point (SYMBOL_POINT; XAUUSD 0.01)

   void Default()
     {
      spread_mode = GZ_COST_SPREAD_RECORDED; fixed_spread_pts = 0.0;
      commission_mode = GZ_COST_COMM_PERCENT; commission_percent = 0.0; commission_per_lot = 0.0;
      contract_size = 100.0; slippage_pts = 0.0; configured = false; point = 0.01;
     }

   //--- true when this configuration can never charge anything (unconfigured, or every component zero)
   bool NetEqualsGross() const
     {
      if(!configured) return true;
      bool spread_zero = (spread_mode==GZ_COST_SPREAD_FIXED && fixed_spread_pts<=0.0);
      bool comm_zero   = (commission_mode==GZ_COST_COMM_PERCENT) ? (commission_percent<=0.0) : (commission_per_lot<=0.0);
      return (spread_zero && comm_zero && slippage_pts<=0.0);
     }
  };

//--- net figures of one population at one slippage level (sensitivity table row)
struct GZ_NetSens
  {
   double   slippage_pts;
   double   net_r;
   double   expectancy;
   double   profit_factor;
   bool     pf_undefined;

   void Clear() { slippage_pts = 0.0; net_r = 0.0; expectancy = 0.0; profit_factor = 0.0; pf_undefined = false; }
  };

//--- net summary of ONE run's closed-trade population (configured costs)
struct GZ_NetSummary
  {
   bool     available;          // false when no trades / not evaluated
   bool     net_equals_gross;   // costs unset or all zero
   int      trades;
   double   gross_net_r;        // sum of gross realized R
   double   gross_expectancy;
   double   net_r;
   double   expectancy;
   double   profit_factor;
   bool     pf_undefined;
   double   win_rate;           // net R > 0
   double   max_dd_r;           // existing metrics logic on the NET series
   int      max_lose_streak;
   double   avg_cost_r;
   double   max_cost_r;
   int      cost_ge_quarter_r;  // trades whose cost is >= 0.25 R
   double   avg_spread_pts;     // spread actually charged (RECORDED: entry-bar spread; FIXED: the fixed value)
   int      spread_zero;        // trades charged a spread of 0 points
   int      spread_missing;     // RECORDED mode: no M1 bar found for the entry time (charged 0)
   int      rollover_crossings; // trades open across a server midnight (swap NOT modelled)
   GZ_NetSens sens[GZ_COST_SENS_COUNT];

   void Clear()
     {
      available = false; net_equals_gross = true; trades = 0; gross_net_r = 0.0; gross_expectancy = 0.0;
      net_r = 0.0; expectancy = 0.0; profit_factor = 0.0; pf_undefined = false; win_rate = 0.0;
      max_dd_r = 0.0; max_lose_streak = 0; avg_cost_r = 0.0; max_cost_r = 0.0; cost_ge_quarter_r = 0;
      avg_spread_pts = 0.0; spread_zero = 0; spread_missing = 0; rollover_crossings = 0;
      for(int i=0;i<GZ_COST_SENS_COUNT;i++) sens[i].Clear();
     }
  };

#endif // __GZ_COST_TYPES_MQH__
