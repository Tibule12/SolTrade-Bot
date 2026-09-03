# SolTrade V2.202 post-fix cross-account audit — 2026-09-03

## Scope

- Live read-only capture: 2026-09-03 17:32:49 UTC
- Post-fix scan cutoff: 2026-09-03 17:15:20 UTC
- Accounts: FP 7404213, FXIFY 7196820, FXIFY 7198096
- No strategy changes and no test orders

## Runtime state

| Account | Process count | Connected | Scanner | Autonomous entry | Ownership | Positions | Orders | Equity |
|---|---:|---|---|---|---|---:|---:|---:|
| FP 7404213 | 1 | YES | LIVE | ENABLED | GRANTED to `vps-fp-prod` | 0 | 0 | 99,038.20 |
| FXIFY 7196820 | 1 | YES | LIVE | ENABLED | GRANTED to `vps-fxify-10k-prod` | 0 | 0 | 10,045.17 |
| FXIFY 7198096 | 1 | YES | LIVE | ENABLED | GRANTED to `vps-fxify-100k-prod` | 0 | 0 | 100,632.26 |

The watchdog was `Ready` with last result `0`. All three ownership tasks were running and every lease was current at capture time. All 19 intended markets were available and resolved on every captured scan for every account. FXIFY 7198096 briefly logged no verified STOXX50 alias during cold start, then resolved `STOXX50.r` before the audited scans; there were no unavailable STOXX50 scan rows.

## Post-fix admission audit

| Account | Window end UTC | Candidate rows | Scans | Eligible | Order attempts | Persistence started |
|---|---|---:|---:|---:|---:|---:|
| FP 7404213 | 17:32:30 | 1,520 | 80 | 0 | 0 | 0 |
| FXIFY 7196820 | 17:32:40 | 1,995 | 105 | 0 | 0 | 0 |
| FXIFY 7198096 | 17:32:40 | 1,995 | 105 | 0 | 0 | 0 |

No row combined directional-core qualification with valid reward room. Consequently, no complete admission state existed and persistence correctly did not start.

Primary rejection counts:

| Gate | FP | FXIFY 10k | FXIFY 100k |
|---|---:|---:|---:|
| High spread relative to M5 ATR | 915 (60.2%) | 1,529 (76.6%) | 1,531 (76.7%) |
| Stale tick | 123 | 172 | 170 |
| M5/M15 directional conflict | 70 | 118 | 118 |
| Range chop without structural trigger | 162 | 74 | 75 |
| Movement weak relative to spread | 59 | 65 | 64 |
| Expected net move insufficient after costs | 73 | 19 | 19 |

The bounded opposite-thesis fix is no longer vetoing USTEC: zero post-fix rows were rejected for `PREVIOUS_OPPOSITE_THESIS_NOT_EXPLICITLY_INVALIDATED`. Current USTEC rows were rejected for current-market reasons (range chop, M5/M15 conflict, or unconfirmed M5 direction), not stale historical state.

## Recorded 2026-09-03 closed-trade outcomes

| Account | Trade | Net result |
|---|---|---:|
| FP 7404213 | USDJPY SELL | +582.25 |
| FP 7404213 | USDJPY SELL | +114.45 |
| FXIFY 7196820 | USDJPY SELL | +50.11 |
| FXIFY 7196820 | US500 BUY | +2.56 |
| FXIFY 7198096 | USDJPY SELL | +536.93 |
| FXIFY 7198096 | US500 BUY | +28.16 |

No post-fix order was placed in the audited interval. No recorded closed trade on 2026-09-03 was a loss.

## Decision

The previously proven inactivity defect was corrected. The current no-trade interval is explained by live spread/cost, structural, and directional gates; the evidence does not show a second stale-state lock or a complete valid setup being rejected. Loosening the dominant spread/ATR gate from this short interval would be unsupported and would weaken an explicit safety control.

Regression verification after the audit: 138 deterministic tests passed; V2.202 static safety checks passed; account-ownership static checks passed.

Evidence:

- `ops/forexvps/remote-output/post-fix-cross-account-audit.zip`
- `ops/forexvps/remote-output/post-fix-cross-account-audit-bundle/manifest.json`
- commit `039beb5` (FP deployment), following `e0e9c7f` (FXIFY deployment)
