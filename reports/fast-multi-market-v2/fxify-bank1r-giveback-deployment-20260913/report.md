# FP Bank1R giveback manager — all three accounts active

**Status: `DEPLOYED_ALL_THREE_ACTIVE`.** The FP manager now runs autonomously on FP demo 7404213 and both FXIFY demo accounts. The verified forward baseline is **2026-09-13 07:23:58 UTC / 09:23:58 SAST**.

| Account | Server | Equity at baseline | Positions / orders | Runtime | PID |
|---|---|---:|---:|---|---:|
| FP 7404213 | FPMarketsSC-Demo | $99,579.64 | 0 / 0 | Connected, scanning, autonomous, ownership GRANTED | 2892 |
| FXIFY 7196820 — 10K | FXIFY-Server | $10,039.41 | 0 / 0 | Connected, scanning, autonomous, ownership GRANTED | 8008 |
| FXIFY 7198096 — 100K | FXIFY-Server | $100,321.36 | 0 / 0 | Connected, scanning, autonomous, ownership GRANTED | 6172 |

Each account has exactly one MT5 process. The total process count is three. The watchdog is enabled, Ready, and its last completed result is 0. All three ownership authorities are enabled and running; their independently renewed runtime leases are current.

[Independent all-account verification](verification.json) · [forward baseline](baseline.json) · [deployment receipt](deployment.json)

## Deployed policy

All three accounts report manager `ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK` with:

- 1.00% initial risk per accepted trade;
- 1.50% aggregate exposure cap;
- original structural broker stop retained;
- 50% of original volume banked once at +1.00R;
- remaining 50% managed as a structural runner;
- durable `PRE_BANK_GIVEBACK` recovery/damage-control state;
- unchanged entry logic, symbols, admission thresholds, sizing code, structural stop construction and account drawdown controls.

The FXIFY binaries are account-bound. Each has its own required login, magic number, FileCommon runtime folder, terminal-global state prefix and ownership instance. The source-port test normalizes those identity substitutions and proves the resulting source is otherwise byte-for-byte the deployed FP source.

## Verification before deployment

| Check | Result |
|---|---|
| FXIFY 10K production compile | 0 errors, 0 warnings |
| FXIFY 100K production compile | 0 errors, 0 warnings |
| Exact portability and account isolation | 2 passed |
| Giveback state/regression suite | 5 passed |
| Bank1R broker/restart/volume suite | 7 passed |
| Ownership static checks | Passed |
| Flat preflight | Both FXIFY accounts had 0 positions and 0 orders |
| Forced or test orders | None |

The deployment drained both FXIFY ownership leases, stopped only the two FXIFY terminals, installed the account-specific source and binary, changed their existing startup/preset settings from paused dry-run to active 1%, restarted their ownership authorities and terminals, and waited for fresh runtime confirmation. FP PID 2892 and both FP code hashes remained unchanged across the deployment.

## Exact live artifacts

| Target | Source SHA256 | Binary SHA256 |
|---|---|---|
| FP 7404213 | `4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e` | `fa2107a6088cf211d73eee646676cb3d61a6975b5b98eb47a548544c04199fea` |
| FXIFY 7196820 | `055855e84ad7fe392932edc1c878f6ff66288360d148575c8dbc5a9692f2c1c3` | `f1a527764b264b903ee54d4d9a890873bd7f0ceb38edca8b98f33df0f5715039` |
| FXIFY 7198096 | `b10d8a40f422cfba2dcb9c02b1b5b0d44dc9d669e4336d4c21601fbb17a483ef` | `63bbbfa3a0fd81180d93cad558e5c841b2a5608aac2c921cf26aca13e7aad1f8` |

The rollback snapshot is `C:\SolTrade\backups\fxify-bank1r-giveback-20260913-071809`. No rollback was needed. The release build commit is `9021bc3`; its PowerShell correction is `a3d2940`. [Release manifest](../../../ops/forexvps/releases/fxify-bank1r-giveback-20260913/manifest.json) · [test receipt](../../../ops/forexvps/releases/fxify-bank1r-giveback-20260913/tests.json) · [file hashes](files.json).
