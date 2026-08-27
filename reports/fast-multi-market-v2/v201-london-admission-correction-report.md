# SolTrade Fast Multi V2.201 London admission correction

Date: 2026-08-27  
Authorized runtime: `7404213 / FPMarketsSC-Demo` only  
Verdict: **C — V2.200 had an admission implementation defect**

## Root cause

V2.200 treated net distance to the nearest completed M5/M15/H1 opposing swing as if it were the maximum achievable reward, then required that value to be at least 1.25R. That is inconsistent with the strategy's no-fixed-TP Runner Mode: the first structural obstacle is initial clean room, not a final reward ceiling.

The structural stop, costs, score, spread, conflict, extension, drift, persistence, churn, portfolio, account, and runner gates were not the source of the one confirmed executable false rejection. The correction therefore changes only the semantic clean-room boundary from 1.25R to 1.20R and renames the rejection reason. It does not remove the room gate.

## Pre-deployment evidence

Frozen snapshot: 2026-08-27 16:08:00 UTC.

- Total evaluations: 164,084
- Score-qualified: 1,466
- Live eligible: 0
- Actual trades/order attempts: 0
- Reward/room rejects: 1,171
- Reward/room rejects with an actual opposing structure: 1,032
- Wide-stop-only reward/room rejects with no opposing structure: 139
- Spread rejects: 87
- M5/M15 conflict rejects: 0
- Extension/exhaustion rejects: 26
- Signal-drift rejects: 0
- Current V2.200 admission rate: 0 / 1,466 = 0.0000%

The frozen machine-readable snapshot is `shadow-admission-20260827/pre-v201-deployment.json`.

## Deduplicated threshold sensitivity

The outcome rates use complete 60-minute, executable-price research windows and one first-admissible observation per setup episode. Net/gross expectancy are 60-minute proxies capped at -1R after a theoretical stop; they do not pretend to reconstruct every production Runner Mode stop update.

| Initial clean room | Admitted observations | Episodes | >=0.5R | >=1R | >=1.5R | >=2R | Stop hit | Gross expectancy proxy | Median cost R |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1.00R | 35 | 5 | 40.0% | 40.0% | 0.0% | 0.0% | 40.0% | -0.348R | 0.0226R |
| 1.10R | 19 | 3 | 33.3% | 33.3% | 0.0% | 0.0% | 33.3% | -0.303R | 0.0164R |
| 1.15R | 8 | 2 | 50.0% | 50.0% | 0.0% | 0.0% | 0.0% | +0.083R | 0.0168R |
| **1.20R** | **1** | **1** | **100.0%** | **100.0%** | **0.0%** | **0.0%** | **0.0%** | **+0.102R** | **0.0226R** |
| 1.25R | 0 | 0 | NA | NA | NA | NA | NA | NA | NA |
| 1.35R | 0 | 0 | NA | NA | NA | NA | NA | NA | NA |
| 1.50R | 0 | 0 | NA | NA | NA | NA | NA | NA | NA |

The lower 1.00R and 1.10R alternatives were rejected because they admitted losing episodes and had negative expectancy proxies. The 1.20R correction is deliberately narrow: corrected admission is 1 / 1,466 = 0.0682%, not a broad release of marginal candidates.

## Confirmed false rejection

Exactly one observation changes from `REJECT -> ACCEPT` on the same immutable data:

- Timestamp: 2026-08-27 11:20:40 SAST
- Symbol/direction: USTEC / BUY (`US100` broker symbol)
- Raw directional score: 79.6752
- Absolute admission score: 64.5080, above 60
- Entry candidate: 29540.70
- Structural stop: 29508.93
- Stop distance: 31.76875, exactly the preserved 1.15 M5-ATR volatility floor
- Selected invalidation: M5 at 29523.35; M15 invalidation was 29457.35
- Opposing obstacle: 39.15 points ahead
- Expected cost: 0.72 points
- Net initial clean room: 1.2097R
- Spread/M5 ATR: 2.1719%; median-spread ratio 1.00
- M5/M15 confirmed: yes/yes
- Persistence: 4 scans / 30 seconds
- Signal drift: -0.0905 ATR; confirmation consumption 0
- Extension: not late or chased
- Old result: `OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS`
- Corrected result: eligible at the 1.20R clean-room boundary
- Forward executable result: +0.761R at 5m, +1.185R at 15m, +1.459R at 30m/60m, -0.046R MAE, no theoretical stop

