# Phase 5 Isolated Close Verifier V2 — Unarmed Preflight

This procedure installs and verifies the inert branch of the isolated V2
connected-demo entry-and-close verifier. It does not authorize a position
creation attempt or a close attempt.

The prior V1 marker with state `ENTRY_REJECTED_DISABLED` is permanent evidence.
Do not delete, rename, edit, replace, truncate, move, or overwrite it.

Phase 6 and backtesting remain prohibited.

## 1. V2 safety boundary

`SolTradeOneShotPositionCloseVerificationV2` is a new compiled script with a
new state namespace. It includes the reviewed common verifier implementation
but overrides its arming policy and every persistence identifier at compile
time.

An armed V2 path can exist only when both inputs are true:

```text
ConfirmCreateOneShotDemoPosition = true
ConfirmCloseOneShotDemoPosition  = true
```

One true and one false is rejected with `BOTH_CONFIRMATIONS_REQUIRED`. Both
false is the inert preflight used in this document.

If separately authorized later, the one V2 run is designed to:

1. call the approved Execution Engine once to create at most one EURUSD
   position with magic `2607202601` and an original attached stop;
2. require a matching entry deal, exactly one owned broker position, and a
   positive broker `POSITION_SL`;
3. rebuild that exact position through the approved Position Manager;
4. persist the V2 close marker and Position Manager claim;
5. call `PositionManager.ProcessClose()` once using the approved
   `EmergencyStop` close path; and
6. confirm the matching exit deal and prove the broker position is absent.

If entry creation is rejected or unconfirmed, the entry marker permanently
disables V2 and no close call occurs. If the close is rejected, unconfirmed, or
partial, its marker permanently disables the close path. There is no entry
retry and no close retry.

V2 retains all safety gates:

- connected demo account only;
- exact `ApprovedDemoAccount` login match;
- every real/unknown account rejected;
- exact EURUSD H1 chart;
- hard-coded magic `2607202601`;
- approved 0.25% risk sizing and safer broker-minimum volume;
- initial stop included in the entry request and verified on the position;
- unrelated manual/wrong-magic positions never managed;
- one synchronous entry gateway and one synchronous close gateway;
- full entry and close diagnostics; and
- no Phase 6 functionality.

Neither broker call is authorized by this preflight.

## 2. Exact files to copy

Choose **File > Open Data Folder** in the connected easyMarkets terminal.
Replace/copy these source files; do not copy repository `.ex5` binaries:

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
MQL5/Scripts/SolTradeOneShotPositionCloseVerificationV2.mq5
                                                    -> MQL5/Scripts/SolTradeOneShotPositionCloseVerificationV2.mq5
```

The non-V2 script is the common source included by the V2 wrapper. Do not run
it. Copying it does not read, alter, or remove its existing V1 marker.

## 3. Compile

1. Press **F4** in the connected terminal.
2. Open `MQL5/Experts/SolTradeBot.mq5`.
3. Press **F7** once and require:

   ```text
   Result: 0 errors, 0 warnings
   ```

4. Confirm `MQL5/Experts/SolTradeBot.ex5` has the current timestamp.
5. Open
   `MQL5/Scripts/SolTradeOneShotPositionCloseVerificationV2.mq5`.
6. Press **F7** once and require:

   ```text
   Result: 0 errors, 0 warnings
   ```

7. Confirm
   `MQL5/Scripts/SolTradeOneShotPositionCloseVerificationV2.ex5` exists with
   the current timestamp.
8. Refresh the MetaTrader Navigator if necessary.

Do not compile or run an old copied `.ex5`. Do not attach the production EA.

## 4. Marker isolation

Preserve the rejected V1 marker under:

```text
MQL5/Files/SolTradeBot/one-shot-close-state-v1/
one_shot_close_fixture_entry_v1_<account-hash>_2607202601.csv
```

Its schema remains:

```text
SOLTRADE_CLOSE_FIXTURE_ENTRY_V1
```

Its recorded state remains:

```text
ENTRY_REJECTED_DISABLED
```

V2 reserves entirely different paths:

```text
MQL5/Files/SolTradeBot/one-shot-close-state-v2/
one_shot_close_fixture_entry_v2_<account-hash>_2607202601.csv

