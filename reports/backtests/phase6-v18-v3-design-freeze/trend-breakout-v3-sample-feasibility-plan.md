# Trend Breakout V3 V19 signal-only sample-feasibility plan

V18 freezes rules only. V19 may begin only from this committed specification and may not change it after viewing any 2026 V3 signal count.

V19 will use qualified FP Markets EURUSD 2026 real ticks, H1 completed candles, the frozen broker-server periods and clean-segment resets, and no generated or synthetic fallback. It will reproduce the V3 state machine without sending orders or calculating monetary results.

Report setup counts, retest candles by ordinal 1–6, confirmations, cancellations by frozen reason, risk/spread blocks, theoretical initial-stop exits, theoretical Donchian-10 exits, naturally completed cycles, and right-censored positions for Validation, proposed OOS, and separately labelled post-proposed-OOS accumulation. Do not calculate P&L or evaluate rejected-setup outcomes.

Return the sample gate as feasible only if proposed OOS contains at least 50 naturally completed V3 cycles. Do not lower the gate, combine post-OOS accumulation, or extend OOS automatically. If infeasible, stop before profitability testing and report any methodology amendment for separate pre-results approval.

Only a passing sample-feasibility result may permit a later phase to implement a tester-only V3 harness, prove parity, and then seek separate authorization for a controlled practical matrix. Production implementation, demo forward testing, live trading, and Phase 7 remain unauthorized.
