# SolTrade Bot

SolTrade Bot is a private, experimental MetaTrader 5 Expert Advisor for testing a
fully specified trend-breakout strategy under conservative risk controls.

The project does **not** promise returns. Its purpose is to determine whether the
strategy remains viable after realistic costs and losing periods while failing
closed whenever market, account, or execution state is uncertain.

## Current status

Phase 6 — default-disabled, tester-only research reporting. The proposed
manifest is blocked as `HISTORY_UNAVAILABLE_FOR_PROPOSED_MATRIX`; no
authoritative backtest has been run.

Verified Phase 1 foundation:

- one native MQL5 Expert Advisor entry point;
- configuration validation and conservative defaults;
- tester/demo/real account-mode detection;
- a default-deny live-account guard;
- market-data and history validation;
- completed-candle/new-bar detection;
- CSV event journaling;
- a read-only on-chart monitoring panel.

Implemented in Phase 2:

- 0.25%-of-equity monetary risk budgets;
- loss-side tick-value position sizing;
- volume-step rounding down with a post-rounding risk check;
- stop-distance and dual spread-gate validation APIs;
- persistent broker-day and broker-week equity baselines;
- daily, weekly, emergency, and consecutive-loss lock states;
- deterministic MQL5 tests for $500 and $10,000 fixtures;
- live risk status, budget, drawdown, and lock information on the dashboard and
  in the CSV journal.

Implemented in Phase 3:

- EMA 200 trend filtering;
- 20-bar Donchian entry and 10-bar Donchian exit channels;
- Wilder-smoothed ATR 14 and a displayed `2 × ATR` initial-stop distance;
- BUY, SELL, and NONE entry signals plus hypothetical long/short exit signals;
- fixed-window calculations using completed H1 candles only;
- structured reason codes in the CSV journal and full signal metrics on the
  dashboard;
- deterministic historical MQL5 and independent fixture tests.

Implemented in Phase 4:

- integration of approved BUY/SELL signals with Phase 2 risk locks and
  0.25%-of-equity position sizing;
- broker volume, initial-stop, dual-spread, margin, permission, and exposure
  validation;
- one synchronous market-order gateway using the SolTrade magic number and an
  initial stop-loss;
- default-disabled, exact-account demo approval and unconditional Phase 4
  real-account rejection;
- completed-candle duplicate prevention and atomically persisted restart state;
- broker request/result/fill journaling with price, spread, slippage, volume,
  risk, stop, tickets, and return code;
- deterministic execution tests that do not submit an order.
- a separately armed, persistent one-shot connected-demo verification script
  that uses the same execution gateway and never retries or closes a position.

Implemented in Phase 5:

- SolTrade-magic-only broker position ownership and restart rebuilding;
- continuous initial stop-loss presence verification;
- completed-candle Donchian 10-bar `EXIT_LONG`/`EXIT_SHORT` direction gates;
- emergency drawdown and operator `EmergencyStop` closure triggers;
- an atomically claimed, single synchronous full-position close attempt with no
  automatic retry;
- exact close request, broker check/send, fill, slippage, ticket, deal, P/L,
  and exit-reason journaling;
- default-disabled connected-demo management with exact account approval and
  unconditional real-account rejection; and
- deterministic Phase 5 tests that contain no broker call.
- a separate default-unarmed, permanently marked connected-demo fixture/close
  verifier that routes through the approved ExecutionEngine and Position
  Manager and cannot retry.

Implemented for Phase 6 review:

- Strategy-Tester-only research gates and inclusive/exclusive dataset locks;
- canonical SHA-256 trading-input identity with separate one-use
  `ExecutionInstanceId` state/artifact isolation;
- native MT5 and supplementary cost-adjusted result layers;
- chronological trade-level cash-flow, metric, equity-curve, boundary, and
  history reconciliation;
- deterministic bootstrap/reshuffle uncertainty reporting that never enters a
  trading decision;
- an authoritative/replica reconciliation tool and a proposed 3 × 3 frozen
  manifest.

Deliberately not implemented or authorized:

- automatic stop repair, trailing stops, or take-profit management;
- optimization, Phase 7 forward-demo automation, or live trading;
- any of the nine authoritative runs or nine replicas before manifest review.

