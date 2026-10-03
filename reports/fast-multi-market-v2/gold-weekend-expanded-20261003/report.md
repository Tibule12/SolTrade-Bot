# Gold Friday M1 to Monday continuation — expanded broker-history test

**Finding: the final completed Friday M1 candle does not show a usable same-direction Monday continuation effect in this FP demo broker sample. No trade was placed, scheduled, queued or modified.** The primary rule was kept exactly as requested: BUY when the last completed Friday M1 bid close exceeds its open, SELL when it falls. Other Friday definitions are secondary. The predeclared [protocol](protocol.json) and full [M1-first results](analysis/primary.json) retain the denominator, ambiguous bars, chronological split and all tested entry methods.

## History recovery and original failure

The original study returned exactly 100,000 M1 bars and failed 12 older weekly `CopyRates` calls. That was a terminal-history limit, not proof the broker lacked those weeks: the isolated terminal returned 1,328,340 bars from January 2023 after its chart limit was raised to 2,000,000, with zero weekly failures. A final 5,000,000-bar setting returned **2,336,387 XAUUSD.r M1 bars**, from **28 February 2020 01:00** to **2 October 2026 23:59 broker-server time**. Its only eight failed requests were entirely before the broker's recorded February 2020 history start; each returned MT5 error `4401`. The full export contains **327 complete Friday-to-Monday pairs** after requiring a Monday session and 14 earlier days for ATR. The original 100,000 bars match the overlapping full export **100,000/100,000 rows with zero field differences**. [Full export receipt](broker-export-full/receipt.json) · [per-week MT5 responses](broker-export-full/requests-20261003-full.csv) · [verified compressed M1 bars](broker-export-full/m1-20261003-full.csv.gz) · [raw-data hashes](history-hashes.json).

