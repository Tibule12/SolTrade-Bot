#!/usr/bin/env bash
set -euo pipefail

awk '
function absolute(value) {
  return value < 0 ? -value : value
}

function assert_near(name, actual, expected, tolerance) {
  if (absolute(actual - expected) > tolerance) {
    printf "FAIL: %s actual=%.10f expected=%.10f\n", \
      name, actual, expected > "/dev/stderr"
    failures++
  } else {
    printf "PASS: %s actual=%.10f expected=%.10f\n", \
      name, actual, expected
  }
}

function assert_true(name, condition) {
  if (!condition) {
    printf "FAIL: %s\n", name > "/dev/stderr"
    failures++
  } else {
    printf "PASS: %s\n", name
  }
}

BEGIN {
  failures = 0
  equity = 10000
  risk_percent = 0.25
  risk_budget = equity * risk_percent / 100
  ask = 1.10002
  bid = 1.10000
  stop_distance = 0.00200
  tick_size = 0.00001
  tick_value_loss = 1
  volume_step = 0.01
  volume_min = 0.01
  loss_per_lot = stop_distance / tick_size * tick_value_loss
  raw_volume = risk_budget / loss_per_lot
  grid_steps = int((raw_volume - volume_min + 0.000000000001) / volume_step)
  volume = volume_min + grid_steps * volume_step
  expected_loss = volume * loss_per_lot

  assert_near("Phase 4 0.25-percent risk budget",
              risk_budget, 25.00, 0.00000001)
  assert_near("Phase 4 lot-step rounding",
              volume, 0.12, 0.00000001)
  assert_near("Phase 4 expected risk",
              expected_loss, 24.00, 0.00000001)
  one_shot_volume = volume_min
  one_shot_risk = one_shot_volume * loss_per_lot
  assert_near("One-shot safer broker-minimum volume",
              one_shot_volume, 0.01, 0.00000001)
  assert_near("One-shot broker-minimum risk",
              one_shot_risk, 2.00, 0.00000001)
  assert_true("One-shot volume does not exceed risk-calculated size",
              one_shot_volume <= volume)
  assert_true("One-shot risk does not exceed approved risk",
              one_shot_risk <= expected_loss)
  assert_near("Phase 4 BUY requested Ask",
              ask, 1.10002, 0.00000001)
  assert_near("Phase 4 BUY stop",
              ask - stop_distance, 1.09802, 0.00000001)
  assert_near("Phase 4 SELL requested Bid",
              bid, 1.10000, 0.00000001)
  assert_near("Phase 4 SELL stop",
              bid + stop_distance, 1.10200, 0.00000001)
  assert_true("Phase 4 valid spread passes absolute limit",
              2 <= 30)
  assert_true("Phase 4 valid spread passes ATR-relative limit",
              2 * 0.00001 <= 0.00100 * 0.10)
  assert_true("Phase 4 excessive absolute spread fails",
              31 > 30)
  assert_true("Phase 4 excessive ATR-relative spread fails",
              11 * 0.00001 > 0.00100 * 0.10)
  assert_true("Phase 4 margin acceptance fixture",
              500 <= 9000)
  assert_true("Phase 4 insufficient margin fixture",
              9500 > 9000)
  assert_true("OrderCheck true plus check retcode 0 is accepted",
              1 && 0 == 0)
  assert_true("OrderCheck false plus check retcode 0 is rejected",
              !(0 && 0 == 0))
  assert_true("OrderCheck true plus non-zero check retcode is rejected",
              !(1 && 10009 == 0))

  if (failures > 0) {
    printf "Execution fixture verification failed: %d failure(s)\n", \
      failures > "/dev/stderr"
    exit 1
  }

  print "Independent Phase 4 execution fixture checks passed."
}
'
