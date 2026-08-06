#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ea="$repo_root/MQL5/Experts/SolTradeV28.mq5"
legacy="$repo_root/MQL5/Experts/SolTradeBot.mq5"
proof="$repo_root/reports/backtests/soltrade-v28-live-ea-equivalence/equivalence-proof.json"
preflight="$repo_root/config/mt5/SolTradeV28-FXIFY-preflight.example.set"
live="$repo_root/config/mt5/SolTradeV28-FXIFY-live.example.set"

test "$(sha256sum "$legacy" | awk '{print $1}')" = "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"
test "$(jq -r .status "$proof")" = "PASS"
test "$(jq -r .unexplained_difference_count "$proof")" = "0"
jq -e '.maximum_metric_absolute_difference == 0' "$proof" >/dev/null

rg -q '#define V28_LEGS[[:space:]]+7' "$ea"
rg -q '#define V28_RISK_PER_LEG_PERCENT[[:space:]]+0\.5' "$ea"
rg -q '#define V28_ATR_MULTIPLIER[[:space:]]+3\.0' "$ea"
rg -q '#define V28_DAILY_LOSS_LIMIT_PERCENT[[:space:]]+1\.0' "$ea"
rg -q '#define V28_EMERGENCY_DRAWDOWN_PERCENT[[:space:]]+5\.0' "$ea"
rg -q 'int ORIENTATION\[V28_LEGS\]=\{1,1,1,1,-1,-1,-1\};' "$ea"
rg -q 'iATR\(g_symbols\[i\],PERIOD_D1,14\)' "$ea"
rg -q 'datetime target=monday\+10\*3600\+5\*60;' "$ea"
rg -q 'datetime recent=monday\+9\*3600;' "$ea"
rg -q 'datetime anchor=PreviousFirstMonday\(monday\)\+9\*3600;' "$ea"
rg -q 'factor\+=ORIENTATION\[i\]\*MathLog\(recent_close\[i\]/anchor_close\[i\]\)/7\.0;' "$ea"
rg -q 'signal\.initial_stop_distance=V28_ATR_MULTIPLIER\*atr;' "$ea"
rg -q 'signal\.exit_reason_code="DOLLAR_FACTOR_REBALANCE";' "$ea"
rg -q 'if\(DryRunMode\)' "$ea"
rg -q 'NO_ORDER_SUBMISSION' "$ea"
rg -q 'HistorySelect\(0,TimeCurrent\(\)\)' "$ea"
rg -q 'last_consumed_signal_bar' "$ea"

grep -Fxq 'DryRunMode=true' "$preflight"
grep -Fxq 'DryRunMode=false' "$live"
grep -Fxq 'SymbolSuffix=.r' "$preflight"
grep -Fxq 'ApprovedAccount=0' "$preflight"
grep -Fxq 'ApprovedServer=FXIFY-Server' "$preflight"

echo "SolTradeV28 static verification: PASS"
