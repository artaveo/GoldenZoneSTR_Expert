# GoldenZone STR — Implementation Roadmap v1.0

## هدف
تبدیل Test Protocol v1.0 به یک برنامه اجرایی مرحله‌به‌مرحله برای Research/Backtest Engine در MQL5، با معماری قابل توسعه برای یک Execution Layer مستقل در آینده.

---

## قانون تحویل هر فاز (Deliverable Convention) — اضافه‌شده بعد از فاز First_Change_In_Structure
هر بار که Claude یک فاز را با فایل zip (Experts+Include) تحویل می‌ده، باید بلافاصله بعد از لینک دانلود، این سه مورد را هم دقیق مشخص کنه — بدون این‌ها تحویل ناقصه:

1. **اسم دقیق ورودی‌ها** — همون‌طور که در دیالوگ Inputs متاتریدر دیده می‌شن (مثلاً `InpUseSessionHourGate`)، نه توضیح یا نسخهٔ خلاصه‌شده.
2. **یک اجرای سریع برای تست کد** (چند روز یا حداکثر یک ماه دیتا، نه کل بازه) که فقط تأیید کنه کامپایل/تست‌های خودکار درستن.
3. **یک اجرای دقیق‌تر فقط برای همون فاز** — با اسم بردهٔ بازهٔ لازم (مثلاً LEGACY_DEV، نه کل ۲۰۲۰-۲۰۲۶ مگر واقعاً لازم باشه) و کدوم ورودی‌ها باید عوض بشن تا نتیجهٔ آن فاز خاص دیده بشه.

قانون نام‌گذاری ورودی که از فاز First_Change_In_Structure ثابت شده: هر جا اسم یک ورودی MT5 گفته می‌شه، باید همون رشتهٔ متغیر دقیق باشه (نه پارافریز)، و اگر توضیح لازمه، در پرانتز بعد از اسم بیاد.

---

## پیوست: فاز "Concurrent Same-Direction Setups + Opposite-Break Survival" + دنبالهٔ Daily Loss Limit / Max Concurrent Trades
این فاز بعد از فاز First_Change_In_Structure (FCIS - که خودش Session Hour Gate، real bid/ask fills، Minimum Risk Gate رو اضافه کرده بود) و در یک چت جدا انجام شد. تمام موارد زیر توی همون یک zip واحد پیاده شدن (فایل Experts+Include کامل، جایگزین نسخهٔ قبلی).

### زمینه
کاربر بعد از تست FCIS با سشن‌های مختلف متوجه شد که Filter اصلی تعداد تریدها، خودِ دو قانون قدیمی Phase 4 هستن (`GZ_CANCEL_NEW_VALID_SETUP` و `GZ_CANCEL_OPPOSITE_BREAK`)، نه گیت‌های جدید FCIS. برای همین خواست این دو قانون رو هم به‌صورت آزمایشی قابل خاموش‌کردن باشن.

### چهار سوییچ جدید (روی `CGZSetupStateMachine` و `CGZEntryEngine`/`CGZTradeSimulator`)
| ورودی (اسم دقیق متغیر) | چیکار می‌کنه | دیفالت فعلی |
|---|---|---|
| `InpAllowConcurrentSameDirectionSetups` (Switch A) | یک لگ هم‌جهت جدید دیگه ستاپ قدیمی‌تر رو کنسل نمی‌کنه (`GZ_CANCEL_NEW_VALID_SETUP` غیرفعال) - چند ستاپ هم‌جهت می‌تونن هم‌زمان باز بمونن | `false` |
| `InpAllowSurviveOppositeBreak` (Switch B) | یک break مخالف‌جهت دیگه ستاپ باز رو کنسل نمی‌کنه (`GZ_CANCEL_OPPOSITE_BREAK` غیرفعال) | `false` |
| `InpUseDailyLossLimit` | وقتی مجموع R معاملات بسته‌شدهٔ همون روز بروکر به `-InpDailyLossLimitR` برسه، تا آخر همون روز دیگه ترید جدید باز نمی‌شه (تریدهای باز دست نمی‌خورن؛ روز بعد خودکار ریست می‌شه) | **`true`** |
| `InpDailyLossLimitR` | آستانهٔ ضرر روزانه به واحد R (پیش‌فرض `3.0` = تقریباً سه استاپ پشت‌سرهم؛ مستقل از درصد ریسک چون R نرمالایزه) | `3.0` |
| `InpUseMaxConcurrentTrades` | جلوی باز شدن ترید جدید رو می‌گیره اگه از قبل `InpMaxConcurrentOpenTrades` ترید باز باشه (ستاپ در WAITING_ENTRY می‌مونه، بعداً که یه ترید بسته شد دوباره امتحان می‌کنه) | **`true`** |
| `InpMaxConcurrentOpenTrades` | سقف تعداد ترید هم‌زمان باز | `3` |

