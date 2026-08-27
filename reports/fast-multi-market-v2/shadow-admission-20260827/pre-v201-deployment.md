# Fast Multi V2.200 shadow admission audit

Generated: 2026-08-27T16:08:43.062415+00:00

`SHADOW_COUNTERFACTUAL_ONLY_NO_ORDER_PATH` / `POST_DECISION_RESEARCH_ONLY`

## Current verdict

**POSSIBLE_OVER_FILTERING**

MFE is diagnostic only. CONFIRMED_OVER_FILTERING requires manual structural-entry review and sufficient liquid-session evidence.

## Objective warning metrics

- SCORE_QUALIFIED_COUNT: 1466
- LIVE_ELIGIBLE_COUNT: 0
- LIVE_ADMISSION_RATE: 0.00%
- ACTUAL_ORDER_ATTEMPTS: 0
- TOP_REJECTING_GATE: OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS
- TOP_REJECTING_GATE_PERCENT: 79.88%
- MEDIAN_SCORE_OF_REJECTED: 62.8568
- MEDIAN_REMAINING_R: 0.31284999999999996
- MEDIAN_SPREAD_ATR: 2.6945
- SCORE_QUALIFIED_WITH_OPPOSING_STRUCTURE: 1265
- RR_REJECT_WITH_OPPOSING_STRUCTURE: 1032
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
| OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS | 1171 |
| EXPECTED_NET_MOVE_INSUFFICIENT_AFTER_COSTS | 89 |
| HIGH_SPREAD_RELATIVE_TO_M5_ATR | 84 |
| STALE_TICK | 33 |
| MOVE_EXHAUSTED_OR_LATE_CHASE | 26 |
| NO_VALID_DIRECTIONAL_STRUCTURE_OR_TRIGGER | 19 |
| MOVEMENT_WEAK_RELATIVE_TO_SPREAD | 14 |
| RANGE_CHOP_WITHOUT_STRUCTURAL_TRIGGER | 13 |
| POST_RECOVERY_HISTORY_WARMUP | 6 |
| DIRECTIONAL_EVIDENCE_WEAK | 6 |
| ABNORMAL_SPREAD | 3 |
| SETUP_SPECIFIC_CONFIRMATION_PENDING | 2 |

## Requested current counters

- TOTAL_EVALUATIONS: 164084
- SCORE_QUALIFIED: 1466
- LIVE_ELIGIBLE: 0
- ACTUAL_TRADES: 0
- REWARD_ROOM_REJECTS: 1171
- OPPOSING_STRUCTURE_REJECTS: 1032
- WIDE_STOP_ONLY_REJECTS: 139
- SPREAD_REJECTS: 87
- M5_M15_CONFLICT_REJECTS: 0
- EXTENSION_REJECTS: 26
- DRIFT_REJECTS: 0

## One-gate ablation

| Counterfactual | Eligible | Rejected | Unknown |
|---|---:|---:|---:|
| LIVE_ALL_GATES | 0 | 1466 | 0 |
| SHADOW_WITHOUT_SPREAD_ATR_GATE | 0 | 1466 | 0 |
| SHADOW_WITHOUT_OPPOSING_STRUCTURE_GATE | 168 | 1298 | 0 |
| SHADOW_WITHOUT_MIN_RR_GATE | 588 | 878 | 0 |
| SHADOW_WITHOUT_60_POINT_THRESHOLD | 0 | 1466 | 0 |
| SHADOW_WITHOUT_EXTENSION_GATE | 0 | 1466 | 0 |
| SHADOW_WITHOUT_SIGNAL_DRIFT_GATE | 0 | 1466 | 0 |
| SHADOW_WITHOUT_M5_M15_CONFLICT_GATE | 0 | 1466 | 0 |

## Parameter sensitivity (shadow only)

| Parameter | Value | Eligible | Rejected | Unknown |
|---|---:|---:|---:|---:|
| spread_atr | 6 | 0 | 1466 | 0 |
| spread_atr | 8 | 0 | 1466 | 0 |
| spread_atr | 10 | 0 | 1466 | 0 |
| spread_atr | 12 | 0 | 1466 | 0 |
| spread_atr | 15 | 0 | 1466 | 0 |
| absolute_score | 55 | 0 | 27943 | 0 |
| absolute_score | 60 | 0 | 27943 | 0 |
| absolute_score | 65 | 0 | 27943 | 0 |
| absolute_score | 70 | 0 | 27943 | 0 |
| impulse_extension | 1.5 | 0 | 1466 | 0 |
| impulse_extension | 1.75 | 0 | 1466 | 0 |
| impulse_extension | 2.0 | 0 | 1466 | 0 |
| impulse_extension | 2.25 | 0 | 1466 | 0 |
| breakout_extension | 0.6 | 0 | 1466 | 0 |
| breakout_extension | 0.75 | 0 | 1466 | 0 |
| breakout_extension | 0.9 | 0 | 1466 | 0 |
| breakout_extension | 1.0 | 0 | 1466 | 0 |
| signal_drift | 0.4 | 0 | 1466 | 0 |
| signal_drift | 0.6 | 0 | 1466 | 0 |
| signal_drift | 0.8 | 0 | 1466 | 0 |
| signal_drift | 1.0 | 0 | 1466 | 0 |
| min_reward_r | 1.0 | 35 | 1431 | 0 |
| min_reward_r | 1.1 | 19 | 1447 | 0 |
| min_reward_r | 1.15 | 8 | 1458 | 0 |
| min_reward_r | 1.2 | 1 | 1465 | 0 |
| min_reward_r | 1.25 | 0 | 1466 | 0 |
| min_reward_r | 1.35 | 0 | 1466 | 0 |
| min_reward_r | 1.5 | 0 | 1466 | 0 |

