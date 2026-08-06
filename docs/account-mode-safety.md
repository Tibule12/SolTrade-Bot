# Account-Mode Safety Design

## Authoritative detection

At startup the EA determines mode in this order:

1. `MQL_TESTER` true → `BACKTEST`;
2. `ACCOUNT_TRADE_MODE_DEMO` → `DEMO`;
3. `ACCOUNT_TRADE_MODE_REAL` → `LIVE`;
4. anything else → `UNKNOWN`.

Configuration never re-labels the detected account. The actual mode is shown on
the chart and included in every journal row.

## Phase 6 safety invariant

The approved Phase 5 gateways remain available only in Strategy Tester and an
explicitly enabled, exactly approved demo account. Phase 6 research additionally
requires all three tester flags, the exact `BACKTEST` expectation, reviewed
metadata/hash inputs, and an in-window tester time. It cannot submit any request
to a real account. It never modifies stops or manages unrelated positions.

## Phase 5 automation-permission matrix

| Detected mode | Required gates | Result |
|---|---|---|
| Backtest | Phase 6 research, entry, and management flags all enabled; exact metadata/hash; registered time; MT5 trade permissions | Eligible |
| Demo | Expected mode matches; relevant capability enabled; exact approved login; MT5 trade permissions | Eligible |
| Live | None can approve it in Phase 5 | `REAL EXECUTION LOCKED` |
| Unknown | None can approve it | Fail closed |

All connected-demo gates must be true simultaneously:

```text
the relevant EnableDemoExecution or EnablePositionManagement flag == true
ApprovedDemoAccount == detected account login
ExpectedEnvironment is AUTO_DETECT or DEMO
terminal/program/account/Expert trading permissions == true
```

`AllowLiveTrading` must remain false and configuration validation rejects true.
A chart Algo Trading toggle or broker permission can deny demo/test trading but
can never bypass the account-mode gate.

`EmergencyStop=true` always blocks entries. If an owned SolTrade position
exists and position management is explicitly enabled, it is also an approved
emergency close trigger.

## Identity and logging

The account login is used in memory for exact approval comparison. Logs contain a
stable pseudonymous account token derived from login, server, and broker; they do
not contain the raw login or credentials. The token prevents casual disclosure
but is not represented as a cryptographic identity proof.

## Visible states

- `TEST EXECUTION READY - PHASE 5`: eligible Strategy Tester run.
- `APPROVED DEMO POSITION MANAGEMENT READY - PHASE 5`: exact demo-management
  gates pass and no position is open.
- `DEMO AUTOMATION DISABLED`: both connected-demo capabilities are off.
- `DEMO ACCOUNT NOT APPROVED`: demo login does not match.
- `REAL EXECUTION LOCKED`: every real account in Phase 5.
- `EMERGENCY STOPPED`: emergency input is active.
- `SOLTRADE POSITION MONITORED - MANAGEMENT DISABLED`: an owned position is
  visible, but no close request can be prepared.
- `POSITION CLOSE ATTEMPT CONSUMED - NO RETRY`: the persistent one-attempt
  claim prevents another submission.
- `MARKET DATA INVALID`: quote/history/connectivity validation failed.
- `WAITING`: no H1 candle has completed since the EA attached.

The panel includes the exact latest refusal/validation reason.

## Pre-enable evidence

The deterministic Phase 5 suite and unarmed connected-demo preflight must pass
before `EnablePositionManagement` is changed from false. See
`tests/phase5-connected-demo-checklist.md`.
