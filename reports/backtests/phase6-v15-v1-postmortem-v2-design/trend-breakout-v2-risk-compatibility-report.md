# Trend Breakout V2 risk compatibility report

## Result

The frozen V2 design is compatible with the approved Phase 1–5 RiskEngine, ExecutionEngine and PositionManager interfaces. No production code was changed in V15.

## Reused without behavioral change

- 0.25% current-equity risk budget;
- tick-value/tick-size stop-risk calculation;
- volume minimum, maximum and lot-step validation with downward rounding;
- 1.0% broker-day loss lock;
- 2.5% broker-week loss lock;
- 5.0% emergency drawdown lock when explicitly armed;
- three-consecutive-loss pause and duplicate-outcome cache;
- stricter-of 30-point and 10%-of-ATR spread validation;
- margin, minimum-stop, fresh-tick, account and symbol validation;
- one position maximum and magic number `2607202601`;
- initial stop submitted with the entry;
- restart restoration, one synchronous request and no uncontrolled retry;
- ownership-only position management and emergency closure.

## Strategy-layer adaptations required later

Only a future, separately authorized V2 strategy implementation needs new behavior:

1. maintain the one-candle pending setup and frozen boundary;
2. calculate `ATR14_MEAN_100` from completed segment-local candles;
3. apply persistence, EMA-extension and volatility confirmation rules;
4. pass confirmation-candle ATR to the existing execution sizing path;
5. persist pending-setup and processed-confirmation identity in an isolated V2 namespace.

These adaptations must not alter RiskEngine arithmetic, execution safety gates, broker request rules, PositionManager ownership checks or V1 source.

## Compatibility cautions

- Minimum history increases to 300 clean H1 bars for V2; warm-up orders remain prohibited.
- A confirmed stop distance that fails broker rules remains a no-trade, not a reason to widen risk or force minimum volume.
- A restart must never treat a consumed or expired V2 setup as new.
- V2 state identifiers must be excluded from canonical trading inputs only when proven non-trading; the setup content itself is trading state and must be deterministic.
- Connected demo, live and Phase 7 permissions remain false.
