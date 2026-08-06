# V3.1 spread-policy specification

At the first tradable real tick after the completed retest-hold candle:

1. read confirmation ATR in EURUSD price units;
2. read the symbol point in EURUSD price units;
3. calculate `atr_limit_points = 0.20 * confirmation_atr_price / symbol_point`;
4. calculate `effective_spread_limit_points = min(30.0, atr_limit_points)`;
5. calculate actual spread as `(ask - bid) / symbol_point`;
6. pass only when actual spread is less than or equal to the effective limit.

Equality passes. Non-finite or invalid ATR, point, bid, or ask fails closed. A failed first tick cancels the setup. It does not wait or retry.

Configuration identifier: `SOLTRADE_V31_SPREAD_POLICY_20PCT_ATR_CAP30_V1`.

State namespace: `SOLTRADE_TREND_BREAKOUT_V31_SPREAD_POLICY_STATE_V1`.

The 30-point absolute ceiling remains an independent guard against abnormal widening. The 0.20 fraction is frozen before V3.1 profitability is viewed and may not be adjusted afterward.
