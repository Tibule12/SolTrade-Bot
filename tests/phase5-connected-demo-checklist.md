# Phase 5 Connected-Demo Deterministic Verification

This is the unarmed Phase 5 verification procedure. It tests calculations,
ownership, direction, persistence, duplicate protection, and safety gates. It
does not submit, modify, or close a broker position.

Do not set `EnablePositionManagement=true` during this procedure.

## 1. Preconditions

Use the already approved easyMarkets demo terminal and confirm:

- the connected account is a demo account;
- the Trade tab is empty;
- the chart symbol is exactly `EURUSD`;
- the chart timeframe is `H1`; and
- the terminal Algo Trading button is off.

No live or real account is permitted for this procedure.

## 2. Copy the exact source

In the connected terminal, choose **File > Open Data Folder**. Close
MetaEditor before replacing source files.

Copy these repository files:

```text
MQL5/Experts/SolTradeBot.mq5
  -> <data-folder>/MQL5/Experts/SolTradeBot.mq5

MQL5/Include/SolTrade/AccountGuard.mqh
MQL5/Include/SolTrade/Config.mqh
MQL5/Include/SolTrade/Dashboard.mqh
MQL5/Include/SolTrade/ExecutionEngine.mqh
MQL5/Include/SolTrade/MarketData.mqh
MQL5/Include/SolTrade/PositionManager.mqh
MQL5/Include/SolTrade/RiskEngine.mqh
MQL5/Include/SolTrade/StrategyBreakout.mqh
MQL5/Include/SolTrade/TradeJournal.mqh
  -> <data-folder>/MQL5/Include/SolTrade/

MQL5/Scripts/SolTradePositionManagerTests.mq5
  -> <data-folder>/MQL5/Scripts/SolTradePositionManagerTests.mq5

MQL5/Scripts/SolTradeExecutionTests.mq5
  -> <data-folder>/MQL5/Scripts/SolTradeExecutionTests.mq5

MQL5/Scripts/SolTradeOneShotDemoVerification.mq5
  -> <data-folder>/MQL5/Scripts/SolTradeOneShotDemoVerification.mq5
```

The final two scripts are copied only to keep the approved Phase 4 regression
and one-shot source compatible with the Phase 5 configuration structure. Do
not run or arm the one-shot verifier.

## 3. Compile

1. Press **F4** in the connected terminal.
2. In MetaEditor, open
   `MQL5/Experts/SolTradeBot.mq5`.
3. Press **F7** and require the Toolbox summary:

   ```text
   Result: 0 errors, 0 warnings
   ```

4. Confirm `MQL5/Experts/SolTradeBot.ex5` exists in the Navigator or data
   folder.
5. Open `MQL5/Scripts/SolTradePositionManagerTests.mq5`.
6. Press **F7** and require:

   ```text
   Result: 0 errors, 0 warnings
   ```

7. Confirm `MQL5/Scripts/SolTradePositionManagerTests.ex5` exists.

Do not enable Algo Trading and do not change either management enable flag.

## 4. Unarmed EA preflight

Attach `SolTradeBot` to the `EURUSD` H1 demo chart with:

```text
ExpectedEnvironment       = DEMO
EnableDemoExecution       = false
EnablePositionManagement  = false
ApprovedDemoAccount       = 0
AllowLiveTrading          = false
EmergencyStop             = false
```

Leave every approved strategy/risk input unchanged. On the Common tab, do not
permit Algo Trading.

Expected dashboard evidence includes:

```text
Build scope: PHASE 5 POSITION MANAGEMENT; NO BACKTESTING/PHASE 6
Account mode: DEMO
Demo execution enabled: NO
Position management enabled: NO
Managed position: NONE
Position Manager state valid / restored: YES / NO
```

The main status must be:

```text
DEMO AUTOMATION DISABLED
```

The restored value may be `YES` instead of `NO` when a valid monitoring-state
file already exists.

Expected startup journal events include:

```text
RISK_ENGINE_STARTED
EXECUTION_STATE_INITIALISED
POSITION_STATE_INITIALISED
FOUNDATION_STARTED
ACCOUNT_GUARD_REFUSAL
```

`*_STATE_RESTORED` may replace `*_STATE_INITIALISED` when a valid prior
monitoring state file exists. `FOUNDATION_STARTED` details must state:

```text
Phase 5 position management started; demo entry disabled; position management disabled; live trading disabled; no Phase 6
```

Confirm the Trade tab remains empty. No order, deal, or position may appear.
The manager may create its account/magic-scoped restart-state file even while
disabled; this is monitoring state, not an execution or completion marker.

## 5. Run the deterministic script

In Navigator, expand **Scripts**, right-click and refresh if needed, then run
`SolTradePositionManagerTests` once. It has no user inputs and no broker
submission path.

The first two Experts lines must be:

```text
SolTrade Phase 5 Position Manager deterministic tests started
This script never submits, modifies, or closes a broker position.
```

Require no `FAIL |` line. The final two lines must be exactly:

```text
SolTrade Position Manager tests complete: 79 passed, 0 failed
ALL SOLTRADE PHASE 5 POSITION MANAGER TESTS PASSED
```

The suite covers:

- exact SolTrade magic ownership and manual-position rejection;
- BUY/`EXIT_LONG` and SELL/`EXIT_SHORT` direction enforcement;
- Bid/Ask close-side construction and exact position ticket/magic;
- real-account, wrong-demo, permissions, quote, volume, and default-off gates;
- emergency drawdown and `EmergencyStop` triggers;
- stop-loss presence/missing-stop visibility;
- requested/actual close slippage calculations;
- persistent one-attempt claim and duplicate prevention;
- isolated restart restoration, broker snapshot reconciliation, and
  multiple-position fail-closed behaviour; and
- matching exit-deal and duplicate-transaction filtering.

The test uses its own `phase5-restart-isolated` persistence namespace and
deletes the fixture file before and after the restart cases.

## 6. Prove no trading occurred

After the script ends:

1. Confirm **Trade** remains empty.
2. In **History**, confirm there is no new order or deal at the test time.
3. Search Experts and Journal for `OrderSend`, `POSITION_CLOSE_ACCEPTED`, and
   `POSITION_EXIT_TRANSACTION_CONFIRMED`; none may be emitted by the test.
4. Confirm the EA dashboard still says `Position Management Enabled: NO`.
5. Remove the EA or leave it attached only with both enable flags false.

Do not create a manual fixture position, do not rerun the one-shot order
verifier, and do not enable automated closing yet.

## 7. Return evidence

Return:

- both MetaEditor summaries showing `0 errors, 0 warnings`;
- the complete Phase 5 test output ending in `79 passed, 0 failed`;
- a screenshot of the unarmed dashboard;
- Experts/Journal excerpts containing the startup state and test summary;
- Trade and History evidence that no order, deal, position, or close occurred;
  and
- any unexpected `FAIL`, state, or stop-loss message verbatim.

Automated position closing remains disabled until this evidence is reviewed.
