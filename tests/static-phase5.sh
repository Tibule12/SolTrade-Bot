#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

required_files=(
  "MQL5/Include/SolTrade/PositionManager.mqh"
  "MQL5/Scripts/SolTradePositionManagerTests.mq5"
  "docs/position-management.md"
  "tests/phase5-connected-demo-checklist.md"
  "tests/verify-position-manager-fixtures.sh"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required Phase 5 file: $required_file" >&2
    exit 1
  fi
done

manager_file="MQL5/Include/SolTrade/PositionManager.mqh"
test_file="MQL5/Scripts/SolTradePositionManagerTests.mq5"
ea_file="MQL5/Experts/SolTradeBot.mq5"

rg -q 'input bool EnablePositionManagement[[:space:]]*=[[:space:]]*false;' \
  "$ea_file"
rg -q 'g_config\.enable_position_management[[:space:]]*=[[:space:]]*EnablePositionManagement' \
  "$ea_file"
rg -q 'input bool AllowLiveTrading[[:space:]]*=[[:space:]]*false;' \
  "$ea_file"
rg -q 'AllowLiveTrading must remain false through Phase 6' \
  MQL5/Include/SolTrade/Config.mqh
rg -q 'REAL_ACCOUNT_POSITION_MANAGEMENT_FORBIDDEN' "$manager_file"
rg -q 'POSITION_DEMO_ACCOUNT_NOT_APPROVED' "$manager_file"
rg -q 'POSITION_MANAGEMENT_DISABLED' "$manager_file"

if [[ "$(rg -c '\bOrderSend\(' MQL5/Include/SolTrade/ExecutionEngine.mqh)" -ne 1 ]]; then
  echo "Entry ExecutionEngine must retain exactly one OrderSend gateway" >&2
  exit 1
fi

if [[ "$(rg -c '\bOrderSend\(' "$manager_file")" -ne 1 ]]; then
  echo "PositionManager must have exactly one synchronous close gateway" >&2
  exit 1
fi

order_send_count="$(
  rg -o '\bOrderSend\(' MQL5/Include/SolTrade/*.mqh |
    wc -l
)"
if [[ "$order_send_count" -ne 2 ]]; then
  echo "Only the approved entry and close gateways may call OrderSend" >&2
  exit 1
fi

if rg -n \
  '\b(OrderSendAsync|CTrade|PositionOpen|PositionClose)\s*\(' \
  MQL5; then
  echo "Unsupported asynchronous or convenience trading API found" >&2
  exit 1
fi

if rg -n \
  '\b(TRADE_ACTION_SLTP|TRADE_ACTION_REMOVE|TRADE_ACTION_PENDING)\b' \
  MQL5; then
  echo "Unsupported stop modification, removal, or pending-order action found" >&2
  exit 1
fi

if rg -n '\b(OrderSend|OrderCheck)\s*\(' "$test_file"; then
  echo "Deterministic Phase 5 tests must never call the broker" >&2
  exit 1
fi

rg -q 'position\.magic_number != config\.magic_number' "$manager_file"
rg -q 'PositionGetInteger\(POSITION_MAGIC\)' "$manager_file"
rg -q 'request\.position[[:space:]]*=[[:space:]]*plan\.position_ticket' \
  "$manager_file"
rg -q 'request\.magic[[:space:]]*=[[:space:]]*plan\.position_magic_number' \
  "$manager_file"
rg -q 'BUY_REQUIRES_EXIT_LONG' "$manager_file"
rg -q 'SELL_REQUIRES_EXIT_SHORT' "$manager_file"
rg -q 'SOLTRADE_CLOSE_EMERGENCY_DRAWDOWN' "$manager_file"
rg -q 'SOLTRADE_CLOSE_EMERGENCY_STOP' "$manager_file"
rg -q 'POSITION_SL' "$manager_file"
rg -q 'SOLTRADE_STOP_LOSS_MISSING' "$manager_file"

rg -q 'SOLTRADE_POSITION_STATE_SCHEMA' "$manager_file"
rg -q 'SolTradeExecutionStateChecksum' "$manager_file"
rg -q 'FileMove\(temporary_path, 0, m_state_path, FILE_REWRITE\)' \
  "$manager_file"
rg -q 'DUPLICATE_POSITION_CLOSE_ATTEMPT' "$manager_file"
rg -q 'POSITION_CLOSE_ORDER_CHECK_REJECTED_NO_RETRY' "$manager_file"
rg -q 'POSITION_CLOSE_REJECTED_NO_RETRY' "$manager_file"
rg -q 'retry_allowed[[:space:]]*=[[:space:]]*false' "$manager_file"
rg -q 'TRADE_TRANSACTION_DEAL_ADD' "$manager_file"
rg -q 'DEAL_ENTRY_OUT' "$manager_file"
rg -q 'POSITION_EXIT_TRANSACTION_CONFIRMED' "$manager_file"

claim_line="$(
  rg -n '!ClaimCloseAttempt\(plan, state_reason\)' "$manager_file" |
    cut -d: -f1
)"
check_line="$(
  rg -n 'const bool check_succeeded = OrderCheck' "$manager_file" |
    cut -d: -f1
)"
send_line="$(
  rg -n 'const bool send_succeeded = OrderSend' "$manager_file" |
    cut -d: -f1
)"
if [[ -z "$claim_line" || -z "$check_line" || -z "$send_line" ||
      "$claim_line" -ge "$check_line" || "$check_line" -ge "$send_line" ]]; then
  echo "Persistent close claim must precede OrderCheck and the sole OrderSend" >&2
  exit 1
fi

rg -q 'LogPositionManagement' MQL5/Include/SolTrade/TradeJournal.mqh
for journal_value in \
  "requested_close_price" \
  "actual_close_price" \
  "slippage_points" \
  "broker_return_code" \
  "order_ticket" \
  "deal_ticket" \
  "exit_reason"; do
  rg -q "$journal_value" MQL5/Include/SolTrade/TradeJournal.mqh
done

rg -q 'ALL SOLTRADE PHASE 5 POSITION MANAGER TESTS PASSED' "$test_file"
rg -q 'never submits, modifies, or closes a broker position' "$test_file"
for fixture in \
  "BUY EXIT_LONG" \
  "SELL EXIT_SHORT" \
  "MANUAL" \
  "REAL-ACCOUNT" \
  "DEFAULT-OFF" \
  "EMERGENCY-DRAWDOWN" \
  "EMERGENCY-STOP" \
  "MISSING-STOP" \
  "DUPLICATE" \
  "RESTART" \
  "MULTIPLE"; do
  rg -q "$fixture" "$test_file"
done

if rg -ni '\b(optimizer|optimization)\b' \
  MQL5; then
  echo "Optimization implementation is outside this build" >&2
  exit 1
fi

# Phase 6 may add tester-only reporting around the approved PositionManager,
# but must not alter its demo/live ownership, exit, or no-retry protections.
rg -q 'SolTradeBacktestManagementEnabled' \
  MQL5/Include/SolTrade/PositionManager.mqh

tests/verify-risk-math.sh
tests/verify-strategy-fixtures.sh
tests/verify-execution-fixtures.sh
tests/verify-position-manager-fixtures.sh
tests/static-phase4.sh
tests/static-one-shot-demo.sh

echo "Phase 5 static position-management safety checks passed."
