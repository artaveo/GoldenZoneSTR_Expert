//+------------------------------------------------------------------+
//| GZ_Partition.mqh                                                  |
//| GoldenZone STR - Phase 15.8 - Historical dataset partitioning     |
//|                                                                    |
//| DATA INFRASTRUCTURE ONLY. No strategy logic, no parameter, no      |
//| selection. Every date here is CONFIGURATION (EA inputs); nothing   |
//| in this file knows that 2020-07-01, 2025-01-01 or 2026-01-01 are   |
//| special.                                                           |
//|                                                                    |
//|   Historical Dataset (validated once)                              |
//|        -> DEVELOPMENT      research allowed                       |
//|        -> FINAL_OOS        (new research cycle) research REFUSED   |
//|        -> LEGACY_TOUCHED   (already observed data) research REFUSED|
//|                                                                    |
//| DESIGN NOTES                                                       |
//| 1) HALF-OPEN [start, end) at this layer. The research engines use  |
//|    INCLUSIVE bar-open ends (GZ_ResearchRange, same as CopyRates):  |
//|        end_inclusive = end_exclusive - 1 M1 minute                 |
//|    followed by the EXISTING M5 alignment (start rounded UP, end     |
//|    rounded DOWN to the last minute of a complete M5 window).       |
//|    Reverse mapping used for classification:                        |
//|        end_exclusive = eff_end + 1 M1 minute.                       |
//| 2) The partition must be contiguous (Development -> Final OOS ->   |
//|    Legacy, no gap, no overlap) and every part must lie inside the  |
//|    Historical range. Historical data OUTSIDE every part (an        |
//|    earlier start or a later end than the parts cover) is accepted  |
//|    and labelled UNASSIGNED: it stays in the dataset and in the     |
//|    coverage tables, research on it is refused until a part is      |
//|    configured for it (change the partition inputs, no code).       |
//| 3) Research gate: only ranges fully inside DEVELOPMENT run. One    |
//|    controlled exception: the LEGACY_DEV range kind over the        |
//|    LEGACY_TOUCHED part = REGRESSION_ONLY_LEGACY (validated         |
//|    baseline check; never usable for selection).                    |
//| 4) WARM-UP never reads bars outside the partition of the measured  |
//|    range (floor = start of that partition).                        |
//+------------------------------------------------------------------+
#ifndef __GZ_PARTITION_MQH__
#define __GZ_PARTITION_MQH__

#include "..\Core\GZ_Constants.mqh"
#include "GZ_ResearchRange.mqh"

//--- ONE user-accepted, documented data hole (no bars on 2022-09-01 and 2022-09-02; the broker history has
//--- none). Only this exact window is excused in runtime check R02; any other hole still fails it. Never
//--- repaired or fabricated. (Phase 15.7 constants, moved here so tests and the EA share one definition.)
#define GZ_P157_ACCEPTED_HOLE_FROM D'2022.08.31 23:59'
#define GZ_P157_ACCEPTED_HOLE_TO   D'2022.09.05 01:00'

enum ENUM_GZ_PART_CLASS
  {
   GZ_PC_DEVELOPMENT = 0,     // fully inside DEVELOPMENT
   GZ_PC_FINAL_OOS,           // fully inside the NEW FINAL OOS part
   GZ_PC_LEGACY_TOUCHED,      // fully inside the LEGACY / TOUCHED part
   GZ_PC_CROSSES_BOUNDARY,    // overlaps more than one part (or a part and unassigned data)
   GZ_PC_UNASSIGNED,          // inside the Historical range but inside no part
   GZ_PC_OUTSIDE_HISTORICAL,  // starts before / ends after the Historical range
   GZ_PC_INVALID              // empty/reversed range or invalid partition
  };

enum ENUM_GZ_PART_ERR
  {
   GZ_PERR_NONE = 0,
   GZ_PERR_NOT_SET,
   GZ_PERR_REVERSED_OR_EMPTY,
   GZ_PERR_OUTSIDE_HISTORICAL,
   GZ_PERR_OVERLAP,
   GZ_PERR_GAP
  };

