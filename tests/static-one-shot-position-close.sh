#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

manager_file="MQL5/Include/SolTrade/PositionManager.mqh"
engine_file="MQL5/Include/SolTrade/ExecutionEngine.mqh"
ea_file="MQL5/Experts/SolTradeBot.mq5"
script_file="MQL5/Scripts/SolTradeOneShotPositionCloseVerification.mq5"
procedure_file="tests/one-shot-position-close-preflight.md"

for required_file in \
  "$manager_file" \
  "$engine_file" \
  "$ea_file" \
  "$script_file" \
  "$procedure_file"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing one-shot close-verification file: $required_file" >&2
    exit 1
  fi
done

rg -q 'input bool ConfirmCreateOneShotDemoPosition[[:space:]]*=[[:space:]]*false;' \
  "$script_file"
rg -q 'input bool ConfirmCloseOneShotDemoPosition[[:space:]]*=[[:space:]]*false;' \
  "$script_file"
rg -q 'input long ApprovedDemoAccount[[:space:]]*=[[:space:]]*0;' \
  "$script_file"
rg -q '#define SOLTRADE_CLOSE_VERIFICATION_SYMBOL "EURUSD"' "$script_file"
rg -q '#define SOLTRADE_CLOSE_VERIFICATION_MAGIC[[:space:]]+2607202601' \
  "$script_file"
rg -q 'SOLTRADE_CLOSE_FIXTURE_ENTRY_V1' "$script_file"
rg -q 'SOLTRADE_ONE_SHOT_POSITION_CLOSE_V1' "$script_file"
rg -q 'one_shot_close_fixture_entry_v1_' "$script_file"
rg -q 'one_shot_position_close_v1_' "$script_file"

rg -q 'account_mode != ACCOUNT_TRADE_MODE_DEMO' "$script_file"
rg -q 'AccountInfoInteger\(ACCOUNT_LOGIN\) != ApprovedDemoAccount' \
  "$script_file"
rg -q 'Every non-demo account is unconditionally rejected' "$script_file"
rg -q 'Strategy Tester is not permitted' "$script_file"
rg -q 'config\.allow_live_trading[[:space:]]*=[[:space:]]*false' \
  "$script_file"
rg -q 'config\.enable_position_management[[:space:]]*=[[:space:]]*close_fixture' \
  "$script_file"
rg -q 'config\.emergency_stop[[:space:]]*=[[:space:]]*close_fixture' \
  "$script_file"

if [[ "$(rg -c 'execution_engine\.ProcessSignal\(' "$script_file")" -ne 1 ]]; then
  echo "Fixture creation must call the approved ExecutionEngine exactly once" >&2
  exit 1
fi

if [[ "$(rg -c 'position_manager\.ProcessClose\(' "$script_file")" -ne 1 ]]; then
  echo "Close verifier must call the approved PositionManager exactly once" >&2
  exit 1
fi

if rg -n '\b(OrderSend|OrderSendAsync|OrderCheck|OrderCalcMargin)\s*\(' \
  "$script_file"; then
  echo "One-shot close script bypasses an approved engine gateway" >&2
  exit 1
fi

if rg -n \
  '\b(CTrade|PositionClose|PositionOpen|TRADE_ACTION_SLTP|TRADE_ACTION_REMOVE|TRADE_ACTION_PENDING)\b' \
  "$script_file"; then
  echo "Unsupported close, modification, or pending-order API found" >&2
  exit 1
fi

rg -q 'SOLTRADE_CLOSE_EMERGENCY_STOP' "$script_file"
if rg -n 'SOLTRADE_EXIT_(LONG|SHORT)' "$script_file"; then
  echo "The close verifier must not fabricate a Donchian exit signal" >&2
  exit 1
fi

rg -q 'position_status\.magic_position_count != 1' "$script_file"
rg -q 'position_status\.position_magic_number !=' "$script_file"
rg -q 'position_status\.stop_attached' "$script_file"
rg -q 'CountUnrelatedPositions' "$script_file"
rg -q 'unrelated_positions_ignored' "$script_file"
rg -q 'ConfirmMatchingExitDealFromHistory' "$manager_file"
rg -q 'HistorySelect' "$manager_file"
rg -q 'DEAL_ENTRY_OUT' "$manager_file"
rg -q 'DEAL_POSITION_ID' "$manager_file"
rg -q 'POSITION_NOT_FULLY_CLOSED_NO_RETRY' "$script_file"

for diagnostic_field in \
  "order_check_performed" \
  "order_check_boolean_result" \
  "order_check_last_error" \
  "order_check_retcode" \
  "order_check_comment" \
  "order_send_performed" \
  "order_send_boolean_result" \
  "order_send_last_error" \
  "requested_close_price" \
  "actual_close_price" \
  "slippage_points" \
  "broker_return_code" \
  "broker_comment" \
  "order_ticket" \
  "deal_ticket" \
  "realised_profit_loss" \
  "exit_reason" \
  "retry_allowed=NO"; do
  rg -q "$diagnostic_field" "$script_file"
done

unarmed_line="$(
  rg -n 'if\(!ConfirmCreateOneShotDemoPosition &&' "$script_file" |
    cut -d: -f1
)"
action_line="$(
  rg -n 'RunArmedVerificationAction\(' "$script_file" |
    tail -3 |
    head -1 |
    cut -d: -f1
)"
if [[ -z "$unarmed_line" || -z "$action_line" ||
      "$unarmed_line" -ge "$action_line" ]]; then
  echo "Unarmed close verifier must exit before an armed action is invoked" >&2
  exit 1
fi

create_marker_line="$(
  rg -n 'if\(!WriteFixtureEntryMarker\(marker_path,' "$script_file" |
    head -1 |
    cut -d: -f1
)"
create_process_line="$(
  rg -n 'execution_engine\.ProcessSignal\(' "$script_file" |
    cut -d: -f1
)"
close_marker_line="$(
  rg -n 'if\(!WritePositionCloseMarker\(marker_path,' "$script_file" |
    head -1 |
    cut -d: -f1
)"
close_process_line="$(
  rg -n 'position_manager\.ProcessClose\(' "$script_file" |
    cut -d: -f1
)"
if [[ -z "$create_marker_line" || -z "$create_process_line" ||
      "$create_marker_line" -ge "$create_process_line" ]]; then
  echo "Fixture marker must precede the sole ExecutionEngine call" >&2
  exit 1
fi
if [[ -z "$close_marker_line" || -z "$close_process_line" ||
      "$close_marker_line" -ge "$close_process_line" ]]; then
  echo "Close marker must precede the sole PositionManager call" >&2
  exit 1
fi

rg -q 'SOLTRADE_CLOSE_VERIFY_PREFLIGHT_STARTED' "$script_file"
rg -q 'SOLTRADE_CLOSE_VERIFY_NOT_ARMED' "$script_file"
rg -q 'ConfirmCreateOneShotDemoPosition = false' "$procedure_file"
rg -q 'ConfirmCloseOneShotDemoPosition  = false' "$procedure_file"
rg -q 'Do not create a fixture position and do not' "$procedure_file"
rg -q 'Phase 6' "$procedure_file"

if rg -n 'ONE_SHOT_CLOSE_FIXTURE_CREATION' "$ea_file"; then
  echo "Test-only fixture override leaked into the production EA" >&2
  exit 1
fi

tests/static-phase5.sh

echo "One-shot Phase 5 position-close static safety checks passed."