هر چهار سوییچ مستقل از هم‌ان و فقط trigger ورود رو "این بار skip می‌کنم" - هیچ‌کدوم ستاپ رو کنسل نمی‌کنن یا ترید باز رو force-close نمی‌کنن.

### دیاگنوستیک‌های جدید (در گزارش `GZ_PhaseConcurrency_Report.txt`)
- Peak تعداد ستاپ‌های non-terminal هم‌زمان، Peak تعداد ترید باز هم‌زمان (همیشه گزارش می‌شن، مستقل از سوییچ‌ها)
- شمارندهٔ "چقدر cancel که قرار بود بیفته، به‌خاطر Switch A/B نیفتاد"
- شمارندهٔ "چند بار ورود به‌خاطر Daily Loss Limit / Max Concurrent Trades بلاک شد"

### تست‌های جدید: T250 تا T263 (مجموع تست‌ها الان ۲۶۳ تاست)
T250-T256: رفتار Switch A/B (تنها، هردو، تداخل). T257-T261: گیت‌های جدید در سطح `CGZEntryEngine` (منفرد). T262-T263: رفتار end-to-end `CGZTradeSimulator` (بلاک‌شدن همون روز + ریست روز بعد) با دیتاست واقعی از موتور.

### تغییر مهم: دیفالت‌های هزینه/اسپرد/اسلیپیج دیگه واقعی‌ان
کاربر متوجه شد چند اجرا رو بدون اسپرد/کارمزد گرفته بوده (بی‌فایده، چون نتیجه خیلی خوش‌بینانه‌تر از واقعیت بود). این ورودی‌ها دیگه پیش‌فرضشون خاموش/صفر نیست:

| ورودی | دیفالت قبلی | دیفالت الان |
|---|---|---|
| `InpUseRealSpreadFills` | `false` | **`true`** |
| `InpCostsConfigured` | `false` | **`true`** |
| `InpCostSpreadMode` | `GZ_COST_SPREAD_RECORDED` | **`GZ_COST_SPREAD_FIXED`** (با `InpCostFixedSpreadPts=0` تا اسپرد دوبار کم نشه - چون `InpUseRealSpreadFills=true` از قبل داخل شبیه‌سازی اسپرد رو حساب می‌کنه) |
| `InpCostCommissionPercent` | `0.0` | **`0.0016`** (نرخ FundedNext Stellar) |
| `InpCostSlippagePts` | `0.0` | **`10.0`** |

⚠️ نتیجهٔ این تغییر: عدد تاریخی «۴۱۲ ترید روی LEGACY_DEV» فقط زمانی صدق می‌کنه که **همهٔ** این سوییچ‌ها (هر ۴ سوییچ این فاز + هر ۳ سوییچ FCIS) صریحاً `false` گذاشته بشن؛ با دیفالت‌های فعلی، یک اجرای تازه دیگه ۴۱۲ نمی‌ده (چون خودِ Real Spread Fills / Daily Loss Limit / Max Concurrent هم روی نتیجه اثر می‌ذارن). گزارش فاز (بخش F) این رو صریح چک و گزارش می‌کنه.

### تغییر دیگه: کامنت جلوی همهٔ Inputها حذف شد
چون MetaTrader 5 وقتی جلوی یک `input` کامنت (`//...`) باشه، توی پنل Inputs **به‌جای اسم متغیر همون کامنت رو نشون می‌ده**، و کاربر ترجیح داد اسم واقعی متغیرها رو ببینه، تمام کامنت‌های توضیحی جلوی هر ۱۲۲ خط `input` این فایل حذف شدن. یعنی از این فاز به بعد، پنل Inputs متاتریدر دقیقاً اسم متغیر (`InpAllowConcurrentSameDirectionSetups` و امثالش) رو نشون می‌ده، نه توضیح. توضیحات هر ورودی فقط داخل خودِ کد (بالای هر بخش، به‌صورت کامنت جداگانه) و در چت باقی موندن.

### وضعیت فعلی / قدم بعدی
اجراهای قبلی (baseline / A-only / B-only / both-on) همه بدون اسپرد/هزینه گرفته شده بودن - قابل مقایسه نیستن با اجراهای بعدی. کاربر قصد داره یک اجرای تازه با هر دو Switch A و B روشن (به‌همراه Daily Loss Limit و Max Concurrent که الان دیفالتشون روشنه) بگیره و وین‌ریت/PF رو ببینه. فاز ۱۶ (Research Freeze) هنوز شروع نشده.

---

