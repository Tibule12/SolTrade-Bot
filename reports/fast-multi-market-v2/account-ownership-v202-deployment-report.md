# SolTrade V2.202 — FP 7404213 single-writer ownership remediation

Generated: 2026-08-29 (Africa/Johannesburg)

## Outcome

The duplicate-sender path is closed in the V2.202 binary and both deployment configurations. Every one of the six broker-mutating `CTrade` paths now requires a fresh, runtime-specific permit immediately before the broker call. The laptop preset is permanently ineligible and has no claim secret; the VPS preset is the only eligible identity and receives its secret during VPS installation.

No strategy scores, admission thresholds, position sizing, runner behavior, churn controls, or version number were changed.

## Root cause

The old architecture relied on process/service state: stopping the laptop terminal was expected to make the VPS the only sender. The laptop watchdog could restart that terminal, and there was no broker-account ownership primitive inside the EA immediately before an order request. That allowed the migration-time XAUUSD SELL to be opened by the laptop runtime.

## Changes

- Added a fail-closed lease client to `SolTradeFastMultiMarketV2.mq5` with account, instance, host, runtime nonce, lease ID, acquisition/renewal/expiry timestamps, and permit-state logging.
- Added a VPS SYSTEM authority using an account-scoped global mutex, atomic state/permit writes, a VPS-only 48-byte random secret, a 15-second bounded TTL, deterministic race arbitration, explicit release, and append-only JSONL audit events.
- Added ownership validation immediately before BUY, SELL, position modification, thesis close, unprotected-entry flatten, and legacy cleanup close.
- Made the VPS watchdog fail closed when the authority task is absent and start the authority before terminals.
- Made the laptop preset `OwnershipEligible=false` with an empty claim secret. A watchdog restart therefore cannot grant it order permission.
- Kept production on `2.202`; no `2.203` was created.

## Proof and verification

- MetaEditor: `0 errors / 0 warnings`.
- Compiled EX5 SHA-256: `27a7012643c2615c5e17a1596bb74b88cc048373ec1e91b3e3c8844651a23bdb`.
- Source SHA-256: `b7359b28f39a3fb01065a9600a1c9f5bd6d364cb5c0c9d1cc9d467d6e17f6072`.
- VPS deployment inspection: authority task `Running`, production binary/source hashes matched, ownership eligible, secret injected but not logged, version `2.202`.
- VPS live authority proof granted account `7404213` only to instance `vps-fp-prod` on host `fxut9756438`; audit recorded acquire, renew, and bounded `STALE_LEASE_EXPIRED` recovery at 15 seconds.
- Laptop live runtime proof while the VPS lease was held: scanner active, connected to `7404213`, `entry_permission=BLOCKED_NO_OWNERSHIP`, `ownership_permit=BLOCKED`, `autonomous_entry=false`. Restarting the laptop watchdog created a new runtime nonce and remained blocked. The laptop service and timer were then stopped and disabled.
- Deterministic ownership tests: 5/5 passed (laptop/watchdog denial, clean VPS restart, crash recovery, stale/wrong-secret denial, simultaneous race exactly-one winner).
- Existing strategy regression suite: 65/65 passed plus both static safety suites.

## Runtime status at handoff

- Laptop FP terminal: stopped; service inactive/disabled; watchdog timer disabled; order sending blocked by compiled code and preset even if manually restarted.
- VPS ownership authority: installed as SYSTEM and observed running.
- VPS FP terminal: V2.202 deployed. The Windows RDP user began immediately logging off during the final FP credential-entry step (`ERRINFO_LOGOFF_BY_USER`), so the actual EA-account authentication and production EA lease could not be re-observed after that disconnect. The authority remains fail-closed: no valid current permit means no order may be sent.
- FXIFY accounts: not modified or enabled during this remediation.

## Preserved incident evidence

The migration-time XAUUSD SELL evidence is preserved separately in `reports/incidents/fp-7404213-xauusd-duplicate-sender-20260828.md`: 0.15 lots, entry 4452.11, SL 4467.86, approximately -1R, NEWYORK_LATE, 1.66 M5 ATR extended, maximum favorable excursion +0.206R.
