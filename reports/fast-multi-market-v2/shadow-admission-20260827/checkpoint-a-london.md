# Checkpoint A — London session

Generated: 2026-08-27T12:00:34.561355+00:00

`SHADOW_COUNTERFACTUAL_ONLY_NO_ORDER_PATH` / `POST_DECISION_RESEARCH_ONLY`

## Current verdict

**POSSIBLE_OVER_FILTERING**

MFE is diagnostic only. CONFIRMED_OVER_FILTERING requires manual structural-entry review and sufficient liquid-session evidence.

## Objective warning metrics

- SCORE_QUALIFIED_COUNT: 1349
- LIVE_ELIGIBLE_COUNT: 0
- LIVE_ADMISSION_RATE: 0.00%
- ACTUAL_ORDER_ATTEMPTS: 0
- TOP_REJECTING_GATE: OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS
- TOP_REJECTING_GATE_PERCENT: 78.43%
- MEDIAN_SCORE_OF_REJECTED: 62.8372
- MEDIAN_REMAINING_R: 0.3333
- MEDIAN_SPREAD_ATR: 2.7406
- SCORE_QUALIFIED_WITH_OPPOSING_STRUCTURE: 1149
- RR_REJECT_WITH_OPPOSING_STRUCTURE: 919
- RR_REJECT_WITHOUT_OPPOSING_STRUCTURE: 139

## Production runtime (read-only snapshot)

- Account: 7404213 / FPMarketsSC-Demo
- Demo / real blocked: true / true
- Entry permission: ENABLED
- Scanner / autonomous / connected: true / true / true
- Positions / orders: 0 / 0
- Production parameters changed: False

## Score-qualified rejection distribution

| Gate | Count |
|---|---:|
| OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS | 1058 |
| EXPECTED_NET_MOVE_INSUFFICIENT_AFTER_COSTS | 88 |
| HIGH_SPREAD_RELATIVE_TO_M5_ATR | 82 |
| STALE_TICK | 33 |
| MOVE_EXHAUSTED_OR_LATE_CHASE | 26 |
| NO_VALID_DIRECTIONAL_STRUCTURE_OR_TRIGGER | 19 |
| MOVEMENT_WEAK_RELATIVE_TO_SPREAD | 14 |
| RANGE_CHOP_WITHOUT_STRUCTURAL_TRIGGER | 13 |
| POST_RECOVERY_HISTORY_WARMUP | 6 |
| DIRECTIONAL_EVIDENCE_WEAK | 6 |
| ABNORMAL_SPREAD | 3 |
| SETUP_SPECIFIC_CONFIRMATION_PENDING | 1 |

## One-gate ablation

| Counterfactual | Eligible | Rejected | Unknown |
|---|---:|---:|---:|
| LIVE_ALL_GATES | 0 | 1349 | 0 |
| SHADOW_WITHOUT_SPREAD_ATR_GATE | 0 | 1349 | 0 |
| SHADOW_WITHOUT_OPPOSING_STRUCTURE_GATE | 159 | 1190 | 0 |
| SHADOW_WITHOUT_MIN_RR_GATE | 549 | 800 | 0 |
| SHADOW_WITHOUT_60_POINT_THRESHOLD | 0 | 1349 | 0 |
| SHADOW_WITHOUT_EXTENSION_GATE | 0 | 1349 | 0 |
| SHADOW_WITHOUT_SIGNAL_DRIFT_GATE | 0 | 1349 | 0 |
| SHADOW_WITHOUT_M5_M15_CONFLICT_GATE | 0 | 1349 | 0 |

## Parameter sensitivity (shadow only)

| Parameter | Value | Eligible | Rejected | Unknown |
|---|---:|---:|---:|---:|
| spread_atr | 6 | 0 | 1349 | 0 |
| spread_atr | 8 | 0 | 1349 | 0 |
| spread_atr | 10 | 0 | 1349 | 0 |
| spread_atr | 12 | 0 | 1349 | 0 |
| spread_atr | 15 | 0 | 1349 | 0 |
| absolute_score | 55 | 0 | 23059 | 0 |
| absolute_score | 60 | 0 | 23059 | 0 |
| absolute_score | 65 | 0 | 23059 | 0 |
| absolute_score | 70 | 0 | 23059 | 0 |
| impulse_extension | 1.5 | 0 | 1349 | 0 |
| impulse_extension | 1.75 | 0 | 1349 | 0 |
| impulse_extension | 2.0 | 0 | 1349 | 0 |
| impulse_extension | 2.25 | 0 | 1349 | 0 |
| breakout_extension | 0.6 | 0 | 1349 | 0 |
| breakout_extension | 0.75 | 0 | 1349 | 0 |
| breakout_extension | 0.9 | 0 | 1349 | 0 |
| breakout_extension | 1.0 | 0 | 1349 | 0 |
| signal_drift | 0.4 | 0 | 1349 | 0 |
| signal_drift | 0.6 | 0 | 1349 | 0 |
| signal_drift | 0.8 | 0 | 1349 | 0 |
| signal_drift | 1.0 | 0 | 1349 | 0 |
| min_reward_r | 1.0 | 35 | 1314 | 0 |
| min_reward_r | 1.1 | 19 | 1330 | 0 |
| min_reward_r | 1.25 | 0 | 1349 | 0 |
| min_reward_r | 1.5 | 0 | 1349 | 0 |

