# Gold Friday-close direction versus Monday reopen — 3 October 2026

**Decision: no 10-lot buy was scheduled on either FXIFY account.** The requested test did not establish a usable directional signal, and the proposed size is incompatible with the 10K account's nominal daily-loss budget. No real order was sent, no FXIFY setting was changed, and no production bot was changed.

The latest FP demo XAUUSD.r M1 broker bar is **2 October 2026, 23:59 broker-server time**. Its bid opened at 4140.16 and closed at 4143.27, so that **one-minute candle was bullish**. The final hour and Friday's full session closed **bearish** by their respective opening bids. The next Monday reopen is not yet observed in this export. Thus “gold closed at buy” describes one timeframe, not a unique market state.

## Historical test

An orderless research program exported 100,000 completed FP demo XAUUSD.r M1 bars. It covered 24 June through 2 October 2026 and included **14 complete Friday-to-Monday reopenings**. Twelve older weekly `CopyRates` requests failed, so this is the complete usable subset, not a claim about every weekend since April. The exporter compiled with **0 errors and 0 warnings** and contains no order API. It ran in the isolated local research terminal, separate from VPS production. Its startup file requested `AllowLiveTrading=0`, but the runtime reported `MQL_TRADE_ALLOWED=1` and `TERMINAL_TRADE_ALLOWED=1`; therefore the startup flag is **not** offered as proof of disabled terminal permissions. The program's lack of order functions is the execution boundary.

The signal is the direction from the **opening bid to closing bid of the last Friday M1, H1, or Friday-session span**. The gap comparison is last Friday bid close to first Monday bid open. A hypothetical trade enters at the first Monday bar; buy entry uses first bid open plus its recorded spread, and sell entry uses bid open. Returns at 15, 60 and 240 minutes use later bid close plus recorded spread for a sell close. “Moving hard” is predeclared as reaching **+$10 per ounce before −$10 per ounce** during the first four hours. A bar touching both boundaries would be ambiguous; none did. These are **bar-based estimates**, without exact opening tick, alternative fill, slippage, commission or FXIFY-specific quote history.

| Friday signal | Weekends | Same-side opening gap | Same-side trade positive after 4 h | +$10 before −$10 | −$10 before +$10 |
|---|---:|---:|---:|---:|---:|
| Last M1 BUY | 4 | 2 | 2 | 1 | 3 |
| Last M1 SELL | 10 | 6 | 6 | 4 | 6 |
| Last H1 BUY | 6 | 2 | 3 | 0 | 6 |
| Last H1 SELL | 8 | 4 | 5 | 1 | 7 |
| Friday session BUY | 10 | 5 | 6 | 4 | 6 |
| Friday session SELL | 4 | 3 | 4 | 1 | 3 |

For the **last-M1 BUY** rule closest to the request, the estimated four-hour average was **−$2.54 per ounce** and 4/4 buys first moved adversely by more than $4 per ounce at some point during the four hours. This is a small, broker-specific sample; it supports **no reliable probability estimate or trading edge**. The [per-weekend rows](weekends.csv) and [machine-readable summary](summary.json) disclose every observation.

## Proposed 10-lot exposure

FXIFY publishes a contract size of **100 ounces per XAUUSD.r lot**. Ten lots are 1,000 ounces, so a **$1 adverse gold move is approximately $1,000**, before spread, slippage and commission. On a nominal $10,000 2-Phase Pro account with a 4% daily-loss limit, approximately **$0.40 adverse movement equals the full $400 allowance**. On a nominal $100,000 account, approximately $4 equals its $4,000 allowance. The historical first-four-hour estimated adverse excursion crossed $0.40 on **14/14** buy paths and $4 on **12/14**. A stop cannot guarantee a fill at its price across a market gap.

The independent 10K broker ledger's largest recorded gold trade was **0.22 lot**; 10 lots would be over **45 times** that size. FXIFY's terms also flag substantially larger position sizes than a customer's other trades as a potentially forbidden practice. The exact current account equity, broker margin, order validity, spread and exposure were **not freshly queried** for this study; the preserved 30 September audit showed both FXIFY entry blocks disabled but could not establish current broker exposure. None of these unknowns makes the proposed order safe to schedule.

The local exporter [receipt](broker-export/receipt.json), [compile log](broker-export/gold-weekend-compile.log), [status](broker-export/status-20261003.csv), [bar data](broker-export/m1-20261003.csv), [source](../../../tools/mql/SolTradeGoldWeekendReadOnly.mq5), and [analysis](../../../tools/analyze_gold_weekend_close.py) are retained. Four focused regression checks passed via the Python test harness; `pytest` was unavailable in the local environment. The analysis did not contact FXIFY or submit any order.
