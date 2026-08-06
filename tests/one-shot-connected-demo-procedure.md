# Diagnostic V2 Connected-Demo Procedure — Unarmed Verification Only

This procedure stops after proving that Diagnostic V2 is installed, compiled,
and inert with `ConfirmOneShotDemoOrder=false`. It does not authorize an armed
order attempt. Keep the production EA detached and do not set the confirmation
input to `true`.

## 1. Safety boundary

The Diagnostic V2 verifier:

- is a separate script and does not add a strategy bypass to the production EA;
- defaults to `ConfirmOneShotDemoOrder=false`;
- permits an armed path only on a connected demo account whose raw login
  exactly equals `ApprovedDemoAccount`;
- rejects Strategy Tester and every non-demo account;
- is hard-coded to exact symbol `EURUSD`;
- calls the approved Phase 4 ExecutionEngine at most once;
- can reach at most one synchronous `OrderSend`;
- persists its attempt marker before that engine call;
- never retries, closes, or modifies a position;
- contains no Phase 5 position-management functionality.

For this unarmed procedure, turn the terminal's Algo Trading button off. The
script exits before checking trading permissions or calling any trading API.

## 2. Exact source files to copy

In the connected terminal select **File → Open Data Folder**. Copy the following
repository files to the exact paths below. Replace the connected-terminal
source copies; do not copy a repository `.ex5` binary.

```text
Repository source                                      MetaTrader data directory
MQL5/Experts/SolTradeBot.mq5                         -> MQL5/Experts/SolTradeBot.mq5
MQL5/Include/SolTrade/AccountGuard.mqh               -> MQL5/Include/SolTrade/AccountGuard.mqh
MQL5/Include/SolTrade/Config.mqh                     -> MQL5/Include/SolTrade/Config.mqh
MQL5/Include/SolTrade/Dashboard.mqh                  -> MQL5/Include/SolTrade/Dashboard.mqh
MQL5/Include/SolTrade/ExecutionEngine.mqh            -> MQL5/Include/SolTrade/ExecutionEngine.mqh
MQL5/Include/SolTrade/MarketData.mqh                 -> MQL5/Include/SolTrade/MarketData.mqh
MQL5/Include/SolTrade/RiskEngine.mqh                 -> MQL5/Include/SolTrade/RiskEngine.mqh
MQL5/Include/SolTrade/StrategyBreakout.mqh           -> MQL5/Include/SolTrade/StrategyBreakout.mqh
MQL5/Include/SolTrade/TradeJournal.mqh               -> MQL5/Include/SolTrade/TradeJournal.mqh
MQL5/Scripts/SolTradeOneShotDemoVerification.mq5     -> MQL5/Scripts/SolTradeOneShotDemoVerification.mq5
```

Copying the complete `SolTrade` include set prevents an older dependency from
being combined with the updated `ExecutionEngine.mqh` and `TradeJournal.mqh`.
No Phase 5 file should be present.

## 3. Exact MetaEditor compilation

1. From the connected terminal press **F4** to open its MetaEditor.
2. In MetaEditor open
   `MQL5/Experts/SolTradeBot.mq5`.
3. Press **F7** once and wait for compilation to finish.
4. Require this Toolbox → Errors summary:

   ```text
   0 errors, 0 warnings
   ```

5. Confirm `MQL5/Experts/SolTradeBot.ex5` exists and has the new compilation
   timestamp.
6. Open
   `MQL5/Scripts/SolTradeOneShotDemoVerification.mq5`.
7. Press **F7** once and wait for compilation to finish.
8. Require this Toolbox → Errors summary:

   ```text
   0 errors, 0 warnings
   ```

9. Confirm
   `MQL5/Scripts/SolTradeOneShotDemoVerification.ex5` exists and has the new
   compilation timestamp.
10. Return to MetaTrader and select **Navigator → Refresh** if the compiled
    script is not visible.

Do not attach `SolTradeBot` to any chart.

## 4. V1 and V2 marker isolation

For the previously verified account hash and magic number, the existing V1
marker is:

```text
MQL5/Files/SolTradeBot/state/
one_shot_demo_5852DBBA_2607202601.csv
```

Its preserved preflight SHA-256 is:

```text
b744a91fb6aaaae0f57838fd95385555eafe0c961f1fcb303757de26a2832cbd
```

The V2 marker reserved for the same account hash and magic number is:

```text
MQL5/Files/SolTradeBot/state/
one_shot_demo_diagnostic_v2_5852DBBA_2607202601.csv
```

Generic forms:

```text
V1: one_shot_demo_<account-hash>_<magic>.csv
V2: one_shot_demo_diagnostic_v2_<account-hash>_<magic>.csv
```

Preserve the V1 marker. Do not rename, edit, move, or delete it.

The previous rejected marker cannot block or contaminate V2:

- V2 constructs and checks only the exact
  `one_shot_demo_diagnostic_v2_<account-hash>_<magic>.csv` path;
- it never opens or parses the V1 marker;
- the V2 file carries schema `SOLTRADE_ONE_SHOT_DEMO_DIAGNOSTIC_V2`;
- the unarmed branch exits before either marker path is constructed and before
  the risk or execution engines are initialized.

Before and after the unarmed run, `sha256sum` of the V1 marker must match the
value above. Confirm the V2 marker does not exist. Do not create an empty V2
marker manually.

## 5. Unarmed connected-demo preflight

