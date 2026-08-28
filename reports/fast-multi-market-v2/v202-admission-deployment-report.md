# SolTrade Fast Multi V2.202 admission correction and deployment

Date: 2026-08-28

Authorized runtime: FP Markets demo `7404213 / FPMarketsSC-Demo` only

Deployment verdict: **V2.202 active, autonomous entry enabled**

## Root cause of inactivity

The post-GER40 audit covered the live V5 decision stream through 2026-08-28 15:04:40 UTC. Across the complete frozen replay there were 275,533 evaluations and 2,353 score-qualified observations.

Since the protected GER40 winner exited at 2026-08-28 08:47:38 UTC, 355 score-qualified rejected observations were recorded:

- 275 `INITIAL_CLEAN_ROOM_TOO_SMALL_AFTER_COSTS`
- 42 `EXPECTED_NET_MOVE_INSUFFICIENT_AFTER_COSTS`
- 33 `HIGH_SPREAD_RELATIVE_TO_M5_ATR`
- 4 `ABNORMAL_SPREAD`
- 1 `STALE_TICK`

The completed 60-minute post-winner sample contained 12 independent episode anchors. No rejected episode reached +1R before its theoretical structural stop. Two reached +0.5R: USDCHF sell at +0.656R and GBPJPY buy at +0.564R. Both were correctly rejected by the unchanged spread/ATR gate (14.841% and 21.575% respectively), so neither justifies weakening spread protection. All three completed clean-room rejects hit their theoretical structural stop; all three completed expected-move rejects failed to reach +0.5R and two hit the stop.

The long zero-trade period was therefore primarily a lack of safe clean room after costs, followed by insufficient expected net movement and unsafe spread—not a dead scanner or disabled order path. The actionable over-filtering was confined to the 1.15R–1.20R initial-clean-room boundary. The old 1.20R boundary rejected the GER40 winner at 1.1959R ten seconds before it qualified at 1.2638R, and rejected a separate USTEC candidate at 1.1901R which subsequently avoided its structural stop, reached +0.385R with -0.251R MAE, and remained +0.054R at 60 minutes.

## Exact engineering changes

- Version `2.201` -> `2.202`.
- `MinRewardRisk` (initial clean room after costs to the first opposing obstacle): `1.20R` -> `1.15R`.
- The demo preset and frozen initialization-policy interlock were changed to the same `1.15R` boundary.
- The research replay was corrected so actual live-eligible observations and rejected observations use the same aligned post-decision outcome vector. The previous rejected-only vector could shift labels after the first live admission.
- Regression expectations were updated to test rejection at 1.149999R and acceptance at 1.15R.

No other EA admission, sizing, stop, execution, churn, or management logic changed. The following remain unchanged: 0.25% primary-setup risk; M5/M15 structural invalidation; ATR, expansion, spread, and broker stop floors; server-side SL confirmation; 8% spread/M5-ATR ceiling; 1.75 median-spread ratio; stale-tick rejection; M5/M15 conflict rejection; 3 scans and 30 seconds persistence; entry-drift, opportunity-consumption, impulse-extension, and breakout-extension gates; consumed-setup and 30-minute re-entry controls; correlation and portfolio caps; runner mode and monotonic profit-protection ratchet; demo-only and real-account interlocks.

## Before/after admission replay

Frozen executable-price replay population: 2,353 score-qualified observations.

| Initial clean-room boundary | Admitted observations | Observation rate | First-admissible episodes | Complete episodes | >=0.5R | >=1R | Structural stops |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1.20R | 5 | 0.2125% | 3 | 3 | 2 | 2 | 0 |
| 1.15R | 14 | 0.5950% | 4 | 4 | 2 | 2 | 0 |
| 1.10R (rejected alternative) | 26 | 1.1041% | 6 | 6 | 2 | 2 | 2 |

V2.202 increases qualifying observations 2.8x and independent first-admissible episodes 33.3% versus the controlled 1.20R replay. The next lower boundary, 1.10R, was explicitly rejected because it introduced two theoretical-stop losses.

Real rows changing from reject to accept include:

- `2026.08.28 07:57:30 UTC`, DE30/GER40 buy: 1.1959R clean room, directional score 97.6977, absolute score 74.9698, spread/M5 ATR 2.0%, no chase; +1.266R MFE before stop, -0.407R MAE, no stop. V2.201 accepted the same episode ten seconds later; V2.202 recognizes it earlier.
- `2026.08.26 22:42:00 UTC`, USTEC buy: 1.1901R clean room, directional score 102.0828, absolute score 76.9877, spread/M5 ATR 1.6783%, drift -0.0839 ATR; +0.385R MFE, -0.251R MAE, no stop, +0.054R terminal 60-minute result.

## Verification

- Python deterministic policy/replay tests: **100 passed, 0 failed**.
- Shell safety and regression suites: **18/18 passed**.
- MetaEditor X64 Regular: **0 errors, 0 warnings**, 4,900 ms.
- Source SHA-256: `a7e1e4e1887e46e03e397c037280e55732bd1ad69a043553151452e451d6d066`.
- EX5 SHA-256: `ea21afe11bdff4b16de6d3fe09b62d251fd11ea868b4d5a979a5b6b0ef4a222b`.
- Demo preset SHA-256: `3b530da19883d7737448f9229f2c1a655b5968ecbb66ae699c068f42da8d5448`.
- Sealed release: `/home/tibule12/.wine-fpmarkets/drive_c/soltrade-v202-release-4Xh6nI`.
- Recoverable V2.201 backup: `/home/tibule12/.wine-fpmarkets/drive_c/soltrade-v201-pre-v202-backup-T2oNsh`.

## Connected deployment state

V2.202 initialized at 2026-08-28 15:07:35 UTC / 17:07:35 SAST.

- Account/server: `7404213 / FPMarketsSC-Demo`.
- Demo mode / real accounts blocked: `true / true`.
- Entry permission / autonomous entry: `ENABLED / true`.
- Scanner / connection: `active / connected`.
- Positions / orders at deployment: `0 / 0`.
- Portfolio risk: `0.0000%`.
- Universe: 19/19 markets available; 19/19 post-restart history warmups completed.
- Service / watchdog timer: `active / active`; service restart count `0`.
- Deployed source, EX5, and both preset locations match the sealed release hashes.
- Neither FXIFY account was accessed, changed, started, stopped, or traded.

Final runtime status: `SOLTRADE_FAST_MULTI_V202_CORRECTED_AUTONOMOUS_FP_DEMO_ACTIVE`.