string GZPartClassToString(ENUM_GZ_PART_CLASS c)
  {
   switch(c)
     {
      case GZ_PC_DEVELOPMENT:       return "DEVELOPMENT";
      case GZ_PC_FINAL_OOS:         return "FINAL_OOS";
      case GZ_PC_LEGACY_TOUCHED:    return "LEGACY_TOUCHED";
      case GZ_PC_CROSSES_BOUNDARY:  return "CROSSES_PARTITION_BOUNDARY";
      case GZ_PC_UNASSIGNED:        return "UNASSIGNED";
      case GZ_PC_OUTSIDE_HISTORICAL:return "OUTSIDE_HISTORICAL";
      case GZ_PC_INVALID:           return "INVALID";
     }
   return "UNKNOWN";
  }

string GZPartErrToString(ENUM_GZ_PART_ERR e)
  {
   switch(e)
     {
      case GZ_PERR_NONE:              return "NONE";
      case GZ_PERR_NOT_SET:           return "NOT_SET";
      case GZ_PERR_REVERSED_OR_EMPTY: return "REVERSED_OR_EMPTY";
      case GZ_PERR_OUTSIDE_HISTORICAL:return "OUTSIDE_HISTORICAL";
      case GZ_PERR_OVERLAP:           return "OVERLAP";
      case GZ_PERR_GAP:               return "GAP";
     }
   return "UNKNOWN";
  }

//--- Historical end INPUT is an INCLUSIVE M1 bar-open time (e.g. 2026.09.24 23:59) -> half-open end.
datetime GZHistEndExclusive(datetime inclusive_end_input)
  {
   return (datetime)((long)inclusive_end_input + GZ_SPACING_M1_SECONDS);
  }

//--- half-open end -> inclusive M1 bar-open end (before M5 alignment)
datetime GZExclusiveToInclusiveEnd(datetime end_exclusive)
  {
   return (datetime)((long)end_exclusive - GZ_SPACING_M1_SECONDS);
  }

//--- inclusive M1 bar-open end -> half-open end
datetime GZInclusiveToExclusiveEnd(datetime end_inclusive)
  {
   return (datetime)((long)end_inclusive + GZ_SPACING_M1_SECONDS);
  }

//+------------------------------------------------------------------+
//| The partition: all ends EXCLUSIVE                                  |
//+------------------------------------------------------------------+
struct GZ_Partition
  {
   datetime          hist_start, hist_end;
   datetime          dev_start,  dev_end;
   datetime          oos_start,  oos_end;
   datetime          leg_start,  leg_end;
   bool              valid;
   ENUM_GZ_PART_ERR  error_code;
   string            error;
   string            warning;

   void Clear()
     {
      hist_start = 0; hist_end = 0; dev_start = 0; dev_end = 0; oos_start = 0; oos_end = 0; leg_start = 0; leg_end = 0;
      valid = false; error_code = GZ_PERR_NOT_SET; error = ""; warning = "";
     }

   void Set(datetime hs, datetime he, datetime ds, datetime de, datetime os, datetime oe, datetime ls, datetime le)
     {
      hist_start = hs; hist_end = he; dev_start = ds; dev_end = de; oos_start = os; oos_end = oe; leg_start = ls; leg_end = le;
      valid = false; error_code = GZ_PERR_NOT_SET; error = ""; warning = "";
     }
  };

string GZPartDate(datetime t)
  {
   return TimeToString(t, TIME_DATE|TIME_MINUTES);
  }

