#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

required_files=(
  "MQL5/Include/SolTrade/BacktestResearch.mqh"
  "MQL5/Experts/SolTradePhase6DataQualificationProbe.mq5"
  "MQL5/Scripts/SolTradePhase6HistoryAcquisition.mq5"
  "MQL5/Scripts/SolTradePhase6SafetyTests.mq5"
  "tools/phase6_analyze.py"
  "tools/phase6_history_inventory.py"
  "tools/phase6_manifest.py"
  "tools/phase6_reconcile_pair.py"
  "tools/phase6_verify_history.py"
  "docs/phase6-backtesting.md"
  "reports/backtests/phase6-proposed-manifest/latency-observations.csv"
  "reports/backtests/phase6-prerun-evidence/aggregate-history-identity.sha256"
  "reports/backtests/phase6-prerun-evidence/history-identity.json"
  "reports/backtests/phase6-prerun-evidence/connected-safety-runtime.json"
)
for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required Phase 6 file: $required_file" >&2
    exit 1
  fi
done

ea_file="MQL5/Experts/SolTradeBot.mq5"
research_file="MQL5/Include/SolTrade/BacktestResearch.mqh"
test_file="MQL5/Scripts/SolTradePhase6SafetyTests.mq5"
history_file="MQL5/Scripts/SolTradePhase6HistoryAcquisition.mq5"
probe_file="MQL5/Experts/SolTradePhase6DataQualificationProbe.mq5"

for default_off in \
  EnableBacktestResearch \
  EnableBacktestExecution \
  EnableBacktestPositionManagement \
  EnableDemoExecution \
  EnablePositionManagement \
  AllowLiveTrading; do
  rg -q "input bool ${default_off}[[:space:]]*=[[:space:]]*false;" "$ea_file"
done

rg -q 'Phase 6 research is permitted only inside Strategy Tester' \
  "$research_file"
rg -q 'ExpectedEnvironment BACKTEST' MQL5/Include/SolTrade/Config.mqh
rg -q 'ExecutionInstanceId state/artifact namespace is not empty' \
  "$research_file"
rg -q 'BACKTEST_SIGNAL_OUTSIDE_DATASET' \
  MQL5/Include/SolTrade/ExecutionEngine.mqh
rg -q 'BACKTEST_CLOSE_OUTSIDE_DATASET' \
  MQL5/Include/SolTrade/PositionManager.mqh
rg -q 'Research latency evidence requires a SHA-256 value and at least 30 samples' \
  MQL5/Include/SolTrade/Config.mqh

rg -q 'adjusted_trade_net - supplementary_charge' \
  tools/phase6_analyze.py || \
  rg -q 'native_trade_net - supplementary_charge' tools/phase6_analyze.py
rg -q 'trade.native_trade_net - trade.supplementary_charge' \
  "$research_file"
rg -q 'case SOLTRADE_COST_NORMAL: return 0.0' \
  MQL5/Include/SolTrade/Config.mqh
rg -q 'case SOLTRADE_COST_HIGH:[[:space:]]*return 0.50' \
  MQL5/Include/SolTrade/Config.mqh
rg -q 'case SOLTRADE_COST_STRESS:[[:space:]]*return 1.00' \
  MQL5/Include/SolTrade/Config.mqh

rg -q 'INCONCLUSIVE_INSUFFICIENT_SAMPLE' "$research_file"
rg -q 'metrics.closed_trades < 50' "$research_file"
rg -q 'metrics.profit_factor > minimum_profit_factor' "$research_file"
rg -q 'metrics.best_trade_contribution_percent > 20.0' "$research_file"
rg -q 'metrics.best_period_contribution_percent > 40.0' "$research_file"
rg -q 'maximum_pf - minimum_pf > 0.40' "$research_file"

rg -q 'REPORTING_ONLY_INDEPENDENTLY_RESAMPLED_HISTORICAL_TRADE_RETURNS' \
  tools/phase6_analyze.py
rg -q 'does not reproduce serial dependence, market regimes' \
  tools/phase6_analyze.py
rg -q 'SUPPLEMENTARY_NOT_BROKER_NATIVE' \
  "$research_file" tools/phase6_analyze.py