## پیوست: فاز "Cost Unification + R-Symmetry Fix"
بعد از فاز FCIS و فاز Concurrency، کاربر متوجه چند تناقض در گزارش‌ها شد (وین‌ریت لانگ/شورت تقریباً یکسان ولی نت-R خیلی متفاوت؛ گزارش‌های Phase 8/9/12/13/15 هزینه رو حساب نمی‌کردن با اینکه InpCostsConfigured=true بود؛ متن گزارش ادعای اشتباه دربارهٔ short ask-fill می‌داد؛ رفرنس‌های بیس‌لاین ۴۱۲-تریدی با هم نمی‌خوندن). Claude مخزن گیت‌هاب رو کلون کرد، ۵ باگ واقعی رو در کد پیدا کرد و پیاده‌سازی کرد.

### باگ ۱ — عدم‌تقارن R بین لانگ و شورت (تأیید شد، جدی بود)
در `GZ_ExitEngine.mqh`، `initial_risk` یک شورت هیچ‌وقت هزینهٔ اسپردی که در خروج (ask) پرداخت می‌شه رو پیش‌بینی نمی‌کرد، در حالی که لانگ چون قیمت ورودش از اول ask بود، این هزینه از قبل توی `initial_risk` اش بود. نتیجه: SL شورت همیشه کمی بدتر از -1R می‌بست و TP شورت هم کمی کمتر از هدف. راه‌حل: دو تابع جدید `AnticipatedSlPriceIfShort` و `AnticipatedTpLevelIfShort` که هم مخرج ریسک و هم سطح TP ذخیره‌شدهٔ شورت رو طوری اصلاح می‌کنن که SL دقیقاً -1.000R و TP دقیقاً روی مضرب کانفیگ‌شده ببنده - دقیقاً مثل لانگ. با `InpUseRealSpreadFills=false` رفتار کاملاً بدون تغییر می‌مونه (تست‌شده). تست‌های T269-T271.
تأیید واقعی از اجرای شما: `AvgWinR=1.000 AvgLossR=0.999` در گزارش اصلی - قبل از فیکس این دو عدد برای شورت به‌وضوح از ۱ فاصله داشتن.

### باگ ۲ — هزینه (کمیسیون+اسلیپیج) فقط توی گزارش Phase 15.5 حساب می‌شد
`GZ_ExperimentConfig` هیچ فیلدی برای کانفیگ هزینه نداشت، پس `CGZExperimentRunner::Execute()` - که Phase 9/12/13/15 همه از همون رد می‌شن - اصلاً نمی‌تونست هزینه حساب کنه. یک فیلد `cost_config` به `GZ_ExperimentConfig` و یک فیلد موازی `net_metrics` به `GZ_ExperimentResult` اضافه شد؛ حالا Robustness/Walk-Forward/Final OOS همه خودکار این رو به ارث می‌برن (چون `GZ_ExperimentConfig` رو کامل کپی می‌کنن). گزارش‌های Phase 12/13/15 هم آپدیت شدن تا ستون‌های Net رو کنار Gross چاپ کنن (این بخش رو بعد از یک بازبینی اضافه اضافه کردم، چون اول فقط داده رو وصل کرده بودم، متن گزارش رو نه). تست‌های T272-T274.

### باگ ۳ — احتمال دوبار کم‌شدن اسپرد
اگه `InpUseRealSpreadFills=true` و `InpCostSpreadMode=RECORDED` هر دو با هم روشن بودن، اسپرد هم توی شبیه‌سازی و هم توی لایهٔ هزینهٔ پسا-اجرا کم می‌شد. راه‌حل ساختاری (نه فقط هشدار متنی): `GZCost_ComputeCostPrice` یک پارامتر `real_spread_fills_active` گرفت که وقتی true باشه، جزء اسپرد رو در کد صفر می‌کنه، مهم نیست spread_mode چی باشه. تست T275.

### باگ ۴ — متن قدیمی و اشتباه در گزارش‌ها
جمله‌ای که می‌گفت "خروج شورت واقعاً روی ask زده می‌شه و این مدل نشده" - این از قبل از FCIS Step 2 بود و دیگه درست نیست (الان واقعاً مدل شده). این جمله در **سه جای مختلف** پیدا و اصلاح شد: `GZ_RewardBeEngine.mqh` (بخش I گزارش Phase 15.5)، خودِ فایل اصلی `.mq5` (بخش E گزارش Phase 15.8) و کامنت طراحی داخل `GZ_CostTypes.mqh`. متن جدید بسته به `InpUseRealSpreadFills` شاخه می‌ره: اگه true باشه می‌گه "اسپرد از این لایه به‌خاطر جلوگیری از دوبار حساب کردن حذف شده"، اگه false باشه توضیح تقریبی قدیمی رو با محدودیتش نگه می‌داره.