MQL5/Files/SolTradeBot/one-shot-close-state-v2/
one_shot_position_close_v2_<account-hash>_2607202601.csv
```

V2 schemas are:

```text
SOLTRADE_CLOSE_FIXTURE_ENTRY_V2
SOLTRADE_ONE_SHOT_POSITION_CLOSE_V2
```

V2 risk state, if later armed, is also isolated under:

```text
MQL5/Files/SolTradeBot/one-shot-close-risk-v2/
```

The V2 source never opens or parses the V1 marker. The different directory,
filename prefixes, and schemas prevent the V1 rejection from blocking or
contaminating V2.

Before the unarmed run, record the V1 marker's filename, size, modification
time, and SHA-256 hash. Afterward, require all four to be unchanged. Do not use
a cleanup command on either directory.

## 5. Unarmed V2 preflight

Before launching:

- confirm the connected account is the easyMarkets demo account;
- keep Algo Trading off;
- confirm Trade is empty and no pending order exists;
- detach `SolTradeBot` from every chart;
- open exact EURUSD H1; and
- confirm the two V2 marker files and their `.tmp` files do not exist.

Run only `SolTradeOneShotPositionCloseVerificationV2` with:

```text
ConfirmCreateOneShotDemoPosition = false
ConfirmCloseOneShotDemoPosition  = false
ApprovedDemoAccount              = 0
FixtureDirection                 = SOLTRADE_SIGNAL_BUY
ConfirmationTimeoutSeconds       = 15
```

Select **OK** once.

The both-false branch exits before demo-login validation, configuration,
journal initialization, account hashing, marker path construction, risk or
execution state, broker exposure scans, or either engine call.

## 6. Exact expected output

The two V2 payloads must be:

```text
SOLTRADE_CLOSE_V2_PREFLIGHT_STARTED | symbol=EURUSD | timeframe=PERIOD_H1 | account_mode=DEMO | create_armed=NO | close_armed=NO
SOLTRADE_CLOSE_V2_NOT_ARMED | no position creation or close is authorised
```

MetaTrader may prepend its timestamp, script name, and chart context and append
its normal script-removal message.

No other `SOLTRADE_CLOSE_V2_*` or `SOLTRADE_CLOSE_VERIFY_*` event may appear.
In particular, none of these may appear:

```text
SOLTRADE_CLOSE_VERIFY_CREATE_ATTEMPT
SOLTRADE_CLOSE_VERIFY_FIXTURE_READY
SOLTRADE_CLOSE_VERIFY_OWNERSHIP_CONFIRMED
SOLTRADE_CLOSE_VERIFY_ATTEMPT
SOLTRADE_CLOSE_VERIFY_MATCHING_EXIT_TRANSACTION
SOLTRADE_CLOSE_VERIFY_DISABLED
```

## 7. Required zero-activity evidence

After the script removes itself, confirm:

- Trade remains empty;
- History contains no new order or deal;
- no position was created, changed, or closed;
- no stop-loss was created or changed;
- both V2 marker files remain absent;
- both V2 `.tmp` files remain absent;
- neither V2 state directory was created;
- no new SolTrade CSV row was written;
- the V1 `ENTRY_REJECTED_DISABLED` marker is byte-for-byte unchanged;
- all older entry-verification markers remain unchanged;
- the production EA remains detached; and
- Algo Trading remains off.

Any broker activity, V2 file, journal row, or V1 marker change fails this
preflight. Stop and return the evidence.

## 8. Values reserved for later authorization

Record only; do not enter or run these values yet:

```text
ConfirmCreateOneShotDemoPosition = true
ConfirmCloseOneShotDemoPosition  = true
ApprovedDemoAccount              = <exact raw easyMarkets demo login>
FixtureDirection                 = SOLTRADE_SIGNAL_BUY
ConfirmationTimeoutSeconds       = 15
Required chart                   = EURUSD H1
Hard-coded magic                 = 2607202601
```

Both confirmations will be required in the same later run. One true and one
false cannot create or close anything.

The raw login must be copied digit for digit from the connected demo account.
Keep it out of screenshots and public logs. This document does not authorize
those values.

## 9. Reserved diagnostics

If a later instruction separately authorizes V2, the entry and close records
are designed to contain:

```text
entry:
  OrderCheck boolean/error/retcode/comment
  OrderSend boolean/error/retcode/comment
  requested and actual entry price
  spread, slippage, volume, risk, margin and initial stop
  order ticket, deal ticket and matching entry transaction

ownership:
  exact EURUSD symbol, magic 2607202601
  position ticket/identifier/direction/full volume
  attached stop status/value
  unrelated positions ignored

close:
  OrderCheck boolean/error/retcode/comment
  OrderSend boolean/error/retcode/comment
  requested and actual close price
  slippage, order ticket, deal ticket
  broker retcode/comment
  realised P/L including commission, swap and fee
  exit reason and matching exit transaction
  proof that the owned broker position no longer exists
  retry_allowed=NO
```

History polling confirms transactions only and cannot submit another entry or
close.

## 10. Evidence to return now

Return:

- both connected MetaEditor summaries with `0 errors, 0 warnings`;
- the two exact V2 unarmed payloads;
- Trade/History evidence showing no activity;
- absence of every V2 marker, temporary, state, journal, order, deal, and
  position artifact; and
- the unchanged V1 marker filename, size, timestamp, SHA-256, schema, and
  `ENTRY_REJECTED_DISABLED` state.

Do not provide the raw demo login. Do not perform the armed V2 run.