//--- Validate: every part inside Historical, start < end, contiguous, non-overlapping. Sets p.valid / p.error /
//--- p.error_code / p.warning. Historical data outside every part is accepted (warning, see header note 2).
bool GZPartitionValidate(GZ_Partition &p)
  {
   p.valid = false; p.error = ""; p.warning = ""; p.error_code = GZ_PERR_NONE;

   if(p.hist_start<=0 || p.hist_end<=0 || p.dev_start<=0 || p.dev_end<=0 || p.oos_start<=0 || p.oos_end<=0 || p.leg_start<=0 || p.leg_end<=0)
     {
      p.error_code = GZ_PERR_NOT_SET;
      p.error = "a partition date is not set (all eight partition/historical dates are required)";
      return false;
     }
   if(p.hist_end <= p.hist_start)
     {
      p.error_code = GZ_PERR_REVERSED_OR_EMPTY;
      p.error = StringFormat("historical range is empty or reversed (%s -> %s)", GZPartDate(p.hist_start), GZPartDate(p.hist_end));
      return false;
     }
   if(p.dev_end <= p.dev_start)
     {
      p.error_code = GZ_PERR_REVERSED_OR_EMPTY;
      p.error = StringFormat("DEVELOPMENT partition is empty or reversed (%s -> %s)", GZPartDate(p.dev_start), GZPartDate(p.dev_end));
      return false;
     }
   if(p.oos_end <= p.oos_start)
     {
      p.error_code = GZ_PERR_REVERSED_OR_EMPTY;
      p.error = StringFormat("NEW FINAL OOS partition is empty or reversed (%s -> %s)", GZPartDate(p.oos_start), GZPartDate(p.oos_end));
      return false;
     }
   if(p.leg_end <= p.leg_start)
     {
      p.error_code = GZ_PERR_REVERSED_OR_EMPTY;
      p.error = StringFormat("LEGACY/TOUCHED partition is empty or reversed (%s -> %s)", GZPartDate(p.leg_start), GZPartDate(p.leg_end));
      return false;
     }

   //--- each part inside Historical
   if(p.dev_start < p.hist_start || p.dev_end > p.hist_end)
     {
      p.error_code = GZ_PERR_OUTSIDE_HISTORICAL;
      p.error = StringFormat("DEVELOPMENT partition %s -> %s lies outside the Historical range %s -> %s (change the historical or the partition inputs)",
                             GZPartDate(p.dev_start), GZPartDate(p.dev_end), GZPartDate(p.hist_start), GZPartDate(p.hist_end));
      return false;
     }
   if(p.oos_start < p.hist_start || p.oos_end > p.hist_end)
     {
      p.error_code = GZ_PERR_OUTSIDE_HISTORICAL;
      p.error = StringFormat("NEW FINAL OOS partition %s -> %s lies outside the Historical range %s -> %s (change the historical or the partition inputs)",
                             GZPartDate(p.oos_start), GZPartDate(p.oos_end), GZPartDate(p.hist_start), GZPartDate(p.hist_end));
      return false;
     }
   if(p.leg_start < p.hist_start || p.leg_end > p.hist_end)
     {
      p.error_code = GZ_PERR_OUTSIDE_HISTORICAL;
      p.error = StringFormat("LEGACY/TOUCHED partition %s -> %s lies outside the Historical range %s -> %s (change the historical or the partition inputs)",
                             GZPartDate(p.leg_start), GZPartDate(p.leg_end), GZPartDate(p.hist_start), GZPartDate(p.hist_end));
      return false;
     }

   //--- contiguity: Development -> Final OOS -> Legacy
   if(p.oos_start < p.dev_end)
     {
      p.error_code = GZ_PERR_OVERLAP;
      p.error = StringFormat("NEW FINAL OOS starts %s, BEFORE the DEVELOPMENT end %s: the partitions OVERLAP (Development must end exactly where the Final OOS starts)",
                             GZPartDate(p.oos_start), GZPartDate(p.dev_end));
      return false;
     }
   if(p.oos_start > p.dev_end)
     {
      p.error_code = GZ_PERR_GAP;
      p.error = StringFormat("unintended GAP between DEVELOPMENT end %s and NEW FINAL OOS start %s (Development must end exactly where the Final OOS starts)",
                             GZPartDate(p.dev_end), GZPartDate(p.oos_start));
      return false;
     }
   if(p.leg_start < p.oos_end)
     {
      p.error_code = GZ_PERR_OVERLAP;
      p.error = StringFormat("LEGACY/TOUCHED starts %s, BEFORE the NEW FINAL OOS end %s: the partitions OVERLAP", GZPartDate(p.leg_start), GZPartDate(p.oos_end));
      return false;
     }
   if(p.leg_start > p.oos_end)
     {
      p.error_code = GZ_PERR_GAP;
      p.error = StringFormat("unintended GAP between NEW FINAL OOS end %s and LEGACY/TOUCHED start %s", GZPartDate(p.oos_end), GZPartDate(p.leg_start));
      return false;
     }

   //--- accepted, with warnings for historical data no part covers
   if(p.hist_start < p.dev_start)
      p.warning += StringFormat("Historical data %s -> %s precedes the DEVELOPMENT start: it is UNASSIGNED (kept in the dataset and coverage, research refused) until the DEVELOPMENT start input is moved earlier. ",
                                GZPartDate(p.hist_start), GZPartDate(p.dev_start));
   if(p.hist_end > p.leg_end)
      p.warning += StringFormat("Historical data %s -> %s follows the LEGACY/TOUCHED end: it is UNASSIGNED (kept in the dataset and coverage, research refused) until a partition is configured for it. ",
                                GZPartDate(p.leg_end), GZPartDate(p.hist_end));

   p.valid = true;
   p.error_code = GZ_PERR_NONE;
   return true;
  }

