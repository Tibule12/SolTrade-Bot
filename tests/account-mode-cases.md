# Account-Mode Cases

| ID | Setup | Expected result |
|---|---|---|
| AM-01 | Strategy Tester, expected mode AUTO | `TEST EXECUTION READY - PHASE 4` when MT5 permissions pass |
| AM-02 | Demo account, all defaults | `DEMO EXECUTION DISABLED`; monitoring continues; no orders |
| AM-03 | Real account, all defaults | `REAL EXECUTION LOCKED`; refusal journaled; no orders |
| AM-04 | Demo account, expected LIVE | Environment mismatch; fail closed |
| AM-05 | Real account, Algo Trading enabled | Still `REAL EXECUTION LOCKED`; permission button cannot bypass mode |
| AM-06 | `AllowLiveTrading=true` | Configuration rejected before normal initialisation |
| AM-07 | Demo enabled, approved login zero | Configuration rejected |
| AM-08 | Demo enabled, wrong approved login | `DEMO ACCOUNT NOT APPROVED`; raw login absent from logs |
| AM-09 | Demo enabled, exact approved login | Eligible only if all terminal/account permissions pass |
| AM-10 | Any account, emergency stop true | `EMERGENCY STOPPED`; no entry eligibility |
| AM-11 | Unknown account mode | `UNKNOWN`; fail closed |
| AM-12 | Approved demo but Algo Trading disabled | `TRADING PERMISSION DISABLED`; no broker call |
| AM-13 | Demo, position management default false | Owned position may be monitored; no close request |
| AM-14 | Demo, management enabled, wrong approved login | Close rejected with `POSITION_DEMO_ACCOUNT_NOT_APPROVED` |
| AM-15 | Demo, management enabled, exact approved login | Close is eligible only for exact SolTrade ownership and an approved exit/emergency trigger |
| AM-16 | Real account, management enabled and Algo Trading on | Still `REAL_ACCOUNT_POSITION_MANAGEMENT_FORBIDDEN`; no broker call |
| AM-17 | Manual EURUSD position with magic zero | Never adopted, modified, or closed |

For rejection cases, inspect the source/tester journal and confirm no broker
submission occurs. Phase 5 contains no stop/position modification path, and
automated closing remains disabled until the separate deterministic gate passes.
