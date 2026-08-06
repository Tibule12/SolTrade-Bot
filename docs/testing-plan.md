# Testing Plan

## Test order

1. Static repository and source checks.
2. MetaEditor compile with zero errors and zero warnings.
3. Phase 1 Strategy Tester smoke tests.
4. Demo attachment and connectivity tests.
5. Account-mode guard tests.
6. Restart and stale-data tests.
7. Phase-specific calculation, signal, and pure execution-request tests.
8. Backtest, forward demo, and only then micro-live validation.

## Foundation checklist

- [ ] `tests/static-phase1.sh` passes.
- [ ] Repository contains only one EA entry point.
- [ ] MetaEditor reports zero errors and zero warnings.
- [ ] Foundation modules contain no trading API calls.
- [ ] Tester mode is detected and displayed as `BACKTEST`.
- [ ] Demo mode is detected and displayed as `DEMO`.
- [ ] A real account with default inputs shows `LIVE DISABLED`.
- [ ] A mismatched explicit expected environment fails closed.
- [ ] Invalid symbol/timeframe/configuration prevents readiness.
- [ ] Missing history shows `MARKET DATA INVALID`.
- [ ] Stale/disconnected quotes show the exact validation reason.
- [ ] One event is produced for a new H1 bar; ticks within the bar do not create
      repeated completed-candle events.
- [ ] The journal header and rows open correctly in a CSV reader.
- [ ] Journal rows contain no raw account login or credentials.
- [ ] Journal open failure prevents normal initialisation.
- [ ] Parameter changes/restart reinitialise without duplicate activity.
- [ ] The panel clearly states the current build scope.

Detailed manual cases are in `tests/account-mode-cases.md` and
`tests/restart-recovery-cases.md`.

## Phase 2 checklist

- [ ] `tests/static-phase2.sh` passes.
- [ ] `tests/verify-risk-math.sh` passes.
- [ ] `SolTradeBot.mq5` compiles with zero errors and warnings.
- [ ] `SolTradeRiskTests.mq5` compiles with zero errors and warnings.
- [ ] Running the script prints `ALL SOLTRADE PHASE 2 RISK TESTS PASSED`.
- [ ] $500 risk budget is $1.25; 123-tick fixture rounds to 0.01 lots and $1.23 loss.
- [ ] $10,000 risk budget is $25; 123-tick fixture rounds to 0.20 lots and $24.60 loss.
- [ ] Zero/negative/under-broker-minimum stops are rejected.
- [ ] Volumes below broker minimum are rejected instead of rounded up.
- [ ] Daily locks trigger at $495 and $9,900 respectively.
- [ ] Weekly locks trigger at $487.50 and $9,750 respectively.
- [ ] Emergency locks trigger at $475 and $9,500 and remain latched after recovery.
- [ ] Third distinct losing outcome locks; duplicate ID does not increment.
- [ ] Consecutive-loss pause clears on the next broker day.
- [ ] Persistent restart restores the same daily/weekly baselines and locks.
- [ ] Corrupt risk state causes initialisation failure with no order activity.
- [ ] Dashboard and CSV show budget/drawdown/lock state.
- [ ] Source still contains no trading API path.

Phase 2 received connected-demo approval with 130 passed and zero failed tests.

## Phase 3 checklist

- [ ] `tests/static-phase3.sh` passes.
- [ ] `tests/verify-strategy-fixtures.sh` passes.
- [ ] `SolTradeBot.mq5` compiles with zero errors and warnings.
- [ ] `SolTradeStrategyTests.mq5` compiles with zero errors and warnings.
- [ ] Running the script prints
      `ALL SOLTRADE PHASE 3 STRATEGY TESTS PASSED`.
- [ ] Flat history returns EMA 1.1000, ATR 0.0010, and no entry/exit signal.
- [ ] BUY requires strict D20-high breakout and close above EMA 200.
- [ ] SELL requires strict D20-low breakout and close below EMA 200.
- [ ] Equality at D20 and D10 boundaries produces no breakout.
- [ ] Up/down breakouts failing the EMA filter return NONE with exact reason.
- [ ] D10 long/short exits evaluate independently from D20 entries.
- [ ] Insufficient, malformed, or non-chronological history fails closed.
- [ ] Runtime strategy history starts at shift 1 and excludes the forming bar.
- [ ] Dashboard and CSV details show signal bar, EMA, D20/D10, ATR, entry/exit,
      and structured reason codes.
