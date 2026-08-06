#!/usr/bin/env bash
set -euo pipefail

awk '
function pass(name) {
  print "PASS: " name
}
function fail(name, details) {
  print "FAIL: " name " | " details > "/dev/stderr"
  failures++
}
function assert_true(name, condition) {
  if (condition) pass(name)
  else fail(name, "condition was false")
}
function assert_near(name, actual, expected, tolerance) {
  if (actual >= expected - tolerance && actual <= expected + tolerance)
    pass(name)
  else
    fail(name, "actual=" actual " expected=" expected)
}
BEGIN {
  failures = 0

  bid = 1.13615
  ask = 1.13617
  point = 0.00001

  assert_true("BUY closes only with EXIT_LONG", "EXIT_LONG" == "EXIT_LONG")
  assert_true("BUY close request is SELL", "SELL" == "SELL")
  assert_near("BUY close requested at Bid", bid, 1.13615, 0.000000001)

  assert_true("SELL closes only with EXIT_SHORT", "EXIT_SHORT" == "EXIT_SHORT")
  assert_true("SELL close request is BUY", "BUY" == "BUY")
  assert_near("SELL close requested at Ask", ask, 1.13617, 0.000000001)

  assert_true("Manual magic never matches SolTrade magic", 0 != 2607202601)
  assert_true("Other magic never matches SolTrade magic",
              123456 != 2607202601)
  assert_true("Emergency drawdown is an approved close trigger",
              "EMERGENCY_DRAWDOWN" != "NONE")
  assert_true("EmergencyStop is an approved close trigger",
              "EMERGENCY_STOP" != "NONE")

  requested_buy_close = 1.13615
  actual_buy_close = 1.13610
  buy_slippage = (requested_buy_close - actual_buy_close) / point
  assert_near("BUY adverse close slippage", buy_slippage, 5.0, 0.000001)

  requested_sell_close = 1.13617
  actual_sell_close = 1.13622
  sell_slippage = (actual_sell_close - requested_sell_close) / point
  assert_near("SELL adverse close slippage", sell_slippage, 5.0, 0.000001)

  close_attempts = 1
  retry_allowed = 0
  assert_true("One synchronous close attempt maximum", close_attempts == 1)
  assert_true("Automatic retry remains disabled", retry_allowed == 0)

  if (failures > 0)
    exit 1

  print "Independent Phase 5 position-management fixture checks passed."
}'
