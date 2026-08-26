# SolTrade Fast Multi-Market V2.200 admission and deployment report

Date: 2026-08-26  
Authorized runtime: `7404213 / FPMarketsSC-Demo` only  
Release implementation commit: `f262b9039be1dddf705967a58d5261941c22bfe8`

## Admission defects found and corrected

1. `MaxSpreadAtrPercent` existed but was not an admission gate. V2.200 hard-rejects spread above 8% of completed-M5 ATR, in addition to the symbol-relative median-spread gate.
2. Remaining room used aggregate M15/H1 extremes and converted a non-positive result into synthetic room. V2.200 selects the nearest completed local swing ahead of price across M5/M15/H1; an ATR projection is used only when no opposing swing exists in the retained horizons.
3. The previous late-entry extension was distance from the invalidation swing, not movement already consumed by the current impulse. V2.200 separately measures six-bar M5 impulse extension, breakout extension beyond the broken level, signal drift, and opportunity consumed during confirmation.
4. The previous raw directional score had an absolute floor, but did not expose an independent economic-quality score. V2.200 adds directional, structure, timing, and remaining-room components, then subtracts cost, extension, and conflict penalties. The final absolute threshold is 60; rank among 19 symbols never grants permission.
5. An aligned structural state or direction-specific trigger was not mandatory. V2.200 requires aligned HH/HL or LH/LL structure, aligned breakout, aligned failed-breakout reversal, or a clean aligned rejection/pullback. Direction-agnostic behaviour labels were removed.
6. Confirmation retained a reference price but did not record first-seen, stable, and admission timestamps or reject a confirmation delay that consumed too much room. V2.200 records all of them and rejects above 35% consumed opportunity or 0.60 ATR signal drift.
7. The discretionary `NewEntriesEnabled` pause could leave the healthy demo in management-only mode. It was removed from source and preset. Entry permission now follows the demo identity, market-data, risk, duplicate, and broker-reconciliation safety gates.
8. Confirmation globals could have inherited state created under the older admission policy. V2.200 uses a new persistence namespace, while preserving restart persistence within the corrected policy.

Runner code was not weakened. It retains no fixed TP, persistent `INITIAL_RISK` / `CONFIRMED_PROFIT` / `RUNNER` state, commission-aware monotonic MFE floors, structural breathing room, one-way stop ratchets, broker reconciliation, and restart recovery.

## Threshold validation

- Signal drift remains 0.60 completed-M5 ATR.
- General impulse extension remains 1.75 completed-M5 ATR, but now measures the current six-bar impulse instead of stop/invalidation distance.
- A breakout-specific maximum of 0.75 completed-M5 ATR prevents buying or selling far beyond the broken level.
- Confirmation may consume at most 35% of the opportunity measured as favourable confirmation movement divided by that movement plus current remaining room.
- ATR normalization tests prove identical extension behaviour for FX, metals, and indices despite different price scales.

## Preserved 25 August regression

The evidence-only classifier contains no embedded trade timestamp, symbol, or price and does not use MFE or realized outcome as an admission input. Full rows are in `admission-regression-20260825.md` and JSON.

- REJECT: trades 2, 5, 10, 11, and 12 — `SAME_SYMBOL_CHURN_COOLDOWN`.
- REJECT: trade 7 — `HIGH_SPREAD_RELATIVE_TO_M5_ATR` (17.08%).
- UNKNOWN: trades 1, 3, 4, 6, 8, 9, 13, and 14 — the old V3 audit did not retain the V2.200 absolute components, nearest opposing swing, impulse/breakout extension, or setup-specific confirmation timing.

The +2.069R XAUUSD, +2.761R US100, and +1.033R GER40 examples are UNKNOWN rather than rejected. Their future MFE was not used. Targeted early-continuation, failed-breakout, and clean-pullback fixtures remain admissible when every independent gate passes; the repair does not optimize for zero losses or zero trades.

## Verification

- Python deterministic tests: 94 passed.
- Repository shell suites: 18 of 18 passed. Legacy Phase 1–6 static tests were corrected to inspect their original `SolTradeBot` target instead of falsely treating newer independent EAs and research harnesses as part of the historical phase scope.
- Targeted admission coverage: agreement, hard conflict, early/late continuation, exhausted breakout, failed breakout, clean pullback, range/chop, opposing structure, high spread, cost rejection, insufficient room, ATR extension, signal drift, transient/stable signal, immediate retry, valid reset re-entry, and correlated-index exposure.
- Runner regression: passed, including NZDUSD commission-aware protected floor, no hard profit ceiling, BUY/SELL monotonic stops, structural invalidation, and the preserved +2R/+2.76R failure envelope.
- Risk regression: passed at 0.25% per trade, 1.50% portfolio risk, six positions, two strongly correlated positions, and smaller lots for wider stops.
- Restart/reconciliation: passed at deployment with epoch `1787320873`, zero duplicates, zero pending Fast Multi orders, and all owned stops/state recoverable.
- Real-account block: passed. Login `7196820`, login `2100139002`, any non-demo mode, and any login/server mismatch remain hard initialization failures.
- MetaEditor: `0 errors, 0 warnings`, X64 Regular.

## Release identity

- Source SHA-256: `c31a52642135441b8931e1e8e183801ea418eca81ef3a1a472c56618dce89581`
- EX5 SHA-256: `969ac80aef987d933b5a14943093a201b8e39043f4944c72bcfd03d8dcb97b86`
- Preset SHA-256: `5f99f0d6932df2a591e9d34a2a8cf06621b95859efb01c4375be7da6d2c737a4`
- Deployed source, EX5, and preset hashes match the release artifacts.

## Connected runtime verification

Snapshot UTC: `2026.08.26 16:09:30`

- Account: `7404213 / FPMarketsSC-Demo`
- Connected: YES
- Account mode: DEMO
- Markets: 19/19 available
- EA: RUNNING
- Scanner: ACTIVE
- Entry permission: ENABLED
- Autonomous entry: ENABLED
- Current decision: NO_TRADE on 19/19; no trade was forced
- Positions: 0
- Pending orders: 0
- Portfolio risk: 0.0000%
- Service: active/running since 2026-08-26 18:06:50 SAST
- Watchdog: HEALTHY (`Result=success`, `ExecMainStatus=0`, timer active/waiting)
- Real accounts: BLOCKED

Final verdict: `SOLTRADE_V2_ADMISSION_CORRECTED_AND_AUTONOMOUS_DEMO_ACTIVE`