The old exporter did not log its per-call error code or terminal limit, so the exact cause of each of its 12 calls cannot be proven individually. The 100,000-row cutoff and complete recovery when `MaxBars` increased are strong evidence for the limit. [MT5's `CopyRates` documentation](https://www.mql5.com/en/docs/series/copyrates) states that a request outside `TERMINAL_MAXBARS` or the server's available interval can return `-1`.

## Primary: last Friday M1 only

Of 327 usable weekends, **315** final Friday M1 candles were directional: **149 BUY**, **166 SELL**; 12 were flat and made no directional prediction. Monday's opening bid gap matched the M1 direction **142/315 (45.1%)**. A same-direction trade entered at the first Monday M1 open and measured four hours later was positive **156/315 (49.5%)** and negative **159/315 (50.5%)**, with estimated **−$0.40/oz mean** and **−$0.01/oz median**. The weekend bootstrap 95% interval for mean return is **−$2.39 to +$1.56/oz**. This bar estimate includes the reported opening spread but no commission or alternative-fill slippage.

| Final M1 signal | Weekends | Four-hour positive | Mean four-hour $/oz | +$5 first / −$5 first | +$10 first / −$10 first | +$20 first / −$20 first |
|---|---:|---:|---:|---:|---:|---:|
| BUY | 149 | 75 | +0.35 | 55 / 47 | 17 / 36 | 14 / 12 |
| SELL | 166 | 81 | −1.06 | 64 / 66 | 41 / 45 | 24 / 23 |
| Combined | **315** | **156** | **−0.40** | **119 / 113** | **58 / 81** | **38 / 35** |

Those are **first-hit counts within four hours**, not final profits. At $5, 12 bars touched both sides within the same minute, 70 reached neither boundary and one path was censored by a quote gap. At $10, there were three same-minute ambiguities, 172 neither and one censored. At $20, one ambiguity, 240 neither and one censored. In the resolved $10 paths, the favorable side won **58/139 = 41.7%**, Wilson 95% interval **33.9%–50.0%**. Ambiguous bars are never assigned a winner. [Per-weekend paths and signals](analysis/weekends.jsonl) · [all signal × side × method tables](analysis/results.csv).

The chronological split is **228 weekends through 18 October 2024** for the first segment and **99 later weekends** for the untouched second segment. The M1 rule had 216 directional cases in the first segment: mean four-hour return **−$0.22/oz**, with $10 favorable/adverse first **23/30**. In the later 99 it averaged **−$0.77/oz**, with $10 first **35/51**. The later mean's 95% bootstrap interval is broad (**−$6.66 to +$5.45/oz**), but it does not confirm a favorable effect. Across all 327 weekends, unconditional Monday BUY averaged **+$0.51/oz**, unconditional SELL **−$0.80/oz**, and a 50/50 random direction **−$0.14/oz** after estimated spread. Against a 50/50 random Monday direction on the **same 315 M1-directional weekends**, the M1 choice changed mean return by **−$0.25/oz** (paired bootstrap interval **−$2.24 to +$1.70**). Neither a profitable nor a reliably inverse M1 signal is established.

## Entry timing, adverse movement and secondary definitions

The following rows use the **same M1 Friday signal**. Conditional mean is over cases where the entry rule fired; paired change compares that rule with immediate entry on exactly those same weekends. Missing triggers are retained as no-entry cases in [the full method receipt](analysis/primary.json).

| Monday entry | Entries / 315 | Four-hour mean $/oz after entry | Paired change vs immediate $/oz |
|---|---:|---:|---:|
| Immediate reopen | 315 | −0.40 | — |
| After 15 minutes | 314 | −0.23 | +0.14 |
| After 30 minutes | 315 | −0.40 | −0.00 |
| First completed H1 in M1 direction | 296 | +0.36 | −0.86 |
| $5 push, $2 pullback, $1 close breakout | 79 | −1.54 | −12.57 |
| $1 close beyond first 30-minute range | 157 | −2.28 | −9.07 |

The positive conditional mean for directional H1 is selection: on the same 296 selected weekends, waiting was worse than immediate entry. No confirmation method materially improved this M1 rule in the paired comparison. Later methods are bar estimates with fixed trigger definitions, and none was optimized after seeing outcomes.

For the immediate M1 rule, the later endpoints are shown separately rather than being used to replace the predeclared four-hour primary test:

| Exit after Monday entry | Observed paths | Mean $/oz | Mean difference from 50/50 direction on same paths, bootstrap 95% interval |
|---|---:|---:|---:|
| 15 minutes | 314 | −0.72 | −0.55 [−1.50, +0.37] |
| 30 minutes | 315 | −0.53 | −0.37 [−1.60, +0.79] |
| 1 hour | 315 | −0.43 | −0.26 [−1.55, +0.97] |
| 4 hours | 315 | −0.40 | −0.25 [−2.24, +1.70] |
| London close, clock proxy | 315 | +1.21 | +1.34 [−2.36, +5.03] |
| New York close, clock proxy | 285 | +1.21 | +1.40 [−3.03, +5.77] |
| Last Monday broker bar | 308 | +1.37 | +1.57 [−2.36, +5.45] |

The later positive estimates have wide intervals that include zero against random direction, and New York/full-Monday coverage is incomplete. They do not validate the M1 signal.

For immediate M1-direction entries that nevertheless finished positive after four hours, adverse excursion over those four hours had a **$2.69/oz median** and **$15.27/oz 90th percentile**. Across *all* 315 entries, median adverse excursion was **$4.95/oz**, 90th percentile **$24.41/oz**. These include movement after an earlier favorable move; they are **not** a measured stop distance or a guarantee of survival. Median first $5 favorable touch was 12 minutes and median first $5 adverse touch 10 minutes. [Primary path measurements](analysis/primary.json).

M15, H1, H4, whole Friday, close-in-range, ATR-scaled return, strong close and agreement cases were tested separately, with the fixed threshold grid in the [protocol](protocol.json). The most favorable *descriptive* secondary four-hour mean was Friday return at least 0.75 prior-day ATR (**+$2.52/oz across 82 cases**), but its 95% bootstrap interval **−$0.29 to +$5.58** crosses zero. A stricter strong-Friday combination (return ≥0.75 ATR and close in the outer 20% of the day's range) averaged **+$1.72/oz across 61 cases**, versus **+$1.08/oz** for the other 266 Friday-session directions; the difference is **+$0.64/oz** with a bootstrap interval of roughly **−$3.04 to +$4.85**. The strong subset's $10 first-hit count was **15 favorable / 15 adverse**, and only 15 cases were in the later segment. Predeclared sensitivity at 0.5/0.75/1.0 ATR and 10%/20%/30% range edges is fully reported in [primary.json](analysis/primary.json); no threshold gives credible evidence that a strong close beats ordinary Friday behavior. Secondary scans are multiple comparisons, so the largest descriptive mean is not a selected strategy.

The [detailed result table](analysis/results.csv) also includes 15/30/60/240-minute, London, New York and full-Monday endpoints. London/New York clock conversion uses `Europe/Athens` as an **unverified historical proxy** for FP broker server DST. Session values are labelled estimates and should not decide a trade without confirmed historical broker offset. Where a session-close quote is missing or stale, the value stays null.

## FXIFY size arithmetic, not an order

FXIFY lists **100 ounces per XAUUSD.r lot** in its [instrument specification](https://fxify.com/faqs/all-faqs/what-instruments-are-offered-by-fxify/). Thus a $0.50/$1/$2/$5/$10 gold move changes cash by approximately **$50/$100/$200/$500/$1,000 per lot**, before spread, commission and slippage. The table uses nominal $10K and $100K balances, a **$0.09/oz median FP reopen spread** and the formula `risk cash ÷ [100 × (stop move + $0.09)]`, rounded down to 0.01 lot for display. It is a theoretical arithmetic cap, **not** broker-valid FXIFY sizing: FXIFY's own historical spread, current account balances, lot increment, margin, commissions and gap fills were not queried.

| Reference balance | Stop / adverse move | 0.25% | 0.5% | 1.0% |
|---|---:|---:|---:|---:|
| $10K | $5 | 0.04 | 0.09 | 0.19 |
| $10K | $10 | 0.02 | 0.04 | 0.09 |
| $10K | $20 | 0.01 | 0.02 | 0.04 |
| $10K | $24.41 observed 90th-percentile MAE | 0.01 | 0.02 | 0.04 |
| $100K | $5 | 0.49 | 0.98 | 1.96 |
| $100K | $10 | 0.24 | 0.49 | 0.99 |
| $100K | $20 | 0.12 | 0.24 | 0.49 |
| $100K | $24.41 observed 90th-percentile MAE | 0.10 | 0.20 | 0.40 |

The full sizing receipt also calculates against the **last known**, now stale, FXIFY balance anchors ($9,660.24 and $96,405.60). A stop can fill beyond its price after a gap, so no theoretical size guarantees the stated cash risk. [Sizing rows](analysis/primary.json).

## Interpretation and isolation

The exact last-Friday-M1 idea is **not supported**: the sample is substantially larger than 14 weekends, the $10 first-hit rate favors the adverse boundary, mean four-hour return is negative, and the later segment does not validate continuation. Immediate reopen is not justified by these data; waiting 15 or 30 minutes did not materially repair the rule. No tested secondary definition has a statistically credible independent edge. A new **orderless** forward test of a predeclared definition could measure exact opening ticks and actual spread, but the present evidence gives no reason to enable or schedule an FXIFY trade.

History before the broker's February 2020 server start is unavailable from this account. This experiment has M1 bid OHLC and reported bar spread, **not exact bid/ask opening ticks, executable alternative fills, slippage, commission, or FXIFY-specific quotes**. It does not pool another feed. The research exporter compiled with **0 errors and 0 warnings**, ran in the isolated local FP demo terminal, and contains no order-send, modification or closing API. Its startup requested `AllowLiveTrading=0`, but MT5 reported both runtime trade permissions true; the safe boundary is the program's absence of order functions, and that discrepancy is disclosed rather than called disabled permissions. FXIFY accounts, FP production, the original collector and the VPS were not contacted or changed for this study. Eleven focused boundary/orderless tests passed. [Exporter source](../../../tools/mql/SolTradeGoldWeekendReadOnly.mq5) · [analysis source](../../../tools/analyze_gold_weekend_expanded.py) · [test source](../../../tests/test_gold_weekend_expanded.py) · [compiler log](broker-export-full/gold-weekend-compile.log).
