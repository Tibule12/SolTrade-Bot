#!/usr/bin/env bash
set -euo pipefail

source_file="MQL5/Experts/SolTradeFastMultiMarketV2.mq5"
demo_set="config/mt5/SolTradeFastMultiMarketV2-FPMarkets-demo.set"

required_patterns=(
  '#define REQUIRED_DEMO_LOGIN 7404213'
  '#define FORBIDDEN_LIVE_LOGIN 7196820'
  '#define FORBIDDEN_OBSERVATION_LOGIN 2100139002'
  'ACCOUNT_TRADE_MODE_DEMO'
  'REAL_OR_NON_DEMO_ACCOUNT_BLOCKED'
  '#define SYMBOL_COUNT 19'
  'SymbolsTotal\(false\)'
  'AMBIGUOUS_VERIFIED_ALIASES'
  'MarketMetadataMatches'
  'FULL_TRADE_FRESH_CONTRACT_RISK_OK'
  'PERIOD_M1'
  'PERIOD_M5'
  'PERIOD_M15'
  'PERIOD_H1'
  'previous_session_context'
  'previous_day_high'
  'buy_score'
  'sell_score'
  'no_trade_score'
  'NO_TRADE_CASE_DOMINATES'
  'EXPECTED_NET_MOVE_INSUFFICIENT_AFTER_COSTS'
  'ABNORMAL_SPREAD'
  'NO_GENUINE_STRUCTURAL_REVERSAL'
  'M5_M15_REVERSAL_NOT_CONFIRMED'
  'SAME_STRUCTURAL_SETUP_ALREADY_CONSUMED'
  'g_immediate_rescan_requested=true'
  'SOLTRADE_FAST_MULTI_V2_INITIAL_RISK_V1'
  'OriginalDistanceFromBrokerHistory'
  'SOLTRADE_FAST_MULTI_V2_EPOCH_V1'
  'GlobalVariablesFlush'
  'RiskPerTradePercent!=0.25'
  'MaxPortfolioRiskPercent!=1.50'
  'MaxSimultaneousTrades!=6'
  'MaxStronglyCorrelatedTrades!=2'
  'PORTFOLIO_RISK_LIMIT'
  'PositionGetDouble\(POSITION_SL\)<=0'
  'PROTECTIVE_STOP_NOT_CONFIRMED_FLATTENED'
  'THESIS_INVALIDATION_EXIT'
  'TIGHTEN_STOP'
  'PROTECT_PROFIT'
  'TRAIL'
  'RUNNER_MODE_ENTERED'
  'RUNNER_TRAIL_UPDATE'
  'RUNNER_PEAK_R'
  'RUNNER_PEAK_DOLLARS'
  'PROTECTED_R'
  'PROTECTED_DOLLARS'
  'TRAIL_UPDATES'
  'FINAL_CAPTURE_RATIO'
  'SOLTRADE_FAST_MULTI_V2_RUNNER_V1'
  'SOLTRADE_FAST_MULTI_V2_SPREAD_AUDIT_V1'
  'FX_PIP_AND_POINT'
  'METAL_TICK_AND_POINT'
  'INDEX_TICK_AND_POINT'
  'broker_sl_confirmed=true'
)

for pattern in "${required_patterns[@]}"; do
  rg -q "$pattern" "$source_file"
done

for setting in \
  'DemoExecutionConfirmed=true' \
  'DryRunOnly=false' \
  'ApprovedDemoAccount=7404213' \
  'ApprovedDemoServer=FPMarketsSC-Demo' \
  'RiskPerTradePercent=0.25' \
  'MaxPortfolioRiskPercent=1.50' \
  'MaxSimultaneousTrades=6' \
  'MaxStronglyCorrelatedTrades=2' \
  'MinEntryScore=68.0' \
  'MinDirectionalDominance=12.0' \
  'MinNoTradeDominance=8.0' \
  'MinExpectedMoveCostMultiple=3.0'; do
  rg -q "^${setting}$" "$demo_set"
done

if rg -ni 'martingale|averaging down|revenge sizing|recovery sizing|17:00|PERIOD_D1' "$source_file"; then
  echo "forbidden lifecycle or sizing construct found" >&2
  exit 1
fi

if rg -n 'g_trade\.(Buy|Sell)\([^;]*,[[:space:]]*[1-9][0-9.]*[[:space:]]*,' "$source_file"; then
  echo "non-zero fixed take-profit found" >&2
  exit 1
fi

echo "fast multi-market V2 static safety checks passed"