rg -q 'NATIVE_MT5' "$research_file"

if rg -n '\b(OrderCheck|OrderSend)\s*\(' "$test_file"; then
  echo "Phase 6 deterministic safety tests must never call a broker" >&2
  exit 1
fi
if rg -n \
  '\b(OrderCheck|OrderSend|PositionClose|TRADE_ACTION_[A-Z_]+)\b' \
  "$history_file"; then
  echo "Phase 6 history acquisition must remain non-trading" >&2
  exit 1
fi
if rg -n \
  '\b(OrderCheck|OrderSend|PositionOpen|PositionClose|TRADE_ACTION_[A-Z_]+)\b' \
  "$probe_file"; then
  echo "Phase 6 data-qualification probe must remain non-trading" >&2
  exit 1
fi
rg -q 'input bool EnableEntryPermission[[:space:]]*=[[:space:]]*false;' \
  "$probe_file"
rg -q 'input bool EnableExecutionPermission[[:space:]]*=[[:space:]]*false;' \
  "$probe_file"
rg -q 'input bool EnablePositionManagementPermission[[:space:]]*=[[:space:]]*false;' \
  "$probe_file"
rg -q 'input bool PermitStrategyOrders[[:space:]]*=[[:space:]]*false;' \
  "$probe_file"
rg -q 'DEAL_TYPE_BALANCE' "$probe_file"
rg -q 'DEAL_TYPE_BUY_CANCELED' "$probe_file"
rg -q 'DEAL_TYPE_SELL_CANCELED' "$probe_file"
rg -q 'no_new_historical_deal_ticket' "$probe_file"
rg -q 'initial_balance_unchanged' "$probe_file"
rg -q 'ConfirmNonTradingHistoryAcquisition = false' "$history_file"
rg -q 'SOLTRADE_HISTORY_SERVER = "easyMarkets-Live"' "$history_file"
rg -q 'SOLTRADE_HISTORY_START = D'\''2024.01.01 00:00:00'\''' \
  "$history_file"
rg -q 'SOLTRADE_HISTORY_END_EXCLUSIVE = D'\''2026.07.01 00:00:00'\''' \
  "$history_file"
rg -q 'This script never calls OrderCheck, OrderSend, or Strategy Tester' \
  "$test_file"
rg -q 'ALL SOLTRADE PHASE 6 SAFETY TESTS PASSED' "$test_file"

# ExecutionInstanceId may select only state/artifact namespaces and report
# identity. It must never enter the approved trading modules.
if rg -n 'execution_instance_id' \
  MQL5/Include/SolTrade/StrategyBreakout.mqh \
  MQL5/Include/SolTrade/RiskEngine.mqh \
  MQL5/Include/SolTrade/ExecutionEngine.mqh \
  MQL5/Include/SolTrade/PositionManager.mqh; then
  echo "ExecutionInstanceId reached a trading calculation module" >&2
  exit 1
fi

if rg -ni '\b(optimizer|optimization|parameter sweep|genetic)\b' MQL5; then
  echo "Optimization remains outside Phase 6 implementation" >&2
  exit 1
fi
if rg -ni 'random delay' MQL5; then
  echo "Random-delay testing is not part of the authoritative implementation" >&2
  exit 1
fi

python3 -m py_compile \
  tools/phase6_analyze.py \
  tools/phase6_history_inventory.py \
  tools/phase6_manifest.py \
  tools/phase6_reconcile_pair.py \
  tools/phase6_verify_history.py
python3 tools/phase6_analyze.py --self-test
python3 tools/phase6_reconcile_pair.py --self-test

sample_count="$(
  awk -F, 'NR > 1 && $6 == "SUCCESS" { count++ } END { print count + 0 }' \
    reports/backtests/phase6-proposed-manifest/latency-observations.csv
)"
if [[ "$sample_count" -lt 30 ]]; then
  echo "Latency manifest contains fewer than 30 successful observations" >&2
  exit 1
fi

tests/static-phase5.sh

echo "Phase 6 static, reporting, and non-broker safety checks passed."
