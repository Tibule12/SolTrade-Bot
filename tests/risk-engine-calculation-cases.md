# Phase 2 Explicit Risk Engine Calculations

These deterministic cases use the approved 0.25% risk, 1% daily loss, 2.5%
weekly loss, 5% emergency drawdown, and three-loss pause.

For lot calculations, the fixture uses EURUSD-like metadata:

```text
tick size             = 0.00001
loss tick value/lot   = $1.00
stop distance         = 0.00123 = 123 ticks
minimum volume        = 0.01 lots
maximum volume        = 100.00 lots
volume step           = 0.01 lots
```

These are deterministic calculation fixtures, not claims about a particular
broker's tick value. Runtime calculations read the broker's
`SYMBOL_TRADE_TICK_VALUE_LOSS`, tick size, and volume metadata.

## $500 account

| Case | Calculation | Expected |
|---|---|---:|
| Risk budget | `$500 × 0.25%` | `$1.25` |
| One-lot stop loss | `123 ticks × $1` | `$123.00` |
| Raw volume | `$1.25 / $123` | `0.0101626016` lots |
| Step rounding | floor to `0.01` | `0.01` lots |
| Normalised stop loss | `0.01 × $123` | `$1.23` |
| Daily threshold | `$500 × (1 − 1%)` | `$495.00` equity |
| Weekly threshold | `$500 × (1 − 2.5%)` | `$487.50` equity |
| Emergency threshold | `$500 × (1 − 5%)` | `$475.00` equity |
| Consecutive losses | third distinct net losing outcome | lock until next broker day |

The remaining `$0.02` risk capacity is deliberately unused because volume is
always rounded down. A zero or negative stop distance is rejected.

## $10,000 account

| Case | Calculation | Expected |
|---|---|---:|
| Risk budget | `$10,000 × 0.25%` | `$25.00` |
| One-lot stop loss | `123 ticks × $1` | `$123.00` |
| Raw volume | `$25 / $123` | `0.2032520325` lots |
| Step rounding | floor to `0.01` | `0.20` lots |
| Normalised stop loss | `0.20 × $123` | `$24.60` |
| Daily threshold | `$10,000 × (1 − 1%)` | `$9,900.00` equity |
| Weekly threshold | `$10,000 × (1 − 2.5%)` | `$9,750.00` equity |
| Emergency threshold | `$10,000 × (1 − 5%)` | `$9,500.00` equity |
| Consecutive losses | third distinct net losing outcome | lock until next broker day |

The remaining `$0.40` risk capacity is deliberately unused. The engine never
rounds `0.2032520325` up to `0.21`.

## Boundary and rejection cases

| Case | Expected |
|---|---|
| Stop distance `0` | Reject |
| Stop distance below `0` | Reject |
| Requested stop 10 points; broker minimum 15 | Reject |
| Requested stop exactly 15 points | Accept |
| Missing/zero tick size or loss tick value | Reject |
| Normalised volume below broker minimum | Reject rather than round up |
| Broker minimum `0.01`, step `0.03` | Round on `0.01 + n × 0.03`, never on an invalid zero-based grid |
| Open SolTrade position count `0` | Accept capacity check |
| Open SolTrade position count `1` | Reject a duplicate/second position |
| Open SolTrade position count below `0` | Reject unavailable/invalid count |
| Daily/weekly/emergency percentage exactly at limit | Lock at equality |
| Equity recovers after emergency trigger | Emergency lock remains latched |
| Duplicate closed-outcome identifier | Ignore without incrementing streak |
| Breakeven outcome | Preserve current streak |
| Positive outcome before lock | Reset streak |
| New broker day after three-loss pause | Clear pause and reset streak |

The executable MQL5 fixture is
`MQL5/Scripts/SolTradeRiskTests.mq5`. It also writes an isolated test state,
restores the daily baseline/lock into a second engine instance, verifies atomic
temporary-file replacement, injects a corrupt state fixture, confirms fail-closed
initialisation, and removes the test files afterward. The `$500` and `$10,000`
display labels are kept separate from their machine-safe `EQ500` and `EQ10000`
outcome IDs and persistence subdirectories.