//--- overlap length (seconds) of [a0,a1) and [b0,b1); 0 when disjoint
long GZPartOverlapSeconds(datetime a0, datetime a1, datetime b0, datetime b1)
  {
   long lo = ((long)a0 > (long)b0) ? (long)a0 : (long)b0;
   long hi = ((long)a1 < (long)b1) ? (long)a1 : (long)b1;
   return (hi > lo) ? (hi - lo) : 0;
  }

//--- Classify a HALF-OPEN range [start, end_excl) against the partition.
ENUM_GZ_PART_CLASS GZPartitionClassify(const GZ_Partition &p, datetime start, datetime end_excl)
  {
   if(!p.valid) return GZ_PC_INVALID;
   if(start<=0 || end_excl<=start) return GZ_PC_INVALID;
   if(start < p.hist_start || end_excl > p.hist_end) return GZ_PC_OUTSIDE_HISTORICAL;

   if(start >= p.dev_start && end_excl <= p.dev_end) return GZ_PC_DEVELOPMENT;
   if(start >= p.oos_start && end_excl <= p.oos_end) return GZ_PC_FINAL_OOS;
   if(start >= p.leg_start && end_excl <= p.leg_end) return GZ_PC_LEGACY_TOUCHED;

   long touched = GZPartOverlapSeconds(start, end_excl, p.dev_start, p.dev_end)
                + GZPartOverlapSeconds(start, end_excl, p.oos_start, p.oos_end)
                + GZPartOverlapSeconds(start, end_excl, p.leg_start, p.leg_end);
   if(touched<=0) return GZ_PC_UNASSIGNED;
   return GZ_PC_CROSSES_BOUNDARY;
  }

//--- first instant of the partition part a class belongs to (warm-up floor). Other classes: no floor (0).
datetime GZPartitionPartStart(const GZ_Partition &p, ENUM_GZ_PART_CLASS cls)
  {
   switch(cls)
     {
      case GZ_PC_DEVELOPMENT:    return p.dev_start;
      case GZ_PC_FINAL_OOS:      return p.oos_start;
      case GZ_PC_LEGACY_TOUCHED: return p.leg_start;
      default:                   break;
     }
   return 0;
  }

//--- Research range from a partition part: [start, end_excl) -> inclusive end = end_excl - 1 M1 minute, then the
//--- existing M5 alignment (GZRangeFinalize).
void GZRangeFromPartitionPart(ENUM_GZ_RANGE_KIND kind, string label, datetime start, datetime end_excl, GZ_ResearchRange &r)
  {
   r.Clear();
   r.kind = kind;
   r.label = label;
   r.req_start = start;
   r.req_end   = GZExclusiveToInclusiveEnd(end_excl);
   GZRangeFinalize(r, true);
  }

