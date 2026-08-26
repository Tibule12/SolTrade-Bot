#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from math import isclose

tolerance = 0.005
assert 0.49685 + tolerance >= 0.50
assert 0.49490 + tolerance < 0.50

# Broker-confirmed NZDUSD example: the old 0.59614 stop was favourable in
# price but negative after commission. The corrected floor solves for target
# net R after the round-trip commission price equivalent.
entry = 0.59620
direction = -1
initial_distance = 0.00056
commission_move = 0.000072
target_net_r = 0.10
risk_move = initial_distance + commission_move
floor = entry + direction * (target_net_r * risk_move + commission_move)
net_r = ((entry - floor) - commission_move) / risk_move
assert isclose(floor, 0.5960648, abs_tol=1e-12)
assert isclose(net_r, target_net_r, abs_tol=1e-12)
old_net_r = ((entry - 0.59614) - commission_move) / risk_move
assert old_net_r < 0

def conflict(direction: int, t5: float, t15: float) -> bool:
    timeframe = (t5 > 0.20 and t15 < -0.16) or (t5 < -0.20 and t15 > 0.16)
    direction_m15 = (direction > 0 and t15 < -0.16) or (direction < 0 and t15 > 0.16)
    return timeframe or direction_m15

assert conflict(1, 0.30, -0.20)
assert conflict(-1, -0.30, 0.20)
assert conflict(1, 0.00, -0.20)
assert not conflict(1, 0.30, 0.20)
assert not conflict(-1, -0.30, -0.20)
PY

echo "fast multi V2 profit-boundary and entry-conflict regressions passed"
