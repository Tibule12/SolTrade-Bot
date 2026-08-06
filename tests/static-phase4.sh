#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

required_files=(
  "MQL5/Include/SolTrade/ExecutionEngine.mqh"
  "MQL5/Scripts/SolTradeExecutionTests.mq5"
  "tests/verify-execution-fixtures.sh"
  "tests/phase4-connected-demo-checklist.md"
  "docs/execution-engine.md"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required Phase 4 file: $required_file" >&2
    exit 1
  fi
done

engine_file="MQL5/Include/SolTrade/ExecutionEngine.mqh"
test_file="MQL5/Scripts/SolTradeExecutionTests.mq5"
ea_file="MQL5/Experts/SolTradeBot.mq5"

if [[ "$(rg -c '\bOrderSend\(' "$engine_file")" -ne 1 ]]; then
  echo "Phase 4 must have exactly one synchronous OrderSend gateway" >&2
  exit 1
fi

if rg -n \
  '\b(OrderSendAsync|CTrade|PositionOpen|PositionClose)\s*\(' \
  MQL5; then
  echo "Unsupported trading or position-management API found" >&2
  exit 1
fi

if rg -n \
  '\b(TRADE_ACTION_SLTP|TRADE_ACTION_REMOVE|TRADE_ACTION_PENDING)\b' \
  MQL5; then
  echo "Unsupported order or stop-modification action is present" >&2
  exit 1
fi

if rg -n '\bOrderSend\s*\(' \
  MQL5/Experts \
  MQL5/Scripts \
  MQL5/Include/SolTrade/AccountGuard.mqh \
  MQL5/Include/SolTrade/MarketData.mqh \
  MQL5/Include/SolTrade/RiskEngine.mqh \
  MQL5/Include/SolTrade/StrategyBreakout.mqh \
  MQL5/Include/SolTrade/TradeJournal.mqh \
  MQL5/Include/SolTrade/Dashboard.mqh; then
  echo "Phase 4 OrderSend exists outside the approved execution gateway" >&2
  exit 1
fi

rg -q 'input bool EnableDemoExecution[[:space:]]*=[[:space:]]*false;' \
  "$ea_file"
rg -q 'input long ApprovedDemoAccount[[:space:]]*=[[:space:]]*0;' \
  "$ea_file"
rg -q 'input bool AllowLiveTrading[[:space:]]*=[[:space:]]*false;' \
  "$ea_file"
rg -q 'AllowLiveTrading must remain false through Phase 6' \
  MQL5/Include/SolTrade/Config.mqh
rg -q 'REAL_ACCOUNT_FORBIDDEN_PHASE4' "$engine_file"
rg -q 'DEMO_ACCOUNT_NOT_APPROVED' "$engine_file"
rg -q 'SOLTRADE_ENV_BACKTEST' "$engine_file"
rg -q 'TRADING_PERMISSION_DISABLED' "$engine_file"

rg -q 'SolTradeCalculatePositionSize' "$engine_file"
rg -q 'SolTradeValidateOrderVolume' "$engine_file"
rg -q 'SolTradeValidateStopDistance' "$engine_file"
rg -q 'SolTradeValidateSpread' "$engine_file"
rg -q 'OrderCalcMargin' "$engine_file"
rg -q 'OrderCheck' "$engine_file"
rg -q 'request\.magic[[:space:]]*=[[:space:]]*plan\.magic_number' \
  "$engine_file"
rg -q 'request\.sl[[:space:]]*=[[:space:]]*plan\.stop_loss' \
  "$engine_file"
rg -q 'request\.tp[[:space:]]*=[[:space:]]*0\.0' \
  "$engine_file"
rg -q 'DUPLICATE_SIGNAL_CANDLE' "$engine_file"
rg -q 'EXISTING_SOLTRADE_POSITION' "$engine_file"
rg -q 'ORDER_REJECTED_NO_RETRY' "$engine_file"
rg -q 'retry_allowed[[:space:]]*=[[:space:]]*false' "$engine_file"
rg -q 'ORDER_FILL_CONFIRMED' "$engine_file"
rg -q 'TRADE_TRANSACTION_DEAL_ADD' "$engine_file"
rg -q 'DEAL_ENTRY_IN' "$engine_file"
rg -q 'SolTradeExecutionStateChecksum' "$engine_file"
rg -q 'FileMove\(temporary_path, 0, m_state_path, FILE_REWRITE\)' \
  "$engine_file"

claim_line="$(
  rg -n '!ClaimExecutionAttempt\(plan, state_reason\)' "$engine_file" |
    cut -d: -f1
)"
send_line="$(
  rg -n 'const bool send_succeeded = OrderSend' "$engine_file" |
    cut -d: -f1
)"
if [[ -z "$claim_line" || -z "$send_line" ||
      "$claim_line" -ge "$send_line" ]]; then
  echo "The completed candle must be persisted before OrderSend" >&2
  exit 1
fi

rg -q 'LogExecution' MQL5/Include/SolTrade/TradeJournal.mqh
for journal_value in \
  "requested_entry" \
  "actual_entry" \
  "spread_points" \
  "slippage_points" \
  "stop_loss" \
  "lot_size" \
  "risk_amount" \
  "order_ticket" \
  "broker_return_code"; do
  rg -q "\"${journal_value}\"" MQL5/Include/SolTrade/TradeJournal.mqh
done

rg -q 'OnTradeTransaction' "$ea_file"
rg -q 'ProcessSignal\(g_strategy_signal' "$ea_file"
rg -q 'ALL SOLTRADE PHASE 4 EXECUTION TESTS PASSED' "$test_file"
rg -q 'never submits an order' "$test_file"

for fixture in \
  "VALID-DEMO-BUY" \
  "VALID-DEMO-SELL" \
  "REAL-ACCOUNT" \
  "LIVE-TRADING-DISABLED" \
  "INVALID-VOLUME" \
  "INVALID-STOP-DISTANCE" \
  "INSUFFICIENT-MARGIN" \
  "EXCESSIVE-SPREAD" \
  "DUPLICATE-CANDLE" \
  "EXISTING-POSITION" \
  "BROKER-REJECT" \
  "RESTART"; do
  rg -q "$fixture" "$test_file"
done

tests/verify-execution-fixtures.sh

echo "Phase 4 static execution-safety checks passed."