//+------------------------------------------------------------------+
//| Research gate                                                      |
//+------------------------------------------------------------------+
struct GZ_ResearchGate
  {
   bool               allowed;
   ENUM_GZ_PART_CLASS part_class;
   string             label;    // DEVELOPMENT | REGRESSION_ONLY_LEGACY | <class name of a refused range>
   string             reason;

   void Clear() { allowed = false; part_class = GZ_PC_INVALID; label = ""; reason = ""; }
  };

void GZPartitionGate(const GZ_Partition &p, const GZ_ResearchRange &r, GZ_ResearchGate &g)
  {
   g.Clear();
   if(!p.valid)
     {
      g.label = "PARTITION_INVALID";
      g.reason = "research NOT run: the partition configuration is invalid: " + p.error;
      return;
     }
   if(r.status != GZ_RSTATUS_OK)
     {
      g.label = "RANGE_INVALID";
      g.reason = StringFormat("research NOT run: invalid research range (%s: %s).", GZRStatusToString(r.status), r.note);
      return;
     }

   datetime start    = r.eff_start;
   datetime end_excl = GZInclusiveToExclusiveEnd(r.eff_end);
   g.part_class = GZPartitionClassify(p, start, end_excl);
   g.label = GZPartClassToString(g.part_class);

   switch(g.part_class)
     {
      case GZ_PC_DEVELOPMENT:
         g.allowed = true;
         g.reason = "range lies fully inside the DEVELOPMENT partition - research allowed.";
         return;
      case GZ_PC_LEGACY_TOUCHED:
         if(r.kind == GZ_RANGE_LEGACY_DEV)
           {
            g.allowed = true;
            g.label = "REGRESSION_ONLY_LEGACY";
            g.reason = "LEGACY_DEV range inside the LEGACY/TOUCHED partition: allowed ONLY as the labelled REGRESSION check of the validated baseline (412 trades, TP 2R, BE off). It must NOT be used for selection.";
            return;
           }
         g.reason = "research REFUSED: the range lies inside the LEGACY/TOUCHED partition (data already observed in earlier phases; it is never treated as clean OOS and never researched).";
         return;
      case GZ_PC_FINAL_OOS:
         g.reason = "research REFUSED: the range lies inside the NEW FINAL OOS partition. It is executed only once, after a candidate is defined for the research cycle (Phase 16), never for selection, tuning or comparison.";
         return;
      case GZ_PC_CROSSES_BOUNDARY:
         g.reason = "research REFUSED: the range crosses a partition boundary (it would mix Development with Final OOS / Legacy / unassigned data). Choose a range fully inside DEVELOPMENT. The range is never shifted or clipped.";
         return;
      case GZ_PC_UNASSIGNED:
         g.reason = "research REFUSED: the range lies in historical data that no partition covers (UNASSIGNED). Move the DEVELOPMENT start input earlier (or configure a partition for it) to make it researchable.";
         return;
      case GZ_PC_OUTSIDE_HISTORICAL:
         g.reason = "research REFUSED: the range starts before or ends after the Historical range.";
         return;
      default:
         g.reason = "research REFUSED: the range could not be classified (empty or reversed).";
         return;
     }
  }

//--- accepted-hole note for the identity metadata of a range (empty when the range does not contain the hole)
string GZAcceptedHoleNote(datetime eff_start, datetime eff_end)
  {
   if(eff_start < GZ_P157_ACCEPTED_HOLE_TO && eff_end > GZ_P157_ACCEPTED_HOLE_FROM)
      return "accepted documented data hole 2022-08-31 23:59 -> 2022-09-05 01:00 (no bars on 2022-09-01/02) lies inside this range; results carry that caveat.";
   return "";
  }

#endif // __GZ_PARTITION_MQH__
