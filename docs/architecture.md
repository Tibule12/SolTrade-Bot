# Architecture

## Scope and governing rule

SolTrade Bot uses one native MQL5 codebase in the MetaTrader 5 Strategy Tester,
demo accounts, and—only after formal approval—real accounts. Account environment
changes configuration and permission, never strategy rules.

The system fails closed: invalid or incomplete state prevents a new trade.

## Target processing flow

```text
Broker market data
        |
        v
Market validation ───── invalid ───> Journal + WAIT/LOCK status
        |
        v
Strategy signal engine
        |
        v
Risk engine ─────────── rejected ──> Journal + rejection status
        |
        v
Account/trade permission checks
        |
        v
Execution engine
        |
        v
Position manager
        |
        v
Journal and monitoring
```

The market-validation, account-detection, journal, configuration, monitoring,
Risk Engine, Strategy Engine, demo/test entry Execution Engine, and
default-disabled Position Manager portions exist through Phase 5. Phase 6 adds
only tester gates, isolated research state, and reporting/reconciliation around
those approved modules.

## Module boundaries

| Module | Owns | Must not own | Phase |
|---|---|---|---:|
| `Config` | Typed settings and validation | Strategy decisions | 1 |
| `AccountGuard` | Environment detection and live approval gates | Orders | 1 |
| `MarketData` | Quotes, symbol metadata, history readiness, new bars | Signals | 1 |
| `TradeJournal` | Append-only decision/event records | Trading decisions | 1 |
| `Dashboard` | Read-only chart status | State mutation or orders | 1 |
| `RiskEngine` | Risk amount, volume, drawdown lockouts, persistent risk state | Signal generation or orders | 2 |
| `StrategyBreakout` | Completed-bar Trend Breakout V1 signals | Orders | 3 |
| `ExecutionEngine` | Gated demo/test entry requests, initial stop, result handling, duplicate/restart state | Signal changes, exits, or position closing | 4 |
| `PositionManager` | Magic-number positions, stops, exits, recovery | Manual positions | 5 |
| `StateManager` | Durable lock/recovery state | Credentials | 5 |
| `BacktestResearch` | Tester-only input identity, isolation, cash-flow reports, reconciliation | Signals, sizing, entry/exit behavior | 6 |

The strategy engine returns structured data and never calls the trading API.
The risk engine may veto any entry signal and exposes the emergency close lock.
The execution engine does not reinterpret strategy or risk policy. Position
Manager consumes only the approved exit signal for the owned direction or an
approved emergency trigger. It never owns manual positions or modifies stops.

## Phase 5 runtime sequence

```text
OnInit
  ├─ load and validate configuration
  ├─ detect actual account environment
  ├─ evaluate default-deny account gates
  ├─ initialise CSV journal
  ├─ initialise market-data state
  ├─ restore or create persistent risk baselines/locks
  ├─ restore or create persistent execution-attempt state
  ├─ rescan broker positions/orders by magic number
  ├─ restore the persistent position/close-claim state
  ├─ rebuild the owned position from broker state and verify its stop
  └─ render the locked/eligible position-management panel

OnTick / OnTimer
  ├─ refresh quote/history validation
  ├─ evaluate current equity against daily/weekly/emergency limits
  ├─ detect a newly opened chart timeframe bar
  ├─ copy 221 completed candles beginning at shift 1
  ├─ calculate EMA 200, Donchian 20/10, and ATR 14
  ├─ produce and journal structured entry/exit signals
  ├─ if an owned position exists, require BUY/EXIT_LONG or SELL/EXIT_SHORT
  ├─ alternatively accept only emergency drawdown or EmergencyStop closure
  ├─ atomically claim the exact position identifier before close checks
  ├─ reselect and revalidate ticket, magic, symbol, direction, and volume
  ├─ run OrderCheck and at most one synchronous full-position close OrderSend
  ├─ for BUY/SELL only, apply account, risk, spread, stop, volume, and margin gates
  ├─ atomically claim the completed candle before broker submission
  ├─ run OrderCheck and at most one synchronous OrderSend with initial stop-loss
  ├─ wait for a matching entry-deal transaction before confirming the fill
  ├─ persist and journal risk-state transitions
  └─ refresh panel

OnTradeTransaction
  ├─ ignore unrelated entry and exit deals
  ├─ confirm the actual entry price/volume from the matching deal
  ├─ calculate and journal slippage and actual initial risk
  ├─ match exit deals by the tracked/claimed broker position identifier
  ├─ journal actual close, slippage, tickets, net P/L, and exit reason
  └─ feed each distinct closed outcome to the Risk Engine

OnDeinit
  ├─ journal shutdown reason
  ├─ close journal handle
  └─ clear panel
```