This is the direct evidence that the nearest opposing structure was an obstacle, not a final take-profit ceiling.

## False-rejection and stop diagnosis

- London wide-stop-only group: 3 episodes; median MFE +0.025R, median MAE -0.912R, 0 reached +0.5R, 1 hit -1R. Confirmed executable false rejects: 0/3.
- London opposing-structure group: 12 episodes; median MFE +0.309R, median MAE -0.947R, 5 reached +0.5R, 4 reached +1R, 1 reached +1.5R, 1 reached +2R, and 5 hit -1R.
- Only one of those 12 opposing-structure episodes also passed every other production gate at the proposed boundary. Confirmed false-rejection rate is therefore 1/12 = 8.33% within opposing-structure episodes, 1/15 = 6.67% across London reward/room episodes, and 1/28 = 3.57% across all deduplicated London score-qualified episodes.

The observed wide-stop-only group did not support narrowing or changing stops. The confirmed USTEC false rejection used the normal 1.15-ATR volatility floor, not an old/deep stop. Stop direction, price units, spread/broker buffers, and cross-asset scaling remain unchanged. V2.201 adds the missing stop-anchor timeframe/server timestamp/age and buffer/floor telemetry so future stop claims are directly auditable.

## Exact changes

- `MinRewardRisk`: 1.25 -> 1.20, now explicitly documented as initial clean room to the first obstacle rather than final reward.
- Rejection reason: `OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS` -> `INITIAL_CLEAN_ROOM_TOO_SMALL_AFTER_COSTS`.
- Added behavior-neutral structure telemetry for stop anchor price/timeframe/server timestamp/age, stop distance in M5/M15 ATR, expansion/volatility/broker floors, opposing price/timeframe/server timestamp/age/reactions, separated spread/commission/slippage costs, tick values, proposed volume/risk/cost USD, M5/M15 trend, volatility, efficiency, regime, and behavior.
- Stop selection, position sizing, 0.25% risk, 1.50% portfolio risk, six-position/two-correlation limits, real-account guards, persistence, churn, spread, conflict, extension, drift, runner, monotonic SL, and reconciliation behavior are unchanged.

## Verification and deployment

- Python: 100 tests passed.
- Shell safety/regression suites: 18/18 passed.
- MetaEditor: 0 errors, 0 warnings; X64 Regular.
- Compile elapsed: 4,847 ms.
- Implementation Git commit: `4f7e5465ec6259e5f3689e7b88d293983e4663f2`.
- Source SHA-256: `c2530ad8e3429c05d4d03e5643f609786ada0bc4a8ecdd4f8216ab9cc00abc61`.
- EX5 SHA-256: `c19de2538d99cbbd5abe614129991f05e0896064271eb13833f7ed75e928aa9f`.
- Preset SHA-256: `b6411be64672842e6c126dd310c2fb3f4941067f39f5716b8a2dfdac8f918c45`.
- Release bundle: `/home/tibule12/.wine-fpmarkets/drive_c/soltrade-v201-release-kVxvRe`.
- Recoverable V2.200 backup: `/home/tibule12/.wine-fpmarkets/drive_c/soltrade-v200-pre-v201-backup-u7Qdxr`.

## Connected post-deployment state

Snapshot: 2026-08-27 16:13:00 UTC / 18:13:00 SAST.

- Account: 7404213 / FPMarketsSC-Demo
- Demo mode / real accounts blocked: yes / yes
- Scanner / connected: active / yes
- Markets: 19/19 telemetry rows; all 19 completed recovery history warm-up
- Entry permission / autonomous entry: ENABLED / true
- Positions / orders: 0 / 0
- Portfolio risk: 0.0000%
- Current scanner result: no eligible setup; no trade was forced
- Watchdog timer: active; latest checks successful
- Service: active/running since 18:10:25 SAST; zero post-deployment service restarts
- V6 telemetry: 19/19 proposed-volume diagnostics pass; timestamps are labeled as broker-server time and all anchor ages are non-negative
- Deployed source, EX5, and preset hashes match the sealed release artifacts
- Worktree: no uncommitted tracked changes; only four rolling shadow outputs (`latest.json`, `latest.md`, `post-decision-outcomes.csv`, and `shadow-candidates.csv`) remain intentionally untracked and continue to refresh

Final status: `SOLTRADE_FAST_MULTI_V201_CORRECTED_AUTONOMOUS_FP_DEMO_ACTIVE`.