Entry execution and position management have separate default-off flags. Either
connected-demo capability requires the exact approved demo login. Both remain
unconditionally unavailable on real accounts.

## Repository layout

```text
.
├── MQL5/
│   ├── Experts/SolTradeBot.mq5
│   ├── Include/SolTrade/
│   └── Scripts/
│       ├── SolTradeRiskTests.mq5
│       ├── SolTradeStrategyTests.mq5
│       ├── SolTradeExecutionTests.mq5
│       ├── SolTradePositionManagerTests.mq5
│       ├── SolTradePhase6HistoryAcquisition.mq5
│       ├── SolTradePhase6SafetyTests.mq5
│       ├── SolTradeOneShotPositionCloseVerification.mq5
│       ├── SolTradeOneShotPositionCloseVerificationV2.mq5
│       └── SolTradeOneShotDemoVerification.mq5
├── docs/
├── tools/
│   ├── phase6_analyze.py
│   ├── phase6_manifest.py
│   ├── phase6_history_inventory.py
│   ├── phase6_reconcile_pair.py
│   └── phase6_verify_history.py
├── tests/
└── reports/
    ├── backtests/
    ├── forward-demo/
    └── live-validation/
```

The intended final layout and module boundaries are documented in
[`docs/architecture.md`](docs/architecture.md).

## Phase 6 verification status

The EA and all nine regression/safety/history scripts compile with zero errors and
zero warnings. `tests/static-phase6.sh` runs the non-broker reporting,
arithmetic, isolation, and prior-phase regression checks.

All 30 proposed in-range TKC months were acquired without a tick-copy failure,
but 12 in-session candidate gaps and incomplete connected M1 access make the
original `[2024-01-01, 2026-07-01)` matrix unavailable. The review-only
replacement interval is `[2024-01-16, 2024-12-24)` after a separate warm-up.

The single connected Phase 6 safety run created no orders, deals, positions, or
marker changes, but reported 65 passed and 1 failed because a 50-trade fixture
violated the unchanged concentration rule. The fixture was corrected and
compiled; no second connected run has been authorized. All manifest hashes
remain review evidence, not run authorization.

Journal files are written beneath `MQL5/Files/SolTradeBot/logs` in the
terminal/tester file sandbox. No passwords are read or recorded.
Persistent risk state is written atomically beneath
`MQL5/Files/SolTradeBot/state`. Separate execution state in the same directory
persists consumed signal candles and request details. Phase 5 position state
persists broker position identity and the one-attempt close claim.

## Safety notice

`EnableDemoExecution`, `EnablePositionManagement`, and all three Phase 6 tester
capabilities default to `false`;
`ApprovedDemoAccount` defaults to `0`; and `AllowLiveTrading` defaults to
`false`. Phase 5 configuration rejects `AllowLiveTrading=true`, and both broker
gateways reject every detected real account regardless of the Algo Trading
button.

See:

- [`docs/configuration-model.md`](docs/configuration-model.md)
- [`docs/account-mode-safety.md`](docs/account-mode-safety.md)
- [`docs/risk-calculation-spec.md`](docs/risk-calculation-spec.md)
- [`docs/execution-engine.md`](docs/execution-engine.md)
- [`docs/position-management.md`](docs/position-management.md)
- [`docs/phase6-backtesting.md`](docs/phase6-backtesting.md)
- [`docs/testing-plan.md`](docs/testing-plan.md)
- [`tests/risk-engine-calculation-cases.md`](tests/risk-engine-calculation-cases.md)
- [`tests/expected-strategy-signals.csv`](tests/expected-strategy-signals.csv)
- [`tests/phase3-runtime-verification.md`](tests/phase3-runtime-verification.md)
- [`tests/phase4-connected-demo-checklist.md`](tests/phase4-connected-demo-checklist.md)
- [`tests/one-shot-connected-demo-procedure.md`](tests/one-shot-connected-demo-procedure.md)
- [`tests/phase5-connected-demo-checklist.md`](tests/phase5-connected-demo-checklist.md)
- [`tests/one-shot-position-close-preflight.md`](tests/one-shot-position-close-preflight.md)
- [`tests/one-shot-position-close-v2-preflight.md`](tests/one-shot-position-close-v2-preflight.md)
