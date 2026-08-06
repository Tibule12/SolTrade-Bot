#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

required_files=(
  "MQL5/Include/SolTrade/StrategyBreakout.mqh"
  "MQL5/Scripts/SolTradeStrategyTests.mq5"
  "tests/expected-strategy-signals.csv"
  "tests/phase3-runtime-verification.md"
  "tests/verify-strategy-fixtures.sh"
  "docs/strategy-v1.md"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required Phase 3 file: $required_file" >&2
    exit 1
  fi
done

if rg -n \
  '\b(OrderSend|OrderSendAsync|CTrade|PositionOpen|PositionClose|Buy|Sell)\s*\(' \
  MQL5/Include/SolTrade/StrategyBreakout.mqh \
  MQL5/Scripts/SolTradeStrategyTests.mq5; then
  echo "A trading API call exists inside the Phase 3 strategy scope" >&2
  exit 1
fi

if rg -n \
  '\b(OnTradeTransaction|MqlTradeRequest|MqlTradeResult)\b' \
  MQL5/Include/SolTrade/StrategyBreakout.mqh \
  MQL5/Scripts/SolTradeStrategyTests.mq5; then
  echo "Execution or trade-transaction code exists during Phase 3" >&2
  exit 1
fi

strategy_file="MQL5/Include/SolTrade/StrategyBreakout.mqh"
test_file="MQL5/Scripts/SolTradeStrategyTests.mq5"
ea_file="MQL5/Experts/SolTradeBot.mq5"

rg -q '#define SOLTRADE_EMA_PERIOD[[:space:]]+200' "$strategy_file"
rg -q '#define SOLTRADE_ENTRY_CHANNEL_PERIOD[[:space:]]+20' "$strategy_file"
rg -q '#define SOLTRADE_EXIT_CHANNEL_PERIOD[[:space:]]+10' "$strategy_file"
rg -q '#define SOLTRADE_ATR_PERIOD[[:space:]]+14' "$strategy_file"
rg -q '#define SOLTRADE_STRATEGY_HISTORY_BARS[[:space:]]+221' "$strategy_file"
rg -q 'CopyRates\(config\.symbol,' "$strategy_file"
rg -q '^[[:space:]]*1,$' "$strategy_file"
rg -q 'SOLTRADE_SIGNAL_BUY' "$strategy_file"
rg -q 'SOLTRADE_SIGNAL_SELL' "$strategy_file"
rg -q 'SOLTRADE_SIGNAL_NONE' "$strategy_file"
rg -q 'BUY_BREAKOUT_ABOVE_EMA200' "$strategy_file"
rg -q 'SELL_BREAKOUT_BELOW_EMA200' "$strategy_file"
rg -q 'NO_ENTRY_BREAKOUT' "$strategy_file"
rg -q 'LONG_EXIT_BREAKOUT' "$strategy_file"
rg -q 'SHORT_EXIT_BREAKOUT' "$strategy_file"
rg -q 'initial_stop_distance = 2\.0 \* atr' "$strategy_file"
if [[ "$(rg -F -c 'SolTradeStrictlyBelow(signal.signal_close,' \
  "$strategy_file")" -ne 2 ]]; then
  echo "Expected strict-below guard on SELL entry and EXIT_LONG only" >&2
  exit 1
fi

rg -q '#property version[[:space:]]+"1\.000"' "$ea_file"
rg -q '#property version[[:space:]]+"1\.000"' "$test_file"
rg -q 'STRATEGY_SIGNAL_EVALUATED' "$ea_file"
rg -q 'SolTradeStrategyLogDetails' "$ea_file"
rg -q '"; entry_reason="' "$strategy_file"
rg -q '"; exit_reason="' "$strategy_file"
rg -q 'ProcessSignal\(g_strategy_signal' "$ea_file"
rg -q 'PHASE 6 TESTER RESEARCH; LIVE TRADING DISABLED' \
  MQL5/Include/SolTrade/Dashboard.mqh
rg -q 'ALL SOLTRADE PHASE 3 STRATEGY TESTS PASSED' "$test_file"

for fixture in \
  "FLAT-001" \
  "BUY-001" \
  "SELL-001" \
  "BOUNDARY-HIGH" \
  "BOUNDARY-LOW" \
  "FILTER-BUY" \
  "FILTER-SELL" \
  "EXIT-LONG-001" \
  "EXIT-SHORT-001" \
  "INVALID-SHORT" \
  "INVALID-ORDER" \
  "INVALID-OHLC"; do
  rg -q "$fixture" "$test_file"
done

tests/static-phase2.sh
tests/verify-strategy-fixtures.sh

echo "Phase 3 static signal-only checks passed."
