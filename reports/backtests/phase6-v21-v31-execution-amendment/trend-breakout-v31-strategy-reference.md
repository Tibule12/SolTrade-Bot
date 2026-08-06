# Trend Breakout V3.1 strategy reference

Specification identifier: `TREND_BREAKOUT_V3_RETEST_HOLD_1_1`

Status: research specification frozen; unimplemented, uncompiled, untested, and unauthorized for trading.

V3.1 incorporates by immutable reference the complete `TREND_BREAKOUT_V3_RETEST_HOLD_1_0` specification at SHA-256 `eb91a76d197ffcf4aab7e8e52172abb5528d1c28a27431730d052f458d4dddb6`. It changes exactly one behavioral field: the ATR-relative first-tick spread fraction from `0.10` to `0.20`.

Entry remains the first tradable real tick after the completed retest-hold candle. There is exactly one eligibility check and one submission opportunity. No later tick, waiting window, delayed entry, or retry is permitted.

The V3.1 spread rule is:

```text
atr_limit_points = 0.20 * confirmation_atr_price / symbol_point
effective_spread_limit_points = min(30.0, atr_limit_points)
entry_allowed = actual_spread_points <= effective_spread_limit_points
```

Equality passes. The absolute ceiling remains 30 points.

All Donchian, EMA, ATR, ATR-regime, six-candle retest, confirmation, two-ATR stop, Donchian-10 exit, 0.25% sizing, position, loss-limit, state-ordering, execution, no-retry, magic-number, account, and authorization rules remain unchanged. Phase 1–5 production code is not modified.

V3.1 may not use any tick dated on or after `2026-08-01 00:00:00` for profitability during design, implementation, parity, or development screening. V21 authorizes no implementation, signal replay, performance calculation, order, position, Phase 7, or live trading.
