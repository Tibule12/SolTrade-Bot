# SolTrade ForexVPS migration report — 2026-08-28

## Outcome

The ForexVPS host and three isolated MT5 runtimes are installed, deployed, and
running under a credentialed Windows Task Scheduler watchdog. The laptop FP
runtime was stopped, preventing duplicate order sending.

The migration cannot be accepted as a trading-runtime migration yet because no
broker account authenticated on the VPS:

- FP Markets account 7404213: the provisioning email contains only a masked
  password. Copying the laptop terminal's encrypted account cache did not make
  the credential portable to Windows.
- FXIFY account 7196820: the exact credential from its original FXIFY email was
  entered; `FXIFY-Server` returned `authorization failed (Invalid account)`.
- FXIFY account 7198096: the exact credential from its original FXIFY email was
  entered; `FXIFY-Server` returned `authorization failed (Invalid account)`.

No paid-account order path was enabled. The completion marker is intentionally
withheld until the broker access blockers are resolved and connectivity,
heartbeat, restart, and reboot acceptance tests can be completed.

## VPS

- Host OS: Microsoft Windows Server 2022 Standard, build 20348
- CPU: AMD EPYC 7713, 6 logical processors
- RAM: 8 GB
- Disk: 199.9 GB total, 178.41 GB free at probe time
- Time zone: UTC; South Africa operational timestamps are UTC+2
- Firewall: Domain, Private, and Public profiles enabled
- Defender: enabled; real-time protection reported disabled by the provider
- Runtime root: `C:\SolTrade`

## Deployed runtimes

| Runtime | Directory | Version | Magic | Permission | Verified EX5 SHA-256 |
|---|---|---:|---:|---|---|
| FP demo | `C:\SolTrade\MT5-FP-DEMO` | 2.202 | 2108202601 | enabled only after account guard succeeds | `ea21afe11bdff4b16de6d3fe09b62d251fd11ea868b4d5a979a5b6b0ef4a222b` |
| FXIFY 10K | `C:\SolTrade\MT5-FXIFY-10K` | 2.201 | 2108202610 | disabled/dry-run | `ed686d27edd652dcba604599d5365bb8758cc9dbf56a9b85659cbaec6e628b55` |
| FXIFY 100K | `C:\SolTrade\MT5-FXIFY-100K` | 2.201 | 2108202620 | disabled/dry-run | `8e1773adcda33e47af238d94c204a18bf1ee9783f1f4b09f8d628483efaa70eb` |

The final VPS verification proved three distinct terminal roots, three distinct
processes launched with `/portable` and instance-specific startup INI files,
three distinct magic namespaces, matching EX5 hashes, and correct presets:
V2.202 at 1.15R and both V2.201 ports at 1.20R with `DryRunOnly=true`.

## Source provenance

### V2.202 FP demo

- source: `a7e1e4e1887e46e03e397c037280e55732bd1ad69a043553151452e451d6d066`
- EX5: `ea21afe11bdff4b16de6d3fe09b62d251fd11ea868b4d5a979a5b6b0ef4a222b`
- preset: `3b530da19883d7737448f9229f2c1a655b5968ecbb66ae699c068f42da8d5448`

### Approved V2.201 base

- source: `c2530ad8e3429c05d4d03e5643f609786ada0bc4a8ecdd4f8216ab9cc00abc61`
- EX5: `c19de2538d99cbbd5abe614129991f05e0896064271eb13833f7ed75e928aa9f`
- preset: `b6411be64672842e6c126dd310c2fb3f4941067f39f5716b8a2dfdac8f918c45`

V2.201 required portability-only ports because its approved source was bound to
the FP demo login, server, magic, and shared persistence namespace. The ports
change only account/server guards and per-account runtime namespaces. No entry,
exit, sizing, threshold, or management behavior changed.

## Watchdog and cutover

- `SolTrade-Watchdog` is registered with two triggers (startup and recurring).
- It runs as `trader`, with Task Scheduler's encrypted password logon and
  highest privileges.
- A forced stop/start simulation launched all three terminals with their
  isolated startup configs.
- The laptop FP terminal process was stopped before attempted VPS activation.
- Therefore there is currently no duplicate FP order sender; there is also no
  authenticated VPS FP order sender.
- A full Windows reboot acceptance test was not performed because none of the
  broker sessions can authenticate; a reboot could not prove reconnect and
  autonomous recovery.

## Tests

- FXIFY V2.201 port generator: 4 passed, 0 failed
- Fast Multi V2 static safety suite: passed
- FXIFY 10K MetaEditor compile: 0 errors, 0 warnings
- FXIFY 100K MetaEditor compile: 0 errors, 0 warnings
- VPS artifact/hash and isolation verification: passed
- Watchdog forced restart: three instance-specific processes launched
- Broker connectivity: blocked as detailed above
- Scanner, live symbol mapping, balance/equity, portfolio risk, and heartbeat:
  not testable without authenticated broker sessions
- Reboot recovery: deferred until account authentication is restored

## Security

- No broker or VPS password was committed, logged, or stored in deployment
  source.
- Broker passwords were entered through protected GUI input only.
- Temporary encrypted MT5 account-cache transfer is git-ignored.
- FXIFY order sending remains disabled at both the terminal config and EA preset
  layers.

## Required external resolution

FP Markets must provide/reset the full MT5 demo trading password for 7404213.
FXIFY must confirm whether 7196820 and 7198096 remain active or issue current
replacement account credentials. After that, the remaining acceptance work is
login, live symbol/spec discovery, scanner/heartbeat validation, and one
controlled reboot test.

`SOLTRADE_FOREXVPS_RUNTIME_MIGRATION_BLOCKED_ACCOUNT_ACCESS`
