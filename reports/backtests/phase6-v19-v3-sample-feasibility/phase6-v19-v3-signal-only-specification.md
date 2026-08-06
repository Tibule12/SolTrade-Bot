# Phase 6 V19 V3 signal-only evaluator

Exact replay of frozen `TREND_BREAKOUT_V3_RETEST_HOLD_1_0` on qualified V16 real ticks. ATR mean excludes the evaluated candle. State resets at each frozen period boundary. Real-tick bid triggers BUY stops and ask triggers SELL stops; Donchian exits execute at the first tick after the completed signal candle. Spread and existing-position guards are applied; performance-dependent locks are excluded, so cycles are `STRUCTURAL_SAMPLE_UPPER_BOUND`. No monetary result is calculated.
