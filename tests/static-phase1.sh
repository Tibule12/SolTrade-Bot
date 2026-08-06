#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

required_files=(
  "MQL5/Experts/SolTradeBot.mq5"
  "MQL5/Include/SolTrade/Config.mqh"
  "MQL5/Include/SolTrade/AccountGuard.mqh"
  "MQL5/Include/SolTrade/MarketData.mqh"
  "MQL5/Include/SolTrade/TradeJournal.mqh"
  "MQL5/Include/SolTrade/Dashboard.mqh"
  "docs/architecture.md"
  "docs/configuration-model.md"
  "docs/account-mode-safety.md"
  "docs/risk-calculation-spec.md"
  "docs/testing-plan.md"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required Phase 1 file: $required_file" >&2
    exit 1
  fi
done

mapfile -t expert_advisors < <(find MQL5/Experts -maxdepth 1 -type f -name '*.mq5' -print)
if [[ "${#expert_advisors[@]}" -ne 1 ]]; then
  echo "Expected exactly one Expert Advisor entry point, found ${#expert_advisors[@]}" >&2
  exit 1
fi

if rg -n \
  '\b(OrderSend|OrderSendAsync|CTrade|PositionOpen|PositionClose|Buy|Sell)\s*\(' \
  MQL5/Include/SolTrade/Config.mqh \
  MQL5/Include/SolTrade/AccountGuard.mqh \
  MQL5/Include/SolTrade/MarketData.mqh \
  MQL5/Include/SolTrade/TradeJournal.mqh \
  MQL5/Include/SolTrade/Dashboard.mqh; then
  echo "A trading API call exists inside a foundation module" >&2
  exit 1
fi

rg -q 'input bool[[:space:]]+AllowLiveTrading[[:space:]]*=[[:space:]]*false;' \
  MQL5/Experts/SolTradeBot.mq5
rg -q 'input ENUM_TIMEFRAMES SignalTimeframe[[:space:]]*=[[:space:]]*PERIOD_H1;' \
  MQL5/Experts/SolTradeBot.mq5
rg -q 'input double RiskPerTradePercent[[:space:]]*=[[:space:]]*0\.25;' \
  MQL5/Experts/SolTradeBot.mq5
rg -q 'input double DailyLossLimitPercent[[:space:]]*=[[:space:]]*1\.0;' \
  MQL5/Experts/SolTradeBot.mq5
rg -q 'input double WeeklyLossLimitPercent[[:space:]]*=[[:space:]]*2\.5;' \
  MQL5/Experts/SolTradeBot.mq5
rg -q 'input double EmergencyDrawdownPercent[[:space:]]*=[[:space:]]*5\.0;' \
  MQL5/Experts/SolTradeBot.mq5
rg -q 'PHASE 6 TESTER RESEARCH; LIVE TRADING DISABLED' \
  MQL5/Include/SolTrade/Dashboard.mqh

required_journal_fields=(
  "timestamp"
  "account_mode"
  "account_identifier_hash"
  "broker"
  "symbol"
  "timeframe"
  "bid"
  "ask"
  "spread_points"
  "strategy_version"
  "signal_result"
  "rejection_reason"
  "requested_entry"
  "actual_entry"
  "slippage_points"
  "stop_loss"
  "lot_size"
  "risk_amount"
  "balance"
  "equity"
  "daily_drawdown_percent"
  "weekly_drawdown_percent"
  "order_ticket"
  "broker_return_code"
  "final_profit_loss"
  "exit_reason"
)

for journal_field in "${required_journal_fields[@]}"; do
  rg -q "\"${journal_field}\"" MQL5/Include/SolTrade/TradeJournal.mqh
done

if rg -n --glob '*.{mq5,mqh}' \
  '(ACCOUNT_NAME|password|passwd|secret|api[_-]?key)' MQL5; then
  echo "Potential credential or personal-account logging token found" >&2
  exit 1
fi

if rg -n 'ACCOUNT_LOGIN' MQL5/Include/SolTrade/TradeJournal.mqh; then
  echo "Raw account login is referenced by the journal implementation" >&2
  exit 1
fi

echo "Phase 1 static safety checks passed."
