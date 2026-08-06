# Trend Breakout V2 — frozen strategy specification

Specification identifier: `SOLTRADE_TREND_BREAKOUT_V2_1_0`

Status: design frozen; uncompiled, unbacktested and unauthorized for trading.

## Design objective

V14 showed that V1's unconfirmed one-candle Donchian entries frequently reversed to the full initial stop before trend follow-through. Of 94 non-duplicated Normal/native trades, 48 hit the stop; 43 of those stopped within 24 hours and 27 stopped within six hours. V2 adds one persistence candle and a non-optimized overextension guard. It retains the profitable Donchian-10 exit mechanism and the approved Phase 1–5 risk and execution infrastructure.

No counterfactual V2 result has been calculated. The rules below are one design, not the winner of a strategy comparison or parameter search.

## Market, data and evaluation

- Market: `EURUSD` only.
- Signal timeframe: `H1` only.
- All indicators and decisions use completed candles only.
- At least 300 clean completed H1 bars from the current isolated dataset segment are required before setup evaluation.
- Indicators:
  - EMA 200 of H1 close;
  - Donchian 20 entry channel;
  - Donchian 10 exit channel;
  - Wilder ATR 14;
  - arithmetic mean of the latest 100 completed ATR-14 values, called `ATR14_MEAN_100`.
- No generated, synthetic or interpolated ticks may be used in authoritative research.

## Entry setup

Let `S` be a completed H1 setup candle. The entry channel for `S` excludes `S` and is calculated from the 20 completed candles immediately preceding it.

BUY setup:

1. `Close(S) > Donchian20High(S)`; and
2. `Close(S) > EMA200(S)`.

SELL setup:

1. `Close(S) < Donchian20Low(S)`; and
2. `Close(S) < EMA200(S)`.

The setup stores its direction, `S` timestamp, `Close(S)` and the frozen Donchian boundary. It may be confirmed only by the next completed market H1 candle. No later candle may revive it.

## Confirmation and entry

Let `C` be the next completed market H1 candle after `S`.

BUY confirmation requires all of:

1. `Close(C) > Close(S)`;
2. `Close(C) > frozen Donchian20High(S)`;
3. `Close(C) > EMA200(C)`;
4. `abs(Close(C) - EMA200(C)) <= 2.0 * ATR14(C)`;
5. `0.50 <= ATR14(C) / ATR14_MEAN_100(C) <= 2.00`.

SELL confirmation requires all of:

1. `Close(C) < Close(S)`;
2. `Close(C) < frozen Donchian20Low(S)`;
3. `Close(C) < EMA200(C)`;
4. `abs(Close(C) - EMA200(C)) <= 2.0 * ATR14(C)`;
5. `0.50 <= ATR14(C) / ATR14_MEAN_100(C) <= 2.00`.

Equality never confirms a breakout or trend condition. If every confirmation and infrastructure guard passes, submit one market entry through the approved ExecutionEngine at the first tradable tick after `C`. A failed, contradictory or missing confirmation cancels the setup without entry. There is no retry.

The volatility band is a broad data-sanity guard, not a value selected from a profitable counterfactual. No V2 performance was examined when it was frozen.

## Trading hours

There is no hour-of-day or weekday selection. Entries are permitted during any broker session in which EURUSD is officially open and every data, spread, risk, margin and execution guard passes. The V14 hourly and weekday samples were too small and heterogeneous to justify a session filter.

## Initial stop and position sizing

- Initial stop distance: exactly `2.0 * ATR14(C)`.
- BUY stop: requested entry price minus the stop distance.
- SELL stop: requested entry price plus the stop distance.
- The stop must be valid under the broker's minimum-stop rules and must be included in the original order request.
- Risk per trade: 0.25% of current equity.
- Volume is calculated from equity risk, actual stop distance and symbol tick economics, then rounded down to the broker lot step.
- Broker minimum, maximum and lot-step checks remain mandatory. If minimum volume would exceed the risk budget, no trade is permitted.
- Maximum simultaneous SolTrade positions: one.
- No take-profit, trailing stop, breakeven move, martingale, grid, averaging or scale-in/out.

## Position exits

The approved V1 Donchian-10 exit is retained because its completed trades were net-positive in both directions.

- Close a BUY only when a completed H1 candle closes strictly below the preceding 10-candle Donchian low (`EXIT_LONG`).
- Close a SELL only when a completed H1 candle closes strictly above the preceding 10-candle Donchian high (`EXIT_SHORT`).
- The current broker-attached initial stop remains active at all times.
- Emergency risk closure remains permitted under the approved PositionManager.
- Exactly one synchronous close attempt is permitted per completed signal candle; no uncontrolled retry.

## Risk limits and loss pauses

The approved risk policy remains unchanged:

- daily loss limit: 1.0% from broker-day starting equity;
- weekly loss limit: 2.5% from broker-week starting equity;
- emergency drawdown limit: 5.0% from the explicitly armed production baseline;
- consecutive-loss limit: three;
- daily lock clears only on a new broker day;
- weekly lock clears only on a new broker week;
- a three-loss pause clears on a new broker day;
- a profitable outcome resets the consecutive-loss streak; breakeven preserves it;
- emergency lock persists until the existing explicit authorized reset;
- duplicate closed-outcome protection remains mandatory.

## Spread and execution limits

- Maximum spread: the stricter of 30 symbol points and 10% of ATR14(C), using the approved ExecutionEngine calculation.
- Existing tick freshness, symbol, stop, volume, margin, account-environment, duplicate-candle, one-position, magic-number and broker-return-code checks remain mandatory.
- Magic number remains `2607202601`.
- Real accounts remain unconditionally rejected while live trading is disabled.

## Setup state and reset rules

- V2 setup state must use a new versioned namespace that cannot read or overwrite V1 state.
- Persist only direction, setup-bar time, setup close, frozen channel boundary, symbol, timeframe and specification identifier.
- On restart, restore a setup only if all identity fields match and `C` has not already been processed.
- Clear a setup after confirmation, rejection, expiration, contradictory breakout, broker-day rollover, risk lock, emergency state, position detection, symbol/timeframe mismatch, corrupt state or insufficient history.
- The processed-confirmation-candle identity must persist so restart cannot duplicate an entry.
- Dataset/segment state is isolated and reset before research statistics begin. Warm-up orders are prohibited.

## No-trade conditions

No entry is allowed when any of the following is true:

- fewer than 300 clean completed segment-local H1 bars;
- missing, stale, non-finite or inconsistent indicator/input data;
- no valid setup or no confirmation on the immediately following completed candle;
- confirmation equality rather than strict penetration;
- EMA-distance cap or volatility guard fails;
- spread, stop-distance, volume, margin or tick-freshness validation fails;
- a SolTrade position exists;
- any daily, weekly, emergency or consecutive-loss lock is active;
- duplicate setup or confirmation candle;
- account, symbol, timeframe, magic or environment mismatch;
- market session is closed;
- tester data mode is not qualified real ticks for authoritative research;
- optimization mode is active;
- live trading remains disabled or an account is real.

## Freeze rule

This specification must be committed before any 2026 V2 profitability result is viewed. A future change requires a new strategy version and new unseen data; it may not overwrite V2.
