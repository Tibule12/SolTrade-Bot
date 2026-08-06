#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

base_file="MQL5/Scripts/SolTradeOneShotPositionCloseVerification.mq5"
v2_file="MQL5/Scripts/SolTradeOneShotPositionCloseVerificationV2.mq5"
procedure_file="tests/one-shot-position-close-v2-preflight.md"

for required_file in "$base_file" "$v2_file" "$procedure_file"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing isolated V2 verifier file: $required_file" >&2
    exit 1
  fi
done

rg -q 'SOLTRADE_CLOSE_VERIFIER_V2_CONFIGURATION' "$v2_file"
rg -q 'SOLTRADE_CLOSE_VERIFIER_REQUIRE_BOTH_CONFIRMATIONS' "$v2_file"
rg -q 'SolTradeOneShotPositionCloseVerification\.mq5' "$v2_file"
rg -q '#define SOLTRADE_V2_RISK_DIRECTORY' "$v2_file"
rg -q '#define SOLTRADE_V2_STATE_DIRECTORY' "$v2_file"
rg -q '#define SOLTRADE_V2_FIXTURE_MARKER_FILENAME_PREFIX' "$v2_file"
rg -q '#define SOLTRADE_V2_CLOSE_MARKER_FILENAME_PREFIX' "$v2_file"
rg -q '#define SOLTRADE_V2_FIXTURE_MARKER_SCHEMA' "$v2_file"
rg -q '#define SOLTRADE_V2_CLOSE_MARKER_SCHEMA' "$v2_file"
rg -q '#define SOLTRADE_V2_PREFLIGHT_STARTED_EVENT' "$v2_file"
rg -q '#define SOLTRADE_V2_NOT_ARMED_EVENT' "$v2_file"
rg -q 'one-shot-close-risk-v2' "$v2_file"
rg -q 'one-shot-close-state-v2' "$v2_file"
rg -q 'one_shot_close_fixture_entry_v2_' "$v2_file"
rg -q 'one_shot_position_close_v2_' "$v2_file"
rg -q 'SOLTRADE_CLOSE_FIXTURE_ENTRY_V2' "$v2_file"
rg -q 'SOLTRADE_ONE_SHOT_POSITION_CLOSE_V2' "$v2_file"
rg -q 'SOLTRADE_CLOSE_V2_PREFLIGHT_STARTED' "$v2_file"
rg -q 'SOLTRADE_CLOSE_V2_NOT_ARMED' "$v2_file"

if rg -n \
  '^#define SOLTRADE_(CLOSE_VERIFICATION_(RISK|STATE)_DIRECTORY|FIXTURE_MARKER_FILENAME_PREFIX|CLOSE_MARKER_FILENAME_PREFIX|FIXTURE_MARKER_SCHEMA|CLOSE_MARKER_SCHEMA|CLOSE_PREFLIGHT_STARTED_EVENT|CLOSE_NOT_ARMED_EVENT)([[:space:]]|$)' \
  "$v2_file"; then
  echo "V2 wrapper must not redefine a common operational macro" >&2
  exit 1
fi

if rg -n \
  'one-shot-close-(risk|state)-v1|fixture_entry_v1|position_close_v1|_V1' \
  "$v2_file"; then
  echo "V2 wrapper references a V1 persistence identifier" >&2
  exit 1
fi

rg -q '#ifdef SOLTRADE_CLOSE_VERIFIER_V2_CONFIGURATION' "$base_file"
rg -q 'SOLTRADE_SELECTED_RISK_DIRECTORY' "$base_file"
rg -q 'SOLTRADE_SELECTED_STATE_DIRECTORY' "$base_file"
rg -q 'SOLTRADE_SELECTED_FIXTURE_MARKER_FILENAME_PREFIX' "$base_file"
rg -q 'SOLTRADE_SELECTED_CLOSE_MARKER_FILENAME_PREFIX' "$base_file"
rg -q 'SOLTRADE_SELECTED_FIXTURE_MARKER_SCHEMA' "$base_file"
rg -q 'SOLTRADE_SELECTED_CLOSE_MARKER_SCHEMA' "$base_file"
rg -q 'SOLTRADE_SELECTED_PREFLIGHT_STARTED_EVENT' "$base_file"
rg -q 'SOLTRADE_SELECTED_NOT_ARMED_EVENT' "$base_file"

