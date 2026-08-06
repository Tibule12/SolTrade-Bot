# Phase 4 Execution Engine

## Scope

Phase 4 converts an approved completed-candle BUY or SELL signal into one
validated market-entry request in MetaTrader 5. It can submit entries in the
Strategy Tester and, only after explicit configuration, one approved demo
account.

It does not:

- act on the strategy's Donchian exit signals;
- close or modify positions;
- trail stops;
- remove protection;
- retry a rejected request;
- submit to a real account.

Those position-management responsibilities remain Phase 5 work.

## Permission boundary

The execution gateway admits only:

| Detected environment | Required Phase 4 condition |
|---|---|
| `BACKTEST` | Expected environment matches and all MT5 trading permissions pass |
| `DEMO` | `EnableDemoExecution=true`, exact `ApprovedDemoAccount` match, expected environment match, and all MT5 trading permissions pass |
| `LIVE` | Always rejected with `REAL_ACCOUNT_FORBIDDEN_PHASE4` |
| `UNKNOWN` | Always rejected |

`EnableDemoExecution` defaults to `false`, `ApprovedDemoAccount` defaults to
`0`, and `AllowLiveTrading` defaults to `false`. Phase 4 configuration
validation rejects `AllowLiveTrading=true`; the Algo Trading button cannot
override the real-account prohibition.

## Request pipeline

For each newly completed H1 signal candle:

1. Confirm a valid BUY or SELL strategy result.
2. Apply environment, account, emergency-stop, and MT5 permission gates.
3. Reject an already-consumed or older signal candle.
4. Apply the approved Phase 2 daily, weekly, emergency, and
   consecutive-loss locks.
5. Require valid current market data.
6. Reject existing SolTrade exposure and unrelated positions on the configured
   symbol.
7. Require broker support for market orders and an initial stop-loss.
8. Apply both spread limits.
9. Calculate the stop at `2 × ATR(14)` and round it outward to the broker tick
   grid.
10. Validate the protective stop distance against
    `SYMBOL_TRADE_STOPS_LEVEL`.
11. Calculate risk from current equity at the configured default `0.25%`.
12. Calculate volume with the Phase 2 loss-side tick value, then validate the
    broker minimum, maximum, and lot step.
13. Calculate and validate margin with `OrderCalcMargin`.
14. Atomically persist the consumed candle and full requested-entry details.
15. Run `OrderCheck`, capture its boolean and `GetLastError()` immediately,
    and require the `MqlTradeCheckResult` success code `0`.
16. Submit exactly once through the synchronous `OrderSend` gateway with the
    SolTrade magic number and compulsory stop-loss.
17. Record the result code without any automatic retry.
18. Wait for a matching `TRADE_TRANSACTION_DEAL_ADD` entry event before
    recording a confirmed actual fill.

An `OrderSend` return value or returned price is recorded as a broker-reported
value, not as a confirmed fill. `actual_entry` and confirmed slippage are
written only after the matching entry deal is observed.

## Stop and risk calculation

BUY requests use the current Ask; SELL requests use the current Bid.

```text
BUY raw stop  = requested Ask - 2 × ATR(14)
SELL raw stop = requested Bid + 2 × ATR(14)
```

BUY stops round downward and SELL stops round upward to the symbol tick size.
This preserves or increases protection distance instead of moving the stop
toward entry. Position size is calculated from the final tick-normalised
entry-to-stop distance.

The broker minimum-stop check uses the protective side of the current quote:

```text
BUY protective distance  = current Bid - stop-loss
SELL protective distance = stop-loss - current Ask
```

## Duplicate and restart safety

Before `OrderCheck` or `OrderSend`, the engine atomically records:

- completed signal-bar time;
- BUY/SELL direction;
- requested entry;
- spread;
- stop-loss;
- volume;
- planned risk;
- later broker order/deal tickets and return code.

The file is scoped by pseudonymous account identifier and SolTrade magic
number. It uses a schema marker, deterministic checksum, temporary write, and
atomic replacement. A corrupt or unreadable file locks execution.

After restart:

- the last consumed candle is restored and cannot be submitted again;
- broker positions and active orders bearing the magic number are rescanned;
- any existing SolTrade exposure blocks another entry;
- an unrelated position on the configured symbol blocks entry;
- an unprotected SolTrade position is displayed and logged, but Phase 4 does
  not modify or close it.

Broker positions remain authoritative. Persistent local state is used to stop
duplicate attempts, never to claim that a position exists.

## Rejection and retry policy

Every signal produces at most one `OrderSend` call. There is no loop, timer
retry, async request, requote acceptance, or escalating recovery request.

Validation, margin, `OrderCheck`, and broker rejections are final for that
completed candle. The reason code, terminal error, broker comment, and broker
return code are journaled.

`OrderCheck` and `OrderSend` have different result structures. A successful
`MqlTradeCheckResult` is boolean `true`, retcode `0`, comment `Done`; the
`TRADE_RETCODE_DONE` value `10009` is an `MqlTradeResult` result from the later
`OrderSend` call. The engine therefore accepts an order check only when its
boolean is true and its check retcode is zero. False or non-zero check results
remain final, fail-closed rejections.

## Execution journal fields

Execution rows populate:

- requested entry;
- confirmed actual entry when available;
- spread in points;
- signed slippage in points;
- stop-loss;
- requested/filled lot size;
- planned or actual-at-fill risk amount;
- required margin;
- order and deal tickets;
- broker return code and comment;
- `OrderCheck` boolean, immediate last error, check retcode, and check comment;
- requested action, order type, filling mode, volume, price, stop-loss,
  deviation, symbol, and magic number;
- broker minimum volume, lot step, stop level, and supported filling-mode
  bitmask;
- fill-confirmation state;
- `retry_allowed=NO`.

Positive slippage values are adverse for both directions:

```text
BUY  = (actual - requested) / point
SELL = (requested - actual) / point
```

## Controlled one-shot verification

`SolTradeOneShotDemoVerification.mq5` is a separate, test-only script for one
connected-demo execution check. It does not alter or bypass the production EA's
Trend Breakout signal path.

The script:

- is inert until `ConfirmOneShotDemoOrder=true`;
- requires an exact approved demo login and exact EURUSD chart;
- rejects Strategy Tester and every non-demo account;
- obtains the approved `2 × ATR(14)` distance from completed strategy history;
- calls the same `ProcessSignal` execution gateway exactly once;
- requests the broker minimum lot only when that is no greater than the normal
  risk-calculated size;
- creates a persistent disable marker before the engine call;
- polls account deal history for the matching entry transaction because scripts
  receive only `OnStart`;
- terminates without retrying or closing the resulting position.

The diagnostic V2 verifier uses a new persistent marker namespace. The original
rejected-attempt marker remains evidence and is never deleted or overwritten by
the V2 build.

The exact procedure and expected log sequence are in
`tests/one-shot-connected-demo-procedure.md`.
