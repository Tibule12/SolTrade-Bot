# Phase 5 Position Management

## Scope

Phase 5 adds position monitoring and a single synchronous close gateway. It
does not add a new entry strategy, stop modification, trailing stops,
take-profit management, backtesting, optimisation, or Phase 6 behaviour.

`EnablePositionManagement` defaults to `false`. The code may monitor and
rebuild broker state while disabled, but it cannot prepare or submit a close.
`AllowLiveTrading=true` is invalid configuration, and every real-account close
request is independently rejected before terminal permissions can matter.

## Ownership

The broker is authoritative. On every refresh, Position Manager scans open
positions and adopts only a position that simultaneously has:

- the configured SolTrade magic number;
- the configured symbol (`EURUSD` in Trend Breakout V1); and
- a valid BUY or SELL position type.

An unrelated manual position, including a manual EURUSD position with magic
number zero, is never adopted, modified, or closed. More than one SolTrade
magic-number position causes the manager to fail closed.

## Stop verification

The current broker `POSITION_SL` value is read whenever the position state is
refreshed. A positive value is displayed as attached. A zero value is logged as
`SOLTRADE_STOP_LOSS_MISSING` / `POSITION_STOP_LOSS_MISSING` and is visible on
the dashboard.

Phase 5 does not silently repair or modify a stop. A missing stop does not
prevent an already approved strategy or emergency close from reducing risk.

## Approved close triggers

| Position | Strategy close allowed | Requested close side/price |
|---|---|---|
| BUY | Valid completed-candle `EXIT_LONG` only | SELL at current Bid |
| SELL | Valid completed-candle `EXIT_SHORT` only | BUY at current Ask |

The exit signal comes from the approved Donchian 10-bar calculation. Strategy
history begins at shift 1, so the forming candle is excluded. A close equal to
the channel boundary is not an exit; the completed close must be strictly below
the prior D10 low for `EXIT_LONG` or strictly above the prior D10 high for
`EXIT_SHORT`.

The two non-strategy triggers are:

- `EMERGENCY_DRAWDOWN_EXIT` when the approved Risk Engine's emergency lock is
  latched; and
- `EMERGENCY_STOP_EXIT` when the operator has set `EmergencyStop=true`.

Daily, weekly, and consecutive-loss locks prevent new entries but do not
themselves close an existing position.

## One-attempt close pipeline

Before any broker call, the manager validates environment, exact demo login,
permissions, current quote, full position volume, broker lot constraints, and
filling mode. It then atomically persists a close-attempt claim for the broker
position identifier.

After the claim, it reselects the exact ticket and rechecks magic number,
symbol, identifier, direction, and volume. It calls `OrderCheck()` once. Only a
successful check can reach the sole synchronous `OrderSend()` close gateway.
Any changed position, check rejection, or send rejection consumes the attempt.
There is no automatic retry.

The request uses `TRADE_ACTION_DEAL`, the exact `request.position` ticket, the
SolTrade magic number, the full open volume, the broker-supported filling mode,
and the configured maximum deviation. There is no close-by, async, pending,
stop-modification, or convenience `CTrade` path.

## Restart state

State is account-token and magic-number scoped under:

```text
MQL5/Files/<ExecutionStateDirectory>/position_<account-token>_<magic>.csv
```

The record has a schema marker and deterministic checksum. It is written to a
temporary file and atomically moved into place. Startup loads the record, then
rescans the broker. Broker state wins over local state.

The persistent close claim prevents a terminal restart from replaying a close
attempt. A genuinely new broker position identifier clears the old claim. A
missing, corrupt, or contradictory state fails closed.

## Journal evidence

Position-management rows record:

- requested and actual close price;
- adverse-positive slippage in points;
- direction, full volume, exact position ticket and identifier;
- stop-attached state;
- action, opposite order type, filling mode, deviation, symbol, and magic;
- `OrderCheck()` boolean, immediate `GetLastError()`, check retcode/comment;
- `OrderSend()` boolean, immediate `GetLastError()`, broker retcode/comment;
- order ticket, deal ticket, matching exit transaction, net P/L, and exit
  reason; and
- `retry_allowed=NO`.

The matching `DEAL_ENTRY_OUT`, `DEAL_ENTRY_OUT_BY`, or `DEAL_ENTRY_INOUT`
transaction is authoritative for actual fill price and deal ticket.

## Activation boundary

The deterministic Phase 5 suite must pass on the connected approved demo while
`EnablePositionManagement=false`. That suite contains no `OrderCheck()` or
`OrderSend()` call. Automated closing remains unapproved until its evidence is
reviewed separately.

The separate `SolTradeOneShotPositionCloseVerification` script provides the
next controlled broker-path gate. Its default branch exits before
configuration, journal, state, or marker creation. Later fixture creation and
close modes are mutually exclusive, permanently marked, demo/login locked, and
route only through the approved Execution Engine and Position Manager. The
unarmed procedure is in `tests/one-shot-position-close-preflight.md`.
