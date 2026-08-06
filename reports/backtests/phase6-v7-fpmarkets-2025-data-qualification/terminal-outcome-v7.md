# Phase 6 V7 FP Markets terminal outcome

`FAIL_M1_HISTORY_UNAVAILABLE`

The FP Markets connected terminal supplied complete broker-native EURUSD real-tick boundary coverage for `[2025-01-02, 2025-12-24)`: 20,682,267 ticks from `2025-01-02 00:00:00.594` through `2025-12-23 23:59:59.877`. Retrieval completed in 356 daily chunks with zero memory errors, timeouts, retrieval failures, duplicates, ordering failures, or boundary violations. No generated-tick fallback occurred because the qualification used connected `CopyTicksRange`, not Strategy Tester.

The dataset does not qualify. Connected `CopyRates` could not return the frozen M1 interval: both the initial bounded check and a separate timer-deferred M1 check ended at `-1`, error `4401`, after 120 attempts. First and last M1 bars are therefore unavailable and are not inferred from HCC files or interpolated.

The real-tick stream also contains three unresolved scheduled-open gaps over 15 minutes:

1. `2025-02-05 00:15:05.295` to `2025-02-05 00:37:12.833` — 1,327 seconds.
2. `2025-03-07 23:57:59.005` to `2025-03-10 00:59:59.698` — maximum scheduled-open segment 3,539 seconds.
3. `2025-08-06 16:13:41.024` to `2025-08-06 17:14:06.171` — 3,625 seconds.

No interval-specific broker evidence was available for those gaps. They remain unresolved and would independently prevent qualification. Fifty other gaps are classified as scheduled weekends using the captured MT5 schedule. No gap was classified as a holiday without supporting evidence. Current FP Markets documentation notes GMT+2/GMT+3 operation with DST, but it does not resolve the exact 2025 timezone transitions or the three intervals.

The strategy matrix remains unauthorized. No strategy run, profitability calculation, optimization, replica, Strategy Tester run, demo trade, live trade, or Phase 7 action occurred. Phase 1–5 trading logic remains unchanged. Stop and wait for separate authorization.
