#!/usr/bin/env bash
set -euo pipefail

awk '
function absolute(value) {
  return value < 0 ? -value : value
}

function assert_near(name, actual, expected, tolerance) {
  if (absolute(actual - expected) > tolerance) {
    printf "FAIL: %s actual=%.12f expected=%.12f\n", \
      name, actual, expected > "/dev/stderr"
    failures++
  } else {
    printf "PASS: %s actual=%.12f expected=%.12f\n", \
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
  ema_alpha = 2 / 201

  assert_near("flat EMA 200", 1.1000, 1.1000, 0.0000000001)
  assert_near("flat ATR 14", 0.0010, 0.0010, 0.0000000001)
  assert_near("flat two-ATR stop", 2 * 0.0010, 0.0020, 0.0000000001)

  buy_ema = 1.1000 + ema_alpha * 0.0010
  sell_ema = 1.1000 - ema_alpha * 0.0010
  assert_near("BUY-001 EMA", buy_ema, 1.100009950249, 0.0000000001)
  assert_near("SELL-001 EMA", sell_ema, 1.099990049751, 0.0000000001)
  assert_true("BUY-001 strict 20-bar breakout",
              1.1010 > 1.1005 && 1.1010 > buy_ema)
  assert_true("SELL-001 strict 20-bar breakout",
              1.0990 < 1.0995 && 1.0990 < sell_ema)
  assert_true("upper equality is not a breakout", !(1.1005 > 1.1005))
  assert_true("lower equality is not a breakout", !(1.0995 < 1.0995))

  filter_buy_ema = 1.2000
  filter_sell_ema = 1.0000
  for (fixture_step = 1; fixture_step <= 20; fixture_step++) {
    filter_buy_ema = ema_alpha * 1.1000 + \
      (1 - ema_alpha) * filter_buy_ema
    filter_sell_ema = ema_alpha * 1.1000 + \
      (1 - ema_alpha) * filter_sell_ema
  }
  filter_buy_ema = ema_alpha * 1.1010 + \
    (1 - ema_alpha) * filter_buy_ema
  filter_sell_ema = ema_alpha * 1.0990 + \
    (1 - ema_alpha) * filter_sell_ema
  assert_near("FILTER-BUY EMA", filter_buy_ema,
              1.181068232992, 0.0000000001)
  assert_near("FILTER-SELL EMA", filter_sell_ema,
              1.018931767008, 0.0000000001)
  assert_true("FILTER-BUY blocks breakout below EMA",
              1.1010 < filter_buy_ema)
  assert_true("FILTER-SELL blocks breakout above EMA",
              1.0990 > filter_sell_ema)

  assert_true("EXIT-LONG is inside D20 but below D10",
              1.0990 > 1.0980 && 1.0990 < 1.0995)
  assert_true("EXIT-SHORT is inside D20 but above D10",
              1.1010 < 1.1020 && 1.1010 > 1.1005)

  if (failures > 0) {
    printf "Strategy fixture verification failed: %d failure(s)\n", \
      failures > "/dev/stderr"
    exit 1
  }

  print "Independent Phase 3 strategy fixture checks passed."
}
'