- [ ] No order, position, stop-submission, or trade-transaction API exists.

Phase 3 received connected-demo approval with 61 passed and zero failed tests.

## Phase 4 checklist

- [ ] `tests/static-phase4.sh` passes.
- [ ] `tests/verify-execution-fixtures.sh` passes.
- [ ] `SolTradeBot.mq5` compiles with zero errors and warnings.
- [ ] `SolTradeExecutionTests.mq5` compiles with zero errors and warnings.
- [ ] Running the script prints
      `SolTrade Execution tests complete: 74 passed, 0 failed`.
- [ ] Running the script prints
      `ALL SOLTRADE PHASE 4 EXECUTION TESTS PASSED`.
- [ ] The deterministic test script never invokes the broker submission path.
- [ ] Valid approved-demo BUY and SELL plans use Ask/Bid respectively, attach
      the initial stop, use the magic number, and round volume down to the
      broker lot step.
- [ ] A $10,000 fixture produces a $25 budget and a 0.12-lot/$24 risk request
      for the deterministic 200-tick stop.
- [ ] Every real account is rejected before terminal/Algo Trading permission
      can affect the result.
- [ ] `AllowLiveTrading=true` is rejected by configuration validation.
- [ ] Demo execution defaults off and requires an exact approved demo login.
- [ ] Invalid volume, minimum stop, margin, absolute/ATR spread, duplicate
      candle, existing exposure, and broker return codes fail closed.
- [ ] The completed candle is atomically persisted before `OrderSend`.
- [ ] Broker rejection consumes the candle and permits no automatic retry.
- [ ] `actual_entry` is not confirmed until a matching entry deal transaction.
- [ ] Restart restores the consumed candle and rescans broker exposure.
- [ ] The request contains the initial stop-loss, SolTrade magic number, and no
      take-profit.
- [ ] The Phase 4 entry gateway still has no async, position-modification, or
      strategy-exit responsibility; Phase 5 closing remains a separate module.
- [ ] The complete locked connected-demo procedure in
      `tests/phase4-connected-demo-checklist.md` passes before demo execution is
      enabled.

Phase 4 received connected-demo approval after 74 deterministic tests and one
controlled EURUSD order with its original stop, matching transaction, no
duplicate, and no retry.

## Phase 5 checklist

- [ ] `tests/static-phase5.sh` passes.
- [ ] `tests/verify-position-manager-fixtures.sh` passes.
- [ ] `SolTradeBot.mq5` compiles with zero errors and zero warnings.
- [ ] `SolTradePositionManagerTests.mq5` compiles with zero errors and zero
      warnings.
- [ ] `EnablePositionManagement` is still false and Algo Trading is off.
- [ ] Running the deterministic script prints
      `SolTrade Position Manager tests complete: 79 passed, 0 failed`.
- [ ] Running the deterministic script prints
      `ALL SOLTRADE PHASE 5 POSITION MANAGER TESTS PASSED`.
- [ ] The deterministic script contains no `OrderCheck` or `OrderSend` call.
- [ ] Exact SolTrade magic and EURUSD ownership are required; manual and
      wrong-magic positions are rejected.
- [ ] BUY close planning accepts only completed-candle `EXIT_LONG` and uses
      SELL/Bid.
- [ ] SELL close planning accepts only completed-candle `EXIT_SHORT` and uses
      BUY/Ask.
- [ ] Emergency drawdown and `EmergencyStop` can trigger risk-reducing closure
      without a strategy exit.
- [ ] Broker `POSITION_SL` is rebuilt and checked after restart; missing stop is
      visible and no modification API exists.
- [ ] Close volume is the broker position's full valid volume.
- [ ] The exact position ticket, identifier, magic, symbol, direction, and
      volume are revalidated after the persistent claim.
- [ ] Close claim persistence precedes `OrderCheck` and the sole synchronous
      close `OrderSend`.
- [ ] A check rejection, send rejection, or changed position consumes the
      attempt with no automatic retry.
- [ ] A matching exit transaction records requested/actual close, slippage,
      retcode, order/deal tickets, net P/L, and exit reason.
