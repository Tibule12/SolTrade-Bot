# Phase 6 V31 — V28 independent external-feed historical replication

## Terminal outcome

`V31_DATA_INSUFFICIENT_OR_INVALID`

The complete Dukascopy acquisition produced 328,975 preserved hourly files containing 1,128,565,591 bid/ask ticks. Every mandatory open-session hourly response was present, the raw immutable manifest was written, and no zero/negative price or backward timestamp was found.

Raw qualification nevertheless failed before transformation. The preserved source payload contains 12,208 bid-above-ask ticks across EURUSD, AUDUSD, NZDUSD, USDCAD, USDCHF and USDJPY, all within the two UTC source hours spanning 2024-10-09 23:00 and 2024-10-10 00:00. GBPUSD has no crossing. Of those rows, 8,698 report both bid and ask volume as zero. The decoder is not the cause: the frozen Jetta/BI5 checkpoint matched all 4,343 timestamps, bids and asks exactly.

V31 requires the imported Dukascopy bid and ask to be used as historical market spread and prohibits filtering, patching, interpolation, provider changes or symbol exclusion. A bid above ask is not a valid market spread. The frozen fail-closed qualification therefore stopped normalization, MT5 import and profitability execution.

No V28 P&L, profit factor, expectancy, drawdown or profitability classification was calculated or viewed. This is an external-data qualification failure, not a V28 performance failure. V28 remains unchanged and has not failed external replication. No optimization, tuning, tester trade, connected trade, demo-forward trade, live trade, V29 use, symbol exclusion, direction exclusion, or automatic push occurred. Phase 1–5 production code and all earlier evidence remain unchanged.