## Spread/ATR by session

| Session (SAST) | Evaluations | Score-qualified | Median % | P75 % | <=8% pass | High-spread rejects | Stale |
|---|---:|---:|---:|---:|---:|---:|---:|
| NEW_YORK_LATE | 40199 | 238 | 25.6881 | 52.093 | 20.24% | 21324 | 9177 |
| ASIA_OVERNIGHT | 61483 | 714 | 24.911 | 42.0601 | 15.34% | 42724 | 8609 |
| LONDON_OPEN | 13674 | 190 | 14.433 | 22.125025 | 22.20% | 9888 | 474 |
| LONDON_SESSION | 20570 | 207 | 14.7368 | 20.9476 | 25.27% | 14171 | 1178 |

## Spread/ATR by asset class

| Asset class | Evaluations | Median % | P75 % | <=8% pass | High-spread rejects |
|---|---:|---:|---:|---:|---:|
| METALS | 14325 | 8.0506 | 21.4468 | 47.40% | 6696 |
| JPY_FX | 28647 | 24.2021 | 34.6847 | 3.05% | 25576 |
| NON_JPY_FX | 57147 | 22.8571 | 36.6279 | 6.62% | 43135 |
| INDICES | 35807 | 11.9658 | 56.0 | 40.10% | 12700 |

## Post-decision outcomes (unique signal episodes, complete 60-minute windows)

A later MFE is not treated as proof that a rejected trade was executable or profitable.

| Initial rejecting gate | N | >=0.5R | >=1R | >=1.5R | >=2R | Failed before +0.5R |
|---|---:|---:|---:|---:|---:|---:|
| POST_RECOVERY_HISTORY_WARMUP | 2 | 1 | 0 | 0 | 0 | 0 |
| OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS | 25 | 14 | 7 | 5 | 3 | 2 |
| EXPECTED_NET_MOVE_INSUFFICIENT_AFTER_COSTS | 5 | 2 | 1 | 1 | 1 | 0 |
| NO_VALID_DIRECTIONAL_STRUCTURE_OR_TRIGGER | 2 | 1 | 1 | 1 | 0 | 1 |
| HIGH_SPREAD_RELATIVE_TO_M5_ATR | 9 | 0 | 0 | 0 | 0 | 4 |
| MOVEMENT_WEAK_RELATIVE_TO_SPREAD | 1 | 1 | 1 | 0 | 0 | 0 |

## Instrumentation limits

- V5 does not record the selected opposing swing timeframe or creation timestamp.
- V5 does not record tick value or a proposed volume for rejected candidates, so exact USD costs are unavailable.
- V5 records M5/M15 confirmation booleans but not the underlying signed trend values/context labels.
- Exact opposing level is inferable only when actual room, rather than the unopposed ATR cap, limits available_move.

The collector records these limits as missing evidence and does not fabricate swing ages, timeframes, or USD values.

## Implementation review

- opposing_direction: PASS: BUY selects completed swing highs strictly above entry; SELL selects completed swing lows strictly below entry.
- spread_atr_units: PASS: raw spread and completed-M5 ATR are both price distances; the ratio is dimensionless before percentage scaling.
- cost_subtraction: PASS: expected_net_move subtracts expected_cost_move once; reward_r divides that net move by stop distance. Cost also affects the independent quality score, which is calibration rather than duplicate arithmetic subtraction.
- cross_asset_normalization: PARTIAL: price-unit and point/tick reporting are internally consistent; exact rejected-candidate USD values need tick value and proposed volume instrumentation.
- structure_relevance: OPEN: V5 lacks selected swing timeframe and creation time, so micro-swing/staleness claims cannot yet be proved from the immutable feed.
