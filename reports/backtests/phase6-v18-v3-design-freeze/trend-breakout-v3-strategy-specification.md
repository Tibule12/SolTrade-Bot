# Trend Breakout V3 Retest Hold — frozen strategy specification

Specification identifier: `TREND_BREAKOUT_V3_RETEST_HOLD_1_0`

Status: design frozen; unimplemented, uncompiled, untested, and unauthorized for trading.

## Market, data, and indicators

- EURUSD, H1, completed candles only.
- A minimum of 300 completed clean segment-local H1 bars is required before setup creation.
- No state, candle, or indicator input may cross an unresolved gap or clean-segment reset. Missing, incomplete, and quarantined H1 periods are not candles.
- EMA 200 of close, Donchian 20 entry channel excluding the current candle, Donchian 10 exit channel excluding the current candle, Wilder ATR 14, and `ATR14_MEAN_100(X)`: the arithmetic mean of the 100 completed ATR-14 values immediately preceding candle X, excluding X.
- All timestamps and candles use qualified broker-server time.

## Breakout setup

A BUY setup is created when a completed candle closes strictly above both the preceding-20-candle Donchian high and EMA 200, and `0.50 <= ATR14 / ATR14_MEAN_100 <= 2.00`. A SELL setup is the strict inverse below the preceding Donchian low and EMA 200 with the same inclusive ATR regime.

Creation freezes direction, setup timestamp, breakout boundary, setup close, setup EMA, setup ATR, and clean-segment identifier. It creates no order. Only one setup may be active. A same-direction breakout never restarts or extends it.

## Six-candle retest window

Exactly the next six fully completed market H1 candles in the same clean segment are eligible retest candles, numbered 1 through 6. Scheduled closed-session hours, missing periods, incomplete candles, and quarantined periods do not increment the count.

A BUY confirms on the first eligible candle whose low is at or below the frozen boundary, whose close is strictly above that boundary and EMA 200, and whose ATR regime is within the inclusive frozen band. A SELL confirms on the first eligible candle whose high is at or above the boundary, whose close is strictly below the boundary and EMA 200, and whose ATR regime passes.

The immediate-next-candle-only rule, continuation beyond setup close, and every absolute EMA-distance cap are absent. Entry is attempted exactly once at the first tradable tick after the completed retest-hold candle.

## Deterministic evaluation order

For each new completed H1 candle:

1. reject/reset all state if the candle or segment identity is invalid;
2. if a position exists, evaluate the Donchian-10 completed-close exit and do not create a setup;
3. if a setup is active, increment its retest count and evaluate the candle against the frozen boundary;
4. if retest-hold price, EMA, and ATR conditions pass, evaluate position, risk, spread, session, and execution guards once; submit once if they pass, otherwise cancel without postponement;
5. if no confirmation occurred, cancel on a wrong-side EMA close, an accepted opposite breakout, or count 6 expiry; for BUY, wrong-side means close less than or equal to EMA 200, and for SELL it means close greater than or equal to EMA 200;
6. after the prior setup is fully evaluated and cancelled, the same completed candle may create one opposite setup if every setup condition passes; a same-direction event cannot replace it;
7. if flat with no active setup, evaluate ordinary setup creation;
8. persist the last processed candle so restart cannot repeat any transition.

An opposite breakout is “accepted” only when it independently satisfies the strict Donchian-20, EMA-side, ATR-regime, 300-bar, segment, data, and identity setup guards. If the active setup confirms, confirmation takes precedence and no opposite setup is created from that candle.

## Cancellation

Cancel without entry on six-candle expiry, accepted opposite breakout, gap/reset, segment end, retest close on the wrong side of EMA 200, a position detected when confirmation would otherwise occur, or any risk/spread/loss-pause/execution guard blocking an otherwise valid confirmation. A block is final for that setup; there is no later retry.

## Position and exit

- Initial stop distance is exactly `2 * ATR14` from the confirming retest-hold candle, below a BUY entry or above a SELL entry.
- Risk is 0.25% of current equity through unchanged Phase 1–5 sizing and broker volume normalization.
- Maximum one position; no take-profit, trailing stop, breakeven move, scaling, partial close, martingale, grid, or averaging.
- Close BUY only on a completed close strictly below the preceding Donchian-10 low; close SELL only strictly above the preceding Donchian-10 high. The initial stop remains active.

## Risk, execution, and authorization

Daily loss limit 1.0%, weekly loss limit 2.5%, emergency drawdown limit 5.0%, pause after three consecutive losses, and the stricter of 30 points or 10% of confirmation ATR for spread remain unchanged. Existing validation, position management, return-code handling, and magic number `2607202601` remain unchanged. Real accounts and live trading remain disabled.

V3 uses a separate versioned state namespace. It persists setup identity and frozen values, segment identity, retest count, last processed candle, and confirmed/cancelled status. Corrupt or mismatched state fails closed. Exactly one submission attempt is allowed; no uncontrolled retry.

## Freeze rule

V3 is the only design frozen by V18. It may not be modified after 2026 V3 signal counts are viewed. V18 authorizes no implementation, signal replay, backtest, profitability calculation, forward test, order, position, or Phase 7 work.
