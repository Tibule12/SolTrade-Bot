# Changelog

All notable changes are recorded here. The project uses semantic versions for
strategy/release identification, but a version number does not imply trading
approval.

## [Unreleased]

### Added

- Phase 1 repository structure and development documentation.
- Monitoring-only native MQL5 Expert Advisor foundation.
- Configuration validation and tester/demo/real account detection.
- Default-deny live-account safety gates.
- Market snapshot validation and H1 new-candle detection.
- CSV event journal and on-chart status panel.
- Phase 2 pure risk-budget, lot-normalisation, stop-distance, and spread
  calculations.
- Persistent daily, weekly, emergency, and consecutive-loss lock state.
- Phase 2 dashboard/journal risk metrics.
- Deterministic MQL5 and independent arithmetic tests for $500 and $10,000
  account fixtures.
- Phase 3 completed-candle Trend Breakout V1 engine with EMA 200, Donchian
  20/10, Wilder ATR 14, structured entry/exit signals, and reason codes.
- Deterministic historical signal fixtures for BUY, SELL, NONE, strict channel
  boundaries, trend-filter vetoes, exit channels, and invalid history.
- Phase 3 signal metrics and reasons on the chart dashboard and in CSV details.
- Phase 4 Strategy Tester/approved-demo entry execution engine.
- Exact demo-account approval with execution disabled by default and
  unconditional real-account rejection.
- Signal-to-risk integration, broker volume/stop/spread/margin validation, and
  one-position/duplicate-candle entry gates.
- Atomic execution-attempt persistence and broker-exposure restart recovery.
- Initial stop-loss submission with SolTrade magic-number market entries.
- Structured request, broker-result, and confirmed-fill journaling.
- Deterministic Phase 4 tests for BUY/SELL requests and every required rejection
  or recovery case.
- A hard-locked one-shot connected-demo verification script using the same
  Execution Engine, safer broker-minimum volume, persistent self-disable marker,
  and matching entry-deal confirmation.
- Complete `OrderCheck`, trade-request, and broker symbol-constraint diagnostics
  in both Experts output and CSV execution rows.
- Phase 5 SolTrade-magic-only Position Manager with broker-authoritative restart
  rebuilding and stop-loss presence verification.
- Direction-locked Donchian 10-bar exits: BUY only on `EXIT_LONG`, SELL only on
  `EXIT_SHORT`.
- Emergency drawdown and operator `EmergencyStop` position-close triggers.
- Atomic persistent close-attempt claims, exact ticket revalidation, one
  synchronous close request, and no automatic retry.
- Structured close request/check/send/fill journaling with requested and actual
  price, slippage, return code, order/deal tickets, net P/L, and exit reason.
- Deterministic Phase 5 position-management tests and an unarmed connected-demo
  procedure that make no broker call.
- A separate default-unarmed Phase 5 connected-demo fixture and position-close
  verifier with mutually exclusive action flags, exact demo/symbol/magic
  ownership, attached-stop proof, independent permanent entry/close markers,
  one Position Manager close call, and no retry.
- Position Manager exit-deal history confirmation for one-shot scripts,
  preserving the original OrderCheck/OrderSend diagnostics while recording
  actual close, slippage, realised P/L, tickets, and exit reason.
- An isolated close-verifier V2 compile target requiring both creation and close
  confirmations in one run, with new V2 risk/state directories, marker
  prefixes, and schemas that never read or overwrite the preserved V1
  `ENTRY_REJECTED_DISABLED` marker.
- Phase 6 default-off tester gates with exact dataset, runtime, fixed-delay,
  source, history, and canonical-input validation.
- SHA-256 trading-input identity shared by each authoritative/replica pair,
  with a separate one-use `ExecutionInstanceId` for state/artifact isolation.
- Chronological native and supplementary trade cash-flow reconstruction,
  equity curves, concentration, boundary evidence, and one-cent
  history/Tester reconciliation.
- Reporting-only independent-return bootstrap and reshuffle analytics.
- A deterministic Phase 6 MQL safety suite, independent reporting checks,
  frozen-history verifier, replica reconciler, and proposed 3 × 3 manifest.
- A default-unarmed, demo-only, non-trading Phase 6 real-tick acquisition
  script and an immutable TKC/HCC/specification/session/build inventory tool.

### Safety

- Entry and close submission each have one bounded synchronous gateway and are
  limited to Strategy Tester or an explicitly approved demo account.
- Position management defaults off, adopts only exact SolTrade magic/symbol
  positions, and cannot manage unrelated manual positions.
- Stop-loss presence is monitored; no stop-repair, trailing, take-profit,
  pending-order, or automatic retry path exists.
- The one-shot verifier defaults unarmed, rejects every non-demo account, and
  cannot submit more than once per persistent marker.
- Live trading is disabled by default.
- Configuration rejects `AllowLiveTrading=true`; real accounts are always
  execution-locked in Phase 5.
- Emergency drawdown is latched and cannot clear from equity recovery alone.
- Phase 6 initialization is Strategy-Tester-only, rejects connected demo/live
  approvals, and rejects any reused state or artifact namespace.
- No authoritative/replica run is authorized by the proposed manifest; its
  current real-tick coverage status is explicitly failed.
- The original Phase 6 date matrix is blocked by 12 recorded in-session
  candidate gaps and incomplete M1 access; no generated ticks were substituted.

### Changed

- Corrected the one-shot `OrderCheck` success contract: boolean `true` plus
  `MqlTradeCheckResult.retcode=0` is accepted for the sole `OrderSend` gateway;
  false or non-zero check results remain fail-closed with no retry.
- Moved the updated one-shot verifier to a diagnostic V2 marker namespace so
  the original rejected-attempt marker remains preserved.
- MQL5 program property version is `1.000`, matching the MetaEditor-verified
  source format.
- Strategy identity advanced from the foundation marker to Trend Breakout V1
  version `1.0.0`.
- Distributed the 50-trade Phase 6 sample fixture across registered reporting
  subperiods after the single connected run correctly rejected its original
  100%-concentrated fixture; acceptance thresholds were not changed.