### باگ ۵ — رفرنس‌های بیس‌لاین (۴۱۲ ترید/۵۰.۷٪/...) در چند جا تکراری بودن
فقط **دو** جای واقعی این مقایسه بود (نه سه‌تا که حدس اولیه بود): `R07` توی فایل اصلی و `V03` توی `GZ_RewardBeEngine.mqh`. هر دو الان از یک تابع مشترک (`GZBaselineCompare`, فایل جدید `GZ_BaselineCompare.mqh`) استفاده می‌کنن که یک نتیجهٔ سوم و مشخص هم داره: `BASELINE_NOT_APPLICABLE_THIS_CONFIG` - وقتی کانفیگ فعلی (TP، سوییچ‌های FCIS، هزینه) با کانفیگی که این رفرنس‌ها براش ثبت شدن یکی نیست، این پیام میاد، نه FAIL و نه PASS. تست‌های T276-T277.

### تست‌های جدید: T269 تا T277 (فایل جدید `GZ_CostRSymTests.mqh`)
مجموع تست‌ها الان ۲۷۷ تاست. یک انحراف کوچیک از متن اولیهٔ پرامپت لازم شد و به کاربر اطلاع داده شد: فرمول TP شورت هم (نه فقط `initial_risk`) باید اصلاح می‌شد تا TP دقیقاً روی مضرب کانفیگ‌شده ببنده.

### فایل‌های تغییر یافته
`GZ_ExitEngine.mqh` (باگ ۱)، `GZ_CostTypes.mqh` + `GZ_CostEngine.mqh` (باگ ۳)، `GZ_ExperimentTypes.mqh` + `GZ_ExperimentRunner.mqh` (باگ ۲)، `GZ_WalkForwardTypes.mqh` + `GZ_WalkForwardEngine.mqh` و `GZ_FinalOosTypes.mqh` + `GZ_FinalOosEngine.mqh` (چاپ Net در گزارش)، `GZ_RewardBeEngine.mqh` (باگ‌های ۳/۴/۵)، `GZ_BaselineCompare.mqh` و `GZ_CostRSymTests.mqh` (جدید)، `GZ_TestHarness.mqh` (قلاب تست جدید)، فایل اصلی `.mq5` (R07، بخش D و E گزارش، اتصال `exp_cfg.cost_config`).
هیچ ورودی/کلاس/متد/فایلی تغییر نام نداد.

### وضعیت
پیاده‌سازی شده و توسط کاربر روی MT5 واقعی اجرا و تأیید شده (۲۷۷/۲۷۷ تست PASS، ماتریس LONG/SHORT حالا متقارنه). قبل از این اجرا، فقط بازبینی دستی کد انجام شده بود (این محیط کامپایلر MT5 نداره).

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
GoldenZone STR — Implementation Roadmap v1.3
(v1.1: added the Deliverable Convention paragraph after Phase First_Change_In_Structure.
 v1.2: added the "Concurrent Same-Direction Setups + Opposite-Break Survival" appendix above,
 including its Daily Loss Limit / Max Concurrent Trades follow-up and the input-comment removal.
 v1.3: added the "Cost Unification + R-Symmetry Fix" appendix above - Long/Short R-symmetry fix,
 cost-engine wiring into CGZExperimentRunner::Execute() (and Robustness/Walk-Forward/Final OOS
 report printing), the structural double-spread-charge guard, three corrected copies of a stale
 report claim, and one shared baseline-comparison function with a new NOT_APPLICABLE verdict;
 tests T269-T277, confirmed by the user in real MT5.
 v1.3.1: added a per-calendar-year breakdown to Phase 8's GZ_MetricsSummary (GZ_YearBucket:
 trades/win_rate/net_r/PF plus that year's OWN drawdown/losing-streak, independent of other years),
 printed as a "By year" table in the main report - for reading a multi-year Development-partition
 run (e.g. 2020.07.01-2025.01.01) at a glance, one run, no code needed per year.
 v1.3.2: the formerly-reserved "M15 Context" filter slot (GZ_FILTER_M15_CONTEXT / InpFilterM15ContextMode -
 names unchanged) is now a REAL HTF Bias filter: higher-timeframe trend = last COMPLETED HTF bar's close vs the
 EMA of HTF closes (bars built from the loaded M5 series; new inputs InpFilterHtfPeriodMinutes=60,
 InpFilterHtfEmaPeriod=50), read at the setup's break_time with no lookahead; INCLUDE keeps trend-aligned setups.
 Applied post-hoc like every Phase 10 filter; the Phase 10 report section now also prints the FILTERED
 population (win rate, PF, drawdown, by direction, by year). Tests T278-T284. Found while testing entry models:
 GZ_ENTRY_TOUCH fills at the M1 bar's extreme (bar.low/bar.high), which is optimistic vs GZ_ENTRY_LIMIT -
 on LEGACY_DEV TOUCH gave 60.6%/+87R while LIMIT gave 40.9%/-71R; LIMIT is the honest baseline.)
