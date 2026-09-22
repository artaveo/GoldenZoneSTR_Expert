# GoldenZone STR — Implementation Roadmap v1.0

## هدف
تبدیل Test Protocol v1.0 به یک برنامه اجرایی مرحله‌به‌مرحله برای Research/Backtest Engine در MQL5، با معماری قابل توسعه برای یک Execution Layer مستقل در آینده.

---

# Phase 1 — Data Layer + Validator + Time Engine
### هدف
ساخت پایه قابل اعتماد برای تمام Research.

### اجزا
- Data Loader برای XAUUSD، M1، M5 و در صورت نیاز M15
- Historical date range
- Data Validator:
  - Missing candles
  - Duplicate candles
  - Invalid OHLC
  - Timestamp ordering/gaps
  - M1/M5 synchronization
  - Symbol/timeframe consistency
  - Spread/volume availability
- Time Engine:
  - BROKER / UTC / NEW_YORK
  - DST AUTO / FIXED / DISABLED
  - Custom session windows
  - Broker/UTC/NY timestamps
  - DST state
  - Session ID
  - Inside-session flag

### خروجی
Dataset معتبر + Time Context استاندارد.

### شرط اتمام
اجرای تکراری روی یک Dataset و Configuration باید نتیجه یکسان بدهد.

---

# Phase 2 — M5 Structure Engine
### هدف
تشخیص Swing بدون Lookahead.

### Baseline
- M5
- Pivot Strength = 2
- Confirmation فقط بعد از بسته‌شدن کندل‌های لازم

### Research
Pivot Strength:
- 1, 2, 3, 4, 5

### Swing Record
- Swing ID
- High/Low
- Price
- Pivot candle
- Detection/confirmation timestamp
- Pivot strength

### شرط اتمام
هیچ Swingی قبل از زمان Confirmation وارد سیستم نشود.

---

# Phase 3 — Leg Engine + Break Engine
### Leg Engine
Baseline:
- آخرین confirmed meaningful opposite swing

Variants:
- Last confirmed swing
- Minimum-distance swing
- Minimum-ATR-distance swing

### Leg Record
- Leg ID
- Direction
- Origin swing/price
- Target swing
- Break timestamp
- Extreme price/time
- Leg size
- Duration

### Break Engine
Baseline:
- CLOSE break

Research:
- WICK break

Break Buffer:
- 0
- 0.05
- 0.10
- 0.15
- 0.20
- 0.30
- 0.50 ATR

ATR period:
- 5, 10, 14, 20, 30

### شرط اتمام
تمام Breakها فقط بر اساس اطلاعات قابل مشاهده در همان لحظه تولید شوند.

---

# Phase 4 — Fibonacci Engine + Setup State Machine
### Fibonacci
Bullish:
- 0% = Leg High
- 100% = Leg Origin Low

Bearish:
- 0% = Leg Low
- 100% = Leg Origin High

Research levels:
- 0.30 تا 0.90 با Grid اولیه
- شامل 0.78
- معماری قابل توسعه تا incrementهای 0.01

### Setup States
NO_SETUP
→ LEG_DETECTED
→ BREAK_CONFIRMED
→ LEG_LOCKED
→ FIB_ACTIVE
→ WAITING_ENTRY
→ ENTERED
→ EXITED

Cancellation:
- Opposite break
- New valid setup
- Session end
- Invalid penetration
- Data end
- Invalid data

### شرط اتمام
هر Setup باید Lifecycle کامل و Terminal Reason داشته باشد.

---

# Phase 5 — Entry Engine + Historical Trade Simulator
### Entry
Baseline:
- TOUCH

Variants:
- LIMIT
- CLOSE_CONFIRMATION
- M1_CONFIRMATION

Confirmation:
- 1 تا 3 candle

Penetration:
- 0
- 0.02
- 0.05
- 0.10
- 0.15 ATR

### Trade Record
- Trade ID
- Setup ID
- Entry timestamp
- Entry price
- Direction
- Fib level
- Entry model
- Spread assumption
- Slippage assumption
- Initial risk

### شرط اتمام
یک Dataset و Configuration یکسان همیشه همان Trades را تولید کند.

---

# Phase 6 — Exit Engine: SL / TP / BE
### SL Models
- Structure-based: Leg Origin ± buffer
- ATR-based: configurable multiplier
- Architecture extensible for future models

