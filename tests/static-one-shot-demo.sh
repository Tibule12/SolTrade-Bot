#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

engine_file="MQL5/Include/SolTrade/ExecutionEngine.mqh"
ea_file="MQL5/Experts/SolTradeBot.mq5"
script_file="MQL5/Scripts/SolTradeOneShotDemoVerification.mq5"
procedure_file="tests/one-shot-connected-demo-procedure.md"

for required_file in \
  "$engine_file" \
  "$ea_file" \
  "$script_file" \
  "$procedure_file"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing one-shot verification file: $required_file" >&2
    exit 1
  fi
done

rg -q 'input bool ConfirmOneShotDemoOrder[[:space:]]*=[[:space:]]*false;' \
  "$script_file"
rg -q 'input long ApprovedDemoAccount[[:space:]]*=[[:space:]]*0;' \
  "$script_file"
rg -q '#define SOLTRADE_VERIFICATION_SYMBOL "EURUSD"' "$script_file"
rg -q 'SOLTRADE_ONE_SHOT_PREFLIGHT_STARTED' "$script_file"
rg -q 'SOLTRADE_ONE_SHOT_NOT_ARMED' "$script_file"
rg -q 'account_mode != ACCOUNT_TRADE_MODE_DEMO' "$script_file"
rg -q 'AccountInfoInteger\(ACCOUNT_LOGIN\) != ApprovedDemoAccount' \
  "$script_file"
rg -q 'every non-demo account is unconditionally rejected' "$script_file"
rg -q 'Strategy Tester is not permitted' "$script_file"
rg -q 'config\.allow_live_trading[[:space:]]*=[[:space:]]*false' \
  "$script_file"
rg -q 'config\.risk_per_trade_percent[[:space:]]*=[[:space:]]*0\.25' \
  "$script_file"
rg -q 'SolTradeEvaluateCurrentCompletedHistory' "$script_file"
rg -q 'SolTradeApplySaferMinimumVolume' "$engine_file"
rg -q 'ConfirmMatchingEntryDealFromHistory' "$engine_file"
rg -q 'MATCHING_TRADE_TRANSACTION_CONFIRMED' "$engine_file"
rg -q 'DEAL_ENTRY_IN' "$engine_file"
rg -q 'SolTradeOrderCheckAccepted' "$engine_file"
rg -q 'return \(boolean_result && check_retcode == 0\);' "$engine_file"
rg -q 'const bool check_succeeded = OrderCheck\(request, check\);' \
  "$engine_file"
rg -q 'const int check_error = GetLastError\(\);' "$engine_file"
rg -q 'retry_allowed=NO' "$script_file"
rg -q 'ONE_SHOT_VERIFICATION_DISABLED' "$script_file"
rg -q 'SOLTRADE_ONE_SHOT_DEMO_DIAGNOSTIC_V2' "$script_file"
rg -q 'one_shot_demo_5852DBBA_2607202601\.csv' "$procedure_file"
rg -q 'one_shot_demo_diagnostic_v2_5852DBBA_2607202601\.csv' \
  "$procedure_file"
rg -q 'ConfirmOneShotDemoOrder      = false' "$procedure_file"
rg -q 'ApprovedDemoAccount          = 0' "$procedure_file"

for diagnostic_field in \
  "order_check_boolean_result" \
  "order_check_last_error" \
  "order_check_retcode" \
  "order_check_comment" \
  "requested_action" \
  "requested_order_type" \
  "requested_filling_mode" \
  "volume" \
  "requested_price" \
  "stop_loss" \
  "requested_deviation_points" \
  "requested_symbol" \
  "requested_magic_number" \
  "broker_volume_min" \
  "broker_volume_step" \
  "broker_stops_level_points" \
  "broker_supported_filling_mode"; do
  rg -q "$diagnostic_field" "$script_file"
  rg -q "$diagnostic_field" MQL5/Include/SolTrade/TradeJournal.mqh
done

if rg -n 'check\.retcode != TRADE_RETCODE_DONE' "$engine_file"; then
  echo "OrderCheck success must not require the OrderSend DONE retcode" >&2
  exit 1
fi

if [[ "$(rg -c 'execution_engine\.ProcessSignal\(' "$script_file")" -ne 1 ]]; then
  echo "One-shot script must call the approved engine exactly once" >&2
  exit 1
fi

unarmed_line="$(
  rg -n 'if\(!ConfirmOneShotDemoOrder\)' "$script_file" |
    cut -d: -f1
)"
journal_line="$(
  rg -n 'CSolTradeJournal journal;' "$script_file" |
    cut -d: -f1
)"
marker_path_line="$(
  rg -n '^[[:space:]]+const string marker_path[[:space:]]*=$' \
    "$script_file" |
    cut -d: -f1
)"
if [[ -z "$unarmed_line" || -z "$journal_line" ||
      -z "$marker_path_line" ||
      "$unarmed_line" -ge "$journal_line" ||
      "$unarmed_line" -ge "$marker_path_line" ]]; then
  echo "Unarmed verifier must exit before journal or marker initialisation" >&2
  exit 1
fi

if rg -n '\b(OrderSend|OrderSendAsync|OrderCheck|OrderCalcMargin)\s*\(' \
  "$script_file"; then
  echo "One-shot script bypasses the approved execution gateway" >&2
  exit 1
fi

if rg -n \
  '\b(PositionClose|PositionOpen|TRADE_ACTION_SLTP|TRADE_ACTION_REMOVE)\b' \
  "$script_file" "$engine_file" "$ea_file"; then
  echo "Position closing/modification code exists before Phase 5" >&2
  exit 1
fi

marker_line="$(
  rg -n 'if\(!WriteOneShotMarker\(marker_path,' "$script_file" |
    head -1 |
    cut -d: -f1
)"
process_line="$(
  rg -n 'execution_engine\.ProcessSignal\(' "$script_file" |
    cut -d: -f1
)"
if [[ -z "$marker_line" || -z "$process_line" ||
      "$marker_line" -ge "$process_line" ]]; then
  echo "Persistent one-shot disable marker must precede the engine call" >&2
  exit 1
fi

if rg -n 'ONE_SHOT_DEMO_EXECUTION_VERIFICATION' "$ea_file"; then
  echo "Test-only direction override leaked into the production EA" >&2
  exit 1
fi

rg -q 'g_risk_status,[[:space:]]*$' "$ea_file"
rg -q '^[[:space:]]+false,[[:space:]]*$' "$ea_file"
rg -q 'Phase 5 contains no stop/position modification path' \
  tests/account-mode-cases.md

tests/static-phase4.sh

echo "One-shot connected-demo static safety checks passed."