1. Keep the Algo Trading button **off**.
2. Confirm `SolTradeBot` is detached from every chart.
3. Open an exact `EURUSD` chart and set it to `H1`.
4. Confirm the connected account is the intended easyMarkets demo account.
5. Record the current Trade and History state so new activity can be detected.
6. From Navigator → Scripts, launch
   `SolTradeOneShotDemoVerification` on that EURUSD H1 chart.
7. Enter exactly:

   ```text
   ConfirmOneShotDemoOrder      = false
   ApprovedDemoAccount          = 0
   VerificationDirection       = SOLTRADE_SIGNAL_BUY
   MagicNumber                 = 2607202601
   ConfirmationTimeoutSeconds  = 15
   ```

8. Select **OK** once.

The first input is evaluated before account approval, market-data
initialization, journal initialization, marker creation, or the ExecutionEngine
call. With it set to `false`, no order path is reachable.

## 6. Exact expected unarmed output

The SolTrade-owned payloads in Experts/Journal must be exactly:

```text
SOLTRADE_ONE_SHOT_PREFLIGHT_STARTED | symbol=EURUSD | account_mode=DEMO | armed=NO
SOLTRADE_ONE_SHOT_NOT_ARMED | ConfirmOneShotDemoOrder must be true
```

MetaTrader may prepend its normal timestamp, program name, and chart context,
and may append its standard script-removal message. There must be no other
`SOLTRADE_ONE_SHOT_*` event for this run. In particular, none of these may
appear:

```text
ONE_SHOT_ATTEMPT_CLAIMED
SOLTRADE_ONE_SHOT_ATTEMPT
ORDER_CHECK_REJECTED_NO_RETRY
ORDER_REQUEST_ACCEPTED_AWAITING_TRANSACTION
ORDER_REJECTED_NO_RETRY
SOLTRADE_ONE_SHOT_DISABLED
```

## 7. Required zero-activity confirmation

After the script removes itself, confirm all of the following:

- no new order was created;
- no new deal was created;
- no new position was created;
- no existing position was changed;
- the production EA is still detached;
- the V1 marker is byte-for-byte unchanged;
- no V2 marker exists;
- no `one_shot_demo_diagnostic_v2_*.tmp` file exists;
- no V2 completion state such as `REJECTED_DISABLED`,
  `ACCEPTED_UNCONFIRMED_DISABLED`, or
  `MATCHING_TRANSACTION_CONFIRMED_DISABLED` exists;
- no new Diagnostic V2 CSV execution row exists.

The unarmed branch returns before `CSolTradeJournal::Initialise`, so it creates
neither a journal row nor an attempt/completion marker.

Any new order, deal, position, state file, CSV row, or attempt event is a failed
preflight. Stop and return the evidence; do not try an armed run.

## 8. Inputs reserved for a later separately authorized attempt

Do not enter these values during this unarmed procedure. Record them only:

```text
ConfirmOneShotDemoOrder      = true
ApprovedDemoAccount          = <exact raw easyMarkets demo login digits>
VerificationDirection       = SOLTRADE_SIGNAL_BUY
MagicNumber                 = 2607202601
ConfirmationTimeoutSeconds  = 15
Required chart              = exact EURUSD, H1
```

`ApprovedDemoAccount` has no safe generic number: it must be copied digit for
digit from the connected demo account's Login field. Keep that raw login out of
screenshots and exported public logs. No armed use of these reserved values is
authorized by this document.

## 9. Diagnostic record reserved for the later attempt

If a later instruction separately authorizes the single attempt, the combined
Experts and CSV record is designed to contain:

```text
OrderCheck:
  order_check_performed
  order_check_boolean_result
  order_check_last_error
  order_check_retcode
  order_check_comment

Exact request:
  requested_action
  requested_order_type
  requested_filling_mode
  requested_volume
  requested_price
  requested_stop_loss
  requested_deviation_points
  requested_symbol
  requested_magic_number

Broker symbol constraints:
  broker_volume_min
  broker_volume_step
  broker_stops_level_points
  broker_supported_filling_mode

OrderSend and execution:
  broker_attempted
  broker_accepted
  broker_return_code
  broker_comment
  terminal_error
  broker_reported_price
  order_ticket
  deal_ticket
  fill_confirmed
  actual fill_price
  spread_points
  slippage_points
  volume
  stop_loss
  risk_amount
  margin_required
  retry_allowed=NO
```

On the OrderSend path, `terminal_error` is the `GetLastError()` value captured
immediately after the single synchronous `OrderSend`; `broker_return_code`,
`broker_comment`, `broker_reported_price`, `order_ticket`, and `deal_ticket`
come from `MqlTradeResult`. A matching entry deal is required before
`fill_confirmed=YES` and `actual fill_price` are recorded.

There is no loop or automatic retry. The one-shot marker disables the V2
verifier after the first accepted or rejected attempt. No code in Phase 4 can
close or modify a resulting position.

## 10. Evidence to return from this unarmed procedure

Return only:

- both MetaEditor summaries showing `0 errors, 0 warnings`;
- the two exact unarmed SolTrade log payloads;
- Trade/History evidence showing no new order, deal, or position;
- confirmation that the V1 marker is unchanged;
- confirmation that the V2 marker and V2 temporary marker do not exist;
- confirmation that the production EA remained detached and Algo Trading
  remained off.

Do not include the raw demo login. Do not perform the reserved armed attempt.
