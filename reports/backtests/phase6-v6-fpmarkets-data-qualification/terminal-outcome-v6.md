# Phase 6 V6 FP Markets terminal outcome

`FAIL_REAL_TICK_HISTORY_UNAVAILABLE_FOR_FROZEN_INTERVAL`

FP Markets’ `FPMarketsSC-Demo` server reports EURUSD real ticks beginning on 2025-01-02. The exact first retrieved real tick is `2025-01-02 00:00:00.594`. The frozen qualification interval ends at `2024-12-24 00:00:00` exclusive, so it has no broker-native real-tick coverage and cannot qualify.

The MT5 tester was configured for “Every tick based on real ticks,” but it explicitly fell back to generated ticks for the 2024 request. Those generated ticks and the tester-only `CopyTicksRange` fragment are rejected as canonical evidence. They were not used by a strategy or for profitability.

The following remain true:

- Authoritative Phase 6 strategy matrix: **unauthorized**.
- Profitability: **unknown**.
- Strategy run: **not performed**.
- Optimization: **not performed**.
- Replica: **not performed**.
- Demo or live trade: **not performed**.
- Phase 7: **unauthorized**.
- Phase 1–5 trading logic: **unchanged**.

Stop here and wait for review.