for operational_macro in \
  "SOLTRADE_CLOSE_VERIFICATION_RISK_DIRECTORY" \
  "SOLTRADE_CLOSE_VERIFICATION_STATE_DIRECTORY" \
  "SOLTRADE_FIXTURE_MARKER_FILENAME_PREFIX" \
  "SOLTRADE_CLOSE_MARKER_FILENAME_PREFIX" \
  "SOLTRADE_FIXTURE_MARKER_SCHEMA" \
  "SOLTRADE_CLOSE_MARKER_SCHEMA" \
  "SOLTRADE_CLOSE_PREFLIGHT_STARTED_EVENT" \
  "SOLTRADE_CLOSE_NOT_ARMED_EVENT"; do
  if [[ "$(rg -c "^#define ${operational_macro}([[:space:]]|$)" "$base_file")" -ne 1 ]]; then
    echo "Common source must define ${operational_macro} exactly once" >&2
    exit 1
  fi
done

rg -q 'if\(!ConfirmCreateOneShotDemoPosition &&' "$base_file"
rg -q 'if\(!ConfirmCreateOneShotDemoPosition ||' "$base_file"
rg -q 'reason_code=BOTH_CONFIRMATIONS_REQUIRED' "$base_file"
rg -q 'RunArmedVerificationAction\(true, false\)' "$base_file"
rg -q 'RunArmedVerificationAction\(false, true\)' "$base_file"
rg -q 'if\(creation_result != 0\)' "$base_file"

if [[ "$(rg -c 'execution_engine\.ProcessSignal\(' "$base_file")" -ne 1 ]]; then
  echo "V2 common source must contain exactly one fixture-entry engine call" >&2
  exit 1
fi

if [[ "$(rg -c 'position_manager\.ProcessClose\(' "$base_file")" -ne 1 ]]; then
  echo "V2 common source must contain exactly one position-close engine call" >&2
  exit 1
fi

if rg -n '\b(OrderSend|OrderSendAsync|OrderCheck|OrderCalcMargin)\s*\(' \
  "$base_file" "$v2_file"; then
  echo "V2 script bypasses the approved entry or close gateway" >&2
  exit 1
fi

if rg -n \
  '\b(CTrade|PositionClose|PositionOpen|TRADE_ACTION_SLTP|TRADE_ACTION_REMOVE|TRADE_ACTION_PENDING)\b' \
  "$base_file" "$v2_file"; then
  echo "Unsupported V2 close, modification, or pending-order API found" >&2
  exit 1
fi

rg -q 'account_mode != ACCOUNT_TRADE_MODE_DEMO' "$base_file"
rg -q 'AccountInfoInteger\(ACCOUNT_LOGIN\) != ApprovedDemoAccount' "$base_file"
rg -q '#define SOLTRADE_CLOSE_VERIFICATION_SYMBOL "EURUSD"' "$base_file"
rg -q '#define SOLTRADE_CLOSE_VERIFICATION_MAGIC[[:space:]]+2607202601' \
  "$base_file"
rg -q 'position_status\.magic_position_count != 1' "$base_file"
rg -q 'position_status\.stop_attached' "$base_file"
rg -q 'CountUnrelatedPositions' "$base_file"
rg -q 'retry_allowed=NO' "$base_file"
rg -q 'SOLTRADE_CLOSE_EMERGENCY_STOP' "$base_file"

if rg -n 'SOLTRADE_EXIT_(LONG|SHORT)' "$base_file" "$v2_file"; then
  echo "V2 close path must not fabricate a Donchian exit" >&2
  exit 1
fi

unarmed_line="$(
  rg -n 'if\(!ConfirmCreateOneShotDemoPosition &&' "$base_file" |
    cut -d: -f1
)"
envelope_line="$(
  rg -n 'if\(!ValidateConnectedDemoEnvelope' "$base_file" |
    cut -d: -f1
)"
if [[ -z "$unarmed_line" || -z "$envelope_line" ||
      "$unarmed_line" -ge "$envelope_line" ]]; then
  echo "V2 unarmed branch must exit before account and state preparation" >&2
  exit 1
fi

rg -q 'WriteFixtureEntryMarker' "$base_file"
rg -q 'WritePositionCloseMarker' "$base_file"
rg -q 'ConfirmMatchingEntryDealFromHistory' "$base_file"
rg -q 'ConfirmMatchingExitDealFromHistory' "$base_file"
rg -q 'POSITION_NOT_FULLY_CLOSED_NO_RETRY' "$base_file"

for diagnostic_field in \
  "order_check_boolean_result" \
  "order_check_last_error" \
  "order_check_retcode" \
  "order_check_comment" \
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
  "exit_reason"; do
  rg -q "$diagnostic_field" "$base_file"
done

rg -q 'ENTRY_REJECTED_DISABLED' "$procedure_file"
rg -q 'Do not delete, rename, edit, replace, truncate, move, or overwrite' \
  "$procedure_file"
rg -q 'ConfirmCreateOneShotDemoPosition = false' "$procedure_file"
rg -q 'ConfirmCloseOneShotDemoPosition  = false' "$procedure_file"
rg -q 'Do not perform the armed V2 run' "$procedure_file"
rg -q 'Phase 6 and backtesting remain prohibited' "$procedure_file"

tests/static-one-shot-position-close.sh

echo "Isolated V2 one-shot entry-and-close static safety checks passed."
