# Phase 5 One-Shot Position-Close Verification — Unarmed Preflight

This procedure verifies installation and the inert branch of the separate
connected-demo position-close verifier. It does not authorize creation of a
fixture position and does not authorize a close.

Keep both arming inputs `false`.

Phase 6 and backtesting remain prohibited and are not part of this verifier.

## 1. Safety boundary

`SolTradeOneShotPositionCloseVerification` is separate from the production EA.
It has three mutually exclusive states:

1. unarmed preflight;
2. later one-shot protected-position creation through the approved
   `ExecutionEngine`; or
3. later one-shot emergency close through the approved `PositionManager`.

The two broker-action states cannot be selected together. Each has a separate
permanent marker. The close state:

- rejects Strategy Tester, live accounts, unknown account modes, and every
  non-demo account;
- requires the raw connected demo login to exactly equal
  `ApprovedDemoAccount`;
- is hard-coded to `EURUSD`, H1, and magic number `2607202601`;
- requires exactly one matching SolTrade-owned broker position;
- verifies that its broker `POSITION_SL` is positive before closing;
- ignores unrelated manual/wrong-magic positions;
- uses `SOLTRADE_CLOSE_EMERGENCY_STOP`, not a fabricated Donchian signal;
- calls the approved `PositionManager.ProcessClose()` exactly once;
- can therefore reach only its one synchronous close `OrderSend`;
- persists its script marker before the manager call, while Position Manager
  persists its own exact-position claim before `OrderCheck`;
- polls account history only to confirm the matching exit deal;
- never retries after an accepted or rejected attempt; and
- remains unavailable on every real account.

The optional fixture-creation state uses the approved Execution Engine, the
approved 0.25% Risk Engine calculation, the safer broker-minimum volume, and an
initial stop in the original order. It can create at most one fixture and does
not close it in the same run.

Neither broker-action state is authorized by this document.

## 2. Exact source files to copy

In the connected terminal choose **File > Open Data Folder**. Replace the
following source copies. Do not copy repository `.ex5` files.

```text
Repository source                                      MetaTrader data directory
MQL5/Experts/SolTradeBot.mq5                         -> MQL5/Experts/SolTradeBot.mq5
MQL5/Include/SolTrade/AccountGuard.mqh               -> MQL5/Include/SolTrade/AccountGuard.mqh
MQL5/Include/SolTrade/Config.mqh                     -> MQL5/Include/SolTrade/Config.mqh
MQL5/Include/SolTrade/Dashboard.mqh                  -> MQL5/Include/SolTrade/Dashboard.mqh
MQL5/Include/SolTrade/ExecutionEngine.mqh            -> MQL5/Include/SolTrade/ExecutionEngine.mqh
MQL5/Include/SolTrade/MarketData.mqh                 -> MQL5/Include/SolTrade/MarketData.mqh
MQL5/Include/SolTrade/PositionManager.mqh            -> MQL5/Include/SolTrade/PositionManager.mqh
MQL5/Include/SolTrade/RiskEngine.mqh                 -> MQL5/Include/SolTrade/RiskEngine.mqh
MQL5/Include/SolTrade/StrategyBreakout.mqh           -> MQL5/Include/SolTrade/StrategyBreakout.mqh
MQL5/Include/SolTrade/TradeJournal.mqh               -> MQL5/Include/SolTrade/TradeJournal.mqh
MQL5/Scripts/SolTradeOneShotPositionCloseVerification.mq5
                                                    -> MQL5/Scripts/SolTradeOneShotPositionCloseVerification.mq5
```

Copying the complete include set prevents an older Phase 4 or Phase 5
dependency from being combined with the new verifier.

## 3. Compile in the connected MetaEditor

1. Press **F4** from the connected terminal.
2. Open `MQL5/Experts/SolTradeBot.mq5`.
3. Press **F7** once.
4. Require:

   ```text
   Result: 0 errors, 0 warnings
   ```

5. Confirm `MQL5/Experts/SolTradeBot.ex5` has a new compilation timestamp.
6. Open
   `MQL5/Scripts/SolTradeOneShotPositionCloseVerification.mq5`.
7. Press **F7** once.
8. Require:

   ```text
   Result: 0 errors, 0 warnings
   ```

9. Confirm
   `MQL5/Scripts/SolTradeOneShotPositionCloseVerification.ex5` exists with a
   new compilation timestamp.
10. Return to MetaTrader and refresh Navigator if necessary.

Do not attach the production EA.

## 4. New marker namespaces

The fixture-entry and close markers are independent:

```text
MQL5/Files/SolTradeBot/one-shot-close-state-v1/
one_shot_close_fixture_entry_v1_<account-hash>_2607202601.csv

MQL5/Files/SolTradeBot/one-shot-close-state-v1/
one_shot_position_close_v1_<account-hash>_2607202601.csv
```

Their schemas are:

```text
SOLTRADE_CLOSE_FIXTURE_ENTRY_V1
SOLTRADE_ONE_SHOT_POSITION_CLOSE_V1
```

These paths do not overlap the prior entry-verification V1/V2 markers:

```text
one_shot_demo_<account-hash>_2607202601.csv
one_shot_demo_diagnostic_v2_<account-hash>_2607202601.csv
```

Preserve all prior markers. Do not delete, rename, edit, or copy them into the
new directory.