## Deduplicated reward-room threshold outcomes

The expectancy columns are 60-minute research proxies, capped at -1R after a theoretical stop; they are not a reconstruction of the production runner.

| Min initial room | Observations | Episodes | Complete | >=0.5R | >=1R | >=1.5R | >=2R | Stop hit | Net expectancy | Gross expectancy | Cost R | False reject |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1.0 | 35 | 5 | 5 | 40.00% | 40.00% | 0.00% | 0.00% | 40.00% | -0.3684520875206503 | -0.3477097756610968 | 0.02257849555093881 | 40.00% |
| 1.1 | 19 | 3 | 3 | 33.33% | 33.33% | 0.00% | 0.00% | 33.33% | -0.31968326458307567 | -0.30329398780891753 | 0.016427774020328207 | 33.33% |
| 1.15 | 8 | 2 | 2 | 50.00% | 50.00% | 0.00% | 0.00% | 0.00% | 0.0665724941108365 | 0.08334910701035161 | 0.01677661289951511 | 50.00% |
| 1.2 | 1 | 1 | 1 | 100.00% | 100.00% | 0.00% | 0.00% | 0.00% | 0.07933832464420264 | 0.10191682019514145 | 0.02257849555093881 | 100.00% |
| 1.25 | 0 | 0 | 0 | NA | NA | NA | NA | NA | None | None | None | NA |
| 1.35 | 0 | 0 | 0 | NA | NA | NA | NA | NA | None | None | None | NA |
| 1.5 | 0 | 0 | 0 | NA | NA | NA | NA | NA | None | None | None | NA |

## London rejected-episode outcomes

| Group | Episodes | Complete | Median MFE R | Median MAE R | >=0.5R | >=1R | >=1.5R | >=2R | Stop hit |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| WIDE_STOP_1_25R_REJECTS | 3 | 3 | 0.025134186483049752 | -0.9123382598849942 | 0 | 0 | 0 | 0 | 1 |
| OPPOSING_STRUCTURE_REJECTS | 12 | 12 | 0.309051961165539 | -0.9471526607752776 | 5 | 4 | 1 | 1 | 5 |

## Spread/ATR by session

| Session (SAST) | Evaluations | Score-qualified | Median % | P75 % | <=8% pass | High-spread rejects | Stale |
|---|---:|---:|---:|---:|---:|---:|---:|
| NEW_YORK_LATE | 41054 | 260 | 25.2252 | 51.2195 | 20.41% | 21871 | 9227 |
| ASIA_OVERNIGHT | 61483 | 714 | 24.911 | 42.0601 | 15.34% | 42724 | 8609 |
| LONDON_OPEN | 13674 | 190 | 14.433 | 22.125025 | 22.20% | 9888 | 474 |
| LONDON_SESSION | 23933 | 214 | 14.7368 | 20.9476 | 25.94% | 16363 | 1347 |
| NEW_YORK_OPEN_OVERLAP | 13680 | 83 | 11.0526 | 16.4983 | 36.54% | 8264 | 398 |
| LONDON_NEW_YORK_OVERLAP | 10260 | 5 | 11.2 | 16.4127 | 34.74% | 6322 | 410 |

## Spread/ATR by asset class

| Asset class | Evaluations | Median % | P75 % | <=8% pass | High-spread rejects |
|---|---:|---:|---:|---:|---:|
| METALS | 17291 | 8.0506 | 19.9147 | 48.89% | 7995 |
| JPY_FX | 34575 | 21.9731 | 31.9218 | 4.61% | 30763 |
| NON_JPY_FX | 69003 | 20.0409 | 33.2613 | 9.81% | 51812 |
| INDICES | 43215 | 10.3321 | 46.6667 | 43.51% | 14862 |

## Post-decision outcomes (unique signal episodes, complete 60-minute windows)

A later MFE is not treated as proof that a rejected trade was executable or profitable.

| Initial rejecting gate | N | >=0.5R | >=1R | >=1.5R | >=2R | Failed before +0.5R |
|---|---:|---:|---:|---:|---:|---:|
| POST_RECOVERY_HISTORY_WARMUP | 2 | 1 | 0 | 0 | 0 | 0 |
| OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS | 32 | 16 | 9 | 5 | 3 | 6 |
| EXPECTED_NET_MOVE_INSUFFICIENT_AFTER_COSTS | 6 | 3 | 2 | 2 | 2 | 0 |
| NO_VALID_DIRECTIONAL_STRUCTURE_OR_TRIGGER | 2 | 1 | 1 | 1 | 0 | 1 |
| HIGH_SPREAD_RELATIVE_TO_M5_ATR | 10 | 0 | 0 | 0 | 0 | 4 |
| MOVEMENT_WEAK_RELATIVE_TO_SPREAD | 1 | 1 | 1 | 0 | 0 | 0 |
| SETUP_SPECIFIC_CONFIRMATION_PENDING | 1 | 1 | 1 | 1 | 0 | 0 |

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
