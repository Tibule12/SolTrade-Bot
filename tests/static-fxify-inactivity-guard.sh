#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

guard="FXIFYInactivityGuard/MQL5/Experts/FXIFYInactivityGuard.mq5"
production="MQL5/Experts/SolTradeBot.mq5"
expected_production_sha="261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"

[[ -f "$guard" ]]
[[ "$(sha256sum "$production" | cut -d' ' -f1)" == "$expected_production_sha" ]]

required_inputs=(
  GuardEnabled WarningDay MaintenanceDay CriticalAlertDay MaintenanceSymbol
  MaximumVolume StopLossPips TakeProfitPips MaximumHoldingMinutes
  MaximumSpreadPips MaximumSlippagePips EstimatedCommissionPerLot
  MaximumStopRiskUSD
  ReferenceInitialBalance DailyLossLimitPercent MaximumLossLimitPercent
  LossLimitSafetyBuffer GuardMagicNumber GuardOrderComment
  RetryIntervalMinutes DryRunMode
)
for required_input in "${required_inputs[@]}"; do
  rg -q "input .*${required_input}" "$guard"
done

rg -q 'input bool[[:space:]]+DryRunMode[[:space:]]*=[[:space:]]*true;' "$guard"
rg -q 'input string MaintenanceSymbol[[:space:]]*=[[:space:]]*"EURUSD";' "$guard"
rg -q 'input double MaximumVolume[[:space:]]*=[[:space:]]*0\.01;' "$guard"
rg -q 'input double StopLossPips[[:space:]]*=[[:space:]]*10\.0;' "$guard"
rg -q 'input int[[:space:]]+WarningDay[[:space:]]*=[[:space:]]*45;' "$guard"
rg -q 'input int[[:space:]]+MaintenanceDay[[:space:]]*=[[:space:]]*50;' "$guard"
rg -q 'input int[[:space:]]+CriticalAlertDay[[:space:]]*=[[:space:]]*55;' "$guard"

[[ "$(rg -c '\bOrderSend\(' "$guard")" -eq 1 ]]
rg -q '\bOrderCheck\(' "$guard"
rg -q 'check_succeeded || check\.retcode!=0' "$guard"
if rg -n '\b(OrderSendAsync|CTrade|PositionOpen|PositionClose)\s*\(' "$guard"; then
  echo "Unsupported asynchronous or convenience trading API in guard" >&2
  exit 1
fi
if rg -n '\b(TRADE_ACTION_SLTP|TRADE_ACTION_REMOVE|TRADE_ACTION_PENDING)\b' "$guard"; then
  echo "Guard must never modify/remove stops or place pending orders" >&2
  exit 1
fi

for required_token in \
  HistorySelect HistoryDealGetTicket DEAL_ENTRY_IN DEAL_ENTRY_INOUT \
  TRADE_TRANSACTION_DEAL_ADD ACCOUNT_TRADE_ALLOWED ACCOUNT_TRADE_EXPERT \
  TERMINAL_TRADE_ALLOWED MQL_TRADE_ALLOWED SYMBOL_VOLUME_MIN \
  SYMBOL_VOLUME_STEP SYMBOL_VOLUME_MAX SYMBOL_TRADE_STOPS_LEVEL \
  SYMBOL_TRADE_TICK_VALUE_LOSS OrderCalcMargin request.sl request.tp \
  projected_loss commission_risk spread_risk slippage_risk stop_risk \
  GlobalVariableSetOnCondition POSITION_IDENTIFIER POSITION_MAGIC \
  POSITION_SL MaximumHoldingMinutes; do
  rg -q "$required_token" "$guard"
done

rg -q 'ResolveMaintenanceSymbol' "$guard"
rg -q 'MaintenanceSymbol\+"\.r"' "$guard"
rg -q 'ACCOUNT_READ_ONLY_OR_TRADE_DISABLED' "$guard"
rg -q 'EXCESSIVE_SPREAD' "$guard"
rg -q 'INSUFFICIENT_MARGIN' "$guard"
rg -q 'DAILY_LOSS_SAFETY_BUFFER' "$guard"
rg -q 'MAXIMUM_LOSS_SAFETY_BUFFER' "$guard"
rg -q 'SERVER_STOP_MISSING' "$guard"
rg -q 'CROSS_INSTANCE_EXECUTION_LOCKED' "$guard"
rg -q 'ACCOUNT_NON_GUARD' "$guard"

if rg -ni 'login|password|investor|account[_ -]?id' "$guard"; then
  echo "Credential-like field found in guard source" >&2
  exit 1
fi

python3 -m unittest -q tests/test_fxify_inactivity_guard.py

echo "FXIFY inactivity guard static and deterministic checks passed."