One Phase 4 gateway calls synchronous `OrderSend` for entries, and one Phase 5
gateway calls it for exact-ticket closes. No path calls `OrderSendAsync`,
`CTrade`, a convenience position-close function, or an order/position
modification action.

## Phase 6 research boundary

The canonical trading-input hash is computed before any research state opens.
The separate execution instance selects only
`root/hash/instance` state/artifact paths. A non-empty namespace rejects
initialization. Registered dates gate both entry and close signal-bar times, and
the reporter records warm-up history separately from actual in-window ticks.

At `OnTester`, native deal history, native Tester statistics, reconstructed
trade cash flows, supplementary adjusted metrics, concentration, boundary
positions, and the equity curve are emitted. External tools independently
rebuild the same metrics and require a fixed-delay authoritative/replica pair
to match. The reporter does not write back to the Strategy, Risk, Execution, or
Position Manager.

## Data ownership

- Broker/account state is authoritative for account mode, prices, and symbol
  specifications.
- Configuration is immutable during one EA instance. A parameter change causes
  normal MT5 reinitialisation.
- Daily/weekly baselines, lock flags, emergency state, loss streak, and the last
  closed-outcome identifier are persisted by account hash and magic number.
- The last consumed signal candle and its requested execution details are
  persisted separately by account hash and magic number before broker
  submission.
- Owned position identity, stop snapshot, last exit reason, and the consumed
  close attempt are persisted separately by account hash and magic number.
- Persistent risk-state replacement is written to a temporary file and moved
  over the prior state only after a successful write. A deterministic checksum
  detects partial or altered state rows before any baseline is accepted.
- The journal is append-only during an instance.
- The chart panel is a projection of current state and is never authoritative.
- Phase 5 restart recovery rescans broker positions bearing the SolTrade magic
  number; local state alone never proves that a position exists. A restored
  close claim can deny a replay but cannot make a broker position exist.

## Failure policy

| Condition | Phase 5 behaviour |
|---|---|
| Real account | `REAL EXECUTION LOCKED`; reject before permission checks |
| Demo capability disabled/unapproved | Monitor and journal exact refusal; no broker call |
| Terminal disconnected or trading permission off | Reject new entry or close |
| Missing/old tick or history | Reject new entry with exact market reason |
| Existing SolTrade exposure | Reject another entry |
| Unrelated configured-symbol position | Reject rather than take ownership |
| Invalid volume, stop, spread, or margin | Reject before submission |
| `OrderCheck`/broker rejection | Journal result; consume candle; no retry |
| Position Manager disabled | Monitor owned position/stop; never prepare a close |
| Manual or wrong-magic position | Never adopt, modify, or close |
| BUY without `EXIT_LONG` / SELL without `EXIT_SHORT` | No close request |
| Emergency Risk Engine lock / `EmergencyStop` | Request one owned-position close if management is enabled |
| Missing position stop | Alert and journal; do not modify the stop |
| Position changes after persistent claim | Reject close; consume attempt; no retry |
| Close `OrderCheck`/broker rejection | Journal full diagnostics; consume attempt; no retry |
| Matching exit transaction | Record actual close/slippage/tickets/reason and distinct outcome |
| Missing execution state on first run | Create empty state atomically |
| Execution state corrupt/unreadable | Fail initialisation; reject all entries |
| Position state corrupt/unreadable | Fail initialisation; reject position management |
| Existing unprotected SolTrade position after restart | Alert and lock entries; no silent stop repair |
| Configuration/journal/risk persistence invalid | Fail closed |

Raw technical signals remain visible even when execution is locked. This
preserves module separation: the strategy reports what the completed candles
say, while risk and execution state separately report whether an entry is
permitted.

## Environment parity

The EA detects tester, demo, and real environments using MT5 runtime/account
properties. `ExpectedEnvironment` can add a stricter deployment assertion but
cannot make a real account look like a demo account. The detected environment is
always used for safety decisions and logging.
