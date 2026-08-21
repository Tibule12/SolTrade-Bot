#!/usr/bin/env bash
set -euo pipefail

source_file="MQL5/Experts/SolTradeFastMultiMarketV1.mq5"
demo_set="config/mt5/SolTradeFastMultiMarketV1-FPMarkets-demo.set"

rg -q '#define REQUIRED_DEMO_LOGIN 7404213' "$source_file"
rg -q 'ACCOUNT_TRADE_MODE_DEMO' "$source_file"
rg -q 'REAL_OR_NON_DEMO_ACCOUNT_BLOCKED' "$source_file"
rg -q 'RiskPerTradePercent!=0.25' "$source_file"
rg -q 'MaxPortfolioRiskPercent!=1.50' "$source_file"
rg -q 'MaxSimultaneousTrades!=6' "$source_file"
rg -q 'MaxStronglyCorrelatedTrades!=2' "$source_file"
rg -q '#define SYMBOL_COUNT 19' "$source_file"
rg -q '"XAUUSD","USTEC","GBPJPY","XAGUSD","DE30","EURJPY","AUDJPY","USDJPY","GBPUSD"' "$source_file"
rg -q '"EURUSD","US500","USDCAD","AUDUSD","NZDUSD","USDCHF","STOXX50","UK100","EURGBP","AUDNZD"' "$source_file"
rg -q '#define LEGACY_PILOT_MAGIC 2082026032' "$source_file"
rg -q 'MAX_SIX_POSITIONS_WITH_LEGACY_REENTRY_RESERVE' "$source_file"
rg -q 'PositionGetDouble\(POSITION_SL\)<=0' "$source_file"
rg -q 'PROTECTIVE_STOP_NOT_CONFIRMED_FLATTENED' "$source_file"
rg -q 'current_r>=0.75' "$source_file"
rg -q 'current_r>=0.50' "$source_file"
rg -q 'current_r>=0.25' "$source_file"
rg -q 'g_immediate_rescan_requested=true' "$source_file"
rg -q 'SymbolsTotal\(false\)' "$source_file"
rg -q 'WriteBrokerSymbolCatalogue' "$source_file"
rg -q 'StartsWithText' "$source_file"
rg -q 'EURO50' "$source_file"
rg -q 'CACHE_REVALIDATED' "$source_file"
rg -q 'SYMBOL_TRADE_MODE_FULL' "$source_file"
rg -q 'FULL_TRADE_FRESH_CONTRACT_RISK_OK' "$source_file"
rg -q 'OrderCalcProfit\(ORDER_TYPE_BUY' "$source_file"
rg -q 'AMBIGUOUS_VERIFIED_ALIASES' "$source_file"
rg -q '^DemoExecutionConfirmed=true$' "$demo_set"
rg -q '^DryRunOnly=false$' "$demo_set"
rg -q '^ApprovedDemoAccount=7404213$' "$demo_set"
rg -q '^ApprovedDemoServer=FPMarketsSC-Demo$' "$demo_set"

if rg -n 'martingale|averaging down|17:00|PERIOD_D1' "$source_file"; then
  echo "Forbidden lifecycle or sizing construct found" >&2
  exit 1
fi

echo "fast multi-market static safety checks passed"