### TP Research
- 0.5R
- 1R
- 1.5R
- 2R
- 2.5R
- 3R
- 3.5R
- 4R
- 4.5R
- 5R
- قابل توسعه بالاتر از 5R

### BE Research
Trigger:
- OFF
- 0.25R
- 0.50R
- 0.75R
- 1R
- 1.25R
- 1.50R
- 1.75R
- 2R
- 2.5R
- 3R
- 4R
- 5R

BE level:
- Entry
- Entry ± configurable R offset

### Intrabar Conflict
اگر در یک M1 هر دو SL و TP لمس شوند و ترتیب مشخص نباشد:
- ambiguity ثبت شود
- policy قابل تنظیم باشد
- ترتیب فرضی مخفی وارد سیستم نشود

### Exit Reasons
- TP_HIT
- SL_HIT
- BREAK_EVEN
- SESSION_EXIT
- DATA_END
- OTHER

---

# Phase 7 — MAE / MFE / R-Path / Event Ledger
### هدف
ثبت رفتار کامل Setup و Trade، نه فقط معاملات نهایی.

### Reach Matrix
حداقل:
0.5R / 1R / 1.5R / 2R / 2.5R / 3R / 3.5R / 4R / 4.5R / 5R

### ثبت
- MAE
- MFE
- Time to MAE
- Time to MFE
- Trade duration
- R-multiple path

### Event Ledger
ثبت:
- Valid setups
- Cancelled setups
- Invalidated setups
- Entries
- Exits
- Rejection reasons
- Filter results

---

# Phase 8 — Metrics + Reporting
### Trade Metrics
- Total trades
- Winners / Losers
- Win rate
- Average win/loss
- Profit Factor
- Expectancy
- Net R
- Average R

### Risk
- Max DD
- Average DD
- DD duration
- Max losing streak
- Max winning streak

### Behavior
- MAE
- MFE
- Duration
- Time to MAE/MFE

### Breakdown
- Long/Short
- Hour
- Session
- Day of week
- Month
- Date range

### Filter Diagnostics
- Setups before/after
- Trades before/after
- Rejections
- Win-rate delta
- PF delta
- Expectancy delta
- DD delta
- Trade-count delta

---

# Phase 9 — Experiment Configuration + Runner
### Modes
- SINGLE
- SWEEP
- GRID
- BATCH

### Experiment ID
مثال:
`GZ_000001`

هر Result باید شامل:
- Experiment ID
- Dataset ID
- Full configuration
- Strategy version
- Date range
- Metrics
- Warnings
- Data validation status

### Rule
از Grid عظیم همزمان استفاده نشود؛ Research مرحله‌ای باشد:
Fib → Exit → Single Filters → Combinations → Robustness

---

# Phase 10 — Filter Engine
هر Filter:
- PASS
- FAIL
- NOT_AVAILABLE

NOT_AVAILABLE نباید خودکار PASS شود.

### Filters
1. Break Quality
2. Leg Quality
3. Volume
4. Volatility
5. VWAP
6. M15 Context
7. Session
8. News

هر Filter:
- OFF
- INCLUDE
- EXCLUDE

---

# Phase 11 — Filter Combination Research
### R11-A
Single Filter

### R11-B
Two-Filter:
- Break Quality × Volume
- Break Quality × VWAP
- Leg Quality × Volume
- Volume × VWAP
- Volume × Volatility
- VWAP × M15
- و ترکیبات قابل توجیه دیگر

### R11-C
Multi-Filter محدود، فقط بر اساس نتایج مراحل قبلی.

تمام Configurationها باید قابل بازسازی باشند.

---

# Phase 12 — Robustness + Sensitivity
### هدف
بررسی وابستگی نتیجه به یک عدد خاص.

مثال برای 1.50 ATR:
- 1.25
- 1.35
- 1.40
- 1.50
- 1.60
- 1.65
- 1.75

Flagها:
- Narrow peak
- Flat region
- Unstable zone
- Parameter sensitivity

بالاترین مقدار تاریخی به‌تنهایی به‌عنوان انتخاب نهایی پذیرفته نشود.

---

# Phase 13 — Walk-Forward Research
### ساختار
Train → Validate → Move Window → Train → Validate

