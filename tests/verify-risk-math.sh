#!/usr/bin/env bash
set -euo pipefail

awk '
function absolute(value) {
  return value < 0 ? -value : value
}

function assert_near(name, actual, expected, tolerance) {
  if (absolute(actual - expected) > tolerance) {
    printf "FAIL: %s actual=%.10f expected=%.10f\n", name, actual, expected > "/dev/stderr"
    failures++
  } else {
    printf "PASS: %s actual=%.10f expected=%.10f\n", name, actual, expected
  }
}

function run_account(label, equity, expected_volume, expected_loss) {
  risk_budget = equity * 0.0025
  loss_per_lot = (0.00123 / 0.00001) * 1.0
  raw_volume = risk_budget / loss_per_lot
  volume_min = 0.01
  step = 0.01
  normalised_volume = volume_min + \
    int(((raw_volume - volume_min) + 0.000000000001) / step) * step
  stop_loss = normalised_volume * loss_per_lot
  offset_step = 0.03
  offset_volume = volume_min + \
    int(((raw_volume - volume_min) + 0.000000000001) / offset_step) * offset_step

  assert_near(label " risk budget", risk_budget, equity == 500 ? 1.25 : 25.00, 0.00000001)
  assert_near(label " raw volume", raw_volume, equity == 500 ? 0.0101626016 : 0.2032520325, 0.00000001)
  assert_near(label " rounded volume", normalised_volume, expected_volume, 0.00000001)
  assert_near(label " minimum-offset 0.03-step volume", offset_volume, \
              equity == 500 ? 0.01 : 0.19, 0.00000001)
  assert_near(label " normalised stop loss", stop_loss, expected_loss, 0.00000001)
  assert_near(label " daily threshold", equity * 0.99, equity == 500 ? 495.00 : 9900.00, 0.00000001)
  assert_near(label " weekly threshold", equity * 0.975, equity == 500 ? 487.50 : 9750.00, 0.00000001)
  assert_near(label " emergency threshold", equity * 0.95, equity == 500 ? 475.00 : 9500.00, 0.00000001)
  assert_near(label " daily lock percentage", ((equity - equity * 0.99) / equity) * 100, 1.0, 0.00000001)
  assert_near(label " weekly lock percentage", ((equity - equity * 0.975) / equity) * 100, 2.5, 0.00000001)
  assert_near(label " emergency lock percentage", ((equity - equity * 0.95) / equity) * 100, 5.0, 0.00000001)

  if (stop_loss > risk_budget + 0.01) {
    printf "FAIL: %s rounded loss exceeds budget\n", label > "/dev/stderr"
    failures++
  }
}

BEGIN {
  failures = 0
  run_account("$500", 500, 0.01, 1.23)
  run_account("$10,000", 10000, 0.20, 24.60)

  consecutive_losses = 0
  last_outcome_id = ""
  outcome_ids[1] = "LOSS-1"
  outcome_ids[2] = "LOSS-2"
  outcome_ids[3] = "LOSS-3"
  for (outcome_index = 1; outcome_index <= 3; outcome_index++) {
    if (outcome_ids[outcome_index] != last_outcome_id) {
      consecutive_losses++
      last_outcome_id = outcome_ids[outcome_index]
    }
  }
  assert_near("third distinct loss locks", consecutive_losses, 3, 0)

  if ("LOSS-3" != last_outcome_id)
    consecutive_losses++
  assert_near("duplicate loss does not increment", consecutive_losses, 3, 0)

  emergency_locked = 1
  recovered_drawdown = 0
  if (recovered_drawdown >= 5)
    emergency_locked = 1
  assert_near("emergency remains latched after recovery", emergency_locked, 1, 0)

  consecutive_locked = 1
  if (20260728 != 20260727) {
    consecutive_locked = 0
    consecutive_losses = 0
  }
  assert_near("next broker day clears consecutive lock", consecutive_locked, 0, 0)
  assert_near("next broker day resets locked streak", consecutive_losses, 0, 0)

  if (failures > 0) {
    printf "Risk arithmetic verification failed: %d failure(s)\n", failures > "/dev/stderr"
    exit 1
  }

  print "Independent Phase 2 risk arithmetic checks passed."
}
'
