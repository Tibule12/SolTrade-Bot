# FP performance and behavior — captured September 30, 2026

**Six positions completed after the September 24 11:16 UTC cutoff: three positive, three negative, +$695.02 / +0.80924R in whole-position results.** The September 28 XAUUSD winner contributed +$2,497.95 / +2.68834R; without it, this cohort is −$1,802.93 / −1.87910R. These six completions remain dependent on one large result.

This is not a $695.02 account-balance gain over the audit interval. The first completed position entered before the cutoff and had already realized a $469.20 allocated partial bank. Its final +$3.22 includes that older partial. Exact interval cash flows require broker deals, including commission timing.

| Entry UTC | Exit UTC | Symbol / direction | Whole-position net cash / R | Bank1R | Runner stop updates | Exit |
|---|---|---|---:|---|---:|---|
| 2026.09.24 09:37:01 | 2026.09.24 12:13:16 | XAUUSD.r SELL | $+3.22 / +0.00346R | Yes | 0 | RUNNER_STRUCTURAL_EXIT |
| 2026.09.28 01:54:01 | 2026.09.28 10:04:02 | XAUUSD.r SELL | $+2,497.95 / +2.68834R | Yes | 31 | RUNNER_STRUCTURAL_EXIT |
| 2026.09.28 15:10:30 | 2026.09.28 16:16:59 | US100 SELL | $-961.86 / -1.00000R | No | 0 | INITIAL_STRUCTURAL_STOP_EXIT |
| 2026.09.28 22:09:01 | 2026.09.28 23:20:00 | XAUUSD.r SELL | $-486.42 / -0.51093R | No | 0 | PRE_BANK_GIVEBACK_FAILED |
| 2026.09.29 06:49:10 | 2026.09.29 10:44:25 | AUDUSD.r SELL | $+595.08 / +0.62775R | Yes | 6 | RUNNER_STRUCTURAL_EXIT |
| 2026.09.30 02:53:52 | 2026.09.30 03:03:57 | EURJPY.r SELL | $-952.95 / -0.99938R | No | 0 | INITIAL_STRUCTURAL_STOP_EXIT |

The six-position expectancy is +0.13487R, profit factor 1.32237 and maximum drawdown 1.88256R when whole-position outcomes are ordered by exit time. This drawdown is not a reconstruction of account equity or the timing of partial realizations.

From the September 18 19:41 UTC flat snapshot, the complete exported cohort now contains **14 completed positions, six positive and eight negative, −$2,647.33 / −2.67623R**. Expectancy is −0.19116R and profit factor 0.62695. The latest positive six-position subtotal therefore does not establish that the entry engine has become reliable.

## What the executions show

- The September 24 carried XAUUSD runner ended at its original structural stop after banking half. Its banked cash was +$469.20; runner cash was −$465.98; whole-position outcome was only +$3.22. It made zero structural-stop advances.
- The September 28 XAUUSD winner banked +$535.85 and realized +$1,962.10 on its runner. It made 31 structural-stop advances, ending at +$2,497.95. Existing structural management can retain a substantial continuation; that single outcome dominates this cohort.
- The September 28 US100 sell produced a recorded price excursion of +0.51928R, never banked, and ended at the original stop for −$961.86 / −1R.
- The later September 28 XAUUSD sell reached a recorded price excursion of +0.77320R, never banked, and was closed by the existing pre-bank giveback failure condition for −$486.42 / −0.51093R. Negative R alone is not the source condition.
- The September 29 AUDUSD sell banked +$480.24 and its runner added +$114.84, with six stop advances, for +$595.08 / +0.62775R.
- The September 30 EURJPY sell had zero recorded favorable excursion and reached its original stop after approximately ten minutes, losing −$952.95 / −0.99938R.

The three newly entered losers all had M1 opposing their sell direction while M5/M15/H1 were bearish. The AUDUSD winner also had opposing M1, so these examples do not justify a rule that rejects every opposing-M1 entry. Losing admission scores ranged from 64.1189 to 68.4309; the AUDUSD winner entered at the lower score of 60.8755. No threshold was changed or tuned.

## Current authority requires a correction

The fresh runtime at **17:28:20 UTC** reports connected, one position, zero pending orders, **`BLOCKED_NO_OWNERSHIP`**, `autonomous_entry=false` and `ownership_permit=BLOCKED`. FP source/binary hashes and PID 2892 match the frozen baseline. Its runtime instance ID also matches September 24, so this capture does not show an FP process restart.

**The earlier September 24 report incorrectly said FP was autonomous and ownership-granted. Its preserved 11:16 runtime already reported blocked ownership.** Fresh entries on September 28–30 prove authority was available at intervening entry times; these two blocked snapshots do not prove a continuous six-day block. The timing and reason require lifecycle/ownership evidence.

The existing ownership verification also gates Bank1R partials, discretionary closes and runner-stop modifications, not only new entries. A blocked verification prevents those actions. The existing broker structural stop is not removed by the block. These checks are at frozen-source lines 2213, 2367, 2569 and 2693.

The latest unmatched entry is **GER40 SELL 408708254**, September 30 15:41:33 UTC, original volume 18.63, entry 25209.75, original stop 25254.40 and initial cash risk $944.54. Its latest sampled event at 17:25 UTC is PRE_BANK_PROFIT, current price R +0.70549 and peak price R +0.81747, with no bank event or exit yet in this export. Fresh runtime position count is one; the exact broker position details are a separate verification.

## Accounting limits

`RUNNER_PEAK_R` is price movement divided by original stop distance. Final R is realized net cash divided by initial dollar risk. Cash MFE excludes commission. Those values must not be subtracted or compared as if they shared the same monetary definition. In particular, a price-R peak over +1 does not prove the cash-based Bank1R trigger was reached.

The frozen source still has known telemetry issues: unbanked losers can show negative allocated `banked_cash`; the logged giveback `opposite_direction` is recomputed after overwriting the direction; and partial-exit `entry` is a cached market-score field rather than a broker fill price. This analysis excludes those fields from unsupported conclusions.

The runtime portfolio-risk amount measures current executable quote to broker stop. It can exceed initial entry risk because it includes open gains that can be surrendered; that alone does not mean position size or the stop changed.

[Machine performance analysis](fp-analysis.json) · [Trade table](fp-trades.csv) · [Operational correction and source references](fp-operational-analysis.json). All work here used local copies; no production or FXIFY setting changed and this analysis sent zero orders.