Configurable:
- Training length
- Validation length
- Step size
- Minimum trades

برای هر Window:
- Training result
- Selected configuration
- Validation result
- Stability information

---

# Phase 14 — Monte Carlo Research
### تحلیل‌ها
- Trade-order randomization
- Return-sequence randomization
- Drawdown distribution
- Losing-streak distribution
- Equity-path variation

ثبت:
- Number of simulations
- Seed
- Median
- Percentiles
- Worst simulated cases

Original historical ledger نباید تغییر کند.

---

# Phase 15 — Final OOS
### قوانین
Final OOS:
- در Optimization استفاده نمی‌شود
- در Filter selection استفاده نمی‌شود
- در Parameter tuning استفاده نمی‌شود
- جداگانه گزارش می‌شود

خروجی:
- OOS trades
- PF
- Expectancy
- DD
- MAE/MFE
- Distribution
- مقایسه با Development/Validation

---

# Phase 16 — Research Freeze
موارد Freeze:
- Symbol
- Timeframes
- Swing
- Leg
- Break
- Fib
- Entry
- SL
- TP
- BE
- Filters
- Session
- News
- Cost model
- Execution assumptions

هر تغییر مهم:
`GZ_STR v1.0 → GZ_STR v1.1`

و Research cycle جدید.

---

# Phase 17 — Future Execution Architecture
## تصمیم معماری

Research Engine و Live Execution نباید دو پیاده‌سازی مستقل از منطق Strategy داشته باشند.

معماری پیشنهادی:

### Shared Strategy Core
- Structure Engine
- Leg Engine
- Break Engine
- Fib Engine
- Filter Engine
- Setup State Machine

### Research Adapter
- Historical Data
- Trade Simulator
- Exit Simulator
- Experiment Runner
- Metrics
- Results Store

### Future Execution Adapter
- Current market data
- همان Strategy Core
- Order/Position management
- Execution logging
- Risk controls

نمای کلی:

`SHARED STRATEGY CORE`
→ `RESEARCH ADAPTER`
→ Historical Simulation

و

`SHARED STRATEGY CORE`
→ `FUTURE EXECUTION ADAPTER`
→ Live/Forward Execution

## نکته
برای Research فعلی، فقط Simulation/Backtest پیاده‌سازی می‌شود. هر قابلیت اجرای واقعی باید بعداً به‌عنوان Execution Layer مستقل و کنترل‌شده ساخته و جداگانه اعتبارسنجی شود.

---

# Phase 18 — Final Architecture + Definition of Done

## Architecture
Historical Data
→ Data Validator
→ Time Engine
→ Structure Engine
→ Leg Engine
→ Break Engine
→ Fib Engine
→ Filter Engine
→ Setup State Machine
→ Entry Engine
→ Exit Engine
→ Trade Simulator
→ Event/Trade Ledger
→ Metrics Engine
→ Experiment Runner
→ Results Store
→ Robustness
→ Walk-Forward
→ Monte Carlo
→ Final OOS

## Definition of Done
سیستم زمانی کامل است که:
- deterministic باشد
- Lookahead نداشته باشد
- Setup lifecycle کامل ثبت شود
- Trade configuration کامل ذخیره شود
- MAE/MFE وجود داشته باشد
- SL/TP/BE مستقل قابل تحقیق باشند
- Filters مستقل قابل فعال/غیرفعال‌سازی باشند
- Experimentها reproducible باشند
- Parameter sweep خودکار باشد
- Results export شوند
- IS/Validation/OOS جدا باشند
- Walk-Forward وجود داشته باشد
- Monte Carlo وجود داشته باشد
- Strategy قابل versioning/freeze باشد
- Strategy Core از Research Simulator مستقل و reusable باشد

---

# Master Implementation Order

1. Data + Validator + Time Engine
2. M5 Structure
3. Leg + Break
4. Fibonacci + Setup State Machine
5. Entry + Simulator
6. Exit Engine
7. MAE/MFE + Event Ledger
8. Metrics + Reports
9. Experiment Runner
10. Filter Engine
11. Filter Combinations
12. Robustness
13. Walk-Forward
14. Monte Carlo
15. Final OOS
16. Research Freeze
17. Future Execution Adapter

## Version
GoldenZone STR — Implementation Roadmap v1.0
