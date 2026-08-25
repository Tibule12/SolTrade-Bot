#!/usr/bin/env bash
set -euo pipefail

source_file="MQL5/Experts/SolTradeFastMultiMarketV2.mq5"
demo_set="config/mt5/SolTradeFastMultiMarketV2-FPMarkets-demo.set"
service_file="ops/fast-multi-v2/soltrade-fast-multi-v2.service"
watchdog_timer="ops/fast-multi-v2/soltrade-fast-multi-v2-watchdog.timer"
launcher="ops/fast-multi-v2/soltrade-fast-multi-v2-launch"
watchdog="ops/fast-multi-v2/soltrade-fast-multi-v2-watchdog"

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
  'SPREAD_BASELINE_WARMUP'
  'MaxSpreadMedianRatio=1.75'
  'MinSpreadBaselineSamples=100'
  'out.direction>0\?MathMax\(m5_swing,m15_swing\):MathMin\(m5_swing,m15_swing\)'
  'LowestLow\(m5,1,8\):HighestHigh\(m5,1,8\)'
  'LowestLow\(m15,1,6\):HighestHigh\(m15,1,6\)'
  'if\(volume<=0\) continue'
  'stop_distance=MathMax\(stop_distance,MathMax\(1.15\*out.atr,0.55\*atr15\)\)'
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
  'PROTECTION_ADVANCED'
  'MinimumProtectedR'
  'MAX_GIVEBACK_R'
  'MAX_GIVEBACK_DOLLARS'
  'PROTECTION_DEFERRED_BROKER_DISTANCE'
  'RUNNER_PEAK_R'
  'RUNNER_PEAK_DOLLARS'
  'PROTECTED_R'
  'PROTECTED_DOLLARS'
  'TRAIL_UPDATES'
  'FINAL_CAPTURE_RATIO'
  'SOLTRADE_FAST_MULTI_V2_RUNNER_V2'
  'SOLTRADE_FAST_MULTI_V2_SPREAD_AUDIT_V1'
  'FX_PIP_AND_POINT'
  'METAL_TICK_AND_POINT'
  'INDEX_TICK_AND_POINT'
  'broker_sl_confirmed=true'
  'BROKER_RECONCILIATION_PASS'
  'AMBIGUOUS_PENDING_FAST_MULTI_ORDER'
  'DUPLICATE_FAST_MULTI_POSITION_'
  'BROKER_DISCONNECTED_RECONCILIATION_REQUIRED'
  'RUNTIME_TIMER_GAP_RECOVERY'
  'RECOVERY_HISTORY_STABLE_SCANS 3'
  'RECOVERY_HISTORY_MIN_SECONDS 30'
  'HISTORY_WARMUP_STARTED'
  'HISTORY_WARMUP_SYMBOL_READY'
  'POST_RECOVERY_HISTORY_WARMUP'
  'POSITION_MANAGEMENT_HISTORY_WARMUP_BLOCKED'
  'ExpectedBarAdvance'
  'normal_progression'
  'SOLTRADE_FAST_MULTI_V2_SCAN_AUDIT_V4'
  'scan-history-v4-'
  'MinStableSignalScans=3'
  'MinSignalPersistenceSeconds=30'
  'MaxEntryDriftM5Atr=0.60'
  'MaxM5SwingExtensionAtr=1.75'
  'MinSameSymbolReentryMinutes=30'
  'MinReentrySeparationAtr=0.50'
  'SETUP_SPECIFIC_CONFIRMATION_PENDING'
  'STRUCTURAL_DETERIORATION'
  'TEMPORARY_SCORE_WEAKNESS'
  'NORMAL_PULLBACK'
  'UpdateDirectionalPersistence'
  'UpdateSoftExitPersistence'
  'FIRST_SUCCESSFUL_SCAN_AFTER_RECOVERY'
  'INDEX_ALIAS_RETRY_FAILED'
  'REASON_TERMINAL_CLOSE_OR_UPDATE'
)

for pattern in "${required_patterns[@]}"; do
  rg -q "$pattern" "$source_file"
done

rg -q '^Restart=always$' "$service_file"
rg -q '^RestartSec=30$' "$service_file"
rg -q '^StartLimitIntervalSec=900$' "$service_file"
rg -q '^ExecStart=/home/tibule12/.local/libexec/soltrade-fast-multi-v2-launch$' "$service_file"
rg -Fq "/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Fast Multi/terminal64.exe" "$launcher"
rg -q 'WAITING_FOR_GRAPHICS' "$launcher"
rg -q 'UPDATE_GRACE_STARTED' "$launcher"
rg -q '^OnUnitActiveSec=1min$' "$watchdog_timer"
rg -q 'isolated_terminal_missing' "$watchdog"
rg -q 'runtime_stale' "$watchdog"

if rg -Fq '/Program Files/MetaTrader 5/terminal64.exe' "$service_file" "$launcher" "$watchdog"; then
  echo "normal MetaTrader terminal referenced by Fast Multi operations files" >&2
  exit 1
fi

bash -n "$launcher" "$watchdog"

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

for setting in \
  'MinStableSignalScans=3' \
  'MinSignalPersistenceSeconds=30' \
  'MaxEntryDriftM5Atr=0.60' \
  'MaxM5SwingExtensionAtr=1.75' \
  'MinSameSymbolReentryMinutes=30' \
  'MinReentrySeparationAtr=0.50'; do
  rg -q "^${setting}$" "$demo_set"
done

for setting in \
  'MaxSpreadMedianRatio=1.75' \
  'MinSpreadBaselineSamples=100' \
  'MinRewardRisk=1.25'; do
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