The unarmed branch returns before the account hash or any marker path is
constructed. It creates neither new marker, no `.tmp` file, and no
ExecutionEngine or PositionManager state file.

## 5. Unarmed connected-demo run

Before launching the script:

- confirm the connected terminal reports an easyMarkets demo account;
- keep the terminal Algo Trading button off;
- confirm the Trade tab is empty;
- confirm no new pending order exists;
- detach `SolTradeBot` from all charts; and
- open an exact `EURUSD` H1 chart.

Run `SolTradeOneShotPositionCloseVerification` once with exactly:

```text
ConfirmCreateOneShotDemoPosition = false
ConfirmCloseOneShotDemoPosition  = false
ApprovedDemoAccount              = 0
FixtureDirection                 = SOLTRADE_SIGNAL_BUY
ConfirmationTimeoutSeconds       = 15
```

Select **OK** once.

Both false inputs are evaluated before account approval, configuration,
journal initialization, market/risk state, marker paths, exposure scans, or
either approved engine call.

## 6. Exact expected unarmed output

The two SolTrade payloads must be:

```text
SOLTRADE_CLOSE_VERIFY_PREFLIGHT_STARTED | symbol=EURUSD | timeframe=PERIOD_H1 | account_mode=DEMO | create_armed=NO | close_armed=NO
SOLTRADE_CLOSE_VERIFY_NOT_ARMED | no position creation or close is authorised
```

MetaTrader may prepend its normal timestamp, script name, and chart context and
may append its ordinary script-removal message.

No other `SOLTRADE_CLOSE_VERIFY_*` event may appear. In particular, none of
these may appear:

```text
SOLTRADE_CLOSE_VERIFY_CREATE_ATTEMPT
SOLTRADE_CLOSE_VERIFY_FIXTURE_READY
SOLTRADE_CLOSE_VERIFY_OWNERSHIP_CONFIRMED
SOLTRADE_CLOSE_VERIFY_ATTEMPT
SOLTRADE_CLOSE_VERIFY_MATCHING_EXIT_TRANSACTION
SOLTRADE_CLOSE_VERIFY_DISABLED
```

## 7. Required zero-activity confirmation

After the script removes itself, confirm:

- Trade remains empty;
- History contains no new order or deal;
- no position was created, changed, or closed;
- no stop-loss was added, removed, or changed;
- the production EA remains detached;
- both new marker files are absent;
- both corresponding `.tmp` files are absent;
- no file was created under
  `MQL5/Files/SolTradeBot/one-shot-close-state-v1`;
- no new close-verification CSV row exists; and
- all prior V1/V2 entry-verification markers are unchanged.

The unarmed branch exits before `CSolTradeJournal::Initialise`, so even a
journal row would be unexpected.

Any broker activity or new state/journal file fails the preflight. Stop and
return the evidence; do not change either confirmation input to true.

## 8. Values reserved for later authorization

Record these only. Do not run them yet.

Later protected-fixture creation:

```text
ConfirmCreateOneShotDemoPosition = true
ConfirmCloseOneShotDemoPosition  = false
ApprovedDemoAccount              = <exact raw easyMarkets demo login>
FixtureDirection                 = SOLTRADE_SIGNAL_BUY
ConfirmationTimeoutSeconds       = 15
Required chart                   = EURUSD H1
Hard-coded magic                 = 2607202601
```

Later one-shot close:

```text
ConfirmCreateOneShotDemoPosition = false
ConfirmCloseOneShotDemoPosition  = true
ApprovedDemoAccount              = <the same exact raw easyMarkets demo login>
ConfirmationTimeoutSeconds       = 15
Required position                = exactly one protected EURUSD position
Required magic                   = 2607202601
```

The exact login must be copied digit for digit from the connected demo
account. Do not expose it in screenshots or public logs. No value in this
section is authorized for use yet.

## 9. Reserved close diagnostics

If a later instruction separately authorizes the close, Experts output, CSV,
and the permanent marker are designed to record:

```text
ownership:
  symbol, magic, position ticket, position identifier
  direction, full volume, initial stop attached/value
  unrelated_positions_ignored

OrderCheck:
  performed, boolean result, immediate GetLastError
  retcode, comment

OrderSend:
  performed, boolean result, immediate GetLastError
  requested close price, broker-reported price
  broker retcode, broker comment
  order ticket, deal ticket

matching exit transaction:
  actual close price
  adverse-positive slippage points
  realised profit/loss including commission, swap, and fee
  exit reason code and text
  proof that the broker position no longer exists
  retry_allowed=NO
```

The confirmation loop reads deal history only. It does not call
`ProcessClose`, `OrderCheck`, or `OrderSend` again. A rejection, timeout,
partial exit, or fully confirmed close leaves the permanent close marker in
place and permits no retry.

## 10. Evidence to return

Return:

- both MetaEditor summaries showing `0 errors, 0 warnings`;
- the two exact unarmed log payloads;
- Trade and History evidence showing no order, deal, position, or close;
- confirmation that both new markers and temporary markers are absent;
- confirmation that prior V1/V2 markers are unchanged; and
- confirmation that the production EA remained detached and Algo Trading
  remained off.

Do not include the raw demo login. Do not create a fixture position and do not
attempt a close.
