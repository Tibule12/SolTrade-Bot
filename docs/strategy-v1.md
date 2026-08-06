# Trend Breakout V1

This document freezes the initial strategy hypothesis implemented by the Phase 3
signal-only engine.

## Market

- Instrument: EURUSD only.
- Timeframe: H1.
- Decisions: once per newly completed candle.
- EMA: 200 periods.
- Entry Donchian channel: 20 preceding completed candles.
- Exit Donchian channel: 10 preceding completed candles.
- ATR: 14 periods.

## Entries

Long: the previous completed candle closes strictly above the highest high of the
20 completed candles before it, and that close is above EMA(200).

Short: the previous completed candle closes strictly below the lowest low of the
20 completed candles before it, and that close is below EMA(200).

ATR and all market/risk/permission checks must be valid. Only one SolTrade
position may be open. Ties at the Donchian boundary are not breakouts.

## Protection and exits

Initial stop distance is 2 × ATR(14), with no fixed take-profit.

A long exits when a completed candle closes below the lowest low of the preceding
10 completed candles, the stop is hit, or an emergency rule closes it. A short
uses the inverse upper-channel rule.

The strategy module reports `EXIT_LONG` and `EXIT_SHORT` channel signals without
inspecting or closing positions. Phase 4 consumes only BUY/SELL entries. Stop
hits, strategy exits, and emergency closure belong to later position-management
work.

## Deterministic calculation contract

The runtime copies 221 completed H1 candles starting at MetaTrader shift `1`.
`CopyRates` places the oldest copied candle first, so the newest element is the
signal candle. The forming shift-0 candle is never supplied to the strategy.

- EMA 200 is seeded with the arithmetic mean of the oldest 200 closes in the
  fixed window, then updated through the remaining 21 closes using
  `alpha = 2 / 201`.
- ATR 14 is seeded with the mean of the first 14 true ranges and then uses
  Wilder smoothing through the signal candle.
- The entry channel uses the 20 candles immediately preceding the signal
  candle.
- The exit channel uses the 10 candles immediately preceding the signal
  candle.
- Strict `>` and `<` comparisons are used; equality is not a breakout.

The structured result contains signal-bar OHLC/time, EMA, both channel bounds,
ATR, `2 × ATR` initial-stop distance, BUY/SELL/NONE, EXIT_LONG/EXIT_SHORT/NONE,
and machine-readable entry/exit reason codes.

The fixed-window seeding rules are part of strategy version `1.0.0`; changing
them is a strategy revision, not an implementation detail.

## Prohibited interpretation

The implementation may not use the forming candle, include the signal candle in
its preceding-channel comparison, add discretionary filters, or alter rules by
environment. Any strategy revision requires a new documented version and fresh
out-of-sample/forward evaluation.

The strategy module only calculates and returns these signals. Phase 4 may pass
BUY/SELL results to the separate gated execution engine; the strategy code does
not place, modify, or close trades. Exit signals remain display/journal only.