- [ ] Restart restores an existing close claim and cannot replay it.
- [ ] More than one SolTrade magic position fails closed.
- [ ] `AllowLiveTrading=true` and every real-account close are rejected.
- [ ] The complete unarmed procedure in
      `tests/phase5-connected-demo-checklist.md` passes before automated closing
      is enabled.
- [ ] Trade and History remain unchanged during deterministic verification.

Backtesting and Phase 6 remain outside the Phase 5 test scope.

## Phase 6 pre-run checklist

- [x] `tests/static-phase6.sh` passes without a broker call.
- [x] Production EA and every Phase 2–6/regression script compile with zero
      errors and zero warnings.
- [x] Canonical trading inputs exclude `ExecutionInstanceId`; pure MQL fixtures
      prove identical signal, volume, requested entry, stop, and magic.
- [x] State/artifact namespaces are hash-and-instance isolated and must be
      empty at initialization.
- [x] Supplementary multipliers are exactly `0.00`, `0.50`, and `1.00`, using
      chronological trade-level cash flows without scaling native statistics.
- [x] Native and supplementary result layers are separately labelled.
- [x] OOS fewer than 50 closed trades is
      `INCONCLUSIVE_INSUFFICIENT_SAMPLE`.
- [x] Reporting-only uncertainty assumptions are explicit.
- [x] Fixed-delay pair reconciliation invalidates missing/mismatched artifacts.
- [ ] Proposed manifest passes review.
- [ ] Complete real-tick history covers the registered interval and its
      inventory fingerprint is frozen.
- [ ] Exact first/final ticks and tester history-quality messages are available.
- [ ] All nine authoritative names and nine replica names/hashes are approved.

No Strategy Tester matrix run, optimization, Phase 7, connected-demo
automation, or live trading is authorized while any final four boxes are open.

## Controlled one-shot position-close verification

After the 79-case Phase 5 suite is approved, run
`tests/static-one-shot-position-close.sh` and compile both the production EA
and `SolTradeOneShotPositionCloseVerification.mq5` with zero errors and zero
warnings.

First complete only `tests/one-shot-position-close-preflight.md` with both
confirmation inputs false, Algo Trading off, no position, and the production EA
detached. The unarmed run must create no order, deal, position, close, journal
row, state file, or marker.

Fixture creation and closing require separate later authorization. A later
close can call Position Manager once and must permanently disable after
acceptance, rejection, timeout, partial exit, or confirmed full exit. Phase 6
remains prohibited until the connected easyMarkets close path is confirmed.

If a prior verifier namespace is permanently consumed, preserve its marker.
Use the separately compiled V2 target and
`tests/one-shot-position-close-v2-preflight.md`; V2 requires both creation and
close confirmations and uses only V2 risk/state directories, marker prefixes,
and schemas. Its armed values remain prohibited until the V2 inert evidence is
reviewed.

## Later backtesting protocol

Use MT5 “Every tick based on real ticks” where broker data permits. Separate
history chronologically into 50% development, 25% validation, and 25% untouched
final test data. Include trending, sideways, volatile, quiet, and disrupted
periods.

Every accepted or rejected parameter variation must record date, rationale,
values, dataset, cost scenario, and results. Normal-, high-, and stress-cost
scenarios must include realistic spread, commission, swap, delay, and slippage
sensitivity. No final-test optimisation is permitted.

## Forward-demo minimum

Use the exact compiled EA and settings intended for later approval. Continue for
at least eight weeks and at least 50 trades where reasonably achievable, including
restart/network tests and both winning and losing sequences. Record fills,
slippage, rejections, downtime, drawdown, expectancy, profit factor, and streaks.

Reports belong in the matching `reports` subdirectory and must identify the
source commit, build, broker, account type, symbol, timeframe, inputs, dates,
data model, and cost assumptions.

## Controlled one-shot demo execution

After the 74-case Phase 4 suite is approved, run
`tests/static-one-shot-demo.sh` and compile both the production EA and
`SolTradeOneShotDemoVerification.mq5` with zero errors and warnings.

Before arming the script, complete Stages A–C of
`tests/one-shot-connected-demo-procedure.md`. The default inert run must create
no order or one-shot marker. One explicitly armed run may call the approved
Execution Engine once and must persist its disable marker before that call.

Accepted, rejected, and accepted-but-unconfirmed outcomes all terminate without
retry. No verification code may close or modify the resulting position.
