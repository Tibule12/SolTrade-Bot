#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

required_files=(
  "MQL5/Include/SolTrade/RiskEngine.mqh"
  "MQL5/Scripts/SolTradeRiskTests.mq5"
  "tests/risk-engine-calculation-cases.md"
  "tests/verify-risk-math.sh"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required Phase 2 file: $required_file" >&2
    exit 1
  fi
done

if rg -n \
  '\b(OrderSend|OrderSendAsync|CTrade|PositionOpen|PositionClose|Buy|Sell)\s*\(' \
  MQL5/Include/SolTrade/RiskEngine.mqh \
  MQL5/Scripts/SolTradeRiskTests.mq5; then
  echo "A trading API call exists inside the Phase 2 risk scope" >&2
  exit 1
fi

rg -q '#property version[[:space:]]+"1\.000"' MQL5/Experts/SolTradeBot.mq5
rg -q '#property version[[:space:]]+"1\.000"' MQL5/Scripts/SolTradeRiskTests.mq5
rg -q 'SYMBOL_TRADE_TICK_VALUE_LOSS' MQL5/Include/SolTrade/RiskEngine.mqh
rg -q 'MathFloor' MQL5/Include/SolTrade/RiskEngine.mqh
rg -q 'DAILY_LOSS_LOCKED' MQL5/Include/SolTrade/RiskEngine.mqh
rg -q 'WEEKLY_LOSS_LOCKED' MQL5/Include/SolTrade/RiskEngine.mqh
rg -q 'EMERGENCY_DRAWDOWN_LOCKED' MQL5/Include/SolTrade/RiskEngine.mqh
rg -q 'CONSECUTIVE_LOSS_LOCKED' MQL5/Include/SolTrade/RiskEngine.mqh
rg -q 'SOLTRADE_OUTCOME_DUPLICATE' MQL5/Include/SolTrade/RiskEngine.mqh
rg -q 'SolTradeValidatePositionCapacity' MQL5/Include/SolTrade/RiskEngine.mqh
rg -q 'SolTradeRiskStateChecksum' MQL5/Include/SolTrade/RiskEngine.mqh
rg -q 'FileMove\(temporary_path, 0, m_state_path, FILE_REWRITE\)' \
  MQL5/Include/SolTrade/RiskEngine.mqh
rg -q 'ALL SOLTRADE PHASE 2 RISK TESTS PASSED' \
  MQL5/Scripts/SolTradeRiskTests.mq5
rg -q 'RunAccountScenario\(500\.0, 0\.01, 1\.23' \
  MQL5/Scripts/SolTradeRiskTests.mq5
rg -q 'RunAccountScenario\(10000\.0' \
  MQL5/Scripts/SolTradeRiskTests.mq5
rg -q '"EQ500"' MQL5/Scripts/SolTradeRiskTests.mq5
rg -q '"EQ10000"' MQL5/Scripts/SolTradeRiskTests.mq5
rg -q 'duplicate-outcome cache starts empty' \
  MQL5/Scripts/SolTradeRiskTests.mq5
rg -q 'persistent state starts clean' \
  MQL5/Scripts/SolTradeRiskTests.mq5

if rg -n 'RecordClosedOutcome\(label' MQL5/Scripts/SolTradeRiskTests.mq5; then
  echo "Display labels must not be reused as machine outcome identifiers" >&2
  exit 1
fi

tests/static-phase1.sh
tests/verify-risk-math.sh

echo "Phase 2 static safety checks passed."
